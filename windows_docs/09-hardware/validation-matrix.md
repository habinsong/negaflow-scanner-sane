# 실기 검증 매트릭스

기준일: 2026-08-04
상태: QA 실행 명세
목적: "장치가 보인다"와 "이 플러그인이 그 스캐너를 지원한다"를 분리한다

관련 문서:

- [driver-conflicts](driver-conflicts.md)
- [usb-transport](../01-sane-runtime/usb-transport.md)
- [backend-quirks](../02-frontend-contract/backend-quirks.md)
- [test-plan](../99-plan/test-plan.md)

## 1. 지원 표시의 조건

Windows 지원을 표시하려면 다음 **정확한 조합**이 검증을 통과해야 한다.

```text
스캐너 하드웨어
+ 펌웨어 버전
+ USB 제품 ID
+ Windows 빌드
+ CPU 아키텍처
+ 바인딩된 드라이버와 버전
+ SANE 런타임 버전과 백엔드
+ 어댑터 버전
+ 연결 경로 (직결 / 허브 / 독)
+ 요청 옵션 조합
```

같은 마케팅 모델명이라도 USB 제품 ID나 하드웨어 리비전이 다르면
**별도 행**이다. OpticFilm 8200i의 `130d`와 `1825`가 그 예다.

## 2. 증거 등급

| 등급 | 증거 | 허용 표현 |
|---|---|---|
| E0 | 벤더 문서 / SANE `.desc` 상태 | 조사 대상 |
| E1 | USB 장치 관리자 열거 | OS가 장치를 본다 |
| E2 | WinUSB 바인딩 성공 | libusb가 열 수 있는 상태 |
| E3 | `scanimage -f`가 나열 | SANE 백엔드가 장치를 인식한다 |
| E4 | `scanimage -A`가 옵션 덤프 반환 | 장치가 능력을 보고한다 |
| E5 | preview 산출물 | preview 경로가 실제 픽셀을 낸다 |
| E6 | full scan 산출물 + applied 증거 | 특정 옵션/ROI로 획득됐다 |
| E7 | 전체 포맷/품질/복구 매트릭스 반복 통과 | 이 조합 verified |

**`verifiedStatus = verified`는 E7에만 쓴다.**
현재 어댑터는 항상 `compatibleTarget`을 보고하므로
([wire-contract](../05-protocol/wire-contract.md) §3.2) wire에는
등급이 나타나지 않는다. 이 매트릭스는 **문서와 README의 지원 표**를
위한 것이다.

E1~E4는 서로 다른 증거다. 특히:

- E1이 있어도 E2가 실패할 수 있다(드라이버 교체 불가)
- E2가 있어도 E3이 실패할 수 있다(백엔드가 이 리비전을 모른다)
- E3이 있어도 E4가 실패할 수 있다(장치 열기 실패)
- E4가 있어도 E5가 실패할 수 있다(전송 실패)

## 3. 매트릭스 축

### 3.1 하드웨어

우선순위 순.

| # | 장치 | 백엔드 | 근거 |
|---:|---|---|---|
| 1 | Nikon Coolscan LS-50 ED | coolscan3 | 벤더 드라이버 없음. 이 플러그인의 최대 가치 |
| 2 | Plustek OpticFilm 8200i (`07b3:130d`) | genesys | IR 지원. 대표적 필름 스캐너 |
| 3 | Plustek OpticFilm 8100 (`07b3:130c`) | genesys | IR 없음. 대조군 |
| 4 | Epson Perfection V850 (GT-X980) | epson2 | 평판 + 투과. 정수 mm 절삭 재현 |
| 5 | Nikon Coolscan LS-5000 ED | coolscan3 | load/eject 미검증 항목 |
| 6 | Reflecta ProScan 10T | pieusb | 재빌드 후 |
| 7 | 그 외 | — | 커뮤니티 보고 |

