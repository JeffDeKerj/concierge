# Sharp edges

Traps and non-obvious constraints, one bullet each.

- **Build flags.** Plain `swift build` / `swift test` fail on this box since the
  2026-09-10 Command Line Tools update; always go through
  `Scripts/swift-build-flags.sh` (`make_app.sh` and `test.sh` already do). There
  is no XCTest in the Command Line Tools; tests are Swift Testing.
- **The CLI must be logged in.** The app runs the standalone `~/.local/bin/claude`
  (2.1.284 on 2026-11-24). `claude auth status` reported `loggedIn: false`, and
  the desktop app's bundled copy was logged out too. A logged-out CLI makes both
  Refresh and the follow-up fail with an authentication line in red. Nothing in
  the app can fix that; the owner logs in once in a terminal.
- **Headless runs do not see the desktop app's connectors.** Gmail and Google
  Calendar are claude.ai connectors injected by the desktop app; `claude mcp list`
  from a shell does not show them. A Refresh from the app writes a page with
  those sources marked down. See pick 2 in [NEXT_SESSION.md](NEXT_SESSION.md).
- **Refresh overwrites today's page.** The skill writes the same date's file
  again. If the scheduled run produced a good page and the headless run has
  fewer sources, Refresh replaces the better page with the poorer one. Copy the
  page to a non-date name first if it matters (the locator ignores such files).
- **Window owner name is "Briefing", not "ClaudeAssistant".** Anything that
  finds the window by owner (`CGWindowListCopyWindowInfo`, `screencapture -l`)
  must use the display name from `Info.plist`.
- **No scripting without Accessibility.** `osascript` System Events calls fail
  with "not allowed assistive access" from Claude's shell. To photograph the
  app, find the window id with CoreGraphics and use `screencapture -x -l <id>`;
  that needs only Screen Recording, which is granted.
- **Test suites share one folder.** Swift Testing runs suites in parallel; two
  suites resetting the same fixture folder corrupt each other. Every suite nests
  under `SerialTests`, which carries `.serialized`.
- **`open … --args` reaches only a fresh launch.** If the app is already running,
  `open` brings it forward and drops the arguments and environment. Quit first.
