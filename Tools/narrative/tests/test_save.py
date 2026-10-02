import json
import tempfile
import unittest
from pathlib import Path

import helpers  # noqa: F401  (puts btg_narrative on sys.path)

from btg_narrative import save as save_mod
from btg_narrative.save import backup_path, load_save, write_save
from btg_narrative.state import StoryState


def sample_state(cycle=2):
    s = StoryState.new("S01_Arrival")
    s.cycle = cycle
    s.stage = "S02_GateClosed"
    s.flags = {"EnteredCastle", "GuardRecognizesPlayer"}
    s.mark_seen("guard.c2.recognize")
    s.record_rel("bartender", "HelpedWithoutReward")
    s.history.append({"cycle": 1, "stage": "S01_Arrival", "ended": "CastleInterior"})
    return s


class SaveFiles(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "slot0.json"

    def tearDown(self):
        self.tmp.cleanup()

    def test_roundtrip(self):
        write_save(self.path, sample_state())
        result = load_save(self.path)
        self.assertEqual(result.state.to_dict(), sample_state().to_dict())
        self.assertEqual(result.source, self.path)

    def test_corrupt_main_falls_back_to_backup(self):
        write_save(self.path, sample_state(cycle=2))
        write_save(self.path, sample_state(cycle=3))
        self.path.write_text(self.path.read_text(encoding="utf-8")[:40], encoding="utf-8")  # truncated write
        result = load_save(self.path)
        self.assertEqual(result.state.cycle, 2)
        self.assertEqual(result.source, backup_path(self.path))
        self.assertTrue(result.problems)

    def test_tampered_payload_is_rejected(self):
        write_save(self.path, sample_state())
        env = json.loads(self.path.read_text(encoding="utf-8"))
        env["payload"]["cycle"] = 99
        self.path.write_text(json.dumps(env), encoding="utf-8")
        self.assertIsNone(load_save(self.path).state)

    def test_corrupt_file_never_becomes_the_backup(self):
        write_save(self.path, sample_state(cycle=2))
        self.path.write_text("garbage", encoding="utf-8")
        write_save(self.path, sample_state(cycle=3))
        self.assertFalse(backup_path(self.path).exists() and load_save(backup_path(self.path)).state is None)

    def test_future_version_refused_and_migrations_applied(self):
        write_save(self.path, sample_state())
        env = json.loads(self.path.read_text(encoding="utf-8"))
        env["version"] = save_mod.VERSION + 1
        self.path.write_text(json.dumps(env), encoding="utf-8")
        self.assertIn("unsupported version", load_save(self.path).problems[0])

        env["version"] = 0
        self.path.write_text(json.dumps(env), encoding="utf-8")
        save_mod.MIGRATIONS[0] = lambda p: {**p, "flags": p["flags"] + ["Migrated"]}
        try:
            self.assertIn("Migrated", load_save(self.path).state.flags)
        finally:
            del save_mod.MIGRATIONS[0]

    def test_nothing_to_load(self):
        result = load_save(self.path)
        self.assertIsNone(result.state)
        self.assertEqual(len(result.problems), 2)


if __name__ == "__main__":
    unittest.main()
