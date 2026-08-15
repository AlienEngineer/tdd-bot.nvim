local M = {}
local VERSION = "0.1.13"

M.version = VERSION

local config = {
  keymap = "<leader>tdd",
  clear_keymap = "<leader>tdc",
  refactor_keymap = "<leader>tdr",
  result_timeout_ms = 120000,
  poll_interval_ms = 200,
  notification_timeout_ms = 3000,
  max_retries = 5,
  copilot_cmd = {
    "copilot",
    "--allow-all-tools",
    "--allow-all-urls",
    "--no-custom-instructions",
    "--disable-builtin-mcps",
  },
}

local last_failure = nil
local copilot_job_id = nil
local loop_running = false
local session_ids = {}
local status_bufnr = nil
local status_winid = nil
local status_state = nil

local status_highlights = {
  red = "TddBotStatusRed",
  green = "TddBotStatusGreen",
  blue = "TddBotStatusBlue",
}

local function status_window_config()
  return {
    relative = "editor",
    width = 1,
    height = 1,
    col = math.max(vim.o.columns - 3, 0),
    row = 1,
    style = "minimal",
    focusable = false,
    zindex = 50,
  }
end

local function set_status(state_name)
  local highlight = status_highlights[state_name]
  if not highlight then
    return
  end

  vim.api.nvim_set_hl(0, "TddBotStatusRed", { fg = "#ff0000" })
  vim.api.nvim_set_hl(0, "TddBotStatusGreen", { fg = "#00cc44" })
  vim.api.nvim_set_hl(0, "TddBotStatusBlue", { fg = "#3399ff" })

  if not status_bufnr or not vim.api.nvim_buf_is_valid(status_bufnr) then
    status_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = status_bufnr })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = status_bufnr })
    vim.api.nvim_set_option_value("swapfile", false, { buf = status_bufnr })
  end

  vim.api.nvim_buf_set_lines(status_bufnr, 0, -1, false, { "●" })
  vim.api.nvim_buf_clear_namespace(status_bufnr, -1, 0, -1)
  vim.api.nvim_buf_add_highlight(status_bufnr, -1, highlight, 0, 0, -1)

  local window_config = status_window_config()
  if status_winid and vim.api.nvim_win_is_valid(status_winid) then
    vim.api.nvim_win_set_config(status_winid, window_config)
  else
    status_winid = vim.api.nvim_open_win(status_bufnr, false, window_config)
  end

  status_state = state_name
end

local function now_ms()
  return (vim.uv or vim.loop).now()
end

math.randomseed(os.time() + (now_ms() % 100000))

local function generate_uuid()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return (template:gsub("[xy]", function(c)
    local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
    return string.format("%x", v)
  end))
end

local function get_or_create_session_id(file_path)
  local existing = session_ids[file_path]
  if existing then
    return existing
  end
  local uuid = generate_uuid()
  session_ids[file_path] = uuid
  return uuid
end

local function notify_info(message)
  vim.notify("[tdd-bot] " .. message, vim.log.levels.INFO, { timeout = config.notification_timeout_ms })
end

local function notify_error(message)
  vim.notify("[tdd-bot] " .. message, vim.log.levels.ERROR)
end

local function show_applied_changes(path, diff)
  local lines = vim.split(diff, "\n", { plain = true })
  if #lines == 0 then
    lines = { "Copilot changed this file." }
  end

  local width = math.min(math.max(60, vim.fn.strdisplaywidth(lines[1])), math.floor(vim.o.columns * 0.8))
  for _, line in ipairs(lines) do
    width = math.min(math.max(width, vim.fn.strdisplaywidth(line)), math.floor(vim.o.columns * 0.8))
  end
  local height = math.min(#lines, math.floor(vim.o.lines * 0.7))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("filetype", "diff", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " tdd-bot: Applied changes to " .. vim.fn.fnamemodify(path, ":t") .. " ",
    title_pos = "center",
  })
end

local function file_mtime(path)
  local stat = (vim.uv or vim.loop).fs_stat(path)
  return stat and stat.mtime and stat.mtime.sec or 0
end

