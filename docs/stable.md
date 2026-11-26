# What's stable

Settled facts about how the app works. Traps are in [sharp-edges.md](sharp-edges.md).

- **Layout.** Swift package, one executable target `Concierge`, macOS 14+,
  SwiftUI with `@Observable`. `Scripts/make_app.sh` builds the release binary
  and wraps it as `Concierge.app` (display name "Concierge", bundle id
  `local.jeffdekerj.concierge`, icon from `Resources/AppIcon.icns`,
  signed with the Mac's stable local identity). Same shape as `finance-update-ui`.
- **Page choice** (`BriefingPage.swift`): today's `briefings/YYYY-MM-DD.html` in
  Europe/London, else the newest file whose stem is a date, else an empty page
  that says to press Refresh. Files with other names are ignored, so backups
  can sit in the folder.
- **Loading** (`BriefingWebView.swift`): the HTML is read from disk and injected
  as a string, so WebKit never serves a cached copy. Links open in the default
  browser. The web view draws no background, so the page's own dark colour shows.
- **Agents** (`AgentBackend.swift`): the CLI behind every run is one of
  `ClaudeBackend`, `AntigravityBackend` or `CodexBackend`, chosen in the Agent
  menu (saved in UserDefaults as `agentBackend`) or by `CONCIERGE_AGENT`.
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
- **Snooze.** A "⏱" under each item's "×" hides it until 06:00 tomorrow or next Monday (`until` in `dismissed.json`); expired snoozes are dropped by the app and brought back by the skill tagged BACK.
- **Dismissed items** (`PageScript.swift`, `DismissStore.swift`): the app injects a
  script into every page that puts a "×" on each top-level item of the four
  list sections. A press hides the item and records it in
  `briefings/dismissed.json` (pretty JSON: key, title, source, section,
  dismissedAt). Each section shows "n dismissed · Show" to reveal and restore
  ("↩") them; View > Forget Dismissed Items empties the file. The briefing
  skill reads the file and leaves those items off the next page unless the
  source moved since. Keys are the page's `data-key`, else the Gmail thread
  id in the item's link, else the item's own words.
- **Model per operation** (`ModelSettings`): the Agent menu has "Model for
  Refresh" and "Model for Questions", one list per backend, saved in
  UserDefaults as `model.<refresh|ask>.<backend>`. Claude defaults to Opus
  for Refresh and Sonnet for questions; a saved id the backend no longer
  lists falls back to that default. The choice is passed as `--model` (agy
  too) or `-m` (Codex).
- **A continued conversation is charged its own share.** `RunReport.sessionID`
  and `RunLog.Entry.sessionCostUSD` keep the running total the CLI reports;
  the entry's `costUSD` and the cost line show the difference from the last
  run of the same session.
- **Scroll position** (`BriefingWebView`): the same file reloading keeps the
  reader's place; a different page or the first load starts at the top.
- **Dark appearance** is forced twice: `NSApplication.shared.appearance` at
  launch and `.preferredColorScheme(.dark)` on the window.
- **Tests** (`Scripts/test.sh`): Swift Testing, pointed at a throwaway folder
  with `CONCIERGE_DIR` and at `Scripts/claude-stub.sh` with
  `CONCIERGE_CLAUDE_BIN`. The stub's behaviour comes from a `stub-mode`
  file in that folder. All suites nest under one serialized parent because they
  share the folder.
- **Reopening** re-checks the folder: `NSApplication.didBecomeActiveNotification`
  calls `checkForNewPage`, so a page written by the scheduled task while the app
  sat in the background appears when the app comes forward.
- **Voice.** `Speaker.swift` lists English voices best first (Premium,
  Enhanced) and speaks for `--say`; a running window takes the alert over a
  distributed notification so it can listen afterwards. `Conversation.swift`
  runs the spoken loop on `VoiceIO.swift` (one engine, echo cancellation,
  interrupting); `WakeListener.swift` waits for "Concierge", on-device only,
  through the same engine, which it holds open while the wake word is on.
  Speaking rules (hours, events, silence) are in `tick.py` and tested in
  `Tests/python`. Settings keys: `speak`, `voice`, `speakFrom`, `speakTo`,
  `quietInEvents`, `silenceUntil`, `listenAfter`, `interruptible`, `wakeWord`.
- **Face.** `Face.swift` holds the rules as plain functions (expression from
  the conversation state, a pose per expression, blink, gaze, picture rate);
  `FaceView.swift` draws a pose in one of nine styles (`Face.Style`, default
  owl, Settings key `face`). The resting face is `FaceButton` in the top bar
  (`toolbar.talk`, Cmd-T); `StagedFace` is the big one that glides to the
  middle during a conversation; `FacePanel.swift` shows it in a screen corner
  when the window is out of sight (Settings key `floatingFace`). The mouth
  follows `VoiceIO.level(at:)`. `FACE_SHEET=<file.png> Scripts/test.sh
  --filter Face` draws every style in every expression into a picture.
- **Window commands by voice**: `Conversation.windowCommand` ("show your
  face", "hide"), handled before the model is asked.
- **Scheduled jobs run through the app**: launchd starts
  `Concierge --tick`, so Concierge's Full Disk Access covers WhatsApp, and
  `tick.py` runs with Homebrew on PATH and `--no-session-persistence`.
