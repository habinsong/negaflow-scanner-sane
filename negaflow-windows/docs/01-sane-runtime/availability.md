# Windows에서 SANE를 얻는 방법

기준일: 2026-08-04
상태: 1차 조사 완료 — 실기 검증 전
조사 방법: upstream 저장소·패키지 색인·공식 문서 직접 확인
검증 표기: **확인**은 이 조사에서 원문을 직접 읽은 것, **미확인**은 확인하지 못한 것

관련 문서:

- [runtime-route-decision](runtime-route-decision.md)
- [usb-transport](usb-transport.md)
- [remote-saned](remote-saned.md)
- [building-sane](building-sane.md)
- [gpl-compliance](../07-distribution/gpl-compliance.md)

## 0. 요약

이 플러그인은 `scanimage` 실행 파일이 있어야 존재할 수 있다. 그래서 Windows
이식의 첫 질문은 "Swift를 무엇으로 바꿀까"가 아니라 **"Windows에 `scanimage`가
있는가"** 다.

결론:

| 경로 | `scanimage` CLI 계약 보존 | 상태 |
|---|:---:|---|
| MSYS2 `mingw-w64-sane` | **예** | 패키지 실존, 1.4.0-4, 2025-09-30 빌드. 백엔드 일부 누락 |
| WSL2 + usbipd-win | **예** | 진짜 Linux `scanimage`, 전체 백엔드. 사용자 설정 부담 큼 |
| SANEWinDS + 원격 `saned` | **아니오** | TWAIN/.NET 클라이언트. CLI 계약이 없다 |
| Cygwin 패키지 | — | **더 이상 존재하지 않음** |
| vcpkg / conan | — | 포트 없음 |
| 직접 MinGW 빌드 | 예 | 가능하나 upstream이 CI로 검증하지 않음 |

가장 큰 장애물은 SANE가 아니라 **USB 드라이버 바인딩**이다. 네이티브 Windows
경로는 libusb를 요구하고, libusb는 WinUSB 바인딩을 요구하며, WinUSB로 바꾸면
벤더 TWAIN/WIA 소프트웨어가 그 스캐너를 못 쓴다. 필름 스캐너 사용자는 대체로
SilverFast나 VueScan을 함께 쓴다 → [usb-transport](usb-transport.md).

## 1. upstream 사실

**확인** — 태그 피드 `https://gitlab.com/sane-project/backends/-/tags?format=atom`

| 항목 | 값 |
|---|---|
| 최신 릴리스 | **1.4.0**, 2025-05-24 |
| 이전 | 1.3.1 (2024-05-22), 1.3.0 (2024-02-12), 1.2.1 (2023-02-04) |
| 1.5.x | **없음** |
| 정본 저장소 | <https://gitlab.com/sane-project/backends> (GitHub 아님) |

### 1.1 upstream이 말하는 Windows 지원

**확인** — `README` at tag 1.4.0, 89~91행:

> SANE should build on most Unix-like systems. Support for OS/2, MacOS X,
> BeOS, and Microsoft Windows is also available.

**확인** — `README.windows` at tag 1.4.0. 이 파일의 마지막 날짜 표기는
**2011/10/08**이다. 요지:

- 컴파일하려면 Cygwin 또는 MinGW 컴파일러와 POSIX 호환 환경이 필요하다.
- `http://www.mingw.org/wiki/MSYS`를 가리킨다(MSYS2로 대체된 구 프로젝트).
- SCSI, USB(libusb-win32), 네트워크 스캐너만 동작할 수 있다.
  FireWire/Parallel은 없다.
- **Windows XP, 7에서 테스트됨**, 그리고 Linux의 Wine에서.

즉 upstream의 Windows 지원 선언은 **15년 전 문서**에 근거한다.

### 1.2 빌드 시스템

**확인** — `configure.ac` at 1.4.0:

- 202행: `AC_CHECK_HEADERS`에 `windows.h`
- 535행: `ntddscsi.h` / `ddk/ntddscsi.h`
- 630~632행: `dnl Windows (cygwin/mingw), BeOS, and OS/2 need this.` —
  host triplet `cygwin* | mingw* | beos* | os2*` 분기

**MSVC 경로는 없다.** autotools 전용이므로 MSVC로는 어떤 형태로도 빌드되지 않는다.

**확인** — `.gitlab-ci.yml` at 1.4.0의 job은 debian-bullseye, debian-bookworm,
fedora-39-clang, alpine-3.18-musl, ubuntu-mantic뿐이다. **Windows/MinGW/Cygwin
job이 없다.** 커밋마다 Windows 빌드 가능성이 검증되지 않는다는 뜻이다.

## 2. Cygwin — 더 이상 없다

**확인(부정)** — 공식 패키지 목록 <https://cygwin.com/packages/package_list.html>
(9,671개 항목)을 대소문자 무시로 `sane` 검색: **0건**. 목록은
`s3270` → `savi` → `schroedinger-*`로 이어지며 `sane`이 들어갈 자리를 건너뛴다.
`https://cygwin.com/packages/summary/sane-backends.html`은 **404**.

검색에 나오는 것은 이미 폐기된 서드파티 Cygwin Ports 저장소이며 sane-backends
**1.0.18** 수준이다(<https://sourceforge.net/p/cygwin-ports/sane-backends/>).

**결론: Cygwin은 패키지 경로로는 죽었다.** Cygwin에서 쓰려면 2011년판
README를 따라 직접 빌드해야 한다.

## 3. MSYS2 — 유일한 공식 Windows 네이티브 패키지

**확인** — <https://packages.msys2.org/base/mingw-w64-sane>

| 항목 | 값 |
|---|---|
| base 패키지 | `mingw-w64-sane` |
| 버전 | **1.4.0-4** |
| 환경 | **ucrt64, clang64, clangarm64** |
| 없는 환경 | **mingw64 (MSVCRT)** |
| 패키지명 | `mingw-w64-ucrt-x86_64-sane`, `mingw-w64-clang-x86_64-sane`, `mingw-w64-clang-aarch64-sane` |
| ucrt64 빌드 시각 | **2025-09-30 07:55:49** |
| 라이선스 | GPL-2.0-or-later |

**ARM64 빌드(`clangarm64`)가 존재한다.** Windows on ARM 지원의 전제 조건이
이미 갖춰져 있다는 뜻이다.

### 3.1 실제로 들어 있는 것

**확인** — 파일 목록:

```text
/ucrt64/bin/scanimage.exe
/ucrt64/bin/sane-find-scanner.exe
/ucrt64/bin/gamma4scanimage.exe
/ucrt64/bin/umax_pp.exe
/ucrt64/bin/libsane-1.dll
/ucrt64/bin/sane-config
/ucrt64/etc/sane.d/*.conf
```

의존: `libusb`(진짜 libusb-1.0 MinGW 빌드), curl, libieee1284, libjpeg-turbo,
libpng, libtiff, libxml2, poppler.

### 3.2 백엔드 — 이 프로젝트에 결정적인 부분

**확인** — PKGBUILD에 명시적 `BACKENDS=` 허용 목록이 있고, 실제로 58개 백엔드
DLL이 들어간다.

이 프로젝트가 다루는 백엔드 기준:

| 백엔드 | MSYS2 포함 | 대상 |
|---|:---:|---|
| `genesys` | **있음** | Plustek OpticFilm 7200/7300/7400/7500i/7600i/8100/8200i |
| `epson2` | **있음** | Epson Perfection V700/V750/V800/V850 |
| `epsonds` | **있음** | 신형 Epson |
| `coolscan2` | **있음** | Nikon Coolscan 구형 |
| `coolscan3` | **있음** | Nikon Coolscan LS-40/50/4000/5000/8000 |
| `pieusb` | **없음** | Reflecta ProScan/CrystalScan/DigitDia, PIE PowerSlide |
| `pie` | **없음** | 구형 PIE SCSI |
| `net` | **없음** | 원격 `saned` 클라이언트 |
| `plustek` | **없음** | (이 프로젝트의 OpticFilm은 genesys 경로이므로 영향 없음) |
| `escl`, `pixma`, `avision`, `snapscan`, `hp`, `umax`, `microtek2`, `magicolor`, `kodakaio`, `test` | 없음 | 범위 밖 |

**주요 목표 세 계열(Plustek OpticFilm, Epson Perfection, Nikon Coolscan)이
그대로 들어 있다.** 빠지는 것은 Reflecta/PIE 계열과 네트워크 경로다.

`net` 백엔드 부재는 별도로 중요하다 → [remote-saned](remote-saned.md).

upstream 백엔드 전체 목록:
<https://gitlab.com/sane-project/backends/-/raw/1.4.0/backend/dll.conf.in>

### 3.3 upstream이 MinGW에서 그대로 빌드되지 않는다

**확인** — MSYS2는 **442행짜리** 다운스트림 패치를 유지한다.

<https://github.com/msys2/MINGW-packages/blob/master/mingw-w64-sane/001-fix-build-on-mingw.patch>

내용: `sys/wait.h`, `sys/ioctl.h`, `sys/socket.h`, `netinet/in.h`, `netdb.h`
가드, `mkdir(path, 0777)` → `mkdir(path)` (`_WIN32` 분기).

빌드 플래그: `--disable-locking --disable-preload LIBS="-lws2_32"`.

**`--disable-locking`이 중요하다.** SANE의 장치 잠금(`/var/lock/sane`)이 꺼져
있다는 뜻이며, 두 프로세스가 같은 장치를 동시에 열려 할 때 SANE 계층의
보호가 없다. 이 플러그인은 자체적으로 세션을 하나로 제한하지만
([child-process](../03-process-and-io/child-process.md) §8),
다른 프로그램과의 경합은 막지 못한다.

### 3.4 `saned.exe`가 없다

**확인** — `saned.conf`와 `saned.8` man 페이지만 있고 실행 파일이 없다.
Windows를 스캐너 서버로 쓸 수는 없다는 뜻이다.

### 3.5 미확인 위험 두 가지

1. **실제 USB 스캐너에서 동작한다는 1차 보고를 찾지 못했다.** 패키지는
   존재하고 libusb에 링크돼 있지만, "Zadig로 WinUSB 설치 → MSYS2 `scanimage`
   실행 → 스캔 성공"이라는 확인된 사례를 찾지 못했다. → spike S-1
2. **binary stdout 처리 미감사.** `scanimage -p --format=tiff > out.tif`가
   바이트 정확한 TIFF를 만드는지, CRLF 변환이 개입하는지 확인하지 못했다.
   `_setmode(_O_BINARY)` 처리 여부를 소스에서 감사하지 않았다.
   **이 항목은 가장 먼저 테스트해야 한다.** 이식 전체가 여기서 무너질 수 있다.
   → spike S-2

## 4. vcpkg / conan — 없다

**확인(부정)**:

- vcpkg: `ports/sane-backends` → 404. `versions/baseline.json`에 `"sane`으로
  시작하는 항목 0개.
- Conan Center Index: `recipes/sane-backends` → 404, `recipes/libsane` → 404.

오버레이 포트/레시피를 직접 작성해야 한다.

## 5. 서드파티 Windows 포팅

### 5.1 SANEWinDS — 살아 있으나 CLI가 아니다

**확인** — 최신 `SANEWinDS_1.6.9221_x64.msi` / `_x86.msi`, **2025-04-02**.

- 널리 인용되는 0.9.5589는 크게 낡은 버전이다. 실제 이력:
  0.9.x → 1.0.7786 → 1.1.8600 → 1.2.8853 → 1.3.8886 → 1.4.9107 → 1.5.9111 →
  1.6.9220 → 1.6.9221.
- 변경 이력: 64-bit TWAIN 지원(1.4), TWAIN 2.0 지원(1.5), TWAIN 2.x 준수 강화,
  "SANE 1.3 백엔드에서 검은 페이지 문제 수정", canon_dr 백엔드 관련 수정(1.6.9220).
- 라이선스 **GPLv3**. x86/x64 MSI. 단독 실행 또는 TWAIN Data Source.
  .NET DLL로 제공되어 다른 .NET 프로그램에 내장 가능.
- **`scanimage`를 제공하지 않는다.** libsane을 쓰지 않고 SANE 네트워크
  프로토콜을 직접 구현한 네이티브 Windows 클라이언트다.
- <https://sourceforge.net/projects/sanewinds/files/> ·
  <https://github.com/cyanfish/SANEWinDS> (마지막 푸시 2024-03-11, **확인**)

**이 플러그인에 대한 함의**: SANEWinDS를 쓰면 전송 계층 전체를 다시 써야 한다
(TWAIN 또는 .NET DLL). "실행 파일 경로만 바꾸면 되는" 이식이 아니다.
그렇게 할 거라면 SANE 대신 WIA/TWAIN 어댑터를 직접 만드는 편이 낫고,
그것은 negaflow 본체 negaflow-windows/docs의 `10-scanner/twain-wia.md`가 이미 소유한
별개 제품이다.

### 5.2 SaneTwain — 폐기됨

**확인** — 최신 v1.37, `sanetwain137.zip`의 `Last-Modified`가 **2013-04-08**.

- 라이선스가 **"e-mail-ware"** — 사이트 원문: 바이너리는 e-mail-ware로
  배포하며 사용하면 이메일을 보내달라. **클로즈드 소스 프리웨어이며
  오픈소스가 아니다.** 배포에 얽으면 라이선스 문제가 된다.
- 자체 `ScanImage.exe`를 포함하지만 이것은 SANE의 `scanimage`가 **아니다.**
  xscanimage와 비슷한 자체 GUI 프런트엔드이며 SANE 넷 프로토콜을 자체 구현한
  것이다.
- ArchWiki는 SaneTwain을 "old"로 표시하고 SANEWinDS를 권한다.

### 5.3 WiaSane — 폐기됨

**확인** — `mback2k/wiasane` 마지막 푸시 **2017-02-19**. 라이선스 필드
`NOASSERTION`.

SANE-net 프런트엔드를 구현한 **WIA 2.0 미니 드라이버**로, 원격 `saned` 장치를
네이티브 Windows 스캐너로 보이게 한다. Windows 7 기준으로 빌드·테스트됐다.
서명되지 않은 드라이버는 Windows 10/11의 드라이버 서명 강제에서 실제 문제다
(서명 상태는 **미확인**).

### 5.4 기타

- `revvv/sane-backends-cygwin`: Canon CanoScan LiDE 20 전용 Cygwin 빌드.
  범용 배포가 아니다.
- XSane for Windows: 0.998, 2010년 11월. 죽었다.
- NAPS2: WIA/TWAIN/SANE/ESCL을 지원하지만 **SANE 드라이버는 Linux/macOS
  전용**이다. NAPS2가 문서화한 Windows에서 SANE 서버에 접근하는 방법은
  "SANEWinDS v1.2+를 설치하라"이다. <https://www.naps2.com/doc/scanner-sharing>

## 6. WSL2 + usbipd-win

**확인** — usbipd-win 최신 **v5.3.0, 2025-10-11**.
<https://github.com/dorssel/usbipd-win>

### 6.1 커널 재빌드는 더 이상 필요 없다

**확인** — Microsoft Learn `connect-usb` 문서 원본
(<https://github.com/MicrosoftDocs/wsl/blob/main/WSL/connect-usb.md>):

- 커널 요건: **5.10.60.1 이상**. 낮으면 `wsl --shutdown` 후 `wsl --update`.
- Store 배포 WSL을 쓰면 Windows 10 사용자도 **소스에서 컴파일하지 않고**
  최신 커널을 받는다.
- 재빌드는 이제 "Store 지원 WSL로 업데이트할 수 없을 때"의 대체 경로다.

**확인** — `linux-msft-wsl-6.6.y`의 `arch/x86/configs/config-wsl`:

```text
CONFIG_USBIP_CORE=m
CONFIG_USBIP_VHCI_HCD=m
CONFIG_USBIP_VHCI_HC_PORTS=8
CONFIG_USB=m
CONFIG_USB_STORAGE=m
CONFIG_USB_XHCI_HCD=m
```

`vhci-hcd`와 USB core가 모듈로 포함돼 배포된다.

### 6.2 현재 문법

```text
usbipd list
usbipd bind --busid 4-4          # 관리자, 재부팅해도 유지
usbipd attach --wsl --busid 4-4  # 비관리자, 유지되지 않음
```

구 `usbipd wsl attach` 하위 명령은 **제거됐다**.

### 6.3 알려진 제약 (영향이 큰 순서)

1. **권한/udev가 1순위 문제.** Microsoft 문서가 직접 말한다 — 애플리케이션에
   따라 비루트 사용자 접근을 위해 udev 규칙 설정이 필요할 수 있다.
   `sane-usb(5)`는 SANE가 `/dev/bus/usb` 권한 조정을 요구하며 그렇지 않으면
   root만 스캔할 수 있다고 명시한다.
2. **WSL에서 udev reload가 깨져 있다.** `udevadm control --reload-rules`가
   "Failed to send reload request: No such file or directory"로 실패한다.
   우회는 `wsl --terminate <distro>` 또는 `sudo service udev restart`,
   때로는 `sudo udevadm trigger` 추가. (WSL issue #8502)
3. **재부팅·WSL 재시작·장치 리셋·물리적 재연결마다 다시 attach해야 한다.**
   VM을 살려두려면 WSL 명령 프롬프트가 열려 있어야 한다.
4. **스캔 중 연결 끊김 보고 있음.** usbipd-win issue #180: Canon CanoScan
   LiDE 50이 `scanimage -L`에 genesys/libusb 장치로 잡히지만 **스캔 완료 후
   연결이 끊긴다.** genesys 백엔드라는 점에서 이 프로젝트의 주요 대상과
   같은 계열이다. → spike S-3에서 최우선 확인
5. isochronous 전송이 USB/IP에서 문제가 있다(issue #530). 스캐너는 보통
   bulk/control을 쓰므로 실제로는 잘 걸리지 않는다.
6. WSL2 전용. WSL1은 USB 패스스루가 없다.
7. x86 32-bit 호스트 미지원. x64/ARM64만.
8. **WSL에 붙어 있는 동안 그 장치는 Windows에서 쓸 수 없다.** 벤더
   소프트웨어/TWAIN/WIA를 동시에 쓸 수 없다.

8번은 WinUSB의 동시성 제약과 같은 결과를 낳는다. 다만 **되돌리기가
훨씬 쉽다**(`usbipd detach` 한 번 vs 드라이버 롤백).

## 7. `scanimage` 출력 형식의 안정성

**확인** — `frontend/scanimage.c` at 1.4.0 (2,979행) 직접 확인.

| 플래그 | 1.4.0 존재 | 행 |
|---|:---:|---|
| `-f` / `--formatted-device-list` | **있음** | 99 |
| `-A` / `--all-options` | **있음** | 105 |
| `-p` / `--progress` | **있음** | 102 |
| `--format` (pnm/tiff/png/jpeg) | **있음** | 115, 2182-2194 |
| JSON 출력 | **없음** — 파일 전체에 `json`/`JSON` 0회 | — |

### 7.1 `-f`는 안전하다

플레이스홀더 `%d %v %m %t %i %n`(장치명, 벤더, 모델, 타입, 인덱스, 개행)을
**호출자가 정한다.** 따라서 출력이 우리 통제 아래 있고 upstream의 표현 변경에
영향받지 않는다. 현재 코드가 `-f`를 우선 경로로 쓰는 것은 옳은 선택이다.

### 7.2 `-A`는 안정성 보장이 없다 — 이 프로젝트의 최대 구조적 위험

**확인** — `-A`는 `print_options()`(2023행) → `print_option()`(369행)로
흐르며, 이는 `--help`가 쓰는 **것과 같은 사람용 렌더러**다. 인터페이스가
아니라 도움말 덤프다. 읽기 전용 옵션과 버튼 옵션까지 전부 출력한다.

1.4.0 변경 이력 자체가 "읽기 전용 옵션 설정 시도가 이제 오해를 부르는
'unknown option' 대신 경고를 낸다"고 적고 있다 — 즉 이 영역의 출력은 실제로
릴리스 사이에 바뀐다.

**이 플러그인의 능력 판정 전체가 `-A` 파싱 위에 서 있다.** 따라서:

- 지원하는 sane-backends 버전을 **명시적으로 고정**하고 버전별로 테스트한다.
- 런타임에 `scanimage --version`을 읽어 기록하고, 알려지지 않은 버전이면
  진단에 경고를 남긴다(차단은 하지 않는다).
- conformance 픽스처를 버전별로 유지한다
  ([conformance-fixtures](../05-protocol/conformance-fixtures.md)).

이것은 macOS에도 이미 존재하는 위험이지만, Windows에서 SANE 버전이 사용자
환경에 따라 갈라지면 더 커진다.

### 7.3 구조화된 대안은 libsane 직접 링크뿐

`sane_get_option_descriptor()`를 직접 순회하는 것이 실제로 안정적인 API다.
SANE 표준 자체는 public domain이고 descriptor 구조체는 버전이 있다.

**그러나 이 플러그인은 그 길을 의도적으로 택하지 않았다.** libsane을 링크하면
GPL 경계 설계가 근본적으로 바뀐다
([gpl-compliance](../07-distribution/gpl-compliance.md) §5). 이 결정을
Windows에서 뒤집을지는 별도 판단이며
[decision-register](../00-overview/decision-register.md) D-17이 소유한다.

## 8. Windows 스캐너 API와 벤더 드라이버 현실 (맥락)

이 플러그인의 경쟁 경로가 무엇인지 알기 위한 참고다.

- **TWAIN 2.5**가 현행(사양 2021-11-18). 레퍼런스 DSM 최신 릴리스
  **v2.5.1, 2023-02-10**(**확인**). Windows에서 `TWAINDSM.DLL`(2.x) vs
  레거시 `TWAIN_32.DLL`(1.x). 데이터 소스는 `C:\Windows\twain_32` 또는
  `twain_64`. 벤더 TWAIN 드라이버가 32-bit 전용인 경우가 많아 32-bit 호스트
  프로세스를 강제한다.
- **WIA 2.0**이 Windows 11의 현행 이미징 드라이버 모델이며 후속이 없다.
  다만 Microsoft의 드라이버 샘플 문서는 여전히 Windows 8.1 빌드 구성을
  참조할 만큼 오래됐다.

| 스캐너 | Windows 11 벤더 상황 |
|---|---|
| Epson Perfection V800/V850 | **최선**. Epson이 현행 Windows 11 드라이버 제공. "Scanner Driver and Epson Scan 2 Utility v6.6.84.0"(64-bit TWAIN에서 사용 가능, **Digital ICE 미지원**), 레거시 "EPSON Scan Utility v3.9.3.7"(Digital ICE 있음, Windows 11 24H2 ARM 호환 명시) |
| Plustek OpticFilm 8200i | 지원, **64-bit 전용**. Windows 7/8/10/11. QuickScan + SilverFast SE Plus 8/9 번들 |
| Nikon Coolscan | **현대 드라이버 없고 앞으로도 없다.** Nikon Scan 최종판이 Windows Vista 대상이며 이후 Windows에서 동작하지 않는다고 Nikon이 명시. 실사용은 VueScan(LS-5000 드라이버를 리버스 엔지니어링, 벤더 드라이버가 없으면 자체 드라이버 설치, 있으면 충돌하지 않음) 또는 SilverFast |
| Reflecta / PIE | 벤더가 CyberView X5 + 드라이버 제공. 설치 시 **서명되지 않은 드라이버 경고** — Windows 11에서 실질적 마찰 |

**Nikon Coolscan이 이 플러그인의 Windows 존재 이유를 가장 강하게 정당화한다.**
벤더 드라이버가 없고 SANE `coolscan2`/`coolscan3`가 MSYS2 빌드에 들어 있다.
반대로 Epson V850은 벤더 경로가 멀쩡하므로 SANE 경로의 가치가 상대적으로 낮다.

## 9. 미확인 항목 (spike로 닫는다)

| ID | 항목 | 소유 문서 |
|---|---|---|
| S-1 | MSYS2 `scanimage.exe`가 실제 USB 스캐너에서 동작하는가 | [runtime-route-decision](runtime-route-decision.md) |
| S-2 | MSYS2 `scanimage.exe`의 binary stdout이 TIFF를 바이트 정확히 내는가 | [runtime-route-decision](runtime-route-decision.md) |
| S-3 | usbipd/WSL2에서 genesys 스캔 완료 후 연결 끊김이 재현되는가 | [usb-transport](usb-transport.md) |
| S-4 | Cygwin에서 sane-backends가 언제·왜 빠졌는가 | 낮은 우선순위 |
| S-5 | WSL2에서 SCSI 패스스루가 가능한가(구형 Coolscan) | [validation-matrix](../09-hardware/validation-matrix.md) |
| S-6 | SANEWinDS의 문서화된 프로그래밍 API 존재 여부 | [remote-saned](remote-saned.md) |
| S-7 | WiaSane의 Windows 10/11 서명 상태 | 낮은 우선순위 |
| S-8 | MinGW `scanimage`가 `LC_ALL=C`로 메시지 언어를 고정하는가 | [exact-option-contract](../02-frontend-contract/exact-option-contract.md) §6 |

## 10. 출처

- <https://gitlab.com/sane-project/backends> · `/-/tags?format=atom` ·
  `/-/raw/1.4.0/README` · `/-/raw/1.4.0/README.windows` ·
  `/-/raw/1.4.0/configure.ac` · `/-/raw/1.4.0/.gitlab-ci.yml` ·
  `/-/raw/1.4.0/frontend/scanimage.c` · `/-/raw/1.4.0/backend/dll.conf.in`
- <https://www.sane-project.org/>
- <https://cygwin.com/packages/package_list.html>
- <https://packages.msys2.org/base/mingw-w64-sane> ·
  <https://packages.msys2.org/packages/mingw-w64-ucrt-x86_64-sane>
- <https://github.com/msys2/MINGW-packages/blob/master/mingw-w64-sane/PKGBUILD> ·
  `.../001-fix-build-on-mingw.patch`
- <https://github.com/microsoft/vcpkg> · <https://github.com/conan-io/conan-center-index>
- <https://sourceforge.net/projects/sanewinds/files/> ·
  <https://github.com/cyanfish/SANEWinDS>
- <https://sanetwain.ozuzo.net/> · <https://wiki.archlinux.org/title/SANE>
- <https://github.com/mback2k/wiasane>
- <https://github.com/dorssel/usbipd-win> ·
  <https://learn.microsoft.com/en-us/windows/wsl/connect-usb> ·
  <https://github.com/microsoft/WSL2-Linux-Kernel>
- <https://github.com/libusb/libusb/wiki/Windows> · <https://zadig.akeo.ie/>
- <https://github.com/twain/twain-dsm/releases> ·
  <https://learn.microsoft.com/en-us/windows-hardware/drivers/image/>
- <https://www.naps2.com/doc/scanner-sharing>
