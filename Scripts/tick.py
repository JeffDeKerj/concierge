"""Run Concierge's daytime jobs when they are due. launchd starts this every
15 minutes (Scripts/com.concierge.tick.plist). It reads briefings/settings.json
itself, so a job that is switched off or paused costs no tokens.

Jobs, each a Claude Code skill run headless in the project folder:
  concierge-check   new urgent things since the last look
  concierge-prep    a note before a calendar event (from briefings/agenda/<day>.json)
  concierge-wrapup  the evening summary
Each run is logged to briefings/runs.jsonl like the app's own runs, and new
entries in briefings/updates/<day>.json marked "notify" become a Mac
notification and an ntfy message.
"""
from __future__ import annotations

import datetime as dt
import fcntl
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(os.environ.get("CONCIERGE_DIR", Path(__file__).resolve().parent.parent))
B = ROOT / "briefings"
CLAUDE = os.environ.get("CONCIERGE_CLAUDE_BIN", str(Path.home() / ".local/bin/claude"))
NTFY = os.environ.get("CONCIERGE_NTFY", "https://apps.tailf7bf45.ts.net:31443/concierge")
DEFAULTS = dict(pausedOn=None, morning=True, checks=True, checkEveryMinutes=120, checkFrom="09:00",
                checkTo="19:00", prep=True, prepMinutes=30, wrapup=True, wrapupAt="18:30",
                notifyMac=True, notifyPhone=True, checkModel="haiku", prepModel="sonnet",
                wrapupModel="sonnet")


def read_json(path: Path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def hm(text: str) -> dt.time:
    h, m = text.split(":")
    return dt.time(int(h), int(m))


def due_jobs(s: dict, state: dict, now: dt.datetime, agenda: list) -> list[tuple[str, str, str]]:
    """(kind, skill argument, model) for every job due now. Pure, for tests."""
    today = now.date().isoformat()
    if s.get("pausedOn") == today:
        return []
    jobs = []
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
        out = subprocess.run([CLAUDE, "-p", prompt, "--output-format", "json", "--model", model],
                             cwd=ROOT, capture_output=True, text=True, timeout=1200)
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


def notify(s: dict, entries: list) -> None:
    for e in entries:
        if not e.get("notify"):
            continue
        title = str(e.get("title", "Concierge"))[:120]
        if s["notifyMac"]:
            script = f"display notification {json.dumps(title)} with title \"Concierge\""
            subprocess.run(["osascript", "-e", script], capture_output=True)
        if s["notifyPhone"]:
            try:
                req = urllib.request.Request(NTFY, data=title.encode(), headers={"Title": "Concierge"})
                urllib.request.urlopen(req, timeout=10)
            except OSError:
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
    for kind, prompt, model in due_jobs(s, state, now, agenda):
        before = len(read_json(updates_path, []))
        run(kind, prompt, model)
        if kind == "check":
            state["lastCheck"] = now.isoformat()
        elif kind == "prep":
            state.setdefault("prepDone", []).append(prompt.split(" ", 1)[1])
        else:
            state["wrapupDone"] = today
        state_path.write_text(json.dumps(state, indent=1))
        notify(s, read_json(updates_path, [])[before:])
    return 0


if __name__ == "__main__":
    sys.exit(main())
