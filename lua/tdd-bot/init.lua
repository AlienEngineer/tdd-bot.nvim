local M = {}
local VERSION = "0.1.14"

M.version = VERSION

local config = {
  keymap = "<leader>tdd",
  clear_keymap = "<leader>tdc",
  refactor_keymap = "<leader>tdr",
  model_keymap = "<leader>tdm",
  result_timeout_ms = 120000,
  poll_interval_ms = 200,
  max_retries = 5,
  max_refactor_retries = 5,
  copilot_cmd = {
    "copilot",
  },
}

-- `--allow-all-tools` is required by Copilot CLI prompt mode. The available-tools
-- filter below makes that approval apply only to these local project tools.
local COPILOT_AVAILABLE_TOOLS = "view,glob,rg,apply_patch,bash"
local COPILOT_SECURITY_ARGS = {
  "--no-custom-instructions",
  "--disable-builtin-mcps",
  "--disallow-temp-dir",
  "--available-tools=" .. COPILOT_AVAILABLE_TOOLS,
  "--deny-tool=url",
  "--deny-tool=shell(rm:*)",
  "--deny-tool=shell(sudo:*)",
  "--allow-all-tools",
}
local SECURITY_OPTION_VALUES = {
  ["--add-dir"] = true,
  ["--add-github-mcp-tool"] = true,
  ["--add-github-mcp-toolset"] = true,
  ["--additional-mcp-config"] = true,
  ["--agent"] = true,
  ["--allow-tool"] = true,
  ["--allow-url"] = true,
  ["--attachment"] = true,
  ["--available-tools"] = true,
  ["--deny-tool"] = true,
  ["--deny-url"] = true,
  ["--disable-mcp-server"] = true,
  ["--excluded-tools"] = true,
  ["--extension-sdk-path"] = true,
  ["--model"] = true,
  ["--plugin-dir"] = true,
  ["--prompt"] = true,
  ["--resume"] = true,
  ["--session-id"] = true,
  ["-C"] = true,
  ["-p"] = true,
  ["-r"] = true,
}
local SECURITY_OPTION_PREFIXES = {
  "--add-dir=",
  "--add-github-mcp-tool=",
  "--add-github-mcp-toolset=",
  "--additional-mcp-config=",
  "--agent=",
  "--allow-tool=",
  "--allow-url=",
  "--attachment=",
  "--available-tools=",
  "--deny-tool=",
  "--deny-url=",
  "--disable-mcp-server=",
  "--excluded-tools=",
  "--extension-sdk-path=",
  "--model=",
  "--plugin-dir=",
  "--prompt=",
  "--resume=",
  "--session-id=",
}
local SECURITY_FLAGS = {
  ["--allow-all"] = true,
  ["--allow-all-mcp-server-instructions"] = true,
  ["--allow-all-paths"] = true,
  ["--allow-all-tools"] = true,
  ["--allow-all-urls"] = true,
  ["--autopilot"] = true,
  ["--disable-builtin-mcps"] = true,
  ["--disallow-temp-dir"] = true,
  ["--enable-all-github-mcp-tools"] = true,
  ["--no-custom-instructions"] = true,
  ["--yolo"] = true,
}

local last_failure = nil
local copilot_job_id = nil
local loop_running = false
local tdd_buffer_lock = nil
local session_ids = {}
local status_bufnr = nil
local status_winid = nil
local status_state = nil
local status_pulse_state = nil
local status_pulse_bright = true
local status_pulse_generation = 0
local status_detail = nil
local suite_total = nil
local preferred_model = "auto"
local saved_models = { "auto" }
local tdd_mode_enabled = false
local tdd_mode_augroup = nil
local tdd_run_generation = 0

local status_highlights = {
  red = { bright = "TddBotStatusRed", dim = "TddBotStatusRedDim" },
  green = { bright = "TddBotStatusGreen", dim = "TddBotStatusGreenDim" },
  blue = { bright = "TddBotStatusBlue", dim = "TddBotStatusBlueDim" },
}

local function status_window_config(lines)
  local width = 1
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  return {
    relative = "editor",
    width = width,
    height = #lines,
    col = math.max(vim.o.columns - width - 2, 0),
    row = 1,
    style = "minimal",
    focusable = false,
    zindex = 50,
  }
end

local function clear_status()
  status_pulse_generation = status_pulse_generation + 1
  status_pulse_state = nil
  status_pulse_bright = true
  status_detail = nil
  suite_total = nil
  status_state = nil

  if status_winid and vim.api.nvim_win_is_valid(status_winid) then
    vim.api.nvim_win_close(status_winid, true)
  end
  status_winid = nil
  status_bufnr = nil
end

