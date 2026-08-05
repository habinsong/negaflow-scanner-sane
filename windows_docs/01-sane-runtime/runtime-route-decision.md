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

## 4.4 2026-08-05 실측 — 장비 없이 확인한 것

Windows 11 x64에 MSYS2를 설치하고 `mingw-w64-ucrt-x86_64-sane`를 깔아
실제로 확인했다. **스캐너는 없었다.** 그래서 "장치를 여는" 항목은 전부
그대로 열려 있고, 아래는 그 앞까지의 사실이다.

```text
scanimage (sane-backends) 1.4.0; backend version 1.4.0    ← macOS와 같은 버전
```

**① 패키지는 실재하고 설치된다.** §3.1이 전제한 A 경로의 첫 조건이 참이다.
주요 대상 백엔드(genesys, epson2, epsonds, coolscan2, coolscan3)의 DLL이
모두 들어 있다.

**①A 결론부터 — 재고 패키지는 백엔드를 하나도 못 싣고, 원인은 두 가지다.**

```text
원인 1  HAVE_DLOPEN 이 꺼져 있다        MinGW 에 dlfcn.h 가 없어서
        + --disable-preload            → 동적·정적 어느 쪽으로도 못 싣는다
        해결: mingw-w64-ucrt-x86_64-dlfcn 를 넣고 다시 빌드하면 켜진다

원인 2  파일 이름 규칙이 다르다          dll.c 는 Windows 에서 **Cygwin** 이름을 찾는다
        찾는 것: cygsane-<name>-1.dll
        있는 것: libsane-<name>-1.dll
        해결: 배포할 때 cygsane- 이름으로 넣는다. **소스 패치가 필요 없다**
```

둘 다 고친 뒤 `test` 백엔드가 실제로 열렸다.

```text
scanimage -f "%d\t%v\t%m\t%t%n"
  test:0	Noname	frontend-tester	virtual device
  test:1	Noname	frontend-tester	virtual device
```

원인 2가 특히 중요하다. `dll.c` 의 해당 블록은 이렇게 생겼다.

```c
# elif defined (HAVE_WINDOWS_H)
#   undef PREFIX
#   define PREFIX "cygsane-"
#   define POSTFIX "-%u.dll"
```

**upstream 이 Windows 를 Cygwin 으로만 상정하고 있다.** MinGW 빌드는 이름이
어긋나서 자기 백엔드를 못 찾는다. 아무도 눈치채지 못한 이유는 증상이
"스캐너가 없다"와 구별되지 않기 때문이다.

`LD_LIBRARY_PATH` 는 필요 없었다(있으나 없으나 같았다). `DIR_SEP` 는
`_WIN32` 에서 `;` 이므로 드라이브 문자가 잘리는 문제도 이 경로에는 없다.

**①a 증상은 "장치가 없다"와 구별되지 않는다.**

가장 큰 발견이다. `-L`이 아무것도 못 찾는 것을 "장치가 없어서"로 읽고
넘어갈 뻔했는데, `test` 백엔드를 넣어 빌드해도 똑같이 안 보여서 파고들었다.

`backend/dll.c`는 백엔드를 싣는 길이 **둘뿐이다.**

```text
HAVE_DLOPEN + HAVE_DLFCN_H   런타임에 동적 로드
ENABLE_PRELOAD               libsane 에 정적 링크
```

**`LoadLibrary` 분기는 없다.** 그리고 MSYS2 빌드는 둘 다 꺼져 있다.

```text
include/sane/config.h:   /* #undef HAVE_DLOPEN */
configure 인자:          --disable-preload
```

즉 이 패키지의 `libsane`은 **백엔드를 하나도 갖고 있지 않다.** 증상은
장치가 없을 때와 구별되지 않는다.

```text
scanimage -L                        No scanners were identified.
scanimage -A -d genesys:libusb:...  open of device ... failed: Operation not supported
scanimage -A -d test:0              open of device test:0 failed: Operation not supported
```

