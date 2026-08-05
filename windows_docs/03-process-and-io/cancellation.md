# 취소

기준일: 2026-08-04
기준 커밋: c554aaf
상태: **설계 필요** — Windows에 직접 대응이 없는 유일한 계층
코드 근거: `Sources/negaflow-scanner-sane/main.swift`(`installScanCancellationForwarders`),
`SANEBackend+Process.swift`(`cancelScan`, `requestOwnedScanCancellation`)

관련 문서:

- [child-process](child-process.md)
- [timeouts-and-watchdog](timeouts-and-watchdog.md)
- [wire-contract](../05-protocol/wire-contract.md)

## 1. 현재 macOS 취소 사슬

```text
사용자가 negaflow에서 취소
   ↓
호스트가 플러그인 프로세스에 SIGTERM
   ↓
main.swift의 DispatchSourceSignal → backend.cancelScan()
   ↓
scanCancellationRequested = true
currentProcess.terminate()          (scanimage에 SIGTERM)
   ↓ 0.5초
여전히 살아 있으면 kill(pid, SIGKILL)
   ↓
scanimage가 SIGTERM에서 sane_cancel() 호출
   ↓
SANE 백엔드가 장치 점유 해제, 램프 끔, 전송 중단
   ↓
플러그인이 cancelled 오류 이벤트 후 exit 1
```

**핵심**: `scanimage`가 SIGTERM을 받아 `sane_cancel()`을 호출하는 것이
전체 설계의 전제다. 그것 없이 프로세스를 죽이면 스캐너가 전송 중간
상태로 남아 다음 open이 실패한다.

## 2. Windows에는 SIGTERM이 없다

정확히 말하면:

- Windows CRT에 `SIGTERM` 상수는 있지만 **다른 프로세스에 보낼 방법이 없다.**
  `raise()`로 자기 자신에게만 보낼 수 있다.
- `TerminateProcess`는 즉시 강제 종료다. 정리 코드가 실행되지 않는다.
  `sane_cancel()`이 호출되지 않는다.

즉 **현재 취소 사슬의 두 번째 고리와 네 번째 고리가 모두 끊긴다.**

## 3. 두 개의 취소가 있다

혼동하지 않아야 한다.

| 취소 | 보내는 쪽 | 받는 쪽 | 현재 수단 |
|---|---|---|---|
| A. 호스트 → 플러그인 | negaflow | `negaflow-scanner-sane` | **SIGTERM 또는 SIGINT** |
| B. 플러그인 → scanimage | 플러그인 | `scanimage` | SIGTERM |

A는 두 신호를 모두 받는다(`[SIGTERM, SIGINT]`). SIGINT는 사용자가 터미널에서
직접 실행하고 Ctrl+C를 누르는 경우를 위한 것이다. Windows 대응인
`SetConsoleCtrlHandler`도 **`CTRL_C_EVENT`와 `CTRL_BREAK_EVENT`를 모두**
받아야 같은 동작이 된다(§6).

각 신호는 `signal(sig, SIG_IGN)` 후 `DispatchSource`로 받는다.
**무시 설정이 먼저 와야 한다** — `DispatchSourceSignal`은 기본 처리가
비활성화된 신호만 관측한다. 이 순서를 바꾸면 첫 SIGTERM에 프로세스가
그냥 죽는다.

A는 호스트 계약이며 negaflow 본체 windows_docs의
`10-scanner/plugin-architecture.md` §11이 소유한다. 거기서는
"adapter별 graceful cancel 신호 또는 control channel 사용"이라고만
정하고 구체적 수단은 열어두었다.

B는 **이 저장소가 정해야 한다.**

## 4. B의 후보

### 4.1 콘솔 제어 이벤트 (`GenerateConsoleCtrlEvent`)

```text
CreateProcessW(..., CREATE_NEW_PROCESS_GROUP, ...)
GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, pid)
```

CRT는 `CTRL_BREAK_EVENT`를 `SIGBREAK`로, `CTRL_C_EVENT`를 `SIGINT`로 매핑한다.
`scanimage`가 `SIGINT` 핸들러를 설치하고 있다면 `CTRL_C_EVENT`가 통할 수 있다.

**문제점**

- `CTRL_C_EVENT`는 프로세스 그룹 ID 0(자기 그룹 전체)에만 보낼 수 있다는
  제약이 있다. 특정 프로세스에만 보내려면 `CTRL_BREAK_EVENT`와
  `CREATE_NEW_PROCESS_GROUP`을 써야 한다.
