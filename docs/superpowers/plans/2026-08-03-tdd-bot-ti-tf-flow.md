# tdd-bot ti/tf Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `<leader>ti` run tests only and add `<leader>tf` to launch Copilot fix from last captured failure.

**Architecture:** Replace popup/prompt-driven flow with listener-captured failure cache. `ti` triggers neotest run; results listener stores latest failure context. `tf` reads cache and starts terminal with `copilot -p` prompt in failing file directory.

**Tech Stack:** Lua, Neovim API, neotest, Copilot CLI

## Global Constraints

- `<leader>ti` only runs current-file tests.
- No tdd-bot popup/prompt on `ti`.
- `<leader>tf` uses last captured failure context.
- Copilot command must use prompt flag (`-p`) to avoid invalid command format.
- Missing prerequisites must surface explicit error messages.

---

## File Structure

- Modify: `tdd-bot/lua/tdd-bot/init.lua` — keymaps, listener capture cache, fix launcher.
- Modify: `tdd-bot/tests/test_tdd_bot.lua` — failing-first tests for split `ti`/`tf` behavior and command args.
- Modify: `tdd-bot/README.md` — new keybind docs.
- Modify: `~/.config/nvim/lua/plugins/tdd-bot.lua` — optional keymap config update if needed.

### Task 1: Implement ti/tf split and listener cache

**Files:**
- Modify: `tdd-bot/lua/tdd-bot/init.lua`
- Test: `tdd-bot/tests/test_tdd_bot.lua`

**Interfaces:**
- Consumes:
  - `M.run_current_file(): nil`
- Produces:
  - `M.run_current_file(): nil` (tests only)
  - `M.fix_last_failure(): nil` (launches Copilot from cache)

- [ ] **Step 1: Write failing tests**

```lua
-- cases:
-- 1) run_current_file calls neotest.run.run and does NOT create prompt mappings y/n
-- 2) results callback stores last failure cache
-- 3) fix_last_failure launches termopen with {"copilot","-p",prompt}
-- 4) fix_last_failure with no cache => notify error
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`  
Expected: FAIL on missing `fix_last_failure` and/or wrong command format.

- [ ] **Step 3: Write minimal implementation**

```lua
-- add local last_failure = nil
-- register neotest listeners once in setup:
--   neotest.consumers.tdd_bot_capture = function(client)
--     client.listeners.results = function(_, results) ...update last_failure... end
--   end
-- map <leader>ti -> run_current_file
-- map <leader>tf -> fix_last_failure
-- default copilot_cmd = {"copilot","-p"}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `nvim --headless -u NONE -c "lua dofile('tdd-bot/tests/test_tdd_bot.lua')" -c "qa!"`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tdd-bot/lua/tdd-bot/init.lua tdd-bot/tests/test_tdd_bot.lua
git commit -m "feat: split ti test run and tf copilot fix flow"
```

### Task 2: Update docs and local plugin config

**Files:**
- Modify: `tdd-bot/README.md`
- Modify: `~/.config/nvim/lua/plugins/tdd-bot.lua`

**Interfaces:**
- Consumes:
  - `setup({ keymap, fix_keymap, copilot_cmd })`
- Produces:
  - Documented usage for `<leader>ti` and `<leader>tf`

- [ ] **Step 1: Write failing expectation**

```text
README must no longer mention popup yes/no flow.
README must document: ti runs tests, tf launches copilot fix from last failure.
```

- [ ] **Step 2: Verify docs currently fail expectation**

Run: `cat tdd-bot/README.md`  
Expected: still contains old popup/prompt flow.

- [ ] **Step 3: Write minimal docs/config updates**

```md
- <leader>ti => run current file tests
- <leader>tf => run Copilot fix on last failing test
```

```lua
opts = {
  keymap = "<leader>ti",
  fix_keymap = "<leader>tf",
  copilot_cmd = { "copilot", "-p" },
}
```

- [ ] **Step 4: Run smoke verification**

Run:
1. `:Lazy reload tdd-bot.nvim`
2. `:doautocmd User VeryLazy`
3. `:nmap <leader>ti`
4. `:nmap <leader>tf`

Expected: both mappings present.

- [ ] **Step 5: Commit**

```bash
git add tdd-bot/README.md /Users/ctw00428/.config/nvim/lua/plugins/tdd-bot.lua
git commit -m "docs: update tdd-bot ti/tf workflow"
```

## Self-Review

1. **Spec coverage:** command format fix, ti/tf split, listener capture, docs all covered.  
2. **Placeholder scan:** no TBD/TODO placeholders.  
3. **Type consistency:** `run_current_file`, `fix_last_failure`, `setup(opts)` names consistent.

