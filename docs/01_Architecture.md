# 01. 아키텍처 — 첫 응답 (핸드오프 37장)

> 기준 문서: [`00_GDD_Handoff.md`](00_GDD_Handoff.md). 이 문서와 충돌하면 핸드오프가 이긴다.
> **엔진: Godot 4.7** (2026-10-02 오너 결정. 처음엔 UE5를 권했지만 아래 2.1의 이유로 변경)

---

## 0. 프로젝트 상태

| 항목 | 상태 |
|---|---|
| 시작 시점 | 완전히 빈 저장소 (커밋 0) |
| 엔진 | Godot 4.7.2 stable. 저장소 루트가 Godot 프로젝트 (`project.godot`) |
| 구현됨 | 내러티브 코어 (Python 레퍼런스 + GDScript 런타임), M01 데이터, 공용 시나리오 테스트, CI |
| 클라우드 작업 환경 | Nix로 Godot 설치 가능 (`Tools/godot/install_godot_nix.sh`). 헤드리스 테스트 + 소프트웨어 렌더링 스크린샷 가능. **소리는 못 들음**(사운드카드 없음) |

---

## 1. 핵심 구조 이해 (요약)

1. **이 게임의 실체는 "정상 상태 + 차이"다.** 공포는 플레이어가 외운 기준선에서 무언가 어긋날 때 생긴다. 데이터도 그렇게 생겼다: 월드 = `baseline` + 회차별 `rules`(diff), diff는 baseline 없이 존재할 수 없다 (검증기가 강제).
2. **루프는 플레이어가 온 뒤 생긴 현상이다.** 회차 = "하루". NPC는 타임루프가 아니라 '어제'를 기억하며 산다. 상태는 두 층: **영속**(NPC 기억, 관계 기록, 스토리 플래그)과 **회차**(손에 든 장작 — 기절하면 사라짐).
3. **진행 = Cycle × Stage × 관계 기록.** "몇 번째 날" × "나레이터가 어디까지 개입했나" × "플레이어가 어떻게 지냈나". 숫자 하나로 분기하지 않는다.
4. **나레이터 = 세계 관리자 = 코드상의 단일 권위.** 모든 상태를 알고 무엇을 보여줄지 고르는 곳은 하나뿐이다: autoload `Narrative`. 시스템 구조와 픽션이 일치한다.
5. **엔딩은 수치가 아니라 행동 기록으로 갈린다.** 호감도 대신 `rel:<npc>.<Event>`("어느 날 무엇을 했나")를 조합한다.
6. **메타는 희소 자원이다.** WAKE UP, 무음, 나레이터 음성은 아낄수록 세다.

---

## 2. 아키텍처

### 2.1 왜 Godot 4인가

| | Godot 4.7 | UE5 |
|---|---|---|
| 씬/리소스 형식 | **텍스트** (`.tscn`, `.tres`) → diff·리뷰·머지 가능, AI가 직접 편집 | 바이너리 (`.uasset/.umap`) |
| AI 작업 환경에서 실행 | **가능** (헤드리스 테스트, 렌더링 스크린샷) | 불가 (설치·빌드 불가) |
| 게임 규모 적합성 | 작은 마을, NPC 6명, 전투 없음 → 충분 | 과함 |
| 그래픽 상한 | 낮음 (이 게임의 공포는 그래픽이 아니라 '차이'에서 나옴) | 높음 |
| 컷신 도구 | AnimationPlayer (충분하지만 Sequencer보다 약함) | Sequencer |
| 라이선스 | MIT, 로열티 없음 | 매출 기준 로열티 |

핸드오프 28장의 C++/Blueprint 분업은 이렇게 옮긴다 — **원칙(핵심 로직과 연출의 분리)은 그대로**:

| 핸드오프 | Godot |
|---|---|
| C++ (핵심 시스템, 상태, 데이터, 세이브, 범용 컴포넌트) | **GDScript `core/`** — `class_name` 클래스 + autoload. 연출 코드 없음 |
| Blueprint (레벨 연출, 조명, 카메라, 시퀀스, VFX, 사운드 트리거) | **씬(`.tscn`) + AnimationPlayer + 씬 전용 스크립트** |
| DataTable / DataAsset | **JSON** (`GameData/`, 대사·규칙) + **Resource `.tres`** (보이스 프로파일처럼 에셋을 참조하는 설정 — 이것도 텍스트) |

### 2.2 레이어

