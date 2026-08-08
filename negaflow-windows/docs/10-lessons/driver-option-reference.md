# 드라이버 인자 정본 — 우리가 보내는 모든 옵션과 그 근거

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 이식 정본 — 값 하나하나가 실기 또는 upstream 소스로 뒷받침된다
코드 근거: `SANEBackend+Discovery.swift`(`resolveMedia`),
`SANEBackend+ScanExecution.swift`(`makeScanimageArgs`, `validateExactOptions`),
`SANEBackend+Capabilities.swift`

관련 문서:

- [backend-quirks](../02-frontend-contract/backend-quirks.md) — 백엔드별 분기 목록
- [exact-option-contract](../02-frontend-contract/exact-option-contract.md) — 검증 규칙
- [scanimage-invocation](../02-frontend-contract/scanimage-invocation.md) — 호출 형태
- [field-lessons](field-lessons.md) — 이 값들을 얻기까지의 실패 기록
- [host-pipeline-contract](host-pipeline-contract.md) — 왜 이 값이어야 하는가

## 0. 이 문서의 위상

[backend-quirks](../02-frontend-contract/backend-quirks.md)가 "백엔드별로
무엇이 다른가"를 다룬다면, 이 문서는 **옵션 하나하나가 왜 그 값인가**를 다룬다.

두 문서가 겹치는 부분이 있지만 겹침은 의도적이다. 이식 중에 값을 바꾸고
싶어지는 순간은 옵션을 보고 있을 때이지 백엔드를 보고 있을 때가 아니다.

각 항목의 **근거 등급**:

| 등급 | 뜻 |
|---|---|
| **소스** | sane-backends 원본 코드를 직접 읽어 확인 |
| **실측** | 실제 하드웨어에서 관측 |
| **문서** | manpage / 릴리스 노트 |
| **추정** | 코드에 분기는 있으나 근거가 기록되지 않음 |

**추정 등급 항목을 이식 중에 "정리"하지 않는다.** 근거가 기록되지 않았다는
것은 근거가 없다는 뜻이 아니라, 근거를 남기지 않은 채 실기에서 얻었다는
뜻일 가능성이 높다.

## 1. 인자 순서 — 바꾸지 않는다

`makeScanimageArgs`가 만드는 순서다. 배열 비교 픽스처가 순서까지 고정한다.

```text
 1  -d <devname>
 2  -p
 3  [--source <S>]
 4  [--mode <M>]
    ─── 아래는 main 패스에서만 ───
 5  [--advance=no]                     pieusb
 6  [--color-correction <C>]           epson2
 7  [--gamma-correction <G>]           epson2
 8  [--film-type <F> | --type <F> | --negative=<yes|no>]
 9  [--brightness=<n>]
10  [--contrast=<n>]
11  [--scan-exposure-time=<n>]
12  [--clean-image=yes]                도달 불가(§9.4)
13  [--preview=yes]
    ─── 다시 공통 ───
14  [--resolution <N>]
15  [--depth <N>]
16  [--tl-x --tl-y --br-x --br-y]  또는  [-l -t]
17  [-x -y]
18  --format=tiff
```

**IR 패스는 3·4번만 바꾸고 14~17을 본 스캔과 동일하게 유지한다.**
먼지 맵을 RGB에 정렬하려면 픽셀 격자가 같아야 한다. 이건 최적화가 아니라
정확성 요건이다.

**없는 옵션에는 플래그를 보내지 않는다.** `MediaSelection`의 `hasXxxOption`
필드가 전부 존재하는 유일한 이유다. coolscan3에 `--mode`를 넘기면
`scanimage`가 스캔을 시작하기도 전에 죽는다.

## 2. `-d <devname>` — 장치 선택자

값은 `scanimage -f`가 준 장치명 원문에서 `sane-` 접두어를 뺀 것이다.

```text
호스트 id     sane-genesys:libusb:001:002
scanimage -d  genesys:libusb:001:002
```

**주소 없는 선택자**(`-d genesys`)는 `genesys`와 `epson2`에만 쓴다
(`supportsStableBackendSelector`). 이 둘은 백엔드 이름만으로 열어도
첫 장치를 잡는다. 다른 백엔드에서 같은 짓을 하면 열리지 않거나 엉뚱한
장치가 열린다.

