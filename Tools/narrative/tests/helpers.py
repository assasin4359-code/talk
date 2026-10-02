import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
NARRATIVE = HERE.parent
REPO = NARRATIVE.parent.parent
GAME_DATA = REPO / "GameData"
sys.path.insert(0, str(NARRATIVE))

from btg_narrative.data import load_db_strict  # noqa: E402
from btg_narrative.engine import ChoicesEvent, EndEvent, LineEvent, NarrativeEngine  # noqa: E402


def load_game_db():
    return load_db_strict(GAME_DATA)


class Transcript:
    """Drives the engine like a player would and records what was said."""

    def __init__(self, engine: NarrativeEngine):
        self.engine = engine
        self.lines: list[tuple[int, str, str]] = []  # (cycle, speaker, text)
        self.choices_seen: list[tuple[str, ...]] = []

    def act(self, verb: str, target: str, picks=(), expect_beat=True):
        """Trigger an action; `picks` are choice texts (prefix match) answered in order."""
        picks = list(picks)
        session = self.engine.trigger(verb, target)
        if session is None:
            assert not expect_beat, f"nothing happened for {verb}:{target}"
            return None
        while True:
            ev = session.advance()
            if isinstance(ev, LineEvent):
                self.lines.append((self.engine.cycle, ev.speaker, ev.text))
            elif isinstance(ev, ChoicesEvent):
                self.choices_seen.append(ev.options)
                assert picks, f"unanswered choice {ev.options}"
                want = picks.pop(0)
                idx = next((i for i, o in enumerate(ev.options) if o.startswith(want)), None)
                assert idx is not None, f"choice {want!r} not offered in {ev.options}"
                session.choose(idx)
            elif isinstance(ev, EndEvent):
                assert not picks, f"unused picks {picks}"
                return ev

    def said(self, speaker: str, fragment: str, cycle=None) -> bool:
        return any(
            s == speaker and fragment in t and (cycle is None or c == cycle)
            for c, s, t in self.lines
        )
