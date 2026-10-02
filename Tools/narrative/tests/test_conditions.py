import json
import unittest

from helpers import GAME_DATA  # noqa: F401  (sets sys.path)

from btg_narrative.conditions import ConditionError, evaluate, parse_condition
from btg_narrative.effects import EffectError, parse_effect


class VectorContext:
    """ConditionContext built straight from condition_vectors.json."""

    def __init__(self, c):
        self.cycle = c["cycle"]
        self._order = c["stageOrder"]
        self._stage = c["stage"]
        self._flags = set(c["flags"]) | set(c["cycleFlags"])
        self._seen = {k: set(v) for k, v in c["seen"].items()}
        self._rel = {k: set(v) for k, v in c["rel"].items()}
        self._world = c["world"]

    def has_flag(self, f):
        return f in self._flags

    def current_stage_index(self):
        return self._order.index(self._stage)

    def stage_index(self, s):
        return self._order.index(s)

    def seen_cycles(self, b):
        return self._seen.get(b, set())

    def rel_cycles(self, npc, ev):
        return self._rel.get(f"{npc}.{ev}", set())

    def world_value(self, t, p):
        return self._world.get(f"{t}.{p}")


class ConformanceVectors(unittest.TestCase):
    """The same file must pass in the engine port."""

    @classmethod
    def setUpClass(cls):
        cls.vectors = json.loads((GAME_DATA / "tests" / "condition_vectors.json").read_text(encoding="utf-8"))
        cls.ctx = VectorContext(cls.vectors["context"])

    def test_cases(self):
        for case in self.vectors["cases"]:
            with self.subTest(atom=case["atom"]):
                self.assertEqual(evaluate(parse_condition(case["atom"]), self.ctx), case["expect"])

    def test_invalid(self):
        for atom in self.vectors["invalid"]:
            with self.subTest(atom=atom):
                with self.assertRaises(ConditionError):
                    parse_condition(atom)


class Effects(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(parse_effect("set:Foo").kind, "set")
        rel = parse_effect("rel:bartender.HelpedWithoutReward")
        self.assertEqual((rel.kind, rel.key, rel.sub), ("rel", "bartender", "HelpedWithoutReward"))
        self.assertEqual(parse_effect("faint:GateTouch").key, "GateTouch")

    def test_invalid(self):
        for bad in ["set", "set:", "rel:bartender", "explode:everything", "cue:has space"]:
            with self.subTest(bad=bad):
                with self.assertRaises(EffectError):
                    parse_effect(bad)


if __name__ == "__main__":
    unittest.main()
