# tdd-bot.nvim

`tdd-bot.nvim` keeps a test-driven development loop inside Neovim. It runs the
current file's tests through [neotest](https://github.com/nvim-neotest/neotest);
when they fail, it asks the Copilot CLI to fix them in a background job and
reruns the tests when Copilot exits.
It also supports Copilot-assisted refactoring that starts only when tests pass.

[![CI](https://github.com/AlienEngineer/tdd-bot.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/AlienEngineer/tdd-bot.nvim/actions/workflows/ci.yml)

## Features

- `<leader>tdd` runs tests for current file with `neotest`
- shows a compact non-focusable floating status dot that pulses while tests or
  Copilot work is running
- ignores stale pass/fail state left over from a prior run until the current run is confirmed underway (guards against neotest's cumulative results cache misreporting)
- on failure, runs Copilot non-interactive fix in background, resuming the same Copilot session for that file across retries/reruns (per-file, in-memory only, not persisted across Neovim restarts)
- when retries are exhausted, notifies with the last failing test's message so you know why Copilot couldn't fix it
- reruns tests once automatically after Copilot exits
- on exit, syncs any buffer Copilot changed with its on-disk content (via `nvim_buf_set_lines`, not `:edit!`, so `FileType`/`BufReadPost` autocmds — and any LSP client attached through them — aren't re-triggered) and opens a popup with a unified diff of what changed
- `<leader>tdc` clears the stored Copilot session for the current file, so the next `<leader>tdd` on it starts fresh
- `<leader>tdr` scans the current buffer for `// Refactoring: <what to do>` comments and applies each one via a background Copilot job, one at a time; Copilot is instructed to remove the comment once the refactoring is applied
- refactoring only starts in a green state: tests run first, and the loop aborts if anything is already failing
- after each refactoring, tests rerun; a broken refactoring reverts the file (disk + buffer) to its pre-refactoring content and stops the loop
- a compact, non-focusable floating dot pulses green while TDD tests run, red
  during failure recovery, and blue during refactoring; blue shows remaining
  refactoring count, which decreases after each verified refactoring and hides
  when complete; completed loops leave a static green or red dot

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

Press `<leader>tdr`. tdd-bot runs tests first. If they pass, it applies each
comment sequentially through Copilot and removes completed comments. Blue status
dot shows remaining queued refactorings, decreases after each verified change,
and hides count when queue completes. Tests rerun after every refactoring; if
one breaks them, tdd-bot restores file and buffer to their pre-refactoring
state and stops.

## Configuration

```lua
require("tdd-bot").setup({
  keymap = "<leader>tdd",
  clear_keymap = "<leader>tdc",
  refactor_keymap = "<leader>tdr",
  copilot_cmd = { "copilot", "--allow-all-tools", "--allow-all-urls" },
  result_timeout_ms = 120000,
  poll_interval_ms = 200,
  max_retries = 5,
})
```

Do not include `-p` in `copilot_cmd`; tdd-bot appends the prompt automatically.
