# wire 계약 (플러그인 쪽)

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 이식 정본
범위: 이 플러그인이 **내는** 것과 **받는** 것
비범위: 호스트 구현(negaflow 본체 windows_docs `10-scanner/protocol-contract.md`가 소유)

코드 근거: `Sources/negaflow-scanner-sane/main.swift`,
`Sources/negaflow-scanner-sane/WireProtocol.swift`,
`Sources/SANEPluginCore/PluginProtocolV2.swift`

관련 문서:

- [encoding-and-json](encoding-and-json.md)
- [conformance-fixtures](conformance-fixtures.md)
- [exact-option-contract](../02-frontend-contract/exact-option-contract.md)
- [capability-model](../02-frontend-contract/capability-model.md)

## 1. 원칙

**wire를 바꾸지 않는다.** 같은 negaflow 호스트가 macOS 플러그인과 Windows
플러그인을 모두 상대하며, 두 플러그인의 응답이 다르면 호스트가 플랫폼별
분기를 갖게 된다. 그 순간 계약이라는 개념이 사라진다.

이 문서에 적힌 모든 형태는 **현재 macOS 구현이 실제로 내는 바이트**다.
설계가 아니라 관측이다.

## 2. 매니페스트

```json
{
  "schemaVersion": 1,
  "protocolVersion": 2,
  "id": "sane",
  "name": "SANE Film Scanner",
  "executable": "negaflow-scanner-sane",
  "kind": "scanner",
  "license": "GPL-2.0-or-later",
  "homepage": "https://github.com/habinsong/negaflow-scanner-sane",
  "pluginVersion": "1.0.3"
}
```

Windows에서 바뀌는 것은 `executable`뿐이다.

```json
"executable": "negaflow-scanner-sane.exe"
```

**`id`를 바꾸지 않는다.** `sane`이다. 라우팅 ID가 `plugin:sane:...`이며
호스트의 승인 기록·능력 캐시·진단이 이 문자열에 묶여 있다.

`pluginVersion`은 Windows 릴리스에서 독립적으로 진행할 수 있다. 그러나
같은 버전 번호가 두 플랫폼에서 다른 동작을 하면 지원이 어려워진다.
**두 플랫폼의 버전을 동기화하는 것을 권장한다.**

아키텍처별 매니페스트가 필요한가? 호스트가 실행 파일의 PE machine type을
확인하므로(본체 windows_docs `10-scanner/plugin-architecture.md` §6.3
"executable path"), 매니페스트에 아키텍처 필드는 필요 없다.
x64용과 ARM64용을 **별도 설치물**로 배포하고 각각 `executable` 이름은
같게 유지한다.

## 3. `detect`

### 3.1 호출

```text
argv: [실행파일, "detect"]
stdin: 없음 (닫힘)
```

### 3.2 응답 — stdout에 한 줄

```json
{"devices":[{"driverVersion":"genesys (SANE)","displayName":"Plustek OpticFilm 8200i","connectionType":"usb","id":"sane-genesys:libusb:001:002","vendor":"Plustek","model":"OpticFilm 8200i","verifiedStatus":"compatibleTarget"}]}
```

**`usbVendorID`/`usbProductID`/`serialNumber`는 nil이라 키가 없다.**
그리고 **키 순서는 보장되지 않는다** — 위는 실측 출력이며 선언 순서가
아니다(§4.2.1).

필드 산출 규칙:

| 필드 | 값 |
|---|---|
| `id` | `"sane-" + <SANE 장치명 전체>` |
| `displayName` | `"<vendor.capitalized> <model>"` 트림. 비면 `model` |
| `vendor` | `<원문 vendor>.capitalized` |
| `model` | 원문 그대로 |
| `connectionType` | `usb`/`network`/`scsi`/`fireWire`/`internalBus` |
| `usbVendorID` | **항상 nil → 키 생략** |
| `usbProductID` | **항상 nil → 키 생략** |
| `serialNumber` | **항상 nil → 키 생략** |
| `verifiedStatus` | **항상 `"compatibleTarget"`** |
| `driverVersion` | `"<backend> (SANE)"` |

