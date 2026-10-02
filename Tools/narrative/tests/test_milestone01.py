"""Milestone 01 — THE FIRST RETURN, as executable checks.

If these fail after a content edit, the slice no longer tells its story.
"""
import unittest

from helpers import Transcript, load_game_db

from btg_narrative.engine import NarrativeEngine

EARLY_LOOP_PHRASES = ("또 시작", "이번에도", "또 왔")  # handoff 12: no "here we go again" before the player caused it


class Milestone01(unittest.TestCase):
    def setUp(self):
        self.db = load_game_db()
        self.engine = NarrativeEngine(self.db)
        self.t = Transcript(self.engine)

    def gate(self):
        return self.engine.world_value("gate", "state")

    def faint_and_wake(self, expected_reason):
        self.assertEqual(self.engine.pending_faint, expected_reason)
        return self.engine.complete_cycle()

    def test_golden_path(self):
        e, t = self.engine, self.t
        # ── cycle 1: the normal world ──
        self.assertEqual((e.cycle, e.state.stage, self.gate()), (1, "S01_Arrival", "open"))
        t.act("use", "firewood")
        self.assertTrue(e.has_flag("CarryingFirewood"))
        t.act("talk", "bartender", picks=["(장작을"])
        self.assertTrue(t.said("bartender", "장작이 얼마 안 남았네"))
        self.assertFalse(e.has_flag("CarryingFirewood"))
        t.act("talk", "bartender", picks=["성에는"])
        self.assertTrue(t.said("bartender", "재밌는 분이셔"))
        t.act("talk", "guard", picks=["고마워"])
        self.assertTrue(t.said("guard", "오늘은 문이 열려 있으니"))
        t.act("enter", "castle_foyer")
        result = self.faint_and_wake("CastleInterior")

        # ── cycle 2: the gate is closed and the guard remembers ──
        self.assertEqual((result.to_stage, e.cycle, result.terminal), ("S02_GateClosed", 2, False))
        self.assertEqual(self.gate(), "closed")
        self.assertFalse(e.has_flag("CarryingFirewood"), "carrying is cycle-scoped")
        self.assertTrue(e.has_flag("EnteredCastle"), "memories are persistent")

        t.act("talk", "bartender", picks=["들어가자마자"])
        self.assertTrue(t.said("bartender", "어제 장작 가져다준 거 고맙더라", cycle=2))
        self.assertTrue(t.said("bartender", "어제 성은 어땠어", cycle=2))

        t.act("talk", "guard", picks=["성문 앞?", "문은 왜", "……아무것도"])
        c2_guard = [txt for c, s, txt in t.lines if c == 2 and s == "guard"]
        self.assertEqual(c2_guard[:3], ["어제?", "……어디서 본 것 같은데.", "아. 어제 성문 앞에서 쓰러진 사람이 자네였나?"])
        self.assertTrue(t.said("player", "어제는 들어갈 수 있었잖아", cycle=2))
        self.assertTrue(e.has_flag("GuardRecognizesPlayer"))

        t.act("use", "gate")
        result = self.faint_and_wake("GateTouch")

        # ── cycle 3: slice end, one thing is off ──
        self.assertEqual((result.to_stage, e.cycle, result.terminal), ("S03_SliceEnd", 3, True))
        self.assertEqual(e.world_value("tavern_sign", "state"), "upside_down")

    def test_player_who_skips_everyone(self):
        e, t = self.engine, self.t
        t.act("enter", "castle_foyer")  # straight to the castle on day one
        self.faint_and_wake("CastleInterior")

        t.act("talk", "bartender")
        self.assertTrue(t.said("bartender", "쓰러졌다던 그 외지인"), "small-town gossip covers the skipped intro")

        t.act("use", "gate", picks=["……아무것도"])  # touches the gate before ever talking to the guard
        self.assertTrue(t.said("guard", "문 닫힌 거 안 보이시오"))
        self.assertTrue(t.said("guard", "자네였나?"), "the recognition beat must not be skippable")
        self.assertIsNone(e.pending_faint, "the first touch is intercepted, not a faint")

        t.act("use", "gate")
        self.faint_and_wake("GateTouch")
        self.assertEqual(e.state.stage, "S03_SliceEnd")

    def test_thanks_only_means_yesterday(self):
        t = self.t
        t.act("use", "firewood")
        t.act("talk", "bartender", picks=["(장작을"])
        t.act("enter", "castle_foyer")
        self.faint_and_wake("CastleInterior")
        # skip the tavern on day 2
        t.act("use", "gate", picks=["……아무것도"])
        t.act("use", "gate")
        self.faint_and_wake("GateTouch")
        t.act("talk", "bartender")
        self.assertFalse(t.said("bartender", "어제 장작"), "'어제' would be a lie two days later")

    def test_nobody_knows_about_a_loop_yet(self):
        self.test_golden_path()
        for cycle, speaker, text in self.t.lines:
            if cycle <= 2 and speaker != "player":
                for phrase in EARLY_LOOP_PHRASES:
                    self.assertNotIn(phrase, text, f"{speaker} in cycle {cycle}")

    def test_bartender_never_spoils_the_closed_gate(self):
        # VS success question 5: the player must notice the closed gate themselves.
        self.test_golden_path()
        for cycle, speaker, text in self.t.lines:
            if cycle == 2 and speaker == "bartender":
                self.assertNotIn("닫", text)

    def test_every_npc_answers_in_every_stage(self):
        npcs = [t.id for t in self.db.targets.values() if t.kind == "npc"]
        for stage in self.db.stage_order:
            for cycle in (1, 2, 5):
                self.engine.state.stage = stage
                self.engine.state.cycle = cycle
                for npc in npcs:
                    with self.subTest(stage=stage, cycle=cycle, npc=npc):
                        self.assertIsNotNone(self.engine.select_beat("talk", npc))


if __name__ == "__main__":
    unittest.main()