**실측(macOS, OpticFilm 8100, sane-backends 1.4.0)**: 장치를 **열 때마다**
libusb 주소가 바뀐다(`002:001 → 002:002 → 002:001`). 목록 조회만으로는
바뀌지 않는다. 죽은 주소로 여는 시도는 하드웨어에 닿기 전에 약 11 ms 만에
실패한다.

→ 다중 패스는 패스마다 주소를 다시 확인한다. 근거: [device-identity](../02-frontend-contract/device-identity.md)

**Windows 미검증**: 이 주소 변동이 Windows USB 스택에서도 일어나는지는
확인되지 않았다(spike U-3).

## 3. `-p` — 진행률

`scanimage`가 진행률을 **stderr**에 낸다. stdout이 아니다.

```text
Progress: 12.3%
```

이 한 글자 플래그가 watchdog·취소·stale 판정의 전체 기반이다. 빼면
"멈춘 스캔"과 "느린 스캔"을 구분할 수단이 사라진다.

`LC_ALL=C`로 고정하는 이유도 여기다. 로케일이 바뀌면 `Progress:`가 번역되고
소수점이 `,`가 된다. 파서는 콤마를 받아들이지만 **환경을 고정하는 쪽이
정본**이다.

## 4. `--format=tiff` — 그리고 stdout의 비대칭

| 실행 | stdout | stderr |
|---|---|---|
| `-L` / `-f` / `-A` | 텍스트 (파이프로 읽음) | 무시 |
| 획득(`-p --format=tiff`) | **이미지 바이트** (파일 핸들로 직접 리다이렉트) | 진행률 (파싱 대상) |

획득에서 stdout을 파이프로 받지 않는다. 파일 핸들로 바로 꽂는다.
수백 MB를 사용자 공간으로 끌어올릴 이유가 없다.

**Windows에서 이 비대칭이 가장 위험한 지점이다.** stdout이 텍스트 모드면
`0x0A` 앞에 `0x0D`가 삽입돼 TIFF가 조용히 깨진다. spike S-2가 이걸 본다.
→ [runtime-route-decision](../01-sane-runtime/runtime-route-decision.md) §5

## 5. `--source` — 투과 유닛 선택

모델명이 아니라 **덤프에 실제로 나온 값**에서 고른다.

| 백엔드 | 관측된 값 |
|---|---|
| genesys | `Transparency Adapter`, `Transparency Adapter Infrared` |
| epson2 | `Flatbed`, `Transparency Unit`, `TPU8x10` |
| coolscan2/3 | 소스 옵션 없음(전용 필름 스캐너) |

선택 규칙(`preferredTransparencySource`) — **3단 폴백**이다:

```text
visibleTransparency = 투과 소스이면서 IR이 아닌 값

① visibleTransparency 중 공백 제거 후 "8x10"을 포함하는 첫 값   (더 큰 투과 영역)
② 없으면 visibleTransparency의 첫 값
③ 그것도 비면 sources 중 투과 소스인 첫 값                      ← IR을 배제하지 않는다
```

그리고 `resolveMedia`는 이것마저 nil이면 `sources.first`로 떨어진다.

**IR 소스를 본 스캔 소스로 고르는 사고가 실제로 가능하다.**
`isInfraredValue`(값에 `infrared` 포함 또는 `ir`과 정확히 일치)가 ①②에서
그걸 막는다. 이식할 때 이 필터를 빠뜨리면 컬러 스캔 자리에 적외선 그레이가
들어온다.

**③이 잠재적 구멍이다.** 투과 소스가 전부 IR인 장치(= IR 소스만 노출하고
일반 투과 소스가 없는 경우)에서는 ③이 IR 소스를 본 스캔에 고른다.
현재 알려진 대상 장치에는 해당하는 것이 없고(genesys "i"는 일반 투과 소스를
함께 노출한다) 그래서 macOS에서 드러난 적이 없다.

```text
이식 시 조치: 동작을 그대로 옮기되, ③에도 IR 배제를 넣을지는
I-20(양 플랫폼 동시 적용) 후보로 올린다. 한쪽만 바꾸지 않는다.
픽스처: "투과 소스가 IR뿐인 합성 덤프"를 media/ 케이스에 추가한다.
```

