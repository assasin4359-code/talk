"""Condition atoms — the tiny condition language used by all narrative data.

A condition list is a flat AND of atoms. OR is expressed by writing several
beats/rules and letting priority pick one. Full grammar:
docs/03_Narrative_Data_Spec.md. The UE C++ port must accept exactly the same
atoms; GameData/tests/condition_vectors.json is the shared conformance suite.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Iterable, Optional, Protocol, Union

OPS = {
    "==": lambda a, b: a == b,
    "!=": lambda a, b: a != b,
    "<": lambda a, b: a < b,
    "<=": lambda a, b: a <= b,
    ">": lambda a, b: a > b,
    ">=": lambda a, b: a >= b,
}

_OP = r"(==|!=|<=|>=|<|>)"
_ID = r"[A-Za-z][A-Za-z0-9_]*"
_BEAT_ID = r"[A-Za-z][A-Za-z0-9_.]*"
_VALUE = r"[A-Za-z0-9_]+"
_SCOPE = r"(?:@(cycle|prev|past))?"

_AROUND_OP = re.compile(r"\s*(==|!=|<=|>=|<|>|=)\s*")

_PATTERNS = [
    ("flag", re.compile(rf"^flag:({_ID})$")),
    ("cycle", re.compile(rf"^cycle{_OP}(\d+)$")),
    ("stage_eq", re.compile(rf"^stage:({_ID})$")),
    ("stage", re.compile(rf"^stage{_OP}({_ID})$")),
    ("seen", re.compile(rf"^seen:({_BEAT_ID}){_SCOPE}$")),
    ("rel", re.compile(rf"^rel:({_ID})\.({_ID}){_SCOPE}(?:{_OP}(\d+))?$")),
    ("world", re.compile(rf"^world:({_ID})\.({_ID})=({_VALUE})$")),
]


class ConditionError(ValueError):
    pass


@dataclass(frozen=True)
class Condition:
    kind: str  # flag | cycle | stage | seen | rel | world
    negate: bool = False
    key: str = ""  # flag / stage / beat / npc / target id
    sub: str = ""  # rel event or world prop
    op: str = ""
    value: Union[str, int] = ""
    scope: str = ""  # "" (any cycle) | cycle | prev | past
    source: str = ""

    def __str__(self) -> str:
        return self.source


class ConditionContext(Protocol):
    """What an evaluator needs from the game. Implemented by NarrativeEngine."""

    @property
    def cycle(self) -> int: ...

    def has_flag(self, flag: str) -> bool: ...

    def current_stage_index(self) -> int: ...

    def stage_index(self, stage_id: str) -> int: ...

    def seen_cycles(self, beat_id: str) -> Iterable[int]: ...

    def rel_cycles(self, npc: str, event: str) -> Iterable[int]: ...

    def world_value(self, target: str, prop: str) -> Optional[str]: ...


def parse_condition(text: str) -> Condition:
    if not isinstance(text, str):
        raise ConditionError(f"condition must be a string, got {type(text).__name__}")
    source = text
    # Spaces are allowed only around operators ("cycle >= 2"); anything else is a typo.
    atom = _AROUND_OP.sub(r"\1", text.strip())
    negate = atom.startswith("!")
    if negate:
        atom = atom[1:]
    for kind, pattern in _PATTERNS:
        m = pattern.match(atom)
        if not m:
            continue
        g = m.groups()
        if kind == "flag":
            return Condition("flag", negate, key=g[0], source=source)
        if kind == "cycle":
            return Condition("cycle", negate, op=g[0], value=int(g[1]), source=source)
        if kind == "stage_eq":
            return Condition("stage", negate, op="==", value=g[0], source=source)
        if kind == "stage":
            return Condition("stage", negate, op=g[0], value=g[1], source=source)
        if kind == "seen":
            return Condition("seen", negate, key=g[0], scope=g[1] or "", source=source)
        if kind == "rel":
            op, count = g[3], g[4]
            return Condition(
                "rel", negate, key=g[0], sub=g[1], scope=g[2] or "",
                op=op or "", value=int(count) if count else "", source=source,
            )
        if kind == "world":
            return Condition("world", negate, key=g[0], sub=g[1], value=g[2], source=source)
    raise ConditionError(f"unrecognised condition atom: {source!r}")


def parse_conditions(items: Optional[Iterable[str]]) -> list[Condition]:
    return [parse_condition(t) for t in (items or [])]


def _scoped(cycles: Iterable[int], scope: str, now: int) -> set[int]:
    cycles = set(cycles)
    if scope == "cycle":
        return {c for c in cycles if c == now}
    if scope == "prev":
        return {c for c in cycles if c == now - 1}
    if scope == "past":
        return {c for c in cycles if c < now}
    return cycles


def evaluate(cond: Condition, ctx: ConditionContext) -> bool:
    if cond.kind == "flag":
        result = ctx.has_flag(cond.key)
    elif cond.kind == "cycle":
        result = OPS[cond.op](ctx.cycle, cond.value)
    elif cond.kind == "stage":
        result = OPS[cond.op](ctx.current_stage_index(), ctx.stage_index(str(cond.value)))
    elif cond.kind == "seen":
        result = bool(_scoped(ctx.seen_cycles(cond.key), cond.scope, ctx.cycle))
    elif cond.kind == "rel":
        count = len(_scoped(ctx.rel_cycles(cond.key, cond.sub), cond.scope, ctx.cycle))
        result = OPS[cond.op](count, cond.value) if cond.op else count > 0
    elif cond.kind == "world":
        result = ctx.world_value(cond.key, cond.sub) == cond.value
    else:  # pragma: no cover - parse_condition never produces other kinds
        raise ConditionError(f"unknown condition kind {cond.kind}")
    return result != cond.negate


def evaluate_all(conds: Iterable[Condition], ctx: ConditionContext) -> bool:
    return all(evaluate(c, ctx) for c in conds)


def failing(conds: Iterable[Condition], ctx: ConditionContext) -> list[Condition]:
    """Atoms that currently fail — used by debug tooling ("why didn't this line play?")."""
    return [c for c in conds if not evaluate(c, ctx)]
