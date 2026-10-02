"""Effect atoms — what a beat or choice does to the story state.

    set:<Flag>          turn a flag on (scope comes from the registry)
    clear:<Flag>        turn a flag off
    rel:<npc>.<Event>   record a relationship event for this cycle
    cue:<Cue>           presentation cue for the engine side (no state change)
    faint:<Reason>      request the end of the current cycle
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Iterable, Optional

_ID = r"[A-Za-z][A-Za-z0-9_]*"

_PATTERNS = [
    ("set", re.compile(rf"^set:({_ID})$")),
    ("clear", re.compile(rf"^clear:({_ID})$")),
    ("rel", re.compile(rf"^rel:({_ID})\.({_ID})$")),
    ("cue", re.compile(rf"^cue:({_ID})$")),
    ("faint", re.compile(rf"^faint:({_ID})$")),
]


class EffectError(ValueError):
    pass


@dataclass(frozen=True)
class Effect:
    kind: str
    key: str
    sub: str = ""
    source: str = ""

    def __str__(self) -> str:
        return self.source


def parse_effect(text: str) -> Effect:
    if not isinstance(text, str):
        raise EffectError(f"effect must be a string, got {type(text).__name__}")
    atom = text.strip()
    for kind, pattern in _PATTERNS:
        m = pattern.match(atom)
        if m:
            g = m.groups()
            return Effect(kind, g[0], g[1] if len(g) > 1 else "", source=text)
    raise EffectError(f"unrecognised effect: {text!r}")


def parse_effects(items: Optional[Iterable[str]]) -> list[Effect]:
    return [parse_effect(t) for t in (items or [])]
