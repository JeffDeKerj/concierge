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
- **Agents** (`AgentBackend.swift`): the CLI behind every run is one of
  `ClaudeBackend`, `AntigravityBackend` or `CodexBackend`, chosen in the Agent
  menu (saved in UserDefaults as `agentBackend`) or by `CLAUDE_ASSISTANT_AGENT`.
  A backend knows its binary, its arguments for Refresh and for a question,
  and how to read its output into a `RunReport`.
- **Cost** (`RunReport`, `RunLog.swift`): every run's price, duration, turns,
  tokens and model come from the tool's JSON output (`--output-format json`
  for Claude and agy, `--json` events for Codex). The last Refresh and the last
  reply show under the page with today's total; each run is appended to
  `briefings/runs.jsonl`. A real Refresh on 2026-11-24 cost $4.29 at API
  prices over 60 turns and 4 minutes; a one-word call costs about $0.22
  because the folder's context is written to the cache every time.
- **Headless permissions** (`.claude/settings.json`): pre-allows the skill's
  read-only connector tools, WhatsApp, writes into `briefings/` and the
  headless Chrome check. Honoured only once the folder is trusted in
  `~/.claude.json` (`hasTrustDialogAccepted`).
- **Refresh** (`AppModel.refresh`): the backend's refresh command with the
  project folder as working directory (`claude -p "/briefing" --output-format json`). A watcher checks the file's modification time
  every two seconds and reloads on change; one more check runs after exit. A
  non-zero exit, or an exit with no new file, is shown in red above the page.
- **Follow-up** (`AppModel.ask`): the backend's continue command
  (`claude -p --continue --output-format json <q>`). When the tool answers that
  there is no conversation, the question is sent again as a fresh one,
  prefixed with the path of the page on screen. Refused tools are listed by
  name in the red line.
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