local function render_status(state_name, bright, detail)
  local highlights = status_highlights[state_name]
  if not highlights then
    return
  end
  local lines = { "● " .. (tdd_mode_enabled and "On" or "Off") }
  if state_name == "blue" and type(detail) == "number" and detail > 0 then
    lines[1] = string.format("%s %d", lines[1], detail)
  elseif suite_total then
    lines[1] = string.format("%s %d", lines[1], suite_total)
  end
  if type(detail) == "table" and detail.kind == "suite" then
    if detail.failed > 0 then
      lines[2] = string.format("%d/%d ✗", detail.failed, detail.total)
    elseif detail.complete then
      lines[2] = string.format("%d ✓", detail.total)
    elseif detail.total > 0 then
      lines[2] = string.format("%s/%d...", detail.completed > 0 and detail.completed or "--", detail.total)
    else
      lines[2] = "--/--"
    end
  end

  vim.api.nvim_set_hl(0, "TddBotStatusRed", { fg = "#ff0000" })
  vim.api.nvim_set_hl(0, "TddBotStatusRedDim", { fg = "#802222" })
  vim.api.nvim_set_hl(0, "TddBotStatusGreen", { fg = "#00cc44" })
  vim.api.nvim_set_hl(0, "TddBotStatusGreenDim", { fg = "#287a40" })
  vim.api.nvim_set_hl(0, "TddBotStatusBlue", { fg = "#3399ff" })
  vim.api.nvim_set_hl(0, "TddBotStatusBlueDim", { fg = "#285b8f" })

  if not status_bufnr or not vim.api.nvim_buf_is_valid(status_bufnr) then
    status_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = status_bufnr })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = status_bufnr })
    vim.api.nvim_set_option_value("swapfile", false, { buf = status_bufnr })
  end

  vim.api.nvim_buf_set_lines(status_bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(status_bufnr, -1, 0, -1)
  for line = 0, #lines - 1 do
    vim.api.nvim_buf_add_highlight(status_bufnr, -1, bright and highlights.bright or highlights.dim, line, 0, -1)
  end

  local window_config = status_window_config(lines)
  if status_winid and vim.api.nvim_win_is_valid(status_winid) then
    vim.api.nvim_win_set_config(status_winid, window_config)
  else
    status_winid = vim.api.nvim_open_win(status_bufnr, false, window_config)
  end

  status_state = state_name
end

local function set_status(state_name, detail)
  if not status_highlights[state_name] then
    return
  end
  status_pulse_generation = status_pulse_generation + 1
  status_pulse_state = nil
  status_pulse_bright = true
  status_detail = detail
  if type(detail) == "table" and detail.kind == "suite" then
    suite_total = detail.total > 0 and detail.total or nil
  end
  render_status(state_name, true, detail)
end

local function start_status_pulse(state_name, detail)
  if not status_highlights[state_name] then
    return
  end
  status_detail = detail
  if type(detail) == "table" and detail.kind == "suite" then
    suite_total = detail.total > 0 and detail.total or nil
  end
  if status_pulse_state == state_name then
    render_status(state_name, status_pulse_bright, detail)
    return
  end

  status_pulse_generation = status_pulse_generation + 1
  status_pulse_state = state_name
  status_pulse_bright = true
  local generation = status_pulse_generation
  render_status(state_name, true, detail)

  local function pulse()
    if generation ~= status_pulse_generation or status_pulse_state ~= state_name then
      return
    end
    status_pulse_bright = not status_pulse_bright
    render_status(state_name, status_pulse_bright, status_detail)
    vim.defer_fn(pulse, 500)
  end

  vim.defer_fn(pulse, 500)
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

local function notify_terminal_failure(message)
  vim.notify("[tdd-bot] " .. message, vim.log.levels.ERROR)
end

local function is_valid_buffer(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr)
end

local function acquire_tdd_buffer_lock(bufnr)
  if not is_valid_buffer(bufnr) then
    return
  end
  tdd_buffer_lock = {
    bufnr = bufnr,
    modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr }),
  }
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
end

local function release_tdd_buffer_lock()
  local lock = tdd_buffer_lock
  tdd_buffer_lock = nil
  if lock and is_valid_buffer(lock.bufnr) then
    vim.api.nvim_set_option_value("modifiable", lock.modifiable, { buf = lock.bufnr })
  end
end

local function with_tdd_buffer_writable(bufnr, callback)
  local lock = tdd_buffer_lock
  if not lock or lock.bufnr ~= bufnr then
    return callback()
  end
  if not is_valid_buffer(bufnr) then
    return
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  local result = callback()
  if tdd_buffer_lock == lock and is_valid_buffer(bufnr) then
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  end
  return result
end

local function finish_loop(status, detail)
  loop_running = false
  release_tdd_buffer_lock()
  if status then
    set_status(status, detail)
  end
end

local function show_applied_changes(path, diff, work_label)
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

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " tdd-bot: " .. work_label .. " - Applied changes to " .. vim.fn.fnamemodify(path, ":t") .. " ",
    title_pos = "center",
  })

  local function close_popup()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "q", close_popup, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", close_popup, { buffer = buf, silent = true })
end

local function same_lines(left, right)
  if #left ~= #right then
    return false
  end
  for index, line in ipairs(left) do
    if line ~= right[index] then
      return false
    end
  end
  return true
