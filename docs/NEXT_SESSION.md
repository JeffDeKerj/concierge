# NEXT_SESSION

Main tip `099d358` (the initial commit: only `.gitignore`). The whole app is on
branch `app-v1`, unmerged and unpushed. Version 1 opens on today's briefing
page, falls back to the newest page with a notice, runs the generator headless
from a Refresh button and reloads when the file changes, and sends a follow-up
question to `claude -p --continue`. Ten tests pass against a stub `claude`.
Session log: [2026-11-24](sessions/2026-11-24.md).

Reference: [What's stable](stable.md) · [Sharp edges](sharp-edges.md) · [Tried](tried.md).

## Next picks

1. **Log the CLI in, then run one real Refresh.** `claude auth status` says
   `loggedIn: false` on this Mac, so headless `claude -p` answers "OAuth session
   expired" and Refresh shows that error (seen 2026-11-24). Run `claude auth login`
   in a terminal, or `claude setup-token` and set `CLAUDE_CODE_OAUTH_TOKEN` for
   unattended runs. Then press Refresh in the app and check the page is rewritten
   and reloaded. Only the owner can do the login.
2. **Gmail and Google Calendar are not visible to the headless CLI.** `claude mcp
   list` shows WhatsApp, recall, bioextract and data-manager, but the Gmail and
   Calendar connectors exist only inside the desktop app, which injects them. A
   Refresh from the app will therefore write a page with mail and calendar
   marked down in the footer. Options: make the desktop scheduled task the only
   generator and have Refresh trigger it (`run_scheduled_task`, if reachable
   from outside); or register the two connectors for the CLI with
   `claude mcp add --transport http …` if claude.ai connectors can be added that
   way. Decide before relying on Refresh.
3. **Serve `briefings/` on the tailnet behind Authentik**, so the page can be
   read from the phone. Static files behind caddy-proxy with the usual
   forward-auth; the pages hold personal mail, so never without auth.
4. **An iPhone view.** The page is already phone-width. The simplest first
   step is pick 3 plus a home-screen bookmark; a native view comes later.
5. **ntfy on completion.** Post to the owner's ntfy topic when the scheduled
   run or a Refresh writes a page, so the phone knows the briefing is ready.
   ntfy runs on spark, so a notice sent while spark is off is lost.
6. **An app icon.** The bundle has none; copy the sibling's `Resources/make_icon.py`
   approach and add `CFBundleIconFile` to `Scripts/make_app.sh`.
7. **Page scroll position on launch.** The very first launch showed the page
   scrolled to the middle; every later launch opened at the top. Not reproduced.
   If it comes back, scroll to the top after each load in `BriefingWebView`.
8. **Drop the toolchain pin** in `Scripts/swift-build-flags.sh` once a Command
   Line Tools update makes plain `swift build` work again (also listed in the
   sibling apps).
