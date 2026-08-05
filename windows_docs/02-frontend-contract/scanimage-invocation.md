# scanimage 호출 계약

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 이식 정본
코드 근거: `SANEBackend+ScanExecution.swift`(`makeScanimageArgs`),
`SANEBackend+Discovery.swift`(`listDevices`, `capabilityOptionsDump`,
`capabilityRedumpArguments`, `scanSpecificOptionsDump`),
`SANEBackend+Process.swift`(`runScanimage`, `runScanimageTo`)

관련 문서:

- [option-dump-parser](option-dump-parser.md)
- [child-process](../03-process-and-io/child-process.md)
- [environment-and-paths](../03-process-and-io/environment-and-paths.md)
- [backend-quirks](backend-quirks.md)

## 1. 호출은 다섯 종류뿐이다

| # | 목적 | 인자 | stdout | stderr | 장치 open |
|---:|---|---|---|---|:---:|
| 1 | 장치 목록(우선) | `-f "%d\t%v\t%m\t%t%n"` | 텍스트(파이프) | 진단 | 아니오 |
| 2 | 장치 목록(후퇴) | `-L` | 텍스트(파이프) | 진단 | 아니오 |
| 3 | 기본 옵션 덤프 | `-A -d <dev>` (+ genesys는 `--mode Color`) | 텍스트(파이프) | 진단 | **예** |
| 4 | 상태 적용 재덤프 | `-A -d <dev> [--source/--mode/--resolution/--depth/--preview=yes/--color-correction/--gamma-correction]` | 텍스트(파이프) | 진단 | **예** |
| 5 | 획득 | `-d <dev> -p [옵션…] --format=tiff` | **이미지 바이트(파일로 리다이렉트)** | 진행률 + 진단(파이프) | **예** |

"장치 open" 열이 핵심이다. 1·2는 장치를 건드리지 않으므로 몇 번이든 안전하지만,
3·4·5는 USB 주소를 만료시킬 수 있고 전용 필름 스캐너에서는 다음 획득을
깨뜨릴 수 있다. 그래서 코드 전체가 **open 횟수를 줄이는 방향**으로 짜여 있다.

## 2. 획득 인자 생성 (`makeScanimageArgs`)

순서가 계약이다. 임의로 재배열하지 않는다.

```text
-d <devname>
-p
[--source <S>]                     source가 있을 때
[--mode <M>]                       mode가 있을 때

── 아래 블록은 pass == .main 일 때만 ──
[--advance=no]                     backend == pieusb && hasAdvanceOption
[--color-correction <C>]           backend == epson2 && hasColorCorrectionOption && C != nil
[--gamma-correction <G>]           backend == epson2 && hasGammaCorrectionOption && G != nil
[--<filmTypeOption> <V>]           filmType과 옵션명이 둘 다 있을 때
   단, 옵션명이 "negative"이면 --negative=<V> 형태
[--brightness=<N>]                 hasBrightnessOption && (인자 brightness 또는 요청 brightness)
[--contrast=<N>]                   hasContrastOption && 요청 contrast
[--scan-exposure-time=<N>]         hasScanExposureOption && 요청 노출시간
[--<cleanImageOption>=yes]         irStrategy == .cleanImage
[--preview=yes]                    preview 요청 && hasPreviewOption
── main 블록 끝 ──

[--resolution <N>]                 resolvedDPI가 있을 때
[--depth <N>]                      depthArgument가 있을 때

지오메트리 (셋 중 하나만):
  [--tl-x A --tl-y B --br-x C --br-y D]   usesCornerPixelGeometry
  [-l X -t Y]                             originXMM/originYMM
  [-l X -t Y]                             originXPixels/originYPixels (정수)
[-x W -y H]                        widthMM/heightMM 또는 widthPixels/heightPixels

--format=tiff
```

### 2.1 IR 패스에서만 바뀌는 것

```text
irStrategy == .separateSource(S):  source ← S, mode ← irPassMode ?? mode
irStrategy == .separateMode(M):    mode   ← M
```

**해상도·심도·지오메트리는 본 스캔과 동일하게 유지한다.** 먼지 맵을 RGB에
정렬하려면 픽셀 격자가 같아야 하기 때문이다. main 전용 블록(밝기·대비·노출·
필름 타입·색보정)은 IR 패스에서 통째로 생략된다.

### 2.2 숫자 직렬화 (`saneNumber`)

```text
값의 반올림이 값과 같으면 → Int로 출력 ("36" not "36.0")
아니면                    → Swift 기본 Double 문자열 ("36.33")
```

Windows 이식에서 **가장 조용한 위험**이다.

