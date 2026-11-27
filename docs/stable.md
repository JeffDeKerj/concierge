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
  read-only connector tools, WhatsApp, three Slack reading tools (search,
  read a channel, read a thread), writes into `briefings/` and the
  headless Chrome check. Slack's writing tools are denied for every run in
  `~/.claude/settings.json`. Honoured only once the folder is trusted in
  `~/.claude.json` (`hasTrustDialogAccepted`).
- **Refresh** (`AppModel.refresh`): the backend's refresh command with the
  project folder as working directory (`claude -p "/briefing" --output-format json`). A watcher checks the file's modification time
  every two seconds and reloads on change; one more check runs after exit. A
  non-zero exit, or an exit with no new file, is shown in red above the page.
- **Questions** (`AppModel.ask`, `AskSession.swift`): the question box and
  the voice talk to a conversation of the app's own, never to a page build
  or a check. The first question starts it (`claude -p --session-id <id>`)
  and is told the page as plain words, today's updates and where the files
  are; later ones resume it (`--resume <id>`) with only their own words,
  plus any updates written since. The conversation is kept in
  `briefings/state/ask.json` and replaced on a new day, a rebuilt page,
  another agent, or when the tool no longer has it. Measured 2026-11-27 on
  Haiku: a fresh question carries about 52,000 tokens and takes 4.5 s, where
  one that continued a page build carried 135,000 to 195,000 and took 10 to
  14 s. Agents that cannot name a conversation continue their latest one.
  Refused tools are listed by name in the red line.
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
- **Sign-in watch** (`check_signin` in `tick.py`). Once a day, from the hour
  the checks start, the job runner reads `claude auth status`. The mail,
  calendar and Slack connectors need that sign-in, and it has an end date
  (`loginExpiresAt`, which the tool says may come up to three days sooner).
  The owner is told 10, 5, 2 and 1 days before the earliest day, then every
  day, and at once when signed out: an entry in today's updates with the
  key `topic:claude-sign-in`, so it shows on the page, as a notification,
  on the phone and aloud. On 2026-11-27 the sign-in ran to 20 to 23
  December 2026.
- **The page is not trusted** (`PageGuard.swift`). It is written by a model
  that has just read mail and chats, so the app adds a rule as the first
  thing in its head (`Content-Security-Policy: default-src 'none'`, with
  the page's own `<style>` allowed): no picture, script, style sheet, font
  or frame is fetched from anywhere. The page view shows only the page
  itself; a clicked web or mail link opens in the browser; a page that
  tries to go elsewhere by itself is refused. The app's own page script is
  not held by the rule. `PageGuard.problems` looks the page over and the
  window shows a yellow line for links outside the papers that go to sites
  other than Google, Slack, GitHub, arXiv and doi.org, links that are not
  plain `https`, and items with no `data-key`. `PageGuardLiveTests` loads
  a hostile page in a real web view beside a listener and counts fetches.
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
- **Answers come in pieces** (`AgentRunner.run(onLine:)`,
  `ClaudeBackend.streamingAskArguments`, `SentenceCutter.swift`). Claude is
  asked with `--output-format stream-json --verbose
  --include-partial-messages`; each `text_delta` line adds to the answer on
  screen, and the last `result` line is the report. In a spoken
  conversation `SentenceCutter` hands each whole sentence to
  `VoiceIO.say(parts:)`, which says them one after the other under one
  listening turn, so talking over any sentence stops it and stops the
  agent (`AppModel.cancelAsk`, which is not an error). Measured 2026-11-27:
  first words 4.8 s after the question, where the whole answer took 7 s
  before any sound. `Concierge --ask "<question>" [--spoken]` asks from a
  shell through the same path and prints each sentence with its time.
- **Face.** `Face.swift` holds the rules as plain functions (expression from
  the conversation state, a pose per expression, blink, gaze, picture rate);
  `FaceView.swift` draws a pose in one of nine styles (`Face.Style`, default
  owl, Settings key `face`). The resting face is `FaceButton` in the top bar
  (`toolbar.talk`, Cmd-T); `StagedFace` is the big one that glides to the
  middle during a conversation; `FacePanel.swift` shows it in a screen corner
  when the window is out of sight (Settings key `floatingFace`). The mouth
  follows `VoiceIO.level(at:)`. `FACE_SHEET=<file.png> Scripts/test.sh
  --filter Face` draws every style in every expression into a picture.
- **The name is Nestor** in everything the owner sees or says: `Brand.name`
  for the window title, tooltips and the wake word, `DISPLAY_NAME` in
  `Scripts/make_app.sh` for the menu bar and Dock, `NAME` in `Scripts/tick.py`
  for notifications, and the greeting in the briefing skill's `example.html`.
  The app file, executable, bundle identifier, repository and skills stay
  "Concierge", so the scheduler's path and the privacy grants hold.
  `CalledName` finds the name in what was heard.
- **Languages.** `Language.swift`: English or French for spoken
  conversations only (Settings keys `language`, `voiceFr`, `frenchOnline`).
  `VoiceIO.use(_:allowOnline:)` sets the recogniser and refuses a language
  this Mac cannot recognise by itself unless Apple's servers are allowed;
  the wake listener never uses them and listens in English when French is
  not on the Mac. "Speak French" / "parle anglais" switch by voice
  (`Language.asked`). Alerts are written and said in English.
  `Phrases.plain` strips accents and punctuation before phrases are matched.
  `SpeechDownload.swift` fetches a language's recognition files from the
  app (`AssetInventory`, macOS 26 and later) behind the `SpeechFiles`
  protocol; it asks for the `DictationTranscriber` files, the ones
  `SFSpeechRecognizer` uses on the Mac.
- **Window commands by voice**: `Conversation.windowCommand` ("show your
  face", "hide"), handled before the model is asked.
- **Scheduled jobs run through the app**: launchd starts
  `Concierge --tick`, so Concierge's Full Disk Access covers WhatsApp, and
  `tick.py` runs with Homebrew on PATH and `--no-session-persistence`.
- **The morning page is one of those jobs** since 2026-11-27 (`morning_due`
  in `tick.py`, Settings keys `morningAt` 07:20 and `morningModel` sonnet).
  It runs `/briefing` at the first tick after the set time while today's
  page is missing, so a Mac that slept through 07:20 builds it on waking.
  A failed build is tried again after 30 minutes, three times a day at
  most. A page left half-written (it still holds `<!-- S:` markers and has
  not changed for ten minutes) counts as missing. Each build is a `morning`
  line in `runs.jsonl`. When the page is written the phone gets "Morning
  page ready · 2 urgent items" through ntfy (`morning_notice`), or after
  the last failed try that there is no page today. The Claude desktop task `morning-briefing` that did
  this before is switched off, not deleted.