- **콘솔이 필요하다.** MS 문서: "Only those processes in the group that
  **share the same console as the calling process** receive the signal."
  플러그인이 negaflow(GUI)의 자식이면 콘솔이 없다.

#### 해결됨 (2026-08-06, 실측)

콘솔이 없으면 어댑터가 직접 하나를 만들고 창을 숨긴다
(`process::ensureConsoleForCancellation`). 이 경로 없이는 취소가
`TerminateProcess` 로만 끝나고, **전송 도중에 죽은 OpticFilm 8100 은 전원을
다시 넣기 전까지 돌아오지 않는다** — 강제 종료 직후 다음 읽기가
`sane_read: Error during device I/O`, 그 뒤 열기가 `Invalid argument` 였다.
워치독이 바로 그 동작을 하므로 제품 경로다.

`AllocConsole` 은 표준 핸들 셋을 새 콘솔로 **덮어쓴다**(MS 문서). 그대로
두면 stdout 이 wire 프로토콜에서 콘솔로 옮겨간다. 그래서 부르기 전에 세 개를
저장했다가 `SetStdHandle` 로 되돌린다. 제어 핸들러 표도 초기화되므로
`installConsoleCancellation` 을 그 뒤에 부른다.

실측 결과:

```text
콘솔 없이 CTRL_BREAK      실패        MS 문서대로
AllocConsole + 창 숨김    성공
stdout 이 아직 파이프인가  예          핸들 복원이 동작한다
숨긴 콘솔로 CTRL_BREAK    성공        자식이 Control-Break 를 받아 출력했다
```

`plugin_smoke` 가 어댑터를 stdio 로 끝까지 구동하므로 wire 프로토콜이
멀쩡하다는 증거도 함께 있다.

**여기까지는 신호가 도달한다는 것뿐이다.** 처음에 이것만 보고 문제가
해결됐다고 적었는데 틀렸다. 신호가 가도 `scanimage` 가 그것으로 무엇을 하는지가
따로 있고, 거기에 두 겹의 문제가 더 있었다 — §4.1a.

#### 4.1a `scanimage` 쪽 두 겹 (2026-08-06, 실기)

판정 기준은 하나다. **취소 뒤에 다음 스캔이 되는가.** 종료 코드나 신호 전달
여부로 판정하면 안 된다.

| 단계 | 결과 | 무엇을 배웠나 |
| --- | --- | --- |
| `TerminateProcess` | 망가짐 | 전송 도중 종료가 문제다 |
| 숨긴 콘솔 + `CTRL_BREAK` | `0xC000013A` 로 종료, 망가짐 | `scanimage` 에 **핸들러가 없다** |
| `SIGBREAK` 핸들러 추가 | `0xC0000005` 크래시, 망가짐 | `sane_cancel` 이 **다른 스레드**에서 불린다 |
| 플래그 + 읽기 루프가 취소 | **통과** | 백엔드를 한 스레드만 만진다 |

둘째 줄: `scanimage` 는 `SIGINT`/`SIGTERM` 만 등록한다. MS 문서 —
"CTRL+C or CTRL+BREAK is treated as a signal (SIGINT or **SIGBREAK**)" — 이라
`CTRL_BREAK` 는 어느 쪽에도 걸리지 않고 기본 동작이 프로세스를 끝낸다.

셋째 줄: `SIGBREAK` 를 등록했더니 핸들러는 돌았는데(`received signal 21` /
`trying to stop scanner`) 171 ms 뒤 접근 위반으로 터졌다. MS 문서 —
"The system creates a new thread in each client process to handle the event."
메인 스레드가 `sane_read` 안에 있는데 다른 스레드가 `sane_cancel` 을 부르니
자료 경쟁이다. Unix 는 핸들러가 메인 스레드를 가로채므로 upstream 코드가
그대로 성립한다.

넷째 줄이 답이다. 핸들러는 플래그만 세우고, 읽기 루프가 자기 스레드에서
`sane_cancel` 을 부른다. 그 뒤 `sane_read` 가 `SANE_STATUS_CANCELLED` 를
돌려주므로 기존 종료 경로가 그대로 탄다.

