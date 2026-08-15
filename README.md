# tdd-bot

Version: `0.1.13`

Minimal Neovim plugin:
- `<leader>tdd` runs tests for current file with `neotest`
- each TDD loop start notifies current tdd-bot version
- every test run (pass or fail, each retry) notifies total passed/failed counts
- when failures exist, notifies the failing test id and its failure output
- ignores stale pass/fail state left over from a prior run until the current run is confirmed underway (guards against neotest's cumulative results cache misreporting)
- on failure, runs Copilot non-interactive fix in background, resuming the same Copilot session for that file across retries/reruns (per-file, in-memory only, not persisted across Neovim restarts)
- when retries are exhausted, notifies with the last failing test's message so you know why Copilot couldn't fix it
- when Copilot marks a test unresolved, shows its detailed audit report in a Neovim warning notification
- streams Copilot output to dedicated bottom log buffer
- reruns tests once automatically after Copilot exits
- on exit, syncs any buffer Copilot changed with its on-disk content (via `nvim_buf_set_lines`, not `:edit!`, so `FileType`/`BufReadPost` autocmds — and any LSP client attached through them — aren't re-triggered) and notifies with a unified diff of what changed
- notifies fix duration on exit, e.g. "Copilot fix took 3.2s"
- `<leader>tdc` clears the stored Copilot session for the current file, so the next `<leader>tdd` on it starts fresh
- `<leader>tdr` scans the current buffer for `// Refactoring: <what to do>` comments and applies each one via a background Copilot job, one at a time; Copilot is instructed to remove the comment once the refactoring is applied
- refactoring only starts in a green state: tests run first, and the loop aborts if anything is already failing
- after each refactoring, tests rerun; a broken refactoring reverts the file (disk + buffer) to its pre-refactoring content and stops the loop

lazy.nvim local path:

```lua
{
  dir = "/Users/ctw00428/development/projects/personal/tdd-bot.nvim",
  dependencies = { "nvim-neotest/neotest" },
  config = function()
    require("tdd-bot").setup()
  end,
}
```

## Copilot fix flow

Flow:
1. Run `<leader>tdd` on test file.
2. If tests fail, tdd-bot starts background Copilot job.
3. Output streams into bottom log buffer.
4. On Copilot exit, tdd-bot reruns tests once.

Requirements:
- `copilot` CLI installed and authenticated.
- default command prefix: `copilot --allow-all-tools --allow-all-urls --no-custom-instructions --disable-builtin-mcps`
  (the last two flags skip loading global custom instructions/skills and the
  built-in github-mcp-server, cutting typical invocation time roughly in half).

Optional setup:

```lua
require("tdd-bot").setup({
  keymap = "<leader>tdd",
  clear_keymap = "<leader>tdc", -- clears the stored copilot session for current file
  refactor_keymap = "<leader>tdr", -- applies `// Refactoring: ...` comments via copilot
  terminal_height = 12,
  copilot_cmd = { "copilot", "--allow-all-tools", "--allow-all-urls" }, -- override command prefix (do not include -p, it is appended automatically)
  result_timeout_ms = 120000, -- wait for late test results
  poll_interval_ms = 200,
  notification_timeout_ms = 3000, -- auto-dismiss info notifications; use 0 to keep them open
})
```

## Refactoring flow

Leave a comment in the file describing the refactoring you want:

```dart
// Refactoring: extract this block into a private helper method
```

Run `<leader>tdr`. tdd-bot first runs the tests once — refactoring only starts from a
green state (aborts with an error if anything is already red). It then scans the current
buffer for every `// Refactoring: <text>` comment and runs one background Copilot job per
comment (sequentially, reusing the same job infrastructure as the TDD fix flow). Each job
is told the file, the comment's line number, and the requested refactoring, and is
instructed to remove the comment once applied. After each refactoring, tests rerun; if the
refactoring broke anything, the file (disk + buffer) is reverted to its pre-refactoring
state and the loop stops.