`capitalized`는 Swift의 `String.capitalized`이며 **각 단어의 첫 글자를
대문자로, 나머지를 소문자로** 바꾼다.

```text
"PLUSTEK"  → "Plustek"
"Epson"    → "Epson"
"pie/reflecta" → "Pie/Reflecta"
```

Windows 구현에서 `ToTitleCase`나 첫 글자만 대문자로 바꾸는 구현을 쓰면
**다른 문자열**이 나온다. `"PLUSTEK"`이 `"PLUSTEK"`으로 남으면
`displayName`이 달라지고, 사용자에게 보이는 이름이 플랫폼마다 달라진다.

정확한 동작:

```text
공백/구두점으로 단어를 나눈다
각 단어: 첫 문자를 대문자로, 나머지를 소문자로
```

로케일 독립이어야 한다. 터키어 로케일에서 `i` → `İ` 문제를 피한다.
인바리언트 컬처를 명시한다.

### 3.3 실패

```text
stderr: "[negaflow-scanner-sane] detect 실패: <설명>\n"
exit 1
```

stdout에는 아무것도 쓰지 않는다.

### 3.4 부작용

현재 macOS는 `detect` 시작 시 `dll.conf` 레거시 복구를 수행하고 결과를
stderr에 남긴다. **Windows에서는 이 호출을 제거한다**
([environment-and-paths](../03-process-and-io/environment-and-paths.md) §8).

## 4. `capabilities <deviceId>`

### 4.1 호출

```text
argv: [실행파일, "capabilities", "<내부 장치 ID>"]
stdin: 선택. 있으면 한 JSON 문서.
```

**`<내부 장치 ID>`는 `plugin:sane:` 접두사가 제거된 값**이다. 즉
`sane-genesys:libusb:001:002`.

stdin 페이로드:

```json
{"deviceID":"sane-genesys:libusb:001:002","vendor":"Plustek","model":"OpticFilm 8200i"}
```

현재 구현의 처리:

```text
isatty(stdin) == 0 일 때만 읽는다
JSON 디코드 실패 → 무시하고 identity 힌트 없이 진행
deviceID != argv[2] → 힌트 무시
vendor 또는 model이 공백뿐 → 힌트 무시
```

**Windows에는 `isatty`가 없다.** 대응:

```text
GetFileType(GetStdHandle(STD_INPUT_HANDLE))
    FILE_TYPE_CHAR   → 콘솔. 읽지 않는다
    FILE_TYPE_PIPE   → 읽는다
    FILE_TYPE_DISK   → 읽는다
    FILE_TYPE_UNKNOWN → 읽지 않는다
```

호스트는 항상 파이프를 준다. 콘솔에서 수동 실행할 때 블록하지 않게
하려는 것이 원래 의도다.

**더 단순한 대안**: 항상 읽되 비블로킹으로 시도한다. 그러나 파이프에서
비블로킹 읽기는 Windows에서 번거롭다. `GetFileType` 방식이 낫다.

### 4.2 응답 — stdout에 한 줄