```text
1) 기준선 스캔        21초  3,030,277 바이트  OK
2) CTRL_BREAK        received signal 21
                     trying to stop scanner
                     sane_read: Operation was canceled
                     종료 코드 2, 6,890 ms
3) 취소 뒤 스캔       17초  3,030,277 바이트  OK
```

패치: `sane-runtime/patches/007-cancel-on-sigbreak.patch`.

**그리고 그 6,890 ms 가 유예 시간을 정한다.** 예전 값 2,000 ms 로는 취소가
끝나기 전에 `TerminateProcess` 로 넘어가 스캐너를 죽였을 것이다. 신호를 받은
뒤 진행 중인 `sane_read` 가 끝나기를 기다리고 `sane_cancel` 이 헤드를 홈으로
돌리는 시간이 그 안에 있다. `kCancelGracePeriod` 를 15,000 ms 로 올렸다.
- **`scanimage`가 `SIGINT`/`SIGBREAK` 핸들러를 실제로 설치하는지 미확인.**
  Unix용 코드는 `SIGINT`/`SIGTERM`/`SIGHUP` 핸들러를 설치하지만
  MinGW 빌드에서 그 코드가 컴파일되는지, `SIGBREAK`가 매핑되는지 확인이 필요하다.

→ spike C-1

### 4.2 stdin 닫기

`scanimage`는 stdin을 읽지 않는다(우리는 `NUL`을 연결한다). 신호로 쓸 수 없다.

### 4.3 `TerminateProcess` 직행

```text
TerminateProcess(hProcess, 1)
```

가장 확실하게 프로세스를 없앤다. 그러나 `sane_cancel()`이 호출되지 않는다.

**결과 예측**:

- USB 핸들이 OS에 의해 닫힌다. WinUSB 핸들은 프로세스 종료 시 커널이 정리한다.
- 스캐너 펌웨어는 전송 중이던 상태로 남는다. 다음 `sane_open`에서
  "device busy" 또는 타임아웃이 날 수 있다.
- 램프가 켜진 채 남을 수 있다.
- 필름 이송 장치(pieusb의 슬라이드 이동)가 중간 상태로 멈출 수 있다.

pieusb에서 watchdog을 끈 이유가 정확히 이것이다 — "중간 종료는 transport
상태를 불명확하게 만든다".

### 4.4 취소 없음 + 타임아웃만

취소를 지원하지 않고 스캔이 끝날 때까지 기다린다. 7200 dpi 다중 노출은
수십 분이다. **제품으로 성립하지 않는다.**

## 5. 권장 설계

```text
1. CTRL_BREAK_EVENT를 시도한다 (spike C-1이 통과하면)
2. 유예 시간 동안 종료를 기다린다
3. 유예 시간이 지나면 Job Object 종료 또는 TerminateProcess
4. 어느 경로로 끝났는지를 기록하고, 강제 종료였으면
   다음 장치 open 전에 복구 절차를 수행한다
```

### 5.1 유예 시간

현재 macOS는 `terminate()` 후 **0.5초**를 기다린다. 이 값은 SIGTERM이
`sane_cancel()`을 트리거하고 백엔드가 정리하는 시간에 대한 추정이다.

Windows에서는 재측정한다. 측정 방법:

```text
1. 스캔 시작
2. 진행률 30%에서 취소
3. scanimage 종료까지의 시간 측정
4. 즉시 새 스캔 시작 → 성공 여부 측정
5. 백엔드별로 반복
```

`sane_cancel()`은 백엔드에 따라 즉시 반환하기도 하고 현재 전송 블록이
끝날 때까지 기다리기도 한다. 고해상도 스캔의 한 스트립이 수백 ms일 수 있다.
**0.5초가 부족할 가능성이 실재한다.**

권장 초기값: **2초**, 백엔드별 조정 가능하게. 호스트의 scan 유예(5초)
안에 들어야 한다.

### 5.2 강제 종료 후 복구

```text
강제 종료했다면:
  1. 주소 캐시를 무효화한다 (invalidateAddressCache)
  2. 다음 장치 open 전에 최소 대기(예: 1초)
  3. 첫 open 실패를 stale로 간주해 재시도 횟수를 1회 늘린다
  4. 진단에 "강제 종료 후 첫 열기"를 기록한다
```

이 복구는 현재 macOS 코드에 없다. Windows에서 강제 종료가 기본 경로가
되므로 필요해진다.

