# 드라이버 충돌

기준일: 2026-08-04
상태: 조사 완료, 실기 검증 전
목적: Windows에서 스캐너 하나를 두고 경쟁하는 소프트웨어 관계를 정리한다

관련 문서:

- [usb-transport](../01-sane-runtime/usb-transport.md)
- [runtime-route-decision](../01-sane-runtime/runtime-route-decision.md)
- [validation-matrix](validation-matrix.md)
- [diagnostics-and-troubleshooting](../08-operations/diagnostics-and-troubleshooting.md)

## 1. macOS에는 없는 문제

README가 명시한다.

> macOS에는 켜야 할 앱별 USB 권한이 없다. negaflow도 이 플러그인도
> App Sandbox를 쓰지 않으므로 스캐너 접근을 막는 **개인정보 보호 및 보안**
> 설정이 없다.

macOS에서 libusb는 커널 드라이버 없이 USB 인터페이스를 claim한다.
Image Capture나 벤더 소프트웨어가 이미 claim하고 있으면 실패하지만,
**드라이버를 교체할 필요가 없다.** 프로그램을 종료하면 해결된다.

**Windows는 다르다.** 커널 드라이버가 장치에 바인딩돼 있고, 어느 드라이버가
바인딩됐는지가 어떤 소프트웨어가 그 장치를 쓸 수 있는지를 결정한다.

## 2. 바인딩 상태별 가능한 것

| 바인딩된 드라이버 | SANE/libusb | 벤더 TWAIN | WIA | VueScan | SilverFast |
|---|:---:|:---:|:---:|:---:|:---:|
| 벤더 커널 드라이버 | ✗ | ✓ | ✓ | ✓ | ✓ |
| WinUSB | ✓ | ✗ | ✗ | ? | ? |
| libusbK | ✓ | ✗ | ✗ | ? | ? |
| 없음 (알 수 없는 장치) | ✗ | ✗ | ✗ | ? | ? |
| usbipd bind (WSL2로) | WSL2에서 ✓ | ✗ | ✗ | ✗ | ✗ |

`?`는 미확인이다. VueScan과 SilverFast는 자체 드라이버를 쓴다고 알려져
있어 예외일 가능성이 있다 → spike U-1.

## 3. VueScan의 특수성

Hamrick 문서에 따르면 VueScan은:

- 자체 내장 드라이버를 가진다
- 벤더 드라이버가 설치돼 있으면 "충돌하지 않는다"
- 벤더 드라이버가 없으면 자체 드라이버를 설치한다

즉 VueScan은 **자기 드라이버를 바인딩한다.** 그렇다면:

```text
VueScan 드라이버가 바인딩된 상태 → libusb가 열 수 없다 (아마도)
WinUSB가 바인딩된 상태 → VueScan이 열 수 있는가? (미확인)
```

**만약 VueScan이 WinUSB 위에서도 동작한다면** Coolscan/Plustek 사용자의
손실이 실질적으로 0이 된다. VueScan이 이 계층의 사실상 표준 소프트웨어이기
때문이다.

**spike U-1이 이 프로젝트의 UX 결론을 크게 바꾼다.**

## 4. 스캐너별 손익

### 4.1 Nikon Coolscan — 잃을 것이 없다

- Nikon Scan 최종판이 Windows Vista 대상이며 이후 Windows에서 동작하지 않는다.
- 벤더 TWAIN/WIA 드라이버가 사실상 없다.
- 사용자는 VueScan 또는 SilverFast를 쓴다.

```text
WinUSB로 바꿔도 잃는 것: (VueScan/SilverFast를 잃지 않는다면) 없음
얻는 것: SANE coolscan2/coolscan3 경로
```

**이 플러그인의 Windows 가치가 가장 큰 장치다.**

단 [backend-quirks](../02-frontend-contract/backend-quirks.md) §3.7이
경고하듯 LS-5000의 load/eject/reset은 패치된 설치에서도 미검증이다.

### 4.2 Plustek OpticFilm — 손실 있음

- Windows 7/8/10/11(64-bit) 벤더 드라이버가 있다.
- QuickScan + SilverFast SE Plus 8 또는 9가 번들된다.
- SilverFast 8 라이선스는 현재 Windows 11 빌드에서 9로 유료 업그레이드가
  필요할 수 있다(미확인).

```text
WinUSB로 바꾸면 잃는 것: QuickScan, SilverFast(벤더 드라이버 경유 시)
얻는 것: SANE genesys 경로, negaflow 통합
```

SilverFast를 산 사용자에게는 실질적 손실이다.

### 4.3 Epson Perfection V800/V850 — 순손실

- Epson이 현행 Windows 11 드라이버를 제공한다.
- "Scanner Driver and Epson Scan 2 Utility v6.6.84.0": 64-bit TWAIN에서
  사용 가능, **Digital ICE 미지원**.
- 레거시 "EPSON Scan Utility v3.9.3.7": Digital ICE 있음,
  Windows 11 24H2 ARM 호환 명시.

```text
WinUSB로 바꾸면 잃는 것: Epson Scan 2, 레거시 유틸리티, Digital ICE
얻는 것: SANE epson2 경로
```