**1~4가 최소 세트다.** 이것 없이 Windows 지원을 표시하지 않는다.

### 3.2 Windows

| 축 | 값 |
|---|---|
| 최소 API 대상 | Windows 10 1903 (activeCodePage UTF-8) 또는 Windows 11 |
| CI 기준 이미지 | GitHub Actions `windows-latest` |
| 하드웨어 랩 OS | Windows 11 현행 지원 빌드 |
| 고객 지원 OS | 출시 시점에 지원 중인 소비자 릴리스 |

**네 축을 분리해서 기록한다.** negaflow 본체 windows_docs README §3.8이
같은 원칙을 정한다. Windows 10 지원 여부는 기술적 실행 가능성과
제품 지원을 구분해 결정한다.

### 3.3 아키텍처

```text
x64        1차
ARM64      2차 (네이티브 빌드 존재, 실기 검증 필요)
x86        지원하지 않음
```

ARM64에서 확인할 것:

- WinUSB 드라이버 설치가 가능한가
- `clangarm64` SANE 빌드가 동작하는가
- USB 컨트롤러 동작이 x64와 다른가

### 3.4 연결

| 경로 | 우선순위 |
|---|---|
| USB 직결(내장 포트) | 필수 |
| USB 2.0 허브 | 권장 |
| USB-C 어댑터 | 권장 (README가 이 조합의 실패를 경고한다) |
| Thunderbolt 독 | 선택 |

USB 2.0 필름 스캐너가 USB-C 어댑터를 통해 자주 실패한다는 것이
macOS에서 관측된 사실이다. Windows에서 재확인한다.

### 3.5 옵션 조합

각 장치에 대해:

```text
preview
full color 8-bit 최저 지원 dpi
full color 16-bit 최저 지원 dpi
full color 16-bit 중간 dpi
full color 16-bit 최고 dpi
full gray 16-bit (지원하면)
IR 요청 (지원하면)
다중 노출 (지원하면)
스캔 영역 축소 (mm 지원 시)
스캔 영역 원점 지정 (지원 시)
밝기 조정 (지원 시)
```

**최고 dpi가 중요하다.** 파일 크기가 크고 전송 시간이 길어
타임아웃·메모리·4 GB TIFF 한계가 여기서 드러난다.

## 4. 케이스별 절차

각 (장치 × Windows × 아키텍처 × 연결) 조합에 대해:

```text
E1  장치 관리자에서 장치 확인, VID/PID 기록, 드라이버 이름 기록
E2  드라이버 바인딩, 성공 여부와 소요 시간 기록
E3  scanimage -f 출력 전문 기록. 장치명 형식 기록
E4  scanimage -A 출력 전문 저장 (fixtures/dumps/에 추가)
E5  preview 스캔. 산출물 크기·픽셀 확인
E6  §3.5의 각 조합. applied options와 산출물 검증
E7  §5의 추가 항목
```

**E4의 덤프를 반드시 보존한다.** conformance corpus의 입력이 된다
([conformance-fixtures](../05-protocol/conformance-fixtures.md) §3.2).

## 5. E7 — 추가 검증 항목

E6까지는 "한 번 성공했다"이다. E7은 "믿을 수 있다"이다.

### 5.1 반복성

```text
같은 옵션으로 5회 연속 스캔
  전부 성공하는가
  결과 크기가 일정한가
  소요 시간이 일정한가
  중간에 장치를 다시 열어야 하는 일이 생기는가
```

### 5.2 취소

```text
진행률 10%, 50%, 90%에서 각각 취소
  프로세스가 종료되는가
  얼마나 걸리는가
  중간 파일이 지워지는가
  즉시 다음 스캔이 가능한가
  램프가 꺼지는가
```

→ [cancellation](../03-process-and-io/cancellation.md) C-2, C-3

### 5.3 재연결

```text
스캔 중 USB 케이블 분리
  오류가 명확한가 (notConnected)
  프로세스가 매달리지 않는가
케이블 재연결 후
  detect가 장치를 다시 찾는가
  주소가 바뀌었는가
```

