"""Corruption-resistant save files (reference for the UE SaveSubsystem).

- Envelope: {"format", "version", "checksum", "payload"}; checksum = sha256 of
  the canonical JSON payload, so a truncated or hand-edited file is detected.
- Writes go to a temp file, are fsync'd, then atomically replace the main file.
  The previous good file is kept as <name>.bak.
- Load tries main, then .bak. A file that fails either check is never used.
- Old versions are upgraded through MIGRATIONS; newer versions are refused.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Optional

from .state import StoryState

FORMAT = "BTGSave"
VERSION = 1

# version -> function upgrading a payload from that version to version + 1
MIGRATIONS: dict[int, Callable[[dict[str, Any]], dict[str, Any]]] = {}


class SaveError(Exception):
    pass


@dataclass
class LoadResult:
    state: Optional[StoryState]
    source: Optional[Path]
    problems: list[str]


def _canonical(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def _checksum(payload: dict[str, Any]) -> str:
    return hashlib.sha256(_canonical(payload)).hexdigest()


def backup_path(path: Path) -> Path:
    return path.with_name(path.name + ".bak")


def write_save(path: Path, state: StoryState) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = state.to_dict()
    envelope = {"format": FORMAT, "version": VERSION, "checksum": _checksum(payload), "payload": payload}
    tmp = path.with_name(path.name + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(envelope, f, ensure_ascii=False, indent=2)
        f.flush()
        os.fsync(f.fileno())
    if path.exists() and _read_one(path)[0] is not None:
        shutil.copy2(path, backup_path(path))  # only ever back up a file that verifies
    os.replace(tmp, path)


def _read_one(path: Path) -> tuple[Optional[StoryState], Optional[str]]:
    try:
        envelope = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None, f"{path.name}: missing"
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as e:
        return None, f"{path.name}: unreadable ({e.__class__.__name__})"
    if not isinstance(envelope, dict) or envelope.get("format") != FORMAT:
        return None, f"{path.name}: not a {FORMAT} file"
    payload = envelope.get("payload")
    if not isinstance(payload, dict) or envelope.get("checksum") != _checksum(payload):
        return None, f"{path.name}: checksum mismatch"
    version = envelope.get("version")
    if not isinstance(version, int) or version > VERSION:
        return None, f"{path.name}: unsupported version {version!r}"
    while version < VERSION:
        if version not in MIGRATIONS:
            return None, f"{path.name}: no migration from version {version}"
        payload = MIGRATIONS[version](payload)
        version += 1
    try:
        return StoryState.from_dict(payload), None
    except (KeyError, TypeError, ValueError) as e:
        return None, f"{path.name}: bad payload ({e})"


def load_save(path: Path) -> LoadResult:
    path = Path(path)
    problems = []
    for candidate in (path, backup_path(path)):
        state, problem = _read_one(candidate)
        if state is not None:
            return LoadResult(state, candidate, problems)
        problems.append(problem)
    return LoadResult(None, None, problems)
