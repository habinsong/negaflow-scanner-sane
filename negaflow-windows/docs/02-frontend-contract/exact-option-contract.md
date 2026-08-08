# 정확 옵션 계약

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 이식 정본 — 이 문서와 코드가 어긋나면 코드가 옳다
코드 근거: `Sources/SANEPluginCore/SANEBackend+ScanExecution.swift`
(`validateExactOptions`, `validateAdjustment`, `validatedScannedTIFF`,
`validatedScanResult`), `Sources/SANEPluginCore/PluginProtocolV2.swift`

관련 문서:

- [option-dump-parser](option-dump-parser.md)
- [capability-model](capability-model.md)
- [backend-quirks](backend-quirks.md)
- [wire-contract](../05-protocol/wire-contract.md)
- [product-invariants](../99-plan/product-invariants.md)

## 1. 이 계약이 존재하는 이유

SANE는 요청을 조용히 반올림한다. `--resolution 3600`을 보내면 백엔드가 2400으로
바꿔 스캔하고 stderr에 `rounded value of resolution from 3600 to 2400` 한 줄을
남긴 뒤 exit 0으로 끝난다. 이 플러그인은 그 결과를 **성공으로 받지 않는다.**

제품 규칙 한 줄:

> 요청한 값을 정확히 적용할 수 없으면 스캔을 시작하지 않는다. 시작한 뒤에
> 알게 되면 결과를 버린다.

Windows 구현이 이 규칙을 완화하면 같은 필름을 같은 설정으로 두 OS에서 스캔했을
때 다른 픽셀이 나온다. 그 시점에서 negaflow의 현상 결과는 플랫폼에 의존하게
되고, 제품 불변식이 깨진다.

## 2. 세 단계 검증

```text
[1] 요청 문법 검증        PluginScanRequestV2.validatedOptions()
        ↓ 실패 → error 이벤트, exit 1, scanimage 미실행
[2] 장치 능력 대조        validateExactOptions(options, media:)
        ↓ 실패 → error 이벤트, exit 1, scanimage 미실행
[3] 산출물 검증           validatedScannedTIFF + validatedScanResult
        ↓ 실패 → 파일 삭제, error 이벤트, exit 1
    성공 → result 이벤트(appliedOptions 포함)
```

세 단계는 **순서가 계약**이다. 2단계 이전에는 장치를 열지 않고, 3단계 이전에는
result를 내지 않는다.

## 3. 1단계 — 요청 문법

`validatedOptions()`가 순서대로 검사한다. 전부 `unsupportedOption` 코드다.

| # | 조건 | 통과 요건 |
|---:|---|---|
| 1 | `protocolVersion` | `== 2` |
| 2 | `deviceID` | 공백 제거 후 비어 있지 않음 |
| 3 | `bitDepth` | `8` 또는 `16` |
| 4 | `colorMode` | `color` 또는 `gray` (`lineart`/`infrared`는 인식은 되나 거부) |
| 5 | `filmType` | `colorNegative`/`colorPositive`/`bwNegative`/`bwPositive` |
| 6 | `scanArea` | 네 값 모두 유한, 원점 ≥ 0, 폭·높이 > 0 |
| 7 | `hardwareExposureTime` | null이거나 > 0 |
| 8 | `brightnessAdjustment`/`contrastAdjustment` | null이거나 유한 |
| 9 | `outputPath` | 정규화된 절대 경로 |
| 10 | `capabilityToken` | null이거나 UTF-8 1,048,576 바이트 이하 |
| 11a | `preview == true` | `resolutionDPI == 0` **그리고** `infrared == false` **그리고** `multiExposure == false` **그리고** `hardwareExposureTime == null` **그리고** `outputRawTIFF == false` |
| 11b | `preview == false` | `resolutionDPI > 0` **그리고** `outputRawTIFF == true` **그리고** `!(multiExposure && hardwareExposureTime != nil)` |

### 3.1 Windows에서 달라지는 항목 — 9번

macOS 구현:

```swift
URL(fileURLWithPath: outputPath).path == outputPath && (outputPath as NSString).isAbsolutePath
```

