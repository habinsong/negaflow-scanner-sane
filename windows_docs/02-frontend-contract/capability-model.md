# 능력 모델

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 이식 정본
코드 근거: `SANEBackend+Capabilities.swift`(`parseCapabilities`, `fixedDepth`,
`isTransparencySource`, `isInfraredValue`, `preferredTransparencySource`),
`SANEBackend+Discovery.swift`(`getCapabilitiesReport`), `WireProtocol.swift`

관련 문서:

- [option-dump-parser](option-dump-parser.md)
- [exact-option-contract](exact-option-contract.md)
- [backend-quirks](backend-quirks.md)
- [wire-contract](../05-protocol/wire-contract.md)

## 1. 원칙

호스트 UI는 능력 응답만 보고 컨트롤을 그린다. 따라서 이 응답은
**약속이 아니라 관측**이어야 한다.

- 모델명으로 능력을 발명하지 않는다.
- 옵션이 있다는 사실과 그 옵션이 활성이라는 사실을 구분한다.
- 능력을 끌 때는 왜 껐는지를 `disabledReasons`에 남긴다.
- 능력을 켜면 [exact-option-contract](exact-option-contract.md)의 2단계가
  그 값을 실제로 적용할 수 있어야 한다. 능력과 검증이 어긋나면
  사용자는 켤 수 있는 컨트롤을 켰다가 스캔 시작 시 거부당한다.

마지막 항목이 가장 중요하다. `parseCapabilities`와 `validateExactOptions`는
**같은 덤프에서 같은 결론**을 내야 한다.

## 2. 능력을 어떤 상태에서 읽는가

이것이 이 프로젝트에서 가장 비싸게 배운 사실이다.

> SANE 옵션은 다른 옵션의 활성 여부와 범위를 바꾼다. 장치 기본 상태에서 읽은
> 덤프는 실제 스캔을 설명하지 않는다.

구체적 사례:

- `epson2`의 기본 모드는 Lineart이고, 그 상태에서 `--depth`를 비활성으로
  내린다(실측: Epson GT-X980 = V850). 모드를 적용하지 않은 덤프만 읽으면
  지원 심도가 통째로 비어 "스캐너를 쓸 수 없음"으로 오판한다.
- `epson2`는 선형 감마를 선택하면 `--brightness`를 비활성으로 내린다.
- 투과 소스를 선택하면 지오메트리 범위가 바뀐다.

그래서 `getCapabilitiesReport`는 다음 순서로 읽는다.

```text
1. -A -d <dev>  (genesys는 --mode Color 추가)
2. 필요하면 투과 source + Color/Gray mode + epson2 color/gamma correction을
   적용해 -A를 한 번 더
3. 그 상태의 덤프를 파싱하고, 같은 덤프를 capabilityToken에 통째로 넣는다
4. 토큰에 그 상태에서 검증된 모드(validatedMode)를 함께 기록한다
```

이후 scan 요청이 같은 모드를 요구하면 토큰의 덤프를 재사용한다. 다른 모드를
요구하면 그 모드를 적용한 `-A`를 다시 읽는다.
자세한 절차는 [scanimage-invocation](scanimage-invocation.md) §3.

### 2.1 `validatedColorMode`

토큰에 기록할 "이 덤프가 어느 모드에서 읽혔는가":

```text
selectedEnumValue("mode")가 있으면:
    소문자에 "color"        → .color
    "gray" 또는 "grey"      → .gray
    그 외                   → nil
없으면:
    !isActive("mode") 이고 (deviceType에 film|slide 포함 || 전용 필름 backend)
        → .color
    아니면 nil
```

nil이면 다음 스캔이 항상 덤프를 다시 읽는다. 정확하지만 느리다.

## 3. 필드별 산출 규칙

입력: 덤프, `deviceTypeHint`(`-L`/`-f`의 `%t`), `backendHint`.

### 3.1 해상도 (`supportedResolutions`)

```text
.list(dpis)      → 그대로 Resolution 배열
.range(min, max) → 표준 후보 [100,150,300,600,1200,2400,3200,3600,4800,6400,7200,9600,12800]
                   중 min<=v<=max 이고 containsExactly(v)인 값
                   + containsExactly(max)이면 max도 추가(중복 제외)
.none            → 빈 배열
```

정렬해서 반환한다. **범위형 장치에서 임의의 dpi를 노출하지 않는다.** UI가
자유 입력을 허용하면 사용자가 step에 맞지 않는 값을 넣어 2단계에서 거부당한다.

### 3.2 색 모드 (`supportedModes`)

```text
mode 열거값(소문자)에 "color" 포함 → .color 추가
"gray" 또는 "grey" 포함            → .gray 추가
비어 있고 dedicatedFilmDevice      → .color 추가
```

