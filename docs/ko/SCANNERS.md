# 지원 스캐너

[문서 홈](README.md)

아래 표는 알려진 SANE 대상과 이 플러그인이 처리하는 경로를 정리한 것입니다. 같은 제품명을 가진
모든 장치가 작동한다는 보장은 아닙니다.
[SANE 최신 지원 목록](https://www.sane-project.org/sane-supported-devices.html)을 확인한 뒤 실제로
연결한 장치를 `scanimage -L`과 `scanimage -A`로 다시 확인하는 편이 확실합니다.

“패치된 SANE”은 `mac26` 설치본이 빌드하는 SANE과 Windows 설치 파일에 들어 있는 SANE 런타임을
말합니다. SANE 1.4.0에 [`sane-runtime/SOURCES.md`](../../negaflow-mac/sane-runtime/SOURCES.md)에
적힌 패치를 더한 것입니다. `mac14` 설치본은 이 패치가 없는 Homebrew 기본 SANE 1.4.0을 씁니다.

| 스캐너 계열 | SANE 백엔드 | 상태 | 플러그인 처리 |
|---|---|---|---|
| Plustek OpticFilm 7200, 7200 v2, 7200i, 7300, 7400 v2, 7500i, 7600i v2 | `genesys` | SANE 1.4 기준 Complete | 필름 전용 스캐너 경로 |
| Plustek OpticFilm 7400 v1, 7600i v1 | `genesys` | 1.4.0 이후 upstream에서 보정됨, 패치된 SANE에 포함 | 필름 전용 스캐너 경로, 실기 미확인 |
| Plustek OpticFilm 8100, USB `07b3:130c` (GL845) | `genesys` | SANE 1.4 기준 Complete | 필름 전용 스캐너 경로, 실기 확인 |
| Plustek OpticFilm 8200i, USB `07b3:130d` (GL845) | `genesys` | SANE 1.4 기준 Complete | 필름 전용 스캐너 경로 |
| Plustek OpticFilm 8200i 신형, USB `07b3:1825` (GL128, SANE에서는 “8200i SE”로 표시) | `genesys`, 패치된 SANE에만 있음 | upstream Basic: 16-bit, 150~7200 dpi, 적외선 없음 | 필름 전용 스캐너 경로, 실기 미확인 |
| Plustek OpticFilm 8100 V2, USB `07b3:1824` (GL128) | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| Plustek OpticFilm 8300i, USB `07b3:181f` (GL128, SE에서 측정) | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| Plustek OpticFilm 9000i Ai, USB `07b3:182f` | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| Plustek OpticFilm 120, 120 Pro, 135, 135i | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| Epson Perfection V700/V750(GT-X900), V800/V850(GT-X980) | `epson2` | Good | 보고된 경우 투과 소스와 위치 지정 플랫베드 영역 사용 |
| Nikon Coolscan LS-40 ED, LS-50 ED, LS-5000 ED (USB) | `coolscan3`, `coolscan2` | Complete(LS-40), Minimal(LS-50), Untested(LS-5000) | 아래 제약이 있는 필름 전용 스캐너 경로, 실기 미확인 |
| Nikon Coolscan LS-4000 ED, LS-8000 ED (IEEE 1394 / FireWire) | SBP-2를 거친 `coolscan3`, `coolscan2` | Linux 기준 Good | macOS 26에서는 사용 불가, Windows와 macOS 14/15는 미확인(아래 참고) |
| Nikon Coolscan LS-30, LS-2000 (SCSI) | `coolscan3` | Complete(LS-30), Good(LS-2000) | SCSI 호스트 어댑터 필요 |
| Nikon Coolscan LS-20, LS-1000 | `coolscan` | 기종별로 다름 | SCSI 전용 |
| Nikon Coolscan LS-9000 ED | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| Reflecta ProScan/CrystalScan/DigitDia, PIE PowerSlide | `pieusb`, 구형 SCSI는 `pie` | 기종과 모델 번호에 따라 다름 | 보고된 옵션만 사용 |
| Pacific Image PrimeFilm XA, XAs, XA Plus | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| 그 밖의 투과 원고용 플랫베드·필름 스캐너 | 백엔드별로 다름 | 기종별로 다름 | 기능 보고 기준, 모델명 fallback 없음 |

## 제품명은 하드웨어를 알려주지 않습니다

Plustek은 새 하드웨어를 옛 제품명 그대로 팝니다. 둘을 가르는 것은 본체에 적힌 이름이 아니라 USB
product ID입니다.

| 본체 표기 | USB ID | 컨트롤러 | SANE |
|---|---|---|---|
| OpticFilm 8100 구형 | `07b3:130c` | GL845 | SANE 1.4.0의 `genesys` |
| OpticFilm 8100 신형(V2) | `07b3:1824` | GL128 | 없음 |
| OpticFilm 8200i 구형 | `07b3:130d` | GL845 | SANE 1.4.0의 `genesys` |
| OpticFilm 8200i 신형 | `07b3:1825` | GL128 | 2026-09부터 upstream master의 `genesys`, 패치된 SANE에만 있음 |
| OpticFilm 8300i SE (Ai는 미확인) | `07b3:181f` | GL128 | 없음 |
| OpticFilm 9000i Ai | `07b3:182f` | 공개되지 않음 | 없음 |

SE와 Ai는 하드웨어가 아니라 함께 주는 SilverFast 판의 이름입니다. 구형 8200i SE·Ai는 `130d`,
신형은 `1825`입니다.

GL128 세 기종은 레지스터 배치는 같지만 값까지 같지는 않습니다. SANE의 GL128 코드가 상당 부분
기대고 있는 USB 캡처 해독은 공개 드라이버 [pyopticfilm](https://github.com/jboneng/pyopticfilm)에서
나왔고, 그 프로젝트가 차이를 기록해 두었습니다. 8100 V2는 부팅할 때 ASIC 클록과 레지스터 `0x0B`
값이 다르고, 8300i SE는 노출·센서 타이밍·모터 테이블이 모두 따로입니다. 8200i SE 테이블을 그대로
돌리는 것은 모터와 램프 제어를 짐작으로 하는 일입니다. pyopticfilm에는 8100 V2에서 레지스터 비트
하나를 켠 직후 모터가 걸린 기록이 있습니다. 그래서 이 플러그인은 GL128 기종을, SANE 빌드가 실제로
구동하고 누군가 그 기기로 스캔해 본 뒤에야 켭니다.

Mac에서는 `system_profiler SPUSBDataType`, Windows에서는 장치 관리자로 ID를 확인합니다.

식별을 어렵게 하는 함정이 두 가지 더 있습니다.

- `pieusb`는 USB ID와 **모델 번호**를 함께 봅니다. Reflecta와 PIE 기기는 `05e3:0145`처럼 같은
  ID를 공유하므로, 모델 번호가 `pieusb.conf`에 있어야만 사용할 수 있습니다.
- `epson2`는 Epson 스캐너를 일본 모델명으로 인식합니다. `scanimage -L`은 Perfection V800/V850을
  `GT-X980`, V700/V750을 `GT-X900`으로 표시합니다. 같은 스캐너입니다.

## Nikon Coolscan

이 플러그인으로 실기 확인을 거친 Coolscan은 아직 없습니다. 아래 내용은 `coolscan3` 소스와 플러그인
코드를 읽고 정리한 것입니다.

### 연결

LS-4000 ED와 LS-8000 ED에는 IEEE 1394(FireWire) 포트만 있습니다. SANE은 이 기기들을 SBP-2를 거친
SCSI 장치로 다루므로, 장치 이름은 USB가 아니라 `coolscan3:scsi:...` 형태로 나옵니다.

- **macOS 26에는 FireWire가 아예 없고**, 어댑터를 써도 되살아나지 않습니다. 패치된 SANE을 쓰는
  유일한 설치본인 `mac26`으로는 이 두 기종에 닿을 수 없습니다.
- macOS 14와 15에는 FireWire가 남아 있고 SANE에도 macOS용 SCSI 인터페이스가 있지만, `mac14`
  설치본으로 이 경로를 시험한 적은 없습니다.
- Windows에서는 SANE이 SCSI pass-through 경로로 SBP-2 스캐너에 닿아야 합니다. 이것도 시험한 적이
  없습니다.

현실적인 Coolscan 대상은 USB를 쓰는 LS-40 ED, LS-50 ED, LS-5000 ED입니다.

### 플러그인 경로가 하는 일

| 항목 | 동작 | 결과 |
|---|---|---|
| 색 모드 | `coolscan2`/`coolscan3`에는 `--mode`가 없고 언제나 RGB를 돌려줌 | `color`만 보고합니다. 흑백 필름도 컬러로 스캔하고 negaflow가 현상하며, 요청은 필름 종류만 빼면 컬러 네거티브와 같습니다 |
| 스캔 영역 | 영역 옵션이 mm가 아니라 스캐너 최대 해상도 기준 픽셀 | negaflow가 영역을 고를 수 없어서 플러그인이 기본값 36 x 24 mm를 픽셀로 바꿉니다. LS-8000의 중판 프레임은 왼쪽 위 36 x 24 mm만 남습니다 |
| 프레임 | `--frame`을 보내지 않음 | 스트립 홀더에서는 첫 프레임만 스캔합니다 |
| 초점 | `coolscan3`는 요청받을 때만 자동 초점을 잡는데, negaflow가 요청하지 않음 | 스캐너의 현재 초점 위치로 스캔합니다 |
| 적외선 | `--infrared`는 RGBI 한 프레임을 돌려줌 | IR 채널로 제공하지 않습니다 |
| 필름 종류 | `--negative`는 스캐너가 색을 뒤집게 함 | 언제나 `--negative=no`로 보내 negaflow가 원본 네거티브를 받습니다 |

표의 마지막 두 줄은 의도한 동작입니다. 앞의 네 줄은 남은 작업이고, 하나하나 실제 스캐너로 확인해야 합니다.

## 적외선 채널

여기서 “IR 사용 가능”은 별도 적외선 이미지를 `irPath`로 negaflow에 넘길 수 있다는 뜻입니다.
백엔드 안에서만 작동하는 먼지 제거 옵션은 IR 채널로 보고하지 않습니다.

| 스캐너·백엔드 경로 | IR 상태 | 획득 방법 | 별도 IR TIFF |
|---|---|---|---|
| OpticFilm 7200, 7200 v2, 7300, 7400, 8100 | 사용 불가 | IR 소스를 제공하지 않는 기종 | 없음 |
| OpticFilm 7200i, 7500i, 7600i, 8200i `07b3:130d` | `scanimage -A`에 IR 소스가 나오면 사용 가능 | `Transparency Adapter Infrared` 별도 패스 | 있음 |
| OpticFilm 8200i 신형 `07b3:1825` | 사용 불가 | SANE의 GL128 코드에 아직 적외선 패스가 없음 | 없음 |
| OpticFilm 8100 V2, 8300i, 9000i | 사용 불가 | SANE 백엔드가 없음 | 없음 |
| `mac26` 설치본의 Epson V700/V750/V800/V850 | `scanimage -A`가 적외선 모드를 보고하면 사용 가능 | 패치된 `epson2`의 `Infrared` 모드 별도 패스 | 있음 |
| 기본 `epson2`의 Epson V700/V750/V800/V850 | 사용 불가 | 기본 빌드는 `SANE_FRAME_IR`이 빠진 채 컴파일됨 | 없음 |
| `--infrared`를 제공하는 Nikon `coolscan3` | `scanimage` 경로에서는 사용 불가 | `coolscan3`는 `SANE_FRAME_RGBI` 한 프레임을 반환하지만 `scanimage` 1.4는 이를 RGB와 IR TIFF로 분리하지 못함 | 없음 |
| `--clean-image`만 제공하는 Reflecta/PIE | IR 채널로는 사용 불가 | 먼지 제거가 백엔드 안에서 끝남 | 없음 |
| 그 밖의 스캐너 | 조건부 | `scanimage -A`에 활성 상태의 별도 IR source 또는 mode가 있을 때만 | 크기·형식 확인 후 있음 |

IR 패스에는 RGB와 같은 요청 해상도와 스캔 영역을 사용하고, 두 파일의 실제 픽셀 크기가 같은지 확인한
뒤 반환합니다. negaflow는 이 IR 이미지를 GrainMend IR에 사용할 수 있습니다.
