# NEXT_SESSION

Main tip `2f36462` (code; this doc lands just after). **Concierge now talks.**
Urgent alerts are spoken in the Premium voice Jamie, with quiet hours, quiet
during calendar events and a silence button. A microphone button (Cmd-T) or
the wake word "Concierge" starts a spoken conversation answered by the
question box. The owner can talk over it, and after an alert it listens a few
seconds for a reply. Recognition and voices stay on the Mac. The morning
briefing now writes its page section by section, because Anthropic's safety
filter stopped three whole-page writes in a row. It runs on Sonnet for a
one-week trial. Session logs: [2026-11-25](sessions/2026-11-25.md),
[2026-11-26](sessions/2026-11-26.md).

Reference: [What's stable](stable.md) · [Sharp edges](sharp-edges.md) · [Tried](tried.md).

First things to check: that the 07:20 page was written whole on Sonnet,
whether a section reads "could not be written this morning", and the stop
count (`grep -l -- "stopped by a safety classifier"
~/.claude/projects/./-Users-jeffdekerj-code-swift-concierge/*.jsonl`).

## Next picks

1. **Judge the Sonnet trial around 2026-12-03.** Compare filter stops and page
   quality with the Opus week. Keep Sonnet, or go back by deleting `model:` in
   `~/.claude/scheduled-tasks/morning-briefing/SKILL.md` and running
   `defaults delete local.jeffdekerj.concierge model.refresh.claude`.
2. **If the filter still stops pages, make the papers section plainer.** Each
   paper gets its title and one line on why it matters to the extraction work,
   with no assay or toxicity detail. Change `~/.claude/skills/briefing/SKILL.md`.
3. **Choose the wake word's microphone.** An always-open microphone on a
   Bluetooth headset (the owner's Shokz) can switch it into call mode, so
   music sounds flatter while Concierge is open. Add a Settings choice to use
   the Mac's built-in microphone for the wake word.
4. **A more natural voice: Kokoro on the Mac.** If Jamie stops being enough,
   add Kokoro (small open voice model, runs locally on Apple Silicon) as a
   voice choice next to the Apple voices, with Apple as the fallback.
5. **Check that the skill honours dismissed items and keeps `data-key`s**
   on a reworded item, so a dismissed thing does not come back.
6. **The skill stops instead of writing when a source is refused.** With tools
   denied it asked "Tell me to go ahead" instead of writing a page with the
   source marked down, against its own "Unattended runs" rule. Tighten the
   wording in `~/.claude/skills/briefing/SKILL.md`.
7. **Run one Refresh through Antigravity.** The backend reads `agy`'s JSON
   but has not built a page. If it cannot reach Gmail and Calendar, note it in
   `tried.md` and leave Claude as the default.
8. **Codex is wired but unchecked**: no Codex subscription at the moment.
   When there is one, fix `CodexBackend.parse` against the real event stream.
9. **Serve `briefings/` on the tailnet behind Authentik**, so the page can be
   read from the phone, with a home-screen bookmark as the first iPhone view.
   Never without auth: the pages hold personal mail.
10. **ntfy when the morning page is written**, so the phone knows it is ready.
   ntfy runs on spark, so a notice sent while spark is off is lost.
11. **A cost history view** by day from `briefings/runs.jsonl`.
12. **Move the flaky `modelChoiceIsSavedPerBackend` test into `SerialTests`**:
    it shares UserDefaults with other suites.
13. **The owner may remove the old `claude-assistant` Full Disk Access
    entry** in System Settings; Concierge has its own now.
14. **Drop the toolchain pin** in `Scripts/swift-build-flags.sh` once plain
    `swift build` works again.
