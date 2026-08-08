# 자식 프로세스와 파이프

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 이식 정본 — 이 장은 전면 재작성 대상이다
코드 근거: `Sources/SANEPluginCore/SANEBackend+Process.swift`,
`Tests/SANEPluginCoreTests/SANEBackendProcessOwnershipTests.swift`

관련 문서:

- [cancellation](cancellation.md)
- [timeouts-and-watchdog](timeouts-and-watchdog.md)
- [environment-and-paths](environment-and-paths.md)
- [scanimage-invocation](../02-frontend-contract/scanimage-invocation.md)

## 1. 무엇을 바꾸는가

| 현재 (Foundation) | Windows |
|---|---|
| `Process` | `CreateProcessW` |
| `Pipe` | `CreatePipe` + `SetHandleInformation` |
| `FileHandle(forWritingTo:)` | `CreateFileW` + `bInheritHandle` |
| `readabilityHandler` | 전용 스레드 또는 overlapped I/O |
| `terminationHandler` | `RegisterWaitForSingleObject` 또는 대기 스레드 |
| `DispatchSourceTimer` | 스레드 풀 타이머 / `CreateThreadpoolTimer` |
| `proc.terminate()` (SIGTERM) | **직접 대응이 없다** → [cancellation](cancellation.md) |
| `kill(pid, SIGKILL)` | `TerminateProcess` |
| `NSLock` | `SRWLOCK` / `std::mutex` / `lock` |
| 프로세스 트리 정리 없음 | **Job Object 필요** |

## 2. 두 가지 실행 형태

### 2.1 유틸리티 실행 (`runScanimage`)

목록 조회와 옵션 덤프. stdout·stderr 둘 다 파이프.

```text
stdout → 파이프 → 백그라운드 스레드가 EOF까지 읽음
stderr → 파이프 → 백그라운드 스레드가 EOF까지 읽음
프로세스 종료 대기
두 읽기 스레드 완료 대기
결과 판정
```

### 2.2 획득 실행 (`runScanimageTo`)

```text
stdout → 출력 파일 핸들 (파이프 아님)
stderr → 파이프 → 스트리밍 파싱 (진행률 추출)
종료 시 잔여 stderr drain
```

이 비대칭을 유지한다. 이미지 바이트를 파이프로 받아 파일에 쓰면
불필요한 복사와 교착 위험이 생긴다.

## 3. 파이프 교착 — 가장 중요한 제약

코드 주석에 "실제 교착 사례"로 기록돼 있다.

> 파이프 버퍼(64KB)가 가득 차면 scanimage가 블록한다.
> 반드시 `proc.run()` **이후에** 백그라운드에서 읽어야 한다.

Windows 기본 익명 파이프 버퍼도 유사한 크기다(`CreatePipe`의 `nSize`가 0이면
시스템 기본값). 규칙은 같다.

```text
1. 파이프 생성
2. 자식의 읽기/쓰기 끝만 상속 가능하게 설정
3. CreateProcessW
4. 부모 쪽에서 자식이 쓰는 끝의 "자식용 핸들"을 즉시 닫는다  ← 필수
5. 그제서야 읽기 시작
```

**4번을 빠뜨리면 EOF가 오지 않는다.** 부모가 쓰기 끝을 붙들고 있으면
`ReadFile`이 영원히 블록한다. Foundation은 이것을 자동으로 처리하므로
Swift 코드에는 대응하는 줄이 없다. Windows에서는 명시적으로 해야 한다.

### 3.1 stdout과 stderr를 동시에 읽어야 한다

순차적으로 읽으면 교착한다.

```text
잘못:  stdout을 EOF까지 읽는다 → stderr를 읽는다
       (scanimage가 stderr 버퍼를 채우고 블록하면 stdout EOF가 오지 않는다)

옳음:  두 파이프를 각각 스레드에서 동시에 읽는다
```

또는 overlapped I/O로 한 스레드에서 다중화한다. 스레드 두 개가 더 단순하고
현재 구현과 의미가 같다.

## 4. 명령줄 조립 — 보안 경계

`CreateProcessW`는 argv 배열이 아니라 **문자열 하나**를 받는다.
자식이 CRT의 인자 파서로 다시 나눈다. 따라서 인용이 잘못되면 인자 주입이
가능하다.

### 4.1 규칙

