"""Cross-reference validation for GameData. Run via `python Tools/narrative/btg.py validate`.

Errors break the game (CI fails). Warnings are probably mistakes. Info is
housekeeping (shown with -v).
"""
from __future__ import annotations

from typing import Iterable

from .conditions import Condition
from .data import Beat, Issue, NarrativeDB
from .effects import Effect

ANCHOR_PROPS = ("location", "spawn")


def _check_conditions(db: NarrativeDB, conds: Iterable[Condition], where: str, issues: list[Issue], allow_world: bool = True) -> None:
    for c in conds:
        if c.kind == "flag" and c.key not in db.flags:
            issues.append(Issue("error", where, f"{c}: unknown flag {c.key}"))
        elif c.kind == "stage" and c.value not in db.stages:
            issues.append(Issue("error", where, f"{c}: unknown stage {c.value}"))
        elif c.kind == "seen" and c.key not in db.beats:
            issues.append(Issue("error", where, f"{c}: unknown beat {c.key}"))
        elif c.kind == "rel":
            if db.targets.get(c.key, None) is None or db.targets[c.key].kind != "npc":
                issues.append(Issue("error", where, f"{c}: {c.key} is not an npc"))
            if c.sub not in db.rel_events:
                issues.append(Issue("error", where, f"{c}: unknown relationship event {c.sub}"))
        elif c.kind == "world":
            if not allow_world:
                issues.append(Issue("error", where, f"{c}: world rules may not depend on world state"))
                continue
            key = (c.key, c.sub)
            possible = {db.world_baseline.get(key)} | {r.value for r in db.world_rules if (r.target, r.prop) == key}
            possible.discard(None)
            if not possible:
                issues.append(Issue("error", where, f"{c}: no baseline or rule defines {c.key}.{c.sub}"))
            elif c.value not in possible:
                issues.append(Issue("error", where, f"{c}: {c.key}.{c.sub} can never be {c.value!r} (possible: {sorted(possible)})"))


def _check_effects(db: NarrativeDB, effects: Iterable[Effect], where: str, issues: list[Issue]) -> None:
    for e in effects:
        if e.kind in ("set", "clear") and e.key not in db.flags:
            issues.append(Issue("error", where, f"{e}: unknown flag {e.key}"))
        elif e.kind == "rel":
            if db.targets.get(e.key) is None or db.targets[e.key].kind != "npc":
                issues.append(Issue("error", where, f"{e}: {e.key} is not an npc"))
            if e.sub not in db.rel_events:
                issues.append(Issue("error", where, f"{e}: unknown relationship event {e.sub}"))
            if e.sub == "Talked":
                issues.append(Issue("warning", where, f"{e}: Talked is recorded automatically"))
        elif e.kind == "cue" and e.key not in db.cues:
            issues.append(Issue("error", where, f"{e}: unknown cue {e.key} (register it in registry.json)"))
        elif e.kind == "faint" and e.key not in db.faint_reasons:
            issues.append(Issue("error", where, f"{e}: unknown faint reason {e.key}"))


def _check_text(db: NarrativeDB, text: str, where: str, issues: list[Issue]) -> None:
    for bad in db.forbidden_text:
        if bad.lower() in text.lower():
            issues.append(Issue("warning", where, f"text contains {bad!r} — the handoff bans quest/score UI language"))


def _check_beat(db: NarrativeDB, beat: Beat, issues: list[Issue]) -> None:
    where = f"{beat.file} beat {beat.id}"
    if beat.on:
        verb, target = beat.on
        t = db.targets.get(target)
        expected = {"talk": ("npc",), "use": ("prop", "npc"), "enter": ("volume",)}[verb]
        if t is None:
            issues.append(Issue("error", where, f"on: unknown target {target}"))
        elif t.kind not in expected:
            issues.append(Issue("error", where, f"on: {verb} needs a target of kind {expected}, {target} is {t.kind}"))
    _check_conditions(db, beat.when, where, issues)
    _check_effects(db, beat.effects, where, issues)
    speakers = db.speakers()
    for i, line in enumerate(beat.lines):
        lwhere = f"{where} line #{i}"
        if line.speaker and line.speaker not in speakers:
            issues.append(Issue("error", lwhere, f"unknown speaker {line.speaker!r}"))
        if line.cue and line.cue not in db.cues:
            issues.append(Issue("error", lwhere, f"unknown cue {line.cue} (register it in registry.json)"))
        _check_text(db, line.text, lwhere, issues)
    if beat.next and beat.choices:
        issues.append(Issue("error", where, '"next" and "choices" are exclusive — put "next" on each choice instead'))
    if beat.next and beat.next not in db.beats:
        issues.append(Issue("error", where, f"next: unknown beat {beat.next}"))
    for i, c in enumerate(beat.choices):
        cwhere = f"{where} choice #{i}"
        _check_conditions(db, c.when, cwhere, issues)
        _check_effects(db, c.effects, cwhere, issues)
        _check_text(db, c.text, cwhere, issues)
        if c.next and c.next not in db.beats:
            issues.append(Issue("error", cwhere, f"next: unknown beat {c.next}"))
    if beat.choices and all(c.when for c in beat.choices):
        issues.append(Issue("warning", where, "every choice is conditional — the player can end up with no options"))
    if not beat.lines and not beat.choices and not beat.effects and not beat.next:
        issues.append(Issue("warning", where, "beat does nothing"))


