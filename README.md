# Claude Assistant

A small macOS app that opens on the morning briefing page. The page itself is
built by the `briefing` skill in Claude Code (`~/.claude/skills/briefing/`),
which writes `briefings/<YYYY-MM-DD>.html` from Gmail, Google Calendar,
WhatsApp and the Obsidian digests. A scheduled task in the Claude desktop app
runs it every morning at about 07:20.

The app does three things:

- shows today's page in a web view, or the newest one with a one-line notice
  when today's is not there yet;
- **Refresh** (toolbar, or ⌘R) runs the generator headless, `claude -p "/briefing"`,
  in this folder, shows a spinner, and reloads the page as soon as the file changes;
- the field at the bottom sends a follow-up question to `claude -p --continue`
  and shows the reply under the page;
- a line under the page says what the last Refresh and the last reply cost,
  how long they took and how many tokens they used, plus today's total. These
  are API prices: on a subscription nothing is billed, but it is what the same
  calls would cost. Every run is appended to `briefings/runs.jsonl`.

`briefings/` is gitignored: the pages hold personal mail.

## Which agent runs

The Agent menu picks the CLI behind Refresh and the follow-up: Claude Code
(the default, checked end to end), Antigravity (`agy`, its JSON checked) or
Codex (`codex exec`, not yet checked). Each is one file in
`Sources/ClaudeAssistant/` implementing `AgentBackend`: where its binary is,
which arguments build the page or ask a question, and how to read its output.
Adding another tool means adding one such file and listing it in
`AgentBackends.all`. Only Claude has the `/briefing` skill as a command; the
others are told to read the skill file and follow it.

## Headless permissions

A headless run cannot ask for permission, so `.claude/settings.json` in this
folder pre-allows what the skill needs: the read-only Gmail and Calendar
tools, WhatsApp, writes into `briefings/`, and the headless Chrome check. The
CLI only honours that file once the folder is trusted: run `claude` here once
interactively and accept the trust dialog, or set
`projects["<this folder>"].hasTrustDialogAccepted: true` in `~/.claude.json`.
The CLI must also be logged in (`claude auth status`).

## Build and run

Plain `swift build` fails on this box since the 2026-09-10 Command Line Tools
update; the scripts source `Scripts/swift-build-flags.sh`, which pins the
working SDK.

```bash
./Scripts/make_app.sh       # release build, then ClaudeAssistant.app
open ClaudeAssistant.app
./Scripts/test.sh           # Swift Testing, against a stub claude
```

`open ClaudeAssistant.app --args --refresh` starts a Refresh at launch.

Environment overrides, for tests and scripted runs:

| Variable | Meaning |
| --- | --- |
| `CLAUDE_ASSISTANT_DIR` | the project folder to use instead of this one |
| `CLAUDE_ASSISTANT_CLAUDE_BIN` | the `claude` binary to run instead of the installed one |
| `CLAUDE_ASSISTANT_AGY_BIN`, `CLAUDE_ASSISTANT_CODEX_BIN` | the same for the other agents |
| `CLAUDE_ASSISTANT_AGENT` | `claude`, `antigravity` or `codex`, overriding the Agent menu |

## Handoff

`docs/NEXT_SESSION.md` is the handoff: what works, what is next, and the traps.