Microsoft가 문서화한 CRT 파싱 규칙에 맞춰 인용한다.

```text
각 인자에 대해:
  공백, 탭, 큰따옴표를 포함하지 않고 비어 있지 않으면 → 그대로
  아니면:
    큰따옴표로 감싼다
    내부의 백슬래시 연속이 큰따옴표 앞이면 2배로 늘린다
    내부의 큰따옴표는 백슬래시로 이스케이프한다
    문자열 끝의 백슬래시 연속은 2배로 늘린다
```

**직접 구현하지 말고 검증된 구현을 쓴다.** .NET의
`ProcessStartInfo.ArgumentList`는 이 규칙을 정확히 구현한다.
C++이면 `CommandLineToArgvW`로 왕복 검증하는 테스트를 반드시 둔다.

### 4.2 우리 인자에 실제로 들어가는 위험 문자

| 인자 | 위험 문자 |
|---|---|
| `-f "%d\t%v\t%m\t%t%n"` | 탭(실제 문자), `%` |
| `--source "Transparency Adapter Infrared"` | **공백** |
| `--mode "Color"` | 없음 |
| `--gamma-correction "User defined"` | **공백** |
| `--color-correction "None"` | 없음 |
| `-d <devname>` | `:`, 백엔드에 따라 `\` 가능성 |
| `-x 36.33` | `.` (로케일 주의) |

`--source` 값은 장치가 준 원문이며, 공백을 포함하는 경우가 실제로 있다.

### 4.3 신뢰할 수 없는 입력이 `-d`에 들어간다

`capabilityToken`의 `acquisitionDevice`가 그대로 `-d` 인자가 된다.
토큰은 호스트를 거쳐 돌아오고 호스트는 내용을 검사하지 않는다.

**현재 macOS 코드에는 이 검사가 없다.** `Process.arguments`가 배열이라
인자 주입이 구조적으로 불가능하기 때문이다. Windows에서는 다르다.

```text
acquisitionDevice 검증 (신규):
  비어 있지 않음
  길이 <= 512
  제어 문자(0x00~0x1F, 0x7F) 없음
  '-'로 시작하지 않음                    ← 옵션으로 오인 방지
  개행/캐리지리턴 없음
  UTF-8 유효
위반 시 unsupportedOption "capabilityToken이 손상되었습니다"
```

`scannerID`(요청의 `deviceID`)에서 파생되는 장치명에도 같은 검사를 적용한다.

## 5. 표준 스트림 리다이렉션

### 5.1 획득 실행의 stdout

```text
SECURITY_ATTRIBUTES sa = { sizeof(sa), nullptr, TRUE };
HANDLE h = CreateFileW(outputPath,
                       GENERIC_WRITE,
                       0,                        // 공유 없음
                       &sa,                      // 상속 가능
                       CREATE_ALWAYS,            // 있으면 덮어씀
                       FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
                       nullptr);
```

`CREATE_ALWAYS`는 현재 macOS 동작(`removeItem` → `createFile`)과 같다.

**출력 파일 검증**: 열자마자 `GetFinalPathNameByHandleW`로 최종 경로를 얻고
요청 `outputPath`와 일치하는지 확인한다. reparse point로 다른 곳에 쓰이는
것을 막는다.

```text
GetFileInformationByHandle → dwFileAttributes에
  FILE_ATTRIBUTE_REPARSE_POINT가 있으면 거부
```

### 5.2 상속 제어

```text
STARTUPINFOEXW si = {};
si.StartupInfo.cb = sizeof(si);
si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
si.StartupInfo.hStdOutput = <파일 또는 파이프 쓰기 끝>;
si.StartupInfo.hStdError  = <파이프 쓰기 끝>;
si.StartupInfo.hStdInput  = <NUL 장치 핸들>;
```

`PROC_THREAD_ATTRIBUTE_HANDLE_LIST`로 **상속할 핸들을 명시적으로 제한한다.**
`bInheritHandles: TRUE`만 쓰면 프로세스의 모든 상속 가능 핸들이 넘어간다.

```text
UpdateProcThreadAttribute(attrList, 0,
                          PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                          handles, count * sizeof(HANDLE), ...)
