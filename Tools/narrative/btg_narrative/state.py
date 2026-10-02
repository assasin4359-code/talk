"""StoryState — everything that survives a faint, plus the current cycle's scratch state.

Serialised shape (also the payload of a save file):

    {
      "cycle": 2,
      "stage": "S02_GateClosed",
      "flags": ["EnteredCastle", ...],          # persistent flags
      "cycleFlags": ["CarryingFirewood"],        # cleared when the cycle ends
      "seen": {"guard.c1.first": [1]},           # beat id -> cycles it was started in
      "rel": {"bartender.Talked": [1, 2]},       # npc.Event -> cycles it happened in
      "history": [{"cycle": 1, "stage": "S01_Arrival", "ended": "CastleInterior"}]
    }
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class StoryState:
    cycle: int
    stage: str
    flags: set[str] = field(default_factory=set)
    cycle_flags: set[str] = field(default_factory=set)
    seen: dict[str, set[int]] = field(default_factory=dict)
    rel: dict[str, set[int]] = field(default_factory=dict)
    history: list[dict[str, Any]] = field(default_factory=list)

    @classmethod
    def new(cls, start_stage: str) -> "StoryState":
        return cls(cycle=1, stage=start_stage)

    def mark_seen(self, beat_id: str) -> None:
        self.seen.setdefault(beat_id, set()).add(self.cycle)

    def record_rel(self, npc: str, event: str) -> None:
        # One record per (npc, event, cycle): counts mean "on how many days".
        self.rel.setdefault(f"{npc}.{event}", set()).add(self.cycle)

    def to_dict(self) -> dict[str, Any]:
        return {
            "cycle": self.cycle,
            "stage": self.stage,
            "flags": sorted(self.flags),
            "cycleFlags": sorted(self.cycle_flags),
            "seen": {k: sorted(v) for k, v in sorted(self.seen.items())},
            "rel": {k: sorted(v) for k, v in sorted(self.rel.items())},
            "history": list(self.history),
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "StoryState":
        cycle = d["cycle"]
        stage = d["stage"]
        if not isinstance(cycle, int) or cycle < 1:
            raise ValueError(f"invalid cycle {cycle!r}")
        if not isinstance(stage, str) or not stage:
            raise ValueError(f"invalid stage {stage!r}")
        return cls(
            cycle=cycle,
            stage=stage,
            flags=set(d.get("flags", [])),
            cycle_flags=set(d.get("cycleFlags", [])),
            seen={k: set(v) for k, v in d.get("seen", {}).items()},
            rel={k: set(v) for k, v in d.get("rel", {}).items()},
            history=list(d.get("history", [])),
        )
