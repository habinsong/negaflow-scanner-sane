# SANE runtime — sources and patches

최종 갱신: 2026-11-03

Windows 빌드가 쓰는 SANE 런타임의 출처와 변경 내용을 적는다.
플러그인은 이 런타임을 **자식 프로세스(`scanimage.exe`)로 실행**하고 링크하지
않는다. 그래도 배포하는 바이너리에는 GPL 의무가 붙으므로, 여기 있는 것만으로
같은 바이너리를 다시 만들 수 있어야 한다.

## upstream

| 항목 | 값 |
| --- | --- |
| 프로젝트 | sane-backends |
| 버전 | 1.4.0 |
| 원본 | `https://gitlab.com/sane-project/backends/-/archive/1.4.0/backends-1.4.0.tar.bz2` |
| sha256 | `813ef8818a498cbb11615f657cd6dc66536ef34df4a557d9cd63086622f6123d` |
| 라이선스 | GPL-2.0-or-later |

빌드 레시피는 [`PKGBUILD`](PKGBUILD) 이며 MSYS2 의
`mingw-w64-sane` 를 기반으로 한다. 빌드 대상 백엔드는
`genesys epson2 epsonds coolscan2 coolscan3 test` 이다.

## 패치

| 파일 | 출처 | 무엇을 고치나 |
| --- | --- | --- |
| `001-fix-build-on-mingw.patch` | [MSYS2 mingw-w64-sane](https://github.com/msys2/MINGW-packages/tree/master/mingw-w64-sane) (GPL-2.0-or-later) | MSYS2 원본 그대로. mingw 에서 컴파일되게 한다 |
| `002-binary-output-mode.patch` | 이 저장소 | `scanimage` 가 stdout 을 텍스트 모드로 열어 이미지의 `0x0A` 를 `0x0D 0x0A` 로 바꿔 내보내던 것을 막는다 |
| `003-test-backend-on-mingw.patch` | 이 저장소 | `test` 백엔드가 mingw 에서 빌드되게 한다. 하드웨어 없는 회귀 시험에 필요하다 |
| `004-usbdk-on-windows.patch` | 이 저장소 | `SANE_USB_USE_USBDK` 가 설정됐을 때만 libusb 의 UsbDk 백엔드를 쓴다. **기본값은 끈 채로 둔다** |
| `005-usbscan-backend.patch` | 이 저장소 | `sanei_usb` 에 `usbscan.sys` 백엔드를 더한다. 아래 참조 |
| `006-debug-output-on-mingw.patch` | 이 저장소 | `SANE_DEBUG_*` 를 켜면 프론트엔드가 segfault 하던 것을 고친다 |
| `007-cancel-on-sigbreak.patch` | 이 저장소 | Windows 에서 취소가 스캐너를 죽이지 않게 한다. 아래 참조 |
| `008-opticfilm-wait-for-park.patch` | 이 저장소 | OpticFilm 이 스캔 헤드를 세운 뒤 끝나게 한다. 아래 참조 |
| `009-expose-infrared-frame.patch` | 이 저장소 | `epson2`가 IR 프레임을 별도 `SANE_FRAME_IR`로 반환하도록 한다 |
| `010-bundled-backend-dir.patch` | 이 저장소 | 설치 번들의 백엔드 디렉터리를 `SANE_BACKEND_DIR`로 지정할 수 있게 한다 |
| `011-opticfilm-host-side-gray.patch` | 이 저장소 | OpticFilm 7400-v2/8100의 멎는 단일채널 Gray 대신 기존 스트리밍 RGB→Gray 경로를 사용하고 GL845/GL846 의 빠진 출력 길이 계산을 바로잡는다 |
| `012-genesys-upstream-opticfilm.patch` | [sane-backends master](https://gitlab.com/sane-project/backends) (GPL-2.0-or-later) | 1.4.0 이후 upstream 이 받은 `genesys` 커밋 14개를 그대로 옮긴다. OpticFilm 8200i SE(GL128), 7400 v1, 7600i v1 과 그것이 기대는 수정. 아래 참조 |
| `013-opticfilm-7400-v1-wait-for-park.patch` | 이 저장소 | 012 가 새로 쓴 7400 v1 행에 008 의 `MUST_WAIT` 을 되살린다 |
| `014-coolscan-depth-list.patch` | [sane-backends 9bea1ee2](https://gitlab.com/sane-project/backends/-/commit/9bea1ee256c744098576acee98053e094b4a14a2) | `coolscan2`/`coolscan3` 의 깊이 word list 할당 수정. 맥 formula 에는 1.0.3 부터 있었고 Windows 에만 빠져 있었다 |
| `015-gl128-libcxx-constexpr-pair.patch` | 이 저장소 | 012 의 `gl128.cpp` 한 줄이 libc++ 의 C++11 모드에서 컴파일되지 않던 것을 고친다. 아래 참조 |

### 005 — usbscan.sys 백엔드

Windows 는 USB 장치를 커널 함수 드라이버 하나가 독점 소유하고, libusb 는
WinUSB / libusbK / libusb0 이 소유한 장치에만 말을 걸 수 있다. 스캐너 제조사
패키지는 마이크로소프트 still-image 클래스 드라이버(`usbscan.sys`)를 붙이므로,
스캐너는 열거되지만 열리지 않는다 — `LIBUSB_ERROR_NOT_SUPPORTED`.

Zadig 등으로 WinUSB 를 다시 묶는 것은 답이 될 수 없다. **제조사 드라이버를
걷어내는 일이라 SilverFast 와 VueScan 이 같이 못 쓰게 된다.**

`usbscan.sys` 는 바꿀 필요가 없다. 설계상 사용자 모드에 raw USB 를 열어주며,
그것이 정확히 `sanei_usb` 가 필요로 하는 면이다.

| sanei_usb | usbscan.sys |
| --- | --- |
| `sanei_usb_control_msg` | `IOCTL_SEND_USB_REQUEST` |
| `sanei_usb_read_bulk` | `ReadFile` (bulk IN) |
| `sanei_usb_write_bulk` | `WriteFile` (bulk OUT) |
| `sanei_usb_clear_halt` | `IOCTL_RESET_PIPE` |
| 장치 열거 | `\\.\UsbscanN` + `IOCTL_GET_DEVICE_DESCRIPTOR` |
| 엔드포인트 | `IOCTL_GET_PIPE_CONFIGURATION` |

장치 이름은 `usbscan:NNN` 형태이고, 전체 이름은 `genesys:usbscan:000` 이 된다.
libusb 로도 보이는 같은 하드웨어는 열거에서 뺀다 — 열 수 없는 장치를 두 번
보여줘야 할 이유가 없다.

실기에서 확인한 주의점들.

* `bmRequestType` 은 쓰이지 않는다. 드라이버는 **언제나** vendor + device
  recipient 요청을 만들고, 방향만 `fTransferDirectionIn` 으로 정한다. 스캐너
  백엔드가 쓰는 모양이 정확히 그것이라 문제가 되지 않지만, 그 밖의 요청은
  전달할 수 없으므로 `SANE_STATUS_UNSUPPORTED` 로 거절한다.
* 읽기 데이터는 `pbyData` 가 아니라 **출력 버퍼**로 온다. `pbyData` 는 출력
  버퍼와 같은 포인터여야 하고 `uLength` 는 출력 버퍼 길이와 같아야 한다.
  이것을 어기면 드라이버가 입력 구조체를 그대로 되돌려주며, 성공을 반환한다.
* `IOCTL_SET_TIMEOUT` 은 성공을 반환하고 **아무것도 하지 않는다**
  (`IOCTL_GET_TIMEOUT` 은 `ERROR_NOT_SUPPORTED`). 응답 없는 전송은 드라이버
  기본값인 2분을 그대로 쓴다. 겹침 입출력으로 열어도 소용없다 — 이 드라이버는
  `IOCTL_SEND_USB_REQUEST` 를 호출 스레드에서 동기로 끝내므로
  `DeviceIoControl` 자체가 블록하고 `ERROR_IO_PENDING` 이 나오지 않는다
  (5초를 요구한 프로브가 120,015 ms 걸렸다). 마감은 프론트엔드를 자식
  프로세스로 감시하는 플러그인 쪽에서 지킨다.
* **`IOCTL_RESET_PIPE` 를 걸면 안 된다.** `sanei_usb_clear_halt` 와
  `sanei_usb_reset` 을 아무것도 하지 않게 두는 이유가 이것이다. 아래 참조.

### 두 번째 스캔이 멈추던 것 — 파이프를 리셋했기 때문

첫 스캔은 언제나 됐고, 프로세스를 닫고 다시 연 두 번째 스캔은 언제나
`write_ahb` 의 컨트롤 OUT(`0x40 / 0x04 / 0x82 / index 1 / len 8`)에서 응답이
없었다. 벌크 쓰기 직후였다. 그때부터 스캐너는 **전원을 껐다 켜기 전까지**
어떤 요청에도 답하지 않았다.

원인은 `sane_close` 가 부르는 `clear_halt`/`reset` 이 걸던 `IOCTL_RESET_PIPE`
였다. 마이크로소프트가 문서로 남긴 실패 양식이다.

> `URB_FUNCTION_SYNC_RESET_PIPE_AND_CLEAR_STALL` 은 **호스트 쪽** 데이터
> 토글을 리셋한다. USB 규격은 장치도 자기 토글을 리셋하라고 하지만,
> **그렇게 하지 않는 비순응 장치가 있다.** 그런 장치를 다루는 드라이버는
> 호스트 토글을 건드리지 말아야 한다.

호스트만 0으로 돌아가고 장치는 그대로라 다음 세션의 벌크 쓰기가 조용히
버려지고, ASIC 은 오지 않는 데이터를 기다리며 그 다음 컨트롤 전송에
답하지 않았다.

**실측 결과** — 리셋을 빼자:

```text
별도 프로세스 연속 스캔   8/8 성공 (17~22초, 전부 3,030,277 바이트)
--batch-count=2           exit=0, 두 장 다 3,030,277 바이트
```

리셋을 걸던 때는 예외 없이 1회차만 성공하고 2회차가 120초 뒤 실패했다.

여기까지 오면서 반증한 것들도 적어 둔다. 같은 길을 다시 파지 않기 위해서다.

| 시도 | 결과 |
| --- | --- |
| 열 때 ASIC 리셋 강제 (`asic_boot` 의 `cold` 고정) | 동일 실패 |
| 닫을 때 ASIC SCANRESET (레지스터 `0x0e`) | 다음 실행이 genesys 판정으로 `cold` 가 되는 것까지 확인. 동일 실패 |
| `RESET_PIPE` 를 `ALL_PIPE` 로 | 동일 실패 |
| `CANCEL_IO` + 전 파이프 개별 리셋 | 동일 실패 |
| `CM_Query_And_Remove_SubTree` / `CM_Setup_DevNode` | `CR_ACCESS_DENIED` (관리자 필요) |
| `IOCTL_USB_HUB_CYCLE_PORT` | `ERROR_GEN_FAILURE` — 최신 Windows 에서 제거됨 |
| WinUSB 로 바인딩을 바꾸면 해결되는가 | 아니다. libusb 의 Windows 백엔드도 `WinUsb_ResetPipe` 뿐이라 장치 리셋이 없다 |

마지막 줄이 중요하다. **Zadig 로 드라이버를 바꿨어도 같은 벽에 부딪혔을
것이다.** usbscan.sys 를 고른 것이 이 문제의 원인이 아니다.

### 011 — OpticFilm 7400-v2/8100 Gray 정지와 GL845/GL846 출력 길이

2026-08-25 OpticFilm 8100, 600 DPI, 16-bit 실측에서 원본 1.4.0의 단일채널
Gray 경로는 dark/white calibration과 `begin_scan`까지 끝낸 뒤 장치 버퍼가 계속
비어 있어 `wait_until_buffer_non_empty()`에서 멎었다. 출력은 0B였다. 같은 장치와
영역의 Color는 856×590, 16-bit, RGB로 끝났으므로 Gray 미지원으로 숨기지 않고
SANE에 이미 있는 `ModelFlag::HOST_SIDE_GRAY`를 먼저 검증하기로 했다.

패치는 hunk 세 개다. 범용성이 서로 다르므로 나눠서 적는다.

| hunk | 파일 | 분기 조건 | 성격 |
|---|---|---|---|
| 1 | `backend/genesys/genesys.cpp` | `ModelFlag::HOST_SIDE_GRAY` | flag 기반. 모델명 없음 |
| 2 | `backend/genesys/tables_model.cpp` | 7400-v2 행 (8100 이 상속) | 모델 행. 증거 범위 한정 |
| 3 | `backend/genesys/gl846.cpp` | `session.use_host_side_gray` | 세션 속성. upstream 버그 수정 |

**hunk 1** 없이는 hunk 2 가 무의미하다. `compute_session()`의 host-side Gray 조건은
`color_filter == ColorFilter::NONE`인데, `genesys.cpp`는 CCD(`is_cis == false`) 스캐너에
`Red|Green|Blue`만 주고 기본값을 `Green`으로 잡는다. OpticFilm은 CCD다. 그래서 이 분기를
`HOST_SIDE_GRAY` flag 기준으로 넓혔다. 설치 번들에서 실제
`--color-filter Red|Green|Blue|None [None]`을 확인했다.

**hunk 2** 가 켜지면 SANE의 기존 파이프라인이 장치에는 RGB single-pass를 요청하고,
`ImagePipelineNodeMergeColorToGray`가 한 행짜리 임시 버퍼에서 RGB를 Gray로 합친다.
전체 RGB 영상을 추가 보관하지 않는다.

**hunk 3 에서 한 번 헛짚었다.** 첫 패치 실장 결과는 정지 없이 종료됐지만 성공은 아니었다.
`scanimage`는 1,010,080B를 예고하고 3,030,240B를 받아 “read more data than announced”를
냈으며 파일은 3,030,462B였다. 코드 대조로 GL841은 host-side Gray일 때
`total_bytes_to_read`를 3으로 나누지만 다른 command set에는 그 줄이 없는 것이 확인됐다.
그래서 처음에는 그 계산을 `gl843.cpp`에 넣었다 — **그런데 8100은 `gl843.cpp`를 한 줄도
타지 않는다.**

```
tables_model.cpp  : plustek-opticfilm-8100 → model.asic_type = AsicType::GL845
low.cpp:64        : case AsicType::GL845:   // 흘려보냄
low.cpp:65        : case AsicType::GL846: return new gl846::CommandSetGl846{};
```

게다가 현재 `HOST_SIDE_GRAY`를 켠 모델(upstream 3개 + 우리 1개)에 GL843은 하나도 없어서
gl843 쪽 수정은 **컴파일만 되고 절대 실행되지 않는 죽은 코드**였다. 빌드는 성공하고 기능만
그대로이므로 로그로는 알 수 없다. 실기 스캔의 바이트 수로만 드러났다. `gl846.cpp`로 옮긴 뒤
통과했다.

#### hunk 2 의 범위를 왜 넓히지 않는가

`tables_model.cpp`는 SANE이 모델별 하드웨어 사실을 적는 표다. upstream도 GL841 3개 행에
같은 방식으로 이 flag를 켠다. 그렇더라도 실기 증거는 **OpticFilm 8100 한 대뿐**이다.

| 모델 | ASIC | flag |
|---|---|---|
| 7200 | GL842 | 끄기 — 미검증 |
| 7200i / 7200-v2 / 7300 / 7400-v1 / 7500i / 7600i-v1 | GL843 | 끄기 — 미검증 |
| **7400-v2** | **GL845** | **켜기** — 8100이 이 행을 상속 |
| **8100** | **GL845** | **켜기** — 실기 증거 |
| 8200i / 7600i-v2 | GL845 | 끄기 — 미검증 |

host-side Gray는 3채널을 획득한다. native Gray가 멀쩡한 장치에 켜면 **느려지는 회귀**다.
어떤 행을 켜려면 그 장치의 실제 스캔 결과가 있어야 한다.

#### 실기 결과

| 항목 | 수정 전 | 수정 후 |
|---|---|---|
| Gray 16-bit 600 dpi | 무한 정지, 0B | exit 0, **16,658 / 16,781 ms** (연속 2회) |
| 예고/실제 바이트 | `3030240 / 1010080` 경고 | 경고 없음, 정확히 일치 |
| 파일 | 3,030,462B | **1,010,302B** |
| TIFF | 856×590, 16-bit, SPP 1 | 동일 |
| Color 16-bit 회귀 | 정상 | 정상 (856×590, SPP 3, exit 0) |

재빌드한 배포본으로 다시 돌린 Gray 는 **12회 중 11 성공**이다. 실패한 1회는
`sane_start: Error during device I/O`, 121,001ms, 0B 였고 121초는 Windows still-image
드라이버의 2분 `ERROR_SEM_TIMEOUT`(121)과 일치한다 — 008 이 다루는 파킹 계열이다. 실패
시점은 설치 프로그램이 DLL 을 막 교체한 직후의 첫 스캔이었고, 연속 3회와 `-L` 직후 스캔
×2 어느 쪽으로도 재현하지 못했다. Gray 전용이라는 증거는 없다. **OPEN 으로 남긴다.**

전체 001~011 패치를 clean 작업 디렉터리에서 빌드한 SANE `1.4.0-5` 패키지 SHA-256은
`f777d88d74d05318761ffab3d46a93e18844588243c56cbc54562035c39e7073`,
그것으로 만든 setup SHA-256은
`092cf0b2a615f41d9cd97435661f8d6e3619f3c8396c0cf69bb4fbb843f5b915`다. 이 setup을 실제 host
경로 `%LOCALAPPDATA%\Negaflow\Plugins\sane`에 무인 설치한 뒤 번들
`cygsane-genesys-1.dll`의 SHA-256이 빌드한 `libsane-genesys-1.dll`과 같음(`ff4803bb…`)을
확인했고, 그 설치 경로로 위 Gray 연속 2회를 다시 통과했다.

#### 왜 고친 백엔드가 한동안 로드되지 않았는가

`dll.c`는 Windows에서 백엔드를 **`cygsane-<backend>-1.dll`** 이름으로만 `dlopen` 한다.
빌드 산출물은 `libsane-<backend>-1.dll`이고 `make-payload.sh`가 복사하며 이름을 바꾼다.
그런데 `$MINGW_PREFIX/lib/sane/`에 예전에 손으로 복사해 둔 `cygsane-*`가 남아 있으면
**새로 빌드한 백엔드를 영원히 가린다.** 진단 중 MSYS2 런타임의 Gray가 무한 정지한 것이
이것이었다. `negaflow-windows/scripts/build-sane-runtime.ps1`이 설치 뒤 이 그림자를 제거한다.

#### macOS

같은 hunk 3개를 `negaflow-mac/Formula/sane-backends-negaflow.rb`의 `__END__` payload에
추가하고 version을 `1.4.0-negaflow.4`로 올렸다. 맥은 008(MUST_WAIT)을 적용하지 않으므로
`tables_model` hunk는 맥 기준 context로 따로 만들었다. formula의 8개 hunk 전체가 실제 맥
upstream tarball(`sane-backends-1.4.0.tar.gz`, sha256 `f99205c9…`)에 `patch -p1 --dry-run`
으로 오프셋 0, fuzz 0으로 적용된다. **맥 실기도 2026-08-30 통과했다** — OpticFilm 8100
Gray 본스캔이 완주했고 결과가 Color 103 MB 대비 34 MB로 정확히 1/3이다(3배면 hunk 3이
빠진 것이다). Color 16-bit 도 같은 빌드에서 정상이다.

맥 설치는 `../scripts/install-patched-sane.sh`로 한다. Homebrew 6.0.20은 tap 밖의 로컬
formula를 `Error: Homebrew requires formulae to be in a tap`으로 거부하므로
`brew install --build-from-source <formula 경로>`는 쓸 수 없다(2026-08-30 실측).

### 007 — 취소가 스캐너를 죽이던 것

스캔 도중 `scanimage` 를 끝내면 스캐너가 전원을 다시 넣기 전까지 어떤 요청에도
답하지 않는다. 다음 읽기가 `sane_read: Error during device I/O`, 그 뒤 열기가
`Invalid argument` 다. 플러그인의 워치독이 바로 그 동작을 하므로 제품 경로다.

`scanimage` 는 이미 옳은 구조를 갖고 있다 — `SIGINT`/`SIGTERM` 핸들러가
`sane_cancel` 을 부른다. Windows 에서만 그것이 성립하지 않고, 이유가 두 겹이다.

**첫째, 신호가 그 핸들러로 가지 않는다.** `GenerateConsoleCtrlEvent` 로 특정
자식만 겨냥할 수 있는 신호는 `CTRL_BREAK_EVENT` 뿐인데, MS 문서대로
"CTRL+C or CTRL+BREAK is treated as a signal (SIGINT or **SIGBREAK**)" 이다.
`SIGBREAK` 핸들러가 없으니 기본 동작이 전송 도중 프로세스를 끝낸다 —
실측 종료 코드 `0xC000013A`.

**둘째, 핸들러를 걸어도 `sane_cancel` 이 터진다.** MS 문서 — "The system
creates a new thread in each client process to handle the event." 메인
스레드가 `sane_read` 안에 있는데 다른 스레드가 `sane_cancel` 을 부르니 자료
경쟁이다. 실측: `received signal 21` / `trying to stop scanner` 를 찍고
171 ms 뒤 `0xC0000005` 접근 위반. Unix 는 핸들러가 메인 스레드를 가로채므로
이 문제가 없다.

그래서 Windows 에서는 핸들러가 플래그만 세우고 읽기 루프가 자기 스레드에서
취소한다. 백엔드를 한 스레드만 만지게 되고, 그 뒤 `sane_read` 가
`SANE_STATUS_CANCELLED` 를 돌려주므로 기존 종료 경로가 그대로 탄다.

**실측 결과** — 판정 기준은 "취소 뒤 다음 스캔이 되는가" 하나다.

```text
1) 기준선 스캔        21초  3,030,277 바이트  OK
2) CTRL_BREAK        received signal 21
                     trying to stop scanner
                     sane_read: Operation was canceled
                     종료 코드 2, 6,890 ms
3) 취소 뒤 스캔       17초  3,030,277 바이트  OK
```

그 6,890 ms 가 어댑터의 유예 시간도 정한다. 신호를 받은 뒤 진행 중인
`sane_read` 가 끝나기를 기다리고 `sane_cancel` 이 헤드를 홈으로 돌리는 시간이
그 안에 있다. `kCancelGracePeriod` 를 2,000 ms 에서 15,000 ms 로 올렸다 —
그 전에 강제 종료로 넘어가면 애써 고친 것이 도로 무의미해진다.

### 008 — 스캔 헤드를 세우지 않고 프로세스를 끝내던 것

OpticFilm 모델표에 `ModelFlag::MUST_WAIT` 이 없다. 그래서 genesys 가

```c
move_back_home(dev, /*wait_until_home=*/false);
dev->parking = true;
```

로 **파킹 명령만 내고 반환하고**, 헤드가 아직 움직이는 중에 `scanimage` 가
끝난다. 움직이는 OpticFilm 은 제어 전송에 답하지 않는다.

Linux 나 macOS 에서는 재시도 한 번으로 끝날 일이지만, Windows 의 still-image
클래스 드라이버는 **자기 2분 타임아웃을 다 쓴 뒤** `ERROR_SEM_TIMEOUT`(121)로
실패한다(`IOCTL_SET_TIMEOUT` 이 듣지 않는 것은 005 참조). 그러면

```text
usbscan_control_msg: request 0x04 failed, error 121
  → update_home_sensor_gpio → scanner_move_back_home → sanei_genesys_asic_init
  → open of device genesys:usbscan:000 failed: Error during device I/O
```

로 **다음 스캔의 열기가 죽거나**, `sane_read` 가 EOF 시점에 파킹하다 죽어
**데이터를 다 받은 스캔이 버려진다**.

실측(OpticFilm 8100, 600/1200/2400/3600/7200 dpi 를 이어서):

```text
간격 0초, 3사이클     3회 중 2회 실패 (실패 시각이 시작 +120.0초)
간격 8초, 3사이클     15/15 성공
같은 해상도 8회 연속   8/8 성공 — 해상도가 안 바뀌면 잘 안 난다
```

8초가 헤드가 집에 돌아가는 시간이다.

플래그를 켜면 `sane_read` 는 EOF 에서 파킹하지 않고, `sane_cancel` 이
`wait_until_home` 으로 파킹한다(홈 센서를 100 ms 씩 300회, 30초 상한).
완료된 스캔을 파킹 실패로 잃는 경로 자체가 사라진다.

1.4.0 의 어느 모델도 이 플래그를 켜지 않는다 — upstream 이 돌린 적 없는
경로다. 그래서 켜기 전에 세 호출 지점을 모두 읽었고 전부 짧고 상한이 있다.

**고친 뒤**: 간격 0초로 15/15 성공. 느려지지 않았다(7200 dpi 57.5 → 58.5초).

OpticFilm 6개 항목에만 켰다. 8100 으로만 확인했고 나머지는 같은 계열이라는
이유로 함께 켰다.

### 012 — 1.4.0 이후 upstream 이 받은 OpticFilm 작업

1.4.0 은 아직 최신 릴리스다. 그 뒤 upstream master 가 검토하고 합친 OpticFilm 커밋을 **고치지
않고** 옮긴다. 1.4.0 에 001~011 을 적용한 트리 위에 아래 순서로 cherry-pick 했고 충돌은
없었다. upstream 의 newsfragments 는 뺐다.

| 커밋 | 내용 |
|---|---|
| `eddc62c1` | OpticFilm 7400 v1 |
| `ca7b306b` | `<iterator>` include 누락(LLVM 22 libc++ 에서 컴파일 실패) |
| `f561b049` | 벡터로 만드는 문자열 옵션 크기에 NUL 1바이트 포함 |
| `2bf54be6` `a4444f83` `3fd47933` `068e509e` | GL128 이 쓰는 영상 파이프라인 노드와 정확한 slope 테이블 |
| `19f59f5f` `288d813a` `8534b728` `f753d218` | GL128 command set 과 OpticFilm 8200i SE (`07b3:1825`) |
| `90a16470` `908b0cb7` | OpticFilm 7600i v1 전체 프레임과 기본 노출 |
| `be064801` | 되돌린 `--scan-exposure-time` MR 이 GL128 에 남긴 두 줄 제거 |

`--scan-exposure-time` MR(`87969366`)은 upstream 이 되돌렸으므로 가져오지 않는다.

#### 장치에 닿는 것 — 세션 비교

upstream 자신의 `genesys_session_config_tests` 로 OpticFilm 구성 148개(컬러·Gray·적외선, 모델별
전 해상도)를 012 전후에서 돌려 레지스터 기록을 비교했다. 012 가 더한 디버그 출력 필드
(`table size`, `lamp_*_pending`)는 빼고 본 결과다.

| 모델 | 결과 |
|---|---|
| 7200, 7400 v2, **8100**, 8200i, 7600i v2 | 바이트 단위로 같다 |
| 7200i, 7200 v2, 7300, 7500i (GL843) | 레지스터 하나, 단일채널 패스(Gray 와 단일채널 캘리브레이션)의 `REG_0x04` 만 `0x1a→0x2a`, `0x5a→0x6a` |
| 7600i v1 | upstream 의 36.6 x 24.7 mm 전체 프레임과 기본 line period |
| 7400 v1 | upstream 의 새 정의 |
| 8200i SE | 새 모델 |

`REG_0x04` 변화는 `eddc62c1` 이 단일채널 패스에도 Analog Devices 의 “slow color pixel by
pixel” AFE 모드를 쓰게 한 것이다. 1.4.0 은 거기에 Wolfson 값을 썼다. GL843 OpticFilm 은 전부
AD9826 프론트엔드이고, 컬러 패스는 원래 AD 값을 쓰고 있었다. Wolfson 프론트엔드를 쓰는 GL843
(Canon 4400F/8400F/8600F, HP G4010/G4050, Panasonic KV-SS080)은 전후 모두 같은 바이트를 쓴다.
GL843 OpticFilm 의 Gray 는 이 프로젝트가 실기로 본 적이 없으므로, 이 변화의 실기 근거는 upstream
의 7400 v1 뿐이다.

#### 8200i SE

본체에는 “8200i” 라고 적혀 있고 USB ID 만 다르다(`07b3:1825`, GL128). upstream 상태는
`:basic` — 투과 전용, 150~7200 dpi, 16-bit 컬러와 Gray, 적외선 없음 — 이고 모델에
`ModelFlag::UNTESTED` 가 붙어 경고만 출력한다. 값은 vendor 드라이버의 USB 캡처를 pyopticfilm
이 해독한 것에서 왔다. 이 프로젝트는 실기로 돌려 본 적이 없다.

`MUST_WAIT` 은 켜지 않는다. GL128 은 독립적인 홈 탐색이 없고 이미지 패스 끝에서 `AGOHOME` 으로
파킹을 기다린 뒤 끝나므로, 008 이 막으려던 “헤드가 움직이는 채로 프로세스가 끝나는” 경로가
없다(`gl128.cpp` 의 `end_scan` / `move_back_home`).

#### 넣지 않은 GL128 기종

pyopticfilm 이 실기로 구동하는 같은 계열 둘은 SANE 에 행이 없고, 여기서도 만들지 않는다.

| 기종 | USB ID | 8200i SE 와 다른 점(pyopticfilm) |
|---|---|---|
| OpticFilm 8100 V2 | `07b3:1824` | 부트 레지스터 `0x0B`(0x8C ↔ 0x4C), 부트 ASIC 클록(0x0E ↔ 0x0C), 적외선 없음 |
| OpticFilm 8300i SE / Ai | `07b3:181f` | 노출 15000, 센서 타이밍, 픽셀 클록, 모터 slope ROM, 라인 수 단위 |

8200i SE 행에 ID 만 바꿔 붙이면 부트 클록과 모터 테이블을 짐작으로 쓰게 된다. pyopticfilm 은
8100 V2 에서 레지스터 비트 하나를 켠 직후 모터가 걸려 전원을 내린 사고를 기록해 두었다.
실기 없이 켤 수 있는 것이 아니다.

#### 확인

- 고정한 upstream 아카이브(`813ef881…`)에 001~014 를 PKGBUILD 순서대로 `patch -p1` — 012~014
  는 offset·fuzz 0
- `autoreconf` → `genesys epson2 epsonds coolscan2 coolscan3 test` 빌드(Linux, 2026-11-03)
- `genesys_unit_tests` 1043/1043 통과(GL128 지오메트리 시험 포함)
- 위 세션 비교

실기 확인은 아니다. 8100 의 레지스터 기록이 바이트 단위로 같다는 것이 지금 가진 가장 강한
회귀 근거다.

#### macOS

같은 커밋을 formula 의 `__END__` payload 에 더하고 version 을 `1.4.0-negaflow.5` 로 올렸다.
맥은 008 과 013 을 적용하지 않는다. formula 는 `autoreconf` 없이 릴리스 tarball 의 생성된
`backend/Makefile.in` 으로 빌드하므로, 그 파일에 gl124 항목을 본떠 gl128 항목 8곳을 손으로
넣었다. 이 파일은 automake 1.16.3 생성물이라 다른 버전으로 다시 만들면 전체가 바뀐다.
payload 는 `Makefile.am` 다음에 `Makefile.in` 을 쓰므로 make 가 automake 를 다시 부르지 않는다. 테스트
소스는 `make install` 이 빌드하지 않으므로 맥 payload 에서는 뺐다.

릴리스 tarball(`f99205c9…`)에 payload 전체를 `patch -g 0 -f -p1` 로 한 번에 적용 — offset·fuzz
0 — 하고 `./configure && make` 가 automake 를 부르지 않고 `gl128` 까지 빌드되는 것을 확인했다
(Linux, 2026-11-03). macOS 의 BSD `patch(1)` 와 Homebrew 실빌드는 아직 돌려 보지 않았다.

### 013 — 7400 v1 의 `MUST_WAIT`

1.4.0 의 7400 v1 행은 7300 행을 복사한 것이라 008 의 `MUST_WAIT` 을 7300 의 flag 로 물려받았다.
012 의 `eddc62c1` 은 7400 v1 에 새 flag 집합을 쓰므로 그대로 두면 7400 v1 만 Windows 에서 헤드가
돌아가는 중에 `sane_read` 가 끝나는 OpticFilm 이 된다. 008 이 설명한 비용이 그대로 돌아온다.

### 014 — Coolscan 깊이 목록

`coolscan2`/`coolscan3` 의 `--depth` 제약은 개수 다음에 8 과 최대 비트 깊이가 오는 word list,
즉 세 word 인데 1.4.0 은 두 word 를 할당하고 세 번째를 그 끝 너머에 쓴다. upstream `9bea1ee2`
의 coolscan 두 hunk 그대로다. 맥 formula 에는 1.0.3 부터 있었고 Windows 런타임만 이것 없이
`coolscan2`/`coolscan3` 를 빌드하고 있었다.

### 015 — GL128 이 libc++ 에서 컴파일되지 않던 것

012 의 upstream `gl128.cpp` 에서 `CommandSetGl128::asic_boot` 의 `static constexpr`
`std::pair` 배열 한 줄이 Apple clang 에서 멈췄다.

```text
genesys/gl128.cpp:1580: error: constexpr variable 'STARTUP_REGS' must be initialized
by a constant expression — non-constexpr constructor 'pair<int, int, 0>'
```

libc++ 는 이 `pair` 생성자를 C++14 부터 constexpr 로 두는데 SANE 의 configure 는 C++ 를
`-std=c++11` 로 빌드한다. GCC 의 libstdc++ 는 받아 주므로 리눅스와 UCRT64 빌드에서는 드러나지
않았고, 맥 CI 의 `install-patched-sane.sh` 에서 처음 실패했다. MSYS2 의 clang64·clangarm64 도
libc++ 라 같은 자리에서 멈춘다.

`static const` 로 바꿨다. 레지스터 세 개를 같은 값, 같은 순서로 쓴다. upstream 원본을 담은
012 는 그대로 두고 별도 패치로 얹는다. 맥 formula 는 같은 hunk 를 payload 끝에 따로 붙였다.

확인(Linux, 2026-11-03):

- 릴리스 tarball 에 formula payload 전체를 `patch -g 0 -f -p1` — offset·fuzz 0 — 하고 clang 18
  + libc++ 로 `./configure && make install` 통과. genesys 백엔드를 `make -k` 로 끝까지 돌려도 이
  한 줄 말고 오류가 없었다
- 아카이브에 001~015 를 적용해 GCC 와 clang + libc++ 각각으로 빌드, `genesys_unit_tests`
  1043/1043 통과

### macOS 전용 — `epson2` 의 Epson 인터프리터

formula 의 `__END__` payload 끝에 붙은 패치이고 version 은 `1.4.0-negaflow.6` 이다. Windows 의
패치 목록(001~015)에는 없다. 코드가 `dlfcn.h` 를 쓰므로 `#ifdef __APPLE__` 안에 두었고, 그 밖에서는
아무것도 하지 않는 대체 함수만 남는다.

Perfection V500 Photo(GT-X770, `04b8:0130`)는 버스 위에서 ESC/I 를 쓰지 않는다. Epson 의 macOS
ICA 드라이버에 든 `Interpreter 7C` 번들이 ESC/I 를 에뮬레이트하며 스캐너 고유의 프로토콜로 바꾼다.
번들은 USB 를 직접 열지 않고, 호스트가 넘긴 콜백 두 개(벌크 읽기와 쓰기)로 전송한다. 패치는
`epson2` 의 USB 경로를 `INTInit` / `INTWrite` / `INTRead` 로 돌린다.

| 항목 | 내용 |
| --- | --- |
| 라이브러리 | `/Library/Image Capture/Devices/EPSON Scanner.app/Contents/PlugIns/Interpreter 7C.bundle`. 환경 변수 `EPSON2_INTERPRETER` 로 경로를 바꾼다. Epson 의 파일이므로 저장소와 설치본에 넣지 않는다 |
| 콜백 | `unsigned char cb(void *buf, unsigned size, void *refcon, void *aux)`. 반환값은 하위 1바이트만 본다. 길이를 돌려주면 256 의 배수에서 실패로 읽힌다 |
| 읽기 | `INTRead` 가 요청한 크기 뒤로 쓸 수 있어 여유를 둔 버퍼로 읽는다 |
| 식별 | USB `04b8:0130` 하나. `epson2_usb.c` 의 제품 ID 목록에 더한다 |
| 적외선 | `FS W` 블록의 옵션 컨트롤 3, 감마 3, 색 보정 0. 800, 1600, 3200 dpi 만 받으므로 그 모드에서 해상도 목록을 세 값으로 줄인다. 3200 dpi 에서는 줄 방향이 2400 dpi 라 픽셀이 정사각형이 아니다(`FS W` 의 sub 해상도 2400). `ESC #` 해제 열을 보내지 않는다 |
| 투과 영역 | 인터프리터가 1/3200 인치 단위로 보고한다(68.58 x 236.98 mm) |
| 깊이 | 스캐너는 최대 8 비트로 보고하지만 16 비트를 받으므로 12·14·16 비트 탐색을 켠다 |

확인: 실기(Perfection V500 Photo, macOS 27, Apple Silicon)에서 평판, 투과, 16비트, 800, 1600, 3200 dpi
적외선 스캔을 했다. 800 dpi 한 프레임의 RGB 와 IR 은 1 픽셀 안에서 겹친다. 호출 규약은 번들의
디스어셈블리로 읽었고, 적외선 `FS W` 값은 VueScan 의 호출 기록과 같다. 다른 모델은 확인하지 않았다.

## 다시 만드는 법

Windows 는 스크립트를 쓴다. 손으로 복사하지 말 것 — 아래 §"손으로 하면 틀리는 것" 참고.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File negaflow-windows\scripts\build-sane-runtime.ps1 -Clean
```

이 스크립트가 하는 일:

1. PKGBUILD 의 `source=()` 와 `prepare()` 를 `patches/` 와 대조한다. 어느 쪽이든 빠지거나
   남으면 빌드 전에 멈춘다.
2. CRLF 로 오염된 패치·PKGBUILD 를 거부한다.
3. 저장소 밖 작업 디렉터리에 staging 하고 `MSYSTEM=UCRT64 makepkg-mingw -sf --nocheck` 를 돈다.
4. `pacman -U` 로 설치한 뒤 `$MINGW_PREFIX/lib/sane` 의 낡은 `cygsane-*` 그림자를 지운다.

수동 절차가 꼭 필요하면 다음과 같다. **`patches/` 에서 복사해야 한다.**

```bash
cp sane-runtime/PKGBUILD sane-runtime/patches/*.patch <작업 디렉터리>/
cd <작업 디렉터리>
MSYSTEM=UCRT64 makepkg-mingw -sf --nocheck
```

### 손으로 하면 틀리는 것 — 실제로 세 번 틀렸다

1. **`sane-runtime/` 최상위의 낡은 패치 복사본.** makepkg 작업 흔적으로 남아 있던 001~010
   사본에는 011 이 없었다. `cp sane-runtime/*.patch` 로 잘못 옮기면 빌드는 성공하고 Gray
   수정만 조용히 빠진다.
2. **CRLF 오염.** 저장소 루트 `.gitattributes` 가 `sane-runtime/patches/*.patch` 로 적혀
   있었는데, `/` 가 든 패턴은 그 파일이 있는 디렉터리에 고정되므로 실제 경로
   `negaflow-mac/sane-runtime/...` 와 한 번도 일치하지 않았다. 001~009 가 CRLF 가 됐고
   `patch(1)` 이 적용하지 못한다. 전체 경로로 고쳤다.
3. **오염된 해시로 덮기.** 그 CRLF 를 고치는 대신 PKGBUILD 의 고정 sha256 을 CRLF 파일의
   해시로 바꿔 놓은 적이 있다. 고정 해시는 **커밋된 LF 파일 기준**이어야 한다
   (`001` → `c7d84a80d4f91000024562500b95de165b8200bae66f48d807e9f07e7e8f4bb2`).