```

stdin은 `NUL`로 연결한다. 현재 macOS 코드는 stdin을 설정하지 않아 부모의
stdin을 상속하는데, 그것은 호스트가 보낸 요청 JSON의 잔여 바이트일 수 있다.
Windows에서는 명시적으로 `NUL`을 준다.

## 6. Job Object — 프로세스 트리 정리

현재 macOS 코드에는 **프로세스 트리 개념이 없다.** `scanimage`가 자식을
만들지 않기 때문에 문제가 되지 않았다.

Windows에서는 반드시 Job Object를 쓴다. 이유:

- WSL2 경로를 쓰면 `wsl.exe`가 중간 프로세스가 된다
- `scanimage.exe`가 어떤 이유로 자식을 만들 수 있다
- 타임아웃 종료 시 손자 프로세스가 남으면 장치가 계속 점유된다

```text
job = CreateJobObjectW(nullptr, nullptr);
JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = {};
info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
SetInformationJobObject(job, JobObjectExtendedLimitInformation, &info, sizeof(info));

CreateProcessW(..., CREATE_SUSPENDED | EXTENDED_STARTUPINFO_PRESENT, ...);
AssignProcessToJobObject(job, pi.hProcess);
ResumeThread(pi.hThread);
```

`CREATE_SUSPENDED`로 만들고 Job에 넣은 뒤 재개하는 순서가 중요하다.
그렇지 않으면 자식이 Job 할당 전에 손자를 만들 수 있다.

`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`는 우리 프로세스가 크래시해도
자식이 정리되게 한다.

**주의**: 프로세스가 이미 다른 Job에 속해 있으면(일부 CI, 컨테이너, 디버거
환경) `AssignProcessToJobObject`가 실패할 수 있다. 중첩 Job은 Windows 8
이상에서 지원되지만 제약이 있다. 실패를 치명적으로 다루지 말고
진단에 기록한 뒤 Job 없이 계속한다.

## 7. 경로 검증

요청 `outputPath`에 대한 검증은
[exact-option-contract](../02-frontend-contract/exact-option-contract.md) §3.1이
소유한다. 여기서는 파일을 실제로 연 뒤의 검증만 다룬다.

```text
1. CreateFileW로 연다
2. GetFinalPathNameByHandleW(VOLUME_NAME_DOS)로 최종 경로를 얻는다
3. 최종 경로가 요청 경로와 (대소문자 무시) 같은지 확인
4. GetFileInformationByHandle로 reparse point가 아님을 확인
5. IR 경로도 같은 검사
```

IR 경로는 어댑터가 만든다:

```text
infraredURL(for: outputURL):
    base = 확장자 제거
    ext  = 원래 확장자 (없으면 "tiff")
    base + ".ir." + ext
```

즉 `C:\stage\frame.tiff` → `C:\stage\frame.ir.tiff`.
호스트가 이 경로를 예측할 수 있어야 검증할 수 있다. 규칙을 바꾸지 않는다.

## 8. 세션 소유권

현재 구현의 계약(`SANEBackendProcessOwnershipTests.swift` 592행이 이를 고정한다):

```text
beginScanSession():
    lock
    currentProcess가 있고 실행 중이 아니면 → nil로 정리
    scanCancellationRequested이면 → cancelled
    activeScanSessionID != nil 또는 currentProcess != nil → busy
    새 UUID 생성해 activeScanSessionID에 저장
    반환

endScanSession(id):
    lock
    activeScanSessionID != id → 아무것도 안 함
    currentProcess가 죽어 있으면 정리
    activeScanSessionID = nil
    scanCancellationRequested = false

launchOwnedScanProcess(process, requiresScanSession):
    lock
    currentProcess != nil → busy
    requiresScanSession ? activeScanSessionID != nil : activeScanSessionID == nil
        위반 → busy
    scanCancellationRequested → cancelled
    process.run()
    currentProcess = process