| 위험 | 대응 |
|---|---|
| 로케일 소수점 | 반드시 invariant/`"C"` 로케일로 포맷 |
| 지수 표기 | `1e-05` 같은 출력이 나오면 `scanimage`가 파싱하지 못할 수 있다. 고정 소수점 강제 |
| 자릿수 | Swift `String(Double)`은 왕복 가능한 최단 표현(shortest round-trip)이다. C++ `std::to_chars`(shortest), C# `"R"`/기본 `ToString()`(.NET Core 3.0+ shortest round-trip)이 같은 계열이다. `printf("%f")`(6자리 고정)는 **다르다** — `36.33`이 `36.330000`이 되고, step 검사를 통과한 값이 백엔드에서 다르게 해석될 수 있다 |
| 음수 0 | `-0.0`이 `"-0"`으로 나가지 않게 정규화 |

권장: 왕복 가능한 최단 표현을 쓰되, 지수 표기가 나오면 고정 소수점으로
대체하는 래퍼를 만들고, 그 래퍼를 fixture로 고정한다.

| 입력 | 기대 출력 |
|---|---|
| `36.0` | `36` |
| `36.33` | `36.33` |
| `0.0` | `0` |
| `-0.0` | `0` |
| `44.25` | `44.25` |
| `1.0e-5` | `0.00001` (지수 금지) |
| `100.0` | `100` |

### 2.3 `--brightness=N` 형태

밝기·대비·노출은 `--opt=값` 한 토큰이고, 소스·모드·해상도·심도는
`--opt 값` 두 토큰이다. 현재 코드가 그렇다. **바꾸지 않는다.** `scanimage`는
둘 다 받지만, 인자 배열이 달라지면 기존 테스트 픽스처가 전부 깨진다.

## 3. 옵션 덤프 획득 전략

### 3.1 `capabilityOptionsDump` — 최대 3회 시도

```text
for attempt in 0..<3:
    attempt == 0 이고 expectedIdentity == nil:
        devname = 요청 장치명 그대로        ← detect가 준 주소는 아직 살아 있다
    아니면:
        devname = currentDeviceAddress(allowSingleBackendSelector: attempt == 2)

    baseArgs = ["-A", "-d", devname]
    backend == "genesys" 이면 baseArgs += ["--mode", "Color"]
    baseDump = runScanimage(baseArgs)

    baseDump가 비면 → ioFailure

    canReuseSinglePassOptionsDump(baseDump, backend) 이면 → (devname, baseDump) 반환
    아니면 → sourceSpecificOptionsDump(...)

    실패 시:
        shouldRetryCapabilityRead(error) 이고 attempt < 2 이면
            주소 캐시 무효화 + 800 ms 대기 후 재시도
        아니면 즉시 전파
```

`shouldRetryCapabilityRead`:

```text
ScannerError면:  busy, notConnected, ioFailure → 재시도
                 unsupportedOption, driverConflict, cancelled, timeout, unknown → 중단
그 외:           isStaleDeviceError(설명 문자열)
```

### 3.2 `canReuseSinglePassOptionsDump`

```text
backend == "genesys"
소스 목록에서 IR이 아닌 값이 정확히 하나
그 하나가 투과 소스
→ true (추가 open 없이 base 덤프 재사용)
```

단일 투과 소스를 가진 genesys 필름 스캐너(OpticFilm 계열)를 연속으로 여러 번
열면 실제 하드웨어에서 다음 획득이 실패한다. 이 최적화가 그 회피책이다.

### 3.3 `capabilityRedumpArguments` — 순수 함수

```text
source = preferredTransparencySource(소스 목록)
depthNeedsMode = hasOption("depth") && !isActive("depth")
mode = (source != nil || depthNeedsMode) ? capabilityDumpMode(덤프) : nil
selectedMode = mode ?? selectedEnumValue("mode")
colorCorrection = backend == epson2 && selectedMode에 "color" 포함
                  ? constraintEnumValues("color-correction")에서 "None" : nil
gammaCorrection = backend == epson2
                  ? constraintEnumValues("gamma-correction")에서 "gamma=1.0"(공백 제거 후)
                    또는 "User defined" : nil

넷 다 nil이면 → nil (재덤프 불필요)
아니면 ["-A", "-d", devname] + 있는 것들
```

`capabilityDumpMode`: Color 우선, 없으면 Gray. **Lineart는 절대 쓰지 않는다.**

이 함수가 순수하다는 점이 중요하다. Windows 이식에서 그대로 단위 테스트할 수 있다.

### 3.4 `sourceSpecificOptionsDump` / `scanSpecificOptionsDump` — 재연결 1회

두 함수 모두 같은 골격이다.

