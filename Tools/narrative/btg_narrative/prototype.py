"""Text-mode playable prototype of Milestone 01.

Throwaway presentation layer on top of the real narrative core. Its only jobs:
let us play the first two cycles before the engine exists, and test whether
the beats land. Locations/flavor text live in Tools/narrative/prototype/ and are
NOT game data.
"""
from __future__ import annotations

import json
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterator, Optional

from .conditions import Condition, parse_conditions
from .data import NarrativeDB
from .engine import ChoicesEvent, CycleResult, EndEvent, LineEvent, NarrativeEngine, PauseEvent
from .save import load_save, write_save

PROTOTYPE_DIR = Path(__file__).resolve().parent.parent / "prototype"

HELP = """명령어:
  look | l                 둘러보기
  go <장소>  (또는 장소 이름만)  이동
  talk [대상]              대화 (대상이 한 명뿐이면 생략 가능)
  use <대상>               사용/만지기
  save | load              저장 / 마지막 체크포인트 불러오기
  state                    [디버그] 스토리 상태
  why <talk|use|enter> <대상>  [디버그] 왜 이 대사가 선택되는지
  quit | q                 종료
선택지가 나오면 번호를 입력."""

ALIASES = {
    "l": "look", "봐": "look", "둘러보기": "look",
    "가": "go", "이동": "go",
    "말": "talk", "대화": "talk",
    "사용": "use", "만지기": "use",
    "q": "quit", "종료": "quit", "exit": "quit",
    "?": "help", "도움말": "help",
}


@dataclass
class Exit:
    to: str
    when: list[Condition] = field(default_factory=list)
    blocked: str = ""


@dataclass
class Location:
    id: str
    name: str
    desc: str
    details: list[tuple[list[Condition], str]]
    exits: list[Exit]
    volume: Optional[str] = None


def load_locations(path: Path) -> dict[str, Location]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    out = {}
    for loc in raw["locations"]:
        exits = []
        for e in loc.get("exits", []):
            if isinstance(e, str):
                exits.append(Exit(e))
            else:
                exits.append(Exit(e["to"], parse_conditions(e.get("when")), e.get("blocked", "")))
        details = [(parse_conditions(d.get("when")), d["text"]) for d in loc.get("details", [])]
        out[loc["id"]] = Location(loc["id"], loc["name"], loc["desc"], details, exits, loc.get("volume"))
    return out


