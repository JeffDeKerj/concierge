# NEXT_SESSION

Main tip `cf8c543` (code; this doc lands just after). **Ten picks were built
on 2026-11-27 with the owner away, and none has been tried by the owner
yet.** Questions and the voice now talk to a conversation of the app's own
and the answer is said sentence by sentence as it is written: first words
after about 5 s, where a question after a page build waited 10 to 14 s.
Nestor's own job runner builds the morning page at 07:20, or when the Mac
wakes, tries again if it fails and tells the phone; the Claude desktop task
that did it is switched off, not deleted. The page may fetch nothing from
anywhere and is looked over before it is shown. The owner is warned before
the Claude sign-in ends (20 to 23 December 2026). The briefing skill always
writes the page when a source is refused, keeps dismissed items off, and
an item that comes back with news is shown again. Settings has a microphone
choice, left on the Mac's own. Found on the way: the headset's adapter was
the microphone and sent pure silence while the owner was away, which is the
likely cause of "Nestor did not respond" that morning. The assistant is
called Nestor in everything the owner sees or says; the code and this
repository keep the name Concierge. Session logs:
[2026-11-26b](sessions/2026-11-26b.md), [2026-11-27](sessions/2026-11-27.md),
[2026-11-27b](sessions/2026-11-27b.md).

Reference: [What's stable](stable.md) · [Sharp edges](sharp-edges.md) · [Tried](tried.md).

First things to check: pick 1 below, then that the page was written whole
on Sonnet, whether a section reads "could not be written this morning",
and the stop count (`grep -l -- "stopped by a safety classifier"
~/.claude/projects/./-Users-jeffdekerj-code-swift-concierge/*.jsonl`).

## Next picks

Ordered by the biggest gain, then by what leans on what. Picks 1 to 9 can
be built without the owner. Picks 10 to 15 wait on the owner or on
something outside.

1. **Check the first morning page built by Nestor's own job runner.** On
   2026-11-28 look for a `morning` line in `briefings/runs.jsonl` soon after
   07:20 (or after the Mac woke), a whole page, and "Morning page ready" on
   the phone. If there is no page, switch the Claude desktop task
   `morning-briefing` back on (it is off, not deleted) and read
   `briefings/state/tick.log`.
2. **Show when Nestor cannot hear.** A headset that is switched off stays
   the Mac's microphone and sends pure silence; with the lid closed the Mac's
   own microphone is cut too (see Sharp edges). Today that only leaves a line
   in the log. Show it: the owl with a hand at its ear in the top bar, and one
   notification when the microphone has been silent for a minute while the
   wake word is on. `WakeListener.noteSilence` already knows.
3. **A cost history view** by day from `briefings/runs.jsonl`.
4. **If the filter still stops pages, make the papers section plainer.** Each
   paper gets its title and one line on why it matters to the extraction work,
   with no assay or toxicity detail. Change `~/.claude/skills/briefing/SKILL.md`.
5. **Serve `briefings/` on the tailnet behind Authentik**, so the page can be
   read from the phone, with a home-screen bookmark as the first iPhone view.
   Never without auth: the pages hold personal mail.
6. **A more natural voice: Kokoro on the Mac.** If Jamie stops being enough,
   add Kokoro (small open voice model, runs locally on Apple Silicon) as a
   voice choice next to the Apple voices, with Apple as the fallback.
7. **Run one Refresh through Antigravity.** The backend reads `agy`'s JSON
   but has not built a page. If it cannot reach Gmail and Calendar, note it in
   `tried.md` and leave Claude as the default.
8. **Drop the toolchain pin** in `Scripts/swift-build-flags.sh` once plain
   `swift build` works again.
9. **The rest of the ideas review** is in [ideas-2026-11-27.md](ideas-2026-11-27.md):
   23 ideas not built. The ones with the most in them: a list of promises both
   ways with a ready follow-up draft, the model returning facts while the app
   draws the page, a new WhatsApp message starting a check at once, and a
   better end of turn than a 1.6 s pause.

Waiting on the owner or on something outside:

10. **Check by voice.** These need the owner talking. New on 2026-11-27: an
    answer is said sentence by sentence as it is written (first words after
    about 5 s), and talking over any sentence should stop both the voice and
    the agent. Still open from before: the beak moving with the voice, the
    heard words under the owl, the owl in the screen corner when called with
    the window hidden.
11. **Try the microphone choice with the lid open.** Settings › Voice ›
    Microphone › This Mac's own microphone, then say "Nestor". The log should
    read "listening on MacBook Pro Microphone" and a quiet room about -58
    dBFS. Built with the lid closed, where that microphone is cut, so no sound
    was ever measured on it, and it failed to start on one switch out of three.
12. **Finish French.** It works: on 2026-11-27 the owner pressed Download
    French in Settings › Voice, the files arrived, and "Nestor, qu'est-ce que
    j'ai demain ?" was answered in French, on the Mac. Left to do: the owner
    downloads a Premium French voice (it speaks with Thomas for now), and
    nobody has checked talking over it in French, the French goodbyes, or how
    English names fare in French.
13. **Judge the Sonnet trial around 2026-12-03.** Compare filter stops and page
    quality with the Opus week. Keep Sonnet, or go back: choose Opus under
    Settings › Morning page › Model (`morningModel`) and run
    `defaults delete local.jeffdekerj.concierge model.refresh.claude`.
14. **The owner may remove the old `claude-assistant` Full Disk Access
    entry** in System Settings; Concierge has its own now.
15. **Codex is wired but unchecked, and parked**: the owner has no Codex
    subscription any more (2026-11-27).
    When there is one, fix `CodexBackend.parse` against the real event stream.
