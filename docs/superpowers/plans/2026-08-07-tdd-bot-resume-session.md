# tdd-bot Resume Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `<leader>tdd` resumes the same Copilot CLI session across repeated runs on the same test file (retries, follow-up fixes), while switching test files starts an isolated session. `<leader>tdc` clears the stored session for the current file, forcing a fresh one next run.

**Architecture:** Track a `session_ids` table in plugin state keyed by absolute test file path, each value a self-generated uuid v4. `build_copilot_cmd` always appends `--session-id <uuid>` — same flag both creates (first time) and resumes (subsequent times) a Copilot session, so no output parsing is needed. `<leader>tdc` deletes the current file's table entry.

**Tech Stack:** Lua, Neovim API, Copilot CLI (`--session-id` flag)

## Global Constraints

- Single source file: all changes go in `tdd-bot/lua/tdd-bot/init.lua` (existing single-file module pattern — do not split).
- No disk persistence — `session_ids` is in-memory only, cleared on Neovim restart.
- Never use `--continue` or `--resume` without an explicit id — must not resume "most recent" session, only our own tracked uuid per file.
- Test runner: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"` run from repo root `/Users/ctw00428/development/projects/personal/tdd-bot.nvim`. Prints `ok` on success (script uses bare `assert`, so any failure raises a Lua error and non-zero-ish output instead of `ok`).
- Existing `build_copilot_cmd` argument order (positions 1-9: `copilot`, `--allow-all-tools`, `--allow-all-urls`, `--add-dir`, `<project_root>`, `--deny-tool=shell(rm:*)`, `--deny-tool=shell(sudo:*)`, `-p`, `<prompt>`) must NOT change — existing tests assert exact indices. New flags must be appended after position 9.

---

### Task 1: uuid v4 generator

**Files:**
- Modify: `tdd-bot/lua/tdd-bot/init.lua` — add `generate_uuid()` local function near top (after `now_ms`/`notify_error`, before `build_copilot_prompt`)
- Test: `tdd-bot/tests/test_tdd_bot.lua`

**Interfaces:**
- Produces: `M._generate_uuid()` — public wrapper for testing, returns a string matching `^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$` (RFC 4122 v4 format, lowercase hex, version nibble `4`, variant nibble one of `8/9/a/b`).

- [ ] **Step 1: Write the failing test**

Add near the end of `tdd-bot/tests/test_tdd_bot.lua`, before the final block of `test_*()` calls (i.e. add a new local function alongside the others, then add its call in the invocation list):

```lua
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
```

Also add `test_generate_uuid_format_and_uniqueness()` to the invocation list (after `test_guard_when_job_already_running()` and before `vim.notify = real.notify`):

```lua
test_generate_uuid_format_and_uniqueness()
```

- [ ] **Step 2: Run test to verify it fails**

Run from repo root: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`
Expected: Lua error, something like `attempt to call a nil value (field '_generate_uuid')` — no `ok` printed.

- [ ] **Step 3: Write minimal implementation**

In `tdd-bot/lua/tdd-bot/init.lua`, add after the `local function now_ms()` block (around line 15-16), before `notify_info`:

```lua
math.randomseed(os.time() + (now_ms() % 100000))

local function generate_uuid()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return (template:gsub("[xy]", function(c)
    local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
    return string.format("%x", v)
  end))