```json
{"resolutionsDPI":[600,1200,2400,3600,7200],"modes":["color","gray"],"bitDepths":[8,16],"sourceModes":["Transparency Adapter","Transparency Adapter Infrared"],"transparencyModes":["Transparency Adapter","Transparency Adapter Infrared"],"supportsPreview":true,"supportsTransparency":true,"supportsInfrared":true,"supportsMultiExposure":false,"supportsScanArea":true,"supportsPositionedScanArea":false,"brightnessRange":{"minimum":-100,"maximum":100,"step":1},"scanOriginXRange":{"minimum":0,"maximum":36.33},"scanOriginYRange":{"minimum":0,"maximum":44.25},"scanWidthRange":{"minimum":0,"maximum":36.33},"scanHeightRange":{"minimum":0,"maximum":44.25},"disabledReasons":{"multiExposure":"scanimage -A에 --scan-exposure-time이 없어 실제 다중노출을 켤 수 없습니다."},"minScanAreaWidthMM":0.1,"minScanAreaHeightMM":0.1,"minScanAreaOriginXMM":0,"minScanAreaOriginYMM":0,"maxScanAreaWidthMM":36.33,"maxScanAreaHeightMM":44.25,"maxScanAreaOriginXMM":0,"maxScanAreaOriginYMM":0,"scanAreaUnit":"millimeter","outputFormats":["tiff"],"capabilityToken":"eyJzY2hlbWFWZXJzaW9uIjoz..."}
```

이 예시도 §4.2.1 규칙을 따라 정리한 것이다. 원래 있던
`"contrastRange":null`, `"hardwareExposureRange":null`, 그리고 각 범위 안의
`"step":null`은 **실제로는 나오지 않는다** — `ScannerOptionRange`도
합성 인코더이고 `step`이 옵셔널이기 때문이다.

키 순서는 여기서도 보장되지 않는다.

### 4.2.1 nil 처리와 키 순서 — 실측 (2026-08-04)

**이 절의 이전 서술은 틀렸다.** Swift 6.3.3에서 실제 인코더 출력을
측정한 결과는 다음과 같다.

```text
합성(synthesized) Codable  → 옵셔널이 nil이면 키를 생략한다
                             (내부적으로 encodeIfPresent)
명시적 encode(to:)          → container.encode(옵셔널) 은 null 을 쓴다
```

측정에 쓴 실제 `PluginDevice`(nil 3개) 출력:

```json
{"devices":[{"driverVersion":"genesys (SANE)","displayName":"Plustek OpticFilm 8100","connectionType":"usb","id":"sane-genesys:libusb:001:002","vendor":"Plustek","model":"OpticFilm 8100","verifiedStatus":"compatibleTarget"}]}
```

두 가지가 드러난다.

1. **`usbVendorID` / `usbProductID` / `serialNumber` 키가 아예 없다.**
   `null`이 아니라 **생략**이다.
2. **키 순서가 선언 순서가 아니다.** `driverVersion`이 맨 앞에 왔다.
   알파벳 순도 아니다. `JSONEncoder`의 내부 해시 순서이며 **안정성을
   보장하지 않는다.**

따라서 wire 타입별 실제 형태는:

| 타입 | 인코더 | nil 필드 |
|---|---|---|
| `PluginDevice` | 합성 | **생략** |
| `PluginCapabilities` | 합성 | **생략** |
| `PluginScanEventV2` | 합성 | **생략** |
| `PluginAppliedScanOptionsV2` | **명시적 `encode(to:)`** | **`null` 명시** |

**마지막 행이 예외이고, 그 예외가 의도적이다.** `PluginAppliedScanOptionsV2`만
커스텀 인코더를 가진 이유가 이것이다 — `appliedOptions` 객체는 12키가
항상 전부 나온다.

호스트 문서가 그 예외를 요구한다. `10-scanner/protocol-contract.md` §9.1:

> `hardwareExposureTime`, `brightnessAdjustment`, `contrastAdjustment`은 값이
> optional이지만 **key는 필수**입니다. 미적용이면 JSON `null`을 씁니다.
> key omission은 decode failure입니다.

**이 문장의 적용 범위는 `appliedOptions` 하나뿐이다.** §9의 제목이
`appliedOptions`이고 §9.1이 그 required key 목록이다. 이것을 "모든 옵셔널
키는 항상 있어야 한다"로 읽으면 실측(§4.2.1 표)과 정면으로 충돌하고,
Windows 구현이 나머지 타입에도 `null`을 채우게 된다.

