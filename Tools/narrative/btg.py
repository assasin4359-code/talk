#!/usr/bin/env python3
"""Back to the Gates — narrative tooling.

    python Tools/narrative/btg.py validate [-v] [--strict]
    python Tools/narrative/btg.py play [--new] [--fast]
    python Tools/narrative/btg.py play --walkthrough      # canned Milestone 01 run
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))

from btg_narrative.data import DataLoadError, load_db, load_db_strict  # noqa: E402
from btg_narrative.prototype import PROTOTYPE_DIR, Prototype, stdin_commands  # noqa: E402
from btg_narrative.validate import validate  # noqa: E402

DEFAULT_DATA = REPO / "GameData"
DEFAULT_SAVE = HERE / ".saves" / "slot0.json"


def cmd_validate(args: argparse.Namespace) -> int:
    db, issues = load_db(args.data)
    issues += validate(db)
    shown = [i for i in issues if args.verbose or i.level != "info"]
    for issue in shown:
        print(issue)
    errors = sum(i.level == "error" for i in issues)
    warnings = sum(i.level == "warning" for i in issues)
    print(f"\n{len(db.beats)} beats, {len(db.flags)} flags, {len(db.stages)} stages — "
          f"{errors} error(s), {warnings} warning(s)")
    if errors or (args.strict and warnings):
        return 1
    return 0


def cmd_play(args: argparse.Namespace) -> int:
    try:
        db = load_db_strict(args.data)
    except DataLoadError as e:
        print("GameData has errors; run `validate` first.\n" + str(e))
        return 1
    if args.walkthrough:
        script = (PROTOTYPE_DIR / "walkthrough.txt").read_text(encoding="utf-8").splitlines()
        game = Prototype(db, save_path=None, new_game=True, fast=True)
        game.run(iter(script), echo=True)
        return 0
    game = Prototype(db, save_path=args.save, new_game=args.new, fast=args.fast)
    print("(help: 명령어 목록)")
    game.run(stdin_commands())
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA, help="GameData directory")
    sub = parser.add_subparsers(dest="cmd", required=True)

    v = sub.add_parser("validate", help="check GameData for broken references")
    v.add_argument("-v", "--verbose", action="store_true", help="also show info-level notes")
    v.add_argument("--strict", action="store_true", help="fail on warnings too")
    v.set_defaults(func=cmd_validate)

    p = sub.add_parser("play", help="text-mode prototype of Milestone 01")
    p.add_argument("--new", action="store_true", help="ignore the existing save")
    p.add_argument("--fast", action="store_true", help="no dramatic pauses")
    p.add_argument("--save", type=Path, default=DEFAULT_SAVE)
    p.add_argument("--walkthrough", action="store_true", help="play the canned golden path and print it")
    p.set_defaults(func=cmd_play)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
