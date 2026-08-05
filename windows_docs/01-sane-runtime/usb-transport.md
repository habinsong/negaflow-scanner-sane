# USB 전송 계층

기준일: 2026-08-04
상태: 조사 완료, 실기 검증 전
목적: Windows에서 SANE가 스캐너에 닿는 경로와 그 대가를 정확히 적는다

관련 문서:

- [availability](availability.md)
- [runtime-route-decision](runtime-route-decision.md)
- [driver-conflicts](../09-hardware/driver-conflicts.md)
- [device-identity](../02-frontend-contract/device-identity.md)

## 1. 계층

```text
scanimage.exe
  libsane-1.dll
    libsane-genesys-1.dll 등 백엔드
      sanei_usb
        libusb-1.0.dll
          ┌─ WinUSB.sys      (권장)
          ├─ libusbK.sys
          ├─ libusb0.sys
          └─ usbdk           (권장하지 않음)
            USB 스택 → 스캐너
```

macOS에서는 libusb가 IOKit을 통해 커널 드라이버 없이 장치를 열 수 있다.
**Windows에서는 그렇지 않다.** 장치에 바인딩된 커널 드라이버가 libusb가
지원하는 것 중 하나여야 한다.

## 2. libusb의 Windows 요건

**확인** — <https://github.com/libusb/libusb/wiki/Windows> 원문:

> If your target device is not HID, and your device is not using WinUSB
> driver, **you must install a driver before you can communicate with it
> using libusb.**

지원 드라이버:

| 드라이버 | 상태 |
|---|---|
| WinUSB (`winusb.sys`) | **권장** |
| libusbK (`libusbk.sys`) | WinUSB 한계에 부딪혔을 때만 |
| libusb-win32 (`libusb0.sys`) | WinUSB/libusb0 한계에 부딪혔을 때만. libusbK DLL도 함께 설치해야 함 |
| HID 드라이버 | HID 장치 전용 |
| usbdk | **권장하지 않음.** wiki 원문: "use of usbdk is also discouraged as it seems to have some stability issue" |

스캐너는 HID가 아니다. 따라서 **드라이버 설치가 필수**다.

### 2.1 WinUSB의 제약 (전부 wiki 확인)

| 제약 | 이 프로젝트에 대한 의미 |
|---|---|
| **동시 사용 불가** — "WinUSB does not support multiple concurrent applications" | 두 프로세스가 같은 스캐너를 동시에 열 수 없다. 플러그인이 스캔 중이면 다른 어떤 프로그램도 못 연다 |
| 실제 리셋 명령 전송 불가 | SANE 백엔드가 장치 리셋에 의존하면 실패한다. 오류 복구 경로에 영향 |
| 첫 번째와 다른 configuration 설정 불가 | 다중 configuration 스캐너에서 문제 가능(대상 장치들은 해당 없을 것으로 추정, 미확인) |

**동시 사용 불가**는 이 플러그인 설계에 이미 부합한다. 백엔드 인스턴스당
scan 세션 하나만 허용하고 있기 때문이다
([child-process](../03-process-and-io/child-process.md) §8). 다만 오류
메시지 문구를 조정해야 한다 — "다른 프로그램이 스캐너를 쓰고 있습니다"가
Windows에서 더 자주, 더 정확한 진단이 된다.

## 3. Zadig

**확인** — <https://zadig.akeo.ie/>

| 항목 | 값 |
|---|---|
| 버전 | **2.9** (2024-06-13) |
| 라이선스 | **GPLv3** |
| 요구 OS | Windows 7 이상 |
| 형태 | 단독 실행 파일 |
| 기반 | libwdi (LGPLv3) |
| 내장 드라이버 | WinUSB v6.1.7600.16385, libusb-win32 v1.4.0.0, libusbK v3.1.0.0, USBSer |

Zadig는 장치 노드에 바인딩된 드라이버를 **교체한다.**

## 4. 드라이버 교체의 대가 — 제품 결정 수준의 문제

스캐너의 벤더 드라이버를 WinUSB로 바꾸면:

| 잃는 것 | 이유 |
|---|---|
| Epson Scan 2 | 벤더 커널 드라이버에 말을 걸지만 그 드라이버가 더 이상 바인딩돼 있지 않다 |
| SilverFast (벤더 드라이버 사용 시) | 위와 같음 |
| Plustek QuickScan | 위와 같음 |
| Windows 팩스 및 스캔 (WIA) | WIA 드라이버가 벤더 드라이버 위에 있다 |
| 벤더 TWAIN 데이터 소스 | 위와 같음 |

되돌릴 수 있다. 장치 관리자 → 드라이버 업데이트 → 롤백 또는 벤더 패키지
재설치. 그러나 **관리자 권한이 필요한, 장치별, 수동, 중단을 동반하는
작업**이며, 되돌리기 전까지 사용자의 기존 스캔 소프트웨어가 동작하지 않는다.

WinUSB가 동시 사용을 지원하지 않으므로 **공존 우회책도 없다.**

### 4.1 스캐너별 손익

| 스캐너 | WinUSB 바인딩 후 잃는 것 | 순평가 |
|---|---|---|
| **Nikon Coolscan** | 사실상 없음. Nikon Scan은 Vista 이후 동작하지 않는다 | **명백한 이득** |
| **Reflecta / PIE** | CyberView X5. 단 MSYS2에 `pieusb`가 없어 애초에 지원 불가 | 재빌드 전에는 무의미 |
| **Plustek OpticFilm** | QuickScan, SilverFast SE | 손실 있음. SilverFast를 산 사용자에게는 큰 손실 |
| **Epson Perfection V800/V850** | Epson Scan 2 (Digital ICE 포함 레거시 유틸리티까지) | **순손실.** 벤더 경로가 멀쩡하다 |

**VueScan은 예외일 수 있다.** Hamrick 문서는 VueScan의 내장 드라이버가
설치된 벤더 드라이버와 "충돌하지 않으며", 벤더 드라이버가 없으면 자체
드라이버를 설치한다고 적는다. 즉 VueScan은 Zadig 처리를 요구하지 않는다.
WinUSB 바인딩 **후에도** VueScan이 동작하는지는 **미확인**이며,
동작한다면 Coolscan 사용자의 손실이 실질적으로 0이 된다 → spike U-1.

### 4.2 제품 문구 요건

설치 전에 다음을 표시한다. 설치 후가 아니다.

```text
이 플러그인은 스캐너의 USB 드라이버를 WinUSB로 바꿉니다.

바꾸면:
  • 제조사 스캔 소프트웨어(Epson Scan 2, QuickScan 등)가
    이 스캐너를 사용할 수 없습니다.
  • Windows 팩스 및 스캔에서도 사라집니다.
  • 한 번에 하나의 프로그램만 이 스캐너를 열 수 있습니다.

되돌리기:
  장치 관리자 → 이미징 장치 → 이 스캐너 → 드라이버 업데이트
  → 제조사 드라이버 선택 (또는 제조사 패키지 재설치)

<스캐너 모델>은(는) 현재 Windows용 제조사 드라이버가 있습니다.
계속하기 전에 무엇을 잃는지 확인하십시오.
```

마지막 문단은 감지된 스캐너에 따라 조건부로 표시한다.

## 5. usbipd-win / WSL2 경로

**확인** — usbipd-win v5.3.0 (2025-10-11).

```text
usbipd list
usbipd bind --busid 4-4          # 관리자, 재부팅 유지됨
usbipd attach --wsl --busid 4-4  # 비관리자, 유지되지 않음
```

구 `usbipd wsl attach`는 **제거됐다.**

### 5.1 이 경로가 WinUSB 문제를 없애지 않는다

`usbipd bind`도 결국 장치를 Windows 쪽 드라이버에서 떼어낸다. 벤더
소프트웨어는 attach 중에 그 스캐너를 쓸 수 없다.

**차이는 되돌리기 비용이다.** `usbipd detach` 한 번이면 장치가 Windows로
돌아온다. 드라이버 롤백이 필요 없다. 이 점에서 WSL2 경로가
"영구 변경"이 아니라 "일시 대여"에 가깝다.