## 6. `--mode` — 색 모드

| 백엔드 | 상태 |
|---|---|
| genesys | 있음. capability는 **항상 `Color`로 읽는다** |
| epson2 | 있음. 기본이 `Lineart`인 기기가 있다(§8.2 함정) |
| coolscan2/3 | **없음. 보내면 즉시 실패** |
| pieusb | 있음(RGBI 포함) |

capability를 Color로 읽는 이유: 이 앱이 실제로 스캔하는 모드가 Color다.
다른 모드에서 읽은 활성 상태를 Color 스캔에 적용하면 안 된다.

IR 패스에서는 `irPassMode`(Gray 우선)로 바꾼다.

## 7. `--depth` — 비트 심도

```text
depthTokens = intTokens("depth") 중 8 이상          (비활성이면 빈 배열)

요청 8-bit  → depthTokens에 8이 있으면 8, 없으면 nil
요청 16-bit → 16이 있으면 16
              없으면 8 초과 값의 최대            (coolscan3 → 14)
              그것도 없으면 nil

옵션이 없거나 비활성 → fixedDepth로 판정, --depth 미전송
```

**8-bit 요청을 16-bit로 바꾸거나 그 반대를 하지 않는다.** 위 규칙이 nil을
내면 preflight에서 명시적으로 실패한다(I-1).

| 백엔드 | 사실 |
|---|---|
| coolscan3 | `8 | 14`. **14-bit는 16-bit 컨테이너로 전달된다** |
| epson2 | Lineart 모드에서 `--depth`가 **비활성**(실측: GT-X980 = V850) |
| pie | `--depth` 없음 → 8-bit 고정 |

**epson2의 이 성질이 능력 판정의 근본 함정이다.** 모드를 적용하지 않은
덤프만 읽으면 지원 심도가 통째로 빈 상태로 보고된다. 그래서
`capabilityRedumpArguments`가 존재한다 → [capability-model](../02-frontend-contract/capability-model.md) §2.

`fixedDepth`가 있으면 `--depth`를 보내지 않고, **요청 심도가 다르면
스캔 전에 실패시킨다.** 8-bit 기기에 16-bit를 요청했는데 조용히 8-bit를
주는 일은 없다.

## 8. epson2 — 내부 처리를 끄는 두 옵션

### 8.1 `--color-correction None`

```text
constraintEnumValues("color-correction")에서
트림 후 "None"과 대소문자 무시 일치하는 첫 값
```

선택 모드에 `color`가 들어갈 때만 적용한다.

negaflow가 원본 밀도를 현상한다. 장치가 색을 미리 만지면 그 현상 파이프라인
전체의 전제가 깨진다. 끄지 못하면 **2단계에서 스캔을 거부한다.**

### 8.2 `--gamma-correction` — 가장 비싸게 배운 옵션

```text
epsonRawGammaCorrection:
    ① 소문자·공백 제거 후 "gamma=1.0"을 포함하는 첫 값
    ② 없으면 트림 후 "User defined"와 일치하는 첫 값
```

**근거 등급: 소스** (sane-backends `epson2.c` / `epson2-ops.c`,
2026-07-29 원본 확인)

세 가지 사실이 이 선택을 강제한다.

**① 감마를 안 건드리는 것은 중립이 아니다.**

A/B 레벨 기기에서 `Default`(index 0)는 그레이/컬러 모드에서
`val += mparam->depth == 1 ? 0 : 1` 때문에 `0x01`이 아니라 **`0x02`(표시용
감마)** 를 보낸다. 즉 "기본값으로 두면 선형이겠지"가 **틀렸다.**

**② `User defined`가 진짜 선형이다.**

초기화 때 항등 램프(`gamma_table[i] = i`)로 채워진 테이블을 ESC z로 올린다.
D 레벨 기기는 기본값이 `User defined (Gamma=1.8)`이라 플러그인이
`Gamma=1.0`으로 덮어써야 한다. 규칙 ①이 D 레벨을, 규칙 ②가 A/B 레벨을 잡는다.

**③ 비활성일 때 보내면 스캔이 실패한다.**

