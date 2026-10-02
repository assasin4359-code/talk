# Back to the Gates

1인칭 스토리 어드벤처. 코미디 → 미스터리 → 심리적/메타 호러. PC/Steam. 전투 없음. **Godot 4.7.**

> 평범한 판타지 마을에 도착한 외지인이 성에 들어가려다 같은 장소와 사람들을 반복해서 경험하고,
> 그 모든 변화가 자신을 즐겁게 하려고 세계의 관리자(나레이터)가 만든 것이었다는 사실을 발견한다.

**현재 단계:** Milestone 01 (THE FIRST RETURN) — **처음부터 끝까지 플레이 가능** (회색 박스, 임시 대사, 소리 거의 없음). 다음: 플레이테스트 → 페이크 보이스 → 환경음.

## 문서

| 문서 | 내용 |
|---|---|
| [`docs/00_GDD_Handoff.md`](docs/00_GDD_Handoff.md) | **최상위 기획 기준** (오너 원문) |
| [`docs/01_Architecture.md`](docs/01_Architecture.md) | 아키텍처, 클래스 목록, 씬 담당 영역, 기술 위험, 결정 필요 항목 |
| [`docs/02_VerticalSlice_Plan.md`](docs/02_VerticalSlice_Plan.md) | M01 비트 시트, 블록아웃 요구사항, 구현 순서, 플레이테스트 체크리스트 |
| [`docs/03_Narrative_Data_Spec.md`](docs/03_Narrative_Data_Spec.md) | `GameData/` 형식, 실행 규칙, 시나리오 테스트 형식 |

## 실행

**Godot 4.7** ([다운로드](https://godotengine.org/download), 압축만 풀면 됨) → Import → 이 폴더의 `project.godot` → F5.
| 키 | |
|---|---|
| WASD / 마우스 | 이동 / 시점 (Shift 달리기). 점프는 없음(의도) — 30cm 이하 턱은 자동으로 넘어감 |
| E (또는 클릭, Space) | 말 걸기·살펴보기, 대사 넘기기 |
| 1~9 | 선택지 |
| Esc | 마우스 해제 |
| F9 | 1회차부터 다시 (진행은 회차 시작마다 자동 저장되고, 다음 실행 때 이어서 시작) |

텍스트 프로토타입은 Python만 있으면 된다 (3.10+, 외부 패키지 없음):

```bash
python Tools/narrative/btg.py play                 # Milestone 01 텍스트 버전 (help로 명령어)
python Tools/narrative/btg.py play --walkthrough   # 골든 패스 자동 재생
```

## 테스트

```bash
python Tools/narrative/btg.py validate                                     # GameData 검사
python -m unittest discover -s Tools/narrative/tests -t Tools/narrative/tests
GODOT=/path/to/godot Tools/godot/run_tests.sh                              # Godot 쪽 (같은 시나리오)
```

## 구조

```
project.godot          Godot 프로젝트 (저장소 루트)
core/narrative/        게임 런타임의 내러티브 코어 (GDScript). autoload Narrative
game/                  플레이어, 월드 표현(앵커/대상/볼륨/성문/간판), HUD, 디렉터
scenes/                village.tscn (blockout/build_village.gd가 생성하는 회색 박스)
assets/fonts/          Pretendard (OFL)
tests/                 Godot 헤드리스 테스트 (+ visual/capture.gd 스크린샷)
GameData/              게임 데이터 (JSON) — 대사, 조건, 플래그, 스테이지, 월드 규칙
  tests/               공용 테스트: 조건 벡터, 시나리오, 픽스처 (Python과 Godot이 둘 다 실행)
Tools/narrative/       Python 레퍼런스 구현 + 검증기 + 텍스트 프로토타입
Tools/godot/           테스트 실행/클라우드 설치 스크립트
docs/                  기획/설계 문서
```
