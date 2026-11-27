"""Tests for the pure parts of Scripts/tick.py: python3 -I -m unittest discover Tests/python"""
import datetime as dt
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("tick", Path(__file__).resolve().parents[2] / "Scripts/tick.py")
tick = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tick)

NOON = dt.datetime(2026, 11, 26, 12, 0)
MEETING = [{"start": "2026-11-26T11:30:00+00:00", "end": "2026-11-26T12:30:00+00:00", "title": "Call"}]


def settings(**kw):
    return {**tick.DEFAULTS, **kw}


class MaySpeak(unittest.TestCase):
    def test_speaks_by_default_in_the_day(self):
        self.assertTrue(tick.may_speak(settings(), NOON, []))

    def test_switched_off(self):
        self.assertFalse(tick.may_speak(settings(speak=False), NOON, []))

    def test_outside_hours(self):
        self.assertFalse(tick.may_speak(settings(), NOON.replace(hour=7), []))
        self.assertFalse(tick.may_speak(settings(), NOON.replace(hour=22), []))

    def test_silenced_until_later(self):
        self.assertFalse(tick.may_speak(settings(silenceUntil="2026-11-26T13:00"), NOON, []))

    def test_silence_over(self):
        self.assertTrue(tick.may_speak(settings(silenceUntil="2026-11-26T11:00"), NOON, []))

    def test_quiet_in_a_meeting(self):
        self.assertFalse(tick.may_speak(settings(), NOON, MEETING))
        self.assertTrue(tick.may_speak(settings(quietInEvents=False), NOON, MEETING))

    def test_meeting_over(self):
        self.assertTrue(tick.may_speak(settings(), NOON.replace(hour=13), MEETING))


SEVEN = dt.datetime(2026, 11, 26, 7, 30)


class Morning(unittest.TestCase):
    def kinds(self, s, state, now, written):
        return [job[0] for job in tick.due_jobs(s, state, now, [], page_written=written)]

    def test_builds_the_page_after_the_set_time_when_it_is_missing(self):
        self.assertEqual(tick.due_jobs(settings(), {}, SEVEN, [], page_written=False),
                         [("morning", "/briefing", "sonnet")])
        self.assertEqual(self.kinds(settings(morningModel="opus", morningAt="07:45"), {}, SEVEN, False), [])

    def test_not_when_the_page_is_there_or_the_switch_is_off(self):
        self.assertEqual(self.kinds(settings(), {}, SEVEN, True), [])
        self.assertEqual(self.kinds(settings(morning=False), {}, SEVEN, False), [])
        self.assertEqual(self.kinds(settings(pausedOn="2026-11-26"), {}, SEVEN, False), [])

    def test_a_mac_that_slept_builds_it_on_waking(self):
        self.assertEqual(self.kinds(settings(), {}, NOON, False), ["morning", "check"])

    def test_tries_again_after_a_pause_and_gives_up_after_three(self):
        tried = lambda count, last: {"morning": {"day": "2026-11-26", "count": count, "last": last}}
        self.assertEqual(self.kinds(settings(), tried(1, "2026-11-26T07:20:00"), SEVEN, False), [])
        self.assertEqual(self.kinds(settings(), tried(1, "2026-11-26T07:20:00"), SEVEN.replace(minute=50), False),
                         ["morning"])
        self.assertEqual(self.kinds(settings(), tried(3, "2026-11-26T06:00:00"), SEVEN, False), [])
        # Yesterday's tries do not count.
        self.assertEqual(self.kinds(settings(), {"morning": {"day": "2026-11-25", "count": 3,
                                                             "last": "2026-11-25T09:00:00"}}, SEVEN, False),
                         ["morning"])

    def test_a_half_written_page_counts_once_it_has_gone_stale(self):
        import os, tempfile
        with tempfile.TemporaryDirectory() as folder:
            page = Path(folder) / "2026-11-26.html"
            self.assertFalse(tick.page_done(page, SEVEN))
            page.write_text("<html><!-- S:urgent --></html>")
            at = dt.datetime.fromtimestamp(page.stat().st_mtime)
            # Being written right now: leave it alone.
            self.assertTrue(tick.page_done(page, at + dt.timedelta(minutes=2)))
            self.assertFalse(tick.page_done(page, at + dt.timedelta(minutes=11)))
            page.write_text("<html>whole</html>")
            self.assertTrue(tick.page_done(page, at + dt.timedelta(hours=1)))


