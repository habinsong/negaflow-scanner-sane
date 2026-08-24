# Windows 실기 검증 범위

기준일: 2026-08-25

## 확인된 장치

| 장치 | 프리뷰 | 본스캔 | 여러 DPI | Color/Gray·심도 | IR |
| --- | --- | --- | --- | --- | --- |
| Plustek OpticFilm 8100 | 성공 | Color 성공 | Color 600/1200/2400/3600/7200 성공 | Color 16-bit 성공. Gray 16-bit 는 원본에서 정지했고 patch 011(HOST_SIDE_GRAY + GL846 출력 길이) 뒤 **설치본에서 연속 2회 성공** (16,658/16,781ms, 1,010,302B, SPP 1, 예고=실제). Color 16-bit 회귀 성공 | 미지원 장치 |
| Epson Perfection V700 (`GT-X900`) | 성공 | 성공 | 성공 | 600 DPI 10×10mm에서 Color/Gray × 8/16-bit 4조합 성공 | Color 16-bit RGB/IR 쌍과 Negaflow host 저장→catalog→재열기 성공 |

이 표는 실제 사용 결과입니다. 색 정확도, 장기 안정성, 다른 USB 컨트롤러, 다른 드라이버와 모든 해상도를 보증하지 않습니다.

### Negaflow host 종단 (2026-08-25, 설치 플러그인 경로)

`--scanner-live-end-to-end`로 실제 plugin→staging/commit→catalog publication→catalog
재열기까지 돌린 결과입니다. 네 조합 모두 `status ok`, requested/published **1/1**, `Completed`.

| 장치 | 모드 | 저장 프로세스 | metadata | source bytes |
| --- | --- | --- | --- | --- |
| Plustek OpticFilm 8100 | gray | `bw-negative` | 856×590, SPP **1**, 16-bit | 1,010,302 |
| Plustek OpticFilm 8100 | color | `color-negative` | 856×590, SPP 3, 16-bit | 3,030,480 |
| Epson GT-X900 | gray | `bw-negative` | 232×236, SPP **1**, 16-bit | 109,726 |
| Epson GT-X900 | color | `color-negative` | 232×236, SPP 3, 16-bit | 328,752 |

렌더링된 설치 WinUI 화면은 포함하지 않습니다. 그 확인은 사용자 QA 범위입니다.

### OpticFilm 계열 중 `HOST_SIDE_GRAY` 를 켜지 않은 행

증거는 8100 한 대뿐이므로 나머지 행은 켜지 않았습니다. host-side Gray 는 3채널을 획득하므로
native Gray 가 되는 장치에 켜면 느려지는 회귀입니다. 각 행은 **그 장치의 실제 스캔 결과**가
있을 때만 켭니다.

| 모델 | ASIC | 상태 |
| --- | --- | --- |
| 7200 | GL842 | 미검증 |
| 7200i / 7200-v2 / 7300 / 7400-v1 / 7500i / 7600i-v1 | GL843 | 미검증 |
| 7400-v2 | GL845 | 켜짐 (8100 이 이 행을 상속) |
| 8100 | GL845 | 켜짐 · 실기 증거 |
| 8200i / 7600i-v2 | GL845 | 미검증 |

## 각 장치에서 남은 확인

- (닫힘 2026-08-25) `HOST_SIDE_GRAY` 설치본의 Gray 16-bit 연속 2회와 Color 16-bit 회귀
- 스캔 중 취소 후 바로 다음 스캔
- USB 분리·재연결 뒤 detect와 scan
- 다른 스캔 프로그램이 장치를 점유한 상태의 오류
- 같은 조건의 반복 스캔
- 결과 TIFF의 크기·심도·색 모델과 요청 옵션 일치. Gray는 예고 바이트와 실제
  바이트도 일치해야 하며 3배 trailing data를 허용하지 않음

## 기록할 정보

- 장치명, Windows 버전, 아키텍처, 드라이버 상태
- `scanimage -f`와 `scanimage -A` 출력
- 요청한 DPI·색상·IR·스캔 영역
- 결과 TIFF의 크기·심도·색 모델
- 실패 시 exit code와 stderr
