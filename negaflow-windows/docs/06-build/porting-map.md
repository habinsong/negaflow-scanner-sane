# 이식 대응표 — Swift 파일이 어느 C++ 모듈로 가는가

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 구현 계획
목적: 4,922행의 Swift 소스를 **함수 단위로** 목적지에 배정한다

관련 문서:

- [macos-inventory](../00-overview/macos-inventory.md) — 파일별 역할과 난이도
- [toolchain-and-layout](toolchain-and-layout.md) §4.1 — CMake 타깃 정의
- [roadmap](../99-plan/roadmap.md) — M2~M5 작업 단위
- [conformance-fixtures](../05-protocol/conformance-fixtures.md) — 각 함수의 골든

## 0. 왜 이 표가 필요한가

`macos-inventory`는 **파일별 난이도**를 주고 `toolchain-and-layout`은
**모듈 이름**을 준다. 그 사이가 비어 있었다.

실제 문제는 이렇게 생긴다:

```text
SANEBackend+Discovery.swift  1,181행
    → src/sane/device_list.cpp ?
    → src/sane/media.cpp ?
    → src/sane/capabilities.cpp ?
    → 셋 다. 그리고 프로세스 호출도 섞여 있다.
```

**가장 큰 파일 3개가 전부 여러 모듈에 걸쳐 있다.** 그래서 "파일을 옮긴다"가
성립하지 않고, 함수 단위 배정이 필요하다.

## 1. 목적지 모듈

```text
sane_logic  (순수, 의존 0)          ← M2. Win32도 libtiff도 링크하지 않는다
    util/numeric
    sane/option_dump
    sane/device_list
    sane/media
    sane/capabilities
    sane/validate
    sane/args

process     (Win32)                 ← M3. 전면 재작성
    process/child
    process/environment
    process/watchdog
    process/cancel

imaging     (libtiff)               ← M4. 수치 동등성 필요
    imaging/tiff_contract           ✅ 태그 판정. 순수 — libtiff 링크 안 함
    imaging/tiff_io                 ✅ libtiff 읽기/쓰기. 이 타깃만 libtiff 를 안다
    imaging/align                   ✅ 이식 완료 — 순수, libtiff 링크 안 함
    imaging/merge                   ✅ 이식 완료 — 순수, libtiff 링크 안 함

wire        (RapidJSON)             ← M5
    wire/request                    ✅ 1단계 검증. 순수 — RapidJSON 링크 안 함
    wire/json                       ✅ 방출. 직접 쓴다(키 순서 통제)
    wire/event                      ✅ 이벤트/적용옵션 JSON 형태
    wire/protocol                   ✅ 응답 DTO 인코딩 / ⬜ 실행부
    wire/emitter                    ✅ 줄 생성
    wire/writer                     ✅ 부분 쓰기 루프 / ⬜ WriteFile 어댑터(Win32)
    wire/parse                      ✅ 요청 디코딩. **이 타깃만 RapidJSON 을 안다**
    wire/cli                        ✅ 서브커맨드 디스패치 판정
    응답 조립                        ⬜ 장치 열거 → DTO. 프로세스 실행이 필요하다
    main.cpp                        ⬜ 위 판정을 받아 실행만 한다
```

**`sane_logic`이 Win32를 링크하지 않는다는 것이 계약이다**
(toolchain-and-layout §4.1). 이 표에서 `sane_logic` 열에 배정된 함수가
`#include <windows.h>`를 필요로 하면 배정이 틀린 것이다.

## 2. 파일별 배정

### 2.1 `SANEBackend+Discovery.swift` (1,181행) — 4개 모듈로 분해

**가장 큰 파일이자 가장 많이 쪼개지는 파일이다.**

