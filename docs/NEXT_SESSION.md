# NEXT_SESSION

Main tip `e91d233` (code; this doc lands just after). **The owner keeps the
Mac's lid shut at the desk, so the headset is the only microphone**
(owner, 2026-11-28): nothing should depend on the Mac's own microphone.
The first morning page built by Nestor's own job runner worked on
2026-11-28: the Mac woke at 08:35, the page was written at 08:44, whole on
Sonnet in 156 s for $1.39, and the phone got "Morning page ready · nothing
urgent". Three picks were then built and merged that day: the face holds a
wing to its ear and one notification goes out when the headset sends only
silence for a minute (tried live: deaf at 09:06, cleared at 09:07 when the
owner switched the headset on); a Cost History window by day; the
build no longer needs the macOS 26.5 SDK pin; and the pages can be read on
the phone at `https://apps.tailf7bf45.ts.net:39443/today`, owner only, served from Docker. Antigravity cannot build the
page: it has no mail, calendar, chat or Slack tools (see Tried). The
assistant is called Nestor in everything the owner sees or says; the code
and this repository keep the name Concierge. Session logs:
[2026-11-27](sessions/2026-11-27.md), [2026-11-27b](sessions/2026-11-27b.md),
[2026-11-28](sessions/2026-11-28.md).

Reference: [What's stable](stable.md) · [Sharp edges](sharp-edges.md) · [Tried](tried.md).

First things to check: that today's page was written whole, and whether a
section reads "could not be written this morning". The stop count by
`grep -l -- "stopped by a safety classifier" ~/.claude/projects/./-Users-jeffdekerj-code-swift-concierge/*.jsonl`
no longer sees the morning build: the job runner runs with
`--no-session-persistence`, so it leaves no conversation file.

## Next picks

Ordered by the biggest gain. Picks 1 to 4 can be built without the owner.

1. **If the filter still stops pages, make the papers section plainer.** Each
   paper gets its title and one line on why it matters to the extraction work,
   with no assay or toxicity detail. Change `~/.claude/skills/briefing/SKILL.md`.
   On 2026-11-28 the page was whole, so this waits for a stopped section.
2. **Count filter stops in the job runner.** It keeps no conversation, so a
   stop is invisible. `run()` in `tick.py` could look for the classifier's
   words in the JSON result and add a `stopped` count to the `runs.jsonl` line.
3. **A more natural voice: Kokoro on the Mac.** If Jamie stops being enough,
   add Kokoro (small open voice model, runs locally on Apple Silicon) as a
   voice choice next to the Apple voices, with Apple as the fallback.
4. **The rest of the ideas review** is in [ideas-2026-11-27.md](ideas-2026-11-27.md):
   23 ideas not built. The ones with the most in them: a list of promises both
   ways with a ready follow-up draft, the model returning facts while the app
   draws the page, a new WhatsApp message starting a check at once, and a
   better end of turn than a 1.6 s pause. Ideas 5 (the Mac's own microphone)
   no longer applies: the lid stays shut.

Waiting on the owner or on something outside:

6. **Check by voice.** These need the owner talking. New on 2026-11-27: an
    answer is said sentence by sentence as it is written (first words after
    about 5 s), and talking over any sentence should stop both the voice and
    the agent. New on 2026-11-28: the owl's wing at its ear when the
    headset is off, and its tooltip. Still open from before: the beak moving with the voice, the
    heard words under the owl, the owl in the screen corner when called with
    the window hidden.
7. **Finish French.** It works: on 2026-11-27 the owner pressed Download
    French in Settings › Voice, the files arrived, and "Nestor, qu'est-ce que
    j'ai demain ?" was answered in French, on the Mac. Left to do: the owner
    downloads a Premium French voice (it speaks with Thomas for now), and
    nobody has checked talking over it in French, the French goodbyes, or how
    English names fare in French.
8. **Judge the Sonnet trial around 2026-12-03.** Compare filter stops and page
    quality with the Opus week. Keep Sonnet, or go back: choose Opus under
    Settings › Morning page › Model (`morningModel`) and run
    `defaults delete local.jeffdekerj.concierge model.refresh.claude`.
9. **The owner may remove the old `claude-assistant` Full Disk Access
    entry** in System Settings; Concierge has its own now.
10. **Codex is wired but unchecked, and parked**: the owner has no Codex
    subscription any more (2026-11-27).
    When there is one, fix `CodexBackend.parse` against the real event stream.
