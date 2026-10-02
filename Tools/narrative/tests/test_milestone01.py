"""Milestone 01 — THE FIRST RETURN, as executable checks.

The story checks live in GameData/tests/scenarios/*.json so the Godot runtime
runs exactly the same ones. If these fail after a content edit, the slice no
longer tells its story.
"""
import json
import unittest

from helpers import GAME_DATA, load_game_db

from btg_narrative.engine import NarrativeEngine
from btg_narrative.scenario import run_scenario

SCENARIO_DIR = GAME_DATA / "tests" / "scenarios"


class Scenarios(unittest.TestCase):
    def test_all_scenarios(self):
        db = load_game_db()
        files = sorted(SCENARIO_DIR.glob("*.json"))
        self.assertTrue(files)
        for path in files:
            with self.subTest(scenario=path.name):
                scenario = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(run_scenario(db, scenario), [])

    def test_runner_reports_failures(self):
        db = load_game_db()
        bad = {"steps": [{"act": "talk:guard", "pick": ["고마워"]}, {"said": "guard: 이런 말은 안 함"}],
               "never": [{"text": "성에", "speaker": "guard"}]}
        failures = run_scenario(db, bad)
        self.assertEqual(len(failures), 1)
        self.assertIn("never said", failures[0])
        self.assertTrue(run_scenario(db, {"steps": [], "never": []}) == [])


class Coverage(unittest.TestCase):
    def test_every_npc_answers_in_every_stage(self):
        db = load_game_db()
        engine = NarrativeEngine(db)
        npcs = [t.id for t in db.targets.values() if t.kind == "npc"]
        for stage in db.stage_order:
            for cycle in (1, 2, 5):
                engine.state.stage = stage
                engine.state.cycle = cycle
                for npc in npcs:
                    with self.subTest(stage=stage, cycle=cycle, npc=npc):
                        self.assertIsNotNone(engine.select_beat("talk", npc))


if __name__ == "__main__":
    unittest.main()