### 5.4 점유

```text
다른 프로그램(VueScan 등)이 장치를 연 상태에서 detect/scan
  오류가 busy로 분류되는가
  오류 문구가 무엇인가
```

### 5.5 주소 변동

```text
scanimage -f → -A → -f 를 20회 반복
장치명이 바뀌는 비율 기록
```

→ [device-identity](../02-frontend-contract/device-identity.md)

### 5.6 다중 패스

```text
IR 요청 스캔 (RGB + IR 2패스)
다중 노출 스캔 (3패스)
다중 노출 + IR (4패스)
NEGAFLOW_HWEXP_SAMPLES=4 (12패스, 지원 장치만)
  각 패스가 성공하는가
  패스 사이에 재연결이 필요한가
  총 소요 시간
  메모리 사용량 최대치
```

**메모리가 여기서 문제가 된다.** 12패스 7200 dpi는 수십 GB의 float
버퍼를 요구한다([exposure-merge](../04-imaging/exposure-merge.md) §7.2).

### 5.7 결과 검증

```text
산출물 TIFF가 3단계 검증을 통과하는가
requested == applied == result == artifact 인가
IR과 RGB의 픽셀 크기가 같은가
스캔 영역이 요청과 일치하는가 (epson2는 1 mm 미만 허용)
macOS에서 같은 스캐너·같은 옵션으로 얻은 결과와 크기가 같은가
```

마지막 항목이 중요하다. **같은 요청에 다른 픽셀 크기가 나오면
지오메트리 처리에 차이가 있다는 뜻이다.**

## 6. SCSI 장치

```text
Nikon Coolscan LS-20, LS-30, LS-1000  (coolscan 백엔드)
PIE 구형 SCSI                          (pie 백엔드)
```

현대 Windows에서 SCSI 스캐너는 사실상 불가능하다.

- ASPI 계층이 없다
- 레거시 SCSI HBA 드라이버가 Windows 11에 없다
- SANE의 `sanei_scsi`가 Windows에서 `ntddscsi.h`를 쓰는 코드 경로가 있지만
  (configure.ac 535행) 실동작이 미검증이다
- MSYS2 빌드에 `pie`가 없다

```text
D-31  SCSI 스캐너를 Windows 지원 범위에서 제외한다.
      README의 지원 표에 명시한다.
      코드에서 특별히 막지는 않는다 — scanimage가 장치를 나열하면
      동작할 수 있다.
```

## 7. 결과 기록 형식

각 케이스마다 한 행.

```text
장치:          Plustek OpticFilm 8200i
USB ID:        07b3:130d
펌웨어:        (읽을 수 있으면)
Windows:       11 24H2 (26100.xxxx)
아키텍처:      x64
드라이버:      WinUSB 6.1.7600.16385 (libwdi로 설치)
SANE:          1.4.0-negaflow (genesys)
어댑터:        1.0.3-win
연결:          내장 USB-A 포트 직결
날짜:          2026-xx-xx

E1 ✓  E2 ✓  E3 ✓  E4 ✓  E5 ✓  E6 부분  E7 미실행

E6 세부:
  preview                    ✓  1.2s
  color 8-bit 600dpi         ✓  18s
  color 16-bit 3600dpi       ✓  142s
  color 16-bit 7200dpi       ✓  521s  (파일 416 MB)
  gray 16-bit 3600dpi        ✓
  IR 3600dpi                 ✓  RGB 142s + IR 138s
  다중 노출                   ✗  --scan-exposure-time 없음
  영역 축소 24×36mm           ✓
  영역 원점 지정              ✗  -l/-t 범위 없음 (예상된 동작)
  밝기 +10                   ✗  16-bit에서 억제됨 (예상된 동작)

메모:
  scanimage -A 덤프를 fixtures/dumps/genesys-8200i-win-color.txt 에 보존
  장치명이 열 때마다 바뀜 (20회 중 11회) — macOS와 같은 현상
  7200dpi에서 진행률 간격 최대 8.2초 (stall timeout 180s에 여유 충분)
```