**Digital ICE 손실이 크다.** epson2 백엔드의 IR은 stock 빌드에서 노출되지
않으므로([backend-quirks](../02-frontend-contract/backend-quirks.md) §2),
SANE 경로에서 IR을 쓸 수 없다. 즉 먼지 제거 기능을 통째로 잃는다.

```text
D-28  Epson Perfection 사용자에게는 이 플러그인을 권하지 않는다.
      설치 프로그램이 Epson 장치를 감지하면 명시적으로 경고한다.
      "이 스캐너는 제조사 소프트웨어가 Windows에서 정상 동작합니다.
       SANE 경로로 바꾸면 Digital ICE(적외선 먼지 제거)를 사용할 수
       없게 됩니다."
```

**negaflow가 Epson을 지원하려면 WIA/TWAIN 어댑터가 정답이다.**
그것은 본체 negaflow-windows/docs의 `10-scanner/twain-wia.md`가 소유한다.

### 4.4 Reflecta / PIE — 현재는 무의미

- 벤더가 CyberView X5 + 드라이버를 제공한다.
- 설치 시 서명되지 않은 드라이버 경고가 나온다(Windows 11에서 마찰).
- **MSYS2 SANE 빌드에 `pieusb`가 없다.**

```text
재빌드 전: SANE 경로가 아예 없다
재빌드 후: WinUSB로 바꾸면 CyberView X5를 잃는다
```

## 5. 요약 권고

```text
Nikon Coolscan     → 이 플러그인을 권한다
Plustek OpticFilm  → 사용자가 선택한다. SilverFast 손실을 명시한다
Reflecta / PIE     → 재빌드 후, 사용자가 선택한다
Epson Perfection   → 권하지 않는다. 벤더 경로 또는 TWAIN 어댑터를 권한다
기타               → 개별 판단
```

이 권고를 README와 설치 프로그램에 반영한다.

## 6. 동시 사용 불가

WinUSB는 여러 애플리케이션의 동시 접근을 지원하지 않는다(libusb wiki 확인).

결과:

```text
플러그인이 스캔 중 → 다른 어떤 프로그램도 그 스캐너를 열 수 없다
다른 프로그램이 열고 있음 → 플러그인이 실패한다
```

**이것은 macOS에서도 실질적으로 같다**(USB 인터페이스 claim).
차이는 오류 메시지와 진단이다.

```text
macOS:   "another process has device opened for exclusive access"
Windows: (spike U-5에서 확인)
```

Windows 문구를 `runScanimage`의 `busy` 분류에 추가해야 한다
([scanimage-invocation](../02-frontend-contract/scanimage-invocation.md) §7).

## 7. 되돌리기 절차

사용자에게 정확히 안내해야 한다.

```text
1. 장치 관리자 열기 (Win+X → 장치 관리자)
2. "범용 직렬 버스 장치" 또는 "libusb-win32 devices" 아래에서
   스캐너를 찾는다
3. 오른쪽 클릭 → 드라이버 업데이트
4. "컴퓨터에서 드라이버 찾아보기"
5. "컴퓨터의 사용 가능한 드라이버 목록에서 직접 선택"
6. 제조사 드라이버가 목록에 있으면 선택
7. 없으면: 장치 제거(드라이버 소프트웨어 삭제 체크) 후
   제조사 설치 프로그램을 다시 실행
```

**5번에서 이전 드라이버가 목록에 없을 수 있다.** Zadig가 드라이버를
교체하면서 이전 바인딩 정보가 남지 않는 경우가 있다. 그때는 7번이 필요하고,
사용자가 제조사 설치 프로그램을 가지고 있어야 한다.

```text
D-29  설치 프로그램이 드라이버를 바꾸기 전에 현재 드라이버 정보를 기록한다.
        하드웨어 ID
        현재 드라이버 이름·버전·제공자
        INF 파일 경로 (있으면)
      되돌리기 도구가 이 정보를 사용자에게 보여준다.
```

이것은 libwdi를 내장할 때 가능하다. Zadig 안내 방식에서는 사용자가
직접 기록해야 하고, 실제로는 아무도 기록하지 않는다.

**이것이 libwdi 내장을 권하는 또 하나의 이유다**
([runtime-route-decision](../01-sane-runtime/runtime-route-decision.md) §8).

## 8. WSL2 경로의 이점

`usbipd bind/attach`도 장치를 Windows에서 떼어내지만:

```text
usbipd detach --busid 4-4
```

한 번으로 되돌아간다. 드라이버 롤백이 없다.

**되돌리기 비용이 압도적으로 낮다.** 이것이 WSL2 경로를 완전히 버리지
않는 이유다. 특히:

- Epson 사용자가 가끔 SANE 경로를 시험해보고 싶을 때
- 여러 스캐너를 번갈아 쓸 때
- 드라이버 교체가 두려운 사용자

**대체 경로로 명시적으로 문서화한다.**

## 9. 감지와 안내

플러그인이 다음을 감지해 사용자에게 알릴 수 있다.

