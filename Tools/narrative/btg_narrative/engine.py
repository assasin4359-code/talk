"""NarrativeEngine — reference implementation of the narrative core.

This is the behaviour the UE C++ NarrativeSubsystem must reproduce. It knows
nothing about rendering: it emits Line/Pause/Choices/End events and named cues,
and the presentation layer (BP in UE, print() in the text prototype) decides
what they look and sound like.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Optional, Union

from .conditions import Condition, evaluate_all, failing
from .data import Beat, Choice, NarrativeDB
from .effects import Effect
from .state import StoryState


@dataclass(frozen=True)
class LineEvent:
    speaker: str
    text: str
    cue: Optional[str] = None


@dataclass(frozen=True)
class PauseEvent:
    seconds: float


@dataclass(frozen=True)
class ChoicesEvent:
    options: tuple[str, ...]


@dataclass(frozen=True)
class EndEvent:
    faint: Optional[str] = None  # set when the conversation ended the cycle


Event = Union[LineEvent, PauseEvent, ChoicesEvent, EndEvent]


@dataclass(frozen=True)
class CycleResult:
    ended_cycle: int
    reason: str
    from_stage: str
    to_stage: str
    terminal: bool


class NarrativeEngine:
    def __init__(self, db: NarrativeDB, state: Optional[StoryState] = None):
        self.db = db
        self.state = state or StoryState.new(db.start_stage)
        if self.state.stage not in db.stages:
            raise ValueError(f"state refers to unknown stage {self.state.stage!r}")
        self.pending_faint: Optional[str] = None
        self.on_cue: Optional[Callable[[str], None]] = None
        self.cue_log: list[str] = []

    # --- ConditionContext -------------------------------------------------
    @property
    def cycle(self) -> int:
        return self.state.cycle

    def has_flag(self, flag: str) -> bool:
        return flag in self.state.flags or flag in self.state.cycle_flags

    def current_stage_index(self) -> int:
        return self.db.stages[self.state.stage].index

    def stage_index(self, stage_id: str) -> int:
        return self.db.stages[stage_id].index

    def seen_cycles(self, beat_id: str) -> set[int]:
        return self.state.seen.get(beat_id, set())

    def rel_cycles(self, npc: str, event: str) -> set[int]:
        return self.state.rel.get(f"{npc}.{event}", set())

    def world_value(self, target: str, prop: str) -> Optional[str]:
        # Baseline first, then every matching rule in file order: later rules win.
        # World rules may not use world: atoms (validator enforces), so no recursion.
        value = self.db.world_baseline.get((target, prop))
        for rule in self.db.world_rules:
            if rule.target == target and rule.prop == prop and evaluate_all(rule.when, self):
                value = rule.value
        return value

    # --- queries ----------------------------------------------------------
    def check(self, conds: list[Condition]) -> bool:
        return evaluate_all(conds, self)

    def world(self) -> dict[tuple[str, str], Optional[str]]:
        keys = set(self.db.world_baseline) | {(r.target, r.prop) for r in self.db.world_rules}
        return {k: self.world_value(*k) for k in sorted(keys)}

    def is_available(self, beat: Beat) -> bool:
        if beat.once == "story" and self.seen_cycles(beat.id):
            return False
        if beat.once == "cycle" and self.cycle in self.seen_cycles(beat.id):
            return False
        return self.check(beat.when)

    def candidates(self, verb: str, target: str) -> list[Beat]:
        # Highest priority wins; ties go to whichever was written first.
        beats = self.db.beats_for(verb, target)
        return sorted(beats, key=lambda b: (-b.priority, b.order))

    def select_beat(self, verb: str, target: str) -> Optional[Beat]:
        for beat in self.candidates(verb, target):
            if self.is_available(beat):
                return beat
        return None

    def explain(self, verb: str, target: str) -> list[str]:
        """Human-readable reason for which beat gets picked. Debug overlay material."""
        out = []
        chosen = self.select_beat(verb, target)
        for beat in self.candidates(verb, target):
            mark = ">>" if beat is chosen else "  "
            if beat.once == "story" and self.seen_cycles(beat.id):
                why = "already seen (once: story)"
            elif beat.once == "cycle" and self.cycle in self.seen_cycles(beat.id):
                why = "already seen this cycle (once: cycle)"
            else:
                bad = failing(beat.when, self)
                why = "ok" if not bad else "fails " + ", ".join(str(c) for c in bad)
            out.append(f"{mark} [{beat.priority:>3}] {beat.id}: {why}")
        return out or [f"   (no beats for {verb}:{target})"]

    # --- actions ----------------------------------------------------------
    def trigger(self, verb: str, target: str) -> Optional["DialogueSession"]:
        if self.pending_faint:
            return None  # the cycle is already ending
        beat = self.select_beat(verb, target)
        if beat is None:
            return None
        if verb == "talk":
            self.state.record_rel(target, "Talked")
        return DialogueSession(self, beat)

    def emit_cue(self, cue: str) -> None:
        self.cue_log.append(cue)
        if self.on_cue:
            self.on_cue(cue)

    def apply_effects(self, effects: list[Effect]) -> None:
        for e in effects:
            if e.kind == "set":
                scope = self.db.flags.get(e.key, "persistent")
                (self.state.cycle_flags if scope == "cycle" else self.state.flags).add(e.key)
            elif e.kind == "clear":
                self.state.flags.discard(e.key)
                self.state.cycle_flags.discard(e.key)
            elif e.kind == "rel":
                self.state.record_rel(e.key, e.sub)
            elif e.kind == "cue":
                self.emit_cue(e.key)
            elif e.kind == "faint":
                self.pending_faint = self.pending_faint or e.key

    def complete_cycle(self) -> CycleResult:
        """Call after the faint presentation has finished. Advances to the next day."""
        reason = self.pending_faint
        if reason is None:
            raise RuntimeError("complete_cycle() called without a pending faint")
        from_stage = self.state.stage
        to_stage = from_stage
        for t in self.db.stages[from_stage].transitions:
            if t.reason and t.reason != reason:
                continue
            if self.check(t.when):  # evaluated in the dying cycle, cycle flags still set
                to_stage = t.to
                break
        self.state.history.append({"cycle": self.state.cycle, "stage": from_stage, "ended": reason})
        ended = self.state.cycle
        self.state.cycle += 1
        self.state.cycle_flags.clear()
        self.state.stage = to_stage
        self.pending_faint = None
        return CycleResult(ended, reason, from_stage, to_stage, self.db.stages[to_stage].terminal)


class DialogueSession:
    """Steps through one beat chain. Call advance() until EndEvent; choose() on ChoicesEvent."""

    def __init__(self, engine: NarrativeEngine, beat: Beat):
        self.engine = engine
        self.done = False
        self._open_choices: Optional[list[Choice]] = None
        self._ending = False  # a choice without "next" closes the conversation
        self._start(beat)

    def _start(self, beat: Beat) -> None:
        self.beat = beat
        self.engine.state.mark_seen(beat.id)
        self._queue: list[Event] = []
        for line in beat.lines:
            if line.pause:
                self._queue.append(PauseEvent(line.pause))
            if line.speaker:
                self._queue.append(LineEvent(line.speaker, line.text, line.cue))
            elif line.cue:
                self._queue.append(LineEvent("", "", line.cue))  # cue-only beat of silence
        self._effects_done = False

    def _chain(self, beat_id: Optional[str]) -> bool:
        if not beat_id:
            return False
        nxt = self.engine.db.beats[beat_id]
        if not self.engine.check(nxt.when):
            return False  # chained beat not valid right now: conversation just ends
        self._start(nxt)
        return True

    def advance(self) -> Event:
        if self.done:
            return EndEvent(self.engine.pending_faint)
        if self._open_choices is not None:
            raise RuntimeError("waiting for choose()")
        while True:
            if self._queue:
                ev = self._queue.pop(0)
                if isinstance(ev, LineEvent) and ev.cue:
                    self.engine.emit_cue(ev.cue)
                    if not ev.text:
                        continue
                return ev
            if self._ending:
                self.done = True
                return EndEvent(self.engine.pending_faint)
            if not self._effects_done:
                self._effects_done = True
                self.engine.apply_effects(self.beat.effects)
            choices = [c for c in self.beat.choices if self.engine.check(c.when)]
            if choices:
                self._open_choices = choices
                return ChoicesEvent(tuple(c.text for c in choices))
            if self._chain(self.beat.next):
                continue
            self.done = True
            return EndEvent(self.engine.pending_faint)

    def choose(self, index: int) -> None:
        if self._open_choices is None:
            raise RuntimeError("no choices are open")
        choice = self._open_choices[index]
        self._open_choices = None
        self.engine.apply_effects(choice.effects)
        if not self._chain(choice.next):
            self._ending = True