```

핵심 불변식:

1. **한 백엔드 인스턴스에 동시 프로세스는 하나.**
2. 스캔 세션 중에는 유틸리티 실행(`ownedByScanSession: false`)이 불가능하다.
3. 스캔 세션 밖에서는 스캔 프로세스(`requiresScanSession: true`)를 못 띄운다.
4. **이름이나 경로로 전역 프로세스를 찾아 죽이지 않는다.** 자기가 만든
   프로세스 객체만 취소 대상이다.

4번은 보안 요건이다. Windows에서 `scanimage.exe` 이름으로 프로세스를
열거해 죽이면 사용자의 다른 SANE 프런트엔드를 죽이게 된다.

### 8.1 Windows 구현

```text
SRWLOCK 또는 std::mutex 하나
currentProcess: { HANDLE hProcess; HANDLE hJob; DWORD pid; } 또는 null
activeScanSessionID: GUID 또는 null
scanCancellationRequested: bool
```

프로세스가 "실행 중"인지는 `WaitForSingleObject(hProcess, 0)`가
`WAIT_TIMEOUT`을 돌려주는지로 판정한다.

**핸들 누수 주의**: `PROCESS_INFORMATION`의 `hProcess`와 `hThread`를
모두 닫아야 한다. `hThread`는 `ResumeThread` 직후 닫아도 된다.

## 9. 프로세스 종료 감지

```text
RegisterWaitForSingleObject(&waitHandle, hProcess, callback, ctx,
                            INFINITE, WT_EXECUTEONLYONCE)
```

또는 전용 대기 스레드. 콜백에서 해야 할 일은 현재 macOS
`terminationHandler`와 같다.

```text
1. stderr readability 처리 중단
2. 락을 잡고 남은 stderr를 끝까지 읽어 파싱      ← 순서 중요
3. watchdog 종료 및 결과 회수
4. 출력 파일 핸들 닫기
5. currentProcess 정리
6. noteDeviceOpened()
7. 취소/타임아웃/정상 판정 후 완료 통지
```

2번이 왜 중요한지는
[scanimage-invocation](../02-frontend-contract/scanimage-invocation.md) §6.2 참조.

### 9.1 종료 코드

```text
GetExitCodeProcess(hProcess, &code)
```

**주의**: `TerminateProcess(h, n)`으로 죽인 프로세스의 종료 코드는 `n`이다.
우리가 타임아웃으로 죽였다면 그 사실을 별도 상태로 기억하고 있어야 하며,
종료 코드만 보고 판단하면 안 된다. 현재 macOS 코드도
`timeoutState.didTimeOut`을 별도로 유지한다.

`STILL_ACTIVE`(259)를 정상 종료 코드로 오인하지 않도록,
`WaitForSingleObject`가 `WAIT_OBJECT_0`를 돌려준 뒤에만 종료 코드를 읽는다.

## 10. stderr 스트리밍 파싱

획득 실행에서 stderr는 진행률의 원천이다.

```text
전용 스레드:
  loop:
    ReadFile(hStderrRead, buf, sizeof(buf), &n, nullptr)
    실패 또는 n == 0 → 종료
    락 획득
    appendScanimageStderr(디코드된 문자열, ...)
    진행률 레코드가 늘었으면 watchdog.markProgress()
    락 해제
```

### 10.1 인코딩

`scanimage`의 stderr 인코딩이 무엇인지 확인해야 한다.

- MinGW 빌드는 보통 UTF-8을 낸다(로케일 설정에 따라).
- 콘솔 코드 페이지가 개입할 수 있다.
- `LC_ALL=C`이면 ASCII만 나올 가능성이 높다.

**대응**: UTF-8로 디코드하되 실패 시 손실 허용 변환(잘못된 바이트를
U+FFFD로)한다. 진행률 정규식은 ASCII만 쓰므로 실용상 문제가 없다.
**단 오류 메시지를 그대로 wire error에 실을 때는 유효한 UTF-8이어야 한다**
([encoding-and-json](../05-protocol/encoding-and-json.md)).

### 10.2 부분 읽기와 버퍼

```text
scanProgressBuffer는 마지막 160자만 유지한다
```

읽기가 진행률 레코드 중간에서 잘려도 다음 chunk와 합쳐 인식하기 위한 것이다.
Windows에서 읽기 단위가 다르므로 이 동작이 더 자주 필요해질 수 있다.
**160자를 그대로 유지한다.** 늘리면 오래된 레코드가 다시 매치될 수 있다.

레코드 개수 판정 로직:

```text
previousCount = 레코드 수(scanProgressBuffer)
combined = scanProgressBuffer + chunk
foundProgress = 레코드 수(combined) > previousCount
fraction = combined에서 마지막 퍼센트
scanProgressBuffer = combined의 마지막 160자
```

이 산술을 그대로 옮긴다.

## 11. 유틸리티 실행의 타임아웃

```text
utilityProcessTimeout = 180초 (최소 0.05초로 클램프)
```

타이머가 만료하면:

```text
claimTimeout(process):
    lock
    이미 타임아웃했거나 프로세스가 실행 중이 아니면 → false
    timedOut = true
    → true
