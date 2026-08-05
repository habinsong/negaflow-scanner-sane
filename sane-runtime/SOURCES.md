# SANE runtime — sources and patches

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
| 라이선스 | GPL-2.0-or-later (SANE 예외 조항 포함) |

빌드 레시피는 [`PKGBUILD`](PKGBUILD) 이며 MSYS2 의
`mingw-w64-sane` 를 기반으로 한다. 빌드 대상 백엔드는
`genesys epson2 epsonds coolscan2 coolscan3 test` 이다.

## 패치

| 파일 | 출처 | 무엇을 고치나 |
| --- | --- | --- |
| `001-fix-build-on-mingw.patch` | MSYS2 (GPL-2.0-or-later) | MSYS2 원본 그대로. mingw 에서 컴파일되게 한다 |
| `002-binary-output-mode.patch` | 이 저장소 | `scanimage` 가 stdout 을 텍스트 모드로 열어 이미지의 `0x0A` 를 `0x0D 0x0A` 로 바꿔 내보내던 것을 막는다 |
| `003-test-backend-on-mingw.patch` | 이 저장소 | `test` 백엔드가 mingw 에서 빌드되게 한다. 하드웨어 없는 회귀 시험에 필요하다 |
| `004-usbdk-on-windows.patch` | 이 저장소 | `SANE_USB_USE_USBDK` 가 설정됐을 때만 libusb 의 UsbDk 백엔드를 쓴다. **기본값은 끈 채로 둔다** |
| `005-usbscan-backend.patch` | 이 저장소 | `sanei_usb` 에 `usbscan.sys` 백엔드를 더한다. 아래 참조 |
| `006-debug-output-on-mingw.patch` | 이 저장소 | `SANE_DEBUG_*` 를 켜면 프론트엔드가 segfault 하던 것을 고친다 |

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

이 패치는 upstream 에 제출할 가치가 있다. 제출 전까지는 여기서 유지한다.

## 다시 만드는 법

```bash
cp sane-runtime/PKGBUILD sane-runtime/patches/*.patch <작업 디렉터리>/
cd <작업 디렉터리>
MSYSTEM=UCRT64 makepkg-mingw -sf --nocheck
```
