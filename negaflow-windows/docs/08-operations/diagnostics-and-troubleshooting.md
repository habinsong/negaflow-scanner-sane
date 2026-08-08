# 진단과 문제 해결

기준일: 2026-08-04
상태: 설계
목적: README의 macOS 문제 해결 절차를 Windows로 옮기고, 로그 정책을 정한다

관련 문서:

- [usb-transport](../01-sane-runtime/usb-transport.md)
- [driver-conflicts](../09-hardware/driver-conflicts.md)
- [environment-and-paths](../03-process-and-io/environment-and-paths.md)

## 1. 진단의 원칙

README가 macOS에서 정립한 원칙이 그대로 유효하다.

> **승인됨**은 플러그인 실행 파일이 실행을 허가받았다는 뜻이다.
> 스캐너를 찾았다는 뜻이 아니다. 탐지는 `scanimage -L`이 돌려주는 것이
> 전부이므로, 거기 없는 스캐너는 negaflow에도 없다. 앱이나 플러그인을
> 다시 설치해도 달라지지 않는다.

Windows에서 여기에 한 층이 추가된다.

> **USB 장치 관리자에 보이는 것**과 **libusb가 열 수 있는 것**은 다르다.
> 벤더 드라이버가 바인딩된 장치는 장치 관리자에 정상으로 보이지만
> `scanimage -L`에는 나타나지 않는다.

## 2. 실패 계층 판정

macOS의 3단계가 Windows에서 4단계가 된다.

```text
1. 장치 관리자에 스캐너가 보이는가
2. 드라이버가 WinUSB(또는 libusbK/libusb0)인가
3. scanimage -f 가 장치를 나열하는가
4. 플러그인 detect 가 장치를 반환하는가
```

| 1 | 2 | 3 | 4 | 문제 위치 |
|---|---|---|---|---|
| 없음 | — | 없음 | 없음 | 케이블·포트·전원. USB 이전 |
| 있음 | 벤더 | 없음 | 없음 | **드라이버 바인딩 필요** |
| 있음 | WinUSB | 없음 | 없음 | SANE 백엔드가 이 모델을 모른다 |
| 있음 | WinUSB | 있음 | 없음 | 플러그인이 SANE를 찾지 못한다 |
| 있음 | WinUSB | 있음 | 있음 | negaflow 쪽. 재승인 |

**두 번째 행이 Windows 고유의 가장 흔한 실패다.** macOS에는 대응이 없다.

### 2.1 사용자가 실행할 명령

```powershell
# 1. USB 장치 목록
Get-PnpDevice -Class USB | Format-Table Status, Class, FriendlyName, InstanceId
```

또는 장치 관리자에서 확인.

```powershell
# 2. 드라이버 확인
Get-PnpDevice -InstanceId "USB\VID_07B3&PID_130D*" |
    Get-PnpDeviceProperty -KeyName DEVPKEY_Device_DriverDesc
```

```powershell
# 3. SANE 장치 목록
& "$env:LOCALAPPDATA\Negaflow\ScannerPlugins\sane\sane\bin\scanimage.exe" -f "%d`t%v`t%m`t%t%n"
```

```powershell
# 4. 플러그인
& "$env:LOCALAPPDATA\Negaflow\ScannerPlugins\sane\negaflow-scanner-sane.exe" detect
```

### 2.2 진단 서브커맨드 추가를 권장

사용자가 네 단계를 손으로 하는 것은 부담이다.

```text
negaflow-scanner-sane.exe diagnose
```

출력(사람이 읽는 형태, stderr):

```text
negaflow-scanner-sane 1.0.3 (win-x64)

[플러그인]
  실행 파일: C:\Users\...\negaflow-scanner-sane.exe
  서명: 유효 (<subject>)

[SANE 런타임]
  scanimage: C:\Users\...\sane\bin\scanimage.exe
  버전: 1.4.0
  서명: 유효
  SANE_CONFIG_DIR: C:\Users\...\sane\etc\sane.d  (존재함)
  활성 백엔드: genesys, epson2, epsonds, coolscan2, coolscan3, pieusb

[USB 장치]
  07B3:130D  Plustek OpticFilm 8200i   드라이버: WinUSB    ✓
  04B8:0151  EPSON GT-X980             드라이버: EPSON USB  ✗ WinUSB 아님

