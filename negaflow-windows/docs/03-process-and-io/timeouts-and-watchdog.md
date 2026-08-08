# 타임아웃과 진행률 watchdog

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 이식 정본 + 재측정 필요
코드 근거: `SANEBackend+Process.swift`(`UtilityProcessTimeoutState`,
`AcquisitionProgressWatchdog`, `usesAutomaticAcquisitionWatchdog`)

관련 문서:

- [child-process](child-process.md)
- [cancellation](cancellation.md)
- [backend-quirks](../02-frontend-contract/backend-quirks.md)

## 1. 세 개의 타임아웃

| 이름 | 기본값 | 적용 대상 | 무엇을 잰다 |
|---|---:|---|---|
| `utilityProcessTimeout` | 180 s | `-L`, `-f`, `-A` | 프로세스 전체 실행 시간 |
| `acquisitionFirstProgressTimeout` | 180 s | 획득 | 시작부터 첫 진행률까지 |
| `acquisitionProgressStallTimeout` | 180 s | 획득 | 마지막 진행률 이후 유휴 시간 |

전부 `max(값, 0.05)`로 클램프된다.

**총 스캔 시간에는 상한이 없다.** 진행률이 계속 오는 한 몇 시간짜리
7200 dpi 스캔도 허용한다. 이것이 설계의 핵심이며, 이식 시 반드시 유지한다.
전체 시간 상한을 두면 고해상도 대형 포맷 스캔이 실패한다.

호스트 쪽 상한은 별개로 존재한다(scan 7,200초). 그것이 최종 안전망이다.

**그러나 `scan` 외의 명령에서는 호스트 상한이 우리 예산보다 좁다.**
본체가 `detect` 90초, `capabilities` 180초를 강제하는데, 우리는 `scanimage`
호출 하나당 180초를 쓰고 한 명령이 여러 번 호출한다. 이대로면 호스트가
우리를 먼저 죽인다 — D-32가 이 문제를 소유한다
→ [host-requirements](../05-protocol/host-requirements.md) §2

## 2. 유틸리티 타임아웃

```text
UtilityProcessTimeoutState:
    lock
    timedOut: bool

    claimTimeout(process) -> Bool:
        lock
        이미 timedOut이거나 process가 실행 중이 아니면 → false
        timedOut = true
        → true

    didTimeOut: lock 후 읽기
```

타이머는 `now + utilityProcessTimeout`에 한 번 발화한다.
발화 시 `claimTimeout`이 참이면:

```text
proc.terminate()
0.5초 후 여전히 실행 중이면 kill(pid, SIGKILL)
```

프로세스 종료 후:

```text
취소 요청됨 → cancelled
timedOut     → timeout "scanimage 조회가 N초 안에 끝나지 않았습니다."
그 외        → 종료 코드 판정
```

**순서가 중요하다.** 취소가 타임아웃보다 우선한다.

### 2.1 Windows 구현

```text
CreateThreadpoolTimer(callback, ctx, nullptr)
SetThreadpoolTimer(timer, &dueTime, 0, 0)   // 주기 0 = 한 번만
```

또는 대기 스레드 하나. `WaitForSingleObject(hProcess, timeoutMs)`가
`WAIT_TIMEOUT`을 돌려주면 타임아웃이다. 이 방식이 더 단순하고,
"프로세스가 실행 중인지" 확인이 자동으로 된다.

```text
DWORD r = WaitForSingleObject(hProcess, (DWORD)(timeout * 1000));
if (r == WAIT_TIMEOUT) {
    claimTimeout();
    // 종료 시도 → cancellation 문서 §5
}
```

정리 시 타이머를 반드시 취소한다(`SetThreadpoolTimer(timer, nullptr, 0, 0)` +
`WaitForThreadpoolTimerCallbacks` + `CloseThreadpoolTimer`).
취소하지 않으면 이미 해제된 컨텍스트를 콜백이 건드린다.

## 3. 획득 watchdog

