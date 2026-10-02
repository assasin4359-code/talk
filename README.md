# Back to the Gates

1인칭 스토리 어드벤처. 코미디 → 미스터리 → 심리적/메타 호러. PC/Steam. 전투 없음.

> 평범한 판타지 마을에 도착한 외지인이 성에 들어가려다 같은 장소와 사람들을 반복해서 경험하고,
> 그 모든 변화가 자신을 즐겁게 하려고 세계의 관리자(나레이터)가 만든 것이었다는 사실을 발견한다.

**현재 단계:** Milestone 01 (THE FIRST RETURN) — 엔진 독립 내러티브 코어 + 텍스트 프로토타입. 엔진 미정 (UE5 권장).

## 문서

| 문서 | 내용 |
|---|---|
| [`docs/00_GDD_Handoff.md`](docs/00_GDD_Handoff.md) | **최상위 기획 기준** (오너 원문) |
| [`docs/01_Architecture.md`](docs/01_Architecture.md) | 아키텍처, 클래스 목록, BP 영역, 기술 위험, 결정 필요 항목 |
| [`docs/02_VerticalSlice_Plan.md`](docs/02_VerticalSlice_Plan.md) | M01 비트 시트, 블록아웃 요구사항, 구현 순서, 플레이테스트 체크리스트 |
| [`docs/03_Narrative_Data_Spec.md`](docs/03_Narrative_Data_Spec.md) | `GameData/` 형식과 엔진이 지켜야 할 동작 규칙 |

## 지금 바로 해보기 (Python 3.10+, 외부 패키지 없음)

```bash
python Tools/narrative/btg.py play                 # Milestone 01 텍스트 버전 (help로 명령어)
python Tools/narrative/btg.py play --new --fast    # 새로 시작, 연출용 정적 없이
python Tools/narrative/btg.py play --walkthrough   # 골든 패스 자동 재생
python Tools/narrative/btg.py validate             # GameData 검사
python -m unittest discover -s Tools/narrative/tests -t Tools/narrative/tests
```

## 구조

```
GameData/              게임 데이터 (JSON) — 대사, 조건, 플래그, 스테이지, 월드 규칙
  beats/               NPC/소품별 비트(대사·선택지·효과)
  tests/               조건 DSL 적합성 벡터 (엔진 포팅도 통과해야 함)
Tools/narrative/       엔진 독립 레퍼런스 구현 + 검증기 + 텍스트 프로토타입
  prototype/           텍스트 프로토타입 전용 임시 데이터 (게임 데이터 아님)
docs/                  기획/설계 문서
```
