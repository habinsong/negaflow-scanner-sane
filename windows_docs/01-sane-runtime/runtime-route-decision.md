# SANE 런타임 경로 결정

기준일: 2026-08-04
상태: **조건부 결정** — spike S-1·S-2 통과 전에는 확정이 아니다
목적: Windows 사용자에게 `scanimage`가 어떤 경로로 도달하는지 하나로 정한다

관련 문서:

- [availability](availability.md)
- [usb-transport](usb-transport.md)
- [remote-saned](remote-saned.md)
- [building-sane](building-sane.md)
- [packaging-and-install](../07-distribution/packaging-and-install.md)
- [gpl-compliance](../07-distribution/gpl-compliance.md)

## 1. 결정해야 하는 이유

macOS에서는 이 질문이 이미 답이 있다. Homebrew가 `sane-backends`를 설치하고,
설치 프로그램이 `brew install`을 대신 실행하며, 플러그인은 keg 경로에서
`scanimage`를 찾는다. 사용자는 SANE의 존재를 거의 의식하지 않는다.

Windows에는 Homebrew가 없고, 공식 SANE 배포도 없고, USB 드라이버 바인딩이
사용자의 다른 소프트웨어와 충돌한다. **런타임 전달 방식이 제품 결정이 된다.**

## 2. 후보 네 가지

| # | 경로 | `scanimage` | 사용자 부담 | 코드 변경 |
|---:|---|:---:|---|---|
| A | MSYS2 패키지를 재배포 | 있음 | Zadig로 WinUSB 바인딩 | 적음 |
| B | WSL2 + usbipd-win | 있음 | WSL 설치, bind/attach, udev | 중간(경로·IPC) |
| C | 원격 `saned` + `net` 백엔드 | 있음(재빌드 필요) | Linux 서버 필요 | 적음 |
| D | SANEWinDS/TWAIN 전환 | **없음** | 낮음 | **전면 재작성** |

D는 이 저장소의 이식이 아니다. TWAIN 어댑터를 새로 만드는 별개 제품이며
negaflow 본체 windows_docs의 `10-scanner/twain-wia.md`가 소유한다.
여기서는 A·B·C만 다룬다.

## 3. 각 경로의 실체

### 3.1 A — MSYS2 `mingw-w64-sane` 재배포

```text
[Negaflow.exe]
   └─ negaflow-scanner-sane.exe
        └─ CreateProcessW → <설치경로>\sane\bin\scanimage.exe
             └─ libsane-1.dll → libusb-1.0.dll → WinUSB.sys → 스캐너
```

**장점**

- `scanimage` CLI 계약이 100% 보존된다. 2장 문서 전체가 그대로 유효하다.
- 네트워크·가상머신·별도 OS가 필요 없다.
- x64와 ARM64 빌드가 이미 존재한다(ucrt64 / clangarm64).
- 주요 대상 백엔드(genesys, epson2, epsonds, coolscan2, coolscan3)가 포함돼 있다.

**단점**

- **Zadig로 WinUSB를 바인딩해야 한다.** 그 순간 사용자의 Epson Scan 2,
  SilverFast, QuickScan, Windows 팩스 및 스캔이 그 스캐너를 못 쓴다.
  WinUSB는 동시 사용도 불가능하다 → [usb-transport](usb-transport.md).
- `pieusb`/`pie`가 없어 Reflecta/PIE 계열을 지원할 수 없다(재빌드하면 가능).
- `net` 백엔드가 없어 원격 경로가 막혀 있다(재빌드하면 가능).
- `--disable-locking`으로 빌드돼 SANE 계층 장치 잠금이 없다.
- upstream이 Windows를 CI로 검증하지 않고, MSYS2가 442행 패치를 유지한다.
  즉 **아무도 지속적으로 테스트하지 않는 구성**이다.
- 재배포하면 GPL 소스 제공 의무가 우리에게 온다
  ([gpl-compliance](../07-distribution/gpl-compliance.md) §4).
- binary stdout 정확성이 미검증이다(spike S-2).

### 3.2 B — WSL2 + usbipd-win

```text
[Negaflow.exe]
   └─ negaflow-scanner-sane.exe
        └─ CreateProcessW → wsl.exe -d <distro> -- scanimage …
             └─ Linux libsane → libusb → usbfs → vhci-hcd
                  └─ usbipd-win → WinUSB(usbipd가 바인딩) → 스캐너
```

**장점**

- **진짜 Linux `scanimage`**다. 백엔드가 전부 있고, upstream이 CI로 검증하는
  구성이며, 배포판이 패키징한다. 동작 신뢰도가 A보다 훨씬 높다.
