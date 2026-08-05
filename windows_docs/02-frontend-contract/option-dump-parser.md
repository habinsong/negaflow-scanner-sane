# 옵션 덤프 파서 이식 명세

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 이식 정본
코드 근거: `Sources/SANEPluginCore/SaneOptionDump.swift`,
`SANEBackend+Discovery.swift`(`resolveMedia`), `Tests/SANEPluginCoreTests/SANEBackendTests.swift`

관련 문서:

- [scanimage-invocation](scanimage-invocation.md)
- [exact-option-contract](exact-option-contract.md)
- [capability-model](capability-model.md)
- [backend-quirks](backend-quirks.md)

## 1. 무엇을 파싱하는가

`scanimage -A -d <dev> [옵션…]`의 출력이다. 형식은 사람이 읽으라고 만든 것이며
공식 기계 판독 형식이 아니다. 대표 예:

```text
Options specific to device `genesys:libusb:001:002':
  Scan Mode:
    --mode Color|Gray [Color]
        Selects the scan mode (e.g., lineart, monochrome, or color).
    --source Transparency Adapter|Transparency Adapter Infrared [Transparency Adapter]
        Selects the scan source (such as a document-feeder).
    --resolution 7200|3600|2400|1200|600dpi [600]
        Sets the resolution of the scanned image.
    --depth 8|16 [16]
        Number of bits per sample, typical values are 1 for "line-art" and 8
  Geometry:
    -l 0..36.33mm [0]
    -t 0..44.25mm [0]
    -x 0..36.33mm [36.33]
    -y 0..44.25mm [44.25]
  Enhancement:
    --brightness -100..100 (in steps of 1) [0]
    --contrast -100..100 (in steps of 1) [inactive]
    --scan-exposure-time 0..65535 [11000]
