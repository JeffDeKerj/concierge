# NEXT_SESSION

Main tip `a4f9510`. Remote `origin` is
`git@github.com:JeffDeKerj/claude-assistant.git`. Version 1 landed in `a4f9510` from
branch `app-v1`. It opens on today's briefing
page, falls back to the newest page with a notice, runs the generator headless
from a Refresh button and reloads when the file changes, and sends a follow-up
question to `claude -p --continue`. Branch `headless-refresh-cost` (unmerged)
adds the project allow-list that makes headless runs work, a cost and token
readout for every run, and an `AgentBackend` seam with Claude, Antigravity and
Codex behind an Agent menu. Nineteen tests pass against a stub. A real Refresh
from the app rewrote and reloaded today's page.
Session logs: [2026-11-24](sessions/2026-11-24.md), [2026-11-24b](sessions/2026-11-24b.md).

Reference: [What's stable](stable.md) · [Sharp edges](sharp-edges.md) · [Tried](tried.md).

## Next picks

1. **Grant the app Full Disk Access, then one Refresh from the app.** System
   Settings → Privacy & Security → Full Disk Access → add
   `~/Applications/ClaudeAssistant.app`. The WhatsApp database lives in
   `~/Library/Group Containers`, which macOS protects; the Terminal has the
   grant, the app does not, and a process started by the app is charged to the
   app. The bundle is signed with a stable identity so the grant survives
   rebuilds. Then press Refresh and check the footer lists WhatsApp.
2. **Run one Refresh through Antigravity.** The backend reads `agy`'s JSON
   (checked with a one-word call) but has not built a page. Pick Antigravity in
   the Agent menu, press Refresh, and see whether `agy` follows the skill file
   it is told to read and whether its tools can reach Gmail and Calendar. If it
   cannot, note it in `tried.md` and leave Claude as the default.
3. **Codex is wired but unchecked**: the owner has no Codex subscription at the
   moment. When one exists again, run a follow-up and a Refresh through it and
   fix `CodexBackend.parse` against the real event stream.
4. **The skill stops instead of writing when a source is refused.** With tools
   denied it answered "Tell me to go ahead" rather than writing a page with the
   source marked down, against its own "Unattended runs" rule. The app now
   shows refused tools by name, so this only matters for the scheduled task.
   Tighten the skill's wording in `~/.claude/skills/briefing/SKILL.md`.
5. **Serve `briefings/` on the tailnet behind Authentik**, so the page can be
   read from the phone. Static files behind caddy-proxy with the usual
   forward-auth; the pages hold personal mail, so never without auth.
6. **An iPhone view.** The page is already phone-width. The simplest first
   step is pick 5 plus a home-screen bookmark; a native view comes later.
7. **ntfy on completion.** Post to the owner's ntfy topic when the scheduled
   run or a Refresh writes a page, so the phone knows the briefing is ready.
   ntfy runs on spark, so a notice sent while spark is off is lost.
8. **A cost history view.** `briefings/runs.jsonl` has every run; the app only
   shows today's total. A small table by day would answer "what does a month
   of briefings cost".
9. **An app icon.** The bundle has none; copy the sibling's `Resources/make_icon.py`
   approach and add `CFBundleIconFile` to `Scripts/make_app.sh`.
10. **Page scroll position on launch.** The very first launch showed the page
   scrolled to the middle; every later launch opened at the top. Not reproduced.
   If it comes back, scroll to the top after each load in `BriefingWebView`.
11. **Drop the toolchain pin** in `Scripts/swift-build-flags.sh` once a Command
    Line Tools update makes plain `swift build` work again (also listed in the
    sibling apps).