- `pieusb`, `net`, `escl`이 전부 사용 가능하다.
- 커널 재빌드가 더 이상 필요 없다.
- 장치 점유를 되돌리기 쉽다(`usbipd detach` 한 번).

**단점**

- 사용자가 WSL2를 설치하고, 배포판을 설치하고, `sane-utils`를 설치하고,
  `usbipd bind`(관리자)를 하고, 재연결마다 `usbipd attach`를 해야 한다.
  **필름 스캐너 사용자 층에게 이것은 무거운 요구다.**
- udev 권한이 1순위 실패 원인이고, WSL에서 udev reload가 깨져 있다.
- **genesys 스캐너에서 스캔 완료 후 연결이 끊기는 보고가 있다**(usbipd #180).
  이 프로젝트의 주요 대상과 같은 백엔드다.
- 경로 변환이 필요하다. 호스트가 준 `C:\Users\...\frame.tiff`를 WSL의
  `/mnt/c/Users/.../frame.tiff`로 바꿔야 하고, 그 변환이 정확 옵션 계약의
  `outputPath` 일치 검사와 충돌하지 않아야 한다.
- 파일 I/O가 9p/DrvFs를 지나므로 대용량 TIFF 쓰기가 느릴 수 있다.
  7200 dpi 다중 노출은 수 GB다.
- `wsl.exe`의 종료 코드·stderr가 `scanimage`의 것과 섞인다.
- 취소가 두 단계가 된다(Windows 프로세스 → WSL 내부 프로세스).

### 3.3 C — 원격 `saned`

```text
[Windows]  negaflow-scanner-sane.exe
              └─ scanimage.exe (net 백엔드 포함 커스텀 빌드)
                   └─ TCP 6566 + 데이터 포트
[Linux/RPi] saned → libsane → libusb → 스캐너
```

**장점**

- Windows 쪽 USB 드라이버 문제가 **완전히 사라진다.**
- 스캐너를 여러 대의 PC가 공유할 수 있다.
- 스캐너 쪽은 검증된 Linux 스택이다.

**단점**

- 사용자가 Linux 머신(라즈베리파이 등)을 운영해야 한다. 일반 제품 요구로는
  비현실적이다.
- MSYS2 빌드에 `net` 백엔드가 없어 재빌드가 필요하다.
- `saned`는 6566에서 듣지만 이미지 데이터는 임의 포트로 전송된다.
  `data_portrange`를 고정하지 않으면 방화벽 문제가 생긴다.
- 네트워크 지연이 진행률 watchdog 타임아웃과 상호작용한다.
- 인증이 약하다(`saned.users`의 평문 자격 증명).

→ [remote-saned](remote-saned.md)

## 4. 조건부 결정

```text
D-01  1차 경로는 A(MSYS2 기반 재배포)로 한다.
      단 spike S-1과 S-2를 통과해야 확정한다.

D-02  B(WSL2)는 "고급 사용자·Reflecta/PIE·구형 장치"를 위한
      명시적 대체 경로로 문서화하되 기본 설치 경로로 만들지 않는다.

D-03  C(원격 saned)는 지원 대상 밖으로 두되, 어댑터가 `net:` 장치명을
      만나도 깨지지 않도록 코드에서 특별 취급하지 않는다.
      사용자가 스스로 구성하면 동작해야 한다.

D-04  D(SANEWinDS/TWAIN)는 이 저장소의 범위가 아니다.
```

### 4.1 A를 1차로 두는 근거

1. 2장 전체(약 3,000행의 파싱·검증 로직)가 그대로 살아난다. B는 살아나지만
   경로 변환과 이중 프로세스 계층이 붙고, C·D는 상당 부분 또는 전부를 버린다.
2. 사용자 설치 단계가 가장 적다. "Zadig 한 번"이 "WSL2 + 배포판 + udev +
   매번 attach"보다 짧다.
3. Nikon Coolscan — 이 플러그인의 가장 강한 존재 이유 — 은 어차피 벤더
   드라이버가 없다. 그 사용자에게 WinUSB 바인딩은 **잃을 것이 없는 거래**다.
   VueScan은 자체 드라이버를 쓰므로 영향 범위가 제한적일 수 있다(미확인).
4. ARM64 빌드가 이미 존재해 Windows on ARM 대응이 열려 있다.

### 4.2 A가 실패하는 조건

다음 중 하나라도 참이면 D-01을 폐기하고 B로 전환한다.

- spike S-2 실패: `scanimage.exe`가 stdout으로 바이트 정확한 TIFF를 내지 못한다.
- spike S-1 실패: 실제 대상 스캐너에서 어떤 백엔드도 장치를 열지 못한다.
- Zadig 바인딩의 되돌리기가 실무적으로 안정적이지 않다(사용자가 벤더
  소프트웨어를 영구히 잃는다).

### 4.3 Epson 사용자에 대한 예외 권고

Epson Perfection V800/V850은 벤더 드라이버와 Epson Scan 2가 Windows 11에서
정상 동작한다. 이 사용자에게 WinUSB 바인딩을 권하는 것은 **순손실**이다.
제품 문서와 설치 UI에서 다음을 명시한다.

> Epson Perfection 스캐너를 쓰고 있고 Epson Scan 2가 동작한다면, 이 플러그인을
> 설치하기 전에 잃게 되는 것을 확인하십시오. WinUSB 드라이버로 바꾸면
> Epson Scan 2와 SilverFast가 이 스캐너를 인식하지 못합니다.

이것은 UX 문구가 아니라 **제품 계약**이다. 설치 후에 알게 하면 안 된다.

## 5. Spike 명세

### S-1 — MSYS2 `scanimage`가 실제 스캐너를 여는가

**전제**: Windows 11 x64, 대상 스캐너 1대(우선순위: Plustek OpticFilm 8200i
또는 Nikon Coolscan LS-50).

```text
1. MSYS2 설치, pacman -S mingw-w64-ucrt-x86_64-sane
2. Zadig 2.9로 대상 스캐너에 WinUSB 바인딩
3. scanimage.exe -f "%d\t%v\t%m\t%t%n"
4. scanimage.exe -A -d <dev>
5. scanimage.exe -d <dev> -p --format=tiff --resolution 1200 > test.tif
```

**통과 조건**

- 3에서 장치가 나온다
- 4의 덤프가 macOS에서 같은 장치가 내는 덤프와 옵션 이름·단위가 같다
- 5가 exit 0이고 `test.tif`가 유효한 TIFF다

**기록할 것**: 각 단계 소요 시간, stderr 전문, `scanimage --version`,
덤프 전문(픽스처로 보존), 장치명 형식(`genesys:libusb:001:002`인지 다른지).

### S-2 — binary stdout 정확성

**가장 먼저 실행한다.** 실패하면 A 경로 전체가 무너진다.

```text
1. 같은 스캐너·같은 옵션으로 macOS와 Windows에서 각각 스캔
2. 두 TIFF의 SHA-256 비교 (같을 필요는 없다 — 스캔은 결정적이지 않다)
3. Windows TIFF에서 0x0D 0x0A 시퀀스가 0x0A 단독을 대체했는지 검사:
   - 파일 크기가 예상 픽셀 바이트 수와 정확히 맞는가
   - libtiff로 열어 strip 오프셋이 유효한가
   - 픽셀 데이터에서 0x0A 앞에 0x0D가 삽입된 패턴이 있는가
4. 리다이렉션 없이 파이프로 받았을 때도 동일한지 확인
5. scanimage 소스에서 _setmode(_O_BINARY) 호출 여부 감사
```

**대체안이 필요할 경우**: `scanimage`에 `--output-file <path>` 옵션이 있다면
그것을 쓴다(1.4.0 소스에서 확인 필요). 없으면 MSYS2 패키지를 재빌드하며
`_setmode` 호출을 추가하는 패치를 유지해야 하고, 그 순간 우리는 SANE의
다운스트림 패치 유지자가 된다 → [building-sane](building-sane.md).

### S-3 — WSL2 경로 안정성

```text
1. usbipd bind/attach
2. WSL 안에서 scanimage -L, -A, 전체 스캔
3. 스캔 완료 후 장치가 계속 잡혀 있는지 확인 (usbipd #180 재현 여부)
4. 연속 5회 스캔 (다중 노출을 흉내)
5. /mnt/c 경로로 직접 출력했을 때의 처리량 측정
6. udev 규칙 없이 비루트로 동작하는지, 필요하면 어떤 규칙이 필요한지
```

### S-4 — 장치명 형식

Windows에서 SANE 장치명이 macOS와 같은 형태(`<backend>:libusb:<bus>:<dev>`)인가.
다르면 다음이 전부 영향받는다.

- `isVolatileUSBSelector`(`:libusb:` 포함 검사)
- `connectionType` 판정(`:net:`, `:scsi:`, `:usb:`, `:libusb:`)
- `supportsStableBackendSelector` 조건(`chosen.devname.contains(":libusb:")`)

→ [device-identity](../02-frontend-contract/device-identity.md)

### S-5 — open 후 주소 변동

macOS 실측(열 때마다 libusb 주소가 바뀐다)이 Windows에서도 성립하는가.
성립하지 않아도 재연결 로직은 제거하지 않는다.

### S-6 — 로케일

`LC_ALL=C`로 `scanimage.exe`의 메시지 언어가 고정되는가.
`rounded value of`, `device busy`, `invalid argument` 감지가 살아 있는가.
한국어 Windows에서 확인한다.

## 6. Spike 실행 순서와 gate

```text
S-2 (binary stdout)      ← 실패하면 A 폐기
  ↓
S-1 (실제 장치 open)      ← 실패하면 A 폐기
  ↓
S-4 (장치명 형식)         ← 결과가 2장 코드에 반영됨
S-6 (로케일)             ← 실패하면 반올림 감지 대체안 필요
  ↓
S-5 (주소 변동)          ← 정보 수집
  ↓
D-01 확정
  ↓
S-3 (WSL2)              ← 대체 경로 문서화용, 병행 가능
```

**S-2와 S-1을 통과하기 전에는 이식 구현을 시작하지 않는다.** 이 두 spike는
장비 1대와 며칠이면 끝나지만, 통과하지 못하면 나머지 모든 설계가 무의미하다.

## 7. 설치 사용자 여정 (A 경로 확정 시)

```text
1. negaflow-scanner-sane 설치 프로그램 실행
2. 설치 프로그램이 SANE 런타임을 함께 배치
     %LOCALAPPDATA%\Negaflow\ScannerPlugins\sane\
       negaflow-scanner-sane.exe
       manifest.json
       sane\bin\scanimage.exe, libsane-1.dll, libusb-1.0.dll, …
       sane\lib\sane\libsane-*.dll
       sane\etc\sane.d\*.conf
       LICENSES\
3. 설치 프로그램이 경고를 표시:
     "이 플러그인은 스캐너의 USB 드라이버를 WinUSB로 바꿉니다.
      바꾸면 제조사 스캔 소프트웨어가 이 스캐너를 사용할 수 없습니다.
      되돌리는 방법: 장치 관리자 → 드라이버 업데이트 → 제조사 드라이버"
4. 사용자가 드라이버 바인딩 단계로 진행 (§8)
5. negaflow 재시작 → 플러그인 승인 → 스캔
```

## 8. 드라이버 바인딩 도구 선택

Zadig(GPLv3, 2.9, 2024-06-13)를 사용자에게 다운로드시킬 것인가,
libwdi(LGPLv3)를 우리 설치 프로그램에 내장할 것인가.

| 방식 | 장점 | 단점 |
|---|---|---|
| Zadig 안내 | 우리가 드라이버를 건드리지 않는다. 책임 경계가 명확 | 사용자가 GUI에서 잘못된 장치를 고를 수 있다. 잘못 고르면 키보드가 죽는다 |
| libwdi 내장 | 대상 VID/PID를 우리가 지정. 사고 위험 낮음 | LGPLv3 준수, 드라이버 설치 권한, 서명, 롤백 UX를 전부 우리가 진다 |

**권장: libwdi 내장.** 이유는 안전이다. Zadig의 장치 목록에서 사용자가
USB 허브나 입력 장치를 고르는 사고가 실제로 보고된다. VID/PID를 우리가
알고 있으므로(README의 지원 표) 대상을 좁힐 수 있다.

단 이것은 **드라이버 설치 프로그램을 만드는 일**이며 서명·권한·롤백·
Windows 버전 대응이 따라온다. 초기 릴리스에서는 Zadig 안내로 시작하고,
사용자 사고가 보고되면 libwdi로 전환하는 단계적 접근도 합리적이다.

이 결정은 [decision-register](../00-overview/decision-register.md) D-09가 소유한다.

## 9. 열린 질문

- VueScan이 자체 드라이버를 쓴다면, WinUSB 바인딩 후에도 VueScan이 동작하는가
  (동작한다면 Coolscan 사용자의 손실이 0이다) — 미확인
- Windows on ARM에서 Zadig/libwdi가 ARM64 드라이버를 설치할 수 있는가
- `--disable-locking` 빌드에서 두 프로세스가 같은 장치를 열면 무슨 일이
  일어나는가(무해한 실패인가, 하드웨어 상태 손상인가)
- MSYS2 패키지를 재배포할 때 어느 파일까지가 "필요한 것"인가
  (poppler, curl, libxml2 의존이 실제로 필요한지)
