# tdd-bot tdd Background Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ti/tf with `<leader>tdd` that runs tests, auto-runs non-interactive Copilot in background on failure, streams to bottom log buffer, and reruns tests once.

**Architecture:** Keep failure capture logic in plugin state. `<leader>tdd` runs current file tests and stores failure context. If failed, start one background `jobstart` using `copilot -p --allow-all-tools`, stream output into dedicated bottom log buffer, then trigger one rerun of tests on job exit.

**Tech Stack:** Lua, Neovim API (`jobstart`, terminal buffers), neotest, Copilot CLI

## Global Constraints

- Single keybind must be `<leader>tdd`.
- No interactive Copilot mode; use non-interactive prompt mode.
- Copilot execution runs in background.
- Must show execution state in bottom log buffer.
- Must auto-accept changes (run with auto-tools permission) and rerun tests once after completion.
- Must avoid infinite rerun loops.

---

## File Structure

- Modify: `tdd-bot/lua/tdd-bot/init.lua` — keymap, background job orchestration, bottom log buffer handling.
- Modify: `tdd-bot/tests/test_tdd_bot.lua` — tests for new keybind, command args, log streaming, single rerun behavior.
- Modify: `tdd-bot/README.md` — usage and behavior updates.
- Modify: `~/.config/nvim/lua/plugins/tdd-bot.lua` — local opts to match new keybind and command defaults.

### Task 1: Red-green tests for new tdd flow

**Files:**
- Modify: `tdd-bot/tests/test_tdd_bot.lua`
- Test: `tdd-bot/tests/test_tdd_bot.lua`

**Interfaces:**
- Consumes:
  - `setup(opts)`
  - `run_current_file()`
- Produces:
  - assertions for `<leader>tdd`, background copilot invocation, bottom log writes, one rerun.

- [ ] **Step 1: Write failing tests**

```lua
-- replace old ti/tf checks with:
-- 1) mapping exists for <leader>tdd only
-- 2) failure starts job with {"copilot","-p","--allow-all-tools",prompt}
-- 3) stdout callback appends lines to log buffer
-- 4) on_exit triggers exactly one rerun
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`  
Expected: FAIL because current implementation still uses ti/tf split.

- [ ] **Step 3: Minimal implementation to pass tests**

```lua
-- implement after failures confirmed
```

- [ ] **Step 4: Run test to verify it passes**

Run: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tdd-bot/tests/test_tdd_bot.lua tdd-bot/lua/tdd-bot/init.lua
git commit -m "feat: add tdd background copilot flow"
```

### Task 2: Implement bottom log buffer and job pipeline

**Files:**
- Modify: `tdd-bot/lua/tdd-bot/init.lua`
- Test: `tdd-bot/tests/test_tdd_bot.lua`

**Interfaces:**
- Consumes:
  - cached failure context
- Produces:
  - `run_tdd()` command bound to `<leader>tdd`
  - background copilot execution with bottom log streaming

- [ ] **Step 1: Write failing test for duplicate output prevention**

```lua
-- assert each run clears/reuses dedicated log buffer and does not duplicate prior lines
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`  
Expected: FAIL on log buffer reuse/clear expectations.

- [ ] **Step 3: Implement minimal code**

```lua
-- add:
-- ensure_log_buffer()
-- append_log(lines)
-- run_tdd()
-- start_copilot_background(failure)
-- on_exit => rerun_once()
```

- [ ] **Step 4: Run tests to verify pass**

Run: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tdd-bot/lua/tdd-bot/init.lua tdd-bot/tests/test_tdd_bot.lua
git commit -m "fix: stream background copilot logs in bottom buffer"
```

### Task 3: Docs/config updates and smoke check

**Files:**
- Modify: `tdd-bot/README.md`
- Modify: `~/.config/nvim/lua/plugins/tdd-bot.lua`

**Interfaces:**
- Consumes:
  - `setup({ keymap, copilot_cmd })`
- Produces:
  - updated user instructions for `<leader>tdd`

- [ ] **Step 1: Write failing doc expectation**

```text
README must remove ti/tf references and describe single tdd flow with background job + auto rerun.
```

- [ ] **Step 2: Verify current docs fail expectation**

Run: `cat tdd-bot/README.md`  
Expected: still references ti/tf.

- [ ] **Step 3: Update docs/config**

```lua
opts = {
  keymap = "<leader>tdd",
  copilot_cmd = { "copilot", "-p", "--allow-all-tools" },
}
```

- [ ] **Step 4: Smoke verification**

Run:
1. `:Lazy reload tdd-bot.nvim`
2. `:doautocmd User VeryLazy`
3. `:nmap <leader>tdd`
4. trigger failing test and confirm bottom log output updates, then automatic rerun occurs

Expected: one-key flow works end-to-end.

- [ ] **Step 5: Commit**

```bash
git add tdd-bot/README.md /Users/ctw00428/.config/nvim/lua/plugins/tdd-bot.lua
git commit -m "docs: update tdd background fix workflow"
```

## Self-Review

1. **Spec coverage:** keybind merge, background non-interactive execution, bottom logs, auto rerun all covered.  
2. **Placeholder scan:** no TBD/TODO placeholders.  
3. **Type consistency:** single public flow anchored on `<leader>tdd` and `setup(opts)` updates.