end
```

Add the public wrapper near the bottom, right before `return M`:

```lua
function M._generate_uuid()
  return generate_uuid()
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`
Expected: prints `ok`

- [ ] **Step 5: Commit**

```bash
cd /Users/ctw00428/development/projects/personal/tdd-bot.nvim
git add tdd-bot/lua/tdd-bot/init.lua tdd-bot/tests/test_tdd_bot.lua
git commit -m "feat(tdd-bot): add uuid v4 generator for session ids"
```

(Skip commit if this directory is not a git repository — verify with `git -C /Users/ctw00428/development/projects/personal/tdd-bot.nvim rev-parse --is-inside-work-tree` first; if it errors, just leave changes uncommitted and note it.)

---

### Task 2: per-file session id tracking wired into Copilot command

**Files:**
- Modify: `tdd-bot/lua/tdd-bot/init.lua`
- Test: `tdd-bot/tests/test_tdd_bot.lua`

**Interfaces:**
- Consumes: `generate_uuid()` from Task 1 (local function, same file).
- Produces:
  - local function `get_or_create_session_id(file_path)` — returns existing uuid for `file_path` or creates+stores a new one.
  - `M._get_session_id(file_path)` — public read-only wrapper for testing, returns stored uuid for `file_path` or `nil` if none stored (does NOT create one).
  - `build_copilot_cmd(context)` now appends `--session-id`, `<uuid>` as the last two elements of the returned command list (positions 10-11), where `<uuid>` comes from `get_or_create_session_id(context.file_path)`.

- [ ] **Step 1: Write the failing tests**

Add to `tdd-bot/tests/test_tdd_bot.lua` (new local functions alongside existing ones):

```lua
local function test_same_file_reuses_session_id_across_runs()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local call1 = state.job_calls[1]
  assert(call1.cmd[10] == "--session-id", "expected --session-id flag at position 10")
  local uuid1 = call1.cmd[11]
  assert(type(uuid1) == "string" and #uuid1 > 0, "expected uuid string at position 11")

  neotest_mode = "fail-results"
  call1.opts.on_exit(1, 0)

  local call2 = state.job_calls[2]
  assert(call2, "expected second job on retry")
  assert(call2.cmd[10] == "--session-id", "expected --session-id flag on retry")
  assert(call2.cmd[11] == uuid1, "expected same uuid reused for same file across retries")
end

local function test_different_file_gets_different_session_id()
  reset_state()
  neotest_mode = "fail-results"
  install_neotest()
  local bot = load_bot()
  bot.setup()
  bot.run_tdd()

  local uuid1 = state.job_calls[1].cmd[11]

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

  local uuid2 = state.job_calls[2].cmd[11]
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
```

Add all three calls to the invocation list, after `test_generate_uuid_format_and_uniqueness()`:

```lua
test_same_file_reuses_session_id_across_runs()
test_different_file_gets_different_session_id()
test_get_session_id_returns_nil_when_unset()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`
Expected: fails on `test_same_file_reuses_session_id_across_runs` — `call1.cmd[10] == "--session-id"` assertion fails (currently `nil`), or `bot._get_session_id` is nil.

- [ ] **Step 3: Write minimal implementation**

In `tdd-bot/lua/tdd-bot/init.lua`, add a new state table near `last_failure`/`copilot_job_id` (around line 10-11):

```lua
local last_failure = nil
local copilot_job_id = nil
local session_ids = {}
```

Add `get_or_create_session_id` right after `generate_uuid` (from Task 1):

```lua
local function get_or_create_session_id(file_path)
  local existing = session_ids[file_path]
  if existing then
    return existing
  end
  local uuid = generate_uuid()
  session_ids[file_path] = uuid
  return uuid
end
```

Modify `build_copilot_cmd` to append the session flag:

```lua
local function build_copilot_cmd(context)
  local project_root = find_project_root(context.file_path)
  local session_id = get_or_create_session_id(context.file_path)
  return {
    "copilot",
    "--allow-all-tools",
    "--allow-all-urls",
    "--add-dir", project_root,
    "--deny-tool=shell(rm:*)",
    "--deny-tool=shell(sudo:*)",
    "-p",
    build_copilot_prompt(context),
    "--session-id", session_id,
  }
end
```

Add the public read-only wrapper near `M._get_last_failure`, before `return M`:

```lua
function M._get_session_id(file_path)
  return session_ids[file_path]
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`
Expected: prints `ok`

- [ ] **Step 5: Commit**

```bash
cd /Users/ctw00428/development/projects/personal/tdd-bot.nvim
git add tdd-bot/lua/tdd-bot/init.lua tdd-bot/tests/test_tdd_bot.lua
git commit -m "feat(tdd-bot): reuse per-file copilot session id across runs"
```

---

### Task 3: `<leader>tdc` clears stored session; README update

**Files:**
- Modify: `tdd-bot/lua/tdd-bot/init.lua`
- Modify: `tdd-bot/README.md`
- Test: `tdd-bot/tests/test_tdd_bot.lua`

**Interfaces:**
- Consumes: `session_ids` table, `M._get_session_id(file_path)` from Task 2.
- Produces:
  - `M.clear_session()` — resolves current buffer's file path, removes its `session_ids` entry if present, notifies via `notify_info`. If no path (empty buffer name), calls `notify_error` and returns, same guard style as `M.run_tdd`. If no entry stored, calls `notify_info` with a "nothing to clear" style message (still no error).
  - `config.clear_keymap` (default `"<leader>tdc"`), settable via `setup({ clear_keymap = ... })` mirroring existing `config.keymap` pattern.
  - `setup()` now also calls `vim.keymap.set("n", config.clear_keymap, M.clear_session, { desc = "tdd-bot: clear stored copilot session for current file" })`.

- [ ] **Step 1: Write the failing tests**

Add to `tdd-bot/tests/test_tdd_bot.lua`:

```lua
local function test_tdc_mapping_exists()
  reset_state()
  install_neotest()
  local bot = load_bot()
  bot.setup()
  assert(mapped_handler("<leader>tdc"), "expected <leader>tdc mapping")
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
```

Add all three calls to the invocation list, after `test_get_session_id_returns_nil_when_unset()`:

```lua
test_tdc_mapping_exists()
test_clear_session_removes_stored_uuid()
test_clear_session_notifies_when_nothing_to_clear()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`
Expected: fails — `mapped_handler("<leader>tdc")` is nil, or `bot.clear_session` is nil.

- [ ] **Step 3: Write minimal implementation**

In `tdd-bot/lua/tdd-bot/init.lua`, add `clear_keymap` to the `config` table at the top:

```lua
local config = {
  keymap = "<leader>tdd",
  clear_keymap = "<leader>tdc",
  result_timeout_ms = 120000,
  poll_interval_ms = 200,
  max_retries = 5,
}
```

Add `M.clear_session`, right after `M.run_tdd` and before `M.setup`:

```lua
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
```

Modify `M.setup` to read `clear_keymap` from opts and register the mapping:

```lua
function M.setup(opts)
  if type(opts) == "table" then
    if type(opts.keymap) == "string" and opts.keymap ~= "" then
      config.keymap = opts.keymap
    end
    if type(opts.clear_keymap) == "string" and opts.clear_keymap ~= "" then
      config.clear_keymap = opts.clear_keymap
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
  end

  vim.keymap.set("n", config.keymap, M.run_tdd, { desc = "tdd-bot: run tests and background fix on failure" })
  vim.keymap.set("n", config.clear_keymap, M.clear_session, { desc = "tdd-bot: clear stored copilot session for current file" })
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`
Expected: prints `ok`

- [ ] **Step 5: Update README**

In `tdd-bot/README.md`, update the feature bullet list (top) to mention resume behavior, and the optional setup block to include `clear_keymap`:

Replace:
```markdown
- `<leader>tdd` runs tests for current file with `neotest`
- on failure, runs Copilot non-interactive fix in background
- streams Copilot output to dedicated bottom log buffer
- reruns tests once automatically after Copilot exits
```
with:
```markdown
- `<leader>tdd` runs tests for current file with `neotest`
- on failure, runs Copilot non-interactive fix in background, resuming the same Copilot session for that file across retries/reruns (per-file, in-memory only, not persisted across Neovim restarts)
- streams Copilot output to dedicated bottom log buffer
- reruns tests once automatically after Copilot exits
- `<leader>tdc` clears the stored Copilot session for the current file, so the next `<leader>tdd` on it starts fresh
```

Replace:
```lua
require("tdd-bot").setup({
  keymap = "<leader>tdd",
  terminal_height = 12,
  copilot_cmd = { "copilot", "--allow-all-tools", "-p" }, -- override command prefix
  result_timeout_ms = 120000, -- wait for late test results
  poll_interval_ms = 200,
})
```
with:
```lua
require("tdd-bot").setup({
  keymap = "<leader>tdd",
  clear_keymap = "<leader>tdc", -- clears the stored copilot session for current file
  terminal_height = 12,
  copilot_cmd = { "copilot", "--allow-all-tools", "-p" }, -- override command prefix
  result_timeout_ms = 120000, -- wait for late test results
  poll_interval_ms = 200,
})
```

- [ ] **Step 6: Commit**

```bash
cd /Users/ctw00428/development/projects/personal/tdd-bot.nvim
git add tdd-bot/lua/tdd-bot/init.lua tdd-bot/tests/test_tdd_bot.lua tdd-bot/README.md
git commit -m "feat(tdd-bot): add <leader>tdc to clear stored copilot session"
```

(As in Task 1, skip commit if not inside a git work tree.)