## 7a. 실측 결과 — OpticFilm 8100 (2026-08-06)

위 §7은 형식 예시다. 아래가 **실제로 돌린 것**이다.

```text
장치:          Plustek OpticFilm 8100
USB ID:        07b3:130c
Windows:       11 Pro 26200
아키텍처:      x64
드라이버:      **바꾸지 않음** — 제조사 드라이버 그대로, usbscan.sys 경유
SANE:          1.4.0-negaflow (genesys), 설치 프로그램이 함께 설치
어댑터:        1.0.3-win, %LOCALAPPDATA%\Negaflow\ScannerPlugins\sane
연결:          메인보드 USB 직결
PATH:          msys64 를 완전히 제거한 상태 — 설치본만으로 돈다
```

사용자가 실제로 하는 순서를 그대로 돌렸다. **중간에 끊지 않았다.**

```text
preview-1    exit=0   17s   848x566    2,880,048 바이트
main-1       exit=0   17s   848x566    2,880,048 바이트   600 dpi
preview-2    exit=0   17s   848x566    2,880,048 바이트
main-2       exit=0   24s  1700x1133  11,556,840 바이트  1200 dpi
preview-3    exit=0   17s   848x566    2,880,048 바이트
```

다섯 번 연속, 프리뷰와 본스캔을 번갈아 해도 스캐너가 죽지 않는다.

**이 기기에는 싼 프리뷰가 없다.** 프리뷰가 600 dpi 본스캔과 결과도 시간도
같다. 이유는 두 가지가 겹쳐서다 — genesys 가 `--preview` 를 읽지 않고
(backend-quirks §1.7), 이 기기의 최저 해상도가 600 이다. 더 낮출 값이 없다.
7500i 계열은 최저가 900 이라 사정이 같다. 고칠 수 있는 것이 아니므로
"프리뷰를 빠르게" 라는 작업을 만들지 않는다.

Epson 은 다르다. 해상도 목록이 50 dpi 부터라 프리뷰가 실제로 싸다.

### 7a.1 해상도 전 범위 — 연속으로 (36 × 24 mm, 16-bit 컬러)

이 기기가 내는 다섯 단계를 **끊지 않고 이어서** 돌렸다.

```text
  600 dpi   17.1s     848 x  566        2,880,048 바이트   진행률  10건
 1200 dpi   21.2s    1700 x 1133       11,556,840 바이트   진행률  28건
 2400 dpi   28.2s    3392 x 2267       46,138,224 바이트   진행률  94건
 3600 dpi   35.3s    5088 x 3401      103,825,968 바이트   진행률 204건
 7200 dpi   57.5s   10192 x 6803      416,017,296 바이트   진행률 798건
```

7200 dpi 에서 416 MB 가 나오고 58초가 걸린다. 진행률 간격이 촘촘해
(798건 / 58초) stall 상한 180초에 여유가 크다.

**폭이 8 픽셀 배수로 내림된다.** 36 mm × 7200 / 25.4 = 10204.7 인데 10192 가
나온다(= 1274 × 8). 2400 에서도 3401 → 3392 다. epson2 의
`pixels_per_line & ~7` 과 같은 성질이고(backend-quirks §2.3), 최대 손실이
7 픽셀 — 7200 dpi 에서 0.025 mm 다. 맥도 같으므로 보정하지 않는다.

메모리는 문제가 되지 않는다. 어댑터는 결과 TIFF 의 **태그만** 읽고 픽셀을
올리지 않는다.

