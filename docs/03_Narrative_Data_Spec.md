# 03. 내러티브 데이터 명세 (GameData/)

> 작가·기획·AI가 편집하는 파일의 형식과, 엔진이 따라야 할 동작 규칙.
> **레퍼런스 구현**: `Tools/narrative/btg_narrative/` — 이 문서와 다르게 동작하면 버그다 (둘 중 하나를 고친다).
> **적합성 테스트**: `GameData/tests/condition_vectors.json` — 엔진 포팅도 같은 파일을 통과해야 한다.

편집 후에는 항상:

```bash
python Tools/narrative/btg.py validate      # 참조 오류 검사
python -m unittest discover -s Tools/narrative/tests -t Tools/narrative/tests
python Tools/narrative/btg.py play          # 직접 해보기
```

---

## 파일 구성

| 파일 | 내용 |
|---|---|
| `registry.json` | 플래그(+범위), 관계 이벤트, cue, 기절 사유, 금지 문구 lint. **여기 등록 안 된 이름은 쓸 수 없다** (오타 방지) |
| `targets.json` | 대상: `npc` / `prop` / `volume` / `player` / `narrator`. 이름은 임시(역할명) |
| `stages.json` | 진행 단계 순서 + 전환 규칙 |
| `world.json` | 앵커, 정상 상태(baseline), 변화 규칙(rules) |
| `beats/*.json` | 비트 = 플레이어 행동에 대한 세계의 반응 (대사·선택지·효과). 파일 분할은 자유 (NPC별 권장) |
| `tests/condition_vectors.json` | 조건 DSL 적합성 벡터 |

ID 규칙: 플래그·이벤트·cue·사유는 `PascalCase`, 대상·앵커는 `snake_case`, 스테이지는 `S01_Name`, 비트는 `owner.part.name`.

---

## 상태 모델

| 상태 | 범위 | 설명 |
|---|---|---|
| `cycle` | 영속 | 몇 번째 날인가. 1부터. 기절할 때마다 +1 |
| `stage` | 영속 | `stages.json`의 단계 id. 순서가 있다 |
| 플래그 `scope: persistent` | 영속 | NPC의 기억, 스토리 사실 |
| 플래그 `scope: cycle` | 회차 | 기절하면 지워진다 (예: 장작을 들고 있음) |
| `seen` | 영속 | 비트 id → 그 비트가 **시작된** 회차 목록 |
| `rel` | 영속 | `npc.Event` → 그 일이 있었던 회차 목록. **같은 회차에 같은 이벤트는 1번만** 기록 → 개수 = "며칠이나" |
| `history` | 영속 | 끝난 회차 기록 `{cycle, stage, ended}` |

내장 관계 이벤트 `Talked`: `talk:<npc>`로 비트가 시작될 때마다 자동 기록 (회차당 1회).
예: "여러 날 찾아옴(VisitedRepeatedly)" = `rel:bartender.Talked>=3`.

---

## 조건 DSL

조건 목록(`when`)은 **원자들의 AND**다. OR이 필요하면 비트를 둘로 나누고 우선순위로 고른다.
원자 앞 `!`는 부정. 공백은 연산자 주변에만 허용 (`cycle >= 2` OK, `flag:Entered Castle` 오류).

| 원자 | 참일 때 |
|---|---|
| `flag:<Flag>` | 플래그가 켜져 있음 (영속 또는 회차) |
| `cycle<op><N>` | 현재 회차 비교. op: `== != < <= > >=` |
| `stage:<Stage>` | 현재 스테이지가 정확히 이것 |
| `stage<op><Stage>` | 스테이지 **순서** 비교 (`stage>=S02_GateClosed` = 2단계 이후 전부) |
| `seen:<BeatId>[@scope]` | 그 비트를 본 적 있음 |
| `rel:<npc>.<Event>[@scope][<op><N>]` | 관계 이벤트가 있음 / 있었던 날 수 비교 |
| `world:<target>.<prop>=<value>` | 월드 값이 그것. **월드 규칙과 스테이지 전환 안에서는 금지** (순환 방지) |

`@scope`:

| scope | 의미 | 예 |
|---|---|---|
| (없음) | 언제든 | `seen:guard.c2.recognize` |
| `@cycle` | 오늘 | `!seen:guard.c2.where@cycle` (오늘 아직 안 물어봤으면) |
| `@prev` | **정확히 어제** | `rel:bartender.HelpedWithoutReward@prev` → "어제 장작 고마웠어" |
| `@past` | 오늘 이전 아무 날 | `rel:bartender.HelpedWithoutReward@past` → "또 가져왔어?" |

> `@prev`가 따로 있는 이유: 이 게임에서 "어제"는 핵심 단어다. 이틀 전 일을 "어제"라고 하면 그건 연출이 아니라 버그다.

---

## 효과

| 효과 | 동작 |
|---|---|
| `set:<Flag>` | 플래그 켜기 (영속/회차는 레지스트리 범위를 따름) |
| `clear:<Flag>` | 플래그 끄기 |
| `rel:<npc>.<Event>` | 오늘 날짜로 관계 이벤트 기록 |
| `cue:<Cue>` | 연출 신호. 상태 변화 없음. 엔진이 cue 이름으로 BP 이벤트/시퀀스 실행 |
| `faint:<Reason>` | 이 대화가 끝나면 회차 종료 (기절 연출 → 전환) |