```
┌───────────────────────────────────────────────────────────────┐
│ GameData/*.json     (텍스트 · 작가/기획/AI가 편집)              │
│   ↑ CI: Python 검증기 (Tools/narrative) — 참조 오류, 금지 문구   │
└──────────────────────────┬────────────────────────────────────┘
                           │ res://GameData 로드
┌──────────────────────────▼────────────────────────────────────┐
│ core/narrative (GDScript) — 연출을 모른다                       │
│  BTGCondition · BTGEffect · BTGStoryState · BTGNarrativeDB     │
│  BTGNarrativeEngine · BTGDialogueSession · BTGSaveSystem(A/B)  │
│  autoload Narrative  (= 나레이터의 책상)                        │
└──────────────────────────┬────────────────────────────────────┘
        시그널 / 이벤트     │ cue_emitted(이름), 대화 이벤트(line/pause/choices/end),
                           │ cycle_started, world_value(target, prop)
┌──────────────────────────▼────────────────────────────────────┐
│ 씬 (Presentation) — 규칙을 모른다                               │
│  마을 레벨, 조명, 카메라, AnimationPlayer, VFX, 오디오 배치, UI  │
│  기절 연출이 끝나면 Narrative.complete_cycle() 호출 (타임아웃)   │
└───────────────────────────────────────────────────────────────┘
```

**규칙 두 줄**
- core는 연출을 모른다. "GuardStare 해" 같은 **cue 이름**만 내보낸다.
- 씬은 규칙을 모른다. 상태를 판단하지 않고 받은 값(`gate.state = closed`)만 표현한다.

### 2.3 레퍼런스 구현과 공용 테스트

- `Tools/narrative/` (Python): 엔진 없이 도는 **레퍼런스 + 검증기 + 텍스트 프로토타입**. 작가가 Godot 없이 대사를 써보고 CI가 데이터를 검사한다.
- `core/narrative/` (GDScript): 실제 게임 런타임. 레퍼런스와 1:1.
- 두 구현이 **같은 파일**을 통과해야 한다: `GameData/tests/condition_vectors.json`, `GameData/tests/scenarios/*.json`, `GameData/tests/fixtures/semantics/`. 하나만 고치면 CI가 잡는다.

### 2.4 회차 파이프라인

```
Playing ──faint:<Reason>──▶ Fainting ──(연출 완료 or 타임아웃)──▶ Narrative.complete_cycle()
   ▲                                                                │ 스테이지 전환, cycle+1,
   │                                                                │ 회차 플래그 초기화, 체크포인트 저장
   └──── Waking ◀── get_tree().reload_current_scene() ◀─────────────┘
```

- **씬 리로드 방식**: 회차마다 마을 씬을 통째로 다시 연다. 상태는 autoload `Narrative`가 들고 넘어간다. 액터 상태 누수가 원천 차단되고 "세계가 리셋된다"는 픽션과도 맞는다.
- **저장 정책 (VS)**: 회차 시작 체크포인트만. 회차 도중 종료하면 그 회차를 처음부터 다시 한다.
- **세이브**: `user://saves/slot0_a.json` / `_b.json` 교대 기록 + 시퀀스 번호 + sha256. 쓰다가 죽어도 다른 슬롯이 남는다.

---

## 3. 주요 클래스 / 노드 / 리소스

### core (구현됨 ✅ / 예정)

| 클래스 | 역할 |
|---|---|
| ✅ `BTGCondition`, `BTGEffect` | 조건/효과 DSL 파싱·평가 |
| ✅ `BTGStoryState` | cycle, stage, 영속/회차 플래그, seen, rel, history. 세이브 payload와 1:1 |
| ✅ `BTGNarrativeDB` | `res://GameData` 로드 |
| ✅ `BTGNarrativeEngine` | 비트 선택, 효과, 월드 값, 회차 종료. `explain()` = "왜 이 대사?" 디버그 |
| ✅ `BTGDialogueSession` | 대화 체인 진행 (line/pause/choices/end 이벤트) |
| ✅ `BTGSaveSystem` | A/B 슬롯, 체크섬, 마이그레이션 |
| ✅ autoload `Narrative` | 게임 전체의 단일 스토리 권위. 시그널 `cue_emitted`, `cycle_started` |
| ✅ `BTGNarrativeTarget` (Node3D) | 노드에 `target_id`("guard", "gate") 부여. 상호작용 → `Narrative.trigger()`, 월드 값 변경 시 `world_value_changed(prop, value)` 시그널 |
| ✅ `BTGAnchor` (Marker3D) | `location`/`spawn` 값이 가리키는 위치 |
| ✅ `BTGNarrativeVolume` (Area3D) | 진입 시 `enter:<id>` |
| ✅ `BTGPlayer` (CharacterBody3D) | 1인칭 이동/시점, 레이캐스트 상호작용, 대화 중 입력 잠금 |
| ✅ `BTGDialogueBox` (CanvasLayer) | 타자기 출력, 선택지, 정적. 글자마다 페이크 보이스 호출 |
| ✅ presenters (`gate_presenter`, `sign_presenter`, `variant_presenter`) | 월드 값 → 보이는 모습. `variant_presenter`는 값 이름의 자식만 보여주는 범용 스위치 |
| `FakeVoice` + `VoiceProfile` (Resource `.tres`) | 샘플 세트, 피치/볼륨 범위, 초당 글자 수. 한글 음절(U+AC00–D7A3) 단위 블립 |
| `Footsteps` (Node) | **모든 발소리는 여기를 경유** — 나중에 지연/추가/소거 이상현상을 붙일 자리 |
| ✅ `BTGDirector` (Node) + `BTGFaintFx` | 2.4 파이프라인. 대화 → 기절 연출 → `complete_cycle()` → 씬 리로드 → 기상. 연출과 진행이 한 곳에 있어 완료 신호 누락이 없음 |
| `AudioDirector` (VS 이후) | 오디오 버스 구성(World/Footsteps/NPCVoice/Narrator/UI), 완전 무음, 나레이터 우선 |

