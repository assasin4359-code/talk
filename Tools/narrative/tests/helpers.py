import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
NARRATIVE = HERE.parent
REPO = NARRATIVE.parent.parent
GAME_DATA = REPO / "GameData"
sys.path.insert(0, str(NARRATIVE))

from btg_narrative.data import load_db_strict  # noqa: E402


def load_game_db():
    return load_db_strict(GAME_DATA)
