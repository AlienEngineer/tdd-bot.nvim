# tdd-bot Copilot Fix Design

Date: 2026-08-03  
Status: Approved for implementation

## Goal

When `<leader>ti` test run fails, ask user if Copilot should attempt a fix. If yes, open interactive Copilot CLI session inside Neovim terminal split with failure context prefilled.

## Scope

In scope:
- Failure follow-up yes/no prompt
- Terminal split launcher for Copilot CLI
- Prefilled prompt with failure details
- Working directory set to current test file directory
- Basic config options for keymap/terminal/command override

Out of scope:
- Auto-applying patches
- Multi-failure orchestration
- Non-interactive autonomous repair flow

## Architecture

Files:
- `tdd-bot/lua/tdd-bot/init.lua` extended with:
  - failure decision prompt
  - Copilot command construction
  - terminal launcher
- `tdd-bot/README.md` updated with new behavior and requirements

Flow:
1. `<leader>ti` triggers test run on current file.
2. Existing failure popup shows first failure details.
3. New yes/no floating prompt asks whether to launch Copilot fix session.
4. On yes:
   - determine current file directory as `cwd`
   - build prompt from file path, test id, error output
   - open bottom split terminal and run Copilot CLI command
5. User interacts with Copilot in terminal to accept/reject proposed fix.

## Copilot Execution Contract

Default launch strategy:
- prefer `copilot exec "<prompt>"`
- configurable override via `setup({ copilot_cmd = { ... } })`

Terminal behavior:
- `botright 15split`
- `termopen(cmd, { cwd = current_file_dir })`
- keep terminal visible for interaction/review

Prompt content includes:
- absolute failing file path
- failed test identifier
- captured failure message
- request for minimal fix and explanation

## Errors and Guardrails

- If `copilot` binary unavailable, show `vim.notify` error and do not open terminal.
- If current buffer has no file path, existing error handling remains.
- Prompt must be passed as argument list (not shell-concatenated string) to avoid escaping issues.

## Testing Strategy

Add Lua unit-style tests (stubbed `vim.api`, `vim.fn`, `vim.ui`, `vim.fn.termopen`) for:
- failure path prompts yes/no
- yes branch launches terminal with expected cwd and command args
- no branch does not launch terminal
- missing `copilot` binary shows error