**세 줄이 전부 같은 원인이다.** 앞의 §4.4 ⑥에서 "Operation not supported"를
WinUSB 바인딩이 없어서라고 적었는데 **그것도 틀렸다** — 백엔드가 아예 없어서다.
그 절의 오류 분류 논의는 근거가 없으니 실기에서 다시 봐야 한다.

이것이 S-1에 주는 의미가 크다. **장비를 붙여도 이 패키지로는 실패한다.**
S-1을 재고 패키지로 시도하면 "스캐너가 안 열린다"는 결론이 나오는데,
그것은 스캐너나 드라이버 문제가 아니라 빌드 구성 문제다.

`--enable-preload` 로 다시 빌드하면 `BACKENDS` 목록이 `libsane`에 정적으로
들어간다. 그쪽이 Windows에서 유일하게 성립하는 구성이다.

**② 백엔드 DLL 위치가 §7의 가정과 다르다 — 그리고 사실 무의미하다.**

`lib/bin`에 있든 `lib/sane`에 있든 **아무도 그것을 열지 않는다**(①a).
E-1("dll 백엔드가 어느 경로에서 찾는가")은 질문 자체가 성립하지 않는다.
백엔드 DLL 60개를 `bin/`에 복사해 놓고 다시 돌려도 결과가 같았다.

배치 문제로 보였던 것의 실체는 로딩 방식 문제였다. §7의 디렉터리 그림에서
`sane\lib\sane\libsane-*.dll` 줄은 preload 구성에서는 **필요 없다.**

```text
가정(§7)   sane\lib\sane\libsane-genesys-1.dll
실제       ucrt64\lib\bin\libsane-genesys-1.dll     ← DLL은 lib\bin
           ucrt64\lib\sane\libsane-genesys.dll.a    ← lib\sane에는 import lib만
```

패키징할 때 이 레이아웃을 그대로 옮길지 재배치할지가 E-1의 실질적 내용이다.
§7의 디렉터리 그림은 실측에 맞춰 다시 써야 한다.

**③ `test` 백엔드가 패키지에 없다 — 그리고 빼 둔 이유가 있다.**

`libsane-test-1.dll`이 존재하지 않는다. PKGBUILD의 `BACKENDS` 목록에도
없다. 처음에는 단순 취사선택으로 보였는데, 목록에 넣고 빌드해 보니
**애초에 MinGW에서 컴파일되지 않는다.**

```text
backend/test.c:3117: error: 'F_SETFL' undeclared
backend/test.c:3117: error: 'O_NONBLOCK' undeclared
```

`sane_test_set_io_mode`가 `fcntl(F_SETFL, O_NONBLOCK)`을 쓴다. MinGW에는
그 상수가 없다. 논블로킹 I/O는 이 백엔드의 부가 기능이고 지원하지 않는
백엔드는 `SANE_STATUS_UNSUPPORTED`를 돌려주는 것이 규약이므로,
Windows에서 그 경로로 보내는 것이 최소 수정이다.

이것이 중요한 이유: SANE의 `test` 백엔드는 **하드웨어 없이 합성 이미지를
만드는 표준 수단**이다. 그것을 쓰려면 패치가 하나 더 필요하다는 뜻이고,
바꿔 말하면 **장비 없는 스캔 검증 자체가 공짜가 아니다.**

**④ `SANE_DEBUG_DLL`을 설정하면 `scanimage.exe`가 세그폴트한다.**

```text
SANE_DEBUG_DLL=255 scanimage.exe -L   → Segmentation fault (exit 139)
SANE_DEBUG_DLL=3   scanimage.exe -L   → 출력 없음
설정하지 않으면                        → 정상 동작
```

[diagnostics-and-troubleshooting](../08-operations/diagnostics-and-troubleshooting.md)이
진단 모드에서 `SANE_DEBUG_*`를 켜라고 적고 있는데, **이 빌드에서는 그것이
크래시 경로다.** 진단 기능을 붙이기 전에 이 사실을 반영해야 한다.

**⑤ 로케일: 번역 카탈로그가 아예 없다.**

```text
LC_ALL 미설정 / LC_ALL=C / LC_ALL=ko_KR.UTF-8   → 셋 다 같은 영어 메시지
ucrt64\share\locale\ko\LC_MESSAGES\             → sane 카탈로그 없음
```

