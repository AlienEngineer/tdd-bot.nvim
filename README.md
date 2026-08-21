# tdd-bot.nvim

`tdd-bot.nvim` runs your Neovim tests with `neotest`. When a test fails, it
asks the Copilot CLI to fix it, then runs the tests again.

## Install

## Features

- `<leader>tdd` toggles TDD mode, off by default; enabling it saves current
  buffer, makes it read-only while automated TDD work runs, then restores its
  prior editability when complete; it runs the project suite, then repeats that
  suite cycle after every file save
- shows a compact non-focusable floating status with `On`/`Off` mode text, the
  current buffer's test total beside it, and live whole-solution progress below it; it pulses
  while tests or Copilot work is running
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
- each refactoring may change related implementation and test files only when they share initiating file's extension; generated `build/` output and other file types are restored if Copilot changes them. Review shows one combined workspace diff. Press `a` to accept or `r`, `q`, or `<Esc>` to reject
- rejected changes restore every candidate file to pre-refactoring content; queue advances only after accept or reject
- failed accepted refactorings start bounded Copilot repair iterations. Exhaustion restores candidate workspace and stops loop
- a compact, non-focusable floating status pulses green while TDD tests run, red
  during failure recovery, and blue during refactoring. The current buffer's test
  total appears beside `On`/`Off`; green whole-solution progress shows `completed/total...`,
  completed suites show `total ✓`, and failures show `failed/total ✗`; blue shows remaining
  refactoring count, which decreases after each verified refactoring and hides
  when complete; completed loops leave a static green or red dot

## Install with LazyVim

Create `~/.config/nvim/lua/plugins/tdd-bot.lua`:

You need `nvim-neotest/neotest` and an installed, authenticated `copilot` CLI.
With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "AlienEngineer/tdd-bot.nvim",
  dependencies = { "nvim-neotest/neotest" },
  opts = {},
}
```

## Start and stop

Open a file and press `<leader>tdd` in normal mode to start TDD mode. It runs
the test suite immediately and again whenever you save a file. Press
`<leader>tdd` again to stop TDD mode and cancel active work.

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
| `<leader>tdd` | Toggle TDD mode. First press turns it On, saves current buffer, makes that buffer read-only during automated TDD work, and runs the project suite. While On, every file save restarts that file's suite TDD/fix/refactor cycle and makes its buffer read-only during the cycle. Next press turns it Off and stops save-triggered cycles. Previous editability returns after recovery and any queued refactoring review finish. |
| `<leader>tdc` | Clear stored Copilot session for current file. Next fix starts a fresh Copilot session. |
| `<leader>tdr` | Save current buffer, then apply every `// Refactoring: <request>` comment through Copilot. Tests must pass before refactoring begins. |
| `<leader>tdm` | Type model for future tdd-bot Copilot jobs. `auto` is suggested. |

### Fix failing tests

1. Open test file.
2. Press `<leader>tdd` to turn TDD mode On and start its first cycle.
3. Save any file to run the project suite; saving while it is already running interrupts it and starts a fresh suite run. Press `<leader>tdd` again to turn mode Off.
4. Watch status dot pulse while Copilot works.
5. tdd-bot syncs Copilot's changed buffers and reruns tests after Copilot exits.
6. When tests are green, queued `// Refactoring:` comments enter blue review mode;
   without comments, TDD finishes with static green status.

The floating status shows `On` or `Off` and, once discovered, the current
buffer's test total in the top-right corner. TDD mode defaults to Off.
A second line shows `--/--` until whole-solution progress is known,
then green `completed/total...` while it runs. A passing suite settles on green
`total ✓`; a failing suite shows red `failed/total ✗`. Blue refactoring status
continues to show its remaining refactoring count. Saving during any active TDD
work cancels its pending suite/Copilot work before starting the replacement run.
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
comment sequentially through Copilot, including related implementation and test
files, then opens one combined workspace diff review. Press `a` to accept, or
`r`, `q`, or `<Esc>` to reject. Accepted changes rerun tests. A failed
verification starts up to `max_refactor_retries` Copilot repairs, each reviewed
as part of same candidate. Rejecting or exhausting repairs restores all candidate
files and stops only on exhaustion. Blue status dot shows remaining queued
refactorings and advances only after verified success. If no refactoring comments
exist, tdd-bot notifies you to add one.

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
  max_refactor_retries = 5,
})
```

`max_retries` limits TDD failure-fix attempts. `max_refactor_retries` independently
limits repair attempts after accepted refactoring verification fails; both default
to `5`.

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
