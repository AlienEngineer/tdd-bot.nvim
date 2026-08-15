# tdd-bot Copilot Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add fail-time prompt that can launch interactive Copilot CLI fix session inside Neovim terminal split.

**Architecture:** Keep current test-run flow. After first failure detection, ask user yes/no in float prompt. On yes, open split terminal in current test file directory and run Copilot CLI with failure-context prompt payload.

**Tech Stack:** Lua, Neovim API (`nvim_open_win`, `termopen`, `vim.fn.executable`), neotest, Copilot CLI

## Global Constraints

- Existing `<leader>ti` flow remains: run current-file tests via `neotest`.
- Copilot flow starts only when failure exists and user says yes.
- Interaction must happen inside Neovim terminal split.
- Terminal launch cwd must be current failing test file directory.
- Missing `copilot` binary must surface explicit error.
- Scope excludes auto-apply patch and multi-failure orchestration.

---

## File Structure

- Modify: `tdd-bot/lua/tdd-bot/init.lua` — add fail prompt + Copilot terminal launcher.
- Modify: `tdd-bot/README.md` — document new fail->Copilot flow and requirements.
- Create: `tdd-bot/tests/test_tdd_bot.lua` — stubbed tests for prompt and terminal launch behavior.

### Task 1: Add failing tests for prompt and launcher

**Files:**
- Create: `tdd-bot/tests/test_tdd_bot.lua`
- Test: `tdd-bot/tests/test_tdd_bot.lua`

**Interfaces:**
- Consumes:
  - `require("tdd-bot").run_current_file(): nil`
- Produces:
  - Verified expected calls to prompt + terminal launch helpers.

- [ ] **Step 1: Write the failing test**

```lua
package.path = "./tdd-bot/lua/?.lua;./tdd-bot/lua/?/init.lua;" .. package.path

local opened_cmd, opened_opts
local prompt_called = false
local notify_msg = nil

vim = vim or {}
vim.log = { levels = { ERROR = 1 } }
vim.o = { columns = 120, lines = 40 }
vim.notify = function(msg) notify_msg = msg end
vim.defer_fn = function(fn) fn() end
vim.keymap = { set = function() end }
vim.bo = setmetatable({}, { __index = function() return {} end })
vim.api = {
  nvim_buf_get_name = function() return "/tmp/sample_test.lua" end,
  nvim_create_buf = function() return 10 end,
  nvim_buf_set_lines = function() end,
  nvim_open_win = function() return 20 end,
  nvim_win_is_valid = function() return true end,
  nvim_win_close = function() end,
}
vim.fn = {
  executable = function(bin) return bin == "copilot" and 1 or 0 end,
  fnamemodify = function(path, mod) if mod == ":p:h" then return "/tmp" end return path end,
  termopen = function(cmd, opts) opened_cmd, opened_opts = cmd, opts return 1 end,
}
vim.ui = {
  select = function(_, _, cb)
    prompt_called = true
    cb("yes")
  end,
}
vim.cmd = function() end

package.loaded["neotest"] = {
  run = { run = function() end },
  state = {
    adapter_ids = function() return { "a" } end,
    results = function()
      return {
        ["sample::test"] = {
          status = "failed",
          errors = { { message = "expected true, got false" } },
        },
      }
    end,
  },
}

local bot = require("tdd-bot")
bot.run_current_file()

assert(prompt_called, "expected user prompt after failure")
assert(opened_cmd ~= nil, "expected terminal to launch copilot")
assert(opened_opts.cwd == "/tmp", "expected cwd to be current file dir")
assert(notify_msg == nil, "expected no error notification")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`  
Expected: FAIL because prompt/launcher code not implemented yet.

- [ ] **Step 3: Write minimal implementation hooks**