```text
1. USB 장치 열거 (SetupAPI 또는 CfgMgr32)
2. VID/PID가 지원 목록에 있는가
3. 현재 바인딩된 드라이버가 무엇인가
4. WinUSB가 아니면 → "드라이버 바인딩이 필요합니다"
5. WinUSB인데 scanimage가 못 찾으면 → "백엔드가 이 모델을 모릅니다"
```

`diagnose` 서브커맨드가 이것을 한다
([diagnostics-and-troubleshooting](../08-operations/diagnostics-and-troubleshooting.md) §2.2).

**필요한 API**:

```text
CM_Get_Device_ID_List_W          장치 인스턴스 ID 목록
CM_Get_DevNode_Property_W        DEVPKEY_Device_DriverDesc,
                                 DEVPKEY_Device_Service,
                                 DEVPKEY_Device_HardwareIds
```

`SetupAPI`보다 `CfgMgr32`가 현대적이고 가볍다.

**주의**: 이 코드는 USB 장치를 열지 않는다. 열거만 한다.
장치를 여는 것은 `scanimage`의 일이다.

## 10. 지원 장치 VID/PID 목록

바인딩 도구와 진단이 대상을 좁히려면 필요하다.

현재 이 저장소에 기록된 것:

| 장치 | VID:PID | 백엔드 |
|---|---|---|
| Plustek OpticFilm 8100 | `07b3:130c` | genesys |
| Plustek OpticFilm 8100 (변종) | `07b3:1824` | **없음** |
| Plustek OpticFilm 8200i | `07b3:130d` | genesys |
| Plustek OpticFilm 8200i (GL128) | `07b3:1825` | **없음** |
| Reflecta/PIE 일부 | `05e3:0145` | pieusb (모델 번호도 확인) |

**나머지는 SANE 소스에서 추출해야 한다.**

```text
sane-backends-1.4.0/
    doc/descriptions/genesys.desc
    doc/descriptions/epson2.desc
    doc/descriptions/coolscan2.desc
    doc/descriptions/coolscan3.desc
    doc/descriptions/pieusb.desc
```

`.desc` 파일에 `:usbid "0x07b3" "0x130c"` 형태로 기록돼 있다.

```text
D-30  빌드 시 .desc 파일에서 우리가 포함한 백엔드의 USB ID를 추출해
      어댑터에 내장한다.
      진단과 바인딩 도구가 이 목록을 쓴다.
      목록은 SANE 버전과 함께 갱신된다.
```

**중요**: 이 목록은 "SANE가 안다"이지 "동작한다"가 아니다.
`.desc`의 status 필드(Complete/Good/Basic/Minimal/Untested)를 함께
추출해 진단에 표시한다.

## 11. 하지 말아야 할 것

```text
✗ VID만 보고 바인딩한다
     07b3:1824처럼 같은 VID의 지원 불가 변종을 망가뜨린다

✗ 자동으로 드라이버를 바꾼다
     사용자 동의 없이 다른 소프트웨어를 망가뜨린다

✗ 모든 스캐너를 자동 감지해 바인딩을 권한다
     Epson 사용자에게 손해를 권하게 된다

✗ 벤더 드라이버를 제거한다
     되돌릴 수 없게 만든다

✗ 제거 시 자동으로 되돌린다
     사용자가 다른 이유로 WinUSB를 원할 수 있다
```

## 12. spike

### U-1 — VueScan / SilverFast 공존

[usb-transport](../01-sane-runtime/usb-transport.md) U-1과 동일.
**이 프로젝트의 UX 결론을 좌우한다.**

### DC-1 — 드라이버 상태 조회

```text
CfgMgr32로 지원 목록의 VID/PID를 가진 장치를 찾고
DEVPKEY_Device_Service를 읽어 "WinUSB", "libusbK", 벤더 드라이버를 구분
```

### DC-2 — 되돌리기 재현성

```text
1. 벤더 드라이버 상태 기록
2. Zadig/libwdi로 WinUSB 바인딩
3. 장치 관리자에서 되돌리기 시도
4. 이전 드라이버가 목록에 나타나는가
5. 나타나지 않으면 제조사 설치 프로그램 재실행으로 복구되는가
6. 스캐너 3종 이상에서 반복
```

**5번이 실패하는 장치가 있으면 그 장치는 지원 대상에서 뺀다.**
되돌릴 수 없는 변경을 사용자에게 시킬 수 없다.

### DC-3 — 동시 열기 오류 문구

[usb-transport](../01-sane-runtime/usb-transport.md) U-5와 동일.

## 13. 체크리스트

- [ ] 스캐너별 손익 표가 문서와 설치 프로그램에 반영됨
- [ ] Epson 경고 (D-28)
- [ ] 드라이버 정보 기록 (D-29)
- [ ] USB ID 목록 추출 (D-30)
- [ ] `diagnose`가 드라이버 상태를 보여줌
- [ ] 되돌리기 절차가 문서화됨
- [ ] 동시 열기 오류가 `busy`로 분류됨
- [ ] WSL2 대체 경로가 문서화됨
- [ ] U-1, DC-2 결과가 반영됨