### 5.3 pieusb 예외

pieusb는 이미 watchdog을 끄고 있다. 취소도 마찬가지로 신중해야 한다.

```text
pieusb + 강제 종료:
  사용자에게 명시적으로 경고한다
  "이 스캐너는 스캔을 중간에 멈추면 필름 이송 위치가 불확실해질 수 있습니다.
   다음 스캔 전에 필름 위치를 확인하십시오."
```

wire의 `warnings` 배열로 전달할 수 있다.

## 6. A(호스트 → 플러그인)의 Windows 설계

이 저장소가 정하지는 않지만, 어댑터가 무엇을 받을 준비를 해야 하는지는
정해야 한다.

가능한 수단:

| 수단 | 어댑터가 할 일 |
|---|---|
| `CTRL_BREAK_EVENT` | 콘솔 제어 핸들러 등록(`SetConsoleCtrlHandler`) |
| 이름 있는 이벤트 객체 | 시작 시 인자로 받은 이름의 이벤트를 대기 |
| stdin EOF | stdin이 닫히면 취소로 간주 |
| `TerminateProcess` | 아무것도 못 함. 자식 정리는 Job Object가 |

**권장: stdin EOF + Job Object.**

이유:

- stdin은 이미 프로토콜의 일부다(요청 JSON). 호스트가 요청을 쓰고 닫는다.
- **추가로**: 호스트가 파이프를 열어둔 채 요청만 쓰고, 취소할 때 닫는 방식으로
  바꾸면 신호 채널이 생긴다. 그러나 **이것은 현재 wire 계약 변경이다.**
  현재 계약은 "호스트가 write를 끝내고 pipe를 닫는다"이다.
- 따라서 v2에서는 stdin을 신호로 쓸 수 없다.

현실적 v2 설계:

```text
호스트가 Job Object로 어댑터를 감싸고, 취소 시:
  1. CTRL_BREAK_EVENT 시도 (콘솔이 있으면)
  2. 유예 대기
  3. TerminateJobObject

어댑터는:
  SetConsoleCtrlHandler로 CTRL_BREAK/CTRL_C를 받으면 cancelScan()
  받지 못하고 강제 종료되면 → Job Object가 scanimage도 함께 죽인다
```

`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`가 있으므로 어댑터가 강제 종료돼도
`scanimage`가 남지 않는다. **이것이 최소 안전 보장이다.**

v3에서 명시적 제어 채널을 도입하는 것이
[wire-contract](../05-protocol/wire-contract.md) §9(v3 후보)의 항목이다.

## 7. 취소 상태 기계

현재 구현의 계약:

```text
scanCancellationRequested: bool

requestOwnedScanCancellation():
    lock
    activeScanSessionID == nil && currentProcess == nil → nil 반환(할 일 없음)
    scanCancellationRequested = true
    currentProcess 반환

cancelScan():
    process = requestOwnedScanCancellation()
    process가 nil이거나 실행 중이 아니면 → 반환
    terminate()
    0.5초 대기
    여전히 실행 중이면 SIGKILL

isScanCancellationRequested(): lock 후 플래그 읽기
```

플래그를 확인하는 지점:

- `beginScanSession` — 이미 취소 요청이 있으면 세션을 시작하지 않는다
- `launchOwnedScanProcess` — 취소 중이면 새 프로세스를 띄우지 않는다
- `runScanimage` 종료 후 — 취소면 `cancelled` 오류
- `runScanimageTo`의 termination 핸들러 — 취소면 `cancelled` 오류
- `runSingleAcquisition` — 획득 후 취소 확인
- genesys 재시도 조건

플래그를 지우는 지점:

- `endScanSession` — 세션이 끝날 때
- `clearUtilityProcessCancellation` — 유틸리티 실행이 끝났고 세션이 없을 때

**이 여덟 지점을 그대로 이식한다.** 하나라도 빠지면 취소 후에도 다음 패스가
시작되거나, 취소가 영구히 남아 이후 스캔이 전부 실패한다.

## 8. 취소의 wire 표현

```text
{"type":"error","protocolVersion":2,"requestID":"…","sequence":N,
 "message":"cancelled: 스캔이 취소되었습니다."}
```

exit code 1.

호스트 관점에서 이것은 다른 오류와 구분되지 않는다. `ScannerError.Code`가
wire에 없기 때문이다([exact-option-contract](../02-frontend-contract/exact-option-contract.md) §7).
호스트는 자신이 취소를 요청했다는 사실로 판단한다.

