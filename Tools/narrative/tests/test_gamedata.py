"""The real GameData and the text prototype must stay valid."""
import tempfile
import unittest
from pathlib import Path

from helpers import GAME_DATA, load_game_db

from btg_narrative.data import load_db
from btg_narrative.prototype import PROTOTYPE_DIR, Prototype, load_locations
from btg_narrative.validate import validate


class GameDataIsValid(unittest.TestCase):
    def test_no_errors_or_warnings(self):
        db, issues = load_db(GAME_DATA)
        issues += validate(db)
        problems = [str(i) for i in issues if i.level in ("error", "warning")]
        self.assertEqual(problems, [])


class PrototypeData(unittest.TestCase):
    def setUp(self):
        self.db = load_game_db()

    def test_locations_match_world_anchors(self):
        locations = load_locations(PROTOTYPE_DIR / "locations.json")
        self.assertEqual(set(locations), self.db.anchors)
        for loc in locations.values():
            for ex in loc.exits:
                self.assertIn(ex.to, locations, f"{loc.id} exit")
            if loc.volume:
                self.assertEqual(self.db.targets[loc.volume].kind, "volume")
            for ex in loc.exits:
                if ex.via:
                    self.assertEqual(self.db.targets[ex.via].kind, "volume", f"{loc.id} exit via")

    def test_walkthrough_reaches_slice_end(self):
        out = []
        with tempfile.TemporaryDirectory() as d:
            game = Prototype(self.db, save_path=Path(d) / "slot.json", new_game=True, fast=True, out=out.append)
            script = (PROTOTYPE_DIR / "walkthrough.txt").read_text(encoding="utf-8").splitlines()
            game.run(iter(script), echo=True)
            self.assertTrue((Path(d) / "slot.json").exists(), "checkpoint written at cycle start")
        text = "\n".join(out)
        self.assertIn("MILESTONE 02", text)
        self.assertIn("술집 간판이 거꾸로 걸려 있다", text)
        self.assertIn("왔었잖아! 들어가는 거 내가 봤어.", text)
        self.assertIn("W A K E   U P !", text)
        self.assertIn("거봐. 약속했잖아.", text)
        self.assertNotIn("무슨 말인지 모르겠다", text, "walkthrough command not understood")
        self.assertNotIn("여기엔 그런 게 없다", text, "walkthrough refers to something not present")
        self.assertEqual(game.engine.cycle, 6)


if __name__ == "__main__":
    unittest.main()