```text
appliedOptions 12키   → 항상 존재. nil이면 null.        (호스트가 요구)
그 밖의 모든 옵셔널    → nil이면 키 생략.                 (macOS 실측)
```

### 4.2.2 Windows에 대한 지시

```text
호스트는 "키 생략"을 nil로 받아들이고 있다. 지금 그렇게 동작 중이다.
Windows도 같은 형태를 낸다: 옵셔널이 없으면 키를 쓰지 않는다.
단 appliedOptions 안의 12키는 null로 명시한다.
```

**Windows가 "친절하게" 모든 키를 null로 채우면 macOS와 다른 JSON이 된다.**
호스트가 둘 다 받아들일 가능성이 높지만, I-5는 **같은 형태**를 요구한다.
추측하지 않고 macOS 형태를 따른다.

**이건 우리 쪽 추론만이 아니다.** negaflow 본체 windows_docs
`10-scanner/protocol-contract.md` §20(Windows port acceptance gate)이
gate 항목으로 이렇게 적고 있다:

> v1 omitted-vs-null serialization 일치

즉 **호스트 팀이 이 구분을 이미 인수 기준으로 삼고 있다.** 생략과 `null`을
바꿔 쓰면 gate에서 걸린다.

`disabledReasons`는 빈 딕셔너리일 수 있다(`{}`). 이건 nil이 아니므로 생략되지 않는다.

### 4.2.3 키 순서는 골든 전략을 바꾼다

`JSONEncoder`의 키 순서가 해시 기반이므로, **wire 출력을 바이트로
비교하는 골든은 성립하지 않는다.** Windows 구현(RapidJSON)은 자연히
선언 순서로 낼 것이고, 그러면 매번 불일치한다.

```text
wire/ 골든은 바이트가 아니라 파싱 후 의미 비교로 한다.
    - 키 집합이 같은가 (생략된 키 포함)
    - 각 값이 같은가
    - 배열 순서는 유지 (JSON 배열은 순서가 의미다)
    - 키 순서는 비교하지 않는다
```

바이트 비교를 굳이 하려면 양쪽 모두 정렬 출력을 써야 한다
(Swift `.sortedKeys`, RapidJSON은 직접 정렬). **그러면 호스트에 나가는
실제 바이트가 바뀌므로 wire 변경이다.** 하지 않는다.

→ [conformance-fixtures](conformance-fixtures.md) §4.9

### 4.3 `capabilityToken`

base64(UTF-8 JSON). 내용은
[capability-model](../02-frontend-contract/capability-model.md) §5.

base64 알파벳은 표준(RFC 4648 §4), 패딩 포함, 줄바꿈 없음.
Swift `Data.base64EncodedString()`의 기본이다.
**URL-safe 변형이나 패딩 생략을 쓰지 않는다.**

### 4.4 실패

```text
stderr: "[negaflow-scanner-sane] capabilities 실패: <설명>\n"
exit 1
```

## 5. `scan`

### 5.1 호출

```text
argv: [실행파일, "scan"]
stdin: 한 JSON 문서, 그 뒤 EOF
```

요청 스키마는
[exact-option-contract](../02-frontend-contract/exact-option-contract.md) §3.

**stdin을 끝까지 읽는다.** `capabilityToken`이 수십 KB이므로 한 번의
`read`로 끝나지 않는다.

### 5.2 이벤트 스트림 — stdout NDJSON

각 줄은 하나의 JSON 객체 + `\n`.

진행률 이벤트는 실제로 이런 형태다(키 순서는 보장되지 않는다):

```json
{"protocolVersion":2,"sequence":0,"type":"progress","requestID":"7A91B43D-90F8-41E2-B71D-04D17CD9E03B","phase":"warmingLamp","fraction":0.02,"message":"Warming lamp"}
```

