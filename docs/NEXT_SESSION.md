# NEXT_SESSION

Main tip `3188b21` (code; this doc lands just after). **Concierge has a
face and a name: Nestor.** The owner sees and says "Nestor" everywhere (window,
menu bar, notifications, wake word); the code, the app file and this
repository keep the working name Concierge. An owl in a concierge's hat rests in the top bar next to the name,
blinking and looking about; it sleeps while Concierge is silenced. A click on
it, Cmd-T or saying "Nestor" starts a conversation: the owl glides to the middle
of the window and grows, shows the words it hears, moves its beak with the
voice, and glides back at the end. When the window is out of sight it appears
in a corner of the screen. The owner chose it from nine styles, all still in
Settings. Also new: "Nestor, show your face" and "hide" move the window,
and the wake listener keeps nothing in the system log. Since 2026-11-27 Nestor
also listens and speaks in French, on the Mac: "Nestor, speak French" and
"Nestor, parle anglais" switch, and Settings › Voice downloads French
recognition itself. The morning page also has a "Keymodule on Slack"
section, and the top bar shows the day under the name, with the time
Nestor last updated itself. Nestor keeps a
short record of each conversation in the system log, numbers only, to read
when it fails to hear (see Sharp edges). Session logs:
[2026-11-26](sessions/2026-11-26.md), [2026-11-26b](sessions/2026-11-26b.md),
[2026-11-27](sessions/2026-11-27.md).

Reference: [What's stable](stable.md) · [Sharp edges](sharp-edges.md) · [Tried](tried.md).

First things to check: that the 07:20 page was written whole on Sonnet,
whether a section reads "could not be written this morning", and the stop
count (`grep -l -- "stopped by a safety classifier"
~/.claude/projects/./-Users-jeffdekerj-code-swift-concierge/*.jsonl`).

## Next picks

1. **Check by voice.** These need the owner talking: the beak moving with
   Concierge's voice, the heard words under the owl, the owl in the screen
   corner when called with the window hidden, and that talking over it
   still stops it. The owner
   confirmed on 2026-11-26 that a click on the owl works with no bip and
   that "Nestor, what's on tomorrow?" is answered.
2. **Finish French.** It works: on 2026-11-27 the owner pressed Download
   French in Settings › Voice, the files arrived, and "Nestor, qu'est-ce que
   j'ai demain ?" was answered in French, on the Mac. Left to do: the owner
   downloads a Premium French voice (it speaks with Thomas for now), and
   nobody has checked talking over it in French, the French goodbyes, or how
   English names fare in French.
3. **Judge the Sonnet trial around 2026-12-03.** Compare filter stops and page
   quality with the Opus week. Keep Sonnet, or go back by deleting `model:` in
   `~/.claude/scheduled-tasks/morning-briefing/SKILL.md` and running
   `defaults delete local.jeffdekerj.concierge model.refresh.claude`.
4. **If the filter still stops pages, make the papers section plainer.** Each
   paper gets its title and one line on why it matters to the extraction work,
   with no assay or toxicity detail. Change `~/.claude/skills/briefing/SKILL.md`.
5. **Choose the wake word's microphone.** An always-open microphone on a
   Bluetooth headset (the owner's Shokz) can switch it into call mode, so
   music sounds flatter while Concierge is open. Add a Settings choice to use
   the Mac's built-in microphone for the wake word.
6. **A more natural voice: Kokoro on the Mac.** If Jamie stops being enough,
   add Kokoro (small open voice model, runs locally on Apple Silicon) as a
   voice choice next to the Apple voices, with Apple as the fallback.
7. **Check that the skill honours dismissed items and keeps `data-key`s**
   on a reworded item, so a dismissed thing does not come back.
8. **The skill stops instead of writing when a source is refused.** With tools
   denied it asked "Tell me to go ahead" instead of writing a page with the
   source marked down, against its own "Unattended runs" rule. Tighten the
   wording in `~/.claude/skills/briefing/SKILL.md`.
9. **Run one Refresh through Antigravity.** The backend reads `agy`'s JSON
   but has not built a page. If it cannot reach Gmail and Calendar, note it in
   `tried.md` and leave Claude as the default.
10. **Codex is wired but unchecked**: no Codex subscription at the moment.
   When there is one, fix `CodexBackend.parse` against the real event stream.
11. **Serve `briefings/` on the tailnet behind Authentik**, so the page can be
   read from the phone, with a home-screen bookmark as the first iPhone view.
   Never without auth: the pages hold personal mail.
12. **ntfy when the morning page is written**, so the phone knows it is ready.
   ntfy runs on spark, so a notice sent while spark is off is lost.
13. **A cost history view** by day from `briefings/runs.jsonl`.
14. **Move the flaky `modelChoiceIsSavedPerBackend` test into `SerialTests`**:
    it shares UserDefaults with other suites.
15. **The owner may remove the old `claude-assistant` Full Disk Access
    entry** in System Settings; Concierge has its own now.
16. **Drop the toolchain pin** in `Scripts/swift-build-flags.sh` once plain
    `swift build` works again.
