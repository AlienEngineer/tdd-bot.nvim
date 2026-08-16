# tdd-bot.nvim: Copilot Agent Guide

## Project Overview

A Neovim plugin that integrates test-driven development with Copilot CLI. Runs failing tests through `neotest`, invokes Copilot to fix failures in background, reruns tests automatically, and supports Copilot-assisted refactoring when tests pass.

**Key Features:**
- `<leader>tdd` — run tests, auto-fix on failure, retry up to 5 times
- `<leader>tdc` — clear per-file Copilot session
- `<leader>tdr` — apply `// Refactoring: <comment>` refactorings (only when tests pass)
- Floating status dot (pulses green/red/blue; static on completion)
- Syncs Copilot changes to buffer and disk; shows unified diff

## Code Structure

- **`lua/tdd-bot/init.lua`** (706 lines) — Main plugin module
  - Config defaults (keymaps, timeouts, Copilot command)
  - Test runner and status UI (floating dot)
  - Copilot job lifecycle (spawn, poll, sync buffer changes)
  - Refactoring loop with test validation
  
- **`plugin/tdd-bot.lua`** — Entry point; calls `setup()`

- **`tests/test_tdd_bot.lua`** (1283 lines) — Comprehensive test suite with mocked Neovim APIs

## Commands

| Task | Command |
|------|---------|
| Run tests | `nvim --headless -u NONE -l tests/test_tdd_bot.lua` |
| No linter/formatter | Manual review only |
| No build step | Lua plugin; no compilation |

## Conventions

- **Lua style:** Standard Neovim plugin conventions; single-module architecture
- **Copilot integration:** Uses CLI with `--allow-all-tools --allow-all-urls --no-custom-instructions --disable-builtin-mcps`
- **Job management:** Per-file session tracking in `session_ids` table; background job polling
- **Buffer sync:** Use `nvim_buf_set_lines` for changes (avoids re-triggering FileType autocmds)
- **Status UI:** Floating window (1×1 char) at top-right; highlights are `TddBotStatusRed`, `TddBotStatusGreen`, `TddBotStatusBlue` (+ `Dim` variants)
- **Version:** Semantic versioning in `lua/tdd-bot/init.lua` line 2 (`local VERSION = "..."`)

## Key Interactions

1. **Test run:** Keymaps call `run_tests_for_current_file()`
2. **Failure recovery:** On neotest failure, spawn Copilot job with file path and test output
3. **Job polling:** Timer checks `vim.fn.jobwait()` every 200ms (configurable); updates status dot
4. **Sync & rerun:** On Copilot exit, sync buffer with disk, rerun tests
5. **Refactoring:** Parse `// Refactoring: ` comments, run Copilot per comment, validate with tests

## Testing

Tests mock all Neovim APIs (`vim.notify`, `vim.fn.jobstart`, `vim.api.*`). No external dependencies required. Tests exercise:
- Status UI lifecycle
- Job spawn and polling
- Buffer sync and diff generation
- Refactoring loop (success and failure cases)