`OPT_GAMMA_CORRECTION`이 `SANE_CAP_INACTIVE`가 되는 조건은 **초기화 시
`!s->hw->cmd->set_gamma` 하나뿐**이다. 모드나 소스로 토글되지 않는다
(토글되는 건 `OPT_GAMMA_VECTOR_R/G/B`다). 비활성이면 감마 명령이 아예
전송되지 않으며, 그 상태에서 `--gamma-correction`을 보내면
`"attempted to set inactive option"`으로 **스캔 전체가 실패한다.**

### 8.3 활성/비활성 처리의 의도된 비대칭

| 위치 | 활성 검사 | 이유 |
|---|---|---|
| `resolveMedia` | `isActive` 확인 **함** | 실제 전송하므로 |
| `capabilityRedumpArguments` | 확인 **안 함**(`constraintEnumValues`) | 앞선 옵션 적용으로 활성화될 옵션을 같은 호출 뒤쪽에 배치 |
| `validateExactOptions` | 활성인데 값 못 정하면 **거부** | I-1 |

**이 비대칭은 버그가 아니다.** 이식 중에 "일관성 있게" 정리하지 말 것.

### 8.4 리버트 이력 — 되돌리지 말 것

```text
82b7b32  fix: set the Epson linear gamma even when the option reports inactive
7f950dc  Revert "fix: set the Epson linear gamma even when the option reports inactive"
```

2026-07-29에 "비활성이어도 감마를 보내면 되지 않나"를 시도했다가 **철회**했다.
§8.2 ③이 이유다. 비활성은 "설정할 수 있는데 지금은 꺼져 있다"가 아니라
**"이 하드웨어에 감마 명령 자체가 없다"** 는 뜻이다.

**되돌리려면 실기 증거가 필요하다.** 실기 없이 이 로직을 "개선"하지 않는다.

## 9. 필름 극성 — 세 가지 다른 옵션, 하나의 의미

장치가 실제 노출한 이름을 그대로 쓴다.

| 옵션 | 백엔드 | 형태 |
|---|---|---|
| `--film-type` | epson2 | enum (`Positive Film` / `Negative Film`) |
| `--type` | coolscan (구형 SCSI) | enum |
| `--negative` | coolscan2 / coolscan3 | bool |

### 9.1 `--negative`는 필름 메타데이터가 아니다

**coolscan2/3의 `--negative`는 스캐너 자체의 색 반전 스위치다.**
요청 filmType과 **무관하게 항상 `no`** 를 보낸다.

negaflow가 원본 네거티브 밀도를 반전한다. 스캐너가 먼저 반전하면 두 번
반전된다.

### 9.2 `preserveRawCoolscan`

구형 `coolscan` + `--type` 조합에서는 **극성 변환을 하지 않고** 항상
positive 계열 값을 고른다. 같은 이유다 — 장치가 손대지 않은 밀도를 원한다.

### 9.3 IR 획득 전략 — 3종, 전부 덤프에서 감지

**모델명으로 분기하지 않는다.**

| 전략 | 조건 | 동작 |
|---|---|---|
| `.separateSource(S)` | 소스 목록에 IR 값 | 두 번째 패스에서 `--source S`, `--mode Gray` |
| `.separateMode(M)` | 모드 목록에 infrared | 두 번째 패스에서 `--mode M` |
| `.cleanImage(opt)` | — | **도달 불가**(§9.4) |
| `.none` | 그 외 | IR 없음 |

`.separateMode`는 **epson2 커스텀 빌드에서만** 성립한다. stock epson2는
`SANE_FRAME_IR` 경로가 `#if 0`으로 막혀 있어 Infrared 모드를 노출하지 않는다.

**coolscan3의 `--infrared`는 IR 능력으로 보고하지 않는다.**
`SANE_FRAME_RGBI` **한 프레임**이며 stock `scanimage` 1.4가 이를 RGB TIFF와
IR TIFF 두 개로 분리하지 못한다. `disabledReasons["infrared"]`에 그 이유를
적는다.

**이건 OS 한계가 아니라 `scanimage` 한계다. Windows에서도 같다.**
해결하려면 `scanimage`를 고치거나 SANE API를 직접 써야 하고, 후자는
GPL 경계 설계를 근본적으로 바꾼다(D-17).