local function reload_changed_buffers(snapshots)
  local changed = {}
  for path, snap in pairs(snapshots) do
    local new_mtime = file_mtime(path)
    if new_mtime ~= snap.mtime then
      changed[#changed + 1] = path
      local new_lines = vim.fn.readfile(path)
      vim.api.nvim_buf_set_lines(snap.bufnr, 0, -1, false, new_lines)
      local old_text = table.concat(snap.lines, "\n")
      local new_text = table.concat(new_lines, "\n")
      local diff = vim.diff(old_text, new_text, { result_type = "unified", ctxlen = 3 }) or ""
      show_applied_changes(path, diff)
    end
  end
  return changed
end

local function snapshot_open_buffers()
  local snaps = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local path = vim.api.nvim_buf_get_name(bufnr)
      if path and path ~= "" then
        snaps[path] = {
          bufnr = bufnr,
          mtime = file_mtime(path),
          lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
        }
      end
    end
  end
  return snaps
end

local function find_project_root(file_path)
  local dir = vim.fn.fnamemodify(file_path, ":p:h")
  local markers = { ".git", "pubspec.yaml", "package.json", "go.mod", "Cargo.toml", "pom.xml" }
  local current = dir
  for _ = 1, 20 do
    for _, marker in ipairs(markers) do
      local candidate = current .. "/" .. marker
      local stat = (vim.uv or vim.loop).fs_stat(candidate)
      if stat then
        return current
      end
    end
    local parent = vim.fn.fnamemodify(current, ":h")
    if parent == current then break end
    current = parent
  end
  return dir
end

local function build_copilot_prompt(context)
  return table.concat({
    "Fix the failing test with minimal code changes.",
    "Apply the fix directly to the file using your tools.",
    "When you can't solve the failing test, audit the issue and provide a detailed report with what went wrong.",
    "End an unresolved-test report with the exact marker `TDD_BOT_REPORT:` followed by the report.",
    "File: " .. context.file_path,
    "Test: " .. context.test_id,
    "Failure output:",
    context.message,
  }, "\n")
end

local function build_refactor_prompt(context)
  return table.concat({
    "Apply the following refactoring exactly as described, with minimal unrelated changes.",
    "Apply the change directly to the file using your tools.",
    "Once applied, remove the refactoring comment that requested it.",
    "File: " .. context.file_path,
    "Line: " .. tostring(context.line),
    "Refactoring: " .. context.text,
  }, "\n")
end

local function find_refactoring_comments(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local refactorings = {}
  for i, line in ipairs(lines) do
    local text = line:match("//%s*[Rr]efactoring:%s*(.+)$")
    if text then
      text = text:gsub("%s+$", "")
      if text ~= "" then
        refactorings[#refactorings + 1] = { line = i, text = text }
      end
    end
  end
  return refactorings
end

local function unresolved_report(output)
  local marker_start, marker_end = output:find("TDD_BOT_REPORT:%s*")
  if not marker_start then
    return nil
  end

  local report = output:sub(marker_end + 1):gsub("^%s+", ""):gsub("%s+$", "")
  return report ~= "" and report or "Copilot marked this test unresolved without a report."
end

local function build_copilot_cmd(context, prompt)
  local project_root = find_project_root(context.file_path)
  local session_id = get_or_create_session_id(context.file_path)
  local cmd = {}
  for _, arg in ipairs(config.copilot_cmd) do
    cmd[#cmd + 1] = arg
  end
  cmd[#cmd + 1] = "--add-dir"
  cmd[#cmd + 1] = project_root
  cmd[#cmd + 1] = "--deny-tool=shell(rm:*)"
  cmd[#cmd + 1] = "--deny-tool=shell(sudo:*)"
  cmd[#cmd + 1] = "-p"
  cmd[#cmd + 1] = prompt
  cmd[#cmd + 1] = "--session-id"
  cmd[#cmd + 1] = session_id
  return cmd
end

local function first_failed_result(results)
  for test_id, result in pairs(results or {}) do
    if result and result.status == "failed" then
      local message = nil
      if result.errors and result.errors[1] then
        local first_error = result.errors[1]
        if type(first_error) == "string" then
          message = first_error
        elseif type(first_error) == "table" then
          message = first_error.message or first_error.output or vim.inspect(first_error)
        end
      end
      return test_id, message or "No failure message provided."
    end
  end
  return nil, nil
end

local function all_results_passed(results)
  if not results or type(results) ~= "table" then
    return false
  end
  local has_results = false
  for _, result in pairs(results) do
    if result then
      has_results = true
      if result.status ~= "passed" and result.status ~= "skipped" then
        return false
      end
    end
  end
  return has_results
end

local function has_any_results(results)
  if not results or type(results) ~= "table" then
    return false
  end
  return next(results) ~= nil
end

local function fetch_results_for_file(neotest, adapter_id, file_path)
  local ok, results = pcall(neotest.state.results, adapter_id, file_path)
  if ok and type(results) == "table" then
    return results
  end
  ok, results = pcall(neotest.state.results, adapter_id)
  if ok and type(results) == "table" then
    return results
  end
  return {}
end

local function first_failed_quickfix(file_path)
  local ok, items = pcall(vim.fn.getqflist)
  if not ok or type(items) ~= "table" then
    return nil
  end
  local target = vim.fn.fnamemodify(file_path, ":p")
  for _, item in ipairs(items) do
    local item_file = item.filename
    if (item_file == nil or item_file == "") and item.bufnr and item.bufnr > 0 then
      item_file = vim.api.nvim_buf_get_name(item.bufnr)
    end
    if item_file and item_file ~= "" then
      item_file = vim.fn.fnamemodify(item_file, ":p")
    end
    if item_file == target and ((item.type or "") == "" or (item.type or "") == "E") then
      return item
    end
  end
  for _, item in ipairs(items) do
    if (item.type or "") == "E" then
      return item
    end
  end
  return nil
end

local function capture_failure_for_file(file_path, done)
  local ok, neotest = pcall(require, "neotest")
  if not ok then
    notify_error("neotest not found.")
    done(nil)
    return
  end

  last_failure = nil
  neotest.run.run(file_path)

  local started_at = now_ms()
  local saw_running = false
  local poll_count = 0

  local function finish(failure, counts)
    last_failure = failure
    done(failure, counts)
  end

  local function inspect_results()
    poll_count = poll_count + 1
    -- Neotest's status/results cache is global and cumulative across runs; on
    -- the very first poll it may still reflect the previous invocation before
    -- this run's async `run` event has fired. Wait one extra cycle so stale
    -- failures/passes from a prior session aren't mistaken for this run's result.
    local trust_results = poll_count > 1

    local adapter_ids = neotest.state.adapter_ids() or {}
    local has_running = false
    local has_failed = false
    local total_passed = 0
    local total_failed = 0
    local total_skipped = 0
    local all_adapters_passed = true
    local has_results = false

    for _, adapter_id in ipairs(adapter_ids) do
      if neotest.state.status_counts then
        local ok_counts, counts = pcall(neotest.state.status_counts, adapter_id, { buffer = vim.api.nvim_get_current_buf() })
        if ok_counts and counts and type(counts.running) == "number" and counts.running > 0 then
          has_running = true
          saw_running = true
        end
        if ok_counts and counts and type(counts.failed) == "number" and counts.failed > 0 then
          has_failed = true
        end
        if ok_counts and counts then
          if type(counts.passed) == "number" then
            total_passed = total_passed + counts.passed
          end
          if type(counts.failed) == "number" then
            total_failed = total_failed + counts.failed
          end
          if type(counts.skipped) == "number" then
            total_skipped = total_skipped + counts.skipped
          end
        end
      end

      local results = fetch_results_for_file(neotest, adapter_id, file_path)
      local test_id, failure_message = first_failed_result(results)
      if test_id and trust_results then
        finish({
          file_path = file_path,
          test_id = test_id,
          message = failure_message,
          updated_at = now_ms(),
        }, { passed = total_passed, failed = total_failed })
        return
      end

      if all_results_passed(results) then
        has_results = true
      elseif has_any_results(results) then
        all_adapters_passed = false
      end
    end

    if has_failed and trust_results and (saw_running or not has_running) then
      local qf = first_failed_quickfix(file_path)
      finish({
        file_path = file_path,
        test_id = qf and ("line " .. tostring(qf.lnum or "?")) or "<unknown>",
        message = qf and (qf.text or "Tests failed.") or "Tests failed. No failure output found.",
        updated_at = now_ms(),
      }, { passed = total_passed, failed = total_failed })
      return
    end

    if saw_running and not has_running and trust_results then
      finish(nil, { passed = total_passed, failed = total_failed })
      return
    end

    if has_results and all_adapters_passed and not has_running and trust_results then
      finish(nil, { passed = total_passed, failed = total_failed })
      return
    end

    if not has_failed and not has_running and (total_passed > 0 or total_skipped > 0) and trust_results then
      finish(nil, { passed = total_passed, failed = total_failed })
      return
    end

    if now_ms() - started_at < config.result_timeout_ms then
      vim.defer_fn(inspect_results, config.poll_interval_ms)
    else
      finish(nil, { passed = total_passed, failed = total_failed })
    end
  end

  vim.defer_fn(inspect_results, config.poll_interval_ms)
end

local function run_copilot_job(context, prompt, start_message, done_label, on_done)
  if vim.fn.executable("copilot") ~= 1 then
    notify_error("copilot binary not found.")
    on_done(false)
    return
  end
  if copilot_job_id then
    notify_error("copilot job already running.")
    on_done(false)
    return
  end

  notify_info(start_message)

  local job_started_at = now_ms()
  local snapshots = snapshot_open_buffers()
  local cwd = find_project_root(context.file_path)
  local accumulated_out = {}
  local accumulated_err = {}
  copilot_job_id = vim.fn.jobstart(build_copilot_cmd(context, prompt), {
    cwd = cwd,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      for _, line in ipairs(data or {}) do
        if line and line ~= "" then
          accumulated_out[#accumulated_out + 1] = line
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data or {}) do
        if line and line ~= "" then
          accumulated_err[#accumulated_err + 1] = line
        end
      end
    end,
    on_exit = function(_, code)
      copilot_job_id = nil
      if code ~= 0 and #accumulated_err > 0 then
        notify_error("copilot error (code " .. code .. "): " .. table.concat(accumulated_err, " | "):sub(1, 200))
      end
      local report = unresolved_report(table.concat(accumulated_out, "\n"))
      if report then
        vim.notify("[tdd-bot] Copilot unresolved-test report:\n" .. report, vim.log.levels.WARN)
      end
      local elapsed_seconds = (now_ms() - job_started_at) / 1000
      notify_info(string.format("%s took %.1fs", done_label, elapsed_seconds))
      reload_changed_buffers(snapshots)
      on_done(true)
    end,
  })
end

local function start_copilot_background(failure, on_done)
  local prompt = build_copilot_prompt(failure)
  run_copilot_job(
    failure,
    prompt,
    "Implementing fix for " .. vim.fn.fnamemodify(failure.file_path, ":t") .. " ...",
    "Copilot fix",
    on_done)
end

local function start_copilot_refactor(refactor, on_done)
  local prompt = build_refactor_prompt(refactor)
  run_copilot_job(
    refactor,
    prompt,
    string.format("Applying refactoring for %s: %s", vim.fn.fnamemodify(refactor.file_path, ":t"), refactor.text),
    "Copilot refactor",
    on_done)
end

local function run_fix_cycle(file_path, attempt)
  capture_failure_for_file(file_path, function(failure, counts)
    local passed = counts and counts.passed or 0
    local failed = counts and counts.failed or 0
    if failed > 0 and failure then
      notify_info(string.format(
        "Test run result: %d passed, %d failed.\nFailing test: %s\nOutput: %s",
        passed, failed, tostring(failure.test_id), tostring(failure.message)))
    else
      notify_info(string.format("Test run result: %d passed, %d failed.", passed, failed))
    end
    if not failure then
      loop_running = false
      set_status("green")
      notify_info(string.format("All tests passing. (%d passed, %d failed)", passed, failed))
      return
    end
    set_status("red")
    if attempt >= config.max_retries then
      loop_running = false
      notify_error(string.format(
        "Max retries exhausted. Giving up. (%d passed, %d failed)\nLast failure (%s): %s",
        passed, failed, tostring(failure.test_id), tostring(failure.message)))
      return
    end
    start_copilot_background(failure, function(launched)
      if launched then
        run_fix_cycle(file_path, attempt + 1)
      else
        loop_running = false
      end
    end)
  end)
end

local function revert_to_snapshot(file_path, bufnr, lines)
  vim.fn.writefile(lines, file_path)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

local function run_refactor_cycle(file_path, bufnr, refactorings, index)
  if index > #refactorings then
    loop_running = false
    set_status("green")
    notify_info(string.format("Refactor loop complete. Applied %d refactoring(s).", #refactorings))
    return
  end

  local refactor = refactorings[index]
  local pre_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  start_copilot_refactor({
    file_path = file_path,
    line = refactor.line,
    text = refactor.text,
  }, function(launched)
    if not launched then
      loop_running = false
      return
    end

    notify_info(string.format("Verifying tests after refactoring %d/%d...", index, #refactorings))
    capture_failure_for_file(file_path, function(failure, counts)
      local passed = counts and counts.passed or 0
      local failed = counts and counts.failed or 0
      if failure then
        set_status("red")
        revert_to_snapshot(file_path, bufnr, pre_lines)
        loop_running = false
        notify_error(string.format(
          "Refactoring %d/%d broke tests, reverted to previous state. (%d passed, %d failed)\nRefactoring: %s\nFailing test: %s\nOutput: %s",
          index, #refactorings, passed, failed, refactor.text, tostring(failure.test_id), tostring(failure.message)))
        return
      end
      run_refactor_cycle(file_path, bufnr, refactorings, index + 1)
    end)
  end)
end

function M.run_tdd()
  local file_path = vim.api.nvim_buf_get_name(0)
  if file_path == nil or file_path == "" then
    notify_error("current buffer has no file path.")
    return
  end

  if loop_running or copilot_job_id then
    notify_error("TDD loop already running.")
    return
  end

  loop_running = true
  notify_info("Starting TDD loop (tdd-bot v" .. VERSION .. ").")
  run_fix_cycle(file_path, 0)
end

function M.run_refactor()
  local file_path = vim.api.nvim_buf_get_name(0)
  if file_path == nil or file_path == "" then
    notify_error("current buffer has no file path.")
    return
  end

  if loop_running or copilot_job_id then
    notify_error("TDD loop already running.")
    return
  end

  local refactorings = find_refactoring_comments(vim.api.nvim_get_current_buf())
  if #refactorings == 0 then
    notify_info("No refactoring comments found (expected `// Refactoring: <what to do>`).")
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  loop_running = true
  notify_info("Checking tests are passing before starting refactor loop...")
  capture_failure_for_file(file_path, function(failure, counts)
    local passed = counts and counts.passed or 0
    local failed = counts and counts.failed or 0
    if failure then
      loop_running = false
      set_status("red")
      notify_error(string.format(
        "Refactoring aborted: tests are red, can only refactor in a green state. (%d passed, %d failed)\nFailing test: %s\nOutput: %s",
        passed, failed, tostring(failure.test_id), tostring(failure.message)))
      return
    end
    notify_info(string.format(
      "Tests passing (%d passed). Starting refactor loop (%d refactoring(s)) (tdd-bot v%s).",
      passed, #refactorings, VERSION))
    set_status("blue")
    run_refactor_cycle(file_path, bufnr, refactorings, 1)
  end)
end

function M.clear_session()
  local file_path = vim.api.nvim_buf_get_name(0)
  if file_path == nil or file_path == "" then
    notify_error("current buffer has no file path.")
    return
  end

  if session_ids[file_path] then
    session_ids[file_path] = nil
    notify_info("Cleared stored session for " .. vim.fn.fnamemodify(file_path, ":t") .. ". Next run starts fresh.")
  else
    notify_info("No stored session for " .. vim.fn.fnamemodify(file_path, ":t") .. "; nothing to clear.")
  end
end

function M.setup(opts)
  if type(opts) == "table" then
    if type(opts.keymap) == "string" and opts.keymap ~= "" then
      config.keymap = opts.keymap
    end
    if type(opts.clear_keymap) == "string" and opts.clear_keymap ~= "" then
      config.clear_keymap = opts.clear_keymap
    end
    if type(opts.refactor_keymap) == "string" and opts.refactor_keymap ~= "" then
      config.refactor_keymap = opts.refactor_keymap
    end
    if type(opts.result_timeout_ms) == "number" and opts.result_timeout_ms > 0 then
      config.result_timeout_ms = math.floor(opts.result_timeout_ms)
    end
    if type(opts.poll_interval_ms) == "number" and opts.poll_interval_ms > 0 then
      config.poll_interval_ms = math.floor(opts.poll_interval_ms)
    end
    if type(opts.notification_timeout_ms) == "number" and opts.notification_timeout_ms >= 0 then
      config.notification_timeout_ms = math.floor(opts.notification_timeout_ms)
    end
    if type(opts.max_retries) == "number" and opts.max_retries >= 0 then
      config.max_retries = math.floor(opts.max_retries)
    end
    if type(opts.copilot_cmd) == "table" and #opts.copilot_cmd > 0 then
      config.copilot_cmd = opts.copilot_cmd
    end
  end

  vim.keymap.set("n", config.keymap, M.run_tdd, { desc = "tdd-bot: run tests and background fix on failure" })
  vim.keymap.set("n", config.clear_keymap, M.clear_session, { desc = "tdd-bot: clear stored copilot session for current file" })
  vim.keymap.set("n", config.refactor_keymap, M.run_refactor, { desc = "tdd-bot: apply // Refactoring: comments via copilot" })
end

function M._get_last_failure()
  return last_failure
end

function M._generate_uuid()
  return generate_uuid()
end

function M._get_session_id(file_path)
  return session_ids[file_path]
end

function M._is_running()
  return loop_running
end

return M
