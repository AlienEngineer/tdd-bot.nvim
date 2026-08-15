# tdd-bot.nvim

`tdd-bot.nvim` keeps a test-driven development loop inside Neovim. It runs the
current file's tests through [neotest](https://github.com/nvim-neotest/neotest);
when they fail, it asks the Copilot CLI to fix them in a background job, streams
the job output to a bottom log buffer, and reruns the tests when Copilot exits.
It also supports Copilot-assisted refactoring that starts only when tests pass.

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
3. If tests fail, read Copilot output in bottom log buffer.
4. tdd-bot syncs Copilot's changed buffers and reruns tests after Copilot exits.

Each TDD loop reports tdd-bot version, passed/failed counts, failing test details,
and fix duration. If retries finish without a fix, it reports last failure. Use
`<leader>tdc` when you need Copilot to forget earlier work for current file.

### Refactor passing code

Add one or more refactoring comments:

```dart
// Refactoring: extract this block into a private helper method
```

Press `<leader>tdr`. tdd-bot runs tests first. If they pass, it applies each
comment sequentially through Copilot and removes completed comments. Tests rerun
after every refactoring; if one breaks them, tdd-bot restores file and buffer to
their pre-refactoring state and stops.

## Configuration

```lua
require("tdd-bot").setup({
  keymap = "<leader>tdd",
  clear_keymap = "<leader>tdc",
  refactor_keymap = "<leader>tdr",
  copilot_cmd = { "copilot", "--allow-all-tools", "--allow-all-urls" },
  result_timeout_ms = 120000,
  poll_interval_ms = 200,
  notification_timeout_ms = 3000,
  max_retries = 5,
})
```

Do not include `-p` in `copilot_cmd`; tdd-bot appends the prompt automatically.