```

`true`이면 `terminate()` → 0.5초 후 여전히 살아 있으면 `SIGKILL`.

Windows:

```text
CreateThreadpoolTimer 또는 대기 스레드
만료 시:
  claimTimeout
  종료 시도 (→ cancellation 문서 §4)
  0.5초 후 살아 있으면 TerminateProcess(h, 1)
```

## 12. 정리(cleanup) 순서

`defer` 블록이 하는 일:

```text
1. 타이머 취소
2. clearCurrentProcess(proc)   — 같은 객체일 때만 nil로
3. opensDevice이면 noteDeviceOpened()
4. !ownedByScanSession이면 clearUtilityProcessCancellation()
```

`clearUtilityProcessCancellation`:

```text
lock
activeScanSessionID == nil && currentProcess == nil 일 때만
scanCancellationRequested = false
```

즉 스캔 세션이 없을 때만 취소 플래그를 지운다. 세션 중이면 그대로 둔다.

Windows에서는 여기에 **핸들 정리**가 추가된다.

```text
5. 파이프 핸들 4개(각 끝 2개씩) 전부 닫혔는지 확인
6. 출력 파일 핸들 닫기
7. hProcess, hThread 닫기
8. Job 핸들 닫기 (KILL_ON_JOB_CLOSE이므로 마지막에)
9. 스레드 join
```

RAII(C++) 또는 `SafeHandle`/`using`(C#)으로 강제한다. 수동 정리는 예외
경로에서 반드시 새어 나간다.

## 13. 테스트 계획

`SANEBackendProcessOwnershipTests.swift`(592행)와
`VirtualScanimageFixture.swift`(405행)가 현재 무엇을 고정하는지 그대로 옮긴다.

### 13.1 가상 `scanimage`

Windows용 가짜 `scanimage.exe`를 만든다. 요구사항:

- 인자에 따라 정해진 `-L`/`-f`/`-A` 텍스트를 stdout에 출력
- 획득 시 stderr에 `Progress: N%`를 정해진 간격으로 출력하고 stdout에
  유효한 TIFF 바이트 출력
- 지연·정지·크래시·거대 출력을 시나리오로 지정 가능
- 종료 신호에 대한 반응을 시나리오로 지정 가능

Swift 픽스처와 **같은 시나리오 이름**을 쓴다. 두 구현이 같은 시나리오에
같은 결과를 내는지 비교할 수 있다.

### 13.2 반드시 있어야 할 테스트

- [ ] 파이프 버퍼를 넘치게 하는 stdout(1 MiB 이상) → 교착 없음
- [ ] stderr만 넘치게 → 교착 없음
- [ ] 둘 다 넘치게 → 교착 없음
- [ ] 자식이 즉시 종료 → EOF 정상 감지
- [ ] 자식이 결과를 쓰고 즉시 종료 → 마지막 바이트 유실 없음
- [ ] 자식이 정지 → 타임아웃 → 종료 → 핸들 누수 없음
- [ ] 자식이 손자를 만들고 정지 → Job으로 트리 전체 종료
- [ ] 동시 스캔 요청 → 두 번째가 `busy`
- [ ] 스캔 중 유틸리티 실행 시도 → `busy`
- [ ] 공백 포함 인자가 자식에게 온전히 도달 (`CommandLineToArgvW` 왕복)
- [ ] `-` 로 시작하는 장치명 → 거부
- [ ] 출력 경로가 symlink/junction → 거부
- [ ] 100회 반복 후 핸들 수가 증가하지 않음 (`GetProcessHandleCount`)
- [ ] 부모 크래시 후 자식이 남지 않음

## 14. 열린 질문

- WSL2 경로를 지원할 경우 `wsl.exe`의 종료 코드가 내부 `scanimage`의 것을
  그대로 전달하는가
- 콘솔 없는(GUI subsystem) 부모에서 자식을 띄울 때 `CREATE_NO_WINDOW`가
  필요한가, 필요하다면 stderr 리다이렉션과 충돌하지 않는가
- 긴 경로(260자 초과) staging에서 `CreateFileW`가 동작하려면
  매니페스트 long-path 인식이 필요한가