한국어 Windows에서 메시지가 번역되지 않는 이유는 `LC_ALL=C`가 통해서가
아니라 **번역본이 배포에 없어서**다. 결론은 같지만 근거가 다르다 —
카탈로그를 포함하는 빌드로 바뀌면 `LC_ALL=C`가 다시 유일한 방어선이 된다.
**그래서 `LC_ALL=C`를 계속 보낸다.** S-6은 이 범위까지만 통과다.

**⑥ 실제 오류 문구가 macOS와 다르다.**

```text
Windows   open of device genesys:libusb:001:002 failed: Operation not supported
macOS     open of device ... failed: Invalid argument
```

`isStaleDeviceError`는 `"open of device"` 부분문자열로 잡으므로 **양쪽 다
재시도 경로를 탄다.** 그러나 `classifyStderr`는 갈린다 —
`"invalid argument"`는 `notConnected`, `"operation not supported"`는 어느
키워드에도 걸리지 않아 `ioFailure`가 된다. 같은 상황이 두 OS에서 다른 코드로
보일 수 있다(I-5).

**고치지 않았다.** 여기서 본 "Operation not supported"는 WinUSB 바인딩이
없는 상태의 응답이고, 실기에서 주소가 만료됐을 때의 문구는 아직 모른다.
**실측 없이 분류표를 늘리면 추측을 코드에 박는 것이다.** S-1과 함께 확인한다.

**⑦ 어댑터가 진짜 `scanimage.exe`를 몬다.**

```text
negaflow-scanner-sane.exe detect                    → {"devices":[]}   exit 0
negaflow-scanner-sane.exe capabilities <없는 장치>   → notConnected …   exit 1
```

`detect`는 장치가 없다는 사실을 계약대로 빈 배열로 보고하고, `capabilities`는
문서화된 3회 재시도와 주소 재확인을 거친 뒤 정해진 문구로 실패한다.
**가상 `scanimage`가 아니라 MinGW로 빌드된 진짜 바이너리 상대의 결과다.**

### 4.4a 드라이버를 바꾸지 않는 길 — 되지만 쓸 수 없다 (2026-08-05, 실기)

Plustek OpticFilm 8100(`07b3:130c`, README의 지원 변종)을 실제로 연결해
확인했다. §8이 전제한 "Zadig로 WinUSB 바인딩"을 피할 수 있는지가 질문이었다.

**① 왜 macOS는 안 바꿔도 되는가 — 이 문서가 답한 적이 없다.**

SANE의 문제가 아니라 OS 드라이버 모델 차이다.

```text
macOS    USB 장치를 커널이 독점하지 않는다. Image Capture 가 사용자 공간이라
         libusb 가 IOKit 으로 그냥 연다. 그래서 아무것도 안 바꿔도 된다.
Windows  장치 하나를 커널 함수 드라이버 **하나**가 소유한다. libusb 는
         WinUSB / libusbK / libusb0 가 소유한 장치에만 말을 걸 수 있다.
```

이 스캐너는 Plustek 드라이버(`usbscan` 서비스, `oem113.inf`)가 소유 중이다.
그래서 **열거는 되는데 열리지 않는다.**

```text
could not open USB device 0x07b3/0x130c at 001:027:
    Operation not supported or unimplemented on this platform   (LIBUSB_ERROR_NOT_SUPPORTED)
```

**② UsbDk 경로 — 기술적으로는 성공했다.**

UsbDk는 벤더 드라이버를 **교체하지 않고 공존하는** 리다이렉터이고, libusb에
백엔드가 이미 들어 있다(MSYS2 빌드에도 컴파일돼 있다). SANE이 요청만 하지
않고 있었다. 요청하도록 고치니 **실제로 열렸다.**

```text
post init -> 0
post set_option -> 0 (LIBUSB_SUCCESS)
post: open 07b3:130c -> 0 (LIBUSB_SUCCESS)
post:   product = Film Scanner        ← Plustek 드라이버를 유지한 채로
```

**③ 그런데 호출 위치가 libusb 헤더 설명과 반대다.**