```text
for attempt in 0..<2:
    attempt > 0:
        reopenSelector(previous:…)로 새 선택자 확보. 못 얻으면 루프 탈출
    runScanimage(인자)
    성공하고 덤프가 비지 않으면 반환
    실패:
        attempt == 0 이고 isStaleDeviceError(설명)이면 계속
        아니면 즉시 전파
```

`reopenSelector`는 이전 선택자에 `:`가 없으면(= 주소 없는 backend 선택자) nil을
돌려 재시도를 멈춘다. 주소 없는 선택자는 재열거를 견디므로 다시 확인할 것이
없기 때문이다.

`scanSpecificOptionsDump`는 **요청값을 실제로 적용한 상태**의 덤프를 읽는다.
인자:

```text
-A -d <dev>
[--source <preliminary.source>]
[--mode <preliminary.mode>]
[--resolution <preliminary.resolvedDPI>]
[--depth <preliminary.depthArgument>]
[--preview=yes]     preview 요청이고 hasPreviewOption일 때
```

`preliminary`는 소스 덤프로 한 번 `resolveMedia`를 돌려 얻는다. 즉
**resolveMedia를 두 번 호출한다**(예비 → 최종). 이 구조를 유지한다.

## 4. capabilityToken이 있을 때의 경로

```text
토큰 디코드 및 검증:
    utf8 <= 1 MiB
    base64 디코드 성공
    JSON 디코드 성공
    schemaVersion == 3
    deviceID == 요청 deviceID
    backend == 요청 backend
    acquisitionDevice 비어 있지 않음
    optionDump가 비어 있지 않음
  하나라도 실패 → unsupportedOption "장치 능력을 다시 조회하십시오"

snapshot.validatedMode == 요청 색 모드:
    → 저장된 (acquisitionDevice, optionDump)를 그대로 사용. 장치 open 0회.
아니면:
    → scanSpecificOptionsDump로 요청 모드를 적용한 덤프를 새로 읽는다. open 1회.
```

**정상 Color 경로에는 scan 전 장치 open이 한 번도 없다.** 이것이 토큰이
존재하는 이유다. 호스트가 토큰을 돌려주지 않으면 매 스캔마다 덤프를 다시 읽어야
하고, 그 자체가 전용 필름 스캐너의 다음 획득을 위협한다.

Windows 이식에서 토큰 스키마를 바꾸면 `schemaVersion`을 4로 올린다. 같은 3을
유지한 채 필드 의미를 바꾸면 macOS에서 만든 토큰과 Windows에서 만든 토큰이
섞였을 때(호스트 설정 이관, 문서 예제 복붙) 조용히 잘못 동작한다.

## 5. 획득 실행 (`runSingleAcquisition`)

```text
attemptCount = (backend == "pieusb") ? 1 : 2

for attempt in 0..<attemptCount:
    attempt > 0 → 주소 캐시 무효화
    devname = resolveDeviceAddress(forceRefresh: attempt > 0)
    args = makeScanimageArgs(...)
    (exitCode, madeProgress) = runScanimageTo(args, outputURL, ...)
    stderr = takeStderr()

    취소 요청됨 → cancelled
    exitCode == 0:
        containsInexactOptionWarning(stderr) → unsupportedOption
        아니면 성공 반환
    exitCode != 0:
        attempt == 0 && attemptCount > 1 && !madeProgress && isStaleDeviceError(stderr)
            → "Re-detecting scanner" 진행률 보고 후 재시도
        아니면 ioFailure

    ScannerError 예외:
        attempt == 0 && backend == "genesys" && code == .timeout
        && 메시지에 "첫 이미지 데이터" 포함 && 취소 아님
            → 출력 파일 삭제, 캐시 무효화, 재시도
        아니면 출력 파일 삭제 후 전파
```

`pieusb`가 재시도하지 않는 이유: full scan 자체가 다음 슬라이드로 이동을
수반할 수 있어서, 같은 요청을 자동 재시도하면 다른 프레임을 덮어쓴다.

genesys의 timeout 재시도 조건에 **한국어 메시지 부분 문자열 매칭**이 들어 있다
(`err.message.contains("첫 이미지 데이터")`). 이식 시 이것을 문자열 비교로
옮기지 말고 **타임아웃 종류를 구조적으로 구분**한다:

```text
enum AcquisitionTimeoutKind { firstProgress, stalled }
→ ScannerError에 kind를 실어 보내고 kind == .firstProgress 로 판정
```

이 정리는 macOS 쪽에도 적용할 가치가 있는 개선이지만, 이 문서는 Windows
계약만 정한다. Windows 구현은 문자열이 아니라 종류로 판정한다.