가장 정교한 부분이다. 그대로 옮긴다.

```text
AcquisitionProgressWatchdog:
    lock
    timer:            타이머 핸들
    observedProgress: bool
    timedOut:         nil | .firstProgress | .stalled
    finished:         bool
    stallTimeout:     TimeInterval
    deadline:         현재 마감 시각
```

### 3.1 `start(firstTimeout:stallTimeout:process:)`

```text
self.stallTimeout = stallTimeout
firstDeadline = now + firstTimeout
self.deadline = firstDeadline
타이머 생성, firstDeadline에 발화하도록 예약
발화 핸들러:
    self, process가 살아 있고 process.isRunning이고
    claimTimeout()이 nil이 아니면:
        process.terminate()
        0.5초 후 살아 있으면 SIGKILL
타이머 시작

lock
finished이면:               ← start 이전에 finish가 불린 경쟁 상황
    unlock, 타이머 취소, 반환
self.timer = timer
unlock
```

마지막 블록이 경쟁 조건 방어다. Windows에서도 필요하다.

### 3.2 `markProgress()`

```text
lock
finished이거나 timedOut != nil이면 → unlock, 반환
observedProgress = true
timer, stallTimeout, deadline = now + stallTimeout 을 로컬로 복사
self.deadline = deadline
unlock
timer?.schedule(deadline: deadline)      ← 락 밖에서 재예약
```

**락 밖에서 재예약**하는 것이 의도적이다. 타이머 API가 콜백과 동기화할 수
있으므로 락을 쥔 채 호출하면 교착 가능성이 있다.

Windows: `SetThreadpoolTimer`를 락 밖에서 호출한다.

### 3.3 `finish()`

```text
lock
finished = true
didTimeOut, didObserveProgress, timer를 로컬로 복사
self.timer = nil
unlock
timer?.cancel()
→ (didTimeOut, didObserveProgress)
```

### 3.4 `claimTimeout()` — 재예약 경쟁 방어

```text
lock
finished이거나 timedOut != nil이면 → unlock, nil

now = 현재 시각
now < deadline 이면:              ← 마감이 뒤로 밀렸는데 타이머가 먼저 발화한 경우
    timer, deadline을 로컬로 복사
    unlock
    timer?.schedule(deadline: deadline)   ← 다시 예약하고 이번 발화는 무시
    → nil

kind = observedProgress ? .stalled : .firstProgress
timedOut = kind
unlock
→ kind
```

**이 재검사가 없으면 잘못된 타임아웃이 발생한다.** `markProgress`가
마감을 미룬 직후 이전 예약이 발화할 수 있기 때문이다.

Windows 스레드 풀 타이머도 같은 경쟁이 있다. `SetThreadpoolTimer`로
마감을 미뤄도 이미 큐에 들어간 콜백은 실행된다. **반드시 콜백 안에서
현재 시각과 마감을 다시 비교한다.**

시각 비교는 **단조 시계**를 쓴다. `DispatchTime.now().uptimeNanoseconds`가
현재 코드의 기준이다. Windows에서는 `QueryPerformanceCounter` 또는
`GetTickCount64`. `GetSystemTime` 계열은 시스템 시각 변경에 영향받으므로
쓰지 않는다.

### 3.5 결과 해석

```text
watchdogResult = watchdog.finish()

취소 요청됨:
    → cancelled
watchdogResult.timeout == .firstProgress:
    → timeout "scanimage가 N초 안에 첫 이미지 데이터를 반환하지 않았습니다."
watchdogResult.timeout == .stalled:
    → timeout "scanimage 진행률이 N초 동안 갱신되지 않았습니다."
그 외:
    → (exitCode, madeProgress: watchdogResult.observedProgress)
```

`madeProgress`는 stale-retry 판정에 쓰인다
([scanimage-invocation](../02-frontend-contract/scanimage-invocation.md) §5).

