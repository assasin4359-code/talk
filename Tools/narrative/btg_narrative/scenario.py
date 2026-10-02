"""Scenario runner — plays a GameData/tests/scenarios/*.json file against the engine.

The same files are run by the Godot test suite (tests/scenario_runner.gd), so
both implementations must agree on every step. Format:
docs/03_Narrative_Data_Spec.md#시나리오-테스트.
"""
from __future__ import annotations

import json
from typing import Any

from .conditions import ConditionError, evaluate, parse_condition
from .data import NarrativeDB
from .engine import ChoicesEvent, EndEvent, LineEvent, NarrativeEngine


def _split_said(text: str) -> tuple[str, str]:
    speaker, _, fragment = text.partition(": ")
    return speaker.strip(), fragment


def run_scenario(db: NarrativeDB, scenario: dict[str, Any]) -> list[str]:
    """Returns failure messages; empty means the scenario passed. Stops at the first failing step."""
    engine = NarrativeEngine(db)
    transcript: list[tuple[int, str, str]] = []  # (cycle, speaker, text)
    last_act: list[str] = []

    for i, step in enumerate(scenario.get("steps", [])):
        where = f"step {i} {json.dumps(step, ensure_ascii=False)}"
        if "check" in step:
            for atom in step["check"]:
                try:
                    ok = evaluate(parse_condition(atom), engine)
                except ConditionError as e:
                    return [f"{where}: {e}"]
                if not ok:
                    return [f"{where}: {atom} is false"]
        elif "act" in step:
            verb, _, target = step["act"].partition(":")
            picks = list(step.get("pick", []))
            session = engine.trigger(verb, target)
            if session is None:
                if step.get("nothing"):
                    continue
                return [f"{where}: nothing happened"]
            if step.get("nothing"):
                return [f"{where}: expected nothing, got beat {session.beat.id}"]
            last_act = []
            while True:
                ev = session.advance()
                if isinstance(ev, LineEvent):
                    transcript.append((engine.cycle, ev.speaker, ev.text))
                    last_act.append(f"{ev.speaker}: {ev.text}")
                elif isinstance(ev, ChoicesEvent):
                    if not picks:
                        return [f"{where}: unanswered choice {list(ev.options)}"]
                    want = picks.pop(0)
                    idx = next((k for k, o in enumerate(ev.options) if o.startswith(want)), None)
                    if idx is None:
                        return [f"{where}: choice {want!r} not offered in {list(ev.options)}"]
                    session.choose(idx)
                elif isinstance(ev, EndEvent):
                    break
            if picks:
                return [f"{where}: unused picks {picks}"]
        elif "said" in step or "notSaid" in step:
            negative = "notSaid" in step
            speaker, fragment = _split_said(step["notSaid" if negative else "said"])
            found = any(c == engine.cycle and s == speaker and fragment in t for c, s, t in transcript)
            if found == negative:
                return [f"{where}: {'unexpectedly said' if negative else 'never said'} this cycle"]
        elif "saidInOrder" in step:
            pos = 0
            for want in step["saidInOrder"]:
                while pos < len(last_act) and last_act[pos] != want:
                    pos += 1
                if pos == len(last_act):
                    return [f"{where}: {want!r} missing or out of order in {last_act}"]
                pos += 1
        elif "faint" in step:
            if engine.pending_faint != step["faint"]:
                return [f"{where}: pending faint is {engine.pending_faint!r}"]
            engine.complete_cycle()
        elif "noFaint" in step:
            if engine.pending_faint is not None:
                return [f"{where}: pending faint is {engine.pending_faint!r}"]
        else:
            return [f"{where}: unknown step"]

    failures = []
    for rule in scenario.get("never", []):
        for cycle, speaker, text in transcript:
            if "speaker" in rule and speaker != rule["speaker"]:
                continue
            if rule.get("npcOnly") and speaker in ("player", "narrator"):
                continue
            if "cycle" in rule and cycle != rule["cycle"]:
                continue
            if "maxCycle" in rule and cycle > rule["maxCycle"]:
                continue
            if rule["text"] in text:
                failures.append(f"never {rule}: cycle {cycle} {speaker}: {text}")
    return failures