### 5.2 커널

**확인** — `linux-msft-wsl-6.6.y`의 `config-wsl`:

```text
CONFIG_USBIP_CORE=m
CONFIG_USBIP_VHCI_HCD=m
CONFIG_USBIP_VHCI_HC_PORTS=8
CONFIG_USB=m
CONFIG_USB_STORAGE=m
CONFIG_USB_XHCI_HCD=m
```

`vhci-hcd`와 USB core가 모듈로 배포된다. 커널 재빌드가 필요 없다.
Microsoft 문서도 재빌드를 "Store WSL로 업데이트할 수 없을 때"의 대체
경로로만 언급한다.

### 5.3 알려진 문제

1. **udev 권한.** Microsoft 문서: 애플리케이션에 따라 비루트 접근을 위해
   udev 규칙 설정이 필요할 수 있다. `sane-usb(5)`는 `/dev/bus/usb` 권한을
   조정하지 않으면 root만 스캔할 수 있다고 명시한다.
2. **WSL에서 udev reload가 실패한다.** `udevadm control --reload-rules`가
   "Failed to send reload request: No such file or directory"를 낸다.
   우회: `wsl --terminate <distro>` 또는 `sudo service udev restart`,
   때때로 `sudo udevadm trigger` 추가. (WSL issue #8502)
3. **재부팅·WSL 재시작·장치 리셋·재연결마다 attach 필요.** VM을 살려두려면
   WSL 프롬프트가 열려 있어야 한다.
4. **usbipd-win issue #180**: Canon CanoScan LiDE 50이 `scanimage -L`에
   genesys/libusb 장치로 잡히지만 **스캔 완료 후 연결이 끊긴다.**
   genesys는 이 프로젝트의 주요 백엔드다. → spike U-2 최우선
5. isochronous 전송 문제(issue #530). 스캐너는 bulk/control을 쓰므로
   실제로는 잘 걸리지 않는다.
6. WSL2 전용. x64/ARM64만.

### 5.4 usbipd + libusb 관계

usbipd가 `bind`할 때 장치에 `VBoxUSB`가 아닌 usbipd 자체 필터를 붙이는지,
WinUSB로 바꾸는지는 버전에 따라 다르다(현재 구현 미확인). 실무적으로는
`usbipd bind`가 필요한 처리를 알아서 한다. **사용자가 Zadig를 따로 쓸
필요는 없다** — 이것이 WSL2 경로의 실질적 이점이다.

## 6. 장치 주소와 재연결

macOS 실측: 장치를 열 때마다 libusb 주소가 바뀐다
([device-identity](../02-frontend-contract/device-identity.md) §1).

Windows에서 확인할 것:

| 질문 | spike |
|---|---|
| libusb Windows 백엔드의 bus/device 번호가 open/close로 바뀌는가 | U-3 |
| WinUSB 핸들을 닫고 다시 여는 사이 번호가 유지되는가 | U-3 |
| usbip 재부착 시 번호가 어떻게 바뀌는가 | U-3 |
| SANE 장치명 문자열 형식이 `<backend>:libusb:<bus>:<dev>`인가 | U-4 |

U-4가 특히 중요하다. 코드 세 곳이 `:libusb:` 부분 문자열에 의존한다.

```text
isVolatileUSBSelector(v)              = v.contains(":libusb:")
connectionType(deviceString)          = ":libusb:" 또는 ":usb:" → .usb
currentDeviceAddress 안정 선택자 조건  = chosen.devname.contains(":libusb:")
```

형식이 다르면 세 곳을 전부 고쳐야 하고, 고치지 않으면:

- 죽은 주소를 재사용해 패스마다 헛된 open이 붙는다
- `connectionType`이 `internalBus`로 잘못 보고된다
- 안정 선택자 최적화가 동작하지 않는다

**주소가 안정적이더라도 재연결 로직을 제거하지 않는다.** 비용은 목록 조회
한 번이고, 제거했다가 특정 컨트롤러에서 실패하면 재현하기 어려운 버그가 된다.

## 7. 대상 스캐너 USB 식별자

바인딩 도구가 대상을 좁히려면 VID/PID가 필요하다. README에서 확인된 것:

| 장치 | VID:PID | 백엔드 |
|---|---|---|
| Plustek OpticFilm 8100 | `07b3:130c` | genesys |
| Plustek OpticFilm 8100 (다른 변종) | `07b3:1824` | **없음** — 지원 불가 |
| Plustek OpticFilm 8200i | `07b3:130d` | genesys |
| Plustek OpticFilm 8200i (GL128) | `07b3:1825` | **없음** — 지원 불가 |
| Reflecta/PIE 일부 | `05e3:0145` | pieusb (모델 번호도 일치해야 함) |

나머지 대상(Epson, Nikon, 기타 Plustek)의 VID/PID는 이 저장소에 기록돼 있지
않다. 바인딩 도구를 내장하려면 SANE의 `.desc` 파일과 백엔드 소스에서
전체 목록을 추출해야 한다.

**절대 하지 말 것**: VID만 보고 바인딩하는 것. `07b3:1824`처럼 같은 VID에
지원 불가 변종이 있고, 그것을 WinUSB로 바꾸면 사용자는 벤더 소프트웨어를
잃고 아무것도 얻지 못한다.

## 8. Spike 명세

### U-1 — VueScan 공존

```text
1. Nikon Coolscan 또는 Plustek에 VueScan 설치, 동작 확인
2. Zadig로 WinUSB 바인딩
3. VueScan이 여전히 스캐너를 인식하는가
4. 인식한다면 플러그인과 동시에 열 수 있는가 (WinUSB 동시성 제약 확인)
```

결과가 "VueScan 동작함"이면 Coolscan/Plustek 사용자에 대한 설치 경고를
크게 완화할 수 있다.

### U-2 — genesys + usbipd 스캔 후 연결 끊김

usbipd-win #180의 재현. genesys 장치로:

```text
1. usbipd bind/attach
2. 전체 스캔 1회
3. 스캔 직후 scanimage -L 이 장치를 여전히 나열하는가
4. 끊겼다면 detach/attach 없이 복구되는가
5. 연속 5회 반복 (다중 노출 시나리오)
```

실패하면 WSL2 경로는 다중 노출·IR 다중 패스에서 사용할 수 없다.

### U-3 — 주소 변동 계측

```text
반복 20회:
  scanimage -f "%d\t%v\t%m\t%t%n"   → 장치명 기록
  scanimage -A -d <장치명>           → open 발생
  scanimage -f …                     → 장치명 다시 기록
장치명이 바뀌는 비율과 패턴을 기록
```

macOS와 같은 표를 만들어 비교한다.

### U-4 — 장치명 형식

S-1의 부산물이지만 별도로 기록한다. 다음을 수집:

- USB 장치: 전체 문자열
- (가능하면) 네트워크 장치: `net:` 접두사 형태
- 여러 대 연결 시 각각의 형태

### U-5 — 동시 열기 실패 형태

```text
1. 프로세스 A가 scanimage로 장치를 연 채 유지
2. 프로세스 B가 같은 장치에 -A 시도
3. B의 stderr 문구와 exit code 기록
```

이 문구가 `runScanimage`의 `busy` 분류에 걸리는지 확인한다.
걸리지 않으면 Windows 전용 문자열을 매핑 표에 추가한다
([scanimage-invocation](../02-frontend-contract/scanimage-invocation.md) §7).

## 9. 열린 질문

- WinUSB 바인딩 후 VueScan/SilverFast가 동작하는가 (U-1)
- Windows on ARM에서 WinUSB 드라이버 설치가 가능한가
- usbipd `bind`가 정확히 무엇을 하는지(필터 드라이버 vs WinUSB 교체)
- 대상 스캐너 전체의 VID/PID 목록을 어디서 추출할 것인가
- `--disable-locking` 빌드 + WinUSB 동시성 제약의 조합에서 실패 형태가
  깨끗한가(오류 반환), 아니면 하드웨어 상태를 남기는가