[SANE 장치 목록]
  genesys:libusb:001:004   Plustek   OpticFilm 8200i   film scanner

[결론]
  1개 장치를 사용할 수 있습니다.
  EPSON GT-X980은 제조사 드라이버를 쓰고 있어 이 플러그인이 사용할 수
  없습니다. 드라이버를 WinUSB로 바꾸면 사용할 수 있지만 Epson Scan 2를
  쓸 수 없게 됩니다.
```

**이 한 명령이 문제 해결 문서의 절반을 대체한다.**
macOS에도 추가할 가치가 있다.

`diagnose`는 wire 프로토콜이 아니므로 stdout에 JSON을 쓰지 않는다.
stderr에 사람이 읽는 형태로 쓰고 exit 0.

## 3. 문제 해결 표 (Windows)

README의 표를 대응시킨다.

| 증상 | 원인 | 조치 |
|---|---|---|
| `scanimage.exe`를 찾을 수 없음 | 설치가 불완전하거나 경로가 바뀜 | 플러그인 재설치 |
| 장치 관리자에 스캐너가 없음 | 허브·독·어댑터·케이블·전원 | 직접 연결. USB 2.0 필름 스캐너는 USB-C 어댑터에서 자주 실패한다 |
| 장치 관리자에 있으나 `scanimage -f`가 비어 있음, 드라이버가 벤더 것 | 드라이버 바인딩 필요 | 드라이버 바인딩 도구 실행 |
| 드라이버가 WinUSB인데도 `scanimage -f`가 비어 있음 | SANE 백엔드가 이 하드웨어 리비전을 모른다 | USB 제품 ID를 지원 표와 대조 |
| `Access is denied` / `device busy` | 다른 프로그램이 장치를 점유 | VueScan, SilverFast, Epson Scan 2, 스캔 앱 종료. WinUSB는 동시 사용 불가 |
| 스캔 중 연결이 끊김 | 절전, 케이블, 허브 전력 | USB 선택적 절전 끄기, 직접 연결 |
| 터미널에서는 되는데 negaflow에서 안 됨 | 플러그인 승인 또는 경로 | negaflow에서 재승인 |
| 업데이트 후 안 됨 | 실행 파일 해시가 바뀌어 승인이 초기화됨 | negaflow에서 재승인 |
| `open of device ... failed: Invalid argument` | USB 주소가 첫 열기 후 바뀜 | `detect`를 다시 실행. 반복되면 진단 로그 수집 |
| 제조사 소프트웨어가 스캐너를 못 찾음 | WinUSB로 바꿨기 때문 | 장치 관리자에서 제조사 드라이버로 되돌림 |
| 스캔이 시작되지 않고 오래 멈춤 | 램프 예열, 캘리브레이션 | 3분(기본 타임아웃)까지 기다림. pieusb는 더 길 수 있다 |
| 결과 파일이 손상됨 | binary stdout 문제(spike S-2) | 즉시 보고. 알려진 위험 항목 |

## 4. SANE 디버그 로그

```powershell
$env:SANE_DEBUG_DLL = "3"
& scanimage.exe -f "%d`t%v`t%m`t%t%n" 2>&1 | Select-Object -Last 40
```

백엔드별:

```powershell
$env:SANE_DEBUG_GENESYS = "128"
$env:SANE_DEBUG_EPSON2 = "128"
$env:SANE_DEBUG_COOLSCAN3 = "128"
$env:SANE_DEBUG_PIEUSB = "128"
```

**플러그인이 이 변수를 자식에게 전달해야 한다.** 부모 환경을 복사하므로
자동으로 되지만, 허용 목록 방식을 쓴다면 명시적으로 포함한다.

### 4.1 플러그인의 디버그 모드

```text
NEGAFLOW_SANE_DEBUG=1
```

설정하면:

- 자식 프로세스의 전체 명령줄을 stderr에 기록
- `-A` 덤프 전문을 stderr에 기록
- 각 실행의 소요 시간 기록
- 주소 캐시 상태 변화 기록

**기본으로 켜지 않는다.** 덤프가 수십 KB이고 stderr 예산(1 MiB)을
잠식한다.

## 5. 로그 정책

negaflow 본체 windows_docs `10-scanner/plugin-architecture.md` §17이
호스트 쪽 정책을 정의한다. 어댑터 쪽 대응:

### 5.1 stderr에 기록하는 것

```text
플러그인 버전과 아키텍처
scanimage 경로와 버전
각 scanimage 실행의 종료 코드와 소요 시간
백엔드 이름
오류 메시지 (scanimage stderr 포함)
재시도 발생과 이유
타임아웃 종류
취소
```

### 5.2 기록하지 않는 것

```text
이미지 픽셀
전체 로컬 경로 (파일명만 또는 해시)
스캐너 시리얼 원문
capabilityToken 원문
환경 변수 덤프
사용자 이름
```

**현재 macOS 구현은 오류 메시지에 `scanimage` stderr 전문을 싣는다.**
그 안에 경로가 들어갈 수 있다. 예:

```text
scanimage: open of device genesys:libusb:001:004 failed: Invalid argument
```

장치명은 경로가 아니므로 안전하다. 그러나 파일 관련 오류에는 경로가
들어갈 수 있다.

```text
D-25  오류 메시지에 실린 절대 경로를 다음으로 축약한다.
        사용자 프로필 경로 → <USER>
        staging 경로       → <STAGING>
      단 파일명은 유지한다(진단에 필요).