**이것은 정규화 검사가 아니다.** 이 문서는 한동안 "정규화 결과가 입력과
같고 `/`로 시작한다"고 서술했는데, 실행해 보니 사실이 아니었다
(2026-08-05 실측).

```text
입력                            .path 결과                     통과
"/tmp/../frame.tiff"            "/tmp/../frame.tiff"           ✅
"/tmp/./frame.tiff"             "/tmp/./frame.tiff"            ✅
"/tmp//frame.tiff"              "/tmp//frame.tiff"             ✅
"/tmp/a/../../../etc/passwd"    (그대로)                        ✅
"/tmp/frame/"                   "/tmp/frame"                   ❌ 입력과 다름
"tmp/frame.tiff"                (cwd 기준 절대 경로로 확장)      ❌
```

`URL(fileURLWithPath:).path`는 **후행 슬래시만** 없앤다. `..`도 `.`도 `//`도
접지 않는다. 즉 macOS의 9번 가드는 실제로는 "`/`로 시작하고 후행 슬래시가
없다"에 지나지 않으며, **경로 탈출을 막지 못한다.**

호스트가 `outputPath`를 주므로 통상 운용에서 공격자 입력은 아니다. 그러나
I-16이 "`outputPath`와 그것에서 파생된 IR 경로에만 결과를 쓴다"를 요구하는데,
`..`이 통과하면 "그 경로"가 어디든 될 수 있다. **심층 방어의 구멍이다.**

→ macOS 쪽 강화는 I-20(양 플랫폼 동시 적용) 후보다. 이 문서의 범위는 아니다.

Windows에서는 §3.2의 규칙으로 **처음부터 막는다.** 아래를 모두 확인한다.

| 항목 | 요건 |
|---|---|
| 형태 | `X:\...` 드라이브 절대 경로. 드라이브 상대(`C:foo`), 루트 상대(`\foo`) 거부 |
| UNC | `\\server\share\...`는 기본 거부(호스트 staging은 로컬 볼륨 전제) |
| 장치 네임스페이스 | `\\?\`, `\\.\`, `\??\` 거부 |
| 구성요소 | `.`, `..`, 빈 구성요소 거부 |
| 예약 이름 | 마지막 구성요소가 `CON`/`PRN`/`AUX`/`NUL`/`COM1`~`COM9`/`LPT1`~`LPT9`(확장자 유무 무관) 거부 |
| 후행 문자 | 구성요소의 후행 `.`/공백 거부 |
| ADS | `:`가 드라이브 문자 위치 외에 나타나면 거부 |
| 정규화 | `GetFullPathNameW` 결과가 입력과 **바이트 동일**해야 함 |
| 길이 | `MAX_PATH` 초과 시 long-path 인식 여부를 매니페스트/OS 정책과 함께 확인 |

### 3.2 두 정책은 의도적으로 다르다

같은 요청이 두 OS에서 다른 판정을 받는다.

```text
"/tmp/../x.tiff"        macOS 통과      경로 탈출을 막지 못한다
"C:\tmp\..\x.tiff"      Windows 거부    구성요소 검사가 막는다
```

**이것은 divergence이지 버그가 아니다.** macOS가 약한 쪽이고 Windows가
문서가 정한 대로 하는 쪽이다. 다른 divergence(CRLF)와 같은 성격이다 —
어느 쪽이 옳은지 판단이 끝났고, 이식이 그 판단을 따른다.

이식 코드는 두 정책을 **모두** 구현한다. Windows 정책이 제품 동작이고,
POSIX 정책은 **파리티 전용**이다 — 9번을 Windows 정책으로 고정하면 macOS를
통과하는 경로가 전부 거부돼 10·11번 가드에 도달할 수 없고, 그러면 나머지
가드의 순서와 문구를 대조할 수 없다.

```text
wire/request.h  PathPolicy::WindowsAbsolute   제품. 단위 테스트가 §3.1 표를 고정
                PathPolicy::PosixAbsolute     파리티 전용. 원본을 그대로 재현
