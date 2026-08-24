# macOS 구현 인벤토리

기준일: 2026-08-04
최종 상태 검토: 2026-08-25
기준 커밋: c554aaf
상태: 사실 기록 — Windows 설계의 입력
목적: Windows 이식이 보존해야 할 **현재 동작**을 파일 단위로 확정한다

이 문서는 설계가 아니다. 지금 저장소에 실제로 있는 코드가 무엇을 하는지만 적는다.
**왜** 그렇게 되어 있는지는 [field-lessons](../10-lessons/field-lessons.md)와
[driver-option-reference](../10-lessons/driver-option-reference.md)에 있다.
다른 문서가 "현재 macOS는 X한다"라고 말할 때 그 근거는 여기다. 이 문서와 코드가
어긋나면 코드가 옳고 이 문서를 고친다.

## 1. 산출물

| 산출물 | 정체 | 비고 |
|---|---|---|
| `negaflow-scanner-sane` | 단일 CLI 실행 파일 | universal(arm64 + x86_64), Developer ID 서명, notarize |
| `manifest.json` | plugin 매니페스트 | `schemaVersion:1`, `protocolVersion:2`, `id:"sane"` |
| 설치 위치 | `~/Library/Application Support/negaflow/Plugins/sane/` | user scope 전용, machine scope 없음 |

플러그인은 SANE를 링크하지 않는다. 별도로 설치된 `scanimage` 실행 파일을 자식
프로세스로 띄우고 그 표준 출력·표준 오류를 파싱한다. 이 사실이 GPL 경계와
Windows 이식 난이도를 동시에 결정한다([gpl-compliance](../07-distribution/gpl-compliance.md)).

## 2. 소스 트리

### 2.1 `Sources/negaflow-scanner-sane` — 프로토콜 어댑터 (341행)

| 파일 | 행 | 역할 |
|---|---:|---|
| `main.swift` | 278 | 서브커맨드 디스패치, stdin/stdout JSON, 이벤트 emitter, 취소 신호 포워딩 |
| `WireProtocol.swift` | 63 | `PluginDevice` / `PluginDetectResponse` / `PluginCapabilityRequest` / `PluginCapabilities` |

`main.swift`가 소유하는 사실:

- 서브커맨드는 `detect`, `capabilities <deviceId>`, `scan`, `repair-sane-config`,
  `tune-sane`, `restore-sane`, 그 외는 usage를 stderr에 출력.
- `emitLine`은 한 줄 JSON + `\n`을 stdout에 직접 write 한다. 버퍼링에 기대지 않는다.
- `ProtocolV2Emitter`가 `requestID`와 `sequence`를 `NSLock`으로 직렬화한다.
  `sequence`는 0부터 1씩 증가한다.
- `detect`는 실행 시 `SaneConfigTuner.hasLegacyFiltering`을 확인하고 과거 버전이
  꺼둔 백엔드를 복구한 뒤 그 사실을 stderr에 남긴다.
- `capabilities`는 stdin이 tty가 아닐 때만 읽는다(`isatty(fd) == 0`). 파싱 실패는
  치명적이지 않으며 identity 힌트 없이 진행한다.
- `scan`은 stdin 전체를 읽어 `PluginScanRequestV2`로 디코드한다. 디코드가 실패해도
  `protocolVersion`/`requestID`만 뽑히면 그 requestID로 v2 error 이벤트를 낸다.
- `scan` 성공 직전에 어댑터가 한 번 더 계약을 확인한다: 결과 경로 == 요청
  `outputPath`, 결과 dpi == 요청 dpi, 결과 심도 == 요청 심도, 결과 IR 유무 ==
  요청 IR. 하나라도 다르면 `ioFailure`로 실패시킨다.
- 오류는 전부 `emitter.emit(type:"error")` + `exit(1)`.

취소 경로:

```swift
[SIGTERM, SIGINT] → signal(SIG_IGN) → DispatchSource.makeSignalSource
                  → backend.cancelScan()
```