```

이것은 macOS에도 적용할 가치가 있다.

### 5.3 로그 목적지

어댑터는 **stderr에만 쓴다.** 파일에 쓰지 않는다.

이유:

- 호스트가 stderr를 수집하고 정책에 따라 저장한다.
- 어댑터가 파일을 쓰면 위치·회전·권한·정리를 우리가 책임진다.
- 프로세스가 짧게 살고 자주 뜨므로 파일 로깅이 비효율적이다.

**예외**: `diagnose` 서브커맨드는 사용자가 파일로 리다이렉트할 수 있다.

## 6. 진단 번들

사용자가 문제를 보고할 때 필요한 것.

```text
negaflow-scanner-sane.exe diagnose > diagnose.txt 2>&1
```

여기에 다음을 더한다.

```text
Windows 버전:      winver 또는 [System.Environment]::OSVersion
Windows 빌드:      Get-ComputerInfo | Select WindowsProductName, OsBuildNumber
아키텍처:          $env:PROCESSOR_ARCHITECTURE
플러그인 버전:     manifest.json
scanimage 버전:    scanimage --version
스캐너 모델과 USB ID
드라이버 상태
SANE_DEBUG_DLL=3 출력
플러그인 detect 출력
```

**진단 번들 생성 스크립트를 제공한다.**

```powershell
# collect-diagnostics.ps1
# 위 항목을 수집해 하나의 텍스트 파일로 만든다
# 사용자 이름과 경로를 마스킹한다
```

마스킹이 중요하다. 사용자가 GitHub 이슈에 붙일 것이기 때문이다.

## 7. 성능 진단

스캔이 느리다는 보고에 대응하려면 어디가 느린지 알아야 한다.

```text
장치 열기        (scanimage -A 소요 시간)
램프 예열        (첫 진행률까지)
전송             (진행률 0 → 100)
병합 (다중 노출) (processingNegative 단계)
검증             (TIFF 열기)
```

**진행률 이벤트에 이미 단계가 있으므로 호스트가 시간을 잴 수 있다.**
어댑터는 각 `scanimage` 실행의 소요 시간을 stderr에 기록한다.

```text
[negaflow-scanner-sane] scanimage -A: 1.83s (exit 0)
[negaflow-scanner-sane] scanimage acquire: 142.7s (exit 0, 87 progress records)
[negaflow-scanner-sane] merge: 38.2s
[negaflow-scanner-sane] validate: 2.1s
```

이 형식을 macOS에도 추가하면 두 플랫폼의 성능을 비교할 수 있다.

## 8. 알려진 Windows 고유 문제

문서에 미리 적어둘 것.

### 8.1 USB 선택적 절전

Windows가 유휴 USB 장치의 전원을 끈다. 긴 스캔 중에는 활동이 있으므로
보통 문제없지만, 다중 노출 사이의 간격에서 발생할 수 있다.

```text
장치 관리자 → USB 루트 허브 → 속성 → 전원 관리
→ "전원을 절약하기 위해 컴퓨터가 이 장치를 끌 수 있음" 해제
```

### 8.2 안티바이러스

실시간 검사가 수백 MB TIFF 쓰기를 크게 느리게 한다.

```text
제외 경로 권장:
  <staging 디렉터리>
  %LOCALAPPDATA%\Negaflow\ScannerPlugins\sane\