class PageReady(unittest.TestCase):
    PAGE = ("<section><h2>Urgent actions</h2><ul><li data-key='a'>x</li><li data-key='b'>y</li></ul></section>"
            "<section><h2>Agenda</h2><ul><li class='row'>z</li></ul></section>")

    def test_counts_the_urgent_items_only(self):
        self.assertEqual(tick.page_ready_text(self.PAGE), "Morning page ready · 2 urgent items")
        self.assertEqual(tick.page_ready_text(self.PAGE.replace("<li data-key='b'>y</li>", "")),
                         "Morning page ready · 1 urgent item")
        self.assertEqual(tick.page_ready_text("<h2>Agenda</h2><ul><li>z</li></ul>"),
                         "Morning page ready · nothing urgent")

    def test_the_phone_hears_of_a_page_or_of_the_last_failed_try(self):
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            page = Path(folder) / "2026-11-26.html"
            first = {"morning": {"day": "2026-11-26", "count": 1, "last": "2026-11-26T07:20:00"}}
            last = {"morning": {"day": "2026-11-26", "count": 3, "last": "2026-11-26T08:20:00"}}
            # No page and tries left: say nothing yet.
            self.assertIsNone(tick.morning_notice(settings(), first, page, SEVEN))
            self.assertIn("could not be built", tick.morning_notice(settings(), last, page, SEVEN))
            page.write_text(self.PAGE)
            self.assertEqual(tick.morning_notice(settings(), first, page, SEVEN), "Morning page ready · 2 urgent items")
            # A page still being written is not ready.
            page.write_text(self.PAGE + "<!-- S:low -->")
            self.assertIsNone(tick.morning_notice(settings(), first, page, dt.datetime.now()))


class Signin(unittest.TestCase):
    ENDS = {"loggedIn": True, "loginExpiresAt": "2026-12-23T21:48:45.684Z"}  # earliest: 20 December

    def on(self, month, day):
        return tick.signin_warning(self.ENDS, dt.datetime(2026, month, day, 9, 0))

    def test_quiet_until_ten_days_before_the_earliest_end(self):
        self.assertIsNone(self.on(11, 27))
        self.assertIsNone(self.on(12, 9))
        self.assertIsNone(self.on(12, 11))

    def test_warns_ten_five_two_and_one_days_before(self):
        self.assertIn("in 10 days at the earliest, on Sunday 20 December", self.on(12, 10))
        self.assertIn("in 5 days", self.on(12, 15))
        self.assertIn("in 2 days", self.on(12, 18))
        self.assertIn("tomorrow at the earliest", self.on(12, 19))
        self.assertIsNone(self.on(12, 16))

    def test_warns_every_day_once_it_may_have_ended(self):
        self.assertIn("any day now", self.on(12, 20))
        self.assertIn("any day now", self.on(12, 22))

    def test_signed_out_is_said_and_no_answer_is_not(self):
        self.assertIn("signed out", tick.signin_warning({"loggedIn": False}, NOON))
        self.assertIsNone(tick.signin_warning({}, NOON))
        self.assertIsNone(tick.signin_warning({"loggedIn": True}, NOON))

    def test_the_entry_shows_on_the_page_and_notifies(self):
        entry = tick.signin_entry("text", NOON)
        self.assertEqual((entry["time"], entry["key"], entry["notify"], entry["tag"]),
                         ("12:00", "topic:claude-sign-in", True, "HIGH"))


class Spoken(unittest.TestCase):
    def test_one_entry(self):
        self.assertEqual(tick.spoken([{"title": "MIT group · Stephane asks", "text": "About assays."}]),
                         "MIT group. Stephane asks. About assays.")

    def test_several_entries_are_counted(self):
        text = tick.spoken([{"title": "A"}, {"title": "B", "text": "b."}])
        self.assertEqual(text, "2 new things. A. B. b.")


class Notify(unittest.TestCase):
    def test_silent_entries_are_not_spoken(self):
        said = []
        quiet = settings(notifyMac=False, notifyPhone=False)
        record = lambda s, text: said.append(text)
        tick.notify(quiet, [{"title": "x", "notify": False}], NOON, [], speaker=record)
        tick.notify(quiet, [{"title": "y", "notify": True}], NOON, [], speaker=record)
        self.assertEqual(said, ["y."])


if __name__ == "__main__":
    unittest.main()
