# 01. 아키텍처 제안 — 첫 응답 (핸드오프 37장)

> 기준 문서: [`00_GDD_Handoff.md`](00_GDD_Handoff.md). 이 문서와 충돌하면 핸드오프가 이긴다.
> 이 문서는 **제안**이다. "결정 필요" 항목은 프로젝트 오너가 정한다.

---

## 0. 현재 프로젝트 상태 (분석 결과)

| 항목 | 상태 |
|---|---|
| 저장소 | 처음엔 완전히 빈 저장소 (커밋 0, 코드/BP/에셋 없음) |
| 엔진 | **미정**. 프로젝트 파일 없음 |
| 구현된 기능 | 없음 → 이번 작업에서 엔진 독립 내러티브 코어 추가 (아래 7장) |
| 이 클라우드 작업 환경 | UE/Unity/Godot 없음. Python 3.11, clang/cmake만 있음 → **엔진 빌드·실행 검증 불가** |

결론: 덮어쓸 것도 깨뜨릴 것도 없다. 대신 엔진 코드는 여기서 컴파일할 수 없으므로, 엔진이 정해지기 전에 **엔진과 무관하게 검증 가능한 부분**(스토리 상태·조건·대사·회차·세이브 규칙)을 먼저 만들고 자동 테스트로 고정했다.

---

## 1. 핵심 구조 이해 (요약)

1. **이 게임의 실체는 "정상 상태 + 차이"다.** 공포는 플레이어가 외운 기준선(baseline)에서 무언가가 어긋날 때 생긴다. 그래서 데이터도 그렇게 생겼다: 월드는 `baseline` + 회차별 `rules`(diff)이고, diff는 baseline 없이 존재할 수 없다 (검증기가 강제).
2. **루프는 세계의 속성이 아니라 플레이어가 온 뒤 생긴 현상이다.** 회차 = "하루". NPC는 타임루프를 사는 게 아니라 '어제'를 기억하며 산다. 그래서 상태는 두 층이다.
   - **영속(persistent)**: NPC의 기억, 관계 이벤트, 스토리 플래그 → 기절해도 남는다.
   - **회차(cycle)**: 손에 든 장작, 오늘 이미 한 대화 → 기절하면 사라진다.
3. **진행 = Cycle × Stage × 관계 기록.** Cycle은 "몇 번째 날", Stage는 "나레이터가 어디까지 개입했나", 관계 기록은 "플레이어가 이 세계에서 어떻게 지냈나". 숫자 하나로 모든 걸 분기하지 않는다 (핸드오프 27장).
4. **나레이터 = 세계 관리자 = 코드상의 Director.** 모든 상태를 알고, 무엇을 보여줄지 고르는 단일 지점. 시스템 구조와 픽션이 일치한다. 내러티브 서브시스템이 사실상 나레이터다.
5. **엔딩은 수치가 아니라 행동의 기록으로 갈린다.** 호감도 숫자 대신 `rel:<npc>.<Event>` 기록("어느 날 무엇을 했나")을 조합한다.
6. **메타는 희소 자원이다.** WAKE UP, 무음, 나레이터 음성은 아껴 쓸수록 세다. 시스템이 이걸 남발하기 쉬운 구조면 안 된다.

---

## 2. 아키텍처 제안

### 2.1 엔진: **UE5 권장** (결정 필요)

핸드오프 27~28장이 C++/Blueprint/DataTable/DataAsset을 전제로 쓰여 있어서 UE5가 가장 마찰이 적다.

- 1인칭 템플릿, Level Sequence(기절/기상 연출), Post Process(흐림/그래픽 이상)가 기본 제공.
- **오디오가 핵심 시스템**인 게임에 MetaSounds + Sound Class/Submix/Sound Mix 조합이 강력함 (페이크 보이스, 지연 발소리, 완전 무음, 나레이터 우선).
- 단점: 무겁고, `.uasset/.umap`이 바이너리라 AI 에이전트가 편집/리뷰할 수 없음 (→ 위험 1).

대안: Godot 4 (가볍고 씬이 텍스트라 AI 친화적이지만, 핸드오프의 C++/BP 분업 전제를 다시 써야 함).
**내러티브 데이터와 규칙은 엔진 독립**으로 만들었으므로 엔진 결정이 늦어도 이번 작업은 버려지지 않는다.

### 2.2 레이어

