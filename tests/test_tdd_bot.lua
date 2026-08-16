package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local state = {
  mapped = {},
  notify_calls = {},
  commands = {},
  run_calls = {},
  job_calls = {},
  qflist = {},
  copilot_exists = true,
  jobstart_result = nil,
  lines_by_buf = {},
  popup_calls = {},
  popup_buffers = {},
  status_calls = {},
  highlights = {},
  buffer_highlights = {},
  buffer_options = {},
  valid_buffers = {},
  valid_windows = {},
  next_buffer = 1000,
  next_window = 2000,
  window_calls = {},
  window_configs = {},
  window_buffers = {},
  closed_windows = {},
  autocmds = {},
  deferred_activity = {},
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
  nvim_create_buf = vim.api.nvim_create_buf,
  nvim_open_win = vim.api.nvim_open_win,
  nvim_buf_is_valid = vim.api.nvim_buf_is_valid,
  nvim_win_is_valid = vim.api.nvim_win_is_valid,
  nvim_win_set_config = vim.api.nvim_win_set_config,
  nvim_win_close = vim.api.nvim_win_close,
  nvim_create_autocmd = vim.api.nvim_create_autocmd,
  nvim_set_hl = vim.api.nvim_set_hl,
  nvim_buf_clear_namespace = vim.api.nvim_buf_clear_namespace,
  nvim_buf_add_highlight = vim.api.nvim_buf_add_highlight,
  nvim_set_option_value = vim.api.nvim_set_option_value,
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

vim.defer_fn = function(fn, delay)
  if delay == 500 then
    table.insert(state.deferred_activity, fn)
  else
    fn()
  end
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
  state.buf_lines[buf] = {}
  for _, line in ipairs(lines) do
    state.lines_by_buf[buf][#state.lines_by_buf[buf] + 1] = line
    state.buf_lines[buf][#state.buf_lines[buf] + 1] = line
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

vim.api.nvim_create_buf = function(_, _)
  local buf = state.next_buffer
  state.next_buffer = state.next_buffer + 1
  state.valid_buffers[buf] = true
  return buf
end

vim.api.nvim_open_win = function(buf, enter, opts)
  local win = state.next_window
  state.next_window = state.next_window + 1
  state.valid_windows[win] = true
  state.window_configs[win] = opts
  state.window_buffers[win] = buf
  table.insert(state.window_calls, { buf = buf, enter = enter, opts = opts, win = win })
  if opts.title then
    state.popup_buffers[buf] = state.lines_by_buf[buf] or {}
    table.insert(state.popup_calls, { buf = buf, enter = enter, opts = opts, win = win })
  elseif not opts.border then
    table.insert(state.status_calls, { buf = buf, enter = enter, opts = opts, win = win })
  end
  return win
end

vim.api.nvim_buf_is_valid = function(buf)
  return state.valid_buffers[buf] == true
end

vim.api.nvim_win_is_valid = function(win)
  return state.valid_windows[win] == true
end

vim.api.nvim_win_set_config = function(win, opts)
  state.window_configs[win] = opts
  for _, call in ipairs(state.status_calls) do
    if call.win == win then
      call.opts = opts
      return
    end
  end
end

vim.api.nvim_win_close = function(win, _)
  state.valid_windows[win] = false
  table.insert(state.closed_windows, win)
  local buf = state.window_buffers[win]
  for _, autocmd in ipairs(state.autocmds) do
    if autocmd.opts.buffer == buf then
      autocmd.opts.callback()
    end
  end
end

vim.api.nvim_create_autocmd = function(event, opts)
  table.insert(state.autocmds, { event = event, opts = opts })
end

vim.api.nvim_set_hl = function(_, name, opts)
  state.highlights[name] = opts
end

vim.api.nvim_buf_clear_namespace = function() end

vim.api.nvim_buf_add_highlight = function(buf, _, highlight)
  state.buffer_highlights[buf] = highlight
end

vim.api.nvim_set_option_value = function(name, value, opts)
  state.buffer_options[opts.buf] = state.buffer_options[opts.buf] or {}
  state.buffer_options[opts.buf][name] = value
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
  return state.jobstart_result or #state.job_calls
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
  state.jobstart_result = nil
  state.lines_by_buf = {}
  state.popup_calls = {}
  state.popup_buffers = {}
  state.status_calls = {}
  state.highlights = {}
  state.buffer_highlights = {}
  state.buffer_options = {}
  state.valid_buffers = {}
  state.valid_windows = {}
  state.next_buffer = 1000
  state.next_window = 2000
  state.window_calls = {}
  state.window_configs = {}
  state.window_buffers = {}
  state.closed_windows = {}
  state.autocmds = {}
  state.deferred_activity = {}
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

local function popup_mapping(popup, key)
  for _, map in ipairs(state.mapped) do
    if map.lhs == key and map.opts.buffer == popup.buf then
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
  -- no log buffer should open
  for _, cmd in ipairs(state.commands) do
    assert(not cmd:match("botright"), "expected no bottom log buffer opened, got: " .. cmd)
  end
end

local function test_failed_copilot_launch_stops_on_static_red_dot()
  reset_state()
  neotest_mode = "fail-results"
  state.jobstart_result = -1
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  assert(not bot._is_running(), "expected failed Copilot launch to stop TDD loop")
  assert(#state.closed_windows == 0, "expected status dot to remain visible after failed Copilot launch")
  assert(state.buffer_highlights[state.status_calls[1].buf] == "TddBotStatusRed",
    "expected failed Copilot launch to leave a static red dot")
  assert(#state.notify_calls == 0, "expected failed Copilot launch to avoid notification")
end

local function test_running_loop_pulses_single_status_dot()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  assert(#state.status_calls == 1, "expected one persistent status window")
  local status = state.status_calls[1]
  assert(not status.enter and not status.opts.focusable, "expected non-focusable status dot")
  assert(#state.window_calls == 1 and not status.opts.border, "expected no bordered activity window")
  assert(state.buffer_highlights[status.buf] == "TddBotStatusRed", "expected bright red recovery dot")
  assert(state.highlights.TddBotStatusRedDim.fg == "#802222", "expected dim red pulse highlight")
  assert(state.highlights.TddBotStatusGreenDim.fg == "#287a40", "expected dim green pulse highlight")
  assert(state.highlights.TddBotStatusBlueDim.fg == "#285b8f", "expected dim blue pulse highlight")

  table.remove(state.deferred_activity, 1)() -- stale green pulse
  table.remove(state.deferred_activity, 1)()
  assert(state.buffer_highlights[status.buf] == "TddBotStatusRedDim", "expected dim red pulse")
  table.remove(state.deferred_activity, 1)()
  assert(state.buffer_highlights[status.buf] == "TddBotStatusRed", "expected bright red pulse")
  assert(#state.notify_calls == 0, "expected no progress notification")
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
  assert(#state.closed_windows == 0, "expected status dot to remain visible after passing run")
  assert(state.buffer_highlights[state.status_calls[1].buf] == "TddBotStatusGreen",
    "expected passing run to settle on a static green dot")
  assert(#state.notify_calls == 0, "expected passing run to avoid notifications")
end

local function test_status_dot_reflects_confirmed_tdd_results()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  assert(#state.status_calls == 1, "expected one persistent status window")
  local status = state.status_calls[1]
  assert(not status.enter and not status.opts.focusable, "expected status window not to take focus")
  assert(status.opts.width == 1 and status.opts.height == 1 and status.opts.relative == "editor",
    "expected compact floating status window")
  assert(state.buffer_highlights[status.buf] == "TddBotStatusRed", "expected red status dot highlight")

  local stale_red_pulse = state.deferred_activity[#state.deferred_activity]
  neotest_mode = "pass"
  state.job_calls[1].opts.on_exit(1, 0)
  assert(#state.status_calls == 1, "expected green update to reuse status window")
  assert(state.buffer_highlights[status.buf] == "TddBotStatusGreen", "expected green status dot highlight")
  stale_red_pulse()
  assert(state.buffer_highlights[status.buf] == "TddBotStatusGreen",
    "expected stale red pulse not to overwrite static green status")
end

local function test_status_dot_recovers_after_manual_close()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local first = state.status_calls[1]
  state.valid_windows[first.win] = false
  neotest_mode = "pass"
  state.job_calls[1].opts.on_exit(1, 0)

  assert(#state.status_calls == 2, "expected closed status window to be recreated")
  assert(state.buffer_highlights[state.status_calls[2].buf] == "TddBotStatusGreen",
    "expected recreated status window to show current green state")
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
  assert(#state.notify_calls == 0, "expected stale failure recovery to avoid notifications")
end

local function test_tdd_loop_exposes_plugin_version()
  reset_state()
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  assert(bot.version == "0.1.13", "expected public plugin version")
  assert(#state.notify_calls == 0, "expected loop start to avoid notifications")
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
  assert(#state.popup_calls == 0, "expected no popup when Copilot makes no changes")
end

local function test_applied_changes_open_in_diff_popup()
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

  assert(#state.popup_calls == 1, "expected changed file to open one popup")
  local popup = state.popup_calls[1]
  assert(popup.enter, "expected popup to receive focus")
  assert(popup.opts.title:find("sample::failing", 1, true), "expected popup title to name failing test")
  assert(popup.opts.title:find("sample_test.dart", 1, true), "expected popup title to name changed file")
  assert(popup.opts.border == "rounded", "expected popup border")
  assert(popup.opts.relative == "editor", "expected floating editor popup")
  assert(popup.opts.style == "minimal", "expected minimal popup")
  assert(popup.opts.width > 0 and popup.opts.height > 0, "expected visible popup dimensions")
  local content = table.concat(state.popup_buffers[popup.buf], "\n")
  assert(content:find("-line2", 1, true) and content:find("+line2 changed", 1, true),
    "expected popup to show unified diff of Copilot changes")
  assert(state.buffer_options[popup.buf].filetype == "diff", "expected diff syntax in popup")
end

local function test_refactor_applied_changes_name_refactoring_in_popup()
  reset_state()
  neotest_mode = "pass"
  state.mtimes["/tmp/sample_test.dart"] = 1000
  state.buf_lines[current_buf] = {
    "local value = 1",
    "// Refactoring: extract value calculation",
  }
  state.file_contents["/tmp/sample_test.dart"] = {
    "local value = 1",
    "// Refactoring: extract value calculation",
  }
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_refactor()

  local call = state.job_calls[1]
  state.mtimes["/tmp/sample_test.dart"] = 2000
  state.file_contents["/tmp/sample_test.dart"] = {
    "local function value() return 1 end",
  }
  call.opts.on_exit(1, 0)

  assert(#state.popup_calls == 1, "expected changed refactoring file to open one popup")
  local popup = state.popup_calls[1]
  assert(popup.opts.title:find("extract value calculation", 1, true),
    "expected popup title to name refactoring")
  assert(popup.opts.title:find("sample_test.dart", 1, true),
    "expected popup title to name changed file")
  assert(popup.opts.title:find("[a]ccept [r]eject", 1, true),
    "expected refactoring popup to show review controls")
  assert(popup_mapping(popup, "a") and popup_mapping(popup, "r") and popup_mapping(popup, "q") and popup_mapping(popup, "<Esc>"),
    "expected refactoring popup to map accept and reject controls")
end

local function test_applied_changes_do_not_use_notification()
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

  assert(#state.popup_calls == 1, "expected changed file to open a popup")
  for _, n in ipairs(state.notify_calls) do
    assert(not n.msg:find("Applied changes to", 1, true),
      "expected applied changes to use popup instead of notification")
  end
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

local function test_copilot_exit_avoids_progress_notification()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local call = state.job_calls[1]
  neotest_mode = "pass"
  call.opts.on_exit(1, 0)

  assert(#state.notify_calls == 0, "expected Copilot exit to avoid progress notification")
end

local function test_unresolved_copilot_report_avoids_notification()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local call = state.job_calls[1]
  neotest_mode = "pass"
  call.opts.on_exit(1, 0)

  assert(#state.notify_calls == 0, "expected unresolved report to avoid notification")
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
  assert(#state.notify_calls == 0, "expected final passing run to avoid notifications")
end

local function test_failing_run_avoids_progress_notification()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup({ max_retries = 3 })
  bot.run_tdd()

  assert(#state.notify_calls == 0, "expected failing run to use activity hint instead of notification")
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

  assert(#state.notify_calls == 1, "expected one terminal retry notification")
  local message = state.notify_calls[1].msg
  assert(message:find("exhausted", 1, true) and message:match("%d+ passed") and message:match("%d+ failed"),
    "expected terminal retry notification to include counts")
  assert(message:find("sample::failing", 1, true) and message:find("Expected true got false", 1, true),
    "expected terminal retry notification to include final failure")
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

local function test_applied_changes_popup_closes_with_q_or_escape()
  local function open_popup()
    reset_state()
    neotest_mode = "fail-results"
    state.mtimes["/tmp/sample_test.dart"] = 1000
    state.buf_lines[current_buf] = { "line1" }
    install_neotest()
    local bot = load_bot()
    bot.setup()
    bot.run_tdd()

    state.mtimes["/tmp/sample_test.dart"] = 2000
    state.file_contents["/tmp/sample_test.dart"] = { "line2" }
    neotest_mode = "pass"
    state.job_calls[1].opts.on_exit(1, 0)

    return state.popup_calls[1]
  end

  local function close_with(key)
    local popup = open_popup()
    local mapping
    for _, candidate in ipairs(state.mapped) do
      if candidate.lhs == key and candidate.opts.buffer == popup.buf then
        mapping = candidate
        break
      end
    end

    assert(mapping, "expected popup mapping for " .. key)
    mapping.rhs()
    assert(not state.valid_windows[popup.win], "expected " .. key .. " to close changes popup")
  end

  close_with("q")
  close_with("<Esc>")
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

local function test_refactor_queue_waits_for_acceptance_before_next_job()
  reset_state()
  neotest_mode = "pass"
  install_neotest()
  state.buf_lines[current_buf] = {
    "local x = 1",
    "// Refactoring: extract this into a helper function",
    "local y = 2",
    "// Refactoring: rename y to total",
  }
  state.file_contents["/tmp/sample_test.dart"] = {
    "local x = 1",
    "// Refactoring: extract this into a helper function",
    "local y = 2",
    "// Refactoring: rename y to total",
  }
  local bot = load_bot()
  bot.setup()
  bot.run_refactor()

  assert(#state.job_calls == 1, "expected first refactoring to start a job")
  local status = state.status_calls[1]
  assert(state.lines_by_buf[status.buf][1] == "● 2", "expected blue status to show all pending refactorings")
  assert(status.opts.width == 3, "expected status window sized for pending refactoring count")
  local prompt = arg_after(state.job_calls[1].cmd, "-p")
  assert(prompt:find("extract this into a helper function", 1, true), "expected first refactoring text in prompt")
  assert(prompt:find("Line: 2", 1, true), "expected line number of first refactoring comment in prompt")

  -- First candidate must remain pending review.
  state.file_contents["/tmp/sample_test.dart"] = {
    "local function helper() return 1 end",
    "local y = 2",
    "// Refactoring: rename y to total",
  }
  state.job_calls[1].opts.on_exit(1, 0)
  assert(#state.commands == 0, "expected pending candidate not to reload or save")
  assert(#state.job_calls == 1, "expected next refactoring to wait for review decision")
  assert(bot._is_running(), "expected loop to stay running while review is unresolved")
  local popup = state.popup_calls[1]
  popup_mapping(popup, "a")()
  assert(#state.commands == 2 and state.commands[1] == "e!" and state.commands[2] == "w",
    "expected accepted refactoring to reload from disk then save")
  assert(#state.job_calls == 2, "expected second refactoring to start a job after first completes")
  assert(state.lines_by_buf[status.buf][1] == "● 1", "expected blue status to decrease after verified refactoring")
  local prompt2 = arg_after(state.job_calls[2].cmd, "-p")
  assert(prompt2:find("rename y to total", 1, true), "expected second refactoring text in prompt")
  assert(prompt2:find("Line: 3", 1, true), "expected line number recalculated after accepted refactoring")

  state.file_contents["/tmp/sample_test.dart"] = { "local function helper() return 1 end", "local total = 2" }
  state.job_calls[2].opts.on_exit(1, 0)
  popup_mapping(state.popup_calls[2], "a")()
  assert(#state.commands == 4 and state.commands[3] == "e!" and state.commands[4] == "w",
    "expected every completed refactoring to reload from disk then write through formatter")
  assert(#state.job_calls == 2, "expected no third job after all refactorings applied")
  assert(not bot._is_running(), "expected refactor loop to mark itself not running once complete")
  assert(state.lines_by_buf[status.buf][1] == "●", "expected completed refactoring queue to hide zero count")
  assert(status.opts.width == 1, "expected completed refactoring status window to shrink to dot")
  assert(state.buffer_highlights[status.buf] == "TddBotStatusGreen", "expected completed refactoring status to be green")

  assert(state.valid_windows[status.win], "expected status dot to remain visible after refactor completion")
  assert(#state.notify_calls == 0, "expected refactor completion to avoid notifications")
end

local function test_refactor_rejection_restores_snapshot_and_advances_once()
  reset_state()
  neotest_mode = "pass"
  install_neotest()
  local pre_lines = {
    "local x = 1",
    "// Refactoring: extract helper",
    "local y = 2",
    "// Refactoring: rename y",
  }
  state.buf_lines[current_buf] = pre_lines
  state.file_contents["/tmp/sample_test.dart"] = pre_lines
  local bot = load_bot()
  bot.setup()
  bot.run_refactor()

  state.file_contents["/tmp/sample_test.dart"] = { "local function helper() end", "// Refactoring: rename y" }
  state.job_calls[1].opts.on_exit(1, 0)
  local popup = state.popup_calls[1]
  popup_mapping(popup, "q")()
  popup_mapping(popup, "q")()

  assert(#state.commands == 0, "expected rejected candidate not to reload or save")
  assert(#state.run_calls == 1, "expected rejection not to verify candidate tests")
  assert(#state.job_calls == 2, "expected rejection to advance queue exactly once")
  for i, line in ipairs(pre_lines) do
    assert(state.file_contents["/tmp/sample_test.dart"][i] == line, "expected rejected candidate removed from disk")
    assert(state.lines_by_buf[current_buf][i] == line, "expected rejected candidate removed from buffer")
  end
  assert(state.lines_by_buf[state.status_calls[1].buf][1] == "● 1", "expected rejected item removed from queue count")
end

local function test_duplicate_refactoring_requests_advance_after_rejection()
  reset_state()
  neotest_mode = "pass"
  install_neotest()
  local lines = {
    "// Refactoring: extract helper",
    "// Refactoring: extract helper",
  }
  state.buf_lines[current_buf] = lines
  state.file_contents["/tmp/sample_test.dart"] = lines
  local bot = load_bot()
  bot.setup()
  bot.run_refactor()

  state.file_contents["/tmp/sample_test.dart"] = { "candidate" }
  state.job_calls[1].opts.on_exit(1, 0)
  popup_mapping(state.popup_calls[1], "r")()

  assert(#state.job_calls == 2, "expected next duplicate request to start after rejection")
  local prompt = arg_after(state.job_calls[2].cmd, "-p")
  assert(prompt:find("Line: 2", 1, true), "expected queue to skip rejected duplicate request")
end

local function test_closing_refactoring_review_rejects_candidate()
  reset_state()
  neotest_mode = "pass"
  install_neotest()
  local lines = { "// Refactoring: extract helper" }
  state.buf_lines[current_buf] = lines
  state.file_contents["/tmp/sample_test.dart"] = lines
  local bot = load_bot()
  bot.setup()
  bot.run_refactor()

  state.file_contents["/tmp/sample_test.dart"] = { "candidate" }
  state.job_calls[1].opts.on_exit(1, 0)
  vim.api.nvim_win_close(state.popup_calls[1].win, true)

  assert(state.file_contents["/tmp/sample_test.dart"][1] == lines[1], "expected closed review to restore disk")
  assert(not bot._is_running(), "expected closed final review to complete queue")
end

local function test_refactor_status_transitions_from_blue_to_red_or_green()
  reset_state()
  neotest_mode = "pass"
  install_neotest()
  state.buf_lines[current_buf] = { "// Refactoring: extract a helper" }
  local bot = load_bot()
  bot.setup()
  bot.run_refactor()

  local status = state.status_calls[1]
  assert(state.buffer_highlights[status.buf] == "TddBotStatusBlue", "expected blue status dot highlight")
  assert(state.lines_by_buf[status.buf][1] == "● 1", "expected blue status to show one pending refactoring")
  table.remove(state.deferred_activity, 1)()
  assert(state.buffer_highlights[status.buf] == "TddBotStatusBlueDim", "expected refactor dot to pulse blue")
  assert(state.lines_by_buf[status.buf][1] == "● 1", "expected blue status count to remain while pulsing")

  neotest_mode = "fail-results"
  state.job_calls[1].opts.on_exit(1, 0)
  popup_mapping(state.popup_calls[1], "a")()
  assert(state.buffer_highlights[status.buf] == "TddBotStatusRed",
    "expected broken refactoring verification to show red status")
  assert(state.lines_by_buf[status.buf][1] == "●", "expected failed refactoring status to hide pending count")

  reset_state()
  neotest_mode = "pass"
  install_neotest()
  state.buf_lines[current_buf] = { "// Refactoring: extract a helper" }
  bot = load_bot()
  bot.setup()
  bot.run_refactor()
  state.job_calls[1].opts.on_exit(1, 0)
  popup_mapping(state.popup_calls[1], "a")()
  assert(state.buffer_highlights[state.status_calls[1].buf] == "TddBotStatusGreen",
    "expected completed refactoring to show green status")
  assert(state.lines_by_buf[state.status_calls[1].buf][1] == "●",
    "expected completed refactoring status to hide pending count")
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
  assert(#state.status_calls == 0, "expected no status display when no refactoring comments present")
  assert(#state.notify_calls == 1, "expected no-comment pre-check notification")
  assert(state.notify_calls[1].msg:find("No refactoring found", 1, true),
    "expected no-comment notification to explain no refactoring was found")
  assert(state.notify_calls[1].msg:find("// Refactoring: <request>", 1, true),
    "expected no-comment notification to show refactoring comment format")
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

  assert(#state.closed_windows == 0, "expected status dot to remain visible after red pre-check")
  assert(#state.notify_calls == 0, "expected red pre-check to avoid notifications")
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
  state.file_contents["/tmp/sample_test.dart"] = pre_lines
  local bot = load_bot()
  bot.setup()
  bot.run_refactor()

  assert(#state.job_calls == 1, "expected first refactoring job to start once tests confirmed green")
  local status = state.status_calls[1]
  assert(state.lines_by_buf[status.buf][1] == "● 2", "expected both refactorings in initial pending count")

  -- Accepted first refactoring breaks tests.
  state.file_contents["/tmp/sample_test.dart"] = {
    "broken",
    "local y = 2",
    "// Refactoring: rename y to total",
  }
  neotest_mode = "fail-results"
  state.job_calls[1].opts.on_exit(1, 0)
  popup_mapping(state.popup_calls[1], "a")()

  assert(#state.job_calls == 1, "expected loop to stop, no second refactoring job started")
  assert(not bot._is_running(), "expected refactor loop to stop running after a revert")
  assert(state.buffer_highlights[status.buf] == "TddBotStatusRed", "expected failed refactoring to show red status")
  assert(state.lines_by_buf[status.buf][1] == "●", "expected red status to hide remaining pending count")

  local path = "/tmp/sample_test.dart"
  for i, line in ipairs(pre_lines) do
    assert(state.file_contents[path][i] == line, "expected file reverted to pre-refactoring content on disk")
    assert(state.lines_by_buf[current_buf][i] == line, "expected buffer reverted to pre-refactoring content")
  end

  assert(state.valid_windows[status.win], "expected status dot to remain visible after reverting")
  assert(#state.notify_calls == 0, "expected reverted refactor to avoid notifications")
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

local function test_clear_session_avoids_notification_when_nothing_to_clear()
  reset_state()
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.clear_session()

  assert(#state.notify_calls == 0, "expected session clearing to avoid notifications")
end

local function test_readme_guides_user_from_purpose_to_installation_and_keymaps()
  local file = assert(io.open("README.md", "r"))
  local readme = file:read("*a")
  file:close()

  local description = assert(readme:find("keeps a test%-driven development loop", 1, false),
    "expected README to describe plugin purpose")
  local installation = assert(readme:find("## Install with LazyVim", 1, true),
    "expected LazyVim installation section")
  local usage = assert(readme:find("## Use tdd%-bot", 1, false),
    "expected usage section")

  assert(description < installation and installation < usage,
    "expected README order: description, LazyVim installation, usage")
  assert(readme:find('"AlienEngineer/tdd%-bot%.nvim"', 1, false),
    "expected LazyVim plugin specification")
  assert(readme:find("<leader>tdd", 1, true), "expected run-tests keymap")
  assert(readme:find("<leader>tdc", 1, true), "expected clear-session keymap")
  assert(readme:find("<leader>tdr", 1, true), "expected refactor keymap")
  assert(readme:find("floating dot", 1, true), "expected TDD status indicator documentation")
end

local function test_repository_has_no_superpowers_docs()
  assert(vim.fn.isdirectory("docs/superpowers") == 0, "expected no superpowers documentation in repository")
end

local function test_ci_pipeline_tests_and_bumps_version_after_merged_pr()
  local file = assert(io.open(".github/workflows/ci.yml", "r"), "expected CI workflow")
  local workflow = file:read("*a")
  file:close()

  assert(workflow:find("pull_request:", 1, true), "expected CI to run for pull requests")
  assert(workflow:find("types: [opened, synchronize, reopened, closed]", 1, true),
    "expected CI to handle merged pull requests")
  assert(workflow:find("push:", 1, true), "expected CI to run for pushes")
  assert(workflow:find("workflow_dispatch:", 1, true), "expected CI to support manual runs")
  assert(workflow:find("contents: write", 1, true), "expected CI to allow version commits")
  assert(workflow:find("nvim --headless -u NONE -l tests/test_tdd_bot.lua", 1, true),
    "expected CI to run plugin behavior tests")
  assert(workflow:find("needs: test", 1, true), "expected version bump to wait for tests")
  assert(workflow:find("github.event.pull_request.merged == true", 1, true),
    "expected version bump only after merged pull requests")
  assert(workflow:find("ref: ${{ github.event.pull_request.base.ref }}", 1, true),
    "expected version bump to target merged base branch")
  assert(workflow:find("bump-plugin-version-${{ github.event.pull_request.base.ref }}", 1, true),
    "expected version bumps to serialize per base branch")
  assert(workflow:find('^local VERSION = "(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)"$', 1, true),
    "expected version declaration validation")
  assert(workflow:find('version_pattern="${version//./\\\\.}"', 1, true),
    "expected version declaration replacement to match literal dots")
  assert(workflow:find("10#$patch + 1", 1, true), "expected patch version increment")
  assert(workflow:find("chore: bump plugin version to ${{ steps.bump.outputs.version }}", 1, true),
    "expected version bump commit")
  assert(workflow:find('git push origin "HEAD:${{ github.event.pull_request.base.ref }}"', 1, true),
    "expected version bump pushed to merged base branch")
end

test_tdd_mapping_exists()
test_failing_run_starts_background_copilot()
test_failed_copilot_launch_stops_on_static_red_dot()
test_running_loop_pulses_single_status_dot()
test_tdd_loop_exposes_plugin_version()
test_passing_run_completes_loop()
test_status_dot_reflects_confirmed_tdd_results()
test_status_dot_recovers_after_manual_close()
test_failure_in_any_adapter_beats_passing_adapter()
test_stale_failure_from_prior_run_is_ignored()
test_buffer_lines_synced_from_disk_on_exit()
test_no_reload_when_mtime_unchanged()
test_applied_changes_open_in_diff_popup()
test_applied_changes_popup_closes_with_q_or_escape()
test_refactor_applied_changes_name_refactoring_in_popup()
test_applied_changes_do_not_use_notification()
test_no_notify_when_mtime_unchanged()
test_copilot_exit_avoids_progress_notification()
test_unresolved_copilot_report_avoids_notification()
test_rerun_after_copilot_exit()
test_retry_loop_fires_second_copilot_on_still_failing()
test_retry_loop_stops_when_passing()
test_failing_run_avoids_progress_notification()
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
test_refactor_queue_waits_for_acceptance_before_next_job()
test_refactor_rejection_restores_snapshot_and_advances_once()
test_duplicate_refactoring_requests_advance_after_rejection()
test_closing_refactoring_review_rejects_candidate()
test_refactor_status_transitions_from_blue_to_red_or_green()
test_refactor_no_comments_found()
test_refactor_aborts_when_tests_red()
test_refactor_reverts_when_refactoring_breaks_tests()
test_clear_session_removes_stored_uuid()
test_clear_session_avoids_notification_when_nothing_to_clear()
test_readme_guides_user_from_purpose_to_installation_and_keymaps()
test_repository_has_no_superpowers_docs()
test_ci_pipeline_tests_and_bumps_version_after_merged_pr()

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
vim.api.nvim_create_buf = real.nvim_create_buf
vim.api.nvim_open_win = real.nvim_open_win
vim.api.nvim_buf_is_valid = real.nvim_buf_is_valid
vim.api.nvim_win_is_valid = real.nvim_win_is_valid
vim.api.nvim_win_set_config = real.nvim_win_set_config
vim.api.nvim_win_close = real.nvim_win_close
vim.api.nvim_create_autocmd = real.nvim_create_autocmd
vim.api.nvim_set_hl = real.nvim_set_hl
vim.api.nvim_buf_clear_namespace = real.nvim_buf_clear_namespace
vim.api.nvim_buf_add_highlight = real.nvim_buf_add_highlight
vim.api.nvim_set_option_value = real.nvim_set_option_value
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
