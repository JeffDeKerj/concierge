import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts"))
import sessions  # noqa: E402


def line(**e):
    return json.dumps(e)


class SessionTests(unittest.TestCase):
    def test_a_session_gives_its_title_state_and_last_words(self):
        s = sessions.summary([
            line(type="user", message={"content": "Fix the loft boxes"}),
            line(type="ai-title", aiTitle="Loft boxes fix"),
            line(type="assistant", message={"stop_reason": "tool_use", "content": [{"type": "text", "text": "Looking."}]}),
            line(type="assistant", isSidechain=True, message={"content": [{"type": "text", "text": "helper"}]}),
            line(type="assistant", message={"stop_reason": "end_turn", "content": [{"type": "text", "text": "Done."}]}),
        ])
        self.assertEqual(s, {"title": "Loft boxes fix", "last_stop": "end_turn", "last_text": "Done.", "asks": False})

    def test_nestors_own_runs_are_left_out(self):
        self.assertIsNone(sessions.summary([line(type="user", message={"content": "(You are the owner's assistant, ..."})]))
        self.assertIsNone(sessions.summary([line(type="user", message={"content": "<command-name>/briefing</command-name>"})]))

    def test_a_question_to_the_owner_is_told_apart_from_a_finished_turn(self):
        asked = sessions.summary([
            line(type="user", message={"content": "Merge it?"}),
            line(type="assistant", message={"stop_reason": "end_turn", "content": [{"type": "text", "text": "Shall I push them, or leave them?"}]}),
        ])
        self.assertTrue(asked["asks"])
        card = sessions.summary([
            line(type="user", message={"content": "Go"}),
            line(type="assistant", message={"stop_reason": "end_turn", "content": [
                {"type": "tool_use", "name": "mcp__ccd_turn__wrap_up", "input": {"recap": "x", "ask": "Push?"}},
                {"type": "text", "text": "Done."}]}),
        ])
        self.assertTrue(card["asks"])
        answered = sessions.summary([
            line(type="assistant", message={"stop_reason": "end_turn", "content": [{"type": "text", "text": "Which one?"}]}),
            line(type="user", message={"content": "The first"}),
            line(type="assistant", message={"stop_reason": "end_turn", "content": [{"type": "text", "text": "Done."}]}),
        ])
        self.assertFalse(answered["asks"])

    def test_the_state_reads_plainly(self):
        self.assertEqual(sessions.state("end_turn", 999), "finished, nothing asked")
        self.assertEqual(sessions.state("end_turn", 999, asks=True), "asked you something and waits for your answer")
        self.assertEqual(sessions.state("tool_use", 30), "working")
        self.assertEqual(sessions.state("tool_use", 600), "stopped mid-way")

    def test_only_this_hosts_own_sessions_count(self):
        home = sessions.HOME_SLUG
        self.assertTrue(sessions.wanted(home + "-code-brain"))
        self.assertFalse(sessions.wanted("-Users-someone-else-code-brain"))
        self.assertFalse(sessions.wanted(home + "-Documents-Personal-Finance"))
        self.assertFalse(sessions.wanted(home + "--cache-claude-tmp-agy-work-crops"))

    def test_the_project_is_named_from_its_folder(self):
        self.assertEqual(sessions.project_name(sessions.HOME_SLUG + "-code-swift-concierge"), "code/swift/concierge")


if __name__ == "__main__":
    unittest.main()
