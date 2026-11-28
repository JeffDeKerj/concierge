"""Serve Nestor's morning pages to the phone, read only.

It runs in Docker (docker-compose.yml, service `pages`) and is reached only
through the Mac's relay (caddy-proxy mac-backend, port 39443), which refuses any
request without the secret that the shared front on spark adds, owner only.
The container publishes no port of its own: the pages hold personal mail.

What it serves:
  /                  a list of the pages, newest first
  /today             the newest page itself, so a home-screen shortcut to it
                     always opens the latest day
  /YYYY-MM-DD.html   one page, under the same rule as the app: it may fetch
                     nothing but this server's own icon and manifest
  /manifest.webmanifest and three icons, for the home-screen shortcut
Nothing else under briefings/ is reachable.
"""
from __future__ import annotations

import html
import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(os.environ.get("CONCIERGE_DIR", Path(__file__).resolve().parent.parent))
B = ROOT / "briefings"
RES = ROOT / "Resources"
# Served path -> file, for the home-screen shortcut.
ICONS = {"/apple-touch-icon.png": "apple-touch-icon.png", "/icon-192.png": "icon-192.png",
         "/icon-512.png": "icon-512.png"}
HOST = os.environ.get("CONCIERGE_PAGES_HOST", "0.0.0.0")
PORT = int(os.environ.get("CONCIERGE_PAGES_PORT", "8080"))
NAME = "Nestor"
PAGE = re.compile(r"^/(\d{4}-\d{2}-\d{2})\.html$")
# The app's own rule for a page (PageGuard.swift), opened only to this server's
# own icon and manifest: nothing is fetched from anywhere else.
POLICY = ("default-src 'none'; style-src 'unsafe-inline'; img-src data: 'self'; manifest-src 'self'; "
          "base-uri 'none'; form-action 'none'")
# Put into each page's head: the shortcut's name, icon and manifest.
HEAD = (b'<link rel="manifest" href="/manifest.webmanifest">'
        b'<link rel="icon" href="/icon-192.png"><link rel="apple-touch-icon" href="/apple-touch-icon.png">'
        b'<meta name="theme-color" content="#0f1115">')
MANIFEST = json.dumps({
    "name": f"{NAME} · morning page", "short_name": NAME, "start_url": "/today", "scope": "/",
    "display": "standalone", "background_color": "#0f1115", "theme_color": "#0f1115",
    "icons": [{"src": "/icon-192.png", "sizes": "192x192", "type": "image/png"},
              {"src": "/icon-512.png", "sizes": "512x512", "type": "image/png"}],
}).encode()
ALWAYS = {
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Cache-Control": "no-store",
    "X-Frame-Options": "DENY",
}


def pages(folder: Path) -> list[str]:
    """The dated pages, newest first, as their day. Pure but for the listing, for tests."""
    days = [m.group(1) for p in folder.glob("*.html") if (m := PAGE.match("/" + p.name))]
    return sorted(days, reverse=True)


def with_head(page: bytes) -> bytes:
    """The page with the shortcut's links at the top of its head. Pure, for tests."""
    at = page.lower().find(b"<head>")
    return page[:at + 6] + HEAD + page[at + 6:] if at >= 0 else HEAD + page


def page(folder: Path, day: str) -> tuple[int, dict, bytes]:
    try:
        body = (folder / f"{day}.html").read_bytes()
    except OSError:
        return 404, {"Content-Type": "text/plain; charset=utf-8"}, b"No page for that day."
    return 200, {"Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": POLICY}, with_head(body)


def route(path: str, folder: Path, res: Path = RES) -> tuple[int, dict, bytes]:
    """(status, headers, body) for a GET of `path`. Pure but for reading files, for tests."""
    path = path.split("?", 1)[0]
    if path == "/":
        return 200, {"Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": POLICY}, index(pages(folder))
    if path == "/today":
        days = pages(folder)
        if not days:
            return 404, {"Content-Type": "text/plain; charset=utf-8"}, b"No page yet."
        return page(folder, days[0])
    if path == "/manifest.webmanifest":
        return 200, {"Content-Type": "application/manifest+json"}, MANIFEST
    if path in ICONS and (res / ICONS[path]).is_file():
        return 200, {"Content-Type": "image/png"}, (res / ICONS[path]).read_bytes()
    m = PAGE.match(path)
    if m:
        return page(folder, m.group(1))
    return 404, {"Content-Type": "text/plain; charset=utf-8"}, b"Not here."


def index(days: list[str]) -> bytes:
    import datetime as dt
    rows = []
    for d in days:
        label = dt.date.fromisoformat(d).strftime("%A %-d %B %Y")
        rows.append(f'<li><a href="/{d}.html">{html.escape(label)}</a></li>')
    items = "\n".join(rows) or "<li>No page yet.</li>"
    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<meta name="apple-mobile-web-app-title" content="{NAME}">
<meta name="theme-color" content="#0f1115">
<link rel="manifest" href="/manifest.webmanifest">
<link rel="icon" href="/icon-192.png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<title>{NAME} · morning pages</title>
<style>
  html, body {{ margin: 0; background: #0f1115; color: #e6e8ee;
    font: 17px/1.5 -apple-system, "Segoe UI", sans-serif; }}
  main {{ max-width: 640px; margin: 0 auto; padding: 24px 18px; }}
  h1 {{ font-size: 22px; margin: 0 0 16px; }}
  ul {{ list-style: none; margin: 0; padding: 0; }}
  li {{ border-bottom: 1px solid #2a2f3a; }}
  a {{ display: block; padding: 14px 4px; color: #7aa2f7; text-decoration: none; }}
  .today {{ display: inline-block; margin-bottom: 18px; padding: 10px 16px; border-radius: 10px;
    background: #171a21; border: 1px solid #2a2f3a; }}
</style></head>
<body><main>
<h1>{NAME} · morning pages</h1>
<a class="today" href="/today">Today's page</a>
<ul>
{items}
</ul>
</main></body></html>
""".encode()


class Handler(BaseHTTPRequestHandler):
    server_version = NAME
    sys_version = ""

    def do_GET(self) -> None:
        self.answer(with_body=True)

    def do_HEAD(self) -> None:
        self.answer(with_body=False)

    def answer(self, with_body: bool) -> None:
        status, headers, body = route(self.path, B)
        self.send_response(status)
        for k, v in {**ALWAYS, **headers, "Content-Length": str(len(body))}.items():
            self.send_header(k, v)
        self.end_headers()
        if with_body:
            self.wfile.write(body)

    def log_message(self, fmt: str, *args) -> None:
        # Path and status only, never a header.
        sys.stderr.write(f"{self.log_date_time_string()} {self.command} {self.path.split('?', 1)[0]} {args[1] if len(args) > 1 else ''}\n")


def main() -> int:
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