def validate(db: NarrativeDB) -> list[Issue]:
    issues: list[Issue] = []

    # stages
    if db.start_stage not in db.stages:
        issues.append(Issue("error", "stages.json", f"start stage {db.start_stage!r} does not exist"))
    for s in db.stages.values():
        where = f"stages.json stage {s.id}"
        for t in s.transitions:
            if t.to not in db.stages:
                issues.append(Issue("error", where, f"transition to unknown stage {t.to!r}"))
            if t.reason and t.reason not in db.faint_reasons:
                issues.append(Issue("error", where, f"transition reason {t.reason!r} is not a faint reason"))
            _check_conditions(db, t.when, where, issues, allow_world=False)
        if not s.terminal and not any(not t.when and not t.reason for t in s.transitions):
            issues.append(Issue("warning", where, "no unconditional transition — the player may repeat this stage forever"))

    # world
    for (target, prop), value in db.world_baseline.items():
        if target not in db.targets:
            issues.append(Issue("error", "world.json", f"baseline for unknown target {target}"))
        if prop in ANCHOR_PROPS and value not in db.anchors:
            issues.append(Issue("error", "world.json", f"{target}.{prop}={value}: unknown anchor"))
    for i, r in enumerate(db.world_rules):
        where = f"world.json rule #{i} ({r.target}.{r.prop})"
        if r.target not in db.targets:
            issues.append(Issue("error", where, f"unknown target {r.target}"))
        if (r.target, r.prop) not in db.world_baseline:
            issues.append(Issue("error", where, "no baseline: every change must be a diff on top of the normal world"))
        if r.prop in ANCHOR_PROPS and r.value not in db.anchors:
            issues.append(Issue("error", where, f"{r.value}: unknown anchor"))
        _check_conditions(db, r.when, where, issues, allow_world=False)

    # targets
    for t in db.targets.values():
        if t.kind == "npc" and not t.voice:
            issues.append(Issue("warning", f"targets.json {t.id}", "npc has no voice profile"))

    # beats
    referenced: set[str] = set()
    for beat in db.beats.values():
        _check_beat(db, beat, issues)
        if beat.next:
            referenced.add(beat.next)
        referenced.update(c.next for c in beat.choices if c.next)
    for beat in db.beats.values():
        # A "next" chain with no choice in between would replay forever without player input.
        seen_ids, cur = [], beat
        while cur is not None and cur.next and not cur.choices:
            if cur.id in seen_ids:
                issues.append(Issue("error", f"{beat.file} beat {beat.id}", "next-chain loops: " + " -> ".join(seen_ids + [cur.id])))
                break
            seen_ids.append(cur.id)
            cur = db.beats.get(cur.next)
        if beat.on is None and beat.id not in referenced:
            issues.append(Issue("warning", f"{beat.file} beat {beat.id}", "unreachable: no trigger and nothing chains to it"))
    for t in db.targets.values():
        if t.kind != "npc":
            continue
        talk = db.beats_for("talk", t.id)
        if not talk:
            issues.append(Issue("warning", f"npc {t.id}", "has no talk beats"))
        elif not any(not b.when and not b.once for b in talk):
            issues.append(Issue("warning", f"npc {t.id}", "no unconditional, repeatable talk beat — talking may do nothing"))

    # housekeeping
    flags_set = set()
    flags_read = set()
    cues_used = set()
    for beat in db.beats.values():
        effects = list(beat.effects) + [e for c in beat.choices for e in c.effects]
        conds = list(beat.when) + [k for c in beat.choices for k in c.when]
        flags_set.update(e.key for e in effects if e.kind == "set")
        cues_used.update(e.key for e in effects if e.kind == "cue")
        cues_used.update(l.cue for l in beat.lines if l.cue)
        flags_read.update(c.key for c in conds if c.kind == "flag")
    for s in db.stages.values():
        flags_read.update(c.key for t in s.transitions for c in t.when if c.kind == "flag")
    flags_read.update(c.key for r in db.world_rules for c in r.when if c.kind == "flag")
    for f in db.flags:
        if f not in flags_set:
            issues.append(Issue("warning", "registry.json", f"flag {f} is never set"))
        elif f not in flags_read:
            issues.append(Issue("info", "registry.json", f"flag {f} is set but never read (fine if it is for later content)"))
    for c in db.cues:
        if c not in cues_used:
            issues.append(Issue("info", "registry.json", f"cue {c} is never used"))
    return issues