| 함수 | 목적지 | 순수 | 비고 |
|---|---|:---:|---|
| `backendName(of:)` | `sane/device_list` | ✓ | 첫 `:` 앞. `net:`은 특별 취급 안 함(D-03) |
| `supportsStableBackendSelector` | `sane/device_list` | ✓ | genesys, epson2만 |
| `connectionType(of:)` | `sane/device_list` | ✓ | `:net:` / `:scsi:` / `/dev/sg` 판정 |
| `isDedicatedFilmBackend` | `sane/device_list` | ✓ | coolscan·pie 계열 5종 |
| `parseDeviceList` | `sane/device_list` | ✓ | `-L` 정규식 |
| `parseFormattedDeviceList` | `sane/device_list` | ✓ | `-f` 탭 구분 |
| `sameIdentity` / `normalizedIdentityComponent` | `sane/device_list` | ✓ | I-9 동일 장치 판정 |
| `resolveMedia(dump:options:...)` **static** | `sane/media` | ✓ | **약 290행. 이 이식의 핵심 단일 함수** |
| `capabilityDumpMode` | `sane/media` | ✓ | Color 우선, Gray 폴백 |
| `epsonRawColorCorrection` | `sane/media` | ✓ | `None` 일치 |
| `epsonRawGammaCorrection` | `sane/media` | ✓ | `gamma=1.0` → `User defined` 2단 |
| `validatedColorMode` | `sane/media` | ✓ | |
| `capabilityRedumpArguments` | `sane/args` | ✓ | 활성 검사 비대칭 주의 |
| `canReuseSinglePassOptionsDump` | `sane/media` | ✓ | I-8 근거 |
| `epson2AlignedHeightMM` | `util/numeric` | ✓ | 4갈래 전부 픽스처 |
| `pixelGeometryValue` / `pixelGeometryLength` | `util/numeric` | ✓ | pel 변환 |
| `maximumResolutionDPI` | `sane/capabilities` | ✓ | |
| `pickModeValue` | `sane/media` | ✓ | |
| `listDevices` | `process/child` | ✗ | 프로세스 실행 |
| `detectScanners` | `wire/protocol` | ✗ | 실행 + 조립 |
| `getCapabilities` / `getCapabilitiesReport` | `wire/protocol` | ✗ | 실행 + 토큰 생성 |
| `currentDeviceAddress` / `resolveIdentity` | `process/child` | ✗ | 재열거 |
| `liveCachedSelector` / `invalidateAddressCache` / `noteDeviceOpened` | `process/child` | ✗ | 5초 TTL 캐시, 상태 |
| `cacheListedDevices` / `cachedDeviceType` / `cachedDeviceIdentity` | `process/child` | ✗ | 상태 |
| `resolveMedia(options:)` **인스턴스** | `process/child` | ✗ | 덤프 획득 후 static 호출 |
| `capabilityOptionsDump` / `scanSpecificOptionsDump` / `sourceSpecificOptionsDump` | `process/child` | ✗ | 덤프 획득 전략 |
| `reopenSelector` / `shouldRetryCapabilityRead` | `process/child` | ✗ | |
| `decodeCapabilitySnapshot` | `wire/json` | ✗ | base64 + JSON |

**static / 인스턴스 구분이 곧 순수 / 비순수 경계다.** Swift 코드가 이미
그렇게 나뉘어 있어서 배정이 기계적이다 — 이건 운이 아니라 원 설계의
의도이며([field-lessons](../10-lessons/field-lessons.md) §11), 이식이
가능한 이유다.

### 2.2 `SANEBackend+ScanExecution.swift` (874행)

| 함수 | 목적지 | 순수 | 비고 |
|---|---|:---:|---|
| `validateExactOptions` | `sane/validate` | ✓ | **약 190행. 거부 케이스 전부 골든** |
| `validateAdjustment` | `sane/validate` | ✓ | |
| `makeScanimageArgs` | `sane/args` | ✓ | 배열 순서까지 비교 |
| `saneNumber` | `util/numeric` | ✓ | **로케일 독립 필수** |
| `infraredURL(for:)` | `util/numeric` 또는 `sane/args` | ✓ | `<path>.ir.tiff` |
| `isStaleDeviceError` | `sane/validate` | ✓ | stderr 문자열 판정 |
| `containsInexactOptionWarning` | `sane/validate` | ✓ | `rounded value of` — **I-1의 마지막 방어선** |
| `isVolatileUSBSelector` | `sane/device_list` | ✓ | |
| `isRetryableAddressError` | `sane/validate` | ✓ | I-20 개선 후보(문자열 → 구조적 이유) |
| `validatedScannedTIFF` | `imaging/tiff` | ✗ | 검증 13단계 |
| `startPreviewScan` / `startFullScan` | `wire/protocol` | ✗ | 오케스트레이션 |
| `startSoftwareMultiPassScan` | `imaging/merge` | ✗ | 다중 패스 조율 |
| `resolveValidatedMedia` | `process/child` | ✗ | |
| `validatedScanResult` | `imaging/tiff` | ✗ | 3단계 계약 검증 |
| `runSingleAcquisition` | `process/child` | ✗ | 재시도 정책 포함 |
| `acquireInfraredPass` | `process/child` | ✗ | 실패를 warnings로 삼킴(I-10) |
| `resolveDeviceAddress` / `currentDeviceAddressWithRetry` | `process/child` | ✗ | |

