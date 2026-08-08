# macOS 패리티 백로그

기준일: 2026-08-08
상태: 진행 중 — 항목이 이식되면 여기서 지우고 해당 문서로 옮긴다
목적: **macOS 에서 이미 원인을 규명하고 고친 것 중 Windows 에 아직 없는 것**을 한 곳에 모은다

관련 문서:

- [roadmap](roadmap.md) — 언제 할 것인가
- [field-lessons](../10-lessons/field-lessons.md) — 이미 실패한 시도들
- [driver-option-reference](../10-lessons/driver-option-reference.md) — 드라이버 옵션 사실관계

## 0. 이 문서가 필요한 이유

Windows 포팅은 macOS 코드를 따라 옮긴 것이라, macOS 쪽에서 나중에 고친 결함이 Windows 에는
**고치기 전 상태 그대로 남는다**. 실기로 원인을 규명하는 데 든 시간이 가장 비싼 자원인데,
그 결론이 한쪽에만 반영되면 같은 조사를 두 번 하게 된다.

각 항목에 **무엇을 관측했고 왜 그렇게 고쳤는지**를 남긴다. 결론만 적으면 이식할 때 판단
근거가 없어 또 실험하게 된다.

## 1. 이미 이식한 것

| 항목 | macOS 커밋 | Windows 반영 |
|---|---|---|
| 필름 홀더용 투과 소스 우선 | `fix: prefer the film holder transparency source` | `sane/capabilities.cpp` |
| 표시상 같은 값의 rounded 경고 무시 | `fix: only reject SANE rounding when the value actually changed` | `process/progress.cpp` |

두 항목의 근거는 아래와 같다. Windows 코드 주석에도 같은 요지를 남겼다.

**투과 소스 우선순위** — Epson V700/V750/V800/V850 계열은 필름 홀더용 소스와 8x10 필름
영역 가이드용 소스를 따로 노출한다. 8x10 쪽은 영역이 넓지만 유리면에 초점을 두는 **다른
렌즈**를 쓴다. GT-X900 실기에서 같은 필름 지점을 위상상관으로 정렬(정렬 후 상관계수
0.9942)해 비교하니 홀더용이 **1.76배 선명**했다. 같은 조건 반복 측정의 편차가 2.9% 인 것에
비하면 압도적인 차이다. 두 소스는 좌표계도 서로 달라, 프리뷰에서 잡은 영역을 본 스캔에
그대로 쓸 수 없다. 그래서 프리뷰와 본 스캔 모두 홀더용을 쓰고, 8x10 만 노출하는 장치에서만
그것을 고른다.

**rounded 경고** — SANE 은 값을 고정소수점(1/65536)으로 들고 있어 mm 요청이 정확히
표현되지 않는 일이 흔하다. 그때 scanimage 가 `rounded value of br-x from 149.86 to 149.86`
처럼 **표시상 같은 값**으로 경고를 낸다. 경고 문자열의 존재만 보고 실패로 처리하면, 100%
까지 완주한 스캔이 통째로 거절된다. from/to 를 읽어 실제로 값이 바뀐 경우에만 실패로 본다.

## 2. 아직 없는 것

### 2-1. 스캔 초점 제어 (focus / autofocus)

Windows 트리에 `focus` 관련 코드가 **한 줄도 없다**. macOS 에는 `ScanFocus`(auto/manual),
프로토콜 필드, `--focus`/`--autofocus` 인자 생성, capabilities 의 `focusRange`/
`supportsAutofocus` 가 들어가 있다.

이식할 때 알아야 할 사실:

- 장치가 `--focus` 를 **활성 옵션으로 노출할 때만** 켜야 한다. OpticFilm 처럼 옵션이 없는
  기종에서 인자를 보내면 스캔이 실패한다. 요청이 없으면 인자를 아예 보내지 않아 기존
  동작이 그대로 보존되어야 한다.
- `--autofocus=yes` 와 `--focus=<값>` 을 **동시에 보내면 안 된다**. 장치가 어느 쪽을
  따르는지 보장할 수 없다. 프로토콜 단계에서 상호배타로 막는다.