```
┌───────────────────────────────────────────────────────────────┐
│ GameData/*.json         (텍스트 · diff 가능 · AI 편집 가능)    │
│  registry / targets / stages / world / beats                  │
│  ↑ CI: Tools/narrative (검증기 + 레퍼런스 구현 + 테스트)        │
└──────────────────────────┬────────────────────────────────────┘
                           │ 런타임 로드 (에디터에서 핫 리로드)
┌──────────────────────────▼────────────────────────────────────┐
│ Narrative Core (C++)   — 연출을 모른다                         │
│  StoryState · Conditions · Beats · Stage 전환 · World 규칙     │
│  CycleSubsystem(기절→전환→저장→리로드→기상) · Save(A/B+체크섬) │
└──────────────────────────┬────────────────────────────────────┘
         이벤트(델리게이트)│ OnLine / OnChoices / OnCue(이름)
                           │ OnFaintRequested(사유) / OnWorldValueChanged
┌──────────────────────────▼────────────────────────────────────┐
│ Presentation (Blueprint) — 규칙을 모른다                       │
│  레벨, 조명, 카메라, Level Sequence, VFX, 사운드 배치, UI 비주얼 │
│  완료 통지: NotifyFaintPresentationFinished() (타임아웃 있음)   │
└───────────────────────────────────────────────────────────────┘
```

**규칙 두 줄**
- Core는 연출을 모른다. "GuardStare 해" 같은 **cue 이름**만 내보낸다.
- Presentation은 규칙을 모른다. 상태를 판단하지 않고, 받은 값(`gate.state = closed`)을 보여주기만 한다.

### 2.3 데이터 배치 규칙

| 무엇 | 어디 | 이유 |
|---|---|---|
| 대사, 조건, 플래그, 스테이지, 월드 규칙 | **JSON** (`GameData/`) | diff/리뷰/머지 가능, AI가 편집 가능, 하나의 소스, CI 검증 |
| 에셋을 참조하는 것 (보이스 샘플 세트, cue→시퀀스 매핑, 기절 연출 프로파일) | **UE DataAsset** | 에디터에서 에셋 참조·미리듣기가 필요 |

JSON은 패키징 시 `Content/GameData`로 옮겨 "Additional Non-Asset Directories to Package"에 등록한다 (엔진 확정 시 `git mv`).

### 2.4 회차 파이프라인 (상태 머신)

```
Playing ──faint:<Reason>──▶ Fainting ──(BP 연출 완료 or 타임아웃 15s)──▶ Transitioning
   ▲                                                                       │ Stage 전환 규칙 평가
   │                                                                       │ cycle+1, 회차 플래그 초기화
   │                                                                       │ 저장 (체크포인트)
   └──────── Waking ◀── OpenLevel(같은 맵) ◀──────────────────────────────────┘
```

- **레벨 리로드 방식**: 회차마다 같은 맵을 다시 연다. GameInstance 서브시스템이 상태를 들고 넘어간다. 액터 상태 누수가 원천 차단되고, "세계가 리셋된다"는 픽션과도 일치한다. 맵이 작아서 로딩은 짧다.
- **저장 정책 (VS)**: 회차 시작 시점 체크포인트만. 회차 도중 종료하면 그 회차를 처음부터 다시 한다. 회차가 짧아서 손해가 작고, 저장 타이밍 버그가 사라진다. 회차 중간 저장은 VS 이후에 필요하면 추가.

---

## 3. 주요 C++ Class / Component / DataAsset 목록 (UE 기준, 접두사 `BTG`)

### Narrative Core (게임 로직, 연출 없음)

| 클래스 | 종류 | 역할 |
|---|---|---|
| `FBTGStoryState` | USTRUCT | cycle, stage, 영속/회차 플래그, seen(비트→회차), rel(npc.Event→회차), history. 세이브 payload와 1:1 |
| `FBTGCondition`, `FBTGConditionParser` | USTRUCT + 정적 함수 | 조건 DSL 파싱/평가. `condition_vectors.json` 통과가 완료 기준 |
| `FBTGEffect` | USTRUCT | `set/clear/rel/cue/faint` |
| `UBTGNarrativeDatabase` | UObject | `GameData/*.json` 로드, 인덱싱, `btg.ReloadNarrative` 콘솔 명령으로 핫 리로드 |
| `UBTGNarrativeSubsystem` | UGameInstanceSubsystem | StoryState 소유. `TriggerAction(Verb, TargetId)` → 비트 선택 → 대화 진행. `OnCue`, `OnFlagChanged` 브로드캐스트. **= 나레이터** |
| `UBTGDialogueRunner` | UObject | 한 대화 체인 진행 (줄/정적/선택지/next). Python `DialogueSession`과 동일 동작 |
| `UBTGCycleSubsystem` | UGameInstanceSubsystem | 2.4의 상태 머신. 연출 핸드셰이크 + 타임아웃 |
| `UBTGWorldStateSubsystem` | UWorldSubsystem | baseline+rules 평가 → 대상 컴포넌트에 `(prop, value)` 푸시. 맵 시작/플래그 변경 시 재평가 |
| `UBTGSaveSubsystem` + `UBTGSaveGame` | UGameInstanceSubsystem + USaveGame | StoryState를 JSON 문자열로 보관 + 버전 + 체크섬. 슬롯 A/B 교대 기록, 최신 유효 슬롯 로드, 마이그레이션 테이블 |
| `UBTGSettingsSave` | USaveGame | 설정(음량, 자막, 감도)은 스토리 세이브와 분리 |

