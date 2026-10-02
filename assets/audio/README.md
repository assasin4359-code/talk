# 소리

지금 게임에서 나는 소리는 **전부 임시 합성음**이다 (`Tools/audio/make_placeholders.py`가 만든다).
진짜 소리가 오면 갈아 끼운다. 코드는 그대로 두고 `.tres` 파일 속 샘플만 바꾸면 된다.

## 진짜 소리 보내는 법

1. GitHub에서 이 레포 → `assets/audio/inbox/` 폴더로 이동 → **Add file → Upload files**
2. 파일을 끌어다 놓는다. 이름은 아무거나 괜찮다 (예: `발소리_흙.zip`, `fire.wav`)
3. 커밋 메시지에 **출처 링크**를 적는다 (예: `freesound.org/s/12345, CC0`)
4. Commit changes → Claude에게 "올렸어"라고 말하면 끝

형식은 WAV, OGG, MP3, ZIP 다 괜찮다. 자르기, 음량 맞추기, 루프 만들기는 Claude가 한다.

## 라이선스 (중요)

Steam에 팔 게임이므로 **상업적 사용이 허락된 소리만** 쓴다.

| 괜찮음 | 안 됨 |
|---|---|
| **CC0** (퍼블릭 도메인, 제일 편함) | **NC** (비상업) 들어간 CC 라이선스 |
| CC-BY (출처 표기하면 됨. 작성자 이름을 같이 적어줘) | ND, "개인 사용만", 라이선스 표기 없는 파일 |
| 로열티 프리 번들 (Sonniss GDC 번들 등) | 유튜브·게임에서 녹음한 소리 |
| 직접 녹음한 소리 | |

찾기 좋은 곳: [freesound.org](https://freesound.org) (검색 필터에서 라이선스 = Creative Commons 0),
[Sonniss GDC 무료 번들](https://sonniss.com/gameaudiogdc), [Kenney](https://kenney.nl/assets?q=audio) (전부 CC0).

## 원하는 소리 (우선순위 순)

| # | 자리 | 지금 (임시) | 원하는 진짜 소리 | 메모 |
|---|---|---|---|---|
| 1 | 발소리 · 흙길 | `footsteps/dirt_1..4` | 흙/자갈길 걷는 소리 | 한 발짝씩 4~8개면 최고. 긴 녹음 하나도 OK (Claude가 자름) |
| 1 | 발소리 · 돌바닥 | `footsteps/stone_1..4` | 돌바닥 걷는 소리 (광장, 성 현관) | 가죽 신발 느낌. 하이힐 X |
| 1 | 발소리 · 나무 | `footsteps/wood_1..4` | 나무 마루 걷는 소리 (술집) | 살짝 삐걱이면 좋음 |
| 2 | 마을 낮 환경음 | `ambience/wind_loop` (바람만) | 새소리, 멀리 사람 소리, 가벼운 바람 | **30초 이상**. 1회차를 "살아 있는 마을"로 만드는 핵심 (핸드오프 §16) |
| 3 | 술집 벽난로 | `ambience/fire_loop` | 장작 타는 타닥 소리 | 10초 이상 |
| 3 | 술집 웅성거림 | 없음 | 손님 몇 명이 낮게 떠드는 소리, 잔 부딪히는 소리 | 말소리가 알아들리면 안 됨 |
| 4 | 성문 | 없음 | 큰 나무 문 삐걱 + 쿵 닫힘 | 열리는 소리 / 닫히는 소리 따로면 좋음 |
| 4 | 장작 | 없음 | 장작 집어 들기, 바구니에 내려놓기 | |
| 5 | 술집 음악 | 없음 | 류트·기타 같은 소박한 연주 | 루프 가능한 1~2분 |
| 6 | 목소리 블립 | `voice/blip_a..u` (합성) | **안 바꿔도 됨.** 원하면 짧은 "아/에/이/오/우" 녹음 | 본인 목소리 녹음도 OK. 캐릭터별 높낮이는 피치로 만든다 |

기절 때 나는 이명(사인파)은 일부러 합성음 그대로 둔다.

## 구조 (Claude용)

| 경로 | |
|---|---|
| `placeholder/` | 임시 합성음. `python Tools/audio/make_placeholders.py`로 다시 만들 수 있다 (항상 같은 결과) |
| `voices/VP_*.tres` | `BTGVoiceProfile` — 캐릭터 목소리. 샘플 5개(a e i o u 순서), 피치·음량 범위, 초당 글자 수 |
| `sets/*.tres` | `BTGSoundSet` — 무작위로 하나 고르는 소리 묶음 (발소리 등) |
| `inbox/` | 오너가 올리는 곳. Godot가 무시함 |

오디오 버스 (`default_bus_layout.tres`): Master ← World(Ambient, Footsteps, SFX) / Voice(NPCVoice, Narrator) / UI / Music.
나중에 "완전 무음"은 World와 NPCVoice를 끄고 Narrator만 남기는 식으로 만든다.

루프 파일은 WAV `smpl` 청크로 루프 지점을 넣어 둔다 (Godot가 자동 인식). 진짜 루프 소리를 넣을 때도 같은 방식이거나 `.import`의 `edit/loop_mode`를 설정한다.
