# Sharp edges

Traps and non-obvious constraints, one bullet each.

- **Build flags.** Plain `swift build` / `swift test` fail on this box since the
  2026-09-10 Command Line Tools update; always go through
  `Scripts/swift-build-flags.sh` (`make_app.sh` and `test.sh` already do). There
  is no XCTest in the Command Line Tools; tests are Swift Testing.
- **The CLI must be logged in.** The app runs the standalone `~/.local/bin/claude`.
  Logged out, both Refresh and the follow-up fail with an authentication line
  in red; `claude auth login` in a terminal fixes it. Logged in, the CLI also
  sees the claude.ai Gmail and Google Calendar connectors (as
  `mcp__claude_ai_Gmail__…` and `mcp__claude_ai_Google_Calendar__…`); logged
  out, `claude mcp list` does not show them at all.
- **Permissions need a trusted folder.** `.claude/settings.json` is ignored,
  with a stderr warning, until the folder is trusted in `~/.claude.json`. In
  print mode a refused tool is a silent denial: the run "succeeds" with no
  page. The app now lists refused tools from the JSON `permission_denials`.
- **`--continue` reports the conversation's running total.** `total_cost_usd`
  of a continued run includes every earlier turn of that session (a $0.22
  Haiku reply came back as $3.46 after a $3.24 Refresh). The log subtracts the
  last total of the same `session_id`; anything that reads the CLI's JSON
  directly must do the same.
- **Menu views get no environment.** A view inside `.commands { }` that uses
  `@Environment(AppModel.self)` crashes at launch with an assertion in
  `EnvironmentValues`; pass the model in as a property instead.
- **agy's model list is long and changes.** `AntigravityBackend.models` holds
  five of them, copied from `agy models` on 2026-11-24; the CLI, not the app,
  is the reference. A model it no longer lists falls back to Default.
- **agy's `status` is upper-case** (`"SUCCESS"`); compare it case-insensitively.
  Its duration is `duration_seconds`, not milliseconds, and it reports no price.
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
- **WhatsApp needs Full Disk Access for the app.** The chat database is under
  `~/Library/Group Containers`. On this macOS that is the "App Data" privacy
  category (`kTCCServiceSystemPolicyAppDataDetailed`), which never prompts: the
  log shows "does not allow prompting; recording denied" for the app at the
  moment the WhatsApp server opened the database (2026-11-24 09:30). macOS
  charges the whole process tree to the app that started it, so granting `uv`
  or `claude` does nothing for in-app runs. Full Disk Access covers App Data
  and is the grant to give `~/Applications/ClaudeAssistant.app`. A run from
  the Terminal works because the Terminal already has it.
- **Grants on bare CLI binaries do not last.** The owner added `uv` to the
  privacy settings a few days ago and the entry vanished, with no macOS
  update and no change to `uv` in between. The App Data category keys entries
  to the accessing app and its code identity; a CLI tool with an ad-hoc
  signature is a poor subject for it. Grant the app bundle, signed with the
  stable identity, rather than the tools it runs. To watch what macOS decides:
  `log show --last 1d --predicate 'subsystem == "com.apple.TCC"' | grep AppData`.
- **Rebuilds and privacy grants.** Full Disk Access is keyed to the code
  identity. `make_app.sh` signs with the stable local identity "Finance
  Advisor Dev" (shared with the sibling apps) so a grant survives rebuilds; an
  ad-hoc build is a new app to macOS every time. `Scripts/make_signing_cert.sh`
  creates the identity if it is ever missing.
