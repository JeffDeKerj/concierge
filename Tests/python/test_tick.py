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