```

**사용자에게 안티바이러스를 끄라고 하지 않는다.** 특정 경로 제외만 안내한다.

### 8.3 절전 모드

스캔 중 컴퓨터가 절전으로 들어가면 USB 전송이 끊긴다.

```text
D-26  스캔 중 시스템 절전을 막는다.
      SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)
      스캔 종료 시 ES_CONTINUOUS만으로 해제
```

**디스플레이는 끄게 둔다**(`ES_DISPLAY_REQUIRED`를 쓰지 않는다).
스캔은 사용자가 지켜볼 필요가 없다.

이것은 macOS에 없는 기능이지만(macOS는 프로세스가 살아 있으면
`caffeinate` 없이도 대체로 괜찮다), Windows에서는 필요하다.

### 8.4 긴 경로

호스트 staging 경로가 260자를 넘으면 `CreateFileW`가 실패할 수 있다.
매니페스트의 `longPathAware`와 레지스트리 정책이 모두 필요하다.

```text
HKLM\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled = 1
```

이 정책이 꺼져 있으면 매니페스트만으로 부족하다.

**대응**: 긴 경로 오류를 명시적으로 감지해 사용자에게 안내한다.

```text
"출력 경로가 너무 깁니다. Windows의 긴 경로 지원이 꺼져 있거나
 negaflow의 스캔 폴더가 너무 깊습니다. 스캔 폴더를 더 짧은 경로로
 옮겨 보십시오."
```

## 9. 오류 메시지 개선

현재 오류 메시지가 한국어이고 원인만 말한다.

```text
"요청 resolution 3600dpi를 정확히 적용할 수 없습니다."
```

**조치를 함께 말하면 지원 부담이 크게 준다.**

```text
"요청 resolution 3600dpi를 정확히 적용할 수 없습니다.
 이 스캐너가 지원하는 값: 600, 1200, 2400, 7200"
```

지원 값을 오류에 싣는 것은 wire를 바꾸지 않는다(메시지 문자열 안이므로).

```text
D-27  거부 오류 메시지에 "무엇이 가능한가"를 포함한다.
      해상도, 심도, 색 모드, 스캔 영역 범위.
      양쪽 플랫폼에 적용한다.
```

단 메시지가 길어지면 UI에서 잘릴 수 있다. 호스트와 협의한다.

## 10. FAQ 항목 (문서용)

```text
Q. 스캔하는 동안 Epson Scan 2를 쓸 수 있나요?
A. 아니요. 드라이버를 WinUSB로 바꾸면 Epson Scan 2가 이 스캐너를
   인식하지 못합니다. 되돌리면 이 플러그인을 쓸 수 없습니다.
   한 번에 하나만 가능합니다.

Q. 리눅스 서버의 스캐너를 쓸 수 있나요?
A. 지원하지 않습니다. → remote-saned 문서 §7

Q. VueScan과 함께 쓸 수 있나요?
A. (spike U-1 결과에 따라 답)

Q. WSL2를 써야 하나요?
A. 아니요. 설치 프로그램이 필요한 것을 모두 포함합니다.
   WSL2는 Reflecta/PIE 스캐너나 지원하지 않는 백엔드가 필요한
   고급 사용자를 위한 대안입니다.

Q. 왜 관리자 권한이 필요한가요?
A. 플러그인 설치에는 필요 없습니다. 스캐너 드라이버를 바꿀 때만
   필요합니다.

Q. 스캔 결과가 macOS와 다른가요?
A. 같아야 합니다. 다르다면 결함입니다. → numerical-parity
```

## 11. 체크리스트

- [ ] `diagnose` 서브커맨드
- [ ] 4단계 실패 판정이 문서화됨
- [ ] Windows 고유 문제 표
- [ ] 경로 마스킹 (D-25)
- [ ] 소요 시간 로깅
- [ ] 절전 방지 (D-26)
- [ ] 긴 경로 오류 안내
- [ ] 오류에 가능한 값 포함 (D-27)
- [ ] 진단 수집 스크립트
- [ ] stderr에만 기록
- [ ] 민감 정보 제외