즉 **호스트의 종료 신호를 자기가 띄운 `scanimage`에 전달하는 것**이 취소의 전부다.
`scanimage`는 SIGTERM을 받으면 `sane_cancel()`을 호출해 장치 점유를 푼다.
Windows에는 이 신호 의미가 없다 → [cancellation](../03-process-and-io/cancellation.md).

### 2.2 `Sources/SANEPluginCore` — 백엔드 (4,581행)

| 파일 | 행 | 역할 | 이식 난이도 |
|---|---:|---|---|
| `SANEBackend+Discovery.swift` | 1,181 | 장치 목록 파싱, 주소 재해석, media 해석, 지오메트리 | 상 (순수 로직, 그대로 이식) |
| `SANEBackend+ScanExecution.swift` | 874 | 정확 옵션 검증, 인자 생성, 획득 재시도, IR 패스, 결과 검증 | 상 |
| `SANEBackend+Process.swift` | 489 | 자식 프로세스, 파이프 drain, watchdog, 진행률 파싱, 취소 | **최상 (전면 재작성)** |
| `ScannerModel.swift` | 356 | 도메인 타입 | 하 |
| `SANEBackend+Capabilities.swift` | 247 | `-A` 덤프 → `ScannerCapabilities` | 중 |
| `PluginProtocolV2.swift` | 224 | v2 요청/적용/이벤트 타입과 검증 | 하 |
| `SANEBackend+ExposureMergingCore.swift` | 217 | 노출 정규화·병합 픽셀 수학 | 중 (수치 동등성 필요) |
| `SANEBackend+Alignment.swift` | 203 | 패스 간 정수 오프셋 정렬 | 중 (수치 동등성 필요) |
| `SaneOptionDump.swift` | 171 | `-A` 텍스트 파서 | 하 |
| `SANEBackend.swift` | 170 | 타입 정의, 캐시 필드, `MediaSelection` | 하 |
| `SANEBackend+Environment.swift` | 119 | `scanimage` 탐색, 환경 변수 구성 | **최상 (전면 재작성)** |
| `SaneConfigTuner.swift` | 123 | `dll.conf` 레거시 복구 | 중 (경로 의미가 다름) |
| `SANEBackend+ExposureMerge.swift` | 93 | TIFF 로드 → 병합 → TIFF 쓰기 | **상 (Core Image 의존)** |
| `SANEBackend+TIFFWriting.swift` | 83 | RGBAf 렌더, RGB16 TIFF 쓰기 | **상 (Core Image/ImageIO 의존)** |
| `TIFFLoader.swift` | 31 | 스캐너 TIFF 로드 | **상 (ImageIO 의존)** |

플랫폼 의존이 실제로 박혀 있는 곳은 셋뿐이다.

1. `Foundation.Process` / `Pipe` / `DispatchSource` / POSIX 신호 → 3장
2. `CoreImage` / `CoreGraphics` / `ImageIO`(CGImageSource, CGImageDestination) → 4장
3. 경로·환경 변수(Homebrew keg, `SANE_CONFIG_DIR`, `LD_LIBRARY_PATH`, `~/Library`) → 3장·7장

나머지 약 3,000행은 문자열 파싱과 산술이며 언어만 바꾸면 된다.

**단 파일이 곧 모듈은 아니다.** 위 표의 큰 파일 3개는 각각 여러 모듈에
걸쳐 있다. 함수 단위 배정은 [porting-map](../06-build/porting-map.md)에 있다.

### 2.3 `Tests/SANEPluginCoreTests` (4,460행)