### 월드와 연출 사이 (범용 컴포넌트, BP에서 확장)

| 클래스 | 종류 | 역할 |
|---|---|---|
| `UBTGNarrativeTargetComponent` | ActorComponent | 액터에 `TargetId`("guard", "gate")를 부여. 상호작용을 Core로 전달, `OnWorldValueChanged(Prop, Value)` BP 이벤트 |
| `ABTGAnchor` | Actor | `location`/`spawn` 값이 가리키는 위치 표식 |
| `ABTGNarrativeVolume` | TriggerBox | `enter:<id>` 발생 (예: 성 현관) |
| `UBTGInteractionComponent` | 플레이어 컴포넌트 | 라인트레이스, 포커스 프롬프트, `IBTGInteractable` 호출 |
| `ABTGPlayerCharacter` / `ABTGPlayerController` / `ABTGGameMode` | | 1인칭 이동·시점, 대화 중 입력 잠금 |
| `UBTGDialogueWidgetBase` | UUserWidget (C++ 베이스) | 타자기 출력 로직. 글자마다 `OnCharacterRevealed` → 페이크 보이스. 비주얼은 BP 자식에서 |
| `UBTGFakeVoiceComponent` | ActorComponent | 한글 음절(U+AC00–D7A3) 단위 블립, 공백 스킵, 문장부호/`……`에서 멈춤 |
| `UBTGFootstepComponent` | ActorComponent | **모든 발소리는 여기를 경유**. VS에선 정상 재생만 하지만, 나중에 지연/추가/소거 이상현상을 리팩터링 없이 붙일 자리 |
| `UBTGAudioDirectorSubsystem` | UWorldSubsystem | (VS 이후) 스테이지별 환경음 프로파일, 이상현상 스케줄, 완전 무음 Sound Mix, 나레이터 우선. VS에선 Sound Class 계층만 만들어 둠 |

### DataAsset (에셋 참조가 필요한 것만)

| DataAsset | 내용 |
|---|---|
| `UBTGVoiceProfile` | Sound Set(샘플 배열), Pitch Min/Max, Volume Min/Max, 초당 글자 수, N글자당 블립, 문장부호 정지 시간. `targets.json`의 `voice` id(`VP_Guard`)와 매칭 |
| `UBTGFaintProfile` | 기절 사유별 연출 파라미터 (이명 사운드, 흐림 커브, 길이). `faintReasons` id와 매칭 |
| `UBTGCueMap` | cue 이름 → Level Sequence / BP 이벤트 매핑. 등록 안 된 cue는 경고 로그 |

---

## 4. Blueprint 담당 영역

- **레벨**: 블록아웃, 앵커 배치, 볼륨 배치, 조명, 환경음 배치.
- **기절/기상 연출**: Level Sequence + Post Process (이명 → 흐림 → 흔들림 → 그래픽 이상 → 암전). 끝나면 `NotifyFaintPresentationFinished()` 호출.
- **cue 처리**: `GuardStare`(카메라 살짝 당김, 고개 기울임), `PickUpFirewood`(손에 장작 메시) 등 `UBTGCueMap`에 연결된 이벤트들.
- **월드 값 표현**: `OnWorldValueChanged("state", "closed")` → 성문 닫힌 메시/애니메이션. 간판 뒤집기 등.
- **UI 비주얼**: 대화창, 선택지, 상호작용 프롬프트 (로직은 C++ 베이스).
- **카메라/VFX/사운드 트리거**: 레벨 고유 연출.

**BP에 두지 않는 것**: 어떤 대사를 할지, 플래그 판단, 회차 분기, 저장. (핸드오프 0장: 반복 콘텐츠를 BP에 하드코딩하지 않는다.)

---

## 5. Vertical Slice 구현 순서

→ [`02_VerticalSlice_Plan.md`](02_VerticalSlice_Plan.md)

## 6. 예상되는 가장 큰 기술적 위험 5개