### 2.3 `SANEBackend+Process.swift` (489행) — **전량 재작성**

**이 파일은 이식하지 않는다. 다시 쓴다.** Foundation `Process`/`Pipe`/
`DispatchSource`/POSIX 신호에 완전히 묶여 있다.

| Swift | Windows 대응 |
|---|---|
| `Process` + `Pipe` | `CreateProcessW` + 익명 파이프 + Job Object |
| `terminate()` → 0.5 s → `SIGKILL` | C-1 결과에 따라: `CTRL_BREAK_EVENT` 또는 stdin EOF → `TerminateProcess` |
| `DispatchSource.makeSignalSource` | 콘솔 제어 핸들러 또는 stdin EOF |
| stdout을 `FileHandle`로 리다이렉트 | `STARTUPINFO.hStdOutput` = 파일 핸들 (**바이너리 모드**) |
| `readabilityHandler`로 stderr drain | 전용 스레드 또는 겹친 I/O — **교착 방지 필수** |
| 타이머 기반 watchdog | 동일 개념, `WaitForMultipleObjects` |

**순수하게 살아남는 것은 둘뿐이다:**

| 함수 | 목적지 |
|---|---|
| `scanimageProgressRecordCount` | `util/numeric` (또는 `process/watchdog`의 순수 부분) |
| `scanimageProgressFraction` | 같음 |
| `usesAutomaticAcquisitionWatchdog` | `sane/device_list` (pieusb 판정) |

**이 두 진행률 파서는 반드시 순수로 유지한다.** watchdog 로직 전체가
그 위에 서 있고, 골든으로 검증할 수 있는 유일한 부분이다.

### 2.4 `SANEBackend+Environment.swift` (119행) — **전량 재작성**

| Swift | Windows |
|---|---|
| `findScanimage` | 번들 경로 우선 + `NEGAFLOW_SCANIMAGE_PATH`(D-08). **keg 개념 없음** |
| `findSaneConfigDir` | E-2 함정(`C:` 잘림) 주의 |
| `makeSaneEnvironment` | 환경 블록 구성. `LC_ALL=C`는 유지 |
| `makeTempURL` | Q-3 결정에 따름 |
| `imageSize(at:)` | `imaging/tiff`로 이동 (ImageIO → libtiff) |

`imageSize`만 모듈이 바뀐다. 나머지는 `process/environment`.

### 2.5 `SANEBackend+Alignment.swift` (203행) — 전량 `imaging/align`, 순수

**이식 완료 (2026-08-05).** `windows/src/imaging/align.{h,cpp}`.
파리티 N-4 통과 — 9 케이스 전부 같은 정수 오프셋.

**전부 순수 함수이고 전부 부동소수점이다.** 즉 **L5 수치 동등성의 주 대상**이다.

| 함수 | 주의 |
|---|---|
| `estimateIntegerOffset` | 결과는 정수 — **완전 일치 요구** |
| `downsampledError` / `downsampledTexture` / `fullResLumaError` | **누적 합. SIMD 금지(D-11)** |
| `downsampledLuma` / `boxBlur3` | |
| `accumulateAligned` | |
| `exposureTrustWeight` / `mix` / `smoothstep` | 골든 픽스처 대상 |

### 2.6 `SANEBackend+ExposureMergingCore.swift` (217행) — 전량 `imaging/merge`, 순수