`PluginScanEventV2`도 합성 인코더이므로 **nil 필드는 키 자체가 없다**
(§4.2.1). `width`/`height`/`path`/`resolutionDPI`/`bitDepth`/`irPath`/
`hasInfrared`/`warnings`/`appliedOptions`는 진행률 이벤트에 **나타나지 않는다.**

result 이벤트에서는 그 필드들이 값을 가지므로 나타나고, 그 안의
`appliedOptions`는 커스텀 인코더라 **12키가 전부** 있다(nil은 `null`).

stdout 예산(4 MiB)에 대한 영향: 진행률 이벤트 하나가 약 160 바이트이므로
넉넉하다. 진행률은 `scanimage`가 stderr에 낸 만큼만 나오므로 실제로는
수백 개다. 문제없다.

**단 다중 노출 12 패스 + 고해상도에서 `scanimage`가 진행률을 자주 내면
늘어날 수 있다.** 이식 시 이벤트 수를 계측하고, 필요하면 진행률 빈도를
제한한다(예: 0.5% 변화 또는 200 ms마다 최대 1회).

### 5.3 `sequence`

```text
0부터 시작해 1씩 증가
NSLock으로 직렬화
```

`UInt64`. Windows에서도 부호 없는 64비트.

### 5.4 `requestID`

요청의 `requestID`를 그대로 반사한다. 형식은 UUID 문자열.

Swift `UUID`의 인코딩은 **대문자 하이픈 형태**다:
`7A91B43D-90F8-41E2-B71D-04D17CD9E03B`.

Windows에서 `Guid.ToString()`은 **소문자**다:
`7a91b43d-90f8-41e2-b71d-04d17cd9e03b`.

**호스트가 문자열 비교를 하면 이것이 깨진다.** negaflow 본체 windows_docs
`10-scanner/protocol-contract.md` §20(Windows port acceptance gate)이
"UUID format/case 차이가 value comparison을 깨지 않음"을 gate 항목으로
명시한다. 즉 호스트는 대소문자 무시 비교를 해야 한다.

**그러나 어댑터가 의존하지 않는 것이 안전하다.**

```text
D-12  Windows 어댑터는 요청 문자열의 requestID를 파싱한 뒤
      재직렬화하지 않고, 받은 문자열을 그대로 반사한다.
```

이렇게 하면 형식 차이 문제가 원천적으로 사라진다. 단 요청이 유효한
UUID인지는 검증한다(비유효 시 거부).

현재 Swift 구현은 `UUID`로 파싱한 뒤 재직렬화하므로 대문자가 된다.
호스트가 소문자를 보냈다면 대문자로 돌아간다. **이미 대소문자 차이가
발생하고 있으며 호스트가 이를 견디고 있다는 뜻이다.** 그래도 Windows에서
원문 반사로 바꾸면 더 안전하다.

### 5.5 진행률 단계

```text
warmingLamp     0.02  "Warming lamp"
scanningRGB     0.08 ~ 0.92 (IR 있으면 0.78)   "Scanning"
warmingLamp     stale 재시도 시  "Re-detecting scanner"
scanningIR      0.86 → 0.80 ~ 0.96             "Scanning infrared"
processingNegative 0.82 (다중 노출) "Merging exposure brackets"
scanningRGB     다중 노출 각 패스 "Exposure bracket N/M @ <exposure>"
complete        1.0   "Scan complete" / "Multi-Exposure scan complete"
```

**다중 노출 각 패스의 구간은 계산식이 있다.** 같은 값을 내려면 그대로 옮긴다.

```text
passCount = 노출 계획 길이 (기본 3, NEGAFLOW_HWEXP_SAMPLES 에 따라 최대 12)

base(i)  = 0.08 + i * (0.70 / passCount)
구간(i)  = base(i) ... base(i) + 0.70 / passCount
메시지    "Exposure bracket \(i+1)/\(passCount) @ \(exposurePlan[i])"
```