```

### 3.3 문자열 검사로 끝내지 않는다

경로 문자열 비교만으로 보안을 끝내지 않는다. 실제 파일을 만든 뒤
`GetFinalPathNameByHandleW`로 최종 경로를 다시 확인하고, reparse point가
아님을 확인한다([child-process](../03-process-and-io/child-process.md) §7).

**대소문자**: Windows 경로 비교는 대소문자 무시가 기본이지만 프로토콜의
`path` 필드는 호스트가 준 문자열을 **그대로** 돌려줘야 한다. 정규화한 대소문자로
바꿔 보내면 호스트의 `normalized path == expected staged path` 검사에서
구현마다 결과가 갈릴 수 있다. 어댑터는 받은 문자열을 보존한다.

## 4. 2단계 — 장치 능력 대조 (`validateExactOptions`)

입력은 요청과 `MediaSelection`(옵션 덤프를 해석한 결과)이다. 검사 순서도 계약이다.

### 4.1 해상도

```text
preview  → media.hasPreviewOption 필수
full     → media.resolvedDPI == options.resolution.dpi 필수
```

`resolvedDPI`는 [option-dump-parser](option-dump-parser.md)에서 정해진다.
목록형이면 정확히 포함, 범위형이면 `containsExactly`(최소·최대·step 모두).
가장 가까운 값으로 스냅하지 않는다.

### 4.2 비트 심도

두 갈래다.

```text
media.fixedDepth != nil
    → fixedDepth == options.bitDepth 필수. --depth를 보내지 않는다.
media.fixedDepth == nil
    → media.hasDepthOption 필수
    → media.depthArgument 존재 필수
    → 8-bit 요청: depthArgument == 8
    → 16-bit 요청: depthArgument > 8
```

16-bit 요청에서 `depthArgument`가 8 초과이면 통과한다. SANE의 9…16-bit 샘플은
16-bit 컨테이너로 전달된다는 규격 때문이다(coolscan3의 `--depth 14`가 대표).
실제 파일이 16-bit인지는 3단계가 다시 본다.

`fixedDepth` 판정은 [capability-model](capability-model.md) §4를 따른다.

### 4.3 색 모드

```text
media.hasModeOption == true
    → color 요청: 적용 모드 문자열에 "color" 포함 필수
    → gray  요청: "gray" 또는 "grey" 포함 필수
    → lineart/infrared 요청: 무조건 거부
media.hasModeOption == false
    → media.dedicatedFilmDevice == true 그리고 요청이 color일 때만 통과
```

즉 `--mode`가 없는 장치는 전용 필름 스캐너로 판정된 경우에만, 그리고
color 요청에 한해 허용된다.

### 4.4 소스

```text
media.source != nil && !isTransparencySource(source) → 거부
```

`isTransparencySource`는 소문자에 `transparency`/`tpa`/`tpu`/`film`/`slide` 중
하나가 포함되면 참이다. 반사 원고 소스로 필름을 스캔하지 않는다.

### 4.5 필름 타입 극성

```text
media.hasFilmTypeOption == true && media.filmType == nil → 거부
```

옵션이 있는데 요청한 극성에 맞는 열거값을 못 찾은 상태를 통과시키지 않는다.

### 4.6 백엔드별 필수 조건

| 백엔드 | 조건 | 실패 시 |
|---|---|---|
| `pieusb` | `media.hasAdvanceOption` 필수 | 거부. 자동 슬라이드 이동을 끌 수 없으면 스캔하지 않는다 |
| `epson2` | `hasColorCorrectionOption`이면 `colorCorrection != nil` | 거부 |
| `epson2` | `hasGammaCorrectionOption`이면 `gammaCorrection != nil` | 거부 |

백엔드 이름은 `deviceID`에서 `sane-` 접두사를 뗀 뒤 첫 `:` 앞부분이다.

### 4.7 지오메트리

네 갈래이며 순서대로 판정한다.

**(a) 모서리 pel 좌표** (`usesCornerPixelGeometry`)

```text
originXPixels, originYPixels, rightPixels, bottomPixels 넷 다 존재 필수
```

**(b) 폭·높이 pel** (`widthPixels != nil && heightPixels != nil`)

```text
originXPixels/originYPixels가 없으면 요청 원점이 (0,0)이어야 한다
```

**(c) preview + 전용 필름 장치**

```text
요청 원점이 (0,0)이어야 한다
```

**(d) mm 지오메트리** (그 외 전부)

```text
appliedHeightMM = 요청 높이 + media.heightAlignmentMM