마지막 갈래: 일부 전용 필름 백엔드는 `--mode`가 없고 출력 프레임 형식으로
Color를 고정한다. 실제 결과 TIFF의 채널 수는 획득 뒤 다시 검증한다.

### 3.3 비트 심도 (`supportedBitDepths`)

```text
depth 토큰(활성일 때만)에 8 있으면       → .eight
depth 토큰에 8 초과 값이 있으면          → .sixteen
둘 다 비고 fixedDepth가 있으면           → [fixedDepth]
```

8 초과(10/12/14/16-bit ADC)는 모두 16-bit 컨테이너로 전달된다는 SANE 규격을
따른다.

### 3.4 `fixedDepth` — 고정 심도 판정

```text
hasOption("depth") == false:
    backendHint ∈ {"epson2", "pie"} → .eight
    그 외                            → nil
isActive("depth") == true:
    → nil (고정이 아니다)
비활성이고 constraintIntTokens("depth")가 정확히 1개:
    값 == 8      → .eight
    값 > 8       → .sixteen
    그 외        → nil
값이 여러 개인데 비활성:
    → nil (우리가 모르는 이유로 잠긴 상태이므로 아무것도 고르지 않는다)
```

근거:

- `epson2`는 심도가 하나뿐인 구형 기기에서 옵션 자체를 노출하지 않고 항상
  8비트로 전송한다(sane-epson2 문서).
- `pie`는 Color/Gray 결과의 `SANE_Parameters.depth`를 항상 8로 설정하며
  별도 depth 옵션을 제공하지 않는다.

**이 두 backend에만 적용한다.** 다른 backend에서 옵션이 없다고 8비트로
추정하지 않는다. Windows 이식에서 이 목록을 확장하려면 해당 backend 소스와
실기 증거가 필요하다.

### 3.5 투과 (`supportsTransparency`)

```text
transparencyModes = sources 중 isTransparencySource(s)
dedicatedFilmDevice = !isActive("source")
                      && (deviceType에 "film"|"slide" 포함 || 전용 필름 backend)
supportsTransparency = !transparencyModes.isEmpty || dedicatedFilmDevice
```

`isTransparencySource(s)`: 소문자에 `transparency`, `tpa`, `tpu`, `film`,
`slide` 중 하나 포함.

`isDedicatedFilmBackend(b)`: `b ∈ {coolscan, coolscan2, coolscan3, pie, pieusb}`.

### 3.6 적외선 (`supportsInfrared`)

```text
infraredViaSource = sources 중 isInfraredValue(s)
infraredViaMode   = mode 값(소문자)에 "infrared" 포함
supportsInfrared  = 둘 중 하나
```

`supportsInfrared == true`의 의미는 **별도 IR TIFF 파일을 돌려줄 수 있다**이다.
백엔드 내부 먼지 제거(`--clean-image`)는 IR 능력이 아니다.

### 3.7 다중 노출 (`supportsMultiExposure`)

```text
hardwareExposureRange가 있고
hardwareExposureTimes(= [11000, 14000, 30000]) 전부를 containsExactly
```

세 값 중 하나라도 범위를 벗어나거나 step에 안 맞으면 false다.
소프트웨어로 흉내 내지 않는다.

### 3.8 스캔 영역

```text
x, y 단위가 둘 다 "mm"이고 두 범위 최대가 0 초과:
    supportsScanArea = true
    leftRange  = l 단위가 mm일 때만
    topRange   = t 단위가 mm일 때만
    surfaceOriginX = leftRange?.minimum ?? 0
    surfaceOriginY = topRange?.minimum  ?? 0
    minScanArea = (surfaceOriginX, surfaceOriginY,
                   minimumPositiveScanDimension(xRange),
                   minimumPositiveScanDimension(yRange))
    maxScanArea = (surfaceOriginX, surfaceOriginY, xRange.maximum, yRange.maximum)
    supportsPositionedScanArea = transparencyModes 비지 않음
                                 && 반사 소스가 하나라도 있음
                                 && leftRange != nil && topRange != nil
아니고 x 또는 y 단위가 "pel":
    scanAreaUnit = .pixel  (영역 크기는 0으로 남는다)
```

`minimumPositiveScanDimension(range)`:

```text
range.minimum > 0        → minimum
step > 0                 → min(step, maximum)
그 외                    → min(0.1, maximum)
```

`supportsPositionedScanArea`에 "반사 소스가 하나라도 있음"이 들어간 이유:
평판 스캐너에서 필름 홀더 위치를 지정하는 워크플로를 위한 것이며,
전용 필름 스캐너는 위치 지정이 의미가 없다.

### 3.9 미리보기

```text
supportsPreview = isActive("preview")
```

### 3.10 밝기·대비·노출 범위

