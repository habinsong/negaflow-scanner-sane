# 지원 스캐너

[문서 홈](README.md)

아래 표는 알려진 SANE 1.4 대상과 이 플러그인이 처리하는 경로를 정리한 것입니다. 같은 제품명을 가진
모든 장치가 작동한다는 보장은 아닙니다.
[SANE 최신 지원 목록](https://www.sane-project.org/sane-supported-devices.html)을 확인한 뒤 실제로
연결한 장치를 `scanimage -L`과 `scanimage -A`로 다시 확인하는 편이 확실합니다.

| 스캐너 계열 | SANE 백엔드 | SANE 1.4 상태 | 플러그인 처리 |
|---|---|---|---|
| Plustek OpticFilm 7200, 7200 v2, 7200i, 7300, 7400 v2, 7500i, 7600i | `genesys` | Complete | 필름 전용 스캐너 경로 |
| Plustek OpticFilm 7400 v1 | `genesys` | 지원표에는 Complete지만 기종별 보정은 SANE 1.4.0 이후 반영됨 | capability 기반 경로, stock 1.4.0 실기 결과 미검증 |
| Plustek OpticFilm 8100, USB `07b3:130c` | `genesys` | Complete | 필름 전용 스캐너 경로 |
| Plustek OpticFilm 8100, USB `07b3:1824` | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| Plustek OpticFilm 8200i, USB `07b3:130d` | `genesys` | Complete | 필름 전용 스캐너 경로 |
| Plustek OpticFilm 8200i, USB `07b3:1825` (GL128) | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| Plustek OpticFilm 120, 120 Pro, 135, 135i, 9000i Ai | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| Epson Perfection V700/V750(GT-X900), V800/V850(GT-X980) | `epson2` | Good | 보고된 경우 투과 소스와 위치 지정 플랫베드 영역 사용 |
| Nikon Coolscan LS-2000, LS-40 ED, LS-50 ED, LS-4000 ED, LS-8000 ED | `coolscan3` | 기종에 따라 Complete~Minimal | 필름 전용 스캐너 경로 |
| Nikon Coolscan LS-5000 ED | `coolscan3` | SANE 1.4 기준 미검증, LS-50과 비슷하게 동작할 수 있음 | 필름 전용 스캐너 경로 |
| Nikon Coolscan LS-20, LS-30, LS-1000 | `coolscan` | 기종별로 다름 | SCSI 전용 |
| Nikon Coolscan LS-9000 ED | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| Reflecta ProScan/CrystalScan/DigitDia, PIE PowerSlide | `pieusb`, 구형 SCSI는 `pie` | 기종과 모델 번호에 따라 다름 | 보고된 옵션만 사용 |
| Pacific Image PrimeFilm XA, XAs, XA Plus | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| 그 밖의 투과 원고용 플랫베드·필름 스캐너 | 백엔드별로 다름 | 기종별로 다름 | 기능 보고 기준, 모델명 fallback 없음 |

## 제품명은 하드웨어를 알려주지 않습니다

OpticFilm 8100과 8200i는 각각 같은 제품명 아래 USB 변형이 적어도 두 가지 있습니다. `07b3:130c`와
`07b3:130d`는 `genesys`가 다루지만, `07b3:1824`와 `07b3:1825`는 어느 백엔드도 다루지 못하는 다른
Genesys 칩을 씁니다. 옛 이름 그대로 판매되는 새 리비전은 SANE 쪽에서 해결할 수 없으므로, 본체에
적힌 이름이 아니라 실제 USB product ID를 확인해야 합니다.

식별을 어렵게 하는 함정이 두 가지 더 있습니다.

- `pieusb`는 USB ID와 **모델 번호**를 함께 봅니다. Reflecta와 PIE 기기는 `05e3:0145`처럼 같은
  ID를 공유하므로, 모델 번호가 `pieusb.conf`에 있어야만 사용할 수 있습니다.
- `epson2`는 Epson 스캐너를 일본 모델명으로 인식합니다. `scanimage -L`은 Perfection V800/V850을
  `GT-X980`, V700/V750을 `GT-X900`으로 표시합니다. 같은 스캐너입니다.

## 적외선 채널

여기서 “IR 사용 가능”은 별도 적외선 이미지를 `irPath`로 negaflow에 넘길 수 있다는 뜻입니다.
백엔드 안에서만 작동하는 먼지 제거 옵션은 IR 채널로 보고하지 않습니다.

| 스캐너·백엔드 경로 | IR 상태 | 획득 방법 | 별도 IR TIFF |
|---|---|---|---|
| OpticFilm 7200, 7200 v2, 7300, 7400, 8100 | 사용 불가 | IR 소스를 제공하지 않는 기종 | 없음 |
| OpticFilm 7200i, 7500i, 7600i, 8200i `07b3:130d` | `scanimage -A`에 IR 소스가 나오면 사용 가능 | `Transparency Adapter Infrared` 별도 패스 | 있음 |
| OpticFilm 8200i `07b3:1825` | 사용 불가 | SANE 1.4 미지원 변형 | 없음 |
| `mac26` 설치본의 Epson V700/V750/V800/V850 | `scanimage -A`가 적외선 모드를 보고하면 사용 가능 | 패치된 `epson2`의 `Infrared` 모드 별도 패스 | 있음 |
| 기본 `epson2`의 Epson V700/V750/V800/V850 | 사용 불가 | 기본 빌드는 `SANE_FRAME_IR`이 빠진 채 컴파일됨 | 없음 |
| `--infrared`를 제공하는 Nikon `coolscan3` | 기본 `scanimage` 경로에서는 사용 불가 | `coolscan3`는 `SANE_FRAME_RGBI` 한 프레임을 반환하지만 `scanimage` 1.4는 이를 RGB와 IR TIFF로 분리하지 못함 | 없음 |
| `--clean-image`만 제공하는 Reflecta/PIE | IR 채널로는 사용 불가 | 먼지 제거가 백엔드 안에서 끝남 | 없음 |
| 그 밖의 스캐너 | 조건부 | `scanimage -A`에 활성 상태의 별도 IR source 또는 mode가 있을 때만 | 크기·형식 확인 후 있음 |

IR 패스에는 RGB와 같은 요청 해상도와 스캔 영역을 사용하고, 두 파일의 실제 픽셀 크기가 같은지 확인한
뒤 반환합니다. negaflow는 이 IR 이미지를 GrainMend IR에 사용할 수 있습니다.