필수:
  scanWidthRange.containsExactly(요청 폭)
  scanHeightRange.containsExactly(appliedHeightMM)
  abs(heightAlignmentMM) < 1
  media.widthMM  == 요청 폭
  media.heightMM == appliedHeightMM

원점(-l/-t 범위가 둘 다 있을 때):
  scanLeftRange.containsExactly(요청 원점X)
  scanTopRange.containsExactly(요청 원점Y)
  media.originXMM == 요청 원점X
  media.originYMM == 요청 원점Y

원점 범위가 없을 때:
  요청 원점이 (0,0)이 아니면 거부

경계:
  요청 원점X + 요청 폭        <= scanSurfaceRightMM  + 1e-9
  요청 원점Y + appliedHeightMM <= scanSurfaceBottomMM + 1e-9
```

`heightAlignmentMM`은 epson2 전용 보정이며 [backend-quirks](backend-quirks.md) §3이
소유한다. **1 mm 미만 높이 정렬만 허용**되고 폭·원점에는 어떤 허용치도 없다.

### 4.8 밝기·대비 (`validateAdjustment`)

```text
값이 null            → 통과
값 == 0 이고 범위 없음 → 통과 (중립값은 옵션이 없어도 의미가 같다)
그 외               → range.containsExactly(값) 필수
```

### 4.9 하드웨어 노출

```text
hardwareExposureTime != nil
    → media.hasScanExposureOption 필수
    → media.hardwareExposureRange.containsExactly(값) 필수
```

### 4.10 다중 노출

```text
colorMode == color 그리고 bitDepth == 16 필수
media.hasScanExposureOption 필수
hardwareExposureTimes(= [11000, 14000, 30000])의 모든 값이 범위에 정확히 존재 필수
infrared 동시 요청이면 irStrategy가 별도 패스 방식이어야 함
```

### 4.11 적외선

```text
irStrategy가 .separateSource 또는 .separateMode 여야 통과
.none, .cleanImage → 거부
```

`--clean-image`(pieusb)는 백엔드 내부 먼지 제거이며 별도 IR 파일을 주지 않으므로
IR 요청을 만족시키지 못한다.

## 5. 3단계 — 산출물 검증

### 5.1 `validatedScannedTIFF`

| 검사 | 실패 코드 |
|---|---|
| `resourceValues` 읽기 성공 | `ioFailure` |
| regular file이고 심볼릭 링크가 아니고 크기 > 0 | `ioFailure` |
| 이미지 소스 생성 성공 | `ioFailure` |
| 이미지 개수 == 1 | `ioFailure` |
| 컨테이너 타입 == TIFF | `ioFailure` |
| 첫 이미지 디코드 성공, width>0, height>0 | `ioFailure` |
| `bitsPerComponent` ∈ {8,16} | `ioFailure` |
| 색 모델이 RGB 또는 monochrome | `ioFailure` |
| 실제 심도 == 요청 심도 | `ioFailure` |
| 실제 색 모드 == 기대 색 모드 | `ioFailure` |

Windows 대응은 [tiff-validation](../04-imaging/tiff-validation.md)이 소유한다.
핵심: **"이미지 개수 == 1"과 "컨테이너 타입 == TIFF"를 반드시 유지한다.**
멀티페이지 TIFF나 다른 컨테이너를 통과시키면 계약이 무너진다.

### 5.2 `validatedScanResult`

```text
RGB TIFF 검증 (요청 심도, 요청 색 모드)

infrared 요청됨:
    infraredURL 존재 필수
    IR TIFF 검증 (요청 심도, gray)
    IR 폭/높이 == RGB 폭/높이 필수