```lua
-- in init.lua add helpers:
-- 1) prompt_for_copilot_fix(context, on_yes)
-- 2) launch_copilot_terminal(context)
-- then call from failure branch
```

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tdd-bot/tests/test_tdd_bot.lua tdd-bot/lua/tdd-bot/init.lua
git commit -m "test: cover copilot launch flow from failing test"
```

### Task 2: Implement Copilot prompt + interactive terminal split

**Files:**
- Modify: `tdd-bot/lua/tdd-bot/init.lua`
- Test: `tdd-bot/tests/test_tdd_bot.lua`

**Interfaces:**
- Consumes:
  - failure data `{ file_path: string, test_id: string, message: string }`
- Produces:
  - `M.run_current_file()` launches optional Copilot session when user confirms.
  - `M.setup(opts)` accepts `copilot_cmd` and `terminal_height`.

- [ ] **Step 1: Write failing test for negative branch**

```lua
-- add second case in test file:
-- vim.ui.select callback returns "no"
-- assert termopen not called
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`  
Expected: FAIL with assertion on no-branch behavior.

- [ ] **Step 3: Implement minimal behavior**

```lua
-- in init.lua
local config = {
  keymap = "<leader>ti",
  terminal_height = 15,
  copilot_cmd = nil,
}

local function prompt_for_copilot_fix(context, on_yes)
  vim.ui.select({ "yes", "no" }, { prompt = "Ask Copilot to fix failing test?" }, function(choice)
    if choice == "yes" then
      on_yes()
    end
  end)
end

local function build_copilot_cmd(context)
  local prompt = table.concat({
    "Fix failing test.",
    "File: " .. context.file_path,
    "Test: " .. context.test_id,
    "Failure:",
    context.message,
    "Provide minimal fix and explain changes.",
  }, "\n")

  if type(config.copilot_cmd) == "table" and #config.copilot_cmd > 0 then
    local cmd = vim.deepcopy(config.copilot_cmd)
    table.insert(cmd, prompt)
    return cmd
  end

  return { "copilot", "exec", prompt }
end

local function launch_copilot_terminal(context)
  if vim.fn.executable("copilot") ~= 1 then
    vim.notify("tdd-bot: copilot binary not found.", vim.log.levels.ERROR)
    return
  end
  local cwd = vim.fn.fnamemodify(context.file_path, ":p:h")
  vim.cmd("botright " .. tostring(config.terminal_height) .. "split")
  vim.fn.termopen(build_copilot_cmd(context), { cwd = cwd })
end
```

- [ ] **Step 4: Run tests to verify pass**

Run: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`  
Expected: PASS for yes/no and missing-binary cases.

- [ ] **Step 5: Commit**

```bash
git add tdd-bot/lua/tdd-bot/init.lua tdd-bot/tests/test_tdd_bot.lua
git commit -m "feat: launch interactive copilot terminal on test failure"
```

### Task 3: Update docs and verify in real Neovim

**Files:**
- Modify: `tdd-bot/README.md`
- Test: manual Neovim run with failing test file

**Interfaces:**
- Consumes:
  - `setup({ terminal_height?, copilot_cmd? })`
- Produces:
  - Documented user workflow and required Copilot CLI availability.

- [ ] **Step 1: Write doc expectation check**

```text
README must state:
1) fail popup appears
2) yes/no prompt appears
3) yes opens interactive Copilot terminal in file dir
4) needs copilot CLI installed and authenticated
```

- [ ] **Step 2: Confirm doc currently missing items**

Run: `cat tdd-bot/README.md`  
Expected: missing Copilot flow details.

- [ ] **Step 3: Update README**

```md
When test fails:
1. tdd-bot shows failure popup.
2. tdd-bot asks if Copilot should fix it.
3. Choose yes -> interactive Copilot terminal opens in current file directory.
4. Chat with Copilot there; accept/reject by your own edits/commands.
```

- [ ] **Step 4: Run manual smoke verification**

Run in Neovim:
1. Open known failing test file
2. Press `<leader>ti`
3. Select `yes`
4. Confirm split terminal opens and Copilot prompt includes failure context

Expected: interactive Copilot session visible in Neovim terminal.

- [ ] **Step 5: Commit**

```bash
git add tdd-bot/README.md
git commit -m "docs: explain copilot-assisted failure flow"
```

## Self-Review

1. **Spec coverage:** Includes fail prompt, interactive terminal, cwd behavior, binary checks, config, docs.  
2. **Placeholder scan:** No TBD/TODO placeholders.  
3. **Type consistency:** Context keys and `setup` options consistent across tasks.

