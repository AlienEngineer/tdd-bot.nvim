# tdd-bot.nvim

`tdd-bot.nvim` runs your Neovim tests with `neotest`. When a test fails, it
asks the Copilot CLI to fix it, then runs the tests again.

## Install

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