즉 다중 노출은 0.08~0.78을 패스 수로 균등 분할하고, 0.82에서 병합,
1.0에서 완료다. 단일 패스 경로의 0.08~0.92(또는 IR 있으면 0.78)와 다르다.

`staleRetryProgress`는 그 패스의 `base(i)`이며, IR 패스에서는 0.86이다.

진행률 메시지 문자열은 영어다. 그대로 유지한다.
**단 오류 메시지는 한국어다**(§5.7) — 두 언어가 섞여 있는 것이 현재 계약이며,
양쪽 다 그대로 옮긴다.

그리고 **오류 메시지 문자열에 의존하는 코드가 있다.** genesys 첫 진행률
재시도가 `"첫 이미지 데이터"` 부분 일치로 판정하므로, 그 문구를 영어로
바꾸면 재시도가 조용히 사라진다
→ [timeouts-and-watchdog](../03-process-and-io/timeouts-and-watchdog.md) §3.5

### 5.6 종료 이벤트 — result

```json
{"type":"result","protocolVersion":2,"requestID":"…","sequence":42,"width":5102,"height":3401,"path":"C:\\Users\\…\\frame.tiff","resolutionDPI":3600,"bitDepth":16,"hasInfrared":false,"appliedOptions":{"deviceID":"sane-genesys:libusb:001:002","resolutionDPI":3600,"bitDepth":16,"colorMode":"color","filmType":"colorNegative","scanArea":{"originXMM":0,"originYMM":0,"widthMM":36,"heightMM":24},"infrared":false,"multiExposure":false,"hardwareExposureTime":null,"brightnessAdjustment":null,"contrastAdjustment":null,"outputRawTIFF":true}}
```

**바깥 이벤트와 `appliedOptions`가 서로 다른 규칙을 따르는 것이 여기서
눈에 보인다.** result는 `phase`/`fraction`/`message`를 넘기지 않으므로
그 키들이 **없고**, IR 없고 경고 없으면 `irPath`/`warnings`도 **없다**.
반면 `appliedOptions` 안에서는 `hardwareExposureTime` 등이 `null`로
**있다**(§4.2.1).

`warnings`는 **빈 배열이면 nil**로 보낸다:

```swift
warnings: result.warnings.isEmpty ? nil : result.warnings
```

빈 배열 `[]`을 보내지 않는다. nil이므로 **키 자체가 사라진다.**
이 동작을 유지한다.

`appliedOptions`는 커스텀 `encode(to:)`를 가지며 **12개 키를 전부 명시한다.**
옵셔널도 `encode`(not `encodeIfPresent`)를 쓰므로 nil이면 `null`이다.
negaflow 본체 windows_docs `10-scanner/protocol-contract.md` §9.1이
"key omission은 decode failure"라고 명시하므로
이 동작이 필수다.

`path`는 Windows 경로다. JSON 문자열에서 백슬래시가 `\\`로 이스케이프된다.
[encoding-and-json](encoding-and-json.md) §3.

### 5.7 종료 이벤트 — error

```json
{"type":"error","protocolVersion":2,"requestID":"…","sequence":3,"message":"unsupportedOption: 요청 resolution 3600dpi를 정확히 적용할 수 없습니다."}
```

**error 이벤트는 5개 키가 전부다.** `emit(type:"error", message:)`만
호출하므로 나머지 옵셔널은 전부 nil이고, 따라서 전부 생략된다.

메시지는 `ScannerError.errorDescription`이며 `"<code>: <message>"` 형태다.
message가 비면 코드만 나온다.

**메시지가 한국어다.** 호스트가 그대로 사용자에게 보여줄 수 있다.
다국어 제품에서 문제가 되지만 v2 wire에 코드 필드가 없다.

```text
Windows 구현: 같은 한국어 메시지를 낸다.
              내부적으로는 코드를 유지해 v3 전환을 준비한다.
```

`exit 1`을 반드시 함께 낸다. 호스트는 exit code와 이벤트를 모두 본다.