---

## 비트 (beats/*.json)

```jsonc
{
  "id": "guard.c2.recognize",          // 전역 유일
  "on": "talk:guard",                   // 트리거: talk:<npc> | use:<prop|npc> | enter:<volume>. 없으면 next/선택지로만 도달
  "when": ["stage:S02_GateClosed", "flag:EnteredCastle"],
  "once": "story",                      // story(평생 1번) | cycle(하루 1번) | 생략(반복)
  "priority": 30,                       // 높을수록 먼저. 동점이면 먼저 쓴 것
  "note": "작가 메모. 게임엔 안 나옴",
  "lines": [
    "player: 어제는 들어갈 수 있었잖아.",                    // 짧은 형식 "화자: 텍스트"
    { "pause": 1.2, "speaker": "guard", "text": "……어디서 본 것 같은데.", "cue": "GuardStare" },
    { "pause": 1.5 }                                         // 정적만
  ],
  "effects": ["set:GuardRecognizesPlayer"],
  "next": "guard.c2.hub"                // 이어지는 비트 (choices와 동시 사용 불가)
}
```

선택지:

```jsonc
"choices": [
  { "text": "성문 앞? 성 안에서 쓰러졌는데.", "when": ["!seen:guard.c2.where@cycle"], "next": "guard.c2.where" },
  { "text": "……아무것도 아니야." }      // next 없음 = 대화 종료
]
```

### 실행 순서 (엔진이 지켜야 할 것)

1. 트리거 `(verb, target)`의 후보 비트를 `priority` 내림차순, 동점은 파일 순서로 정렬.
2. `once`가 소진되지 않았고 `when`이 참인 첫 비트를 고른다. 없으면 아무 일도 없다.
3. `talk`이면 `rel:<npc>.Talked` 자동 기록.
4. 비트 시작 → `seen`에 오늘 날짜 기록.
5. `lines`를 순서대로: `pause`(정적) → 줄 표시 + 그 줄의 `cue` 발생.
6. 줄이 끝나면 비트의 `effects` 적용.
7. `choices` 중 `when`이 참인 것만 표시. 고르면 그 선택지의 `effects` → `next` 비트로 (4번부터). `next`가 없으면 종료.
8. 선택지가 없으면 `next`로 이어감. 이어갈 비트의 `when`이 거짓이면 조용히 종료.
9. 종료 시 `faint`가 요청돼 있으면 회차 종료 파이프라인으로.

기절 대기 중에는 새 대화를 시작할 수 없다.

---

## 스테이지 (stages.json)

```jsonc
{
  "start": "S01_Arrival",
  "stages": [
    { "id": "S01_Arrival", "transitions": [ { "to": "S02_GateClosed" } ] },
    { "id": "S03_SliceEnd", "terminal": true }
  ]
}
```

회차 종료 시: 현재 스테이지의 `transitions`를 순서대로 보고, `reason`(기절 사유 필터, 선택)과 `when`이 맞는 첫 전환을 따른다. 맞는 게 없으면 **같은 스테이지에 머문다** (회차는 +1). 전환 조건은 끝나는 회차 기준으로 평가하므로 회차 플래그도 볼 수 있다. 그 다음 회차 플래그를 지운다.

---

## 월드 (world.json)

```jsonc
{
  "anchors": ["entrance", "gate", ...],                 // location/spawn 값으로 쓸 수 있는 위치
  "baseline": [ { "target": "gate", "prop": "state", "value": "open" } ],
  "rules": [
    { "target": "gate", "prop": "state", "value": "closed", "when": ["stage>=S02_GateClosed"] }
  ]
}
```

값 = baseline → 조건이 참인 rules를 **파일 순서대로 덮어씀 (나중 것이 이김).**
모든 rule은 같은 `(target, prop)`의 baseline이 있어야 한다. **변화는 정상 위의 차이로만 존재한다** — 이 게임의 공포 공식을 데이터 구조로 강제한 것.

예약된 prop: `location`, `spawn`(값은 앵커여야 함). 나머지 prop/value는 자유 문자열이고, 그 의미는 연출(BP)이 정한다.

---

## 세이브 파일

```jsonc
{ "format": "BTGSave", "version": 1, "checksum": "<sha256(정규화된 payload JSON)>", "payload": { /* 상태 모델 */ } }
```

- 쓰기: 임시 파일 → fsync → 원자적 교체. 기존 파일이 검증을 통과할 때만 `.bak`으로 보관.
- 읽기: 본 파일 → `.bak` 순서. 체크섬/형식/버전이 하나라도 틀리면 그 파일은 쓰지 않는다.
- 버전: 낮으면 마이그레이션 체인으로 올리고, 높으면 거부.
- UE 포팅: `USaveGame`에 payload JSON 문자열 + 체크섬 + 버전을 담고, `.bak` 대신 슬롯 A/B 교대 기록 + 시퀀스 번호를 쓴다.

**콘텐츠 업데이트 주의**: 출시 후 스테이지/플래그 id를 바꾸면 기존 세이브가 깨진다. id는 바꾸지 말고 추가만 하거나, 마이그레이션을 쓴다.
