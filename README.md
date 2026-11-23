# Dumpcito

A small companion that lives on your desktop. It taps you when a coding agent (Claude Code, Codex, Cursor) needs an answer or finishes a long turn, and, on the Mac, when a meeting is about to start. It stays out of the way the rest of the time.

- **Alerts that matter, driven by hooks only.** A permission prompt, a finished turn that took 20 seconds or more, a meeting about to start. Dumpcito never guesses from transcripts, idle time or window titles, so there are no phantom alerts.
- **It finds you.** Hops to the display you are on. While it needs you it trails your cursor, and holds still when you move toward it so you can click it.
- **Hold to talk.** Hold `Ctrl+Option+Space`, say something, and send your words plus a screenshot to a Claude Code session. Speech is recognised on your Mac.
- **Three skins.** Jelly, Pixel and Pocket. Right-click Dumpcito to switch, mute sounds, pause, or replay the tour.

Two native apps: macOS 14 or later (Apple Silicon or Intel), and Windows 10/11 (x64, tray app). The Windows app is new and has had less real-world testing; see [Windows](#windows).

## Install

Dumpcito is not signed with an Apple Developer ID yet, so macOS will warn you the first time.

1. Download `Dumpcito.zip` from the latest release and unzip it.
2. Check the download: `shasum -a 256 Dumpcito.zip` should match `Dumpcito.zip.sha256` on the release page.
3. Move `Dumpcito.app` to `/Applications`.
4. Open it. macOS says it cannot verify the app. Open **System Settings > Privacy & Security**, scroll down, click **Open Anyway**, and confirm. (Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/Dumpcito.app`.)
5. Follow the short tour. Every step can be skipped.

If you would rather not trust a binary, build it yourself (below). The source is small enough to read.

## Connect your coding agents

The tour lists Claude Code, Codex and Cursor. Connecting adds a small hook to that tool's hook file (`~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.cursor/hooks.json`) so Dumpcito knows exactly when a session needs you or finishes. A tick appears next to a tool once Dumpcito has seen it send an event.

- Claude Code (terminal, VS Code, Desktop Code tab): "needs you" and "finished". Also covers Copilot in VS Code (finished only).
- Codex: "needs you" and "finished". After connecting, open Codex and run `/hooks` once to trust Dumpcito.
- Cursor: "finished" only. Cursor exposes no "needs approval" event.
- Claude Desktop chat and ChatGPT desktop have no hooks and are not supported.

- A timestamped backup (`settings.json.dumpcito-backup-...`) is written before the first change.
- Only entries Dumpcito added are ever touched. Your own hooks and settings are kept.
- The hook runs `Dumpcito --hook`, which writes a small state file per session under `~/.dumpcito/state/`. Alerts come only from these hook events, never from guessing. It never fails loudly and does nothing if Dumpcito has been deleted.
- Disconnect any tool any time from Dumpcito's menu.

Hold-to-talk copies your transcribed prompt to the clipboard so you can paste it into an already open session, or opens a **new** Claude Code session in VS Code with it filled in (you press Enter).

## Levels (experimental, off by default)

Switch on **Levels** in the menu and Dumpcito grows with you. It counts finished Claude Code sessions and meetings you join through Dumpcito, sets your level against your own last four weeks, and gets slightly bigger as you level up. Beating your usual pace earns nothing extra, a quiet week costs nothing, and levels never go down.

- Counts only. No titles, names or content are stored, in `~/Library/Application Support/Dumpcito/progress.json` (owner-only).
- Nothing leaves your Mac, there is no leaderboard, and pausing nudges also pauses counting.
- **Reset levels** in the menu deletes the file.

## Calendar

Dumpcito reads the macOS Calendar app, so it works with any calendar macOS knows about. For Google Calendar, add the account in **System Settings > Internet Accounts > Google** with Calendars switched on. Dumpcito's menu shows whether calendar access is connected.

## Privacy and security

What Dumpcito does, so you can judge it:

- **No network access.** There is no networking code in the app. Speech recognition runs on-device, and Dumpcito refuses to fall back to Apple's servers.
- **What it reads.** The state files its own hook writes (session id, folder, first 80 characters of your last prompt as a title, and state) and, on the Mac, your calendar events (title, time, join link). It does not read transcripts or your code.
- **What it writes.** One small state file per session in `~/.dumpcito/state/`, screenshots in `~/Library/Caches/Dumpcito/captures/`, and, only if you turn Levels on, a counts file in `~/Library/Application Support/Dumpcito/`. All are owner-only (mode 0600, directories 0700). Screenshots older than 24 hours are deleted at launch and before each new capture.
- **Screenshots can contain secrets.** If you send one to an agent that has shell access, the agent can read what is in it. Treat text visible on screen as untrusted input to that agent.
- **Meeting links.** Only `https` links to Zoom, Google Meet and Microsoft Teams are recognised, and a link opens only when you click Join.
- **Nothing sends a prompt without you.** Prompts come only from what you say or type. New sessions open pre-filled and wait for you to press Enter.
- **Local trust boundary.** Any process running as your user can already write to your `~/.claude` folder. Dumpcito does not widen that.

Found a vulnerability? Please open a private security advisory on the GitHub repository rather than a public issue.

## Uninstall

1. Menu > each connected tool (for example **Claude Code: connected**) to disconnect it. This removes only Dumpcito's hook entries.
2. Quit Dumpcito and delete `Dumpcito.app`.
3. Optional cleanup: `~/Library/Caches/Dumpcito`, `~/.dumpcito`, and the backups `~/.claude/settings.json.dumpcito-backup-*` (and the same for `~/.codex/hooks.json`, `~/.cursor/hooks.json`).

## Custom sounds

Dumpcito plays small synthesized blips. To use your own, put `needs-you`, `meeting` or `finished` (`.wav`, `.aiff`, `.mp3` or `.m4a`) in `~/.dumpcito/sounds`. Only use audio you have the right to use.

## Build from source

```
swift test                       # run the tests
scripts/run.sh                   # build and launch build/Dumpcito.app
scripts/make-zip.sh              # universal Dumpcito.zip + SHA-256
scripts/make-dmg.sh              # drag-to-Applications disk image + SHA-256
```

Ad-hoc signing changes the app's identity on every build, so macOS asks for permissions again after each rebuild. To avoid that, create a local code-signing certificate named "Dumpcito Dev" in Keychain Access and build with `DUMPCITO_SIGN_IDENTITY="Dumpcito Dev" scripts/build-app.sh`.

Layout: `BuddyCore` (models), `BuddySessions` (hook, state files, detector, installers), `BuddyCalendar`, `BuddyCapture` (hotkey, screenshot, speech), `BuddyUI` (characters, menu, tour), `BuddyApp` (window, wiring).

## Windows

A native tray app (C#, .NET 8, WPF) with the same hook pipeline and the same alert rules. It passes the same 16 replay scenarios as the Mac app (`spec/scenarios`).

- Download `Dumpcito-windows-x64.zip` from the latest release, unzip, run `Dumpcito.exe`. Windows SmartScreen may warn because the exe is not code-signed yet: **More info > Run anyway**.
- A checklist opens on first run. Connect Claude Code, Codex and/or Cursor; a tick appears once Dumpcito sees that tool send an event.
- Connecting copies `Dumpcito.exe` to `%LOCALAPPDATA%\Dumpcito\` so the hooks keep working if you delete the download.
- Alerts are small cards in the bottom-right corner with a system sound. Tray menu: active sessions, connect checklist, launch at login, quit.
- Not on Windows yet: hold-to-talk, screenshots, calendar nudges, skins and Levels.
- Build: `cd windows && dotnet test tests/Dumpcito.Core.Tests && dotnet publish src/Dumpcito.App -c Release -r win-x64 --self-contained -p:PublishSingleFile=true`.

## How alerts work

Each tool runs `Dumpcito --hook --tool <tool>` on its own events. That writes a small state file per session; the app polls the folder once a second. The full contract is in [spec/HOOK-SPEC.md](spec/HOOK-SPEC.md).

- **Needs you:** a permission request or question. Repeats for the same session are suppressed for 30 seconds.
- **Finished:** a turn that ran at least 20 seconds. Short turns stay quiet.
- Sessions already open when Dumpcito starts never alert, and a session silent for 15 minutes shows as idle.
- Claude Code's `idle_prompt` notification is ignored on purpose; it fires about a minute after a turn ends and is the main source of fake alerts.

## Known limits

- Claude Desktop chat and ChatGPT desktop have no hooks, so they are not supported. Claude Code inside Claude Desktop (the Code tab) works.
- Cursor and Copilot in VS Code expose no "needs approval" event, so for them Dumpcito reports finished turns only. Copilot is covered through the Claude Code hook file and is best effort.
- Codex needs a one-time `/hooks` trust after connecting.
- Codex and Cursor hook formats follow their documentation; if a tool changes its format, the tick in the checklist will not appear.

## License

MIT. See [LICENSE](LICENSE).