**이식 개선 — 구현됨(2026-08-05).** 현재 macOS 는 genesys 재시도 조건을
오류 메시지에 `"첫 이미지 데이터"`가 들어 있는지로 판정한다. 그 문구를
영어로 바꾸면 **재시도가 조용히 사라진다.**

Windows 구현은 `windows/src/process/acquisition.h` 의 `TimeoutKind`
(`None`/`FirstProgress`/`Stalled`)를 결과 구조체에 실어 종류로 판정한다.
`decideRetry()` 가 그 판정을 하고 단위 테스트가 네 갈래를 고정한다.

**동작은 같다.** 문자열 의존만 사라졌다. macOS 에도 같은 구조를 적용하는
것을 권장하며, 그 전까지 두 구현은 같은 입력에 같은 결정을 내린다.

```text
struct ScannerError {
    Code code
    string message
    optional<AcquisitionTimeoutKind> timeoutKind   // 신규
}
```

## 4. pieusb 예외

```text
usesAutomaticAcquisitionWatchdog(backend) = backend != "pieusb"
```

`pieusb`는 shading/calibration과 실제 acquisition을 `sane_start` 안에서
동기 실행해 첫 progress가 장시간 없을 수 있다. 중간 종료는 transport 상태를
불명확하게 만들므로 **사용자 취소만 허용한다.**

즉 pieusb 스캔에는 watchdog 자체가 시작되지 않는다. 무한정 매달릴 수 있다.

**Windows에서도 동일하다.** 다만 MSYS2 빌드에 `pieusb`가 없으므로
재빌드 전에는 이 경로가 도달 불가능하다
([building-sane](../01-sane-runtime/building-sane.md) §3).

## 5. 진행률의 정의

watchdog이 보는 "진행"은 **stderr에 진행률 레코드가 새로 나타난 것**이다.
값이 증가했는지는 보지 않는다.

```text
appendScanimageStderr(...) -> Bool:
    previousCount = 레코드 수(scanProgressBuffer)
    combined = scanProgressBuffer + chunk
    foundProgress = 레코드 수(combined) > previousCount
    fraction이 있으면 progress 콜백 호출
    scanProgressBuffer = combined의 마지막 160자
    → foundProgress
```

레코드 정규식:

```text
(?i)progress\s*:?\s*(?:\([^)]*\)|[0-9]{1,3}(?:[.,][0-9]+)?\s*%)
```

퍼센트 형태와 괄호 형태를 모두 센다. 백엔드에 따라
`Progress: (34/512)` 같은 형태가 나올 수 있기 때문이다.

분수 정규식:

```text
(?i)progress\s*:?\s*([0-9]{1,3}(?:[.,][0-9]+)?)\s*%
```

**마지막** 매치를 쓰고, 콤마를 점으로 바꾼 뒤 파싱하고, 0…1로 클램프한다.

### 5.1 Windows 정규식 주의

- .NET `Regex`와 C++ `std::regex`, PCRE의 동작이 미묘하게 다르다.
  특히 `\s`의 유니코드 범위.
- `LC_ALL=C` 전제이므로 ASCII만 나온다. `\s`를 `[ \t]`로 명시해도 된다.
- **백트래킹 폭발 방지**: 입력은 최대 160자 + chunk다. 현재 패턴은
  중첩 반복이 없어 안전하다. 패턴을 "개선"하지 않는다.
- 컴파일된 정규식을 재사용한다(매 chunk마다 컴파일하지 않는다).

## 6. 재측정 계획

180초와 0.5초는 macOS 실측 기반이다. Windows에서 다시 잰다.

### T-1 — 첫 진행률까지의 시간

```text
백엔드별, 해상도별로:
  scanimage 시작 → 첫 Progress 출력까지의 시간
  20회 측정, p50/p95/p99 기록
```

특히 확인할 것:

- 램프 예열이 있는 장치(epson2 평판)
- calibration이 긴 장치(genesys 고해상도)
- WSL2 경로의 추가 지연

### T-2 — 진행률 간격