infrared 미요청인데 infraredURL 존재:
    거부

실패 시: RGB와 IR 파일을 모두 삭제한 뒤 오류 전파
```

성공 시 `ScanResult`를 만든다. `appliedScanArea`는:

```text
originXMM: media.originXMM ?? 요청 원점X
originYMM: media.originYMM ?? 요청 원점Y
widthMM:   media.widthMM   ?? 요청 폭
heightMM:  media.heightMM  ?? 요청 높이
```

즉 mm 인자를 실제로 보낸 경우에만 보낸 값을, 아니면 요청값을 그대로 보고한다.
pel 장치에서는 요청값이 그대로 보고된다는 뜻이다.

### 5.3 어댑터의 마지막 확인 (`main.swift`)

result 이벤트를 내기 직전에 한 번 더:

```text
result.rawFileURL.path      == request.outputPath
result.resolution.dpi       == request.resolutionDPI
result.bitDepth.rawValue    == request.bitDepth
result.hasInfraredChannel   == request.infrared
```

이 네 줄은 중복처럼 보이지만 백엔드 계층과 프로토콜 계층 사이의 마지막
안전망이다. Windows 구현에서도 남긴다.

## 6. 실행 중 반올림 감지

획득이 exit 0으로 끝나도 stderr를 본다.

```swift
static func containsInexactOptionWarning(_ stderr: String) -> Bool {
    stderr.lowercased().contains("rounded value of")
}
```

참이면 `unsupportedOption`으로 실패시키고 stderr 전문을 메시지에 싣는다.

**Windows 위험**: 이 문자열은 `scanimage`의 영어 메시지다. 환경을 `LC_ALL=C`로
고정하는 이유가 여기 있다. Windows 빌드가 gettext 번역을 포함하고 로케일 변수를
무시하면 이 감지가 통째로 죽는다. 이식 시 다음을 spike로 확인한다.

1. 대상 `scanimage` 빌드가 NLS를 포함하는가
2. `LC_ALL`/`LANG`/`LANGUAGE`를 존중하는가, 아니면 `GetUserDefaultUILanguage`를 보는가
3. 존중하지 않는다면 번역 카탈로그를 배제한 빌드를 쓸 것인가, 아니면
   `--dont-scan`류 사전 검증으로 반올림을 사전에 배제할 것인가

이 spike가 실패로 끝나면 옵션 반올림 감지의 대체 수단을 반드시 마련해야 한다.
가장 유력한 대체: 획득 직전에 요청 인자를 그대로 실은 `-A` 덤프를 한 번 더 읽어
선택값(`[value]`)이 요청과 같은지 확인. 비용은 장치 open 1회 추가다.

## 7. 실패 코드 매핑

| 코드 | 발생 지점 |
|---|---|
| `unsupportedOption` | 1·2단계 전부, 반올림 감지 |
| `ioFailure` | 3단계 전부, 프로세스 실패, 덤프 없음 |
| `busy` | `access to resource has been denied`, `device busy`, `resource busy` |
| `notConnected` | `no such device`, `invalid argument`, `not connected`, 주소 재해석 실패 |
| `cancelled` | 취소 요청 확인됨 |
| `timeout` | 유틸리티 타임아웃, 첫 진행률 타임아웃, 진행률 정체 |
| `driverConflict` | 현재 코드에서 생성되지 않음(도메인에만 존재) |
| `unknown` | 현재 코드에서 생성되지 않음 |

현재 wire v2의 error 이벤트에는 코드 필드가 없다. `errorDescription`이
`"<code>: <message>"` 형태로 직렬화될 뿐이다. Windows 구현은 내부 코드를
그대로 유지하되 wire 형식을 바꾸지 않는다
([wire-contract](../05-protocol/wire-contract.md) §8).

## 8. 이식 conformance 목록

각 항목에 accept/reject 픽스처가 하나씩 있어야 한다.

### 8.1 1단계

- [ ] 11개 문법 조건 각각의 거부 케이스
- [ ] preview 조합 5가지 각각의 거부
- [ ] full 조합 3가지 각각의 거부
- [ ] Windows 경로 거부 8종(UNC, 장치 네임스페이스, `..`, 예약 이름, 후행 점,
      후행 공백, ADS, 드라이브 상대)
- [ ] 정확히 1,048,576 바이트 토큰 통과 / 1 바이트 초과 거부

### 8.2 2단계

- [ ] 목록형 해상도 미포함 거부
- [ ] 범위형 step 불일치 거부
- [ ] `fixedDepth` 불일치 거부 / 일치 통과
- [ ] `--depth` 비활성 + 제약값 2개 이상 → `fixedDepth == nil` → 거부
- [ ] `--mode` 없음 + 비전용 장치 → 거부
- [ ] `--mode` 없음 + 전용 필름 장치 + gray 요청 → 거부
- [ ] 반사 소스만 있는 장치 → 거부
- [ ] `--film-type`/`--type`/`--negative`가 있는데 극성 값을 못 고름 → 거부
      (`hasFilmTypeOption && filmType == nil`)
- [ ] `pieusb` + `--advance` 없음 → 거부
- [ ] `epson2` + color-correction 옵션 있으나 `None` 값 없음 → 거부
- [ ] `epson2` + **gamma**-correction 옵션 활성이나 값 없음 → 거부
- [ ] pel 모서리 지오메트리인데 네 좌표 중 하나라도 nil → 거부
- [ ] pel 폭/높이만 있고 pel 원점이 없는데 요청 원점 ≠ 0 → 거부
- [ ] preview + 전용 필름 장치 + 요청 원점 ≠ 0 → 거부
- [ ] mm 폭 정확 불일치 거부
- [ ] 높이 정렬 0.99 mm 통과 / 1.0 mm 거부
- [ ] 원점 범위 없는데 원점 ≠ 0 → 거부
- [ ] 우측/하단 경계 초과 거부
- [ ] brightness 0 + 범위 없음 통과 / brightness 5 + 범위 없음 거부
- [ ] 단일 `hardwareExposureTime` + `scan-exposure-time` 옵션 없음 → 거부
- [ ] 단일 `hardwareExposureTime`이 범위에 `containsExactly` 아님 → 거부
- [ ] 다중 노출 8-bit 거부, gray 거부, 노출 계획 미포함 거부
- [ ] 다중 노출 + IR인데 IR이 별도 패스 방식이 아님 → 거부
- [ ] IR `.cleanImage` 거부, `.none` 거부

이 목록은 §4.1~§4.11의 조건과 **일대일로 대응한다.** 항목을 추가·삭제할 때
양쪽을 함께 고친다 — 본문에만 있고 목록에 없으면 그 조건은 픽스처 없이
이식된다.

### 8.3 3단계

- [ ] 멀티페이지 TIFF 거부
- [ ] JPEG/PNM을 `.tiff`로 저장한 파일 거부
- [ ] 크기 0 파일 거부
- [ ] 심볼릭 링크/reparse point 거부
- [ ] 8-bit 파일 + 16-bit 요청 거부
- [ ] gray 파일 + color 요청 거부
- [ ] CMYK/팔레트 TIFF 거부
- [ ] IR 미요청인데 IR 파일 생성됨 → 거부
- [ ] IR 크기 불일치 거부
- [ ] 실패 시 두 파일이 모두 지워졌는지 확인

### 8.4 반올림

- [ ] `rounded value of` 포함 stderr + exit 0 → 실패
- [ ] 대소문자 변형 감지
- [ ] 번역된 메시지에서 감지 실패를 재현하는 회귀 테스트(로케일 위험 문서화용)

## 9. 열린 질문

- Windows에서 `LC_ALL=C`가 `scanimage` 메시지 언어를 실제로 고정하는가
- long path(`\\?\` 없이 260자 초과) staging을 호스트가 만들 수 있는가, 만든다면
  어댑터가 그 경로를 열 수 있는가
- 반올림 감지 대체 경로를 채택할 경우 추가 장치 open이 전용 필름 스캐너의
  다음 획득을 깨뜨리지 않는지(현재 코드가 회피하려는 바로 그 문제)
