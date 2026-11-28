import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts"))
import pages  # noqa: E402

RESOURCES = Path(__file__).resolve().parents[2] / "Resources"


class RouteTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.folder = Path(self.dir.name)
        for name in ("2026-11-27.html", "2026-11-28.html", "morning-2026-11-24-desktop-run.html"):
            (self.folder / name).write_text(f"<p>{name}</p>")
        (self.folder / "dismissed.json").write_text("{}")
        (self.folder / "runs.jsonl").write_text("{}")

    def tearDown(self):
        self.dir.cleanup()

    def test_only_dated_pages_are_listed_newest_first(self):
        self.assertEqual(pages.pages(self.folder), ["2026-11-28", "2026-11-27"])

    def test_today_is_the_newest_page_itself(self):
        # Served, not redirected: a home-screen shortcut keeps /today and opens the latest day.
        status, headers, body = pages.route("/today", self.folder)
        self.assertEqual(status, 200)
        self.assertNotIn("Location", headers)
        self.assertTrue(body.endswith(b"<p>2026-11-28.html</p>"))

    def test_the_shortcut_finds_its_manifest_and_icons(self):
        (self.folder / "2026-11-26.html").write_text("<html><head><title>x</title></head><body></body></html>")
        _, _, body = pages.route("/2026-11-26.html", self.folder)
        self.assertTrue(body.startswith(b"<html><head><link rel=\"manifest\""))
        status, headers, manifest = pages.route("/manifest.webmanifest", self.folder)
        self.assertEqual((status, headers["Content-Type"]), (200, "application/manifest+json"))
        self.assertIn(b'"start_url": "/today"', manifest)
        for icon in ("/icon-192.png", "/icon-512.png", "/apple-touch-icon.png"):
            self.assertEqual(pages.route(icon, self.folder, RESOURCES)[0], 200, icon)

    def test_a_page_comes_with_the_rule_that_fetches_nothing(self):
        status, headers, body = pages.route("/2026-11-27.html?x=1", self.folder)
        self.assertEqual(status, 200)
        self.assertIn("default-src 'none'", headers["Content-Security-Policy"])
        self.assertTrue(body.endswith(b"<p>2026-11-27.html</p>"))
        # Opened only to this server's own icon and manifest.
        self.assertIn("manifest-src 'self'", headers["Content-Security-Policy"])
        self.assertNotIn("http", headers["Content-Security-Policy"])

    def test_nothing_else_is_reachable(self):
        for path in ("/dismissed.json", "/runs.jsonl", "/morning-2026-11-24-desktop-run.html",
                     "/../Scripts/pages.py", "/2026-11-27.html/../runs.jsonl", "/state/tick.json",
                     "/2026-11-29.html", "/%2e%2e/briefings/runs.jsonl"):
            self.assertEqual(pages.route(path, self.folder)[0], 404, path)

    def test_the_list_links_each_page(self):
        status, _, body = pages.route("/", self.folder)
        self.assertEqual(status, 200)
        self.assertIn(b'href="/2026-11-28.html"', body)
        self.assertIn(b"Saturday 28 November 2026", body)


if __name__ == "__main__":
    unittest.main()