| # | 위험 | 왜 위험한가 | 대응 |
|---|---|---|---|
| 1 | **바이너리 에셋 vs AI 협업** | `.uasset/.umap`은 AI가 열지도, 리뷰하지도, 머지하지도 못한다. BP에 로직이 쌓일수록 AI가 도울 수 있는 범위가 줄고, 충돌 시 한쪽 작업이 날아간다 | 로직/콘텐츠는 텍스트(C++/JSON), BP는 얇게. 반복 에셋 세팅은 Editor Utility/Python 스크립트로. Git LFS + 파일 잠금 |
| 2 | **이 환경에서 엔진 빌드 불가** | 클라우드 세션에 UE가 없어서, 여기서 작성한 C++는 컴파일 확인 없이 커밋된다 (핸드오프 32장 6번 위반 위험) | 규칙을 엔진 독립 레퍼런스 + 공용 테스트 벡터로 먼저 고정. 엔진 코드는 작은 PR 단위로 쓰고 오너 로컬 빌드로 확인. 장기적으로 UE 빌드 가능한 CI 러너 고려 |
| 3 | **회차 리셋과 상태 일관성** | 리로드 시 상태 누수, 연출 BP가 완료 콜백을 안 부르면 소프트락, 기절 도중 종료 시 진행 꼬임 | 명시적 Cycle 상태 머신, 연출 핸드셰이크 타임아웃, 안정 지점(회차 시작)에서만 저장, A/B 슬롯 + 체크섬 |
| 4 | **조건부 콘텐츠의 조합 폭발 + "의도된 모순" QA** | 플래그 × 회차 × 관계가 곱해지면 틀린 대사/무반응이 생긴다. 게다가 이 게임은 NPC 기억 모순이 **의도된 연출**이라, 버그와 연출을 구분하기 어렵다 | 우선순위 + 무조건 폴백 비트, 검증기(미등록 플래그/도달 불가 비트/폴백 누락), 경로별 플레이스루 테스트, `why` 디버그(왜 이 대사가 골라졌나), 의도된 모순은 비트 `note`에 명시 |
| 5 | **오디오가 게임플레이 시스템** | 한글 음절 동기 페이크 보이스, 발소리 지연/추가, "사운드 버그로 착각할" 완전 무음(UI·리버브 꼬리·엔진 소리 누수), 나레이터 우선순위. 나중에 붙이면 전부 리팩터링 | Day 1부터 Sound Class/Submix 계층 설계, 모든 플레이어 기원 소리는 단일 컴포넌트 경유, 무음 상태를 자동 테스트(활성 오디오 컴포넌트 0개 검사) |

차순위: 메타 종료 연출과 Steam 정책/세이브 안정성(엔딩 전 세이브 선기록, 실제 프로세스 종료 대신 "종료처럼 보이는" 연출), 한국어 우선 텍스트의 현지화(String Table 이전 시점), "무음 = 버그"로 오인한 실제 버그 리포트/환불.

## 7. 첫 번째 실제 구현 작업

→ [`02_VerticalSlice_Plan.md` 7장](02_VerticalSlice_Plan.md#7-첫-번째-실제-구현-작업-완료)

---

## 결정 필요 (프로젝트 오너)

| 항목 | 임시값 | 메모 |
|---|---|---|
| 엔진 | UE5 권장 | 확정되면 프로젝트 생성 단계로 진행 |
| 2회차 기상 위치 | 마을 입구 (1회차 도착 지점과 동일) | 입구 → 광장 → 성문이 일직선이면 **눈 뜨자마자 닫힌 성문이 보인다** (VS 성공조건 5) |
| 경비의 "성문 **앞**에서 쓰러졌다" | 의도된 어긋남으로 사용 | 핸드오프 12장 대사에서 이미 플레이어는 성 **안**에서 쓰러졌다. 첫 미스터리 씨앗으로 쓰자는 제안 (`guard.c2.where`) |
| "아무도 왕을 직접 본 적 없다" 씨앗 | 술집 주인 대사 2줄 | 왕의 실체가 미정이라 위험할 수 있음. 빼려면 `bartender.c1.king`/`bartender.c2.dontremember`의 해당 줄만 삭제 |
| 경비 "누가 닫으라고 했더라" | 사용 | 2회차에 너무 이른 균열이면 삭제 |
| 3회차 티저(간판 뒤집힘) | VS 마지막 장면 | 성공조건 7("다음엔 뭐가 바뀌지?")을 위한 장치. VS 범위 밖이라 빼도 됨 |
| 임시 대사 전반 | 전부 임시 | 톤 기준점일 뿐 최종 아님 |
