package.path = "./tdd-bot/lua/?.lua;./tdd-bot/lua/?/init.lua;" .. package.path

local state = {
  mapped = {},
  notify_calls = {},
  commands = {},
  run_calls = {},
  job_calls = {},
  qflist = {},
  copilot_exists = true,
  lines_by_buf = {},
  -- mtime per path: bumped to simulate copilot changing a file
  mtimes = {},
  open_bufs = {},
  -- simulated buffer content per bufnr, used as the "before" snapshot for diffs
  buf_lines = {},
  -- simulated on-disk file content per path, returned by vim.fn.readfile
  file_contents = {},
}

local real = {
  notify = vim.notify,
  defer_fn = vim.defer_fn,
  cmd = vim.cmd,
  keymap_set = vim.keymap.set,
  nvim_buf_get_name = vim.api.nvim_buf_get_name,
  nvim_get_current_buf = vim.api.nvim_get_current_buf,
  nvim_buf_set_lines = vim.api.nvim_buf_set_lines,
  nvim_list_bufs = vim.api.nvim_list_bufs,
  nvim_buf_is_loaded = vim.api.nvim_buf_is_loaded,
  nvim_buf_get_lines = vim.api.nvim_buf_get_lines,
  readfile = vim.fn.readfile,
  writefile = vim.fn.writefile,
  executable = vim.fn.executable,
  fnamemodify = vim.fn.fnamemodify,
  getqflist = vim.fn.getqflist,
  jobstart = vim.fn.jobstart,
  uv_now = vim.uv and vim.uv.now or nil,
  uv_fs_stat = vim.uv and vim.uv.fs_stat or nil,
}

local fake_now = 0
local current_buf = 1

vim.notify = function(msg, level, opts)
  table.insert(state.notify_calls, { msg = msg, level = level, opts = opts or {} })
end

vim.defer_fn = function(fn)
  fn()
end

vim.cmd = function(cmd)
  table.insert(state.commands, cmd)
end

vim.keymap.set = function(mode, lhs, rhs, opts)
  table.insert(state.mapped, { mode = mode, lhs = lhs, rhs = rhs, opts = opts or {} })
end

vim.api.nvim_buf_get_name = function(buf)
  if buf == 0 or buf == current_buf then
    return "/tmp/sample_test.dart"
  end
  return state.open_bufs[buf] or ""
end

vim.api.nvim_get_current_buf = function()
  return current_buf
end