### 5.8 JSON 파싱 실패

```text
PluginScanRequestV2 디코드 실패:
    ScanRequestEnvelope로 다시 시도
    protocolVersion == 2 이고 requestID가 있으면:
        그 requestID로 error 이벤트 "scan 옵션 JSON 파싱 실패"
    아니면:
        stderr에 "[negaflow-scanner-sane] scan 옵션 JSON 파싱 실패\n"
    exit 1
```

이 이중 시도를 그대로 옮긴다. 호스트가 requestID를 알면 어떤 job이
실패했는지 상관시킬 수 있다.

## 6. 기타 서브커맨드

```text
repair-sane-config / tune-sane:
    stdout: "repair: <결과>\n"
            "active backends: <쉼표 구분>\n"
    exit 0

restore-sane:
    stdout: "restored from <경로>\n" 또는 "no backup to restore (<경로>)\n"
    exit 0

그 외 (help 포함):
    stderr: usage 텍스트
    exit 0        ← 주의: 0이다
```

**`default` 분기가 exit 0인 것은 현재 동작이다.** 알 수 없는 서브커맨드가
성공으로 보인다. Windows 이식에서 이것을 고칠지는 결정 사항이다.

```text
권장: 알 수 없는 서브커맨드는 exit 2로 바꾼다.
      단 "help"는 exit 0을 유지한다.
```

호스트는 이 세 서브커맨드를 호출하지 않으므로 위험이 낮다.
Windows에서는 `repair-sane-config`/`restore-sane`이 no-op다
([environment-and-paths](../03-process-and-io/environment-and-paths.md) §8).

## 7. stdout 오염 금지

```text
stdout에는 프로토콜 JSON만 쓴다.
BOM, 배너, 로그, 진행률 텍스트를 섞지 않는다.
사람이 읽을 진단은 stderr에.
```

Windows에서 추가로 주의할 것:

- **CRT가 stdout을 텍스트 모드로 열면 `\n`이 `\r\n`이 된다.**
  호스트가 NDJSON을 `\n`으로 분리하면 각 줄 끝에 `\r`가 남는다.
  JSON 파서가 후행 공백을 허용하면 동작하지만 의존하면 안 된다.

  ```text
  _setmode(_fileno(stdout), _O_BINARY)   ← 프로세스 시작 시 즉시
  ```

  또는 `WriteFile`로 직접 쓴다. **현재 macOS 구현이
  `FileHandle.standardOutput.write`로 직접 쓰므로 같은 계층을 쓴다.**

- 콘솔 코드 페이지가 UTF-8이 아니어도 상관없다. 파이프로 쓰므로
  콘솔 변환이 개입하지 않는다. 단 사용자가 콘솔에서 직접 실행하면
  깨져 보일 수 있다. `SetConsoleOutputCP(CP_UTF8)`을 호출할지는 선택이다.

## 8. 알려진 v2 한계 (플러그인 쪽 관점)

| 한계 | 영향 |
|---|---|
| error에 코드 필드가 없다 | 호스트가 재시도 가능성을 문자열로 판단할 수 없다 |
| `disabledReasons`가 현지화된 문자열이다 | 다국어 제품에서 문제 |
| `capabilityToken` 최대 길이가 wire에 없다 | 플러그인이 1 MiB로 자체 제한 |
| detect/capabilities 응답에 버전 필드가 없다 | 어느 프로토콜로 응답했는지 알 수 없다 |
| preview의 실제 획득 DPI를 보고할 방법이 없다 | provenance 공백 |
| IR artifact의 심도/색모델 의미가 약하다 | 어댑터가 자체 검증하지만 wire에 표현되지 않는다 |
| `usbVendorID`/`usbProductID`/`serialNumber`가 항상 null | 같은 모델 2대 구분 불가 |