**이식 완료 (2026-08-05).** `windows/src/imaging/merge.{h,cpp}`.
파리티 N-3 통과 — 병합 6 케이스를 float 비트 패턴과 UInt16 양쪽으로 대조.

Swift 쪽 `mergedHardwareExposureValue` / `alternateExposureValue` /
`normalizeExposure` 는 `private` 이라 `@testable import` 로도 부를 수 없다.
그래서 파리티는 **공개 진입점을 통해 전체 파이프라인을 대조한다** —
개별 함수가 아니라 결과 픽셀이 같은지를 본다.

| 함수 | 주의 |
|---|---|
| `mergedHardwareExposureValue` | 핵심 수식 |
| `alternateExposureValue` | |
| `normalizeExposure` | |
| `alignedAverageRGBAf` / `alignedExposureNormalizedRGBAf` | |

### 2.7 `SANEBackend+ExposureMerge.swift` (93행) — Core Image 제거

**병합 코어 부분 이식 완료 (2026-08-05).** URL 을 받는 두 함수는
libtiff 로드/쓰기가 필요하므로 `imaging/tiff` 와 함께 남았다.

| 함수 | 조치 |
|---|---|
| `averageMultiSampleScans(URLs)` | libtiff 로드 → 순수 코어 → libtiff 쓰기 |
| `mergeHardwareExposureScans` | 같음 |
| `averageMultiSampleScans(CIImage)` | **삭제.** CIImage 경로 |
| `averageMultiSampleBitmap` | `imaging/merge`로. CIImage → 배열 |
| `mergeHardwareExposureBitmap` | 순수. 골든 대상 |
| `referenceExposureTime` | `util/numeric` |

### 2.8 `SANEBackend+TIFFWriting.swift` (83행) / `TIFFLoader.swift` (31행)

**N-1 spike의 대상이다.** 여기서 수치 동등성이 결정된다.

**이식 완료 (2026-08-05).** `windows/src/imaging/tiff_io.{h,cpp}`.
파리티가 **양방향 상호운용**을 대조한다 — libtiff 로 쓴 것을 ImageIO 가,
ImageIO 로 쓴 것을 libtiff 가 같은 픽셀로 읽는다. 파일 바이트는 다르다
(libtiff `II`, ImageIO `MM`).

`validatedScannedTIFF` 는 둘로 나뉘었다:

```text
imaging/tiff_contract   태그 → 통과/거부 판정과 메시지. 순수라 파리티 밖에서
                        단위 테스트로 고정된다(Swift 짝이 파일을 받으므로)
imaging/tiff_io         libtiff 로 태그·픽셀을 읽고 판정을 호출한다
⬜ Win32                §3.1 핸들 기반 검증, reparse point 거부
```

| 함수 | 조치 |
|---|---|
| `loadScannerTIFF` | libtiff 직접 읽기. **linear 재해석(변환 아님)** |
| `renderRGBAf` | `CIContext.render(.RGBAf)` 대체. **N-1이 증명해야 하는 부분** |
| `writeRGB16TIFF` | libtiff. **ICC 프로파일을 넣지 않는다** |
| `writeLinearTIFF` | **호출자 0.** 이식하지 않거나 미사용 표시 (§3.5) |
| `saveScannerTIFF` | **호출자 0.** LZW 경로. 같음 (§3.5) |

### 2.9 `SaneOptionDump.swift` (171행) — 전량 `sane/option_dump`, 순수

**가장 깔끔하게 옮겨지는 파일이다.** 전부 순수, 전부 문자열 처리.

정규식 6개는 [language-decision](language-decision.md) §8.1에 따라
**수동 파서로 대체하는 것이 실용적이다.** `intTokens`/`numericRange`/
`rangeUnit`이 정규식을 쓴다.

**`snapResolution`은 진짜로 스냅한다** — 리스트는 가장 가까운 값(동률이면
큰 쪽), 범위는 클램프. 그리고 **production 경로에서 호출되지 않는다.**
실제 해상도 결정은 `resolveMedia`가 하고, 거기서는 정확 일치만 통과한다:

```text
.list  → values.contains(requestedDPI) ? requestedDPI : nil
.range → resolutionRange.containsExactly(dpi) ? dpi : nil
.none  → nil
```

즉 `snapResolution`은 **연결하면 I-1을 위반하는 죽은 코드**다.
`IRStrategy.cleanImage`와 같은 성격이며([field-lessons](../10-lessons/field-lessons.md) §4),
같은 이유로 연결하지 않는다. 옮긴다면 "테스트·진단 전용, production 호출
금지" 주석을 반드시 함께 옮긴다
([option-dump-parser](../02-frontend-contract/option-dump-parser.md) §6).

### 2.10 `SaneConfigTuner.swift` (123행) — **D-05에 따라 no-op**

```text
recoverLegacyFiltering / tune / restore / restoreNegaflowDisabledLines
    → Windows에서는 전부 no-op
```

**"미구현"이 아니라 "의도적 no-op"다.** 나중에 구현하지 말 것
([field-lessons](../10-lessons/field-lessons.md) §8).

### 2.11 `ScannerModel.swift` (356행) / `PluginProtocolV2.swift` (224행)

도메인 타입과 v2 요청/검증. **거의 그대로 옮겨진다.**

**`validatedOptions` 이식 완료 (2026-08-05).** `windows/src/wire/request.{h,cpp}`.
배정을 `sane/validate` 가 아니라 `wire/request` 로 바꿨다 — 이 검증은 **호스트
요청**을 보는 것이고 `sane/validate` 는 **장치 능력**과 대조하는 2단계라,
같은 모듈에 두면 두 단계의 경계가 흐려진다.

11개 가드 중 **9번(경로)만 플랫폼별로 갈린다.** 정책을 주입 가능하게 해서
가드 순서·문구는 파리티 45 케이스로, Windows 경로 규칙은 단위 테스트로
각각 고정했다.

파리티가 문서 오류를 하나 잡았다 — macOS 의 경로 검사는 정규화를 하지 않고
후행 슬래시만 없앤다. 경로 탈출이 통과한다.
→ [exact-option-contract](../02-frontend-contract/exact-option-contract.md) §3.1

### 2.12 `main.swift` (278행) / `WireProtocol.swift` (63행)

| Swift | Windows |
|---|---|
| 서브커맨드 디스패치 | `main.cpp` |
| `emitLine` (버퍼링 미의존 직접 write) | `wire/emitter`. **stdout 바이너리 모드** |
| `ProtocolV2Emitter` (`NSLock` 직렬화) | `wire/emitter`. `sequence` 0부터. **파리티 불가** — main.swift 안 private (handoff §4.2b) |
| `isatty(fd) == 0` | `GetFileType(h) != FILE_TYPE_CHAR` |
| 신호 핸들러 설치 | `process/cancel` |
| 결과 계약 재확인 4종 | `wire/protocol` |
| `repair-sane-config` / `tune-sane` / `restore-sane` | no-op 출력(D-05) |

## 3. 규모 요약

Swift 소스 총 **4,922행**(`Sources/`, 2026-08-04 실측)의 배분 추정이다.

| 목적지 | 대략 행수 | 성격 | 마일스톤 |
|---|---:|---|---|
| `sane_logic` | ~2,200 | 순수. **골든으로 전량 검증 가능** | M2 |
| `process` | ~1,400 | **전면 재작성** | M3 |
| `imaging` | ~700 | 순수 + libtiff. 수치 동등성 | M4 |
| `wire` | ~350 | 재작성(구조는 유지) | M5 |
| no-op / 삭제 | ~150 | `SaneConfigTuner`, CIImage 경로 | — |

**행수는 추정이며 정확히 합해지지 않는다.** `SANEBackend+Discovery.swift`
(1,181행)와 `SANEBackend+ScanExecution.swift`(874행)가 각각 여러 모듈에
걸쳐 있어(§2.1, §2.2) 파일 단위로 나눌 수 없기 때문이다. 실제 배분은
구현하면서 확정된다.

**약 2,900행(sane_logic + imaging)이 골든으로 기계 검증된다.**
나머지가 사람이 확인해야 하는 부분이고, 위험이 집중된 곳은 `process`다.