```text
brightnessRange       = numericRange("brightness")
contrastRange         = numericRange("contrast")
hardwareExposureRange = numericRange("scan-exposure-time")
```

`numericRange`는 활성일 때만 값을 준다. 따라서 비활성 옵션은 자동으로 nil이다.

**주의**: `parseCapabilities`는 genesys 16-bit 예외를 적용하지 **않는다**.
그 예외는 `resolveMedia`에만 있다(`supportsHardwareToneAdjustments`).
결과적으로 genesys 장치의 능력 응답에는 brightness 범위가 나타나지만
16-bit 스캔 요청에서 그 값을 보내면 2단계에서 거부된다.

이것은 **현재 코드의 실제 동작**이며, 능력과 검증이 어긋나는 유일한 지점이다.
Windows 이식에서 선택지는 둘이다.

1. 현재 동작을 그대로 옮긴다(호환 우선). 사용자는 16-bit에서 밝기를 조정하려다
   거부당한다.
2. `parseCapabilities`에도 같은 예외를 넣고 `disabledReasons["brightness"]`에
   이유를 적는다. 동작이 개선되지만 macOS와 능력 응답이 달라진다.

**권장: 2번을 macOS와 Windows 양쪽에 동시에 적용한다.** 한쪽만 바꾸면
같은 스캐너가 OS에 따라 다른 컨트롤을 보여준다. 이 결정은
[open-questions](../99-plan/open-questions.md) Q-7이 소유한다.

### 3.11 `disabledReasons`

| 키 | 조건 | 메시지 |
|---|---|---|
| `transparency` | `!supportsTransparency` | `--source`에 Transparency/TPU/Film 항목이 없습니다 |
| `infrared` | `!supportsInfrared` && backend==coolscan3 && `hasOption("infrared")` | coolscan3의 `--infrared`는 RGBI 프레임이며 stock scanimage가 별도 IR TIFF로 전달하지 못합니다 |
| `infrared` | `!supportsInfrared` && `hasOption("clean-image")` | `--clean-image`는 별도 IR 채널을 반환하지 않습니다 |
| `infrared` | 그 외 | 별도 IR 채널을 획득할 활성 source/mode가 없습니다 |
| `multiExposure` | `!supportsHardwareExposure` && `hasOption("scan-exposure-time")` | 범위가 필요한 노출 계획을 모두 지원하지 않습니다 |
| `multiExposure` | `!supportsHardwareExposure` && 옵션 없음 | `--scan-exposure-time`이 없어 실제 다중노출을 켤 수 없습니다 |
| `brightness` | `brightnessRange == nil` && `hasOption` | 현재 스캔 옵션 조합에서 비활성입니다 |
| `brightness` | `brightnessRange == nil` && 옵션 없음 | `--brightness` 옵션이 없습니다 |
| `contrast` | 위와 동일 | 위와 동일 |
| `scanArea` | `!supportsScanArea` | mm 단위 `-x`/`-y` 범위가 없어 요청 영역을 정확히 적용할 수 없습니다 |

메시지는 한국어다. Windows 이식에서:

- 이 문자열들은 호스트 UI에 그대로 표시될 수 있다.
- 현지화는 프로토콜에 없다. 메시지 문자열을 wire에 싣는 현재 구조는
  다국어 제품에서 문제가 된다.
- **v3 후보**: `disabledReasons`를 `{키: {code, message}}`로 바꿔 호스트가
  코드로 현지화하게 한다. v2에서는 문자열을 유지한다.
- Windows 구현은 같은 한국어 문자열을 내되, 내부적으로는 코드를 유지해
  v3 전환을 준비한다.

### 3.12 고정값

```text
supportsLampWarmupStatus = false   (항상)
outputFormats            = ["tiff"] (항상)
estimatedScanSpeeds      = [:]      (wire에 없음)
sourceModes              = 덤프의 source 열거값 전부(투과가 아닌 것 포함)
```

## 4. `preferredTransparencySource`

```text
visibleTransparency = sources 중 투과이면서 IR이 아닌 것

1) visibleTransparency 중 공백 제거 후 "8x10"을 포함하는 첫 값
2) 없으면 visibleTransparency의 첫 값
3) 없으면 sources 중 투과인 첫 값 (IR 포함)
```

Epson V700/V750/V800/V850 계열은 일반 TPU와 전체 8x10 투과 영역을 별도
source로 노출한다. 평판 프리뷰/프레임 배치는 가장 넓은 TPU8x10을 우선한다.

## 5. `capabilityToken` 스키마