| 파일 | 행 | 무엇을 고정하는가 |
|---|---:|---|
| `SANEBackendTests.swift` | 880 | 덤프 파싱, media 해석, 인자 생성 전반 |
| `SANEBackendEnvironmentTests.swift` | 801 | `scanimage` 선택, 환경 구성, config dir 우선순위 |
| `SANEBackendProcessOwnershipTests.swift` | 592 | 세션 소유권, 동시 실행 거부, 취소, 좀비 방지 |
| `VirtualScanimageFixture.swift` | 405 | 실제 자식 프로세스로 동작하는 가짜 `scanimage` |
| `SANEBackendVirtualScannerTests.swift` | 358 | 모델별 가상 스캐너 end-to-end |
| `PluginProtocolV2Tests.swift` | 314 | v2 요청 검증과 적용 옵션 인코딩 |
| `SANEBackendDepthCapabilityTests.swift` | 284 | 고정 심도/비활성 `--depth` 판정 |
| `SANEBackendMultiSampleTests.swift` | 219 | 다중 샘플 병합 |
| `SANEBackendScanAreaGeometryTests.swift` | 212 | mm/pel/모서리 좌표 지오메트리 |
| `SANEBackendHardwareExposureTests.swift` | 151 | 노출 브래킷 계획과 병합 |
| `ReleaseScriptContractTests.swift` | 140 | 릴리스 스크립트 계약 |
| `SaneConfigTunerTests.swift` | 55 | `dll.conf` 레거시 복구 (Windows에서는 D-05로 no-op) |
| `SANEBackendTestSupport.swift` | 49 | 공용 헬퍼 |

`VirtualScanimageFixture`는 Windows 이식에서 **가장 값싼 승리**다. 이 픽스처가
내는 `-L`/`-f`/`-A` 텍스트와 TIFF는 실제 백엔드가 무엇을 출력하는지에 대한
현재 저장소의 유일한 기계 판독 기록이다. 언어 중립 corpus로 뽑아내면 Windows
구현이 같은 입력에 같은 판정을 내는지 바로 비교할 수 있다
([conformance-fixtures](../05-protocol/conformance-fixtures.md)).

### 2.4 배포 자산

| 경로 | 역할 |
|---|---|
| `scripts/build-release.sh` | provenance 검사 → `swift test` → arm64/x86_64 빌드 → `lipo` → dSYM → 서명 → 패키징 → 검증 |
| `scripts/package-release.sh` | ZIP/dSYM/소스 아카이브/SHA256SUMS 생성, arch·UUID 일치 확인 |
| `scripts/sign-plugin.sh` | Developer ID Application, hardened runtime 강제 |
| `scripts/notarize-plugin.sh` | `notarytool submit --wait`, `spctl --assess` |
| `scripts/create-source-archive.sh` | GPL 대응 소스 tarball(재현 가능하도록 `gzip -n`, `COPYFILE_DISABLE`) |
| `scripts/build-installer.sh` (325행) | PKG/DMG 4종(standard/coolscan × arm64/universal) |
| `scripts/verify-installer.sh` (221행) | PKG 확장·DMG 마운트 후 내용물 검사 |
| `scripts/verify-provenance.py` (179행) | 네이티브 코드·SANE 링크·번들 금지 규칙 자동 검사 |
| `scripts/verify-release.sh` (84행) | 릴리스 산출물 디렉터리 검증. Windows `verify-release.ps1`의 원본 |
| `scripts/install-release.sh` (46행) | 릴리스 ZIP 안에서 사용자 플러그인 디렉터리로 설치(`NEGAFLOW_PLUGINS_DIR` 존중) |
| `scripts/install-patched-sane.sh` (49행) | Coolscan 경로: 패치된 SANE keg를 사용자 Mac에서 빌드·설치 |
| `install.sh` (54행) | 개발용. 빌드 후 플러그인 디렉터리에 설치 |
| `Installer/Distribution.xml` | Homebrew 필요 여부 판정, CLT 설치 확인, 최소 OS |
| `Installer/Scripts/postinstall*` | root에서 콘솔 사용자로 강등해 brew 설치 → 플러그인 설치 |
| `Installer/Scripts/install-plugin-user.sh` (63행) | postinstall이 강등 후 호출하는 실제 설치 단계 |
| `Formula/sane-backends-negaflow.rb` | SANE 1.4.0 + coolscan2/3 word-list 수정 + epson2 높이 수정 |