픽셀을 통째로 올리는 곳은 `loadScannerTIFF` 하나뿐이고, 그것을 부르는 것은
다중 노출 병합뿐이다. 다중 노출은 `--scan-exposure-time` 이 있어야 켜지는데
genesys 에도 epson2 에도 그 옵션이 없다(실기 8100 덤프로 확인). 그러니
OpticFilm 과 Epson 사용자는 그 경로를 지나지 않는다.

지나갔다면 문제가 됐을 것이다. 픽셀 하나가 float 4개(16바이트)라 7200 dpi
한 장이 **1.1 GB** 다.

### 7a.2 해결 — 스캔 헤드를 세우지 않고 프로세스를 끝내고 있었다

위 매트릭스를 세 번 돌려 **두 번 실패했다.**

```text
1회차   7200 dpi  61.3초  실패
2회차   전부 통과
3회차   3600 dpi  35.3초  실패
```

3회차에서 실제 메시지를 잡았다.

```text
Progress: ... 99.0%  100.0%  100.0%
scanimage.exe: sane_read: Error during device I/O          (exit 9)
```

**진행률이 100% 를 찍은 뒤에 실패한다.** 데이터는 다 받았는데 실패로
처리되어 35~58초짜리 스캔이 통째로 버려진다.

원인 위치는 코드에서 좁혔다. `genesys.cpp` 의 `sane_read_impl` 은 데이터를
다 읽은 그 호출 안에서 헤드 파킹을 시작한다.

```c
if (dev->total_bytes_read >= dev->total_bytes_to_read) {
    ...
    dev->cmd_set->move_back_home(dev, false);
```

`scanner_move_back_home` 은 가벼운 호출이 아니다 — TA 헤드 복귀, 모터 이동,
`update_home_sensor_gpio`, `scanner_read_reliable_status`, 그리고 작은 모터
세션까지 **전부 레지스터 I/O**(제어 전송 `IOCTL_SEND_USB_REQUEST`)다. 큰 벌크
전송 직후 그중 하나가 실패하면 `sane_read` 가 EOF 대신 IO_ERROR 를 낸다.

#### 재현과 원인

```text
같은 해상도(3600)로 8회 연속            8/8 성공 — 재현 안 됨
해상도를 바꿔 가며(600~7200) 연속        4번째에서 실패, 오류 코드 확보
같은 순서에 스캔 사이 8초 쉬기           15/15 성공
```

오류 코드가 결정적이었다.

```text
usbscan_control_msg: request 0x04 failed, error 121
  → UsbDevice::control_msg
  → ScannerInterfaceUsb::write_register
  → CommandSetGl846::update_home_sensor_gpio
  → scanner_stop_action
  → scanner_move_back_home_ta
  → scanner_move_back_home
  → sanei_genesys_asic_init
  → sane_open_impl: failed during open device 'usbscan:000'
```

`121` 은 `ERROR_SEM_TIMEOUT` 이고, 시작 10:53:55 → 실패 10:55:55 로 **정확히
120초**다. usbscan.sys 자신의 2분 타임아웃이다(`IOCTL_SET_TIMEOUT` 이 듣지
않는다는 것은 patch 005 주석에 이미 적혀 있다).

원인은 이렇다. OpticFilm 모델표에 `ModelFlag::MUST_WAIT` 이 없어서 genesys 가

```c
move_back_home(dev, /*wait_until_home=*/false);
dev->parking = true;
```

로 **파킹 명령만 내고 반환한다.** 헤드가 아직 움직이는 중에 `scanimage` 가
끝나고, 움직이는 OpticFilm 은 제어 전송에 답하지 않는다. 그래서

- 다음 스캔의 `sane_open` 이 120초를 버리고 실패하거나,
- 이번 스캔의 `sane_read` 가 EOF 시점 파킹에서 실패한다
  (데이터는 이미 다 받았는데 버려진다).

8초를 쉬면 사라지는 이유가 이것이다 — 그 시간이 헤드가 집에 돌아가는 시간이다.

#### 고친 방법

