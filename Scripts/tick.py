"""Run Concierge's daytime jobs when they are due. launchd starts this every
15 minutes (Scripts/com.concierge.tick.plist). It reads briefings/settings.json
itself, so a job that is switched off or paused costs no tokens.

Jobs, each a Claude Code skill run headless in the project folder:
  briefing          the morning page, when today's is not written yet
  concierge-check   new urgent things since the last look
  concierge-prep    a note before a calendar event (from briefings/agenda/<day>.json)
  concierge-wrapup  the evening summary
Each run is logged to briefings/runs.jsonl like the app's own runs, and new
entries in briefings/updates/<day>.json marked "notify" become a Mac
notification and an ntfy message. The phone is also told when the morning
page is ready, or that it could not be built.
"""
from __future__ import annotations

import datetime as dt
import fcntl
import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(os.environ.get("CONCIERGE_DIR", Path(__file__).resolve().parent.parent))
B = ROOT / "briefings"
CLAUDE = os.environ.get("CONCIERGE_CLAUDE_BIN", str(Path.home() / ".local/bin/claude"))
NTFY = os.environ.get("CONCIERGE_NTFY", "https://apps.tailf7bf45.ts.net:31443/concierge")
DEFAULTS = dict(pausedOn=None, morning=True, morningAt="07:20", morningModel="sonnet", morningTries=3,
                morningRetryMinutes=30, checks=True, checkEveryMinutes=120, checkFrom="09:00",
                checkTo="19:00", prep=True, prepMinutes=30, wrapup=True, wrapupAt="18:30",
                notifyMac=True, notifyPhone=True, checkModel="haiku", prepModel="sonnet",
                wrapupModel="sonnet", speak=True, voice="", speakFrom="08:30", speakTo="21:00",
                quietInEvents=True, silenceUntil=None)
NAME = "Nestor"  # what the owner calls it: the title of every notification
APP = os.environ.get("CONCIERGE_APP")  # set by the app's --tick launcher