```

이 텍스트가 유일한 능력 정보원이다. **모델명 테이블은 존재하지 않는다.**

## 2. `SaneOptionDump` 자료구조

```text
values:              [옵션명 → 토큰 뒤 원문 전체]
optionNames:         Set<옵션명>
inactiveOptionNames: Set<옵션명>
isEmpty:             values.isEmpty
```

### 2.1 줄 파싱 알고리즘

각 줄에 대해:

1. 양끝 공백 제거.
2. `-`로 시작하지 않으면 버린다. → 섹션 제목, 설명문, 헤더가 모두 걸러진다.
3. 첫 공백 전까지를 토큰으로 삼는다.
4. 토큰 앞의 `-`를 전부 제거해 이름을 만든다(`--mode` → `mode`, `-x` → `x`).
5. 이름에 `[`가 있으면 그 앞까지만 남긴다. → `--preview[=(yes|no)]` → `preview`.
6. 이름이 비면 버린다.
7. 나머지(토큰 이후, 공백 제거)를 값으로 저장한다. **먼저 나온 항목이 이긴다**
   (`if parsed[name] == nil`).
8. 값의 소문자에 `[inactive]`가 있으면 비활성 집합에 넣는다.

### 2.2 Windows 이식 시 주의

| 항목 | 요건 |
|---|---|
| 줄 분리 | **§2.2.1을 읽을 것.** Swift 구현은 CRLF 덤프를 파싱하지 못한다. C++ 는 바이트 단위로 나누고 trim 집합에 `\r`를 포함시킨다 |
| 공백 정의 | Swift `.whitespaces`는 유니코드 공백을 포함한다. `LC_ALL=C` 전제라면 ASCII 공백/탭만으로 충분하지만, 관대하게 두는 편이 안전하다 |
| 대소문자 | 옵션 이름은 원문 그대로 키로 쓴다. SANE 옵션명은 소문자 관례이나 정규화하지 않는다 |
| 인코딩 | UTF-8로 디코드. 실패 시 덤프 전체를 오류로 처리한다(현재 macOS는 `String(data:encoding:.utf8) ?? ""`로 조용히 빈 문자열이 된다 — Windows에서는 이를 명시적 `ioFailure`로 승격할 것을 권장) |

### 2.2.1 CRLF — Swift 구현이 아예 파싱하지 못한다 (2026-08-04 실측)

**이 절의 이전 서술은 원인과 심각도를 둘 다 틀렸다.** "`\r`가 trim 되지
않는다"가 아니다. 실제로는 **줄 분리 자체가 일어나지 않는다.**

Swift에서 `"\r\n"`은 **한 Character**다(확장 자소 클러스터). 따라서
`dump.split(separator: "\n")`이 CRLF 경계를 인식하지 못한다.

```swift
"a\r\nb\n".count                      // 4  ← "a", "\r\n", "b", "\n"
"a\r\nb\n".split(separator: "\n")     // ["a\r\nb"]   한 조각
"\r\n".count == 1                     // true
```

결과: **덤프 전체가 옵션 하나로 뭉개진다.** 첫 옵션만 이름으로 잡히고,
그 뒤 모든 옵션이 첫 옵션의 "값" 안으로 빨려 들어가 사라진다.

실측:

```text
입력   "    --mode Color|Gray [Color]\r\n    --depth 8|16 [16]\r\n"

Swift  optionNames        == ["mode"]     ← depth 가 없다
       intTokens("depth") == []
C++    optionNames        == ["mode", "depth"]
       intTokens("depth") == [8, 16]
```

**왜 지금까지 드러나지 않았나**: macOS `scanimage`는 LF만 낸다. 이 경로가
한 번도 실행된 적이 없다.

**Windows에서는 실행될 수 있다.** MinGW 빌드가 stdout을 텍스트 모드로 열면
`\n`이 `\r\n`으로 바뀐다 — 그것이 spike S-2가 이미지에 대해 확인하는
바로 그 현상이고, 텍스트 출력에도 똑같이 적용된다.

```text
결정: Windows 구현은 Swift 동작을 재현하지 않는다.
      바이트 단위로 '\n' 을 나누고, trim 집합에 '\r' 을 포함시킨다.
      즉 CRLF 덤프를 정상 파싱한다.

이유: 이 divergence 는 "다른 결과"가 아니라 "Swift 가 틀린 것"이다.
      LF 입력에서는 두 구현이 완전히 일치한다(파리티 검사 20/21).
```

**macOS도 고쳐야 한다.** I-20 후보이며, 고치면 divergence가 사라진다.
수정은 한 줄이다 — `split(separator: "\n")` 대신 `\r\n`도 함께 다루거나,
`unicodeScalars` 기준으로 나눈다.

#### CRLF 는 이제 가능성이 아니라 측정된 사실이다 (2026-08-05)

이 절은 "MinGW `scanimage`가 CRLF를 **낼 수 있다**"는 전제 위에 서 있었다.
그 전제를 실측했다. MSYS2 `mingw-w64-ucrt-x86_64-sane` 1.4.0 으로 확인:

```text
scanimage.exe -L        stdout 5줄 전부  \r\n
scanimage.exe --help    출력 38줄 전부   \r\n
```

원인은 CRT다. MinGW/UCRT의 기본 파일 모드가 텍스트라 `printf`의 `\n`이
`\r\n`으로 나간다. **`-A` 덤프도 같은 stdout으로 나오므로 CRLF다.**

즉 Swift 구현을 그대로 베꼈다면 **Windows에서 옵션 덤프가 통째로 한 줄로
뭉개져 능력 판정이 전부 무너졌을 것이다.** §2.2.1의 결정이 옳았다.

같은 텍스트 모드가 이미지 바이트도 망가뜨린다 — 그쪽은 별개의 차단 항목이다.
→ [runtime-route-decision](../01-sane-runtime/runtime-route-decision.md) §5

파리티 검사가 이 divergence를 **알려진 예외로 허용**하고 나머지는
전부 일치를 요구한다: `windows/tools/parity-check.sh`.

### 2.3 `[inactive]` 판정의 함정

`scanimage`는 비활성 옵션도 제약 목록을 그대로 출력한다:

```text
--depth 8 [inactive]
```

따라서 "값을 읽을 수 있다"와 "그 값을 보낼 수 있다"는 다르다. 이 구분이 API로
분리돼 있다.

| API | 활성 필요 | 용도 |
|---|:---:|---|
| `hasOption(name)` | 아니오 | 옵션 존재 여부만 |
| `isActive(name)` | — | 존재 + 비활성 아님 |
| `enumValues(name)` | 예 | 실제로 보낼 값 후보 |
| `constraintEnumValues(name)` | 아니오 | 뒤에 활성화될 옵션의 값을 미리 읽을 때만 |
| `intTokens(name)` | 예 | 실제로 보낼 정수 |
| `constraintIntTokens(name)` | 아니오 | 고정 심도 식별 전용. **장치에 보내면 안 된다** |
| `numericRange(name)` | 예 | 범위 검사 |
| `rangeUnit(name)` | 예 | mm/pel 판정 |
| `selectedEnumValue(name)` | 예 | 현재 선택값 |
| `resolutionSpec` | 예 | 목록/범위 |

Windows 구현은 이 열 개 함수의 활성 요건을 **그대로** 옮겨야 한다. 하나라도
바꾸면 고정 심도 장치나 epson2 재덤프 경로가 조용히 달라진다.

## 3. 값 파싱 규칙

### 3.1 열거값

```text
"A|B|C [default]" → ["A", "B", "C"]
```

- `[` 이전까지만 자른다.
- `|`로 분리하고 각 항목의 양끝 공백을 제거한다.
- 빈 항목은 버린다.
- **원문 대소문자와 공백을 보존한다.** `Transparency Adapter Infrared`를
  그대로 `--source`에 되돌려 보내야 하기 때문이다.

### 3.2 선택값

```text
selectedEnumValue(name):
    enumValues(name) 중에서 원문에 "[<후보>]"가 (대소문자·발음구별 무시) 있는 첫 값
```

`[inactive]`는 열거값이 아니므로 자연히 제외된다.

### 3.3 정수 토큰

```text
"8|14 [8]" → [8, 14]
```

- `[` 이전까지 자른다.
- `|`와 공백으로 분리한다.
- 각 토큰에서 숫자가 아닌 문자를 양끝에서 제거한 뒤 정수 변환한다.
  → `600dpi` → `600`.

### 3.4 수치 범위

```text
정규식: (-?\d+(?:\.\d+)?)\.\.(-?\d+(?:\.\d+)?)
step:   steps? of (-?\d+(?:\.\d+)?)
```

첫 매치만 쓴다. step이 없으면 nil.

### 3.5 단위

```text
정규식: -?\d+(?:\.\d+)?\.\.-?\d+(?:\.\d+)?\s*(mm|pel)
```

`mm` 또는 `pel`만 인식한다. 그 외(예: `bit`, `dpi`, `us`)는 nil이며,
지오메트리 판정에서 자동으로 배제된다.

### 3.6 해상도 사양

```text
값에 ".."가 있으면 → .range(min: Int(하한), max: Int(상한))
없으면              → "[" 이전을 "|"와 공백으로 분리, "dpi" 문자열 제거 후 정수 → .list(정렬)
어느 쪽도 아니면    → .none
```

`.range`의 `Int()` 변환은 절삭이다. `50.5..6400.0`이 있으면 `50..6400`이 된다.
현재 코드가 그렇게 동작하므로 Windows도 같아야 한다.

### 3.7 `containsExactly` — 가장 중요한 한 함수

```text
containsExactly(value):
    value가 유한하고 minimum <= value <= maximum
    step이 없거나 <= 0 이면 → true
    offset = (value - minimum) / step
    abs(offset - round(offset)) <= 1e-7
```

이 함수가 "정확히 적용 가능한가"의 전부다. Windows 구현에서 반드시 지킬 것:

- **`double`(binary64)로 계산한다.** `float`이나 `decimal`로 바꾸면 1e-7
  허용치의 의미가 달라진다.
- `round`는 half-away-from-zero(Swift `rounded()`)다. C의 `round()`와 같고
  C#의 `Math.Round(x)`(banker's rounding, half-to-even)와는 **다르다**.
  C#이면 `Math.Round(x, MidpointRounding.AwayFromZero)`를 쓴다.
- 나눗셈 순서를 바꾸지 않는다. `(value - minimum) / step`이지
  `value / step - minimum / step`이 아니다.
- 파싱은 로케일 독립이어야 한다. `36.33`을 `36`으로 읽는 로케일이 있으면
  전체 지오메트리 계약이 무너진다. `strtod`의 `"C"` 로케일 또는
  `std::from_chars` / `double.Parse(s, CultureInfo.InvariantCulture)`를 쓴다.

conformance 픽스처에 다음이 있어야 한다.

| 입력 | 기대 |
|---|---|
| `0..36.33mm [36.33]`, value=36.33 | true |
| `-100..100 (in steps of 1) [0]`, value=0.5 | false |
| `-100..100 (in steps of 1) [0]`, value=-100 | true |
| `0..65535 [11000]`, value=11000 | true (step 없음) |
| `1..100 (in steps of 3)`, value=4 | true |
| `1..100 (in steps of 3)`, value=5 | false |
| step 0 | true (step 무시) |
| value = NaN/Inf | false |

## 4. 장치 목록 파싱

### 4.1 우선 경로 — `--formatted-device-list`

```text
scanimage -f "%d\t%v\t%m\t%t%n"
```

출력 한 줄당 탭 4필드. 파싱:

- `\n`으로 분리, 빈 줄 제거.
- 탭으로 최대 4조각(`maxSplits: 3`, 빈 항목 유지).
- 정확히 4필드가 아니거나 첫 필드가 비면 버린다.
- 1·2·3필드는 양끝 공백 제거.

이 경로를 쓰는 이유는 **번역된 문장을 파싱하지 않기 위해서**다.

### 4.2 후퇴 경로 — `-L`

```text
device `coolscan3:usb:libusb:001:002' is a Nikon LS-50 ED film scanner
```

정규식: ``device `([^']+)' is a (.+)$``

캡처 2에서 장치 타입 접미사를 뗀다. 후보(긴 것부터):

```text
multi-function peripheral, flatbed scanner, film scanner, slide scanner,
sheetfed scanner, sheet-fed scanner, handheld scanner, hand-held scanner,
frame grabber, virtual device, video camera, still camera, scanner
```

접미사 제거 후 첫 토큰이 vendor, 나머지가 model이다. 토큰이 하나뿐이면
vendor와 model이 같다.

**후퇴 조건**: `-f`가 예외를 던졌고 그 예외가 `cancelled`/`timeout`이 **아닐**
때만. 취소·타임아웃은 프로세스를 다시 띄우지 않고 즉시 전파한다.
`-f`가 성공했지만 빈 목록이면 `-L`을 시도한다.

### 4.3 Windows 주의

- `-f` 인자의 `%n`은 `scanimage`가 개행으로 치환한다. 셸이 아니라
  `CreateProcessW` argv로 직접 전달되므로 셸 이스케이프 문제는 없다.
  단 인자 문자열에 실제 탭 문자가 들어간다는 점에서 **명령줄 조립 시
  따옴표 처리**를 정확히 해야 한다([child-process](../03-process-and-io/child-process.md) §4).
- `-L` 경로는 번역에 취약하다. Windows 빌드에서 `-f` 지원 여부는
  [availability](../01-sane-runtime/availability.md)의 spike 항목이다.
  `-f`가 없으면 `-L` 파싱의 로케일 고정이 필수 요건으로 승격된다.

## 5. `resolveMedia` — 덤프 → `MediaSelection`

순수 함수다. 입력은 (덤프 문자열, 요청, 장치 타입 힌트). 부작용이 없으므로
Windows 이식에서 **가장 먼저 옮기고 가장 먼저 fixture로 고정할 부분**이다.

### 5.1 판정 순서

```text
1. backend = deviceID에서 "sane-" 제거 후 첫 ":" 앞
2. dedicatedFilmDevice = !isActive("source") && (deviceType에 film|slide 포함
                                                 || backend ∈ {coolscan, coolscan2,
                                                    coolscan3, pie, pieusb})
3. 덤프가 비면 모든 필드 nil로 즉시 반환 (production은 이 상태를 오류 처리)
4. source: 투과 우선(preferredTransparencySource), 없으면 첫 소스, 소스 목록이
   비면 nil
5. mode: 요청 색 모드에 맞는 원문 값. 없으면 nil
6. colorCorrection / gammaCorrection: epson2이고 해당 옵션이 활성일 때만
7. depthArgument:
       8-bit 요청  → depth 토큰(>=8)에 8이 있으면 8, 없으면 nil
       16-bit 요청 → 16이 있으면 16, 없으면 8 초과 값의 최대
   fixedDepth = fixedDepth(opts, backendHint:)
8. resolvedDPI: 요청 dpi <= 0이면 nil.
       .list  → 정확히 포함되면 그 값
       .range → containsExactly면 그 값
       .none  → nil
9. 지오메트리 (아래 5.2)
10. filmType (아래 5.3)
11. IR 전략 (아래 5.4)
12. supportsHardwareToneAdjustments = !(backend == "genesys" && 16-bit)
    → 거짓이면 brightness/contrast 옵션과 범위를 통째로 없는 것으로 취급
```

### 5.2 지오메트리 네 갈래

**(a) mm 단위** — `rangeUnit("x") == "mm" && rangeUnit("y") == "mm"`이고 두
범위의 최대가 0 초과일 때:

```text
x/y 범위가 요청 폭/높이를 containsExactly 하면 widthMM/heightMM 설정
l 범위가 mm이고 요청 원점X를 containsExactly 하면 originXMM 설정
t 범위가 mm이고 요청 원점Y를 containsExactly 하면 originYMM 설정
backend == "epson2" 이고 heightMM이 정해졌으면 epson2AlignedHeightMM 적용
    heightAlignmentMM = 정렬값 - 요청 높이
```

**(b) 폭·높이 pel** — 요청 dpi > 0이고 x/y 단위가 `pel`일 때:

```text
widthPixels  = pixelGeometryValue(요청 폭, dpi, x범위)
heightPixels = pixelGeometryValue(요청 높이, dpi, y범위)
l/t 단위가 pel이면 originXPixels/originYPixels도 같은 방식
```

**(c) 모서리 pel** — `tl-x`/`tl-y`/`br-x`/`br-y`가 모두 `pel`이고 해상도
최대값을 단위 dpi로 삼아 좌·상·폭·높이가 전부 계산되며 우·하 좌표가
`containsExactly`를 만족할 때:

```text
originXPixels = left
originYPixels = top
rightPixels   = left + width  - 1
bottomPixels  = top  + height - 1
usesCornerPixelGeometry = true
```

**(d) 아무것도 아님** — 전부 nil. 2단계 검증이 거부한다.

보조 함수:

```text
pixelGeometryValue(mm, dpi, range):
    mm 유한, mm >= 0, dpi > 0 필수
    exact = mm * dpi / 25.4
    rounded = round(exact)
    abs(exact - rounded) <= 0.5 + 1e-9 필수   ← 항상 참. 방어적 검사
    range.containsExactly(rounded)이면 Int(rounded), 아니면 nil

pixelGeometryLength(mm, unitDPI):
    mm 유한, mm > 0, unitDPI > 0 필수
    rounded = round(mm * unitDPI / 25.4)
    rounded >= 1 이어야 함
```

`25.4`는 인치당 밀리미터다. Windows 구현에서 이 상수와 연산 순서를
바꾸지 않는다. `mm * dpi / 25.4`이지 `mm / 25.4 * dpi`가 아니다 —
부동소수점 결과가 달라질 수 있다.

### 5.3 필름 타입 선택

옵션 이름 우선순위: `film-type` → `type` → `negative` (활성인 첫 번째).

```text
옵션이 있고, source가 없거나 투과 소스일 때만 값을 정한다.

backend ∈ {coolscan2, coolscan3} 이고 옵션명이 "negative":
    filmType = "no"        ← 장치 자체 반전을 끈다. 필름 메타데이터가 아니다.

그 외:
    preserveRawCoolscan = (backend == "coolscan" && 옵션명 == "type")
    requestedPolarity = (preserveRawCoolscan || !filmType.requiresInversion)
                        ? "positive" : "negative"
    polarityMatches = 열거값 중 소문자에 requestedPolarity 포함
    requiresInversion이고 !preserveRawCoolscan:
        polarityMatches 중 "slide"를 포함하지 않는 첫 값, 없으면 첫 값
    아니면:
        polarityMatches 중 "slide"를 포함하는 첫 값, 없으면 첫 값
```

`requiresInversion`은 `colorNegative`/`bwNegative`가 true다.

### 5.4 IR 전략

`options.infraredEnabled`일 때만 결정한다.

```text
소스 목록에 infrared 값이 있으면      → .separateSource(그 값)
아니면 모드 목록에 "infrared" 포함    → .separateMode(그 값)
아니면                               → .none
```

`isInfraredValue(s)`: 소문자에 `infrared`가 포함되거나 정확히 `ir`.

`.cleanImage`는 `resolveMedia`가 만들지 않는다. 능력 보고
([capability-model](capability-model.md))에서만 `--clean-image` 존재를
`disabledReasons`로 설명한다. `IRStrategy.cleanImage`는 타입에는 있으나
현재 어느 경로에서도 생성되지 않는 상태다 — Windows 이식 시 이 사실을
그대로 유지하고, 죽은 분기를 임의로 되살리지 않는다.

### 5.5 `irPassMode`

별도 IR 패스에서 쓸 `--mode` 값. gray 모드 값을 선호한다.
`pickModeValue(modeValues, colorMode: .gray)`의 결과가 그대로 들어간다.

### 5.6 `pickModeValue`

```text
gray    → 소문자에 "gray" 또는 "grey"
lineart → "lineart" 또는 "binary"
infrared→ "infrared"
color   → "color"
첫 매치의 원문을 반환. 없으면 nil.
```

## 6. `resolutionSpec`과 `snapResolution`

`snapResolution`은 코드에 있지만 **production 경로에서 호출되지 않는다.**
정확 옵션 계약이 스냅을 금지하기 때문이다. 이식 시 이 함수를 옮길지는 선택이며,
옮긴다면 "테스트·진단 전용, production 호출 금지" 주석을 반드시 유지한다.

## 7. 이식 fixture 목록

`SaneOptionDump` 단위:

- [ ] 섹션 제목·설명문 무시
- [ ] `--preview[=(yes|no)]` → 이름 `preview`
- [ ] 중복 옵션 → 첫 항목 채택
- [ ] `[inactive]` 대소문자 변형
- [ ] `\r\n` 줄바꿈 입력
- [ ] 열거값의 공백 포함 항목 보존
- [ ] `600dpi` 정수 추출
- [ ] `0..36.33mm` 단위 추출
- [ ] `0..65535` 단위 없음 → nil
- [ ] `(in steps of 0.5)` step 파싱
- [ ] `containsExactly` 표(§3.7)
- [ ] 비활성 옵션의 `enumValues` == 빈 배열, `constraintEnumValues` == 값 있음
- [ ] UTF-8 아닌 바이트 → 오류

`resolveMedia` 단위 — 백엔드별 실제 덤프를 픽스처로 고정:

- [ ] genesys(투과 단일 소스, IR 소스 있음/없음)
- [ ] epson2(Flatbed + TPU + TPU8x10, film-type, color/gamma correction)
- [ ] coolscan3(`--mode` 없음, pel 지오메트리, `--depth 8|14`)
- [ ] coolscan2(`--negative`)
- [ ] coolscan(`--type`)
- [ ] pieusb(`--advance`, `--clean-image`, RGBI 모드)
- [ ] pie(`--depth` 없음)
- [ ] 빈 덤프
- [ ] 모서리 pel 좌표만 있는 가상 장치

각 픽스처는 (덤프, 요청) → `MediaSelection` 전체 필드의 기대값을 JSON으로
고정하고, Swift와 Windows 구현이 같은 값을 내는지 비교한다
([conformance-fixtures](../05-protocol/conformance-fixtures.md)).