**패치된 SANE는 배포물에 들어 있지 않다.** `install-patched-sane.sh`와
Coolscan 설치 프로그램이 **사용자 기계에서 빌드**한다. 이것이 macOS에
SANE 바이너리 재배포 의무가 없는 이유이며, Windows에서 D-06(자체 빌드
런타임 포함)을 택하는 순간 그 의무가 생긴다
([gpl-compliance](../07-distribution/gpl-compliance.md) §1~2).

## 3. 프로토콜 계약 (현재 구현이 실제로 보내는 것)

### 3.1 `detect`

입력 없음. 출력 한 줄:

```json
{"devices":[{"driverVersion":"genesys (SANE)","displayName":"Plustek OpticFilm 8100",
"connectionType":"usb","id":"sane-genesys:libusb:001:002","vendor":"Plustek",
"model":"OpticFilm 8100","verifiedStatus":"compatibleTarget"}]}
```

**키 순서와 누락에 주의한다.** `usbVendorID`/`usbProductID`/`serialNumber`는
nil이라 **키 자체가 없고**, 키 순서는 선언 순서가 아니다(둘 다 2026-08-04
실측) → [wire-contract](../05-protocol/wire-contract.md) §4.2.1

고정된 사실:

- `id`는 항상 `sane-` + SANE 장치명 전체.
- `vendor`는 `.capitalized`, `displayName`은 `"<vendor> <model>"`.
- `verifiedStatus`는 **항상** `compatibleTarget`. 백엔드 이름이나 모델명으로
  `verified`를 만들지 않는다.
- `driverVersion`은 `"<backend> (SANE)"`.
- `usbVendorID`/`usbProductID`/`serialNumber`는 현재 **항상 nil**이며,
  wire에서는 **키가 생략된다**. `scanimage`가 그 값을 주지 않기 때문이다.

### 3.2 `capabilities <deviceId>`

stdin(선택): `{"deviceID":..., "vendor":..., "model":...}`.
`deviceID`가 argv와 같고 vendor/model이 비어 있지 않을 때만 identity 힌트로 쓴다.

출력은 `PluginCapabilities` 한 줄. `capabilityToken`은 base64(JSON)이며 내용은
`SANECapabilitySnapshot`이다:

```text
schemaVersion(=3), deviceID, backend, acquisitionDevice,
deviceIdentity{vendor,model}, deviceType, optionDump(원문 전체), validatedMode
```

호스트는 이것을 해석하지 않는다. 다음 scan 요청에 그대로 돌려준다.
**옵션 덤프 원문이 통째로 들어 있으므로 토큰은 수십 KB가 될 수 있다.**
현재 상한은 1 MiB(`capabilityToken.utf8.count <= 1_048_576`).

### 3.3 `scan`

stdin에 `PluginScanRequestV2` 한 건. stdout에 NDJSON:

```text
{"type":"progress",...,"sequence":0,"phase":"warmingLamp","fraction":0.02,...}
{"type":"progress",...,"sequence":1,"phase":"scanningRGB","fraction":0.31,...}
...
{"type":"result",...,"sequence":N,"width":...,"appliedOptions":{...}}
```

`appliedOptions.scanArea`는 요청 복사가 아니라 **실제로 `scanimage`에 보낸
영역**이다(epson2 정수 mm 정렬 때문에 높이가 1 mm 미만 달라질 수 있다).

## 4. 요청 검증 (`PluginScanRequestV2.validatedOptions`)

시작 전에 무조건 거부하는 것:

| 조건 | 이유 |
|---|---|
| `protocolVersion != 2` | v1 미지원 |
| `deviceID` 공백 | 라우팅 불가 |
| `bitDepth ∉ {8,16}` | 도메인 밖 |
| `colorMode ∉ {color,gray}` | lineart/infrared는 주 모드로 미지원 |
| `filmType` 미인식 | 도메인 밖 |
| scanArea 비유한/음수 원점/비양수 크기 | 기하 불가 |
| `hardwareExposureTime <= 0` | 도메인 밖 |
| brightness/contrast 비유한 | 도메인 밖 |
| `outputPath`가 정규화된 절대 경로가 아님 | 호스트 staging 계약 |
| `capabilityToken > 1 MiB` | 자원 방어 |
| preview인데 dpi≠0 / IR / 다중노출 / 노출시간 / rawTIFF | preview 계약 |
| full인데 dpi<=0 | 계약 |
| full인데 `outputRawTIFF != true` | 이 플러그인은 raw TIFF만 낸다 |
| 다중노출 + 단일 `hardwareExposureTime` 동시 | 상호 배타 |