### 5.1 `resolveDeviceAddress`

```text
forceRefresh == false:
    liveCachedSelector(target, backend, identity)가 있으면 그것
    아니면 media.acquisitionDevice가 있고 ":libusb:"를 포함하지 않으면 그것
forceRefresh == true 또는 위가 없으면:
    currentDeviceAddressWithRetry(최대 3회, 800 ms 간격, allowSingleBackendSelector: true)
```

`isVolatileUSBSelector(v) = v.contains(":libusb:")`. Windows에서 SANE가 내는
장치명 형식이 다르면([availability](../01-sane-runtime/availability.md)) 이
판정식을 그 형식에 맞게 다시 정해야 한다. 판정식이 틀리면 죽은 주소를 재사용해
매 패스마다 헛된 open이 붙는다.

## 6. 표준 스트림 처리

### 6.1 목록·덤프 (`runScanimage`)

```text
stdout → Pipe, stderr → Pipe
프로세스 시작 후 두 파이프를 각각 별도 스레드에서 끝까지 읽는다
waitUntilExit → 두 읽기 작업 완료 대기
```

**파이프 버퍼가 차면 `scanimage`가 블록한다.** 반드시 `run()` **이후에**
백그라운드로 drain한다. 이 순서를 바꾸면 실제 교착이 발생한다(코드 주석에
"실제 교착 사례"로 기록돼 있다).

Windows 대응은 [child-process](../03-process-and-io/child-process.md) §5.

### 6.2 획득 (`runScanimageTo`)

```text
출력 파일을 미리 지우고 새로 만든다
stdout ← 그 파일의 쓰기 핸들 (파이프가 아니다)
stderr → Pipe, readabilityHandler로 스트리밍 파싱
terminationHandler에서:
    readabilityHandler 해제
    남은 stderr를 readToEnd로 마저 읽어 파싱      ← 이 순서가 중요
    watchdog.finish()
    파일 핸들 close
    프로세스 추적 해제, noteDeviceOpened()
    취소/타임아웃/정상 판정
```

"readabilityHandler가 가져간 chunk까지 처리한 뒤 최종 stderr를 drain"이
코드 주석으로 명시돼 있다. 그렇게 하지 않으면 빠른 I/O 실패를 "진행 전"으로
오판해 잘못된 재시도가 붙는다.

`stderrReadLock`(`NSLock`)이 readability 콜백과 termination 콜백의 경합을
막는다. Windows에서도 같은 상호 배제가 필요하다.

## 7. 종료 코드 → 오류 코드 매핑 (`runScanimage`)

```text
proc.terminationReason == .exit && terminationStatus == 0 이 아니면:
    detail = stderr 트림
    message = detail이 비면 "scanimage가 종료 코드 N으로 실패했습니다." 아니면 detail
    소문자 message에:
        "access to resource has been denied" | "device busy" | "resource busy" → busy
        "no such device" | "invalid argument" | "not connected"                → notConnected
        그 외                                                                  → ioFailure
```

`isStaleDeviceError`(재시도 판정용, 별개):

```text
소문자에 다음 중 하나 포함:
  "invalid argument", "open of device", "failed to open",
  "device busy", "no such device", "i/o error", "device i/o"
```

두 목록이 겹치지만 목적이 다르다. 하나는 코드 분류, 하나는 재시도 판정이다.
**둘을 합치지 않는다.**

Windows 위험: 이 문자열들도 `scanimage` 영어 메시지다.
[exact-option-contract](exact-option-contract.md) §6의 로케일 spike가
여기에도 그대로 적용된다. 로케일 고정에 실패하면 재시도·busy 판정이 통째로
무력화되며, 그 결과는 "가끔 안 되는 스캐너"로 나타난다.

## 8. 이식 체크리스트

- [ ] 다섯 가지 호출 형태의 인자 배열이 바이트 단위로 같다
- [ ] `saneNumber` 출력이 §2.2 표와 같다
- [ ] `-f` 인자의 탭·`%n`이 자식 프로세스에 온전히 전달된다
- [ ] 획득 stdout이 파일로 직접 가고 파이프를 거치지 않는다
- [ ] stdout/stderr 동시 drain, 교착 재현 테스트 통과
- [ ] termination 시 잔여 stderr를 반드시 마저 읽는다
- [ ] `attemptCount`가 pieusb에서 1이다
- [ ] genesys 첫 진행률 타임아웃 재시도가 문자열이 아니라 종류로 판정된다
- [ ] 오류 문자열 매핑 두 목록이 분리된 채 이식됐다
- [ ] 토큰 있는 정상 Color 경로에서 scan 전 장치 open이 0회임을 카운터로 증명
