"""Tell Nestor what the owner's Claude Code sessions are doing, read only.

Lists the sessions active in the last hour, on this Mac and on spark, newest
first: the project, the session's title, when it last did something, whether
it is working or waiting for the owner, and the last thing it said. Left out:
Nestor's own question and job runs, sessions in the finance folder, batch runs
working in a scratch folder, and the copies of the Mac's sessions that the
token monitor keeps on spark.

    python3 -I Scripts/sessions.py [hours]          this Mac, then spark
    python3 - [hours] --here < Scripts/sessions.py  one host only (spark runs this)
"""
from __future__ import annotations

import datetime as dt
import json
import subprocess
import sys
import time
from pathlib import Path

PROJECTS = Path.home() / ".claude" / "projects"
HOME_SLUG = str(Path.home()).replace("/", "-")
# Nestor's own runs start with these words.
OWN = ("(You are the owner's assistant", "<command-name>/briefing", "<command-name>/concierge-")
WORKING_FOR = 120  # seconds since the last write that still count as working
# Batch runs work in scratch folders; their sessions are not the owner's.
SCRATCH = ("-cache-", "-tmp-", "claude-tmp")


def wanted(slug: str) -> bool:
    """A session folder of this host's own, not finance, not a scratch folder. Pure, for tests."""
    if not slug.startswith(HOME_SLUG):
        return False  # a copy of another host's sessions
    rest = slug[len(HOME_SLUG):]
    if "Finance" in rest or "finance" in rest:
        return False
    return not any(mark in rest for mark in SCRATCH)


def project_name(slug: str) -> str:
    """'-Users-jeffdekerj-code-swift-concierge' is 'code/swift/concierge'. Pure, for tests."""
    rest = slug[len(HOME_SLUG):] if slug.startswith(HOME_SLUG) else slug
    return rest.strip("-").replace("-", "/") or "home"


def summary(lines: list[str]) -> dict | None:
    """The title, first question, state and last words of one session, or None when it is Nestor's own."""
    title = first = last_text = ""
    last_stop = None
    text_asks = card_asks = False  # a question in its last words; a question card, until answered
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
        if kind == "user" and isinstance(content, str) and content.strip():
            text_asks = card_asks = False  # the owner answered
        if kind == "assistant":
            last_stop = message.get("stop_reason") or last_stop
            for b in content or []:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "text" and b.get("text", "").strip():
                    last_text = b["text"].strip()
                    text_asks = ends_with_question(last_text)
                if b.get("type") == "tool_use" and asks_owner(b.get("name", ""), b.get("input") or {}):
                    card_asks = True
    if first.startswith(OWN):
        return None
    return {"title": title or first[:80], "last_stop": last_stop, "last_text": last_text, "asks": text_asks or card_asks}


def ends_with_question(text: str) -> bool:
    """Whether the last sentence is a question. Pure, for tests."""
    return text.rstrip().rstrip("*_`\"' )").endswith("?")


def asks_owner(tool: str, given: dict) -> bool:
    """A question card, a plan to approve, or the app's next-step box with a question. Pure, for tests."""
    return tool in ("AskUserQuestion", "ExitPlanMode") or (tool.endswith("wrap_up") and bool(given.get("ask")))


def state(last_stop: str | None, idle_seconds: float, asks: bool = False) -> str:
    """Working, asking the owner something, finished, or stopped. Pure, for tests."""
    if last_stop == "end_turn" or (asks and idle_seconds >= WORKING_FOR):
        return "asked you something and waits for your answer" if asks else "finished, nothing asked"
    return "working" if idle_seconds < WORKING_FOR else "stopped mid-way"


def ago(seconds: float) -> str:
    minutes = int(seconds // 60)
    if minutes < 1:
        return "just now"
    if minutes < 60:
        return f"{minutes} min ago"
    return f"{minutes // 60} h {minutes % 60} min ago"


def lines_here(hours: float) -> list[str]:
    now = time.time()
    found = []
    for path in PROJECTS.glob("*/*.jsonl"):
        slug = path.parent.name
        if not wanted(slug):
            continue
        idle = now - path.stat().st_mtime
        if idle > hours * 3600:
            continue
        s = summary(path.read_text(errors="replace").splitlines())
        if s is None:
            continue
        found.append((idle, project_name(slug), s))
    out = []
    for idle, project, s in sorted(found, key=lambda f: f[0]):
        when = dt.datetime.fromtimestamp(now - idle).strftime("%H:%M")
        words = " ".join(s["last_text"].split())
        words = words[:300] + ("..." if len(words) > 300 else "")
        out.append(f"- {project}: \"{s['title']}\", last active {when} ({ago(idle)}), {state(s['last_stop'], idle, s['asks'])}."
                   + (f" Last said: {words}" if words else ""))
    return out


def lines_on_spark(hours: float) -> list[str] | None:
    """The same list from spark, or None when spark does not answer (it is off at night)."""
    try:
        run = subprocess.run(["/usr/bin/ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "spark-mit",
                              "python3", "-", f"{hours:g}", "--here"],
                             input=Path(__file__).read_text(), capture_output=True, text=True, timeout=25)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return [line for line in run.stdout.splitlines() if line.startswith("- ")] if run.returncode == 0 else None


def main(hours: float = 1, here_only: bool = False) -> int:
    if here_only:
        print("\n".join(lines_here(hours)))
        return 0
    span = "hour" if hours == 1 else f"{hours:g} hours"
    mac = lines_here(hours)
    print(f"On this Mac, the last {span}:")
    print("\n".join(mac) if mac else "- none")
    spark = lines_on_spark(hours)
    print(f"On spark, the last {span}:")
    print("- spark did not answer" if spark is None else ("\n".join(spark) if spark else "- none"))
    return 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--here"]
    sys.exit(main(float(args[0]) if args else 1, here_only="--here" in sys.argv[1:]))
