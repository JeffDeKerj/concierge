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