Windows 구현은 이 표를 **한 항목도 빼지 않고** 같은 순서로 재현해야 한다.
[exact-option-contract](../02-frontend-contract/exact-option-contract.md)가 정본이다.

## 5. 실행 계약 (`SANEBackend`가 `scanimage`를 어떻게 부르는가)

### 5.1 호출 형태

| 목적 | 인자 |
|---|---|
| 장치 목록(우선) | `-f "%d\t%v\t%m\t%t%n"` |
| 장치 목록(후퇴) | `-L` |
| 옵션 덤프 | `-A -d <dev>` (+ `--source`/`--mode`/`--resolution`/`--depth`/`--preview=yes`/`--color-correction`/`--gamma-correction`) |
| 획득 | `-d <dev> -p [옵션…] --format=tiff` |

획득 인자는 `makeScanimageArgs`가 만든다. 순서가 고정돼 있다:

```text
-d <dev> -p
[--source S] [--mode M]
(main pass만) [--advance=no] [--color-correction C] [--gamma-correction G]
              [--film-type|--type|--negative=…] [--brightness=] [--contrast=]
              [--scan-exposure-time=] [--clean-image=yes] [--preview=yes]
[--resolution N] [--depth N]
[--tl-x/--tl-y/--br-x/--br-y]  또는  [-l -t]
[-x -y]
--format=tiff
```

**없는 옵션에는 플래그를 보내지 않는다.** coolscan3에 `--mode`를 넘기면
`scanimage`가 즉시 실패하기 때문이다. 이 규칙이 `MediaSelection`의 모든
`hasXxxOption` 필드가 존재하는 이유다.

### 5.2 표준 출력의 의미

- `-p`는 진행률을 **stderr**에 `Progress: 12.3%` 형태로 낸다.
- `--format=tiff` 결과 이미지는 **stdout**으로 나오며, 플러그인은 stdout을
  파일 핸들로 직접 리다이렉트한다(파이프가 아니다).
- 따라서 획득 실행에서 stdout은 이미지 바이트이고 stderr만 파싱 대상이다.
  목록·덤프 실행에서는 stdout이 텍스트이고 파이프로 읽는다.

이 비대칭은 Windows에서도 그대로 유지된다.

### 5.3 진행률 파싱

```text
records:  (?i)progress\s*:?\s*(?:\([^)]*\)|[0-9]{1,3}(?:[.,][0-9]+)?\s*%)
fraction: (?i)progress\s*:?\s*([0-9]{1,3}(?:[.,][0-9]+)?)\s*%
```

- 마지막 매치의 퍼센트를 0…1로 클램프해 `progressRange`에 선형 매핑한다.
- 콤마 소수점을 받아들이지만 환경은 `LC_ALL=C`로 고정한다.
- 버퍼는 마지막 160자만 유지한다(잘린 레코드 재조립용).
- 레코드 **개수 증가**가 "진행이 있었다"의 판정이다. 이 값이 watchdog과
  stale-retry 판단에 쓰인다.

### 5.4 타임아웃

| 이름 | 기본 | 의미 |
|---|---:|---|
| `utilityProcessTimeout` | 180 s | `-L`/`-f`/`-A` 한 번의 상한 |
| `acquisitionFirstProgressTimeout` | 180 s | 첫 진행률까지 |
| `acquisitionProgressStallTimeout` | 180 s | 마지막 진행률 이후 유휴 |

**총 스캔 시간에는 상한이 없다.** 진행률이 계속 오는 한 몇 시간짜리 7200 dpi
스캔도 허용한다. `pieusb`는 watchdog 자체를 켜지 않는다
(`usesAutomaticAcquisitionWatchdog(backend:) == backend != "pieusb"`).

