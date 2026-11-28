"""Tell Nestor what the owner's Claude Code sessions are doing, read only.

Lists the sessions active in the last few hours, newest first: the project,
the session's title, when it last did something, whether it is working or
waiting for the owner, and the last thing it said. Nestor's own question and
job runs are left out, and so are sessions in the finance folder.

    python3 -I Scripts/sessions.py [hours]
"""
from __future__ import annotations

import datetime as dt
import json
import sys
import time
from pathlib import Path

PROJECTS = Path.home() / ".claude" / "projects"
HOME_SLUG = str(Path.home()).replace("/", "-")
# Nestor's own runs start with these words.
OWN = ("(You are the owner's assistant", "<command-name>/briefing", "<command-name>/concierge-")
WORKING_FOR = 120  # seconds since the last write that still count as working


def project_name(slug: str) -> str:
    """'-Users-jeffdekerj-code-swift-concierge' is 'code/swift/concierge'. Pure, for tests."""
    rest = slug[len(HOME_SLUG):] if slug.startswith(HOME_SLUG) else slug
    return rest.strip("-").replace("-", "/") or "home"


def summary(lines: list[str]) -> dict | None:
    """The title, first question, state and last words of one session, or None when it is Nestor's own."""
    title = first = last_text = ""
    last_stop = None
    for line in lines:
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get("isSidechain"):
            continue
        kind = e.get("type")
        if kind == "ai-title":
            title = e.get("aiTitle") or title
        message = e.get("message") or {}
        content = message.get("content")
        if kind == "user" and not first:
            text = content if isinstance(content, str) else " ".join(
                b.get("text", "") for b in content or [] if isinstance(b, dict) and b.get("type") == "text")
            if text.strip():
                first = text.strip()
        if kind == "assistant":
            last_stop = message.get("stop_reason") or last_stop
            for b in content or []:
                if isinstance(b, dict) and b.get("type") == "text" and b.get("text", "").strip():
                    last_text = b["text"].strip()
    if first.startswith(OWN):
        return None
    return {"title": title or first[:80], "last_stop": last_stop, "last_text": last_text}


def state(last_stop: str | None, idle_seconds: float) -> str:
    """Working, waiting for the owner, or stopped. Pure, for tests."""
    if last_stop == "end_turn":
        return "waiting for you"
    return "working" if idle_seconds < WORKING_FOR else "stopped mid-way"


def ago(seconds: float) -> str:
    minutes = int(seconds // 60)
    if minutes < 1:
        return "just now"
    if minutes < 60:
        return f"{minutes} min ago"
    return f"{minutes // 60} h {minutes % 60} min ago"


def main(hours: float = 3) -> int:
    now = time.time()
    found = []
    for path in PROJECTS.glob("*/*.jsonl"):
        slug = path.parent.name
        if "Finance" in slug or "finance" in slug:
            continue
        idle = now - path.stat().st_mtime
        if idle > hours * 3600:
            continue
        s = summary(path.read_text(errors="replace").splitlines())
        if s is None:
            continue
        found.append((idle, project_name(slug), s))
    if not found:
        print(f"No code session was active in the last {hours:g} hours.")
        return 0
    for idle, project, s in sorted(found, key=lambda f: f[0]):
        when = dt.datetime.fromtimestamp(now - idle).strftime("%H:%M")
        words = " ".join(s["last_text"].split())
        words = words[:300] + ("..." if len(words) > 300 else "")
        print(f"- {project}: \"{s['title']}\", last active {when} ({ago(idle)}), {state(s['last_stop'], idle)}."
              + (f" Last said: {words}" if words else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(float(sys.argv[1]) if len(sys.argv) > 1 else 3))
