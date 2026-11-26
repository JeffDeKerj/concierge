# Tried

Ideas tried that did not deliver. One entry per idea: the date, the idea, the
result, why it fell short, what would change the verdict, and where the detail is.

- **2026-11-24 · Drive the app with `osascript` System Events** to click Refresh
  and read the window for the launch check. Result: every call failed with
  "osascript is not allowed assistive access" from Claude's shell. Fell short
  because Accessibility is not granted to that process, and granting it is the
  owner's call. Verdict changes if the owner grants Accessibility to the
  terminal host that runs these sessions; until then the app exposes
  accessibility identifiers (`toolbar.refresh`, `followup.input`, …) and a
  `--refresh` launch flag, and the logic is covered by tests against a stub.
  Detail: [sessions/2026-11-24.md](sessions/2026-11-24.md).

- **2026-11-26: drawing the resting face with SwiftUI.** A `TimelineView`
  with a `Canvas` in the window cost 8% CPU at 30 pictures a second and still
  5% at 8, because each picture made the whole window lay itself out. The
  same view in its own `NSHostingView` cost 0.5% beside the question box, but
  9% once the face moved to the top bar, where each picture made the toolbar
  measure its items again. It fell short because the cost is in the layout
  around the picture, not in the drawing. Kept instead: an AppKit view that
  sets its layer's picture, about 1% with the wake word on. Verdict changes
  if the face leaves the top bar for a place inside the page, where the
  hosting view was cheap. Detail: [sessions/2026-11-26b.md](sessions/2026-11-26b.md).

- **2026-11-26: voice processing switched on all day.** To stop the headset's
  bip, the wake word and the conversation were put on one always-running
  engine with echo cancellation on. The bip went, but the app used 24% of a
  core at rest: the Mac's voice processor runs a noise-removal model on every
  buffer. Kept instead: the same engine with voice processing bypassed
  outside a conversation, 2.3% at rest and no volume change. Verdict changes
  only if Apple makes the processor cheap. Detail:
  [sessions/2026-11-26b.md](sessions/2026-11-26b.md).