### 5.5 세션 소유권

- 한 백엔드 인스턴스에서 scan 세션은 하나뿐(`beginScanSession`).
- 이름·경로로 전역 프로세스를 찾아 죽이지 않는다. 자기가 만든 `Process`
  인스턴스만 취소 대상이다.
- `cancelScan()`은 `terminate()` → 0.5 s → 여전히 살아 있으면 `SIGKILL`.

### 5.6 USB 주소 실측 사실

`SANEBackend+Discovery.swift`의 주석에 남은 실측(Plustek OpticFilm 8100 +
sane-backends 1.4.0):

- 장치를 **열 때마다** libusb 주소가 바뀐다(`002:001 → 002:002 → 002:001`).
- 목록 조회(`-L`/`-f`)만으로는 주소가 바뀌지 않는다.
- 죽은 주소로 여는 시도는 하드웨어에 닿기 전에 즉시 실패한다(실측 약 11 ms).

따라서 `noteDeviceOpened()`가 주소 기반 선택자를 만료시키고, 5초 TTL 캐시와
`genesys`/`epson2`에 한한 주소 없는 선택자(`-d genesys`)가 존재한다.
이 실측은 macOS USB 스택에서 얻은 것이며 Windows에서 그대로 성립하는지는
**미검증**이다([usb-transport](../01-sane-runtime/usb-transport.md)).

## 6. 백엔드별 특수 처리 (모델명이 아니라 옵션에서 감지)

| 백엔드 | 처리 | 코드 위치 |
|---|---|---|
| `genesys` | capability를 `--mode Color`로 읽음; 단일 투과 소스면 덤프 재사용(추가 open 회피); 16-bit에서 brightness/contrast 비활성 취급; 첫 진행률 타임아웃 시 1회 재시도 | Discovery, ScanExecution |
| `epson2` | `--color-correction None`, `--gamma-correction Gamma=1.0|User defined`; `br_y` 정수 mm 절삭 보정(`epson2AlignedHeightMM`); `--depth`가 Lineart에서 비활성 | Discovery |
| `coolscan2`/`coolscan3` | `--negative=no`(장치 반전 끔); `--mode` 없음; pel 단위 지오메트리; `--infrared`는 RGBI 한 프레임이라 IR 채널로 보고하지 않음 | Discovery, Capabilities |
| `coolscan` | `--type` 원문 유지(`preserveRawCoolscan`) | Discovery |
| `pieusb` | `--advance=no` 필수(없으면 실패); 재시도 금지(1회만); watchdog 끔; `--clean-image`는 IR 채널이 아님 | ScanExecution, Process |
| `pie` | `--depth` 없으면 8-bit 고정으로 판정 | Capabilities |

이 표는 Windows에서도 **그대로** 유지된다. 백엔드 동작은 OS가 아니라 SANE
구현이 결정하기 때문이다. 단, 각 항목의 실기 재확인은 별도다
([validation-matrix](../09-hardware/validation-matrix.md)).

## 7. 이미징 의존

| 연산 | 현재 API | Windows 대체 후보 |
|---|---|---|
| TIFF 검증(단일 이미지·타입·크기·심도·색모델) | `CGImageSource*` | WIC + libtiff 교차 |
| TIFF 크기 조회 | `CGImageSourceCopyPropertiesAtIndex` | 동일 |
| 스캐너 TIFF 로드(linear sRGB 재해석) | `CIImage(cgImage:options:)` | 직접 버퍼 로드 |
| RGBAf 렌더 | `CIContext.render(toBitmap:format:.RGBAf)` | 직접 변환 |
| RGB16 TIFF 쓰기 | `CGImage` + `CGImageDestination` | libtiff |
| 반투명/색공간 변환 | Core Image working color space | 명시적 선형 변환 |

`CIContext.render`가 실제로 무엇을 하는지가 수치 동등성의 핵심 위험이다.
현재 코드는 16-bit TIFF를 `linearSRGB`로 **재해석**(변환이 아님)해 로드하고
`.RGBAf`로 렌더한다. Windows에서 같은 결과를 내려면 감마 변환이 개입하지
않는다는 것을 fixture로 증명해야 한다
([numerical-parity](../04-imaging/numerical-parity.md)).

