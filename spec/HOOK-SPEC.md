# Dumpcito hook spec v1

Single source of truth for both apps (macOS Swift, Windows C#). Both must pass every file in `spec/scenarios/`.

Principle: **alerts come only from hook events.** Never guess from transcripts, idle time, window titles or screen contents.

## 1. Pipeline

```
AI tool --(runs hook command, JSON on stdin)--> Dumpcito --hook --tool <tool>
        --> normalize --> write/remove state file --> app polls state dir --> detector --> alert
```

The hook command must be fast, never print errors, and always exit 0 (a failing hook shows an error inside the user's session).
Cursor hooks expect JSON on stdout: print `{}` for `--tool cursor`. For every other tool print nothing.

## 2. State directory

- macOS: `~/.dumpcito/state/`   Windows: `%USERPROFILE%\.dumpcito\state\`
- Directory owner-only (0700). Files owner-only (0600) on macOS; on Windows inherit the user profile ACL.
- One file per session: `<tool>__<session>.json`. Write atomically (temp file in the same directory + rename).
- Ignore stdin bigger than 1 MB. Session id must match `^[A-Za-z0-9_-]{1,64}$`, otherwise drop the event.
- Delete state files older than 7 days at app launch.

File content (all times are epoch milliseconds):

```json
{"v":1,"tool":"claude","session":"abc","cwd":"/work/x","title":"fix the bug",
 "state":"waiting","at":1700000000000,"workingSince":1699999990000,"touched":1700000000500}
```

- `state`: `idle` | `working` | `waiting` | `done`
- `at`: when the file entered its current `state`. **Only updated when `state` changes.** The app uses `at` to decide whether something new happened.
- `workingSince`: when the current turn began. Set on the transition from `idle`/`done`/absent into `working`/`waiting`; kept while moving between `working` and `waiting`; **kept when moving to `done`** (so the file alone tells how long the turn lasted); omitted when moving to `idle`. A `done` written on a missing file has no `workingSince`.
- `touched`: time of the last event of any kind.
- `title`: first 80 chars of the last user prompt, whitespace collapsed. Only changed by prompt events.
- `cwd`: from payload `cwd`, else first of `workspace_roots`. Keep the previous value if the payload has none.

## 3. Normalization

Input fields (first present wins): session = `session_id` | `sessionId` | `conversation_id`; event = `hook_event_name` | `hookEventName`.
Match event names **case-insensitively**.

| Event (any tool) | Result |
|---|---|
| `UserPromptSubmit`, `beforeSubmitPrompt`, `userPromptSubmitted` | `working`, and set `title` from `prompt` |
| `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionDenied`, `postToolUse`, `preToolUse` | `working` |
| `SessionStart` | `idle` only if no file exists; otherwise touch only |
| `PermissionRequest` | `waiting` |
| `Notification` with `notification_type` in `permission_prompt`, `elicitation_dialog`, `elicitation_url_dialog` | `waiting`, **unless** current state is `done` or `idle` (then touch only) |
| `Notification` with no `notification_type` | `waiting` only if `message` contains "permission" (case-insensitive), same unless-rule; otherwise touch only |
| `Stop`, `agentStop`, `StopFailure` | `done` |
| Cursor `stop` | `done` if `status` is `completed`; `idle` if `aborted` or `error` |
| `SessionEnd`, `sessionEnd` | delete the file |
| anything else (`Notification` of other types such as `idle_prompt`, `PreCompact`, `SubagentStop`, ...) | touch only (update `touched`, never `state`) |

`Notification` `idle_prompt` is deliberately ignored: it fires about 60 s after Claude finished and is the main source of fake alerts.

Touch-only on a missing file does nothing. A new `working`/`waiting`/`done` event on a missing file creates it.
If the resulting `state` equals the existing one, keep `at` and `workingSince`, update only `touched` (and `title`/`cwd` when applicable).

## 4. Detector (app side)

Poll the state dir every 1 s. Keep, per `tool+session`, the last seen `at` and the last alert time. Alert rules:

- **Priming:** the first poll after app start only records baselines. It never alerts.
- **needsAttention**: `state == waiting` and `at` is newer than the last seen `at`, and the previous alert of this kind for this session was more than 30 s ago.
- **finished**: `state == done` and `at` is newer than the last seen `at`, and `workingSince` is present and `at - workingSince >= 20 s`. A turn shorter than 20 s, or of unknown start, never alerts. (Threshold configurable in the app, default 20 s.)
- A session whose file `touched` is older than 15 min is shown as `idle` and never alerts.
- `waiting` older than 30 min is still shown but never re-alerts.
- Removing a file clears the session without alerting.

## 5. Per-tool installation

All installers are consent-based, write a timestamped backup before the first change, never touch entries they did not create, write atomically, and are idempotent. Recognise our entries by the marker `dumpcito-hook` inside the command.

Command shapes (`<exe>` = full path of the Dumpcito executable):

- macOS: `[ -x '<exe>' ] && '<exe>' --hook --tool <tool> >/dev/null 2>&1; exit 0 # dumpcito-hook`
- Windows: `"<exe>" --hook --tool <tool>` (exit code is forced to 0 by the app itself). Marker: because there is no comment syntax portable across shells, recognise ours by the `--hook --tool` substring plus the exe file name `Dumpcito.exe`.

| Tool | Config file | Shape | Events we register |
|---|---|---|---|
| `claude` | `~/.claude/settings.json` | `{"hooks":{"<Event>":[{"matcher":"","hooks":[{"type":"command","command":"...","timeout":5}]}]}}` | UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, PermissionDenied, Notification, Stop, StopFailure, SessionStart, SessionEnd |
| `codex` | `~/.codex/hooks.json` (Windows: `%USERPROFILE%\.codex\hooks.json`) | same shape as claude, top-level `"hooks"` | UserPromptSubmit, PreToolUse, PostToolUse, PermissionRequest, Stop, SessionStart, SessionEnd |
| `cursor` | `~/.cursor/hooks.json` | `{"version":1,"hooks":{"<event>":[{"command":"...","timeout":5}]}}` | beforeSubmitPrompt, postToolUse, stop, sessionEnd |

Never register Cursor's permission-style hooks (`beforeShellExecution`, `beforeMCPExecution`, `beforeReadFile`, `preToolUse`, `subagentStart`): invalid output from them blocks the user's action.

Notes shown to the user:
- Codex skips new hooks until trusted: after connecting, the user opens Codex and runs `/hooks` once to trust Dumpcito.
- Cursor and VS Code Copilot expose no "needs you" event, so for them Dumpcito only tells you when a turn finished.
- VS Code Copilot agent hooks also read `~/.claude/settings.json`, so connecting Claude Code covers Copilot in VS Code (finished only). Verify against the live VS Code build; payload field names may be camelCase (handled by section 3).

Detection of installed tools (to pre-tick the connect list): `claude` if `~/.claude` exists or `claude` is on PATH; `codex` if `~/.codex` exists or `codex` on PATH; `cursor` if Cursor.app (macOS) / `%LOCALAPPDATA%\Programs\cursor` (Windows) / `~/.cursor` exists.

## 6. Out of scope (stated honestly to users)

Claude Desktop chat and ChatGPT desktop expose no hooks, so they are not supported. Claude Code inside Claude Desktop (Code tab) shares the Claude Code hooks and works.