end

local function show_refactoring_review(path, diff, work_label, on_accept, on_reject)
  local lines = vim.split(diff, "\n", { plain = true })
  if #lines == 0 then
    lines = { "Copilot made no textual changes." }
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

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " tdd-bot: review " .. work_label .. " for " .. vim.fn.fnamemodify(path, ":t") .. " [a]ccept [r]eject ",
    title_pos = "center",
  })

  local decided = false
  local function decide(callback)
    if decided then
      return
    end
    decided = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    callback()
  end

  vim.keymap.set("n", "a", function() decide(on_accept) end, { buffer = buf, silent = true })
  vim.keymap.set("n", "r", function() decide(on_reject) end, { buffer = buf, silent = true })
  vim.keymap.set("n", "q", function() decide(on_reject) end, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", function() decide(on_reject) end, { buffer = buf, silent = true })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function() decide(on_reject) end,
  })
end

local function file_mtime(path)
  local stat = (vim.uv or vim.loop).fs_stat(path)
  return stat and stat.mtime and stat.mtime.sec or 0
end

local function reload_changed_buffers(snapshots, work_label)
  local changed = {}
  for path, snap in pairs(snapshots) do
    local new_mtime = file_mtime(path)
    if new_mtime ~= snap.mtime then
      changed[#changed + 1] = path
      local new_lines = vim.fn.readfile(path)
      with_tdd_buffer_writable(snap.bufnr, function()
        vim.api.nvim_buf_set_lines(snap.bufnr, 0, -1, false, new_lines)
      end)
      local old_text = table.concat(snap.lines, "\n")
      local new_text = table.concat(new_lines, "\n")
      local diff = vim.diff(old_text, new_text, { result_type = "unified", ctxlen = 3 }) or ""
      show_applied_changes(path, diff, work_label)
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
      if (vim.uv or vim.loop).fs_stat(current .. "/" .. marker) then
        return current
      end
    end
    local parent = vim.fn.fnamemodify(current, ":h")
    if parent == current then break end
    current = parent
  end
  return dir
end

local function is_project_file(root, path)
  return path:sub(1, #root + 1) == root .. "/"
    and not path:find("/.git/", 1, true)
    and not path:find("/node_modules/", 1, true)
end

local function snapshot_workspace(root)
  local snapshot = {}
  for _, path in ipairs(vim.fn.globpath(root, "**/*", false, true)) do
    local stat = (vim.uv or vim.loop).fs_stat(path)
    if stat and stat.type == "file" and is_project_file(root, path) then
      snapshot[path] = { exists = true, lines = vim.fn.readfile(path) }
    end
  end
  return snapshot
end

local function file_extension(path)
  return path:match("%.([^./]+)$") or ""
end

local function is_refactor_file(path, extension)
  return not path:find("/build/", 1, true) and file_extension(path) == extension
end

local function workspace_candidate(root, snapshot)
  local current, paths, changes = snapshot_workspace(root), {}, {}
  for path in pairs(snapshot) do paths[path] = true end
  for path in pairs(current) do paths[path] = true end
  for path in pairs(paths) do
    local before, after = snapshot[path] or { exists = false, lines = {} }, current[path] or { exists = false, lines = {} }
    if before.exists ~= after.exists or not same_lines(before.lines, after.lines) then
      changes[path] = { before = before, after = after }
    end
  end
  return changes
end

local function partition_workspace_candidate(changes, extension)
  local allowed, excluded = {}, {}
  for path, change in pairs(changes) do
    if is_refactor_file(path, extension) then
      allowed[path] = change
    else
      excluded[path] = change
    end
  end
  return allowed, excluded
end

local function candidate_diff(changes)
  local paths, parts = {}, {}
  for path in pairs(changes) do paths[#paths + 1] = path end
  table.sort(paths)
  for _, path in ipairs(paths) do
    local change = changes[path]
    local diff = vim.diff(table.concat(change.before.lines, "\n"), table.concat(change.after.lines, "\n"), { result_type = "unified", ctxlen = 3 }) or ""
    parts[#parts + 1], parts[#parts + 1] = "--- " .. path, "+++ " .. path
    if diff ~= "" then parts[#parts + 1] = diff end
  end
  return table.concat(parts, "\n")
end

local function merge_candidate_changes(original, additions)
  for path, addition in pairs(additions) do
    local existing = original[path]
    if existing then
      existing.after = addition.after
      if existing.before.exists == existing.after.exists and same_lines(existing.before.lines, existing.after.lines) then
        original[path] = nil
      end
    else
      original[path] = addition
    end
  end
end

local function buffers_by_path()
  local buffers = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local path = vim.api.nvim_buf_get_name(bufnr)
      if path and path ~= "" then
        buffers[path] = bufnr
      end
    end
  end
  return buffers
end

local function sync_candidate_buffers(changes)
  local buffers = buffers_by_path()
  for path, change in pairs(changes) do
    if buffers[path] then
      with_tdd_buffer_writable(buffers[path], function()
        vim.api.nvim_buf_set_lines(buffers[path], 0, -1, false, change.after.lines)
      end)
    end
  end
end

local function restore_workspace_candidate(changes)
  local buffers, conflicts = buffers_by_path(), {}
  for path, change in pairs(changes) do
    local current_exists = (vim.uv or vim.loop).fs_stat(path) ~= nil
    local current_lines = current_exists and vim.fn.readfile(path) or {}
    if current_exists ~= change.after.exists or not same_lines(current_lines, change.after.lines) then
      conflicts[#conflicts + 1] = path
    elseif change.before.exists then
      vim.fn.writefile(change.before.lines, path)
      if buffers[path] then
        with_tdd_buffer_writable(buffers[path], function()
          vim.api.nvim_buf_set_lines(buffers[path], 0, -1, false, change.before.lines)
        end)
      end
    else
      vim.fn.delete(path)
      if buffers[path] then
        with_tdd_buffer_writable(buffers[path], function()
          vim.api.nvim_buf_set_lines(buffers[path], 0, -1, false, {})
        end)
      end
    end
  end
  return conflicts
end

local function notify_restore_conflicts(conflicts)
  if #conflicts > 0 then
    vim.notify(
      "Refactoring rollback skipped concurrent edits: " .. table.concat(conflicts, ", "),
      vim.log.levels.WARN)
  end
end

local function build_copilot_prompt(context)
  return table.concat({
    "Fix the failing test with minimal code changes.",
    "Apply the fix directly to the file using your tools.",
    "File: " .. context.file_path,
    "Test: " .. context.test_id,
    "Failure output:",
    context.message,
  }, "\n")
end

local function build_refactor_prompt(context)
  local extension = file_extension(context.file_path)
  local file_type = extension == "" and "files without an extension" or ("files with ." .. extension .. " extension")
  return table.concat({
    "Apply the following refactoring exactly as described, with minimal unrelated changes.",
    "Inspect and change every related project file required, including affected tests, but only " .. file_type .. ".",
    "Do not edit generated build output or files with other extensions.",
    "Once applied, remove only the refactoring comment that requested it.",
    "Preserve every other // Refactoring: directive in this file, including duplicate requests.",
    "Run relevant tests before finishing.",
    "File: " .. context.file_path,
    "Line: " .. tostring(context.line),
    "Refactoring: " .. context.text,
  }, "\n")
end

local function build_refactor_repair_prompt(context, failure)
  local extension = file_extension(context.file_path)
  local file_type = extension == "" and "files without an extension" or ("files with ." .. extension .. " extension")
  return table.concat({
    "Finish this refactoring. Previous candidate failed verification.",
    "Make minimal related implementation and test changes needed to pass, but only " .. file_type .. ".",
    "Do not edit generated build output or files with other extensions.",
    "Keep requested refactoring, remove only its comment, and preserve every other // Refactoring: directive in this file.",
    "Run relevant tests before finishing.",
    "File: " .. context.file_path,
    "Refactoring: " .. context.text,
    "Failing test: " .. tostring(failure.test_id),
    "Failure output:",
    tostring(failure.message),
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
        refactorings[#refactorings + 1] = { line = i, text = text, directive = line }
      end
    end
  end
  return refactorings
end

local function build_copilot_cmd(context, prompt, model)
  local project_root = find_project_root(context.file_path)
  local session_id = get_or_create_session_id(context.file_path)
  local cmd = { config.copilot_cmd[1] }
  local skip_next = false
  for index, arg in ipairs(config.copilot_cmd) do
    if index == 1 then
      goto continue
    end
    if skip_next then
      skip_next = false
    elseif SECURITY_OPTION_VALUES[arg] then
      skip_next = true
    elseif not SECURITY_FLAGS[arg] then
      local security_option = false
      for _, prefix in ipairs(SECURITY_OPTION_PREFIXES) do
        if arg:sub(1, #prefix) == prefix then
          security_option = true
          break
        end
      end
      if not security_option then
        cmd[#cmd + 1] = arg
      end
    end
    ::continue::
  end
  for _, arg in ipairs(COPILOT_SECURITY_ARGS) do
    cmd[#cmd + 1] = arg
  end
  cmd[#cmd + 1] = "--add-dir"
  cmd[#cmd + 1] = project_root
  cmd[#cmd + 1] = "--model"
  cmd[#cmd + 1] = model or preferred_model
  cmd[#cmd + 1] = "-p"
  cmd[#cmd + 1] = prompt
  cmd[#cmd + 1] = "--session-id"
  cmd[#cmd + 1] = session_id
  return cmd
end

local function output_has_unavailable_model_error(output)
  return output:match("[Mm]odel%s+.-%s+from%s+%-%-model%s+flag%s+is%s+not%s+available") ~= nil
end

local function remember_model(model)
  for _, saved_model in ipairs(saved_models) do
    if saved_model == model then
      return
    end
  end
  saved_models[#saved_models + 1] = model
end

local function forget_model(model)
  for index, saved_model in ipairs(saved_models) do
    if saved_model == model then
      table.remove(saved_models, index)
      return
    end
  end
end

local function prompt_for_model(on_choice)
  vim.ui.input({
    prompt = "Copilot model (saved: " .. table.concat(saved_models, ", ") .. "; Enter for auto): ",
    default = "auto",
  }, function(input)
    if input == nil then
      on_choice(nil)
      return
    end
    local model = input:match("^%s*(.-)%s*$")
    if model == "" then
      model = "auto"
    end
    preferred_model = model
    remember_model(model)
    on_choice(model)
  end)
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
      return test_id, message or "No failure message provided.", result
    end
  end
  return nil, nil, nil
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

local function fetch_suite_results(neotest, adapter_id)
  local ok, results = pcall(neotest.state.results, adapter_id)
  if ok and type(results) == "table" then
    return results
  end
  return {}
end

local function collect_suite_state(neotest, bufnr)
  local snapshot = {
    has_running = false,
    has_failed = false,
    has_results = false,
    all_adapters_passed = true,
    passed = 0,
    failed = 0,
    skipped = 0,
    running = 0,
    total = 0,
    signature = {},
  }
  local reported_total = 0
  local has_reported_total = false

  for _, adapter_id in ipairs(neotest.state.adapter_ids() or {}) do
    if neotest.state.status_counts then
      local ok_counts, counts = pcall(neotest.state.status_counts, adapter_id, { buffer = bufnr })
      if ok_counts and type(counts) == "table" then
        for _, status in ipairs({ "passed", "failed", "skipped", "running" }) do
          local count = counts[status]
          if type(count) == "number" then
            snapshot[status] = snapshot[status] + count
          end
        end
        if type(counts.total) == "number" then
          reported_total = reported_total + counts.total
          has_reported_total = true
        end
      end
    end

    local results = fetch_suite_results(neotest, adapter_id)
    local test_id, failure_message, failed_result = first_failed_result(results)
    if test_id and not snapshot.failure then
      snapshot.failure = {
        file_path = failed_result and failed_result.path,
        test_id = test_id,
        message = failure_message,
      }
    end
    if all_results_passed(results) then
      snapshot.has_results = true
    elseif has_any_results(results) then
      snapshot.all_adapters_passed = false
    end
    for test_id, result in pairs(results) do
      snapshot.signature[#snapshot.signature + 1] = table.concat({
        adapter_id,
        tostring(test_id),
        tostring(result and result.status),
      }, "\0")
    end
  end

  table.sort(snapshot.signature)
  snapshot.signature = table.concat(snapshot.signature, "\n")
  snapshot.has_running = snapshot.running > 0
  snapshot.has_failed = snapshot.failed > 0
  snapshot.total = has_reported_total and reported_total
    or (snapshot.passed + snapshot.failed + snapshot.skipped + snapshot.running)
  return snapshot
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

local function capture_suite_failure(file_path, bufnr, done, generation)
  local ok, neotest = pcall(require, "neotest")
  if not ok then
    done(nil)
    return
  end

  last_failure = nil
  local root = find_project_root(file_path)
  local previous = collect_suite_state(neotest, bufnr)
  local run_ok = pcall(neotest.run.run, root)
  if not run_ok then
    done({
      file_path = file_path,
      test_id = "<suite>",
      message = "Unable to start the project test suite through neotest.",
      updated_at = now_ms(),
    }, { passed = 0, failed = 1, total = 0 })
    return
  end

  local started_at = now_ms()
  local saw_running = false
  local saw_fresh_state = false

  local function finish(failure, counts)
    if generation and generation ~= tdd_run_generation then
      return
    end
    last_failure = failure
    done(failure, counts)
  end

  local function inspect_results()
    if generation and generation ~= tdd_run_generation then
      return
    end
    local current = collect_suite_state(neotest, bufnr)
    if current.has_running then
      saw_running = true
      saw_fresh_state = true
    elseif current.signature ~= previous.signature
      or current.total ~= previous.total
      or current.passed ~= previous.passed
      or current.failed ~= previous.failed
      or current.skipped ~= previous.skipped then
      saw_fresh_state = true
    end

    local completed = current.passed + current.failed + current.skipped
    if current.total > 0 and generation then
      start_status_pulse(current.has_failed and "red" or "green", {
        kind = "suite",
        total = current.total,
        completed = completed,
        failed = current.failed,
        complete = saw_fresh_state and not current.has_running,
      })
    end

    local counts = { passed = current.passed, failed = current.failed, total = current.total }
    if saw_fresh_state and current.failure and not current.has_running then
      finish({
        file_path = current.failure.file_path or file_path,
        test_id = current.failure.test_id,
        message = current.failure.message,
        updated_at = now_ms(),
      }, counts)
      return
    end

    if saw_fresh_state and current.has_failed and not current.has_running then
      local qf = first_failed_quickfix(file_path)
      finish({
        file_path = file_path,
        test_id = qf and ("line " .. tostring(qf.lnum or "?")) or "<unknown>",
        message = qf and (qf.text or "Tests failed.") or "Tests failed. No failure output found.",
        updated_at = now_ms(),
      }, counts)
      return
    end

    if saw_fresh_state and not current.has_running
      and (saw_running
        or (current.has_results and current.all_adapters_passed)
        or (not current.has_failed and completed > 0)) then
      finish(nil, counts)
      return
    end

    if now_ms() - started_at < config.result_timeout_ms then
      vim.defer_fn(inspect_results, config.poll_interval_ms)
    else
      finish({
        file_path = file_path,
        test_id = "<suite>",
        message = "Timed out waiting for the requested neotest suite to start.",
        suite_error = true,
        updated_at = now_ms(),
      }, counts)
    end
  end

  vim.defer_fn(inspect_results, config.poll_interval_ms)
end

local function run_copilot_job(context, prompt, on_done, review, generation)
  if vim.fn.executable("copilot") ~= 1 then
    on_done(false)
    return
  end
  if copilot_job_id then
    on_done(false)
    return
  end

  local work_label = context.test_id or context.text or "current work"
  local snapshots = snapshot_open_buffers()
  local cwd = find_project_root(context.file_path)
  local workspace_snapshot = review and snapshot_workspace(cwd) or nil
  local function start_job(model)
    local output = {}
    local job_id = vim.fn.jobstart(build_copilot_cmd(context, prompt, model), {
      cwd = cwd,
      stdout_buffered = true,
      stderr_buffered = true,
      on_stdout = function(_, data)
        output[#output + 1] = table.concat(data or {}, "\n")
      end,
      on_stderr = function(_, data)
        output[#output + 1] = table.concat(data or {}, "\n")
      end,
      on_exit = function(_, _)
        copilot_job_id = nil
        if generation and generation ~= tdd_run_generation then
          return
        end
        if model ~= "auto" and output_has_unavailable_model_error(table.concat(output, "\n")) then
          forget_model(model)
          preferred_model = "auto"
          prompt_for_model(function(next_model)
            if next_model then
              start_job(next_model)
            else
              on_done(false)
            end
          end)
          return
        end
        if review then
          local allowed, excluded = partition_workspace_candidate(
            workspace_candidate(cwd, workspace_snapshot),
            file_extension(context.file_path))
          notify_restore_conflicts(restore_workspace_candidate(excluded))
          on_done(true, {
            changes = allowed,
          })
        else
          reload_changed_buffers(snapshots, work_label)
          on_done(true)
        end
      end,
    })
    if job_id <= 0 then
      on_done(false)
      return
    end
    copilot_job_id = job_id
  end
  start_job(preferred_model)
end

local function start_copilot_background(failure, on_done, generation)
  local prompt = build_copilot_prompt(failure)
  run_copilot_job(
    failure,
    prompt,
    on_done,
    false,
    generation)
end

local function start_copilot_refactor(refactor, on_done)
  local prompt = build_refactor_prompt(refactor)
  run_copilot_job(
    refactor,
    prompt,
    on_done,
    true)
end

local function start_copilot_refactor_repair(refactor, failure, on_done)
  run_copilot_job(refactor, build_refactor_repair_prompt(refactor, failure), on_done, true)
end

local start_refactoring_if_present

local function run_fix_cycle(file_path, bufnr, attempt, generation)
  capture_suite_failure(file_path, bufnr, function(failure, counts)
    if generation ~= tdd_run_generation then
      return
    end
    local passed = counts and counts.passed or 0
    local failed = counts and counts.failed or 0
    local total = counts and counts.total or (passed + failed)
    if not failure then
      if not start_refactoring_if_present(file_path, bufnr) then
        finish_loop("green", { kind = "suite", total = total, completed = total, failed = 0, complete = true })
      end
      return
    end
    if failure.suite_error then
      finish_loop("red", { kind = "suite", total = total, completed = total, failed = failed, complete = true })
      notify_terminal_failure(failure.message)
      return
    end
    start_status_pulse("red", status_detail)
    if attempt >= config.max_retries then
      finish_loop("red", { kind = "suite", total = total, completed = total, failed = failed, complete = true })
      notify_terminal_failure(string.format(
        "Max retries exhausted. Giving up. (%d passed, %d failed)\nLast failure (%s): %s",
        passed, failed, tostring(failure.test_id), tostring(failure.message)))
      return
    end
    start_copilot_background(failure, function(launched)
      if launched then
        if generation == tdd_run_generation then
          run_fix_cycle(file_path, bufnr, attempt + 1, generation)
        end
      else
        finish_loop("red", { kind = "suite", total = total, completed = total, failed = failed, complete = true })
      end
    end, generation)
  end, generation)
end

local function reload_and_format_refactor(bufnr)
  with_tdd_buffer_writable(bufnr, function()
    if not is_valid_buffer(bufnr) then
      return
    end
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("e!")
      vim.cmd("w")
    end)
  end)
end

local function find_refactoring_comment(bufnr, text, occurrence)
  local matches = 0
  for _, refactoring in ipairs(find_refactoring_comments(bufnr)) do
    if refactoring.text == text then
      matches = matches + 1
      if matches == occurrence then
        return refactoring
      end
    end
  end
  return nil
end

local function preserve_queued_refactoring_comments(file_path, bufnr, changes, refactorings, index)
  local change = changes[file_path]
  if not change then
    return
  end

  local pending, lines, changed = {}, change.after.lines, false
  local pending_texts = {}
  for i = index + 1, #refactorings do
    pending[#pending + 1] = refactorings[i]
    pending_texts[refactorings[i].text] = true
  end

  local pending_index = 1
  for line_index, line in ipairs(lines) do
    local text = line:match("//%s*[Rr]efactoring:%s*(.+)$")
    if text then
      text = text:gsub("%s+$", "")
      local expected = pending[pending_index]
      if expected and text == expected.text then
        if line ~= expected.directive then
          lines[line_index] = expected.directive
          changed = true
        end
        pending_index = pending_index + 1
      end
    end
  end

  if pending_index <= #pending then
    local preserved_lines = {}
    for _, line in ipairs(lines) do
      local text = line:match("//%s*[Rr]efactoring:%s*(.+)$")
      text = text and text:gsub("%s+$", "")
      if not text or not pending_texts[text] then
        preserved_lines[#preserved_lines + 1] = line
      end
    end
    lines = preserved_lines
    for _, pending_refactoring in ipairs(pending) do
      lines[#lines + 1] = pending_refactoring.directive
    end
    change.after.lines = lines
    changed = true
  end

  if changed then
    change.after.exists = true
    vim.fn.writefile(lines, file_path)
    if vim.api.nvim_buf_is_loaded(bufnr) then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end
  end
end

local function run_refactor_cycle(file_path, bufnr, refactorings, index)
  if index > #refactorings then
    finish_loop("green")
    return
  end
  if not is_valid_buffer(bufnr) then
    finish_loop("red")
    return
  end

  local occurrence = 1
  for i = 1, index - 1 do
    if refactorings[i].text == refactorings[index].text and refactorings[i].rejected then
      occurrence = occurrence + 1
    end
  end
  local refactor = find_refactoring_comment(bufnr, refactorings[index].text, occurrence)
  if not refactor then
    finish_loop("red")
    notify_terminal_failure("Queued refactoring comment no longer exists: " .. refactorings[index].text)
    return
  end
  local context = {
    file_path = file_path,
    line = refactor.line,
    text = refactor.text,
  }
  local candidate_state = nil
  local function review_candidate(launched, candidate, repair_attempt)
    if not launched then
      if candidate_state then
        notify_restore_conflicts(restore_workspace_candidate(candidate_state.changes))
      end
      finish_loop("red")
      return
    end

    if candidate_state then
      merge_candidate_changes(candidate_state.changes, candidate.changes)
    else
      candidate_state = candidate
    end
    preserve_queued_refactoring_comments(file_path, bufnr, candidate_state.changes, refactorings, index)
    local diff = candidate_diff(candidate_state.changes)
    show_refactoring_review(file_path, diff, refactor.text, function()
      sync_candidate_buffers(candidate_state.changes)
      reload_and_format_refactor(bufnr)
      capture_suite_failure(file_path, bufnr, function(failure, counts)
        if failure then
          start_status_pulse("red")
          if repair_attempt >= config.max_refactor_retries then
            local conflicts = restore_workspace_candidate(candidate_state.changes)
            loop_running = false
            set_status("red")
            local conflict_message = #conflicts > 0 and ("\nUnrestored concurrent edits: " .. table.concat(conflicts, ", ")) or ""
            notify_terminal_failure(string.format(
              "Refactoring retries exhausted after %d repairs.\nLast failure (%s): %s%s",
              repair_attempt, tostring(failure.test_id), tostring(failure.message), conflict_message))
            return
          end
          start_copilot_refactor_repair(context, failure, function(repair_launched, repaired_candidate)
            review_candidate(repair_launched, repaired_candidate, repair_attempt + 1)
          end)
          return
        end
        start_status_pulse("blue", #refactorings - index)
        run_refactor_cycle(file_path, bufnr, refactorings, index + 1)
      end)
    end, function()
      refactorings[index].rejected = true
      notify_restore_conflicts(restore_workspace_candidate(candidate_state.changes))
      start_status_pulse("blue", #refactorings - index)
      run_refactor_cycle(file_path, bufnr, refactorings, index + 1)
    end)
  end
  start_copilot_refactor(context, function(launched, candidate)
    review_candidate(launched, candidate, 0)
  end)
end

start_refactoring_if_present = function(file_path, bufnr)
  local refactorings = find_refactoring_comments(bufnr)
  if #refactorings == 0 then
    return false
  end

  start_status_pulse("blue", #refactorings)
  run_refactor_cycle(file_path, bufnr, refactorings, 1)
  return true
end

local function cancel_tdd_run()
  tdd_run_generation = tdd_run_generation + 1
  if copilot_job_id then
    vim.fn.jobstop(copilot_job_id)
    copilot_job_id = nil
  end
  local ok, neotest = pcall(require, "neotest")
  if ok and neotest.run.stop then
    pcall(neotest.run.stop)
  end
  finish_loop()
end

local function start_tdd_cycle(file_path, bufnr, save_buffer, restart)
  if file_path == nil or file_path == "" then
    return
  end

  if (loop_running or copilot_job_id) and not restart then
    return
  end
  if restart then
    cancel_tdd_run()
  end

  loop_running = true
  tdd_run_generation = tdd_run_generation + 1
  local generation = tdd_run_generation
  if save_buffer then
    vim.cmd("write")
  end
  acquire_tdd_buffer_lock(bufnr)
  suite_total = nil
  start_status_pulse("green", { kind = "suite", total = 0, completed = 0, failed = 0, complete = false })
  run_fix_cycle(file_path, bufnr, 0, generation)
end

function M.run_tdd()
  if tdd_mode_enabled then
    tdd_mode_enabled = false
    cancel_tdd_run()
    set_status("green")
    return
  end

  tdd_mode_enabled = true
  clear_status()
  local bufnr = vim.api.nvim_get_current_buf()
  start_tdd_cycle(vim.api.nvim_buf_get_name(bufnr), bufnr, true)
end

function M.run_refactor()
  local file_path = vim.api.nvim_buf_get_name(0)
  if file_path == nil or file_path == "" then
    return
  end

  if loop_running or copilot_job_id then
    return
  end

  vim.cmd("write")
  local bufnr = vim.api.nvim_get_current_buf()
  loop_running = true
  capture_suite_failure(file_path, bufnr, function(failure, counts)
    if failure then
      finish_loop("red")
      if failure.suite_error then
        notify_terminal_failure(failure.message)
      end
      return
    end
    if not start_refactoring_if_present(file_path, bufnr) then
      finish_loop()
      vim.notify("No refactoring found. Add a // Refactoring: <request> comment to start a refactoring.", vim.log.levels.INFO)
    end
  end)
end

function M.clear_session()
  local file_path = vim.api.nvim_buf_get_name(0)
  if file_path == nil or file_path == "" then
    return
  end

  if session_ids[file_path] then
    session_ids[file_path] = nil
  end
end

function M.select_model()
  if loop_running or copilot_job_id then
    return
  end
  prompt_for_model(function() end)
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
    if type(opts.model_keymap) == "string" and opts.model_keymap ~= "" then
      config.model_keymap = opts.model_keymap
    end
    if type(opts.result_timeout_ms) == "number" and opts.result_timeout_ms > 0 then
      config.result_timeout_ms = math.floor(opts.result_timeout_ms)
    end
    if type(opts.poll_interval_ms) == "number" and opts.poll_interval_ms > 0 then
      config.poll_interval_ms = math.floor(opts.poll_interval_ms)
    end
    if type(opts.max_retries) == "number" and opts.max_retries >= 0 then
      config.max_retries = math.floor(opts.max_retries)
    end
    if type(opts.max_refactor_retries) == "number" and opts.max_refactor_retries >= 0 then
      config.max_refactor_retries = math.floor(opts.max_refactor_retries)
    end
    if type(opts.copilot_cmd) == "table" and #opts.copilot_cmd > 0 then
      config.copilot_cmd = opts.copilot_cmd
    end
  end

  vim.keymap.set("n", config.keymap, M.run_tdd, { desc = "tdd-bot: run tests and background fix on failure" })
  vim.keymap.set("n", config.clear_keymap, M.clear_session, { desc = "tdd-bot: clear stored copilot session for current file" })
  vim.keymap.set("n", config.refactor_keymap, M.run_refactor, { desc = "tdd-bot: apply // Refactoring: comments via copilot" })
  vim.keymap.set("n", config.model_keymap, M.select_model, { desc = "tdd-bot: select Copilot model" })

  if tdd_mode_augroup then
    vim.api.nvim_del_augroup_by_id(tdd_mode_augroup)
  end
  tdd_mode_augroup = vim.api.nvim_create_augroup("TddBotMode", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = tdd_mode_augroup,
    callback = function(args)
      if not tdd_mode_enabled then
        return
      end
      local bufnr = args.buf
      local file_path = args.file
      if file_path == nil or file_path == "" then
        file_path = vim.api.nvim_buf_get_name(bufnr)
      end
      start_tdd_cycle(file_path, bufnr, false, true)
    end,
  })
  render_status(status_state or "green", status_pulse_bright, status_detail)
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

function M._get_model()
  return preferred_model
end

function M._is_mode_enabled()
  return tdd_mode_enabled
end

return M