**실측(macOS)**: 이 맥의 genesys 빌드는 OpticFilm(8100으로 보고되는 8200i)에서
IR을 노출하지 않는다(`source = Transparency Adapter`만). epson2/epkowa도
미노출. 즉 **현재 이 개발 환경에서 IR 경로는 실기 검증이 되지 않았다.**

### 9.4 `.cleanImage`는 죽은 코드다 — 살리지 말 것

`IRStrategy.cleanImage`가 정의돼 있고 `makeScanimageArgs`와 `startFullScan`에
분기가 있지만, **`resolveMedia`가 이 값을 만들지 않는다.**

이유: pieusb의 `--clean-image=yes`는 백엔드가 IR로 먼지를 제거한 RGB를
반환하는 단일 패스 기능이다. **별도 IR 파일이 없다.** 호스트의 IR 능력은
"별도 IR 채널 파일"을 뜻하므로 계약이 맞지 않는다.

**이식 시 이 도달 불가 상태를 그대로 유지한다.** "구현이 있으니 연결하자"가
정확히 틀린 판단이다.

## 10. `--brightness` / `--contrast` — 대부분 함정

```text
supportsHardwareToneAdjustments = !(backend == "genesys" && bitDepth == .sixteen)
거짓이면 hasBrightnessOption / hasContrastOption / brightnessRange / contrastRange
를 모두 없는 것으로 취급
```

**근거 등급: 추정.** 코드에 이유가 적혀 있지 않다. 이식 시 upstream
`backend/genesys/`에서 근거를 찾아 주석으로 남기고, 못 찾으면 "실기 관측 기반,
근거 미문서화"로 명시한다. **근거 없이 제거하지 않는다.**

### 10.1 genesys에서는 애초에 기대할 것이 없다

**근거 등급: 문서**

- `--brightness` / `--contrast`는 **sane-backends 1.0.32에서 제거됐다.**
  릴리스 노트 genesys 항목: *"Removes lineart and image enhancement emulation
  support"* — 이 둘의 소프트웨어 구현이 그것이다.
- 그 이전 1.0.29대에도 `scanimage`가 무시하는 확인된 버그가 있었다.
- 애초에 **하드웨어 노출이 아니라 소프트웨어 후처리**였다. 걸렸더라도
  16-bit raw에서는 본체 노출 슬라이더와 같은 곱셈일 뿐이라 이득이 0이다.

### 10.2 능력 응답과 검증이 어긋나는 유일한 지점

`parseCapabilities`는 genesys 16-bit 예외를 **적용하지 않는다.** 그 예외는
`resolveMedia`에만 있다. 결과적으로 genesys 장치의 능력 응답에는 brightness
범위가 나타나지만, 16-bit 스캔에서 그 값을 보내면 2단계에서 거부된다.

이 불일치의 처리는 open question Q-7이 소유한다.

## 11. `--scan-exposure-time` — 막다른 길

```text
hasScanExposureOption: opts.isActive("scan-exposure-time")
hardwareExposureTimes = [11000, 14000, 30000]
NEGAFLOW_HWEXP_SAMPLES = 노출당 샘플 수 (1…4, 기본 1)
```

옵션이 있는 기기에서는 정상 동작한다. 문제는 **대상 기기 대부분에 없다**는 것이다.

**genesys에서는 원리상 불가능하다. 재시도 금지.** (2026-07-27 확정)

| 근거 | 내용 |
|---|---|
| 문서 | `sane-genesys` manpage에 사용자용 exposure/gain 옵션이 **없다**. 노출은 캘리브레이션 중 내부 처리(LED exposure calibration)라 외부 훅이 없다 |
| 설계 | 따라서 `hasScanExposureOption`이 false로 떨어지는 것이 **정상 동작**이다. 버그가 아니다 |
| 문서 | 멀티 노출은 하드웨어가 노출 시간을 바꿀 수 있어야 성립한다. genesys는 그 제어를 노출하지 않으므로 같은 노출로 두 번 찍는 것 = 멀티샘플링이며, 이는 DR을 늘리지 못한다 |

**실측이 문헌과 일치했다** (2026-07-26, E100D 슬라이드 6컷, ICC 없는 16-bit
무압축 linear TIFF):