def read_json(path: Path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def hm(text: str) -> dt.time:
    h, m = text.split(":")
    return dt.time(int(h), int(m))


def page_done(page: Path, now: dt.datetime) -> bool:
    """Whether today's page is written. The skill writes it in parts, with a marker
    where each part goes: a page that still has markers and has not changed for ten
    minutes was left half-written by a run that died."""
    try:
        text = page.read_text(errors="replace")
        changed = dt.datetime.fromtimestamp(page.stat().st_mtime)
    except OSError:
        return False
    return "<!-- S:" not in text or now - changed < dt.timedelta(minutes=10)


def morning_due(s: dict, state: dict, now: dt.datetime, page_written: bool) -> bool:
    """Whether to build the morning page now: after the set time, while today's page
    is missing, a few tries at most with a pause between them. A Mac that slept
    through the set time builds the page at its first tick after waking. Pure, for tests."""
    if not s["morning"] or page_written or now.time() < hm(s["morningAt"]):
        return False
    tries = state.get("morning") or {}
    if tries.get("day") != now.date().isoformat():
        return True
    if tries.get("count", 0) >= s["morningTries"]:
        return False
    try:
        last = dt.datetime.fromisoformat(tries["last"])
    except (KeyError, ValueError):
        return True
    return now - last >= dt.timedelta(minutes=s["morningRetryMinutes"])


def due_jobs(s: dict, state: dict, now: dt.datetime, agenda: list,
             page_written: bool = True) -> list[tuple[str, str, str]]:
    """(kind, skill argument, model) for every job due now. Pure, for tests."""
    today = now.date().isoformat()
    if s.get("pausedOn") == today:
        return []
    jobs = []
    if morning_due(s, state, now, page_written):
        jobs.append(("morning", "/briefing", s["morningModel"]))
    if s["checks"] and hm(s["checkFrom"]) <= now.time() <= hm(s["checkTo"]):
        last = state.get("lastCheck")
        if not last or now - dt.datetime.fromisoformat(last) >= dt.timedelta(minutes=s["checkEveryMinutes"]):
            jobs.append(("check", "/concierge-check", s["checkModel"]))
    if s["prep"]:
        done = set(state.get("prepDone", []))
        for ev in agenda:
            try:
                start = dt.datetime.fromisoformat(ev["start"])
                if start.tzinfo:
                    start = start.astimezone().replace(tzinfo=None)
            except (KeyError, ValueError):
                continue
            ahead = start - now
            if dt.timedelta(0) < ahead <= dt.timedelta(minutes=s["prepMinutes"]) and ev.get("id") not in done:
                jobs.append(("prep", f"/concierge-prep {ev.get('id')}", s["prepModel"]))
    if s["wrapup"] and now.time() >= hm(s["wrapupAt"]) and state.get("wrapupDone") != today:
        jobs.append(("wrapup", "/concierge-wrapup", s["wrapupModel"]))
    return jobs


def run(kind: str, prompt: str, model: str) -> None:
    try:
        out = subprocess.run([CLAUDE, "-p", prompt, "--output-format", "json", "--model", model,
                              # Unsaved, so the app's question box keeps resuming its own conversation.
                              "--no-session-persistence"],
                             cwd=ROOT, capture_output=True, text=True, timeout=1200,
                             # Nestor's own run: the desk hook leaves it alone.
                             env={**os.environ, "NESTOR_RUN": "1"})
        report = json.loads(out.stdout or "{}")
    except (subprocess.SubprocessError, ValueError, OSError) as exc:
        report = {"is_error": True, "result": str(exc)}
    usage = report.get("usage") or {}
    entry = {
        "when": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "kind": kind,
        "backend": "claude", "costUSD": report.get("total_cost_usd"), "durationMs": report.get("duration_ms"),
        "inputTokens": sum(usage.get(k, 0) or 0 for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")) or None,
        "outputTokens": usage.get("output_tokens"), "turns": report.get("num_turns"),
        "model": model, "failed": bool(report.get("is_error")), "sessionID": report.get("session_id"),
        "sessionCostUSD": report.get("total_cost_usd"),
    }
    with open(B / "runs.jsonl", "a") as f:
        f.write(json.dumps(entry) + "\n")


def in_event(now: dt.datetime, agenda: list) -> bool:
    for ev in agenda:
        try:
            start, end = (dt.datetime.fromisoformat(ev[k]) for k in ("start", "end"))
        except (KeyError, ValueError):
            continue
        start, end = (t.astimezone().replace(tzinfo=None) if t.tzinfo else t for t in (start, end))
        if start <= now < end:
            return True
    return False


def may_speak(s: dict, now: dt.datetime, agenda: list) -> bool:
    """Whether Concierge may talk now. Pure, for tests."""
    if not s["speak"]:
        return False
    if s.get("silenceUntil"):
        try:
            if now < dt.datetime.fromisoformat(s["silenceUntil"]):
                return False
        except ValueError:
            pass
    if not hm(s["speakFrom"]) <= now.time() <= hm(s["speakTo"]):
        return False
    return not (s["quietInEvents"] and in_event(now, agenda))


def spoken(entries: list) -> str:
    """What is said for the new notifying entries, plainly. Pure, for tests."""
    lines = []
    for e in entries:
        title = str(e.get("title", "")).replace(" · ", ". ").strip()
        text = str(e.get("text", "")).strip()
        lines.append(f"{title}. {text}" if text else f"{title}.")
    if len(lines) > 1:
        lines.insert(0, f"{len(lines)} new things.")
    return " ".join(lines)


def say(s: dict, text: str) -> None:
    cmd = [APP, "--say", s["voice"], text] if APP else ["say", text]
    subprocess.run(cmd, capture_output=True, timeout=120)


def push(title: str) -> None:
    """One line to the phone, through ntfy on spark. Lost while spark is off."""
    try:
        req = urllib.request.Request(NTFY, data=title.encode(), headers={"Title": NAME})
        urllib.request.urlopen(req, timeout=10)
    except OSError:
        pass


def page_ready_text(html: str) -> str:
    """What the phone is told when the morning page is written. Pure, for tests."""
    urgent = re.search(r"<h2[^>]*>\s*Urgent actions\s*</h2>(.*?)(?:</section>|<h2)", html, re.S | re.I)
    count = len(re.findall(r"<li\b", urgent.group(1))) if urgent else 0
    what = "nothing urgent" if count == 0 else "1 urgent item" if count == 1 else f"{count} urgent items"
    return f"Morning page ready · {what}"


def morning_notice(s: dict, state: dict, page: Path, now: dt.datetime) -> str | None:
    """What to tell the phone after a morning build: the page is ready, or, after
    the last try, that there is none today. Nothing while tries are left."""
    if page_done(page, now) and "<!-- S:" not in page.read_text(errors="replace"):
        return page_ready_text(page.read_text(errors="replace"))
    if (state.get("morning") or {}).get("count", 0) >= s["morningTries"]:
        return "The morning page could not be built today. Press Refresh to try again."
    return None


def signin_warning(status: dict, now: dt.datetime) -> str | None:
    """What to tell the owner about the Claude sign-in, or None. The connectors for
    mail, calendar and Slack need the `claude auth login` sign-in, which has an end
    date; the tool gives the latest day and says it may end up to three days sooner.
    Said 10, 5, 2 and 1 days before the earliest day, then every day. Pure, for tests."""
    if not status:
        return None  # the tool could not be asked: say nothing rather than guess
    if not status.get("loggedIn"):
        return ("Nestor is signed out of Claude, so no page or check can run. "
                "Run claude auth login in a terminal.")
    try:
        latest = dt.datetime.fromisoformat(str(status["loginExpiresAt"]).replace("Z", "+00:00"))
    except (KeyError, ValueError):
        return None
    earliest = (latest.astimezone() - dt.timedelta(days=3)).date()
    days = (earliest - now.date()).days
    if days > 10 or (days > 0 and days not in (10, 5, 2, 1)):
        return None
    when = ("any day now" if days <= 0 else "tomorrow at the earliest" if days == 1
            else f"in {days} days at the earliest, on {earliest.strftime('%A')} {earliest.day} {earliest.strftime('%B')}")
    return (f"Nestor's Claude sign-in ends {when}. Run claude auth login in a terminal before then, "
            "or the morning page and the checks stop.")


def signin_entry(text: str, now: dt.datetime) -> dict:
    """The warning as an entry of today's updates, shown on the page and notified."""
    return {"time": now.strftime("%H:%M"), "kind": "check", "tag": "HIGH", "title": "Claude sign-in",
            "text": text, "key": "topic:claude-sign-in", "notify": True}


def check_signin(s: dict, state: dict, now: dt.datetime, updates_path: Path, agenda: list) -> None:
    """Once a day, from the hour the checks start: ask the tool about the sign-in
    and warn the owner when it is about to end."""
    today = now.date().isoformat()
    if state.get("signinChecked") == today or now.time() < hm(s["checkFrom"]):
        return
    state["signinChecked"] = today
    try:
        out = subprocess.run([CLAUDE, "auth", "status"], capture_output=True, text=True, timeout=60)
        status = json.loads(out.stdout or "{}")
    except (subprocess.SubprocessError, ValueError, OSError):
        status = {}
    text = signin_warning(status, now)
    if not text:
        return
    entries = read_json(updates_path, [])
    if any(e.get("key") == "topic:claude-sign-in" for e in entries):
        return
    entry = signin_entry(text, now)
    updates_path.parent.mkdir(exist_ok=True)
    updates_path.write_text(json.dumps(entries + [entry], indent=1))
    notify(s, [entry], now, agenda)


def notify(s: dict, entries: list, now: dt.datetime | None = None, agenda: list | None = None,
           speaker=None) -> None:
    entries = [e for e in entries if e.get("notify")]
    for e in entries:
        title = str(e.get("title", NAME))[:120]
        if s["notifyMac"]:
            script = f"display notification {json.dumps(title)} with title {json.dumps(NAME)}"
            subprocess.run(["osascript", "-e", script], capture_output=True)
        if s["notifyPhone"]:
            push(title)
    # Spoken last: the banners show at once, the voice takes a few seconds.
    if entries and may_speak(s, now or dt.datetime.now(), agenda or []):
        try:
            (speaker or say)(s, spoken(entries))
        except (OSError, subprocess.SubprocessError):
            pass


def main() -> int:
    if not B.is_dir():
        return 0
    s = {**DEFAULTS, **read_json(B / "settings.json", {})}
    lock = open(B / ".tick.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 0  # the previous tick is still running a job
    now = dt.datetime.now().replace(second=0, microsecond=0)
    today = now.date().isoformat()
    state_path = B / "state" / "tick.json"
    state_path.parent.mkdir(exist_ok=True)
    state = read_json(state_path, {})
    agenda = read_json(B / "agenda" / f"{today}.json", [])
    updates_path = B / "updates" / f"{today}.json"
    page = B / f"{today}.html"
    if s.get("pausedOn") != today:
        check_signin(s, state, now, updates_path, agenda)
        state_path.write_text(json.dumps(state, indent=1))
    for kind, prompt, model in due_jobs(s, state, now, agenda, page_done(page, now)):
        before = len(read_json(updates_path, []))
        run(kind, prompt, model)
        if kind == "morning":
            tries = state.get("morning") or {}
            count = tries.get("count", 0) + 1 if tries.get("day") == today else 1
            state["morning"] = {"day": today, "count": count, "last": now.isoformat()}
            notice = morning_notice(s, state, page, dt.datetime.now())
            if notice and s["notifyPhone"]:
                push(notice)
        elif kind == "check":
            state["lastCheck"] = now.isoformat()
        elif kind == "prep":
            state.setdefault("prepDone", []).append(prompt.split(" ", 1)[1])
        else:
            state["wrapupDone"] = today
        state_path.write_text(json.dumps(state, indent=1))
        notify(s, read_json(updates_path, [])[before:], now, agenda)
    return 0


if __name__ == "__main__":
    sys.exit(main())
