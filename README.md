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
  and shows the reply under the page.

`briefings/` is gitignored: the pages hold personal mail.

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

## Handoff

`docs/NEXT_SESSION.md` is the handoff: what works, what is next, and the traps.