이 목록은 negaflow 본체 windows_docs `10-scanner/protocol-contract.md`
§21(알려진 현재 한계)과 일치해야 한다. Windows 이식에서
**이 한계를 임의로 메우지 않는다.** v3 제안으로 분리한다.

## 9. v3 후보 (이 플러그인이 필요로 하는 것)

우선순위 순:

1. **구조화된 오류**: `{code, message, retryable, nativeDomain, nativeCode}`.
   `ScannerError.Code`가 이미 있으므로 즉시 채울 수 있다.
2. **`disabledReasons`의 코드화**: `{키: {code, message}}`.
3. **USB 식별자**: SANE가 제공하면 채운다.
4. **preview 실제 DPI**: `appliedOptions`에 `acquisitionDPI` 추가.
5. **취소 제어 채널**: stdout 프로토콜과 분리된 채널
   ([cancellation](../03-process-and-io/cancellation.md) §6).
6. **중간 파일 선언**: 다중 노출 중간 TIFF가 staging에 만들어진다는 것을
   호스트에 알린다(§10).

## 10. staging 디렉터리의 추가 파일

현재 어댑터는 다음을 staging에 만든다.

```text
<outputPath>                      RGB 결과
<outputPath의 base>.ir.<ext>      IR 결과 (요청 시)
```

그리고 다중 노출에서 **`/tmp`에** 중간 샘플을 만든다.

[environment-and-paths](../03-process-and-io/environment-and-paths.md) §7.1은
Windows에서 중간 파일을 staging 디렉터리로 옮길 것을 권한다(공간·정리·
성능 이유). 그러면 staging에 예상 밖의 파일이 생긴다.

```text
<outputPath의 base>.sample1.<ext>
<outputPath의 base>.sample2.<ext>
...
```

**호스트 계약을 확인해야 한다.** 호스트가 staging 디렉터리에 정확히
두 파일만 있을 것을 검증한다면 실패한다.

선택지:

| 안 | 내용 |
|---|---|
| A | 호스트가 staging의 추가 파일을 허용한다는 것을 확인하고 그대로 쓴다 |
| B | staging 아래 하위 디렉터리를 만든다: `<staging>\.negaflow-sane-work\` |
| C | `%TEMP%`를 쓴다(현재 macOS와 같음). 공간·성능 문제를 감수 |

**권장: B.** 호스트가 두 파일을 검증한다면 하위 디렉터리는 방해하지 않고,
정리도 staging 삭제로 함께 된다.

이 결정은 [open-questions](../99-plan/open-questions.md) Q-3이 소유한다.

## 11. 이식 체크리스트

- [ ] 매니페스트에서 `executable`만 바뀐다
- [ ] `id`가 `sane`이다
- [ ] `capitalized` 동작이 동일하고 로케일 독립이다
- [ ] `verifiedStatus`가 항상 `compatibleTarget`
- [ ] `driverVersion`이 `"<backend> (SANE)"`
- [ ] USB/serial 필드가 항상 null
- [ ] `isatty` 대응(`GetFileType`)
- [ ] nil 옵셔널은 **키를 생략한다** (§4.2.1 — macOS 실측과 일치)
- [ ] `appliedOptions` 안의 12키는 `null`로라도 **전부 명시된다**
- [ ] `warnings`가 빈 배열일 때 null(= 키 생략)
- [ ] wire 골든이 바이트가 아니라 의미 비교다 (§4.2.3)
- [ ] `sequence`가 0부터 1씩
- [ ] `requestID`를 원문 반사
- [ ] base64가 표준 알파벳 + 패딩
- [ ] 진행률 단계와 메시지가 동일
- [ ] 오류 메시지 형식 `"<code>: <message>"`
- [ ] JSON 파싱 실패의 이중 시도
- [ ] stdout이 바이너리 모드이고 `\n`만 쓴다
- [ ] stdout에 다른 것이 섞이지 않는다
- [ ] 중간 파일 위치 결정이 반영됐다