`sane-runtime/patches/008-opticfilm-wait-for-park.patch` 가 OpticFilm 6개
항목에 `ModelFlag::MUST_WAIT` 을 넣는다. 그러면

- `sane_read` 는 EOF 에서 파킹하지 않는다 → 완료된 스캔을 파킹 실패로 잃는
  경로가 사라진다
- `sane_cancel` 이 `wait_until_home` 으로 파킹한다 → 홈 센서를 100 ms 씩
  300회 확인하고 30초에 포기한다. 프로세스가 끝날 때 장치가 멈춰 있다

1.4.0 의 어느 모델도 이 플래그를 켜지 않아 upstream 이 이 경로를 돌린 적이
없다. 그래서 켜기 전에 두 호출 지점을 모두 읽었고, 둘 다 짧고 상한이 있다.

#### 고친 뒤 실측

```text
해상도를 바꿔 가며 연속, 간격 0초, 3사이클      15/15 성공
```

**느려지지 않았다.** 사이클당 시간이 전과 같다(7200 dpi 57.5초 → 58.5초).
`sane_cancel` 시점에는 헤드가 거의 돌아와 있어서 기다림이 1초 안쪽이다.

## 8. README 지원 표 갱신

현재 README의 표는 **SANE 1.4 문서 상태**를 적고 있으며 개별 유닛 검증이
아니라고 명시한다. Windows 열을 추가한다.

```markdown
| Scanner family | SANE backend | SANE 1.4 status | macOS | Windows |
|---|---|---|---|---|
| Plustek OpticFilm 8200i (07b3:130d) | genesys | Complete | 전용 필름 경로 | E6 부분 (2026-xx) |
| Nikon Coolscan LS-50 ED | coolscan3 | Complete | 전용 필름 경로 | 미검증 |
| Epson Perfection V800/V850 | epson2 | Good | 투과 + 위치 지정 | **권장하지 않음** — driver-conflicts 참조 |
| Reflecta / PIE | pieusb | 모델별 | 보고된 옵션만 | 미지원 (백엔드 미포함) |
| Nikon Coolscan LS-20/30/1000 | coolscan | 모델별 | SCSI 전용 | **미지원** (SCSI) |
```

**"미검증"과 "미지원"을 구분한다.** 전자는 시도하지 않은 것,
후자는 시도해도 안 되는 것이다.

## 9. 커뮤니티 보고

장비를 전부 확보할 수 없으므로 사용자 보고가 필요하다.

```text
보고 템플릿:
  diagnose 출력
  Windows 버전
  스캐너 모델과 USB ID
  드라이버 상태
  성공/실패한 작업
  scanimage -A 덤프 (개인정보 확인 후)
```

**보고를 그대로 지원 표에 올리지 않는다.** E 등급을 명시하고
"사용자 보고"로 표시한다.

## 10. 이 매트릭스가 증명하지 않는 것

- 이미지 품질(색 정확도, 해상력, 노이즈)
- 다른 스캔 소프트웨어와의 결과 비교
- 장기 신뢰성
- 모든 펌웨어 리비전
- 모든 USB 컨트롤러

**품질은 negaflow 본체의 영역이다.** 이 플러그인은 "요청한 옵션이
정확히 적용된 raw TIFF"를 낼 뿐이고, 그 이후는 negaflow가 한다.

## 11. 릴리스 gate

Windows 지원을 표시하려면:

- [ ] §3.1의 1~4번 장치 중 최소 2대에서 E6 통과
- [ ] 그중 하나는 IR 경로 E6 통과
- [ ] 취소·재연결·점유 시나리오 통과
- [ ] 반복성 5회 통과
- [ ] macOS와 결과 픽셀 크기 일치
- [ ] 각 장치의 `-A` 덤프가 fixtures에 보존됨
- [ ] 드라이버 되돌리기가 재현 가능(DC-2)
- [ ] 지원 표에 검증 날짜와 등급이 기록됨