## 8. 환경 구성 (현재 macOS)

```text
LC_ALL=C, LANG=C                      # 영문 옵션명·"." 소수점 계약
PATH=<scanimage dir>:/opt/homebrew/bin:…:<기존>
SANE_CONFIG_DIR=<선택한 keg>/etc/sane.d   (없으면 환경변수 → /opt/homebrew → /usr/local → /etc)
LD_LIBRARY_PATH=<선택한 keg>/lib/sane:<기존>
SANE_DEFAULT_DEVICE=<캐시된 선택자>        (유효할 때만)
```

`scanimage` 탐색 순서:

```text
NEGAFLOW_SCANIMAGE_PATH
/opt/homebrew/opt/sane-backends-negaflow/bin/scanimage
/usr/local/opt/sane-backends-negaflow/bin/scanimage
/opt/homebrew/bin/scanimage
/usr/local/bin/scanimage
/usr/bin/scanimage
"scanimage"  (PATH)
```

**패치된 keg를 최우선**으로 두고, 같은 keg의 `etc/sane.d`와 `lib/sane`을 함께
쓰는 것이 핵심이다. stock 설정이 섞이면 Coolscan 패치가 우회된다.
Windows에는 keg 개념이 없으므로 이 우선순위 자체를 다시 설계해야 한다
([environment-and-paths](../03-process-and-io/environment-and-paths.md)).

## 9. 환경 변수 (플러그인이 읽는 것)

| 변수 | 의미 | 범위 |
|---|---|---|
| `NEGAFLOW_SCANIMAGE_PATH` | `scanimage` 절대 경로 강제 | 진단·테스트 |
| `NEGAFLOW_HWEXP_SAMPLES` | 노출 단계당 샘플 수(1…4, 기본 1) | 실험 |
| `NEGAFLOW_KEEP_MULTIPASS` | 다중 패스 중간 TIFF 보존 | 진단 |
| `SANE_CONFIG_DIR` | 명시 지정 시 존중(단, 같은 keg 설정이 우선) | 사용자 |

## 10. Windows에서 사라지거나 반드시 바뀌는 것

| 현재 | Windows |
|---|---|
| Homebrew, keg, `brew install sane-backends` | 없음. SANE 런타임 전달 방식 자체가 미결 |
| `.pkg`/`.dmg`, Distribution.xml, notarization | MSI/MSIX + Authenticode |
| `~/Library/Application Support/negaflow/Plugins` | `%LOCALAPPDATA%\Negaflow\Plugins` |
| POSIX 신호 취소 | 신호 없음 — 새 취소 설계 필요 |
| `dll.conf` 주석 복구 | SANE 설정 파일이 존재하는지 자체가 경로에 따라 다름 |
| `codesign`/`spctl` | `signtool`/`WinVerifyTrust` |
| universal binary(lipo) | x64/ARM64 **별도 산출물** |
| Core Image/ImageIO | libtiff(+WIC 교차 검증) |
| `/tmp` | 호스트가 지정한 staging 디렉터리 |

## 11. 이 인벤토리가 증명하지 않는 것

- Windows에서 `scanimage`가 실행 가능한지
- Windows에서 어떤 SANE 백엔드가 USB 장치를 열 수 있는지
- macOS에서 관측한 USB 주소 변동이 Windows에서도 일어나는지
- Core Image 렌더 결과를 Windows에서 비트 단위로 재현할 수 있는지
- 현재 실기 검증 상태(README의 표는 SANE 1.4 문서 상태이지 개별 유닛 검증이 아니다)

이 다섯 가지가 이식 프로젝트의 실제 위험이며, 각각
[availability](../01-sane-runtime/availability.md),
[usb-transport](../01-sane-runtime/usb-transport.md),
[numerical-parity](../04-imaging/numerical-parity.md),
[validation-matrix](../09-hardware/validation-matrix.md)가 소유한다.
