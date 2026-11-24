# What's stable

Settled facts about how the app works. Traps are in [sharp-edges.md](sharp-edges.md).

- **Layout.** Swift package, one executable target `ClaudeAssistant`, macOS 14+,
  SwiftUI with `@Observable`. `Scripts/make_app.sh` builds the release binary
  and wraps it as `ClaudeAssistant.app` (display name "Briefing", bundle id
  `local.jeffdekerj.claude-assistant`). Same shape as `finance-update-ui`.
- **Page choice** (`BriefingPage.swift`): today's `briefings/YYYY-MM-DD.html` in
  Europe/London, else the newest file whose stem is a date, else an empty page
  that says to press Refresh. Files with other names are ignored, so backups
  can sit in the folder.
- **Loading** (`BriefingWebView.swift`): the HTML is read from disk and injected
  as a string, so WebKit never serves a cached copy. Links open in the default
  browser. The web view draws no background, so the page's own dark colour shows.
- **Refresh** (`AppModel.refresh`): `claude -p "/briefing"` with the project
  folder as working directory. A watcher checks the file's modification time
  every two seconds and reloads on change; one more check runs after exit. A
  non-zero exit, or an exit with no new file, is shown in red above the page.
- **Follow-up** (`AppModel.ask`): `claude -p --continue --output-format text <q>`.
  When the CLI answers "No conversation found", the question is sent again
  without `--continue`, prefixed with the path of the page on screen.
- **Dark appearance** is forced twice: `NSApplication.shared.appearance` at
  launch and `.preferredColorScheme(.dark)` on the window.
- **Tests** (`Scripts/test.sh`): Swift Testing, pointed at a throwaway folder
  with `CLAUDE_ASSISTANT_DIR` and at `Scripts/claude-stub.sh` with
  `CLAUDE_ASSISTANT_CLAUDE_BIN`. The stub's behaviour comes from a `stub-mode`
  file in that folder. All suites nest under one serialized parent because they
  share the folder.
- **Reopening** re-checks the folder: `NSApplication.didBecomeActiveNotification`
  calls `checkForNewPage`, so a page written by the scheduled task while the app
  sat in the background appears when the app comes forward.
