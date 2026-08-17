# tdd-bot.nvim

`tdd-bot.nvim` keeps a test-driven development loop inside Neovim. It runs the
current file's tests through [neotest](https://github.com/nvim-neotest/neotest);
when they fail, it asks the Copilot CLI to fix them in a background job and
reruns the tests when Copilot exits.
It also supports Copilot-assisted refactoring that starts only when tests pass.

[![CI](https://github.com/AlienEngineer/tdd-bot.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/AlienEngineer/tdd-bot.nvim/actions/workflows/ci.yml)

## Features

- `<leader>tdd` runs tests for current file with `neotest`
- `<leader>tdc` clears the stored Copilot session for the current file, so the next `<leader>tdd` on it starts fresh
- `<leader>tdr` scans the current buffer for `// Refactoring: <what to do>` comments and queues each one for background Copilot review; Copilot is instructed to remove the comment once the refactoring is applied
- `<leader>tdm` opens model selector with `auto` plus models currently offered by Copilot CLI


## Install with LazyVim

Create `~/.config/nvim/lua/plugins/tdd-bot.lua`:

```lua
return {
  {
    "AlienEngineer/tdd-bot.nvim",
    dependencies = { "nvim-neotest/neotest" },
    opts = {},
  },
}
```

Restart Neovim, then let LazyVim install the plugin. `tdd-bot.nvim` requires the
`copilot` CLI to be installed and authenticated. Its default Copilot command is:

```sh
copilot --allow-all-tools --allow-all-urls --no-custom-instructions --disable-builtin-mcps
```

## Use tdd-bot

Open a test file and use these normal-mode mappings. `<leader>` is your Neovim
leader key.

| Mapping | Action |
| --- | --- |
| `<leader>tdd` | Run tests for current file. On failure, start a background Copilot fix; rerun tests once Copilot exits. |
| `<leader>tdc` | Clear stored Copilot session for current file. Next fix starts a fresh Copilot session. |
| `<leader>tdr` | Apply every `// Refactoring: <request>` comment through Copilot. Tests must pass before refactoring begins. |
| `<leader>tdm` | Choose model for future tdd-bot Copilot jobs. `auto` is default. |

### Fix failing tests

1. Open test file.
2. Press `<leader>tdd`.
3. Watch status dot pulse while Copilot works.
4. tdd-bot syncs Copilot's changed buffers and reruns tests after Copilot exits.

Status dot stays visible in top-right corner. It pulses green while a TDD test
run waits for a result, red while fixing failures, and blue while refactoring.
When work ends it becomes static green for success or static red for failure.
If every retry fails, tdd-bot shows one notification with passed/failed totals
and final test failure. Use `<leader>tdc` when you need Copilot to forget
earlier work for current file.

### Refactor passing code

Add one or more refactoring comments:

```dart
// Refactoring: extract this block into a private helper method
```

Press `<leader>tdr`. tdd-bot runs tests first. If they pass, it prepares each
comment sequentially through Copilot, then opens a focused diff review. Press
`a` to accept, or `r`, `q`, or `<Esc>` to reject. Accepted changes reload and
save buffer content before tests rerun. Rejected changes restore disk and buffer
content without running tests. Blue status dot shows remaining queued
refactorings and advances only after each decision. If an accepted change breaks
tests, tdd-bot restores file and buffer to pre-refactoring state and stops. If
no refactoring comments exist, tdd-bot notifies you to add one.

## Configuration

```lua
require("tdd-bot").setup({
  keymap = "<leader>tdd",
  clear_keymap = "<leader>tdc",
  refactor_keymap = "<leader>tdr",
  model_keymap = "<leader>tdm",
  copilot_cmd = { "copilot", "--allow-all-tools", "--allow-all-urls" },
  result_timeout_ms = 120000,
  poll_interval_ms = 200,
  max_retries = 5,
})
```

Do not include `-p` in `copilot_cmd`; tdd-bot appends the prompt automatically.

Press `<leader>tdm` to scrape installed, authenticated Copilot CLI's `/model`
selector and choose a model for this Neovim session. `auto` is default and
always available. Selection applies to future TDD fixes and refactorings; it is
not persisted across restarts. If Copilot rejects selected model as unavailable,
tdd-bot retries that job once with `auto`.
