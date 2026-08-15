# tdd-bot ti/tf Flow Design

Date: 2026-08-03  
Status: Approved for implementation

## Goal

Split responsibilities:
- `<leader>ti` runs tests only
- `<leader>tf` launches Copilot fix flow from last recorded failing test

## Scope

In scope:
- Remove failure popup and yes/no prompt from test run path
- Capture last failure context from neotest results listener
- Add `<leader>tf` keybind to run Copilot with cached failure context
- Fix Copilot CLI invocation format using prompt flag

Out of scope:
- Auto apply patches
- Multi-failure queue management
- Custom interactive review UI beyond terminal split

## Architecture

Core module `lua/tdd-bot/init.lua` will expose:
- `run_current_file()` for `<leader>ti`
- `fix_last_failure()` for `<leader>tf`
- internal cache `last_failure` updated from neotest results events

Data flow:
1. `<leader>ti` runs `neotest.run.run(current_file)`.
2. neotest listener callback receives result updates.
3. first failed result for current file updates `last_failure` cache (`file_path`, `test_id`, `message`, `updated_at`).
4. `<leader>tf` builds Copilot prompt from cache and opens terminal split in failure file directory.

## Copilot Command Contract

Default command prefix:
- `{ "copilot", "-p" }`

Final command:
- `{ "copilot", "-p", "<generated prompt>" }`

This avoids invalid interactive `exec` format and matches CLI guidance for non-interactive prompt submission.

## Keymaps

- `<leader>ti` -> run current file tests only.
- `<leader>tf` -> run fix command from last failure cache.

If no cached failure exists:
- show explicit notify: `tdd-bot: no failed test captured yet; run <leader>ti first.`

## Error Handling

- Missing `neotest` -> explicit error notify.
- Missing `copilot` binary -> explicit error notify.
- Empty current file path on `ti` -> explicit error notify.
- Cache without valid file path -> explicit error notify.

## Testing

Update Lua tests to cover:
1. `ti` invokes neotest run and does not open tdd-bot popup.
2. Listener capture writes `last_failure` when failed result arrives.
3. `tf` uses cached failure and calls `termopen` with `copilot -p`.
4. `tf` errors when cache missing.