`libusb.h`는 이 옵션을 `libusb_init_context()`로 초기화 시점에 주라고 적었다.
**그렇게 하면 동작하지 않는다.** libusb 1.0.30에서 실측:

```text
libusb_init_context(&ctx, {USE_USBDK})   set_option 은 성공하는데 열기는
                                          여전히 winusb_open 으로 가고 -12
libusb_init(&ctx) → set_option(ctx, …)   열린다
```

원인으로 보이는 것: 옵션이 컨텍스트별 `priv->backend`를 바꾸는데
`libusb_init_context`는 **옵션을 먼저 적용하고 백엔드를 나중에 init** 한다.
게다가 프로세스의 첫 컨텍스트에서는 `usbdk_available`이 아직 서지 않아
`UsbDk backend not available`로 떨어진다(로그로 확인).

**④ 그리고 UsbDk는 커널을 무너뜨렸다.**

SANE이 그 경로로 스캐너를 여는 순간 시스템이 죽었다.

```text
BugCheck 0x0000010D  WDF_VIOLATION
파라미터 0xD, 덤프 C:\Windows\Minidump\080526-9578-01.dmp
UsbDk = KMDF 1.11 드라이버
```

UsbDk의 **알려진 결함**이다 — 전원 정책 소유자 충돌
([daynix/UsbDk#115](https://github.com/daynix/UsbDk/issues/115)). libusb
upstream이 "UsbDk는 안정성 문제로 권장하지 않는다"고 적은 것이 이것이다.

`libusb_open` + 문자열 서술자 읽기까지는 죽지 않았다. SANE이 그보다 더
많은 것을 할 때 죽었다. **어느 호출이 방아쇠인지는 특정하지 못했다.**

**⑤ 결론 — 되지만 배포할 수 없다.**

```text
D-01 보강  UsbDk 경로는 "드라이버를 안 바꾸는 유일한 길"이지만
           제품 경로가 될 수 없다. 사용자 PC 에 블루스크린을 유발하는
           커널 드라이버를 배포하는 것이 되기 때문이다.

           sanei_usb 패치는 남기되 **opt-in 으로 둔다**
           (`SANE_USB_USE_USBDK`). 기본값으로 두면 스캔이 블루스크린이 된다.

           1차 경로는 §8 그대로 WinUSB 바인딩이다.
```

**⑥ 부수 사실 — UsbDk는 재열거가 필요하다.**

설치 시점에 이미 꽂혀 있던 장치는 UsbDk 목록에 나타나지 않는다. 재부팅 후
장치 수가 4개에서 15개로 늘고 그제서야 스캐너가 보였다. 설치 프로그램이
UsbDk를 다룬다면 이 사실을 UX에 반영해야 한다.

### 4.4b 드라이버를 **정말로** 안 바꾸는 길이 있다 — `usbscan.sys` (2026-08-05, 실기)

§4.4a의 전제가 틀렸다. "Windows에서는 커널 드라이버가 장치를 독점하므로
libusb가 소유하지 않으면 못 연다"까지는 맞다. 그런데 **그 소유자가 raw USB를
사용자 모드에 열어준다**는 사실을 빠뜨렸다.

`usbscan.sys`는 Windows의 still-image USB 클래스 드라이버이고, 벤더 스캐너
드라이버가 그 위에 얹힌다. 이 드라이버는 **문서화된 IOCTL 인터페이스**를
제공한다 — 원래 사용자 모드 스캐너 드라이버(WIA 마이크로드라이버)가 쓰라고
만든 것이다.

```text
IOCTL_GET_PIPE_CONFIGURATION   엔드포인트/파이프 목록
IOCTL_GET_DEVICE_DESCRIPTOR    VID / PID / bcdDevice
IOCTL_SEND_USB_REQUEST         벤더 정의 컨트롤 전송 (IO_BLOCK_EX)
IOCTL_READ_REGISTERS / WRITE_REGISTERS
ReadFile / WriteFile           **raw 벌크 파이프 읽기·쓰기**
IOCTL_RESET_PIPE, IOCTL_SET_TIMEOUT, IOCTL_CANCEL_IO
```

**실측 (OpticFilm 8100, Plustek 드라이버 그대로, 관리자 아님, 설치한 것 없음):**

```text
\\.\Usbscan0 열림
  파이프 3개
    [0] endpoint 0x81  bulk        maxPacket 512
    [1] endpoint 0x02  bulk        maxPacket 512
    [2] endpoint 0x83  interrupt   maxPacket 1
  IOCTL_GET_DEVICE_DESCRIPTOR -> VID=07B3 PID=130C bcdDevice=0605
```

**이것이 macOS와 같은 위치다.** macOS가 아무것도 안 바꿔도 되는 이유는 커널이
장치를 독점하지 않아서인데, Windows는 독점하되 **그 소유자가 통로를 낸다.**
도달 방법이 다를 뿐 결과는 같다.

#### 무엇이 증명됐고 무엇이 아직 아닌가

처음 시도에서 벤더 전송이 데이터를 옮기는지 확인하지 못했는데, **원인은
드라이버가 아니라 호출 규약을 어긴 이쪽이었다.** MS 문서에 이렇게 적혀 있다.

```text
"The bmRequestType member ... is not used with IOCTL_SEND_USB_REQUEST."
TransferBuffer = lpOutBuffer (read) or pIoBlockEx->pbyData (write)
pbyData        = "Same pointer as lpOutBuffer"
uLength        = "Same value as lpOutBufferSize"
```

즉 **읽기 데이터는 `pbyData` 가 아니라 출력 버퍼로 오고**, 두 포인터와 두
길이가 서로 같아야 한다. 처음 프로브는 둘을 다르게 줬고, 그래서 드라이버가
입력 구조체를 그대로 되돌려준 것이다. 규약대로 다시 보내니 바로 나왔다.

```text
GL843 레지스터 0x00..0x5F 를 읽는다 (드라이버 교체 없음, 관리자 아님)
  00: 05 00 00 8F 00 40 00 00 00 00 00 01 00 00 00 00
  10: 00 00 00 00 00 00 33 14 10 00 10 00 00 04 80 00
  ...
  40: B0 48 00 00 00 00 00 00 00 00 00 00 00 00 00 00
       ^^ ^^ REG40/REG41 — GL843 상태 레지스터
  0xAA 그대로인 칸 0/96,  서로 다른 값 17종,  두 번째 읽기도 전부 동일
```

**컨트롤 전송이 실제로 스캐너까지 간다.** 그 위에서 `sanei_usb` 백엔드를
붙이고 나니 나머지도 따라왔다.

```text
증명됨   scanimage -L    → device `genesys:usbscan:000' is a
                            PLUSTEK OpticFilm 8100 flatbed scanner
         scanimage -A    → 63줄 옵션 덤프 전문 (mode/source/resolution/
                            geometry/gamma/lamp-off …)
         장치명이 안 바뀐다 — usbscan:000 을 세 번 열어도 그대로.
                            macOS 의 libusb:BBB:DDD churn 이 여기엔 없다
```

`sane_open` 이 성공했다는 것은 genesys 의 ASIC init 전체가 돌았다는 뜻이고,
거기엔 벌크 전송이 들어 있다.

```text
미확인   실제 필름 스캔 한 장 (진행 중)
```

#### 이 경로가 의미하는 것

```text
필요 없는 것   WinUSB 바인딩 / Zadig / libwdi / UsbDk / 커널 드라이버 서명
               관리자 권한 / 재부팅 / 벤더 소프트웨어 포기
한 일          sanei_usb 에 usbscan.sys 백엔드를 하나 더 붙였다.
               patches/005-usbscan-backend.patch — **전부 사용자 모드 코드다.**
```

§4.4a의 UsbDk 논의와 §8의 Zadig 절차는 **둘 다 불필요해졌다.**

#### 도중에 걸린 것 두 가지

**`IOCTL_SET_TIMEOUT` 은 거짓말을 한다.** 성공을 반환하고 아무것도 바꾸지
않는다 — `IOCTL_GET_TIMEOUT` 은 `ERROR_NOT_SUPPORTED` 를 돌려주고, 응답 없는
전송은 드라이버 기본값인 **정확히 120초**를 쓴다. 백엔드가 쓸 수 있는 마감이
아니라서, 핸들을 겹침 입출력(`FILE_FLAG_OVERLAPPED`)으로 열고 마감 시간을
`sanei_usb` 쪽에서 직접 지킨다.

**SANE 디버그 출력이 mingw 에서 죽는다.** `SANE_DEBUG_*` 를 어떤 값으로든
켜면 프론트엔드가 segfault 한다. `sanei_debug_msg` 가 `localtime (&tv.tv_sec)`
를 호출하는데, mingw-w64 의 `struct timeval::tv_sec` 은 `time_t`(8바이트)가
아니라 `long`(4바이트)이다. `localtime` 이 이웃 스택 4바이트를 시각의 일부로
읽고 `NULL` 을 돌려주며, 바로 다음 줄에서 그것을 역참조한다. 실측:

```text
sizeof(tv.tv_sec)=4  sizeof(time_t)=8
localtime(&tv.tv_sec) = 0000000000000000
localtime(&copy)      = 000002B99560FC00
```

`patches/006-debug-output-on-mingw.patch` 로 고쳤다. 이것 없이는 Windows 에서
SANE 을 진단할 방법이 없다.

→ 패치 전문과 재현 절차: [sane-runtime/SOURCES.md](../../sane-runtime/SOURCES.md)

### 4.5 E-2를 닫지 못했다 — 시도한 방법과 실패 이유

`SANE_CONFIG_DIR`에 드라이브 문자가 든 경로(`C:\...`)를 주고, dll.conf에
`epson2`만 남긴 설정 디렉터리로 `-A -d genesys:...`를 요청해 보았다.
honor하면 genesys가 목록에 없으니 다른 오류가 나야 한다는 설계였다.

**세 경우(미설정 / `C:\` 경로 / MSYS 경로)가 모두 같은 출력을 냈다.**
즉 이 실험은 아무것도 구분하지 못한다 — `-d <backend>:...`처럼 백엔드를
명시하면 dll 계층이 dll.conf 목록과 무관하게 그 백엔드를 직접 열려 하기
때문으로 보인다.

**장치가 하나라도 보이는 환경이 필요하다.** E-2는 그대로 대기다.

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

#### 결과 — **통과** (2026-08-06, OpticFilm 8100 실기)

2단계는 필요 없었다. **Zadig 도 WinUSB 도 쓰지 않는다** — §4.4b 참조.

```text
장치 목록   genesys:usbscan:000|PLUSTEK|OpticFilm 8100|flatbed scanner
옵션 덤프   63줄. mode/source/resolution/depth/geometry/gamma/lamp-off
```

컬러 해상도 전 범위를 실기로 돌렸다. `-x`/`-y` 는 고해상도에서 시간을
아끼려고 줄인 것이지 스캐너 한계가 아니다.

```text
 600 dpi 36.33×25   24초  3,030,277 bytes  856×590
1200 dpi    20×15   16초  4,010,149 bytes  944×708
2400 dpi      8×6   21초  2,553,829 bytes  752×566
3600 dpi      4×3   22초  1,428,037 bytes  560×425
7200 dpi    2×1.5   28초  1,428,037 bytes  560×425
 600 dpi 36.33×25   17초  3,030,277 bytes  856×590   ← 전 범위 뒤 재현
```

3600/4mm 와 7200/2mm 가 같은 560×425 인 것은 산술이 맞아떨어지는 것이다.
다섯 장 모두 값 종류가 249~256 으로 실제 광학 데이터였고, 7200 dpi 에서는
필름 그레인이 분해된다. 마지막 600 dpi 재현이 성공했으므로 해상도를 오가도
장치 상태가 오염되지 않는다.

**Gray 는 제외했다.** upstream genesys 결함으로 무한 정지한다 —
[sane-runtime/SOURCES.md](../../sane-runtime/SOURCES.md) 참조.

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

#### 결과 — **실패** (2026-08-05). 단 3줄로 고쳐진다

**스캐너 없이 끝났다.** 이 spike는 "바이트가 보존되는가"를 묻는 것이고,
그것은 CRT의 파일 모드 문제라 장치가 필요 없었다.

**① 소스 감사 — SANE 1.4.0은 Windows에서 바이너리 모드를 설정하지 않는다.**

`frontend/scanimage.c`에서 모드를 바꾸는 곳은 OS/2 하나뿐이다.

```c
#ifdef __EMX__          /* OS2 - write in binary mode. */
  _fsetmode (ofp, "b");
#endif
```

이미지는 `fwrite(..., ofp)`로 나가고 `ofp`는 기본이 `stdout`이다.
MSYS2가 유지하는 `001-fix-build-on-mingw.patch`는 `frontend/scanimage.c`를
**건드리지 않는다**(30개 파일을 고치지만 전부 백엔드·빌드 파일이다).

**② `--output-file`은 대체안이 못 된다.**

옵션은 존재한다(`-o`). 그러나 여는 방식이 이렇다.

```c
ofp = fopen (output_file, "w");     /* "wb" 가 아니다 */
```

**텍스트 모드다.** stdout과 정확히 같은 문제를 겪는다.
§5의 "옵션이 있다면 그것을 쓴다"는 **성립하지 않는다.**

**③ 실측 — MinGW/UCRT 런타임은 텍스트 모드가 기본이다.**

`scanimage.c`와 같은 방식(setmode 없이 `fwrite`)으로 쓰는 10바이트짜리
프로그램을 같은 툴체인(gcc 16.1.0, MSYS2 ucrt64)으로 빌드해 쟀다.

```text
입력   49 49 2a 00 0a ff 0a 0d 0a 00                 10바이트
stdout 49 49 2a 00 0d 0a ff 0d 0a 0d 0d 0a 00        13바이트  ← 0x0A → 0x0D 0x0A
-o 경로 (fopen "w")                                   13바이트  ← 동일하게 깨진다
```

**④ 배포된 `scanimage.exe` 자체가 텍스트 모드다.**

프로브가 아니라 실제 바이너리로 확인했다. `-L`과 `--help` 출력의 줄 끝이
전부 CRLF다.

```text
scanimage.exe -L     stdout 5줄 전부 \r\n
scanimage.exe --help 출력 38줄 전부 \r\n
```

즉 이미지가 없어도 **이 빌드의 stdout이 텍스트 모드라는 것은 확정**이다.
이미지 바이트가 그 경로를 지나면 0x0A마다 0x0D가 삽입된다.

**⑤ 고치는 데는 3줄이면 된다 — 그것도 실측했다.**

```c
#ifdef _WIN32
  _setmode (_fileno (ofp), _O_BINARY);
#endif
```

`ofp`가 정해진 직후에 넣고 같은 툴체인으로 다시 빌드해 쟀다.

```text
수정 후 stdout   10바이트, 입력과 바이트 동일
수정 후 -o 경로  10바이트, 입력과 바이트 동일
```

**⑥ 그래서 D-01은 폐기가 아니라 조건이 하나 늘어난다.**

§4.2는 "S-2 실패 → A 폐기, B로 전환"이라고 적었다. 그 판단은 "패치 없이는
안 된다"를 "A가 불가능하다"로 읽은 것인데, **이 저장소는 이미 SANE 패치
유지자다** — macOS의 `Formula/sane-backends-negaflow.rb`가 Coolscan 수정을
얹어 SANE를 직접 빌드한다. Windows에서 3줄을 더 얹는 것은 새로운 종류의
부담이 아니다.

```text
D-01 수정안  A(재배포)를 유지하되 **패치 없는 MSYS2 패키지를 그대로
             재배포하지 않는다.** frontend/scanimage.c 의 바이너리 모드
             수정을 얹어 직접 빌드한 것만 배포한다.
             (S-1 은 여전히 장비가 필요하며 그것이 A 의 남은 차단 조건이다)
```

이 결정은 사용자 승인이 필요하다 —
[decision-register](../00-overview/decision-register.md)가 소유한다.

**⑥a 패치 없는 빌드로 스캔하면 어떻게 보이는가**

조용히 깨진 이미지가 사용자에게 가지는 **않는다.** 어댑터가 획득 뒤
`validatedScannedTIFF` 로 컨테이너와 실제 디코드를 확인하므로, 삽입된
0x0D 가 strip 오프셋과 바이트 수를 어긋나게 만들어 그 단계에서 걸린다.

```text
증상   ioFailure: scanimage TIFF를 실제 이미지로 decode할 수 없습니다.
원인   이 절의 텍스트 모드
```

**감지 코드를 넣지 않았다.** 옵션 덤프에 CRLF가 있으면 그 빌드의 stdout이
텍스트 모드라는 뜻이므로 획득 전에 미리 경고할 수는 있다. 그러나 실패는
이미 안전하게 잡히고 있어 얻는 것이 오류 문구뿐이며, 우리가 배포할 빌드는
애초에 패치된 것이라 그 경로를 지나지 않는다. **가정 위에 분기를 늘리지
않는다** — 남의 빌드를 물려 쓰는 구성이 실제로 생기면 그때 넣는다.

**⑦ 덤으로 CRLF 가정이 실측으로 확인됐다.**

`-L`/`--help`가 CRLF를 낸다는 것은 옵션 덤프(`-A`)도 CRLF로 온다는 뜻이다.
파리티 하네스가 유일한 의도적 divergence로 기록해 둔 그 항목이 —
"MinGW `scanimage`가 CRLF를 **낼 수 있으므로**" — 이제 가능성이 아니라
**측정된 사실**이다. C++ 파서가 CRLF를 나누고 Swift가 못 나누는 차이를
그대로 둔 판단이 옳았다.
→ [option-dump-parser](../02-frontend-contract/option-dump-parser.md) §2.2

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

#### 결과 — **다르다** (2026-08-05, OpticFilm 8100 실기)

```text
genesys:usbscan:000|PLUSTEK|OpticFilm 8100|flatbed scanner
```

`:libusb:` 가 아니라 `:usbscan:` 이다. 위 세 판정이 전부 이 이름을 USB 로도,
안정 선택자로도 보지 못한다. **`:usbscan:` 를 세 곳 모두에 더해야 한다.**

### S-5 — open 후 주소 변동

macOS 실측(열 때마다 libusb 주소가 바뀐다)이 Windows에서도 성립하는가.
성립하지 않아도 재연결 로직은 제거하지 않는다.

#### 결과 — **성립하지 않는다** (2026-08-05, OpticFilm 8100 실기)

```text
1: genesys:usbscan:000
2: genesys:usbscan:000
3: genesys:usbscan:000
```

`usbscan:NNN` 의 N 은 커널 장치 인스턴스 번호라 열고 닫는다고 바뀌지 않는다.
macOS 의 `libusb:BBB:DDD` churn 이 여기엔 없다. **그래도 재연결 로직은 그대로
둔다** — 뽑았다 꽂으면 번호가 달라질 수 있고, 그 경로는 아직 확인하지 않았다.

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
3. negaflow 재시작 → 플러그인 승인 → 스캔
```

**3단계가 끝이다.** 드라이버 경고도, 바인딩 단계도, 관리자 권한도, 재부팅도
없다 (§4.4b). 제조사 소프트웨어는 그대로 동작한다 — 예전 초안에 있던
"WinUSB로 바꿉니다" 경고는 이제 사실이 아니어서 지웠다.

## 8. 드라이버 바인딩 도구 선택

> **이 절은 폐기됐다 (2026-08-06, 실기 검증).** 드라이버를 바인딩하지 않는다.
> §4.4b 가 이유를 소유한다 — `usbscan.sys` 가 사용자 모드에 raw USB 를 열어주고,
> `sanei_usb` 에 백엔드를 하나 더 붙이면 드라이버 교체·관리자 권한·재부팅이
> 전부 필요 없다. 아래는 왜 그 길을 검토했는지 남겨두는 기록이다.
>
> 결정 상태는 [decision-register](../00-overview/decision-register.md) §2 의
> D-09 에 있다.

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