vim.api.nvim_buf_set_lines = function(buf, _, _, _, lines)
  state.lines_by_buf[buf] = {}
  for _, line in ipairs(lines) do
    state.lines_by_buf[buf][#state.lines_by_buf[buf] + 1] = line
  end
end

vim.api.nvim_list_bufs = function()
  local bufs = { current_buf }
  for buf, _ in pairs(state.open_bufs) do
    bufs[#bufs + 1] = buf
  end
  return bufs
end

vim.api.nvim_buf_is_loaded = function(_)
  return true
end

vim.api.nvim_buf_get_lines = function(bufnr, _, _, _)
  return state.buf_lines[bufnr] or {}
end

vim.fn.readfile = function(path)
  return state.file_contents[path] or {}
end

vim.fn.writefile = function(lines, path)
  state.file_contents[path] = {}
  for _, line in ipairs(lines) do
    state.file_contents[path][#state.file_contents[path] + 1] = line
  end
  return 0
end

vim.fn.executable = function(bin)
  if bin == "copilot" then
    return state.copilot_exists and 1 or 0
  end
  return 0
end

vim.fn.fnamemodify = function(path, mod)
  if mod == ":p:h" then
    return path:gsub("/[^/]+$", "")
  end
  if mod == ":p" then
    return path
  end
  if mod == ":t" then
    return path:match("[^/]+$") or path
  end
  return path
end

vim.fn.getqflist = function()
  return state.qflist
end

vim.fn.jobstart = function(cmd, opts)
  table.insert(state.job_calls, { cmd = cmd, opts = opts or {} })
  return #state.job_calls
end

vim.uv = vim.uv or {}
vim.uv.now = function()
  fake_now = fake_now + 100
  return fake_now
end
vim.uv.fs_stat = function(path)
  -- make /tmp look like a project root by simulating .git presence
  if path == "/tmp/.git" then
    return { mtime = { sec = 1 } }
  end
  local mt = state.mtimes[path] or nil
  if mt then return { mtime = { sec = mt } } end
  return nil
end

local function reset_state()
  state.mapped = {}
  state.notify_calls = {}
  state.commands = {}
  state.run_calls = {}
  state.job_calls = {}
  state.qflist = {}
  state.copilot_exists = true
  state.lines_by_buf = {}
  state.mtimes = {}
  state.open_bufs = {}
  state.buf_lines = {}
  state.file_contents = {}
  fake_now = 0
  current_buf = 1
end

local neotest_mode = "pass"
local stale_poll_count = 0

local function install_neotest()
  stale_poll_count = 0
  package.loaded["neotest"] = {
    run = {
      run = function(path)
        table.insert(state.run_calls, path)
      end,
    },
    state = {
      adapter_ids = function()
        if neotest_mode == "mixed-adapters" then
          return { "passing", "failing" }
        end
        return { "fake" }
      end,
      results = function(adapter_id)
        if neotest_mode == "mixed-adapters" and adapter_id == "failing" then
          return {
            ["sample::failing"] = {
              status = "failed",
              errors = { { message = "Expected true got false" } },
            },
          }
        end
        if neotest_mode == "fail-results" then
          return {
            ["sample::failing"] = {
              status = "failed",
              errors = { { message = "Expected true got false" } },
            },
          }
        end
        return {}
      end,
      status_counts = function(adapter_id)
        if neotest_mode == "mixed-adapters" then
          if adapter_id == "failing" then
            return { running = 0, failed = 1 }
          end
          return { running = 0, failed = 0, passed = 1 }
        end
        if neotest_mode == "stale-then-pass" then
          stale_poll_count = stale_poll_count + 1
          -- first poll reflects a leftover failure from a previous, unrelated
          -- run; from the second poll onward the real (passing) state shows
          if stale_poll_count <= 1 then
            return { running = 0, failed = 1 }
          end
          return { running = 0, failed = 0, passed = 1 }
        end
        if neotest_mode == "fail-results" or neotest_mode == "fail-qf" then
          return { running = 0, failed = 1 }
        end
        return { running = 0, failed = 0, passed = 1 }
      end,
    },
  }
end

local function load_bot()
  package.loaded["tdd-bot"] = nil
  return require("tdd-bot")
end

local function mapped_handler(lhs)
  for _, map in ipairs(state.mapped) do
    if map.mode == "n" and map.lhs == lhs and type(map.rhs) == "function" then
      return map.rhs
    end
  end
  return nil
end

local function contains(list, value)
  for _, item in ipairs(list) do
    if item == value then
      return true
    end
  end
  return false
end

local function arg_after(list, flag)
  for i, item in ipairs(list) do
    if item == flag then
      return list[i + 1]
    end
  end
  return nil
end

local function test_tdd_mapping_exists()
  reset_state()
  install_neotest()
  local bot = load_bot()
  bot.setup()
  assert(mapped_handler("<leader>tdd"), "expected <leader>tdd mapping")
end

local function test_failing_run_starts_background_copilot()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  assert(#state.job_calls == 1, "expected one background job")
  local call = state.job_calls[1]
  assert(call.cmd[1] == "copilot", "expected copilot binary")
  assert(call.cmd[2] == "--allow-all-tools", "expected allow-all-tools flag")
  assert(contains(call.cmd, "--add-dir"), "expected --add-dir flag")
  assert(contains(call.cmd, "-p"), "expected -p prompt flag")
  local prompt_idx = nil
  for i, arg in ipairs(call.cmd) do
    if arg == "-p" then
      prompt_idx = i + 1
    end
  end
  assert(type(call.cmd[prompt_idx]) == "string" and call.cmd[prompt_idx]:find("Expected true got false", 1, true),
    "expected failure text in prompt")
  assert(call.cmd[prompt_idx]:find("When you can't solve the failing test", 1, true),
    "expected unresolved-test reporting instruction in prompt")
  assert(call.cmd[prompt_idx]:find("TDD_BOT_REPORT:", 1, true),
    "expected unresolved-test report marker in prompt")
  -- no log buffer should open
  for _, cmd in ipairs(state.commands) do
    assert(not cmd:match("botright"), "expected no bottom log buffer opened, got: " .. cmd)
  end
end

local function test_start_notifies_implementing()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local found = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("Implementing", 1, true) or n.msg:find("implementing", 1, true) or n.msg:find("started", 1, true) then
      found = true
      assert(n.opts.timeout == 3000, "expected transient start notification")
    end
  end
  assert(found, "expected start notification")
end

local function test_passing_run_completes_loop()
  reset_state()
  neotest_mode = "pass"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  assert(#state.run_calls == 1, "expected one test run")
  assert(not bot._is_running(), "expected passing test run to complete TDD loop")
end

local function test_failure_in_any_adapter_beats_passing_adapter()
  reset_state()
  neotest_mode = "mixed-adapters"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  assert(#state.job_calls == 1, "expected failing adapter to start Copilot despite another adapter passing")
end

local function test_stale_failure_from_prior_run_is_ignored()
  reset_state()
  neotest_mode = "stale-then-pass"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  assert(#state.job_calls == 0,
    "expected stale failure from a previous, unrelated run to be ignored; got " .. tostring(#state.job_calls) .. " job(s)")
  local found_pass = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("All tests passing", 1, true) then
      found_pass = true
    end
  end
  assert(found_pass, "expected dirty/stale first-poll failure to resolve to a passing notification")
end

local function test_tdd_loop_start_notifies_plugin_version()
  reset_state()
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local found_version = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg == "[tdd-bot] Starting TDD loop (tdd-bot v0.1.13)." then
      found_version = true
    end
  end
  assert(found_version, "expected TDD loop start notification with plugin version")
  assert(bot.version == "0.1.13", "expected public plugin version")
end

local function test_buffer_lines_synced_from_disk_on_exit()
  reset_state()
  neotest_mode = "fail-results"
  -- seed mtime before copilot runs so mtime changes and triggers force reload
  state.mtimes["/tmp/sample_test.dart"] = 1000
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local call = state.job_calls[1]
  state.mtimes["/tmp/sample_test.dart"] = 2000
  state.file_contents["/tmp/sample_test.dart"] = { "fresh1", "fresh2" }
  neotest_mode = "pass"
  call.opts.on_exit(1, 0)

  -- must NOT use :edit! (retriggers FileType/BufReadPost and conflicts with LSP attach)
  for _, cmd in ipairs(state.commands) do
    assert(cmd ~= "edit!", "expected no :edit! (breaks LSP), got: " .. tostring(cmd))
  end
  assert(state.lines_by_buf[current_buf] ~= nil, "expected buffer lines to be replaced")
  assert(state.lines_by_buf[current_buf][1] == "fresh1" and state.lines_by_buf[current_buf][2] == "fresh2",
    "expected buffer synced with on-disk content via nvim_buf_set_lines")
end

local function test_no_reload_when_mtime_unchanged()
  reset_state()
  neotest_mode = "fail-results"
  state.mtimes["/tmp/sample_test.dart"] = 1000
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local call = state.job_calls[1]
  -- mtime unchanged: copilot made no file changes
  neotest_mode = "pass"
  call.opts.on_exit(1, 0)

  assert(state.lines_by_buf[current_buf] == nil, "expected no buffer sync when mtime unchanged")
end

local function test_notification_includes_diff_content()
  reset_state()
  neotest_mode = "fail-results"
  state.mtimes["/tmp/sample_test.dart"] = 1000
  state.buf_lines[current_buf] = { "line1", "line2" }
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local call = state.job_calls[1]
  -- simulate copilot changing the file on disk
  state.mtimes["/tmp/sample_test.dart"] = 2000
  state.file_contents["/tmp/sample_test.dart"] = { "line1", "line2 changed" }
  neotest_mode = "pass"
  call.opts.on_exit(1, 0)

  local found_diff = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("sample_test.dart", 1, true)
      and n.msg:find("-line2", 1, true)
      and n.msg:find("+line2 changed", 1, true) then
      found_diff = true
    end
  end
  assert(found_diff, "expected notification to include unified diff of changes")
end

local function test_notify_changed_file_when_mtime_differs()
  reset_state()
  neotest_mode = "fail-results"
  -- seed mtime before copilot runs
  state.mtimes["/tmp/sample_test.dart"] = 1000
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local call = state.job_calls[1]
  -- simulate copilot changed the file (bump mtime)
  state.mtimes["/tmp/sample_test.dart"] = 2000
  neotest_mode = "pass"
  call.opts.on_exit(1, 0)

  local found_change = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("sample_test.dart", 1, true) then
      found_change = true
    end
  end
  assert(found_change, "expected per-file change notification when mtime changed")
end

local function test_no_notify_when_mtime_unchanged()
  reset_state()
  neotest_mode = "fail-results"
  state.mtimes["/tmp/sample_test.dart"] = 1000
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local call = state.job_calls[1]
  -- mtime unchanged: copilot made no file changes
  neotest_mode = "pass"
  call.opts.on_exit(1, 0)

  for _, n in ipairs(state.notify_calls) do
    assert(not n.msg:find("Applied changes to", 1, true),
      "expected no file-change notification when mtime unchanged, got: " .. n.msg)
  end
end

local function test_notify_includes_fix_duration_on_exit()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local call = state.job_calls[1]
  neotest_mode = "pass"
  call.opts.on_exit(1, 0)

  local found_duration = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("took", 1, true) and n.msg:match("%d+%.%d+s") then
      found_duration = true
    end
  end
  assert(found_duration, "expected a notification reporting fix duration in Ns format")
end

local function test_unresolved_copilot_report_is_notified()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local call = state.job_calls[1]
  call.opts.on_stdout(1, {
    "TDD_BOT_REPORT:",
    "Root cause: expected value is stale.",
    "No safe fix found without changing product behavior.",
  })
  neotest_mode = "pass"
  call.opts.on_exit(1, 0)

  local found_report = false
  for _, n in ipairs(state.notify_calls) do
    if n.level == vim.log.levels.WARN
      and n.msg:find("Copilot unresolved%-test report", nil, false)
      and n.msg:find("Root cause: expected value is stale.", 1, true)
      and n.msg:find("No safe fix found without changing product behavior.", 1, true) then
      found_report = true
    end
  end
  assert(found_report, "expected Copilot unresolved-test report notification")
end

local function test_rerun_after_copilot_exit()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local call = state.job_calls[1]
  local runs_before = #state.run_calls
  neotest_mode = "pass"
  call.opts.on_exit(1, 0)
  assert(#state.run_calls == runs_before + 1, "expected rerun after copilot exit")
end

local function test_retry_loop_fires_second_copilot_on_still_failing()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup({ max_retries = 3 })
  bot.run_tdd()

  local call1 = state.job_calls[1]
  assert(call1, "expected first job")
  neotest_mode = "fail-results"
  call1.opts.on_exit(1, 0)

  assert(#state.job_calls == 2, "expected second copilot job on still-failing. got " .. tostring(#state.job_calls))
end

local function test_retry_loop_stops_when_passing()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup({ max_retries = 3 })
  bot.run_tdd()

  local call1 = state.job_calls[1]
  neotest_mode = "pass"
  call1.opts.on_exit(1, 0)

  assert(#state.job_calls == 1, "expected no second job when passing. got " .. tostring(#state.job_calls))
  local found_done = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("passing", 1, true) or n.msg:find("Done", 1, true) or n.msg:find("done", 1, true) then
      found_done = true
    end
  end
  assert(found_done, "expected final passing notification")
end

local function test_every_run_notifies_pass_fail_counts()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup({ max_retries = 3 })
  bot.run_tdd()

  local found_result_counts = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("Test run result", 1, true) and n.msg:match("%d+ passed") and n.msg:match("%d+ failed") then
      found_result_counts = true
    end
  end
  assert(found_result_counts, "expected per-run notification with passed/failed counts even on first failing run")
end

local function test_failing_run_notification_includes_test_id_and_output()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup({ max_retries = 3 })
  bot.run_tdd()

  local found = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("Test run result", 1, true)
      and n.msg:find("Failing test:", 1, true)
      and n.msg:find("sample::failing", 1, true)
      and n.msg:find("Output:", 1, true)
      and n.msg:find("Expected true got false", 1, true) then
      found = true
    end
  end
  assert(found, "expected failing-run notification to include failing test id and its output")
end

local function test_passing_notification_includes_counts()
  reset_state()
  neotest_mode = "pass"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local found_counts = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("passed", 1, true) and n.msg:find("failed", 1, true) and n.msg:match("%d+ passed") and n.msg:match("%d+ failed") then
      found_counts = true
    end
  end
  assert(found_counts, "expected passing notification to include passed/failed counts")
end

local function test_exhausted_notification_includes_counts()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup({ max_retries = 1 })
  bot.run_tdd()

  local call1 = state.job_calls[1]
  neotest_mode = "fail-results"
  call1.opts.on_exit(1, 0)

  local found_counts = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("exhausted", 1, true) and n.msg:match("%d+ passed") and n.msg:match("%d+ failed") then
      found_counts = true
    end
  end
  assert(found_counts, "expected exhausted notification to include passed/failed counts")
end

local function test_retry_loop_stops_at_max_retries()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup({ max_retries = 2 })
  bot.run_tdd()

  for i = 1, 2 do
    local call = state.job_calls[i]
    assert(call, "expected job " .. i)
    neotest_mode = "fail-results"
    call.opts.on_exit(1, 0)
  end

  assert(#state.job_calls == 2, "expected exactly max_retries jobs. got " .. tostring(#state.job_calls))
  local found_exhausted = false
  local found_reason = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("max", 1, true) or n.msg:find("retries", 1, true) or n.msg:find("exhausted", 1, true) or n.msg:find("giving up", 1, true) then
      found_exhausted = true
      if n.msg:find("Expected true got false", 1, true) then
        found_reason = true
      end
    end
  end
  assert(found_exhausted, "expected exhausted/give-up notification")
  assert(found_reason, "expected give-up notification to include the last failure reason")
end

local function test_fallback_quickfix_failure_used()
  reset_state()
  neotest_mode = "fail-qf"
  state.qflist = {
    { filename = "/tmp/sample_test.dart", lnum = 23, type = "E", text = "QF fail text" },
  }
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()
  assert(#state.job_calls == 1, "expected job via quickfix fallback")
  local prompt = arg_after(state.job_calls[1].cmd, "-p")
  assert(prompt and prompt:find("QF fail text", 1, true), "expected quickfix text in prompt")
end

local function test_guard_when_job_already_running()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()
  bot.run_tdd()
  assert(#state.job_calls == 1, "expected second run blocked while job active")
end

local function test_default_cmd_includes_speed_flags()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local cmd = state.job_calls[1].cmd
  assert(contains(cmd, "--no-custom-instructions"),
    "expected --no-custom-instructions to skip loading global custom instructions/skills")
  assert(contains(cmd, "--disable-builtin-mcps"),
    "expected --disable-builtin-mcps to skip built-in MCP server startup")
end

local function test_copilot_cmd_is_configurable()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup({ copilot_cmd = { "copilot", "--my-custom-flag" } })
  bot.run_tdd()

  local cmd = state.job_calls[1].cmd
  assert(cmd[1] == "copilot", "expected copilot binary")
  assert(cmd[2] == "--my-custom-flag", "expected configured prefix to be used")
  assert(not contains(cmd, "--allow-all-tools"),
    "expected default flags replaced, not merged, when copilot_cmd is overridden")
  assert(contains(cmd, "--add-dir"), "expected structural flags still appended after custom prefix")
end

local function test_generate_uuid_format_and_uniqueness()
  reset_state()
  install_neotest()
  local bot = load_bot()
  bot.setup()

  local id1 = bot._generate_uuid()
  local id2 = bot._generate_uuid()

  assert(type(id1) == "string", "expected uuid to be a string")
  assert(id1:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"),
    "expected RFC4122 v4 format, got: " .. id1)
  assert(id1 ~= id2, "expected two calls to produce different uuids")
end

local function test_same_file_reuses_session_id_across_runs()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local call1 = state.job_calls[1]
  assert(contains(call1.cmd, "--session-id"), "expected --session-id flag")
  local uuid1 = arg_after(call1.cmd, "--session-id")
  assert(type(uuid1) == "string" and #uuid1 > 0, "expected uuid string after --session-id")

  neotest_mode = "fail-results"
  call1.opts.on_exit(1, 0)

  local call2 = state.job_calls[2]
  assert(call2, "expected second job on retry")
  assert(contains(call2.cmd, "--session-id"), "expected --session-id flag on retry")
  assert(arg_after(call2.cmd, "--session-id") == uuid1, "expected same uuid reused for same file across retries")
end

local function test_different_file_gets_different_session_id()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local uuid1 = arg_after(state.job_calls[1].cmd, "--session-id")

  -- switch current buffer's file path
  vim.api.nvim_buf_get_name = function(buf)
    if buf == 0 or buf == current_buf then
      return "/tmp/other_test.dart"
    end
    return state.open_bufs[buf] or ""
  end

  -- stop the pending job from the first run so a fresh run_tdd is allowed
  neotest_mode = "pass"
  state.job_calls[1].opts.on_exit(1, 0)

  neotest_mode = "fail-results"
  bot.run_tdd()

  local uuid2 = arg_after(state.job_calls[2].cmd, "--session-id")
  assert(uuid2 ~= uuid1, "expected different uuid for different file path")

  -- restore
  vim.api.nvim_buf_get_name = function(buf)
    if buf == 0 or buf == current_buf then
      return "/tmp/sample_test.dart"
    end
    return state.open_bufs[buf] or ""
  end
end

local function test_get_session_id_returns_nil_when_unset()
  reset_state()
  install_neotest()
  local bot = load_bot()
  bot.setup()
  assert(bot._get_session_id("/tmp/never_ran.dart") == nil, "expected nil for file with no stored session")
end

local function test_tdc_mapping_exists()
  reset_state()
  install_neotest()
  local bot = load_bot()
  bot.setup()
  assert(mapped_handler("<leader>tdc"), "expected <leader>tdc mapping")
end

local function test_tdr_mapping_exists()
  reset_state()
  install_neotest()
  local bot = load_bot()
  bot.setup()
  assert(mapped_handler("<leader>tdr"), "expected <leader>tdr mapping")
end

local function test_refactor_starts_copilot_job_per_comment()
  reset_state()
  neotest_mode = "pass"
  install_neotest()
  state.buf_lines[current_buf] = {
    "local x = 1",
    "// Refactoring: extract this into a helper function",
    "local y = 2",
    "// Refactoring: rename y to total",
  }
  local bot = load_bot()
  bot.setup()
  bot.run_refactor()

  assert(#state.job_calls == 1, "expected first refactoring to start a job")
  local prompt = arg_after(state.job_calls[1].cmd, "-p")
  assert(prompt:find("extract this into a helper function", 1, true), "expected first refactoring text in prompt")
  assert(prompt:find("Line: 2", 1, true), "expected line number of first refactoring comment in prompt")

  -- finish first job, should launch the second
  state.job_calls[1].opts.on_exit(1, 0)
  assert(#state.job_calls == 2, "expected second refactoring to start a job after first completes")
  local prompt2 = arg_after(state.job_calls[2].cmd, "-p")
  assert(prompt2:find("rename y to total", 1, true), "expected second refactoring text in prompt")
  assert(prompt2:find("Line: 4", 1, true), "expected line number of second refactoring comment in prompt")

  -- finish second job, loop should complete with no more jobs
  state.job_calls[2].opts.on_exit(1, 0)
  assert(#state.job_calls == 2, "expected no third job after all refactorings applied")
  assert(not bot._is_running(), "expected refactor loop to mark itself not running once complete")

  local found_complete = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("Refactor loop complete", 1, true) and n.msg:find("2", 1, true) then
      found_complete = true
    end
  end
  assert(found_complete, "expected completion notification mentioning number of refactorings applied")
end

local function test_refactor_no_comments_found()
  reset_state()
  neotest_mode = "pass"
  install_neotest()
  state.buf_lines[current_buf] = { "local x = 1", "local y = 2" }
  local bot = load_bot()
  bot.setup()
  bot.run_refactor()

  assert(#state.job_calls == 0, "expected no job when no refactoring comments present")
  local found = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("No refactoring comments found", 1, true) then
      found = true
    end
  end
  assert(found, "expected notification that no refactoring comments were found")
end

local function test_refactor_aborts_when_tests_red()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  state.buf_lines[current_buf] = {
    "local x = 1",
    "// Refactoring: extract this into a helper function",
  }
  local bot = load_bot()
  bot.setup()
  bot.run_refactor()

  assert(#state.job_calls == 0, "expected no copilot job started when tests are red")
  assert(not bot._is_running(), "expected loop_running left false after aborting")

  local found = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("aborted", 1, true) and n.msg:find("red", 1, true) then
      found = true
    end
  end
  assert(found, "expected notification explaining refactoring was aborted because tests are red")
end

local function test_refactor_reverts_when_refactoring_breaks_tests()
  reset_state()
  neotest_mode = "pass"
  install_neotest()
  local pre_lines = {
    "local x = 1",
    "// Refactoring: extract this into a helper function",
    "local y = 2",
    "// Refactoring: rename y to total",
  }
  state.buf_lines[current_buf] = pre_lines
  local bot = load_bot()
  bot.setup()
  bot.run_refactor()

  assert(#state.job_calls == 1, "expected first refactoring job to start once tests confirmed green")

  -- first refactoring breaks the tests
  neotest_mode = "fail-results"
  state.job_calls[1].opts.on_exit(1, 0)

  assert(#state.job_calls == 1, "expected loop to stop, no second refactoring job started")
  assert(not bot._is_running(), "expected refactor loop to stop running after a revert")

  local path = "/tmp/sample_test.dart"
  for i, line in ipairs(pre_lines) do
    assert(state.file_contents[path][i] == line, "expected file reverted to pre-refactoring content on disk")
    assert(state.lines_by_buf[current_buf][i] == line, "expected buffer reverted to pre-refactoring content")
  end

  local found = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("reverted to previous state", 1, true) then
      found = true
    end
  end
  assert(found, "expected notification that the broken refactoring was reverted")
end

local function test_clear_session_removes_stored_uuid()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local uuid_before = bot._get_session_id("/tmp/sample_test.dart")
  assert(uuid_before ~= nil, "expected a session id to be stored after run_tdd")

  bot.clear_session()
  assert(bot._get_session_id("/tmp/sample_test.dart") == nil, "expected session id cleared")

  -- next run on same file should generate a brand-new uuid
  neotest_mode = "pass"
  state.job_calls[1].opts.on_exit(1, 0) -- let the earlier retry loop settle, avoid job guard
  neotest_mode = "fail-results"
  bot.run_tdd()
  local uuid_after = bot._get_session_id("/tmp/sample_test.dart")
  assert(uuid_after ~= nil and uuid_after ~= uuid_before, "expected fresh uuid after clear + rerun")
end

local function test_clear_session_notifies_when_nothing_to_clear()
  reset_state()
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.clear_session()

  local found = false
  for _, n in ipairs(state.notify_calls) do
    if n.msg:find("[Nn]o.*session", nil, false) or n.msg:find("[Nn]othing to clear", nil, false) then
      found = true
    end
  end
  assert(found, "expected a notify when clearing with no stored session")
end

local function test_repository_has_no_superpowers_docs()
  assert(vim.fn.isdirectory("docs/superpowers") == 0, "expected no superpowers documentation in repository")
end

test_tdd_mapping_exists()
test_failing_run_starts_background_copilot()
test_start_notifies_implementing()
test_tdd_loop_start_notifies_plugin_version()
test_passing_run_completes_loop()
test_failure_in_any_adapter_beats_passing_adapter()
test_stale_failure_from_prior_run_is_ignored()
test_buffer_lines_synced_from_disk_on_exit()
test_no_reload_when_mtime_unchanged()
test_notification_includes_diff_content()
test_notify_changed_file_when_mtime_differs()
test_no_notify_when_mtime_unchanged()
test_notify_includes_fix_duration_on_exit()
test_unresolved_copilot_report_is_notified()
test_rerun_after_copilot_exit()
test_retry_loop_fires_second_copilot_on_still_failing()
test_retry_loop_stops_when_passing()
test_every_run_notifies_pass_fail_counts()
test_failing_run_notification_includes_test_id_and_output()
test_passing_notification_includes_counts()
test_exhausted_notification_includes_counts()
test_retry_loop_stops_at_max_retries()
test_fallback_quickfix_failure_used()
test_guard_when_job_already_running()
test_default_cmd_includes_speed_flags()
test_copilot_cmd_is_configurable()
test_generate_uuid_format_and_uniqueness()
test_same_file_reuses_session_id_across_runs()
test_different_file_gets_different_session_id()
test_get_session_id_returns_nil_when_unset()
test_tdc_mapping_exists()
test_tdr_mapping_exists()
test_refactor_starts_copilot_job_per_comment()
test_refactor_no_comments_found()
test_refactor_aborts_when_tests_red()
test_refactor_reverts_when_refactoring_breaks_tests()
test_clear_session_removes_stored_uuid()
test_clear_session_notifies_when_nothing_to_clear()
test_repository_has_no_superpowers_docs()

vim.notify = real.notify
vim.defer_fn = real.defer_fn
vim.cmd = real.cmd
vim.keymap.set = real.keymap_set
vim.api.nvim_buf_get_name = real.nvim_buf_get_name
vim.api.nvim_get_current_buf = real.nvim_get_current_buf
vim.api.nvim_buf_set_lines = real.nvim_buf_set_lines
vim.api.nvim_list_bufs = real.nvim_list_bufs
vim.api.nvim_buf_is_loaded = real.nvim_buf_is_loaded
vim.api.nvim_buf_get_lines = real.nvim_buf_get_lines
vim.fn.readfile = real.readfile
vim.fn.writefile = real.writefile
vim.fn.executable = real.executable
vim.fn.fnamemodify = real.fnamemodify
vim.fn.getqflist = real.getqflist
vim.fn.jobstart = real.jobstart
if vim.uv then
  vim.uv.now = real.uv_now
  vim.uv.fs_stat = real.uv_fs_stat
end

print("ok")
