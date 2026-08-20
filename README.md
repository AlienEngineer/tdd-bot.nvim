# tdd-bot.nvim

`tdd-bot.nvim` keeps a test-driven development loop inside Neovim. It runs the
current file's tests through [neotest](https://github.com/nvim-neotest/neotest);
when they fail, it asks the Copilot CLI to fix them in a background job and
reruns the tests when Copilot exits.
It also supports Copilot-assisted refactoring that starts only when tests pass.

[![CI](https://github.com/AlienEngineer/tdd-bot.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/AlienEngineer/tdd-bot.nvim/actions/workflows/ci.yml)

## Features

- `<leader>tdd` saves current buffer, then runs tests for current file with `neotest`;
  once green, it applies queued `// Refactoring:` comments
- shows a compact non-focusable floating status dot that pulses while tests or
  Copilot work is running
- ignores stale pass/fail state left over from a prior run until the current run is confirmed underway (guards against neotest's cumulative results cache misreporting)
- on failure, runs Copilot non-interactive fix in background, resuming the same Copilot session for that file across retries/reruns (per-file, in-memory only, not persisted across Neovim restarts)
- when retries are exhausted, notifies with the last failing test's message so you know why Copilot couldn't fix it
- reruns tests once automatically after Copilot exits
- after a failure-fix Copilot job exits, syncs any changed buffer with on-disk content (via `nvim_buf_set_lines`, not `:edit!`, so `FileType`/`BufReadPost` autocmds — and any LSP client attached through them — aren't re-triggered) and opens a popup with a unified diff
- `<leader>tdc` clears the stored Copilot session for the current file, so the next `<leader>tdd` on it starts fresh
- `<leader>tdr` manually starts refactoring: it saves current buffer, verifies tests
  pass, then scans `// Refactoring: <what to do>` comments and queues each for
  background Copilot review; Copilot is instructed to remove each applied comment
- `<leader>tdm` prompts for a Copilot model ID; `auto` is suggested
- refactoring only starts in a green state: tests run first, and the loop aborts if anything is already failing
- each refactoring opens a focused diff review: press `a` to accept or `r`, `q`, or `<Esc>` to reject; only accepted changes reload and save the buffer, then rerun tests
- rejected changes restore pre-refactoring disk and buffer content without saving candidate changes; queue advances only after accept or reject
- a broken accepted refactoring reverts file (disk + buffer) to pre-refactoring content and stops loop
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
`copilot` CLI to be installed and authenticated. Every Copilot job starts in
detected project root and limits file tools to that root (not system temp).
Only local read, edit, search, and shell tools needed for project work are
available. URL/web tools and MCP servers are unavailable.

```sh
copilot --available-tools=view,glob,rg,apply_patch,bash --disallow-temp-dir --deny-tool=url
```

Copilot CLI requires `--allow-all-tools` for non-interactive jobs; tdd-bot adds
it only after restricting available tools to this allowlist. This does not
sandbox shell commands at OS level. For hard filesystem/network isolation,
enable Copilot CLI's local sandbox and configure it to allow only current
working directory, disable outbound/local network and bypasses, disable dev
tool access and git/gh credential injection, and deny user-profile paths.

## Use tdd-bot

Open a test file and use these normal-mode mappings. `<leader>` is your Neovim
leader key.

| Mapping | Action |
| --- | --- |
| `<leader>tdd` | Save current buffer and run tests for current file. On failure, start a background Copilot fix and rerun tests once it exits. Once tests pass, apply queued `// Refactoring:` comments. |
| `<leader>tdc` | Clear stored Copilot session for current file. Next fix starts a fresh Copilot session. |
| `<leader>tdr` | Save current buffer, then apply every `// Refactoring: <request>` comment through Copilot. Tests must pass before refactoring begins. |
| `<leader>tdm` | Type model for future tdd-bot Copilot jobs. `auto` is suggested. |

### Fix failing tests

1. Open test file.
2. Press `<leader>tdd`.
3. Watch status dot pulse while Copilot works.
4. tdd-bot syncs Copilot's changed buffers and reruns tests after Copilot exits.
5. When tests are green, queued `// Refactoring:` comments enter blue review mode;
   without comments, TDD finishes with static green status.

The floating dot stays visible in top-right corner. It pulses green while a TDD test
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

Press `<leader>tdr` to start refactoring without a TDD failure-fix cycle.
tdd-bot runs tests first. If they pass, it prepares each
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
  copilot_cmd = { "copilot", "--no-color" },
  result_timeout_ms = 120000,
  poll_interval_ms = 200,
  max_retries = 5,
})
```

`copilot_cmd` may set executable and benign CLI arguments. tdd-bot removes
permission, path, URL, MCP/plugin, agent, model, prompt, and session flags from
this setting, then appends its fixed project-confinement policy. Do not include
`-p` in `copilot_cmd`; tdd-bot appends prompt automatically.

Press `<leader>tdm` to type any Copilot model ID. `auto` is suggested by default,
and models typed during this Neovim session are shown in later prompts for easy
reuse. Selection applies to future TDD fixes and refactorings; it is not
persisted across restarts. If Copilot rejects a selected model as unavailable,
tdd-bot removes it from saved models and prompts for a replacement, suggesting
`auto`.