다른 문서가 "약 3,000행의 파싱·검증 로직"이라고 말할 때는
`sane_logic`에 도메인 타입과 순수 이미징 코드를 더해 느슨하게 센 값이다.
같은 코드를 가리킨다.

## 3.5 죽은 코드 인벤토리 — 연결하지 말 것

호출되지 않거나 도달할 수 없는 코드가 **네 개** 있다. 전부 "구현이 있으니
연결하면 되겠다"로 보이고, **전부 연결하면 불변식을 깬다.**

| 대상 | 상태 | 연결하면 |
|---|---|---|
| `IRStrategy.cleanImage` | 정의·분기 있음, `resolveMedia`가 생성 안 함 | pieusb 사용자가 IR 토글을 켜고, 별도 IR 파일 없는 결과를 받고, 3단계 검증이 실패시킨다 |
| `SaneOptionDump.snapResolution` | 호출자 0 | **I-1 위반.** 요청 해상도를 가장 가까운 값으로 스냅한다 |
| `writeLinearTIFF` | 호출자 0 | RGBAh(반정밀) 경로. 16-bit 정수 계약과 다르다 |
| `TIFFLoader.saveScannerTIFF` | 호출자 0 | LZW 압축 경로. `writeRGB16TIFF`(무압축)와 산출물이 갈린다 |

**공통 처리**: 옮기지 않거나, 옮긴다면 "미사용 / production 호출 금지"
주석을 함께 옮긴다. 어느 쪽이든 **호출부를 만들지 않는다.**

이것들이 남아 있는 이유는 게으름이 아니다. 각각 한때 필요했거나
필요해 보였고, 지우는 것보다 남겨 두고 표시하는 쪽이 "왜 없지?"를
막는다. 같은 판단이 [field-lessons](../10-lessons/field-lessons.md) §4에 있다.

## 4. 배정이 애매한 것들

정직하게 적는다. 구현하면서 정한다.

| 항목 | 애매한 이유 |
|---|---|
| `infraredURL` | 경로 조작이지만 계약의 일부. `sane/args` 또는 `util` |
| `imageSize` | 환경 유틸이었으나 실제로는 이미징 |
| 진행률 파서 | 순수하지만 watchdog과만 쓰인다 |
| `decodeCapabilitySnapshot` | JSON이지만 `sane/capabilities`의 입력 |
| `isStaleDeviceError` 계열 | 문자열 판정이라 순수. 그러나 프로세스 오류 처리 문맥 |

**애매하면 순수 쪽에 둔다.** `sane_logic`에 있으면 골든으로 검증되고,
`process`에 있으면 안 된다.

## 5. 이식 순서 제안

`sane_logic` 안에서도 의존 순서가 있다.

```text
1. util/numeric          의존 0. containsExactly, saneNumber, epson2AlignedHeightMM
2. sane/option_dump      util만 의존. 파서
3. sane/device_list      독립. 문자열 판정
4. sane/capabilities     option_dump 의존
5. sane/media            option_dump + device_list + numeric 의존. 가장 큼
6. sane/validate         media 의존
7. sane/args             media 의존
```

**1→2 순서가 특히 중요하다.** `numeric`이 없으면 `option_dump`의 범위
파싱을 테스트할 수 없다. 그리고 `numeric`이 가장 쉬우면서 골든을
가장 먼저 만들 수 있는 곳이다(conformance-fixtures §9).

## 6. 체크리스트

- [ ] `sane_logic`이 `windows.h`도 `tiffio.h`도 포함하지 않는다
- [ ] `resolveMedia` static이 통째로 순수하게 옮겨졌다
- [ ] 진행률 파서 2개가 순수로 남았다
- [ ] `saneNumber`가 로케일 독립이다
- [ ] §3.5의 죽은 코드 4개 중 어느 것도 호출부가 생기지 않았다
- [ ] `SaneConfigTuner`가 no-op이고 그 사실이 주석에 있다
- [ ] CIImage 전용 오버로드가 삭제됐다
- [ ] 누적 합 함수 3개가 스칼라다
- [ ] §4의 애매한 항목들이 최종 배정과 함께 이 표에 반영됐다