def load_flavor(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class Prototype:
    def __init__(
        self,
        db: NarrativeDB,
        save_path: Optional[Path] = None,
        new_game: bool = False,
        fast: bool = False,
        out: Callable[[str], None] = print,
        prototype_dir: Path = PROTOTYPE_DIR,
    ):
        self.db = db
        self.locations = load_locations(prototype_dir / "locations.json")
        self.flavor = load_flavor(prototype_dir / "flavor.json")
        self.save_path = save_path
        self.fast = fast
        self.out = out
        self.finished = False
        self._echo = False
        state = None
        if save_path and not new_game:
            result = load_save(save_path)
            for p in result.problems:
                if not p.endswith("missing"):
                    self.out(f"[세이브 경고] {p}")
            state = result.state
        try:
            self.engine = NarrativeEngine(db, state)
        except ValueError as e:  # save from older content (e.g. a renamed stage)
            self.out(f"[세이브 경고] {e} — 새로 시작한다.")
            self.engine = NarrativeEngine(db)
        self.engine.on_cue = self._on_cue
        self.location = self._spawn()

    # --- helpers ------------------------------------------------------------
    def _spawn(self) -> str:
        return self.engine.world_value("player", "spawn") or next(iter(self.locations))

    def _pause(self, seconds: float) -> None:
        if not self.fast:
            time.sleep(min(seconds, 2.0))

    def _on_cue(self, cue: str) -> None:
        text = self.flavor.get("cues", {}).get(cue)
        self.out(f"  {text}" if text else f"  [cue:{cue}]")

    def _name(self, target_id: str) -> str:
        t = self.db.targets.get(target_id)
        return t.name if t else target_id

    def _present(self) -> list[str]:
        here = []
        for tid, t in self.db.targets.items():
            if t.kind in ("npc", "prop") and self.engine.world_value(tid, "location") == self.location:
                here.append(tid)
        return here

    def _resolve(self, word: str, candidates: list[str]) -> Optional[str]:
        word = word.strip()
        for tid in candidates:
            if word in (tid, self._name(tid)):
                return tid
        matches = [tid for tid in candidates if self._name(tid).startswith(word) or tid.startswith(word)]
        return matches[0] if len(matches) == 1 else None

    def _narrate(self, lines: list[str]) -> None:
        for line in lines:
            self.out(line)
            self._pause(0.6)

    # --- presentation ---------------------------------------------------------
    def intro(self) -> None:
        if self.engine.cycle == 1 and not self.engine.state.history:
            self._narrate(self.flavor.get("arrival", []))
        else:
            self.out(f"(이어하기: {self.engine.cycle}회차 시작 지점)")
        self.save()
        self.look()

    def look(self) -> None:
        loc = self.locations[self.location]
        self.out("")
        self.out(f"[{loc.name}]")
        self.out(loc.desc)
        for conds, text in loc.details:
            if self.engine.check(conds):
                self.out(text)
        present = self._present()
        if present:
            self.out("보이는 것: " + ", ".join(self._name(t) for t in present))
        exits = [self.locations[e.to].name for e in loc.exits]
        self.out("갈 수 있는 곳: " + ", ".join(exits))

    def save(self) -> None:
        if self.save_path:
            write_save(self.save_path, self.engine.state)

    def run_session(self, verb: str, target: str, answers: Iterator[str]) -> None:
        session = self.engine.trigger(verb, target)
        if session is None:
            if verb != "enter":
                self.out("(아무 일도 일어나지 않았다.)")
            return
        while True:
            ev = session.advance()
            if isinstance(ev, PauseEvent):
                self._pause(ev.seconds)
            elif isinstance(ev, LineEvent):
                self.out(f'  {self._name(ev.speaker)}: "{ev.text}"')
                self._pause(0.3)
            elif isinstance(ev, ChoicesEvent):
                for i, opt in enumerate(ev.options, 1):
                    self.out(f"    {i}) {opt}")
                session.choose(self._ask_choice(len(ev.options), answers))
            elif isinstance(ev, EndEvent):
                if ev.faint:
                    self.faint()
                return

    def _ask_choice(self, n: int, answers: Iterator[str]) -> int:
        while True:
            try:
                raw = next(answers)
            except StopIteration:
                raise SystemExit("(선택지 대기 중에 입력이 끝났다)")
            if self._echo:
                self.out(f"  > {raw}")
            if ALIASES.get(raw.strip(), raw.strip()) == "quit":
                raise SystemExit(0)
            if raw.strip().isdigit() and 1 <= int(raw) <= n:
                return int(raw) - 1
            self.out(f"  1~{n} 중에서 고르기.")

    def faint(self) -> None:
        reason = self.engine.pending_faint or ""
        self.out("")
        self._narrate(self.flavor.get("faint", {}).get(reason, ["……"]))
        self.out("")
        self.out("(암전)")
        self._pause(1.5)
        result: CycleResult = self.engine.complete_cycle()
        self.save()  # checkpoint: the start of every cycle
        self.out("")
        self._narrate(self.flavor.get("wake", {}).get(result.to_stage, ["눈을 떴다."]))
        self.location = self._spawn()
        self.look()
        if result.terminal:
            self._narrate(self.flavor.get("sliceEnd", []))

    def move(self, word: str) -> None:
        loc = self.locations[self.location]
        exits = {e.to: e for e in loc.exits}
        if word not in exits:
            self.out("거기로는 바로 갈 수 없다.")
            return
        dest, ex = word, exits[word]
        if not self.engine.check(ex.when):
            self.out(ex.blocked or "지금은 갈 수 없다.")
            return
        self.location = dest
        self.look()
        target = self.locations[dest].volume
        if target:
            self.run_session("enter", target, iter(()))

    # --- command loop ---------------------------------------------------------
    def _resolve_location_word(self, word: str) -> Optional[str]:
        word = word.strip()
        if not word:
            return None
        for lid, loc in self.locations.items():
            if word in (lid, loc.name):
                return lid
        partial = [lid for lid, loc in self.locations.items() if word in loc.name]  # "광장" → "중앙 광장"
        return partial[0] if len(partial) == 1 else None

    def command(self, raw: str, answers: Iterator[str]) -> None:
        parts = raw.strip().split(maxsplit=1)
        if not parts:
            return
        verb = ALIASES.get(parts[0], parts[0])
        arg = parts[1] if len(parts) > 1 else ""
        if verb == "look":
            self.look()
        elif verb == "go":
            lid = self._resolve_location_word(arg) or arg
            self.move(lid)
        elif verb in ("talk", "use"):
            present = self._present()
            pool = [t for t in present if self.db.targets[t].kind == "npc"] if verb == "talk" else present
            if not arg and len(pool) == 1:
                target = pool[0]
            else:
                target = self._resolve(arg, pool) if arg else None
            if target is None:
                self.out("여기엔 그런 게 없다." if arg else "누구/무엇?")
                return
            self.run_session(verb, target, answers)
        elif verb == "state":
            self.out(json.dumps(self.engine.state.to_dict(), ensure_ascii=False, indent=2))
            world = {f"{t}.{p}": v for (t, p), v in self.engine.world().items()}
            self.out("world: " + json.dumps(world, ensure_ascii=False))
        elif verb == "why":
            bits = arg.split()
            if len(bits) != 2:
                self.out("사용법: why <talk|use|enter> <대상 id>")
                return
            for line in self.engine.explain(bits[0], bits[1]):
                self.out(line)
        elif verb == "save":
            self.save()
            self.out("(저장했다.)" if self.save_path else "(세이브 경로가 없다.)")
        elif verb == "load":
            if not self.save_path:
                self.out("(세이브 경로가 없다.)")
                return
            result = load_save(self.save_path)
            if result.state is None:
                self.out("(불러올 세이브가 없다: " + "; ".join(result.problems) + ")")
                return
            self.engine = NarrativeEngine(self.db, result.state)
            self.engine.on_cue = self._on_cue
            self.location = self._spawn()
            self.out(f"({self.engine.cycle}회차 시작 지점으로 돌아왔다.)")
            self.look()
        elif verb == "help":
            self.out(HELP)
        elif verb == "quit":
            self.finished = True
        elif self._resolve_location_word(raw.strip()):
            self.move(self._resolve_location_word(raw.strip()) or "")
        else:
            self.out("무슨 말인지 모르겠다. (help)")

    def run(self, commands: Iterator[str], echo: bool = False) -> None:
        self._echo = echo
        self.intro()
        for raw in commands:
            if raw.strip().startswith("#") or not raw.strip():
                continue
            if echo:
                self.out(f"\n> {raw}")
            self.command(raw, commands)
            if self.finished:
                break


def stdin_commands() -> Iterator[str]:
    while True:
        try:
            yield input("\n> ")
        except EOFError:
            return