```json
{
  "schemaVersion": 3,
  "deviceID": "sane-genesys:libusb:001:002",
  "backend": "genesys",
  "acquisitionDevice": "genesys:libusb:001:002",
  "deviceIdentity": { "vendor": "Plustek", "model": "OpticFilm 8100" },
  "deviceType": "film scanner",
  "optionDump": "<-A 출력 전문>",
  "validatedMode": "color"
}
```

base64(UTF-8 JSON)로 인코딩해 문자열 하나로 보낸다.

### 5.1 크기

`optionDump`가 통째로 들어간다. 실제 덤프는 백엔드에 따라 2 KB~30 KB이고,
base64로 약 1.34배가 된다. 상한은 1 MiB.

Windows 이식 고려사항:

- 호스트가 이 토큰을 다음 scan 요청의 stdin JSON에 넣어 되돌려준다. 즉
  **stdin으로 수십 KB가 들어온다.** 파이프 쓰기가 블록하지 않도록 호스트가
  전체를 쓰고 닫아야 하고, 어댑터는 EOF까지 읽어야 한다.
- 명령줄이 아니라 stdin이므로 Windows 명령줄 길이 제한(32,767자)과 무관하다.
  **토큰을 argv로 옮기지 않는다.**

### 5.2 검증

디코드 시 확인하는 것은 [scanimage-invocation](scanimage-invocation.md) §4에
정리돼 있다. 핵심은 `schemaVersion == 3` 정확 일치다. 다른 값이면
"능력을 다시 조회하십시오"로 실패한다. **가장 가까운 버전으로 낮추지 않는다.**

### 5.3 신뢰 경계

토큰은 호스트를 거쳐 돌아온다. 호스트는 내용을 검사하지 않는다. 따라서
어댑터 입장에서 토큰은 **신뢰할 수 없는 입력**이다.

Windows 구현이 지킬 것:

- base64 디코드와 JSON 파싱에 크기·깊이 상한을 둔다.
- `acquisitionDevice`를 그대로 `-d` 인자로 쓰기 전에 형식을 검사한다.
  옵션처럼 보이는 문자열(`--foo`)이나 개행이 들어오면 거부한다.
  현재 macOS 코드는 이 검사가 없다 — Windows에서는 추가한다.
  `CreateProcessW`는 argv 배열이 아니라 문자열 하나를 받으므로 인용 처리가
  잘못되면 인자 주입이 가능하다([child-process](../03-process-and-io/child-process.md) §4).
- `optionDump`는 파서에만 들어가고 명령줄에 나가지 않으므로 상대적으로 안전하다.
  단 파서가 무한 루프나 지수 백트래킹에 빠지지 않아야 한다(정규식 검토).

## 6. wire 필드 매핑

`PluginCapabilities`(플러그인 출력) ← `ScannerCapabilities`(내부):

| wire 필드 | 내부 | 비고 |
|---|---|---|
| `resolutionsDPI` | `supportedResolutions.map(\.dpi)` | 필수 |
| `modes` | `supportedModes.map(\.rawValue)` | 필수 |
| `bitDepths` | `supportedBitDepths.map(\.rawValue)` | 필수 |
| `sourceModes` | 그대로 | |
| `transparencyModes` | 그대로 | |
| `supportsPreview` … `supportsPositionedScanArea` | 그대로 | |
| `brightnessRange`/`contrastRange`/`hardwareExposureRange` | 그대로 | |
| `scanOriginXRange`/`scanOriginYRange`/`scanWidthRange`/`scanHeightRange` | 그대로 | |
| `disabledReasons` | 그대로 | |
| `minScanArea*`/`maxScanArea*` | 네 필드씩 평탄화 | |
| `scanAreaUnit` | `.rawValue` | |
| `outputFormats` | 그대로 | |
| `capabilityToken` | 보고서에서 | |

`supportsLampWarmupStatus`와 `estimatedScanSpeeds`는 **wire에 나가지 않는다.**
내부 타입에만 있다. 이식 시 이 비대칭을 유지한다.

## 7. 이식 체크리스트

- [ ] `parseCapabilities`가 순수 함수로 유지된다
- [ ] 각 backend 실제 덤프에 대한 능력 응답 전체를 JSON fixture로 고정
- [ ] `fixedDepth` 판정 5갈래 전부 테스트
- [ ] 범위형 해상도의 표준 후보 목록이 동일
- [ ] `minimumPositiveScanDimension` 3갈래
- [ ] `preferredTransparencySource` 3갈래
- [ ] `disabledReasons` 10가지 조합
- [ ] 토큰 라운드트립(인코드 → 디코드 → 같은 덤프)
- [ ] 토큰 `schemaVersion` 2/4 거부
- [ ] 토큰 `acquisitionDevice`에 `--`, 개행, 널 문자 → 거부 (신규)
- [ ] 1 MiB 경계
- [ ] genesys 16-bit 밝기 불일치 결정(Q-7)을 반영
