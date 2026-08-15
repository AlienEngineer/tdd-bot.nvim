# tdd-bot tdd Keybind Background Flow Design

Date: 2026-08-03  
Status: Approved for implementation

## Goal

Replace separate `ti/tf` flow with one keybind `<leader>tdd` that runs tests, auto-fixes failures in background using Copilot non-interactive mode, then reruns tests once.

## Scope

In scope:
- Single keybind `<leader>tdd`
- Run current-file neotest first
- On failure, launch Copilot in background (`jobstart`) with non-interactive prompt
- Stream Copilot output to dedicated bottom log buffer
- On Copilot exit, rerun tests once automatically

Out of scope:
- Infinite retry loops
- Interactive Copilot terminal chats
- Multi-job queueing

## Architecture

Main file: `lua/tdd-bot/init.lua`

State:
- `last_failure` context cache
- `copilot_job_id` active background job id
- `log_buf/log_win` bottom output buffer handles

Flow:
1. `<leader>tdd` runs current-file tests.
2. Failure capture logic stores failing context.
3. If failure exists, start background Copilot job with auto flags.
4. Stream stdout/stderr to bottom log buffer.
5. On exit, rerun current-file tests once.

## Copilot Command

Default prefix:
- `{ "copilot", "-p" }`

Flags:
- `--allow-all-tools`

Prompt contains:
- failing file path
- test identifier
- failure output
- explicit instruction to apply edits directly and finish

## UX

- Bottom log buffer opened with `botright 12new` and reused for each run.
- Buffer shows start header, live Copilot output, exit status, and rerun result.
- Notifications show coarse lifecycle (`started`, `completed`, `rerun done`).

## Error Handling

- Missing `neotest`: notify and stop.
- Missing `copilot`: notify and stop.
- Empty buffer path: notify and stop.
- Active Copilot job already running: notify and skip starting another.

## Testing

Update Lua tests for:
1. `<leader>tdd` mapping exists.
2. failing test path starts background `jobstart` with `copilot -p --allow-all-tools`.
3. output callbacks append lines to bottom log buffer.
4. `on_exit` triggers one rerun and does not loop.
5. guard when job already running.

