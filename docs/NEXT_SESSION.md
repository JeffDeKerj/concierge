# NEXT_SESSION

Main tip `1fa68ec`. Remote `origin` is
`git@github.com:JeffDeKerj/claude-assistant.git`. The app opens on today's
briefing page (or the newest, with a notice), rebuilds it headless from a
Refresh button, answers follow-up questions under it, and shows what every run
cost. Since the last handoff it has a "×" on every item that keeps the item off
later pages (`briefings/dismissed.json`, read by the skill), a model picker per
operation in the Agent menu (Claude defaults: Opus for Refresh, Sonnet for
questions), a correct price for continued conversations (the CLI reports the
conversation's running total; the log now charges only the new turn), and it
keeps the reader's place when the same page reloads. 24 tests pass against a
stub. Checked in the app: dismiss, show, forget, the model menu, a Haiku
follow-up, and the scroll position.
Session logs: [2026-11-24](sessions/2026-11-24.md), [2026-11-24b](sessions/2026-11-24b.md),
[2026-11-24c](sessions/2026-11-24c.md).

Reference: [What's stable](stable.md) · [Sharp edges](sharp-edges.md) · [Tried](tried.md).

## Next picks

1. **Check that the skill honours dismissed items.** Tomorrow's scheduled
   run is the first to read `briefings/dismissed.json`. Dismiss two or three
   items today, then see whether tomorrow's page leaves them off, and whether
   one whose thread moved comes back tagged NEW. If the generator ignores the
   file, move the rule higher in `~/.claude/skills/briefing/SKILL.md`. Also
   check that the new page carries `data-key` on its items: without keys, a
   reworded title gets a new key and a dismissed item reappears.
2. **Run one Refresh with the model flag** from the app (`--model opus` by
   default now) and compare its cost line with this morning's $3.24 run
   without the flag. Try Sonnet for Refresh once to see whether the page holds
   up at a lower price. The larger saving is inside the skill: gather mail
   and chats in a cheaper subagent and let the strong model only write.
3. **Run one Refresh through Antigravity.** The backend reads `agy`'s JSON
   (checked with a one-word call) but has not built a page. Pick Antigravity in
   the Agent menu, press Refresh, and see whether `agy` follows the skill file
   it is told to read and whether its tools can reach Gmail and Calendar. If it
   cannot, note it in `tried.md` and leave Claude as the default.
4. **Codex is wired but unchecked**: the owner has no Codex subscription at the
   moment. When one exists again, run a follow-up and a Refresh through it and
   fix `CodexBackend.parse` against the real event stream.
5. **The skill stops instead of writing when a source is refused.** With tools
   denied it answered "Tell me to go ahead" rather than writing a page with the
   source marked down, against its own "Unattended runs" rule. The app now
   shows refused tools by name, so this only matters for the scheduled task.
   Tighten the skill's wording in `~/.claude/skills/briefing/SKILL.md`.
6. **Serve `briefings/` on the tailnet behind Authentik**, so the page can be
   read from the phone. Static files behind caddy-proxy with the usual
   forward-auth; the pages hold personal mail, so never without auth.
7. **An iPhone view.** The page is already phone-width. The simplest first
   step is pick 6 plus a home-screen bookmark; a native view comes later.
8. **ntfy on completion.** Post to the owner's ntfy topic when the scheduled
   run or a Refresh writes a page, so the phone knows the briefing is ready.
   ntfy runs on spark, so a notice sent while spark is off is lost.
9. **A cost history view.** `briefings/runs.jsonl` has every run; the app only
   shows today's total. A small table by day would answer "what does a month
   of briefings cost".
10. **Drop the toolchain pin** in `Scripts/swift-build-flags.sh` once a Command
    Line Tools update makes plain `swift build` work again (also listed in the
    sibling apps).