### 씬이 담당 (핸드오프의 Blueprint 영역)

레벨 블록아웃, 앵커/볼륨 배치, 조명, 기절/기상 연출(AnimationPlayer + 화면 셰이더: 흐림·흔들림·그래픽 이상), cue 처리(카메라 당김, 손에 든 장작), 월드 값 표현(성문 닫힘 메시, 뒤집힌 간판), UI 비주얼.
**씬에 두지 않는 것**: 어떤 대사를 할지, 플래그 판단, 회차 분기, 저장.

---

## 4. Vertical Slice 구현 순서

→ [`02_VerticalSlice_Plan.md`](02_VerticalSlice_Plan.md)

## 5. 예상되는 가장 큰 기술적 위험 5개

| # | 위험 | 대응 |
|---|---|---|
| 1 | **손맛과 소리는 AI가 검증 못 함** — 헤드리스/소프트웨어 렌더링으로는 이동감, 대사 타이밍, 페이크 보이스 느낌, 무음의 공포를 판단할 수 없다 | 마일스톤마다 오너 플레이테스트 (핸드오프 31장 체크리스트). 타이밍 값은 전부 데이터(`pause`, VoiceProfile)라서 코드 수정 없이 조정 |
| 2 | **회차 리셋과 상태 일관성** — 리로드 시 상태 누수, 연출이 완료 신호를 안 보내면 소프트락, 기절 중 종료 | 명시적 상태 머신, 연출 타임아웃, 회차 시작에서만 저장, A/B 슬롯 (테스트로 고정됨) |
| 3 | **조건부 콘텐츠의 조합 폭발 + "의도된 모순" QA** — NPC 기억 모순이 의도된 연출이라 버그와 구분이 어렵다 | 우선순위 + 폴백 비트, 검증기, 경로별 시나리오 테스트, `explain()` 디버그, 의도된 모순은 비트 `note`에 명시 |
| 4 | **오디오가 게임플레이 시스템** — 한글 음절 동기 페이크 보이스, 발소리 이상현상, "버그로 착각할" 완전 무음, 나레이터 우선 | Day 1부터 오디오 버스 설계, 모든 플레이어 기원 소리는 단일 노드 경유, 무음 상태 자동 테스트(재생 중인 플레이어 0개) |
| 5 | **두 구현의 드리프트** — Python 레퍼런스와 GDScript 런타임이 조금씩 달라질 수 있다 | 공용 벡터/시나리오/픽스처를 두 쪽 CI가 모두 실행. 장기적으로 Python 엔진이 짐이 되면 검증기만 남기고 퇴역 |

차순위: 메타 종료 연출과 Steam 정책(실제 프로세스 종료 대신 "종료처럼 보이는" 연출, 엔딩 전 세이브), Steam 연동은 GodotSteam(GDExtension) 필요, 한국어 우선 텍스트의 현지화(Godot TranslationServer/CSV로 이전 시점), 저사양 PC에서 Forward+ 성능(필요하면 Mobile/Compatibility 렌더러).

## 6. 첫 번째 실제 구현 작업

→ [`02_VerticalSlice_Plan.md` 7장](02_VerticalSlice_Plan.md#7-지금까지-구현된-것)

---

## 결정 필요 (프로젝트 오너)

| 항목 | 현재 값 | 메모 |
|---|---|---|
| ~~엔진~~ | **Godot 4.7 (결정됨)** | |
| 2회차 기상 위치 | 마을 입구 (1회차 도착 지점과 동일) | 입구 → 광장 → 성문이 일직선이면 **눈 뜨자마자 닫힌 성문이 보인다** (VS 성공조건 5) |
| 경비의 "성문 **앞**에서 쓰러졌다" | 의도된 어긋남으로 사용 | 핸드오프 12장 대사에서 이미 플레이어는 성 **안**에서 쓰러졌다. 첫 미스터리 씨앗 (`guard.c2.where`) |
| "아무도 왕을 직접 본 적 없다" 씨앗 | 술집 주인 대사 2줄 | 왕의 실체가 미정이라 위험할 수 있음. 빼려면 `bartender.c1.king`/`bartender.c2.dontremember`의 해당 줄 삭제 |
| 경비 "누가 닫으라고 했더라" | 사용 | 2회차에 너무 이른 균열이면 삭제 |
| 3회차 티저(간판 뒤집힘) | VS 마지막 장면 | 성공조건 7("다음엔 뭐가 바뀌지?")용 장치. VS 범위 밖이라 빼도 됨 |
| 임시 대사 전반 | 전부 임시 | 톤 기준점일 뿐 최종 아님 |