```text
6% 인셋 휘도 p50   0.066 ~ 0.074
전 프레임 max      0.16 ~ 0.62
18% 미드까지 필요   +1.27 ~ 1.45 스탑
캘리브레이션 화이트까지 남은 헤드룸   최대 ~0.7 스탑
```

노출 제어가 열려 있었더라도 **필요량의 절반만 얻고 밝은 컷은 클리핑됐다.**
구현 실패가 아니라 얻을 것이 없었던 것이다.

→ 자세한 경위와 결론: [field-lessons](field-lessons.md) §2

## 12. `--advance=no` — pieusb 전용, 안전 문제

```text
backend == "pieusb" && media.hasAdvanceOption → args += ["--advance=no"]
```

`pieusb`는 full scan 뒤 다음 슬라이드로 이동하는 `--advance`의 기본값이
`yes`다. 앱이 배치 이동을 요청한 적이 없으므로 옵션이 확인되면 **항상 `no`**.

**옵션이 활성이 아니면 스캔을 거부한다.** 자동 이동을 끌 수 없는 상태로
스캔하면 사용자의 필름 배치가 예상 없이 움직인다. 이건 성능이 아니라
물리적 부작용 문제다.

같은 이유로 pieusb는 **재시도 금지**(`attemptCount = 1`)다. 재시도가
다른 프레임을 덮어쓴다.

## 13. `--preview=yes`

`options.resolution == .preview`이고 옵션이 있을 때만. preview 요청은
계약상 dpi=0, IR 금지, 다중노출 금지, 노출시간 금지, rawTIFF 금지다.

## 14. 지오메트리 — mm와 pel은 섞이지 않는다

```text
usesCornerPixelGeometry → --tl-x --tl-y --br-x --br-y   (정수 pel)
mm 단위 장치            → -l -t  그리고  -x -y          (mm)
pel 단위 장치           → -l -t  그리고  -x -y          (정수 pel)
```

**coolscan 계열의 `-x`/`-y`는 pel 단위다.** mm 값을 넘기면 N픽셀 폭으로
오해된다. 36 mm를 요청했는데 36픽셀이 나온다.

pel 변환은 `mm * dpi / 25.4`이며 반올림 후 범위의 `containsExactly`를
만족해야 한다. 만족하지 못하면 **거부한다.** 가까운 값으로 스냅하지 않는다(I-1).

pel 단위 장치에서 `-x`/`-y`를 아예 생략하면 장치 기본값 = 전체 영역이다.

### 14.1 epson2 정수 mm 절삭 — 조용히 필름이 잘린다

**근거 등급: 소스** (`epson2-ops.c`의 `e2_init_parameters`)

```c
((int) SANE_UNFIX(s->val[OPT_BR_Y].w) / MM_PER_INCH * dpi + 0.5) - s->top
```

`(int)` 캐스트가 나눗셈보다 **먼저** 걸린다(1.4.0과 master 모두 동일).
`br_y`가 소수 mm면 결과 이미지의 **세로만** 최대 1 mm어치 짧아진다.
요청한 종횡비와 어긋나고 필름 컷이 조용히 잘린다.

보정(`epson2AlignedHeightMM`):

```text
bottom = originY + height
bottom이 이미 정수(1e-9 이내)      → 그대로

grownBottom = ceil(bottom)
grown = grownBottom - originY
range.containsExactly(grown) 이고 grownBottom <= surfaceBottom + 1e-9
                                   → grown 채택 (최대 1 mm 넓어질 뿐, 잘리지 않는다)

shrunk = floor(bottom) - originY
shrunk > 0 이고 range.containsExactly(shrunk)
                                   → shrunk 채택

둘 다 불가능             → 요청값 그대로
```

`heightAlignmentMM = 채택값 - 요청 높이`. 2단계 검증이 `abs(...) < 1`을
요구하고, `appliedOptions.scanArea.heightMM`에 **채택값**이 실린다.

**이 tolerance는 높이에만 있다. 폭·원점에는 없다.**

**넓히는 쪽을 먼저 시도하는 것이 핵심이다.** 좁히면 필름이 잘리고, 넓히면
여백이 조금 더 들어올 뿐이다. 실패 방향을 고르는 문제이지 정확도 문제가 아니다.