**이식 시 유지**: 취소 메시지 형식을 바꾸지 않는다. 호스트가 문자열을
파싱하지는 않지만, 진단 로그의 비교 가능성이 떨어진다.

## 9. 정리 책임

취소 시 지워야 할 것:

```text
runSingleAcquisition의 catch:
    출력 파일 삭제 (try? FileManager.removeItem)

acquireInfraredPass의 catch:
    IR 파일 삭제

startSoftwareMultiPassScan의 defer:
    NEGAFLOW_KEEP_MULTIPASS가 아니면 중간 샘플 TIFF 전부 삭제
```

Windows에서 파일 삭제가 실패할 수 있는 경우가 macOS보다 많다.

- 자식 프로세스가 아직 핸들을 붙들고 있다 → 삭제 실패
- 안티바이러스가 스캔 중이다 → 일시적 실패

**대응**: 삭제 전에 자식 프로세스 종료를 확인한다. 실패해도 무시하되
(현재 `try?`와 같음) 진단에 기록한다. 호스트가 staging 디렉터리 전체를
정리하므로 최종 안전망이 있다.

`FILE_FLAG_DELETE_ON_CLOSE`를 쓰면 자동 정리가 되지만, 정상 경로에서는
파일을 남겨야 하므로 쓸 수 없다.

## 10. Spike 명세

### C-1 — `scanimage.exe`가 콘솔 제어 이벤트에 반응하는가

```text
1. CREATE_NEW_PROCESS_GROUP으로 scanimage.exe 스캔 시작
2. 진행률이 나오기 시작하면 GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, pid)
3. 종료하는가? 종료까지 시간은?
4. CTRL_C_EVENT로도 시도
5. 종료 후 즉시 같은 장치를 다시 열 수 있는가
6. 콘솔 없는 부모(GUI subsystem)에서도 동작하는가
```

통과하면 graceful cancel이 가능하다. 실패하면 §4.3 + §5.2가 유일한 경로다.

### C-2 — 강제 종료 후 장치 복구

```text
백엔드별로:
1. 스캔 시작, 30% 지점에서 TerminateProcess
2. 즉시 scanimage -L → 장치가 보이는가
3. 즉시 scanimage -A -d <dev> → 성공하는가
4. 실패하면 몇 초 후 성공하는가
5. 물리적 재연결이 필요한가
6. 램프가 꺼지는가
```

결과가 §5.1의 유예 시간과 §5.2의 복구 절차를 정한다.

### C-3 — 취소 지연 측정

```text
graceful cancel(C-1 통과 시)과 강제 종료 각각에 대해:
  취소 요청 → 프로세스 종료까지
  프로세스 종료 → 다음 스캔 성공까지
백엔드별, 해상도별로 측정
```

### C-4 — 다중 패스 중 취소

```text
1. 다중 노출 스캔 시작 (3~12 패스)
2. 2번째 패스 중 취소
3. 중간 TIFF가 전부 지워지는가
4. 다음 스캔이 정상 동작하는가
```

## 11. 이식 체크리스트

- [ ] 취소 플래그 확인 지점 8곳, 해제 지점 2곳
- [ ] `requestOwnedScanCancellation`의 "할 일 없음" 반환 조건
- [ ] 자기가 만든 프로세스만 취소 대상 (이름으로 찾지 않음)
- [ ] 유예 시간이 측정 기반으로 정해졌다
- [ ] 강제 종료 후 복구 절차가 구현됐다
- [ ] Job Object로 어댑터 강제 종료 시 `scanimage`도 정리된다
- [ ] 취소 시 출력 파일과 중간 파일이 지워진다
- [ ] pieusb 취소 경고가 warnings에 실린다
- [ ] 취소 wire 메시지 형식이 동일하다

## 12. 열린 질문

- MinGW `scanimage`가 signal 핸들러를 설치하는가 (C-1)
- `sane_cancel()`이 백엔드별로 얼마나 걸리는가 (C-3)
- 강제 종료 후 램프가 켜진 채 남는 백엔드가 있는가 (C-2)
- 호스트가 어떤 취소 수단을 쓸지 (본체 windows_docs 결정 대기)
- v3에서 명시적 제어 채널을 도입할 가치가 있는가
