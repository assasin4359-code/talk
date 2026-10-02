"""Loads GameData/ into a NarrativeDB.

Loading is forgiving: malformed items are reported as Issues and skipped, so the
validator can list every problem in one run. Runtime code should use
load_db_strict(), which refuses to start on any error.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

from .conditions import Condition, ConditionError, parse_conditions
from .effects import Effect, EffectError, parse_effects

VERBS = ("talk", "use", "enter")
ONCE_VALUES = ("cycle", "story")
FLAG_SCOPES = ("persistent", "cycle")
TARGET_KINDS = ("npc", "prop", "volume", "player", "narrator")
BUILTIN_REL_EVENTS = ("Talked",)


@dataclass
class Issue:
    level: str  # error | warning | info
    where: str
    message: str

    def __str__(self) -> str:
        return f"[{self.level.upper()}] {self.where}: {self.message}"


@dataclass
class Line:
    speaker: Optional[str]  # None for a pure pause
    text: str = ""
    pause: float = 0.0  # seconds of silence *before* the line
    cue: Optional[str] = None


@dataclass
class Choice:
    text: str
    when: list[Condition] = field(default_factory=list)
    next: Optional[str] = None
    effects: list[Effect] = field(default_factory=list)


@dataclass
class Beat:
    id: str
    on: Optional[tuple[str, str]]  # (verb, target) or None for chained-only beats
    when: list[Condition] = field(default_factory=list)
    once: Optional[str] = None
    priority: int = 0
    lines: list[Line] = field(default_factory=list)
    choices: list[Choice] = field(default_factory=list)
    effects: list[Effect] = field(default_factory=list)
    next: Optional[str] = None
    note: str = ""
    file: str = ""
    order: int = 0


@dataclass
class Transition:
    to: str
    when: list[Condition] = field(default_factory=list)
    reason: Optional[str] = None


@dataclass
class Stage:
    id: str
    index: int
    note: str = ""
    terminal: bool = False
    transitions: list[Transition] = field(default_factory=list)


@dataclass
class Target:
    id: str
    kind: str
    name: str
    voice: Optional[str] = None


@dataclass
class WorldRule:
    target: str
    prop: str
    value: str
    when: list[Condition] = field(default_factory=list)
    note: str = ""


@dataclass
class NarrativeDB:
    root: Path
    flags: dict[str, str] = field(default_factory=dict)  # id -> scope
    flag_notes: dict[str, str] = field(default_factory=dict)
    rel_events: dict[str, str] = field(default_factory=dict)
    cues: dict[str, str] = field(default_factory=dict)
    faint_reasons: dict[str, str] = field(default_factory=dict)
    forbidden_text: list[str] = field(default_factory=list)
    targets: dict[str, Target] = field(default_factory=dict)
    stages: dict[str, Stage] = field(default_factory=dict)
    stage_order: list[str] = field(default_factory=list)
    start_stage: str = ""
    beats: dict[str, Beat] = field(default_factory=dict)
    anchors: set[str] = field(default_factory=set)
    world_baseline: dict[tuple[str, str], str] = field(default_factory=dict)
    world_rules: list[WorldRule] = field(default_factory=list)

    def beats_for(self, verb: str, target: str) -> list[Beat]:
        return [b for b in self.beats.values() if b.on == (verb, target)]

    def speakers(self) -> set[str]:
        return {t.id for t in self.targets.values() if t.kind in ("npc", "player", "narrator")}


class DataLoadError(Exception):
    def __init__(self, issues: list[Issue]):
        self.issues = issues
        super().__init__("\n".join(str(i) for i in issues))


def _read_json(path: Path, issues: list[Issue]) -> Optional[Any]:
    try:
        with path.open(encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        issues.append(Issue("error", str(path), "file not found"))
    except json.JSONDecodeError as e:
        issues.append(Issue("error", f"{path}:{e.lineno}:{e.colno}", f"invalid JSON: {e.msg}"))
    return None


def _rel(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root.parent).as_posix()
    except ValueError:
        return path.as_posix()


def parse_line(raw: Any) -> Line:
    """A line is either "speaker: text" or {"speaker", "text", "pause", "cue"}."""
    if isinstance(raw, str):
        speaker, sep, text = raw.partition(":")
        if not sep or not text.strip():
            raise ValueError(f'line string must look like "speaker: text", got {raw!r}')
        return Line(speaker.strip(), text.strip())
    if isinstance(raw, dict):
        unknown = set(raw) - {"speaker", "text", "pause", "cue"}
        if unknown:
            raise ValueError(f"unknown line keys {sorted(unknown)}")
        pause = float(raw.get("pause", 0.0))
        if pause < 0:
            raise ValueError("pause must be >= 0")
        speaker, text = raw.get("speaker"), raw.get("text", "")
        if (speaker is None) != (not text):
            raise ValueError("a line needs both speaker and text (or neither, for a pure pause)")
        if speaker is None and pause == 0 and not raw.get("cue"):
            raise ValueError("empty line")
        return Line(speaker, text, pause, raw.get("cue"))
    raise ValueError(f"line must be a string or object, got {type(raw).__name__}")


def _load_registry(db: NarrativeDB, issues: list[Issue]) -> None:
    path = db.root / "registry.json"
    data = _read_json(path, issues)
    if data is None:
        return
    where = _rel(path, db.root)
    for f in data.get("flags", []):
        fid, scope = f.get("id"), f.get("scope")
        if not fid:
            issues.append(Issue("error", where, f"flag without id: {f}"))
        elif fid in db.flags:
            issues.append(Issue("error", where, f"duplicate flag {fid}"))
        elif scope not in FLAG_SCOPES:
            issues.append(Issue("error", where, f"flag {fid}: scope must be one of {FLAG_SCOPES}"))
        else:
            db.flags[fid] = scope
            db.flag_notes[fid] = f.get("note", "")
    for e in BUILTIN_REL_EVENTS:
        db.rel_events[e] = "(built-in)"
    for key, target in (("relationshipEvents", db.rel_events), ("cues", db.cues), ("faintReasons", db.faint_reasons)):
        for item in data.get(key, []):
            iid = item.get("id")
            if not iid:
                issues.append(Issue("error", where, f"{key} entry without id: {item}"))
            elif iid in target:
                issues.append(Issue("error", where, f"duplicate {key} id {iid}"))
            else:
                target[iid] = item.get("note", "")
    db.forbidden_text = list(data.get("lint", {}).get("forbiddenText", []))


def _load_targets(db: NarrativeDB, issues: list[Issue]) -> None:
    path = db.root / "targets.json"
    data = _read_json(path, issues)
    if data is None:
        return
    where = _rel(path, db.root)
    for t in data.get("targets", []):
        tid, kind = t.get("id"), t.get("kind")
        if not tid or kind not in TARGET_KINDS:
            issues.append(Issue("error", where, f"target needs id and kind in {TARGET_KINDS}: {t}"))
        elif tid in db.targets:
            issues.append(Issue("error", where, f"duplicate target {tid}"))
        else:
            db.targets[tid] = Target(tid, kind, t.get("name", tid), t.get("voice"))


def _conds(raw: Any, where: str, issues: list[Issue]) -> list[Condition]:
    try:
        return parse_conditions(raw)
    except ConditionError as e:
        issues.append(Issue("error", where, str(e)))
        return []


def _effects(raw: Any, where: str, issues: list[Issue]) -> list[Effect]:
    try:
        return parse_effects(raw)
    except EffectError as e:
        issues.append(Issue("error", where, str(e)))
        return []


def _load_stages(db: NarrativeDB, issues: list[Issue]) -> None:
    path = db.root / "stages.json"
    data = _read_json(path, issues)
    if data is None:
        return
    where = _rel(path, db.root)
    db.start_stage = data.get("start", "")
    for i, s in enumerate(data.get("stages", [])):
        sid = s.get("id")
        if not sid:
            issues.append(Issue("error", where, f"stage without id at index {i}"))
            continue
        if sid in db.stages:
            issues.append(Issue("error", where, f"duplicate stage {sid}"))
            continue
        swhere = f"{where} stage {sid}"
        transitions = [
            Transition(t.get("to", ""), _conds(t.get("when"), swhere, issues), t.get("reason"))
            for t in s.get("transitions", [])
        ]
        db.stages[sid] = Stage(sid, len(db.stage_order), s.get("note", ""), bool(s.get("terminal")), transitions)
        db.stage_order.append(sid)


def _load_world(db: NarrativeDB, issues: list[Issue]) -> None:
    path = db.root / "world.json"
    data = _read_json(path, issues)
    if data is None:
        return
    where = _rel(path, db.root)
    db.anchors = set(data.get("anchors", []))
    for b in data.get("baseline", []):
        key = (b.get("target", ""), b.get("prop", ""))
        if key in db.world_baseline:
            issues.append(Issue("error", where, f"duplicate baseline for {key[0]}.{key[1]}"))
        elif not all(key) or not isinstance(b.get("value"), str):
            issues.append(Issue("error", where, f"baseline needs target, prop and string value: {b}"))
        else:
            db.world_baseline[key] = b["value"]
    for i, r in enumerate(data.get("rules", [])):
        rwhere = f"{where} rule #{i}"
        if not r.get("target") or not r.get("prop") or not isinstance(r.get("value"), str):
            issues.append(Issue("error", rwhere, f"rule needs target, prop and string value: {r}"))
            continue
        db.world_rules.append(WorldRule(r["target"], r["prop"], r["value"], _conds(r.get("when"), rwhere, issues), r.get("note", "")))


def _load_beats(db: NarrativeDB, issues: list[Issue]) -> None:
    beat_dir = db.root / "beats"
    files = sorted(beat_dir.glob("*.json"))
    if not files:
        issues.append(Issue("error", _rel(beat_dir, db.root), "no beat files"))
    order = 0
    for path in files:
        data = _read_json(path, issues)
        if data is None:
            continue
        fwhere = _rel(path, db.root)
        for raw in data.get("beats", []):
            bid = raw.get("id")
            if not bid:
                issues.append(Issue("error", fwhere, f"beat without id: {raw}"))
                continue
            where = f"{fwhere} beat {bid}"
            if bid in db.beats:
                issues.append(Issue("error", where, f"duplicate beat id (also in {db.beats[bid].file})"))
                continue
            unknown = set(raw) - {"id", "on", "when", "once", "priority", "lines", "choices", "effects", "next", "note"}
            if unknown:
                issues.append(Issue("error", where, f"unknown keys {sorted(unknown)}"))
            on = None
            if raw.get("on") is not None:
                verb, sep, target = str(raw["on"]).partition(":")
                if not sep or verb not in VERBS or not target:
                    issues.append(Issue("error", where, f'"on" must be <verb>:<target> with verb in {VERBS}'))
                else:
                    on = (verb, target)
            once = raw.get("once")
            if once is not None and once not in ONCE_VALUES:
                issues.append(Issue("error", where, f'"once" must be one of {ONCE_VALUES}'))
                once = None
            lines: list[Line] = []
            for i, rl in enumerate(raw.get("lines", [])):
                try:
                    lines.append(parse_line(rl))
                except (ValueError, TypeError) as e:
                    issues.append(Issue("error", f"{where} line #{i}", str(e)))
            choices = []
            for i, rc in enumerate(raw.get("choices", [])):
                cwhere = f"{where} choice #{i}"
                if not isinstance(rc, dict) or not rc.get("text"):
                    issues.append(Issue("error", cwhere, "choice needs text"))
                    continue
                choices.append(Choice(rc["text"], _conds(rc.get("when"), cwhere, issues), rc.get("next"), _effects(rc.get("effects"), cwhere, issues)))
            db.beats[bid] = Beat(
                id=bid,
                on=on,
                when=_conds(raw.get("when"), where, issues),
                once=once,
                priority=int(raw.get("priority", 0)),
                lines=lines,
                choices=choices,
                effects=_effects(raw.get("effects"), where, issues),
                next=raw.get("next"),
                note=raw.get("note", ""),
                file=fwhere,
                order=order,
            )
            order += 1


def load_db(root: Path) -> tuple[NarrativeDB, list[Issue]]:
    root = Path(root)
    db = NarrativeDB(root=root)
    issues: list[Issue] = []
    _load_registry(db, issues)
    _load_targets(db, issues)
    _load_stages(db, issues)
    _load_world(db, issues)
    _load_beats(db, issues)
    return db, issues


def load_db_strict(root: Path) -> NarrativeDB:
    from .validate import validate  # local import: validate depends on data

    db, issues = load_db(root)
    issues += validate(db)
    errors = [i for i in issues if i.level == "error"]
    if errors:
        raise DataLoadError(errors)
    return db
