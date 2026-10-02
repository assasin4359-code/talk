"""Engine semantics on a tiny synthetic GameData (GameData/tests/fixtures/semantics), independent of the real content."""
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from helpers import GAME_DATA

from btg_narrative.data import load_db, load_db_strict
from btg_narrative.engine import ChoicesEvent, EndEvent, LineEvent, NarrativeEngine
from btg_narrative.validate import validate

FIXTURE = GAME_DATA / "tests" / "fixtures" / "semantics"  # shared with tests/test_engine.gd


def write_data(root: Path, beats=None) -> Path:
    """Copy of the shared fixture, optionally with different beats (for validator tests)."""
    shutil.copytree(FIXTURE, root, dirs_exist_ok=True)
    if beats is not None:
        (root / "beats" / "bob.json").write_text(json.dumps(beats, ensure_ascii=False), encoding="utf-8")
    return root


class EngineSemantics(unittest.TestCase):
    def setUp(self):
        self.db = load_db_strict(FIXTURE)
        self.e = NarrativeEngine(self.db)

    def drain(self, session, picks=()):
        picks = list(picks)
        out = []
        while True:
            ev = session.advance()
            out.append(ev)
            if isinstance(ev, ChoicesEvent):
                session.choose(picks.pop(0))
            if isinstance(ev, EndEvent):
                return out

    def test_priority_once_and_ties(self):
        cues = []
        self.e.on_cue = cues.append
        evs = self.drain(self.e.trigger("talk", "bob"), picks=[1])  # "숨김" is hidden, so index 1 is "끝"
        choices = next(ev for ev in evs if isinstance(ev, ChoicesEvent))
        self.assertEqual(choices.options, ("다음", "끝"), "conditional choice hidden")
        self.assertEqual(cues, ["Wave"])
        self.assertTrue(self.e.has_flag("Today"))
        # once:cycle used up; two beats tie at priority 5 → first written wins
        evs = self.drain(self.e.trigger("talk", "bob"))
        self.assertEqual([ev.text for ev in evs if isinstance(ev, LineEvent)], ["먼저 쓴 것"])

    def test_chain_effects_and_transition(self):
        evs = self.drain(self.e.trigger("talk", "bob"), picks=[0])
        self.assertEqual(evs[-1], EndEvent("Boom"))
        self.assertIsNone(self.e.trigger("talk", "bob"), "no new conversations while fainting")
        result = self.e.complete_cycle()
        self.assertEqual((result.from_stage, result.to_stage, result.ended_cycle), ("A", "B", 1))
        self.assertEqual(self.e.cycle, 2)
        self.assertFalse(self.e.has_flag("Today"), "cycle flags cleared")
        self.assertTrue(self.e.has_flag("Known"), "persistent flags kept")
        self.assertEqual(self.e.state.history, [{"cycle": 1, "stage": "A", "ended": "Boom"}])
        # once:cycle beat is available again on the new day
        self.assertEqual(self.e.select_beat("talk", "bob").id, "bob.once")

    def test_transition_reason_filter_and_fallthrough(self):
        self.e.pending_faint = "Fizz"
        self.assertEqual(self.e.complete_cycle().to_stage, "C")
        e2 = NarrativeEngine(self.db)
        e2.pending_faint = "Boom"  # Known not set → falls to unconditional "stay in A"
        self.assertEqual(e2.complete_cycle().to_stage, "A")

    def test_world_rules_later_wins(self):
        self.assertEqual(self.e.world_value("door", "state"), "open")
        self.e.state.stage = "B"
        self.assertEqual(self.e.world_value("door", "state"), "closed")
        self.e.state.stage = "C"
        self.assertEqual(self.e.world_value("door", "state"), "gone")

    def test_talked_is_recorded_once_per_cycle(self):
        for _ in range(3):
            self.drain(self.e.trigger("talk", "bob"), picks=[1])
        self.assertEqual(self.e.rel_cycles("bob", "Talked"), {1})

    def test_explain(self):
        report = "\n".join(self.e.explain("talk", "bob"))
        self.assertIn(">> [  9] bob.once: ok", report)
        self.assertIn("bob.tie1: fails flag:Today", report)


class ValidatorCatches(unittest.TestCase):
    def issues_for(self, beats):
        with tempfile.TemporaryDirectory() as d:
            db, issues = load_db(write_data(Path(d), beats=beats))
            return [str(i) for i in issues + validate(db) if i.level == "error"]

    def test_broken_references(self):
        errors = self.issues_for({"beats": [
            {"id": "x", "on": "talk:bob", "when": ["flag:Nope", "seen:ghost", "world:door.state=ajar"],
             "lines": ["alice: 누구?"], "effects": ["cue:Unregistered", "faint:Nope"], "next": "nowhere"},
            {"id": "y", "on": "enter:bob", "lines": ["bob: 내가 볼륨이라고?"]},
            {"id": "z", "on": "talk:bob", "lines": ["bob: 기본"]},
        ]})
        text = "\n".join(errors)
        for needle in ["unknown flag Nope", "unknown beat ghost", "can never be 'ajar'", "unknown speaker 'alice'",
                       "unknown cue Unregistered", "unknown faint reason Nope", "next: unknown beat nowhere",
                       "enter needs a target of kind"]:
            self.assertIn(needle, text)

    def test_next_loop(self):
        errors = self.issues_for({"beats": [
            {"id": "a", "on": "talk:bob", "lines": ["bob: 하나"], "next": "b"},
            {"id": "b", "lines": ["bob: 둘"], "next": "a"},
        ]})
        self.assertTrue(any("next-chain loops" in e for e in errors))

    def test_bad_atoms_are_load_errors(self):
        errors = self.issues_for({"beats": [{"id": "x", "on": "talk:bob", "when": ["cycle => 2"], "lines": ["bob: 음"]}]})
        self.assertTrue(any("unrecognised condition" in e for e in errors))


if __name__ == "__main__":
    unittest.main()
