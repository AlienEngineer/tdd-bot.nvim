# tdd-bot Resume Session Design

Date: 2026-08-07
Status: Approved for implementation

## Goal

`<leader>tdd` resumes the previous Copilot CLI session for the same test file instead of starting a fresh one each time, so retries and follow-up fixes keep prior context. Switching to a different test file must not inherit an unrelated session's context.

## Scope

In scope:
- Per-file session id tracking (in-memory, process lifetime only)
- Pass `--session-id <uuid>` to every Copilot invocation
- New `<leader>tdc` keymap to clear the stored session id for the current file

Out of scope:
- Disk persistence across Neovim restarts
- Any global "resume most recent session" behavior (`--continue`) — explicitly avoided to prevent picking up unrelated/dirty Copilot sessions

## Design

### Session id storage

- `session_ids` table in plugin state: `session_ids[file_path] = uuid`.
- Key is the absolute test file path (`vim.api.nvim_buf_get_name` / `:p`), not project root — each test file gets its own Copilot session.
- Table lives only in-memory for the current Neovim process; no file written to disk.

### Resume mechanism

- Copilot CLI's `--session-id=<uuid>` flag both creates a session (if unseen) and resumes it (if already used) — verified experimentally.
- `get_or_create_session_id(file_path)`:
  - if `session_ids[file_path]` exists, return it
  - else generate a new uuid v4 (pure Lua, no external deps), store it, return it
- `build_copilot_cmd` appends `--session-id`, `<uuid>` to the existing argument list.

### `<leader>tdc` — clear session

- New `M.clear_session()` function, bound to `<leader>tdc` (configurable via `setup({ clear_keymap = ... })`, mirroring existing `keymap` option).
- Resolves current buffer's file path, removes its entry from `session_ids` if present, notifies user.
- Does NOT run tests or launch Copilot — purely resets state so the next `<leader>tdd` on that file starts a brand-new Copilot session.
- If no session stored for the file, notify that there's nothing to clear (no error).

### uuid generation

Pure-Lua uuid v4 generator (no external dependency), using `math.random` seeded once at module load, formatted as `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx` per RFC 4122 version/variant bits.

## Errors and Guardrails

- Existing guardrails (no file path, copilot binary missing, job already running) unchanged.
- Clearing a session with no stored id is a no-op notify, not an error.

## Testing

- Same file path across two `M.run_tdd()` calls → same uuid passed to `build_copilot_cmd` both times.
- Different file path → different uuid.
- `M.clear_session()` removes stored uuid; subsequent `run_tdd()` on that file generates a new uuid (different from prior).
- `build_copilot_cmd` includes `--session-id` followed by the resolved uuid.