- **GT-X900 에서는 focus 가 실효가 없다.** 0~254 전 범위(유리면 기준 −6.4 ~ +19.0mm)를
  훑어도 선명도 변동이 7.7%, 픽셀 차이가 1.89% 에 그쳤다. 25mm 를 움직였다면 있을 수 없는
  수치다. Perfection 1650 에서도 같은 사례가 보고돼 있다 — 펌웨어가 `ESC p` 에 응답만 하고
  광학계는 움직이지 않는 것으로 보인다. 그래서 **이 기종용 UI 는 만들지 않는다**. 실제로
  초점이 움직이는 기종(Expression 12000XL 등)을 위해 경로만 열어 두는 성격이다.
- 우선순위는 낮다. 초점이 흐린 원인은 focus 값이 아니라 **위 1절의 소스(렌즈) 선택**이었고,
  그쪽은 이미 이식했다.

### 2-2. epson2 적외선 모드 활성화 (SANE 패치)

이것은 플러그인 코드가 아니라 **SANE 빌드 패치**다. macOS 는 Homebrew Formula 의 패치로
해결했고, Windows 는 SANE 을 어떻게 빌드하는지에 따라 반영 방법이 달라진다.

사실관계:

- epson2 에는 Epson 의 문서화되지 않은 IR 활성화 절차가 **이미 구현돼 있다**
  (`esci_enable_infrared` 의 32바이트 magic sequence XOR). 모델 판정에도 GT-X700/X800/
  X900/X980 이 들어 있다.
- 그런데 `sane.h` 가 `SANE_FRAME_IR` 을 `#if 0` 안에 두고 있어서, `mode_list` 의
  `"Infrared"` 항목과 `e2_init_parameters` 의 IR 분기가 **둘 다 컴파일에서 빠진다**.
  라이브러리 버전을 올리는 합의가 안 돼 비활성으로 남은 상태다.
- IR 프레임 타입을 부활시키면 SANE ABI 를 건드리게 되고 프론트엔드까지 연쇄로 손봐야 한다.
  대신 두 `#ifdef` 를 걷어내 모드를 노출하고, 결과를 `SANE_FRAME_IR` 이 아니라
  **`SANE_FRAME_GRAY`** 로 내보낸다. 프론트엔드에서는 그냥 16-bit 그레이스케일이라 아무것도
  바꿀 필요가 없다. 이 그레이가 IR 이라는 사실은 호출하는 쪽이 알면 된다.
- 패치 위치는 두 곳이다. `backend/epson2.c` 의 `mode_list` 에서 `#ifdef SANE_FRAME_IR` /
  `#endif` 제거, `backend/epson2-ops.c` 의 `MODE_INFRARED` 분기에서 같은 `#ifdef` 제거와
  `SANE_FRAME_IR` → `SANE_FRAME_GRAY` 치환.

플러그인 쪽은 손댈 것이 없다. `IRStrategy::SeparateMode` 가 이미 있어서, SANE 이 모드를
노출하기만 하면 `capabilities` 가 자동으로 `supportsInfrared` 를 켜고 2-pass 획득이 그대로
돈다. macOS 에서 실제로 그렇게 동작했다.

측정값(GT-X900, 컬러 네거티브):

- IR 평균 투과 **98.9%**, 표준편차 0.9% — 염료가 적외선을 거의 다 통과시킨다
- 같은 ROI 를 `Gray` 로 찍은 것과의 상관 **0.44** — IR 경로가 실제로 적외선을 보고 있다는
  근거다(대조군으로 `Gray` 와 `R` 의 상관은 0.96)
- **RGB↔IR 정합 오차 0px** — 두 패스가 별도 스캔인데도 캐리지 위치가 재현된다. 서브픽셀
  정합 단계가 필요 없다.

## 3. 이식할 때의 원칙

한쪽만 고치면 두 플랫폼이 갈린다. macOS 에서 동작을 바꿀 때는 **이 문서에 항목을 먼저
추가하고**, Windows 에 반영한 뒤 1절로 옮긴다.