`Formula/sane-backends-negaflow.rb`가 백엔드 자체도 고치지만, stock SANE
사용자를 위해 플러그인 보정을 함께 유지한다. **Windows에서 stock 빌드를
쓴다면 플러그인 보정이 유일한 방어선이다.**

## 15. 수 형식 — `saneNumber`

```swift
if value.rounded() == value { return String(Int(value)) }
return String(value)
```

`36.0` → `"36"`, `36.33` → `"36.33"`.

**로케일 독립이어야 한다.** `LC_ALL=C`가 `scanimage` 쪽을 고정하지만
**생성 쪽도 고정해야 한다.** 한국어 Windows에서 `,`가 나오는 순간
`scanimage`가 파싱에 실패한다.

지수 표기가 나오면 안 된다 → 고정 소수점으로.

## 16. 우리가 **보내지 않는** 것

명시적으로 기록한다. "왜 이 옵션을 안 쓰지?"가 이식 중에 반드시 나온다.

| 옵션 | 왜 안 보내는가 |
|---|---|
| `--gamma-table` / `--gamma-vector-*` | 항등 램프를 직접 올릴 이유가 없다. `User defined`가 이미 항등이다 |
| `--resolution` 이외의 해상도 별칭 | 하나로 충분 |
| `--batch-*` | 배치 스캔을 하지 않는다. pieusb `--advance` 참조 |
| `--jpeg-quality`, `--compression` | 무손실 raw TIFF만 낸다 |
| `--buffer-size` | 기본값으로 충분. 튜닝 근거 없음 |
| `--infrared` (coolscan3) | §9.3 — 분리 불가한 RGBI 프레임 |
| `--calibrate`, `--focus` 등 버튼형 옵션 | `-A`가 출력하지만 설정 대상이 아니다 |

## 17. 실패 문구 — 무엇으로 판정하는가

`LC_ALL=C`가 이것들을 영어로 고정한다는 전제 위에 있다.

| 문구 | 의미 | 우리 대응 |
|---|---|---|
| `attempted to set inactive option` | 비활성 옵션 설정 | 옵션 활성 판정 오류. 코드 결함 |
| `rounded value of ... to ...` | 값이 스냅됐다 | **I-1 위반. 결과를 버린다** |
| `Device busy` | 점유 | 재시도 또는 안내 |
| `Invalid argument` | 대개 지오메트리 범위 밖 | 검증 로직 결함 |
| `no SANE devices found` | 목록 비었음 | 드라이버/권한 |

**`rounded value of`를 무시하면 안 된다.** 이 한 줄이 "요청한 해상도로
스캔했다"와 "비슷한 해상도로 스캔했다"를 가른다.

**Windows 미검증**: `LC_ALL=C`가 MinGW `scanimage`의 메시지를 실제로
영어로 고정하는지는 확인되지 않았다(spike S-6 / E-3). **실패하면 반올림
감지, busy 분류, stale 판정이 전부 무력화된다.** 대체 감지 경로가 필요하다.

## 18. 이식 체크리스트

- [ ] 인자 순서 18단계가 그대로다 (배열 비교 픽스처)
- [ ] `hasXxxOption`이 false면 플래그를 만들지 않는다
- [ ] IR 패스가 소스/모드만 바꾸고 지오메트리·해상도·심도를 유지한다
- [ ] IR 값이 본 스캔 소스 후보에서 제외된다
- [ ] epson2 감마 2단 규칙(`gamma=1.0` → `User defined`)이 순서대로다
- [ ] epson2 활성 검사 비대칭 3종이 그대로다
- [ ] `--negative=no` 무조건 전송
- [ ] `preserveRawCoolscan`이 극성 변환을 건너뛴다
- [ ] `.cleanImage`가 여전히 도달 불가다
- [ ] genesys 16-bit 톤 억제가 있고, 근거 조사 결과가 기록됐다
- [ ] `epson2AlignedHeightMM` 4갈래 전부 픽스처
- [ ] 넓히기를 좁히기보다 먼저 시도한다
- [ ] `saneNumber`가 로케일 독립이고 지수 표기를 내지 않는다
- [ ] `rounded value of` 감지가 살아 있다
- [ ] §16의 "안 보내는 옵션"이 여전히 안 나간다
