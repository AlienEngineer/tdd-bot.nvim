# AGENTS.md

`tdd-bot` is a small Neovim plugin. Core code lives in `tdd-bot/lua/tdd-bot/init.lua`; the plugin entry is `tdd-bot/plugin/tdd-bot.lua`; tests are in `tdd-bot/tests/test_tdd_bot.lua`.

## What it does
- `<leader>tdd` runs `neotest` for the current file, then uses `copilot` CLI to fix failures in the background.
- `<leader>tdc` clears the per-file Copilot session.
- `<leader>tdr` applies `// Refactoring: ...` comments one at a time, but only from a green test state.

## Commands
Run from the `tdd-bot/` directory:
- `nvim --headless -u NONE -c "lua dofile('tests/test_tdd_bot.lua')"`

## Conventions
- Keep changes surgical and in the existing style.
- Preserve the per-file Copilot session behavior and the stale-results guard in `init.lua`.
- Use `vim.notify` for user-facing status/errors and keep buffer sync via `nvim_buf_set_lines`.
- Default Copilot command flags stay in `init.lua`; do not load custom instructions or built-in MCPs unless explicitly changing that behavior.