```text
연속된 Progress 출력 사이의 최대 간격
해상도가 높을수록, 스트립이 클수록 길어진다
```

`acquisitionProgressStallTimeout`은 이 최댓값보다 충분히 커야 한다.

### T-3 — 유틸리티 실행 시간

```text
scanimage -f          → 장치 수에 따라
scanimage -A -d <dev> → 백엔드별
```

180초는 매우 넉넉하지만, WSL2 경로나 네트워크 경로에서는 다를 수 있다.

### T-4 — 취소 유예

[cancellation](cancellation.md) C-3과 동일.

## 7. 값 결정 원칙

측정 후 값을 정할 때:

```text
firstProgressTimeout  >= p99(첫 진행률) × 3
stallTimeout          >= p99(진행률 간격) × 3
utilityTimeout        >= p99(유틸리티 실행) × 3
```

3배 여유를 두는 이유: 사용자 환경은 측정 환경보다 느리다(백그라운드 작업,
안티바이러스, 저속 USB 허브, 절전 모드).

**너무 짧은 타임아웃이 너무 긴 타임아웃보다 나쁘다.** USB 전송 중에
프로세스를 죽이면 장치가 반쯤 열린 상태로 남는다. 반면 너무 길면
사용자가 오래 기다릴 뿐이고 호스트 상한이 결국 개입한다.

## 8. 환경 변수로 조정 가능하게

현재는 `SANEBackend`의 `init`에만 인자가 있고 환경 변수로 조정할 수 없다
(테스트만 다른 값을 쓴다). Windows에서는 진단을 위해 노출한다.

```text
NEGAFLOW_UTILITY_TIMEOUT_SEC
NEGAFLOW_FIRST_PROGRESS_TIMEOUT_SEC
NEGAFLOW_PROGRESS_STALL_TIMEOUT_SEC
```

파싱 실패나 범위 밖 값은 기본값을 쓴다. 값을 사용했다면 진단에 기록한다.
**사용자에게 이 변수를 일반 해결책으로 안내하지 않는다.** 타임아웃을
늘려야 한다면 그것은 진단해야 할 문제다.

## 9. 이식 체크리스트

- [ ] 세 타임아웃이 별개로 존재하고 총 시간 상한이 없다
- [ ] `claimTimeout`의 마감 재검사가 구현됐다
- [ ] `markProgress`의 재예약이 락 밖에서 일어난다
- [ ] `start`/`finish` 경쟁 방어가 있다
- [ ] 단조 시계를 쓴다
- [ ] 타임아웃 종류가 오류에 구조적으로 실린다
- [ ] pieusb에서 watchdog이 시작되지 않는다
- [ ] 진행률 레코드 개수 판정 산술이 동일하다
- [ ] 160자 버퍼
- [ ] 정규식을 한 번만 컴파일한다
- [ ] 정리 시 타이머 콜백 완료를 대기한다
- [ ] 취소가 타임아웃보다 우선한다

## 10. 테스트

가상 `scanimage`가 지원해야 할 시나리오:

| 시나리오 | 기대 |
|---|---|
| 진행률 없이 즉시 종료 | 타임아웃 아님. 종료 코드로 판정 |
| 진행률 없이 무한 대기 | `firstProgress` 타임아웃 |
| 진행률 후 무한 대기 | `stalled` 타임아웃 |
| 진행률을 stall 직전마다 출력 | 타임아웃 없음, 무한정 계속 |
| 진행률을 한 번에 몰아서 출력 | 레코드 수 증가 감지 |
| 잘린 진행률 레코드 | 다음 chunk와 합쳐 인식 |
| 콤마 소수점 | 인식 |
| 괄호 형태 | 레코드로 세되 분수는 없음 |
| 100% 초과 값 | 1.0으로 클램프 |
| 진행률 도중 취소 | `cancelled`, 타임아웃 아님 |
| pieusb 백엔드로 무한 대기 | 타임아웃 없음 |
