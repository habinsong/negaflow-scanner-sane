# Spike 체크리스트

기준일: 2026-08-04
상태: 실행 대기
목적: 문서 전체에 흩어진 미확인 항목을 한 곳에 모아 실행 순서를 정한다

## 표기

- **차단**: 통과하지 못하면 그 단계를 진행할 수 없다
- **결정**: 결과가 설계 결정을 바꾼다
- **정보**: 결과를 알면 좋지만 진행을 막지 않는다

### 별칭

같은 실험이 두 문서에서 다른 ID로 불린다. **한 번만 수행하고 결과를
양쪽에 기록한다.**

| 별칭 | 정본 | 내용 |
|---|---|---|
| U-4 | S-4 | 장치명 형식 (U-4는 S-1의 부산물로 기술됨) |
| DC-3 | U-5 | 동시 열기 오류 문구 |
| E-3 | S-6 | 로케일 고정 |
| N-2 | I-2 | `writeRGB16TIFF` 산출물 바이트 |

## Gate 0 — 프로젝트 실행 가능성

| ID | 항목 | 등급 | 소유 문서 |
|---|---|---|---|
| **S-2** | MSYS2 `scanimage.exe`가 stdout으로 바이트 정확한 TIFF를 내는가 | **차단** | [runtime-route-decision](../01-sane-runtime/runtime-route-decision.md) §5 |
| **S-1** | MSYS2 `scanimage.exe`가 실제 대상 스캐너를 열고 스캔하는가 | **차단** | [runtime-route-decision](../01-sane-runtime/runtime-route-decision.md) §5 |
| **D-1** | 코드 서명 인증서를 확보할 수 있는가 / 호스트가 요구하는가 | **차단** | [signing-and-trust](../07-distribution/signing-and-trust.md) §12 |

### S-2 상세

```text
가장 먼저 실행한다. 30분이면 끝난다.

1. MSYS2 설치, pacman -S mingw-w64-ucrt-x86_64-sane
2. (스캐너 없이도 가능) test 백엔드가 없으므로 실제 장치 필요.
   또는 소스 감사만 먼저:
     grep -n "_setmode\|_O_BINARY\|setmode" frontend/scanimage.c
3. 실제 스캔:
   scanimage.exe -d <dev> -p --format=tiff --resolution 300 > test.tif
4. 검증:
   - 파일 크기 == 예상 픽셀 바이트 + 헤더
   - tiffinfo가 열 수 있는가
   - 0x0A 앞에 0x0D가 삽입된 패턴이 있는가
5. 파이프로 받았을 때도 동일한가
```

**실패 시**: `--output-file` 옵션 존재 확인 → 없으면 패치 필요 →
[building-sane](../01-sane-runtime/building-sane.md) §5

### S-1 상세

```text
1. Zadig 2.9로 대상 스캐너에 WinUSB 바인딩
2. scanimage.exe -f "%d\t%v\t%m\t%t%n"
3. scanimage.exe -A -d <dev>          → 전문 저장
4. scanimage.exe -d <dev> -p --format=tiff --resolution 1200 > test.tif
5. 각 단계 소요 시간, stderr, scanimage --version 기록
```

**우선 장치**: Plustek OpticFilm 8200i 또는 Nikon Coolscan LS-50.
둘 다 없으면 genesys 계열 아무거나.

### D-1 상세

```text
1. negaflow 호스트 팀에 확인:
   "플러그인에 Authenticode 서명을 요구하는가? 필수인가 선택인가?"
2. Azure Trusted Signing의 개인 개발자 자격 요건 확인
3. 대안 CA(DigiCert, SSL.com)의 요건과 비용
4. HSM/토큰 없이 CI에서 서명할 경로가 있는가
```

## Gate 1 — 경로 확정

| ID | 항목 | 등급 | 소유 문서 |
|---|---|---|---|
| **S-4 / U-4** | Windows SANE 장치명 형식 | 결정 | [device-identity](../02-frontend-contract/device-identity.md), [usb-transport](../01-sane-runtime/usb-transport.md) §8 |
| **S-6 / E-3** | `LC_ALL=C`가 `scanimage` 메시지를 영어로 고정하는가 | 결정 | [exact-option-contract](../02-frontend-contract/exact-option-contract.md) §6 |
| **E-2** | `SANE_CONFIG_DIR`의 Windows 경로가 잘리지 않는가 | 결정 | [environment-and-paths](../03-process-and-io/environment-and-paths.md) §9 |
| **E-1** | `dll` 백엔드가 백엔드 DLL을 어느 경로에서 찾는가 | 결정 | [environment-and-paths](../03-process-and-io/environment-and-paths.md) §9 |
| **U-5 / DC-3** | 동시 열기 실패의 오류 문구 | 결정 | [usb-transport](../01-sane-runtime/usb-transport.md) §8 |

### E-2가 특히 중요하다

```text
SANE는 SANE_CONFIG_DIR를 ':'로 분리하는 검색 경로로 다룰 수 있다.
"C:\Users\..." 의 "C:"가 잘리면 설정을 못 찾는다.

1. SANE_CONFIG_DIR="C:\test\sane.d" 설정
2. Process Monitor로 scanimage.exe -L 실행 추적
3. 어느 경로를 여는지 확인
4. 잘린다면 sanei/sanei_config.c 확인
```

**이것이 Windows 이식을 실제로 막을 수 있는 구체적 함정이다.**

### S-6 상세

```text
한국어 Windows에서:
1. $env:LC_ALL="C"; scanimage.exe --help      → 영어인가
2. 존재하지 않는 장치로 -A                     → 오류가 영어인가
3. step에 안 맞는 해상도 요청                  → "rounded value of"가 나오는가
4. LANGUAGE, LANG도 시도
5. 실패 시 gettext 카탈로그가 빌드에 포함됐는지 확인
```

**실패하면** 반올림 감지, `busy` 분류, stale 판정이 전부 무력화된다.
대체 감지 경로가 필요하다.

## Gate 2 — 이미징 동등성

| ID | 항목 | 등급 | 소유 문서 |
|---|---|---|---|
| **N-1** | Core Image 로드 경로와 직접 uint16 읽기가 같은 float를 만드는가 | **차단(M4)** | [numerical-parity](../04-imaging/numerical-parity.md) §3.2 |
| **I-2 / N-2** | `writeRGB16TIFF` 산출물의 실제 바이트 | 결정 | [tiff-validation](../04-imaging/tiff-validation.md) §8 |
| **N-4** | `estimateIntegerOffset`가 두 구현에서 같은 정수를 내는가 | **차단(M4)** | [numerical-parity](../04-imaging/numerical-parity.md) §4 |
| **N-3** | 병합 파이프라인 전체가 픽셀 단위로 같은가 | **차단(M4)** | [numerical-parity](../04-imaging/numerical-parity.md) §3.1 |
| **I-1** | `scanimage` gray 출력의 photometric | 정보 | [tiff-validation](../04-imaging/tiff-validation.md) §8 |
| **I-4** | 4 GB TIFF 한계(120 포맷 고해상도) | 결정 | [tiff-validation](../04-imaging/tiff-validation.md) §8 |
| **I-3** | libtiff 산출물을 WIC가 읽는가 | 정보 | [tiff-validation](../04-imaging/tiff-validation.md) §8 |

### N-1 상세

```text
macOS에서만 실행하면 된다. Windows 장비가 필요 없다.

1. 알려진 픽셀 값을 가진 16-bit RGB TIFF 생성
   값: 0, 1, 2, 255, 256, 32767, 32768, 65534, 65535
2. TIFFLoader.loadScannerTIFF + renderRGBAf 실행
3. 결과 [Float]의 비트 패턴을 hex로 덤프
4. Float(v) / 65535.0 의 비트 패턴과 비교
```

**M4를 시작하기 전에 반드시 한다.** 결과가 M4의 규모를 결정한다.

#### 결과 — 통과 (2026-08-05)

9개 값 전부 **비트 단위로 일치**했다. 최대 절대 오차 0.

```text
value       loaded float   bits       v/65535.0     bits
    0      0.000000000  00000000    0.000000000  00000000
    1      0.000015259  37800080    0.000015259  37800080
  255      0.003891051  3b7f00ff    0.003891051  3b7f00ff
32767      0.499992371  3effff00    0.499992371  3effff00
32768      0.500007629  3f000080    0.500007629  3f000080
65535      1.000000000  3f800000    1.000000000  3f800000
```

즉 `CIImage(cgImage:options:[.colorSpace: linearSRGB])` + `CIContext.render(.RGBAf)`
는 **감마 변환을 하지 않고** 정확히 `Float(v) / 65535.0` 을 만든다.

**M4 가 커지지 않는다.** Windows 는 Core Image 동작을 모사할 필요 없이
`float(v) / 65535.0f` 로 구현하면 된다. numerical-parity §7 의 선택지
(a)/(b)/(c) 중 어느 것도 발동하지 않는다.

### N-4 / N-3 상세

N-1과 달리 이 둘은 **이식 코드가 있어야 실행할 수 있다.** 그래서
`imaging/align`·`imaging/merge`를 옮긴 뒤 파리티 하네스로 돌린다.

```text
macOS에서만 실행하면 된다. Windows 장비가 필요 없다.

1. 합성 입력을 두 언어에서 **비트 단위로 같게** 만든다
   → 부동소수점 난수 대신 32비트 정수 해시로 값을 생성한다
     (unsigned 모듈러 연산은 Swift &*/&+ 와 C++ 가 동일하게 정의)
2. 같은 입력을 Swift 원본과 C++ 이식에 먹인다
   → parity-check.sh 가 @testable import 로 **저장소의 실제 Swift** 를 링크한다
3. N-4: estimateIntegerOffset 의 (dx, dy) 를 비교
   N-3: 병합 결과를 float 비트 패턴과 UInt16 **양쪽**으로 비교
```

**float와 UInt16을 둘 다 봐야 한다.** 양자화가 절삭이라 1 ULP 차이는
대개 같은 `UInt16`으로 떨어진다.

#### 결과 — 통과 (2026-08-05)

```text
N-4  정렬 9 케이스 전부 일치
     시프트 복원: (2,0)→(-2,0), (-3,5)→(3,-5), factor 2 에서 (4,-6)→(-4,6)
     조기 종료 경로: 동일 이미지, 평탄 이미지, dw<=6, dh<=6
     정렬되지 않는 노이즈를 섞은 케이스 포함

N-3  병합 6 케이스 전부 일치 (float 비트 패턴 + UInt16)
     3패스 / 6패스(samplesPerStop=2) / 단일 패스 / 짧은 노출 없음 / 긴 노출 없음
     패스별 시프트가 있는 케이스 포함
     신뢰 가중치 5분기를 전부 지나는 합성 입력
     평균 경로(averageMultiSampleBitmap)도 함께 대조
```

**한계를 정직하게**: 이것은 macOS에서 C++와 Swift를 대조한 결과이지
Windows에서 컴파일한 결과가 아니다. MSVC `/fp:precise`가 clang
`-ffp-contract=off`와 같은 값을 내는지는 미확인이다.

이 spike를 돌리는 과정에서 **하네스 자체의 결함**을 찾았다 —
`parity-check.sh`가 `-ffp-contract=off` 없이 컴파일하고 있었다.
[field-lessons](../10-lessons/field-lessons.md) §9b.2.

## Gate 3 — 프로세스와 취소

| ID | 항목 | 등급 | 소유 문서 |
|---|---|---|---|
| **C-1** | `scanimage.exe`가 `CTRL_BREAK_EVENT`에 반응하는가 | 결정 | [cancellation](../03-process-and-io/cancellation.md) §10 |
| **C-2** | 강제 종료 후 장치가 즉시 다시 열리는가 | 결정 | [cancellation](../03-process-and-io/cancellation.md) §10 |
| **C-3** | 취소 지연 측정 | 정보 | [cancellation](../03-process-and-io/cancellation.md) §10 |
| **C-4** | 다중 패스 중 취소 시 정리 | 정보 | [cancellation](../03-process-and-io/cancellation.md) §10 |
| **T-1** | 첫 진행률까지의 시간 분포 | 결정 | [timeouts-and-watchdog](../03-process-and-io/timeouts-and-watchdog.md) §6 |
| **T-2** | 진행률 간격 최댓값 | 결정 | 위와 같음 |
| **T-3** | 유틸리티 실행 시간 | 정보 | 위와 같음 |

### C-1이 취소 설계를 결정한다

```text
통과: graceful cancel이 가능하다. sane_cancel()이 호출된다.
실패: TerminateProcess만 남는다. 강제 종료 후 복구 절차가 필수가 된다.
```

## Gate 4 — USB와 드라이버

| ID | 항목 | 등급 | 소유 문서 |
|---|---|---|---|
| **U-1** | WinUSB 바인딩 후 VueScan/SilverFast가 동작하는가 | **결정(UX)** | [driver-conflicts](../09-hardware/driver-conflicts.md) §12 |
| **DC-2** | 드라이버 되돌리기가 재현 가능한가 | **차단(지원 범위)** | [driver-conflicts](../09-hardware/driver-conflicts.md) §12 |
| **U-3** | open 후 장치 주소가 바뀌는가 | 정보 | [usb-transport](../01-sane-runtime/usb-transport.md) §8 |
| **DC-1** | CfgMgr32로 드라이버 상태 조회 | 정보 | [driver-conflicts](../09-hardware/driver-conflicts.md) §12 |
| **DC-3** | 동시 열기 오류 문구 (= U-5) | 결정 | [driver-conflicts](../09-hardware/driver-conflicts.md) §12 |
| **U-2** | usbipd/WSL2에서 genesys 스캔 후 연결 끊김 | 결정(B 경로) | [usb-transport](../01-sane-runtime/usb-transport.md) §8 |

### U-1이 UX 결론을 바꾼다

```text
통과: Coolscan/Plustek 사용자의 실질 손실이 0이다.
      설치 경고를 크게 완화할 수 있다.
실패: 사용자가 VueScan을 잃는다. 경고가 강해야 한다.
```

### DC-2가 지원 범위를 정한다

```text
대상 장치 3종 이상에서:
1. 벤더 드라이버 상태 기록
2. WinUSB 바인딩
3. 장치 관리자에서 되돌리기 시도
4. 이전 드라이버가 목록에 나타나는가
5. 나타나지 않으면 제조사 설치 프로그램 재실행으로 복구되는가

5번이 실패하는 장치는 지원 대상에서 제외한다.
```

## Gate 5 — 빌드와 배포

| ID | 항목 | 등급 | 소유 문서 |
|---|---|---|---|
| **B-1** | `scanimage` TIFF writer의 압축 | 정보 | [toolchain-and-layout](../06-build/toolchain-and-layout.md) §10 |
| **B-2** | MSVC `std::to_chars(double)` 지원 | 정보 | 위와 같음 |
| **B-3** | GitHub Actions ARM64 Windows 러너 | 결정 | 위와 같음 |
| **B-4** | 정적 링크 산출물 크기 | 정보 | 위와 같음 |
| **D-2** | SmartScreen 동작 | 정보 | [signing-and-trust](../07-distribution/signing-and-trust.md) §12 |
| **D-3** | `activeCodePage: UTF-8`의 영향 | 정보 | 위와 같음 |
| **E-4** | 임시 파일 위치별 처리량 | 결정 | [environment-and-paths](../03-process-and-io/environment-and-paths.md) §9 |

## Gate 6 — 낮은 우선순위

| ID | 항목 | 등급 | 소유 문서 |
|---|---|---|---|
| S-3 | WSL2 경로 전반 안정성 | 정보(B 경로 대비) | [runtime-route-decision](../01-sane-runtime/runtime-route-decision.md) §3.2 |
| S-5 | WSL2에서 SCSI 패스스루 | 정보 | [validation-matrix](../09-hardware/validation-matrix.md) §6 |
| S-6b | Cygwin에서 SANE가 언제 빠졌는가 | 정보 | [availability](../01-sane-runtime/availability.md) |
| S-7 | WiaSane의 Windows 10/11 서명 상태 | 정보 | [availability](../01-sane-runtime/availability.md) §3.5 |
| S-8 | SANEWinDS의 프로그래밍 API | 정보 | [remote-saned](../01-sane-runtime/remote-saned.md) §6 |

**이 다섯은 "답을 알면 좋은 것"이지 진행을 막지 않는다.** S-6b·S-7·S-8은
경쟁 경로 조사이므로, A 경로가 확정되면(D-01) 답할 필요가 없어진다.

## 실행 순서

```text
[장비 없이 지금 할 수 있는 것]
  N-1   (macOS만 필요)
  I-2   (macOS만 필요)
  D-1   (조사)
  B-2, B-3  (조사)
  scanimage.c 소스 감사 (S-2 사전 조사, E-2 사전 조사)

[Windows PC만 있으면]
  MSYS2 설치
  E-2, E-1  (스캐너 없이 가능)
  D-2, D-3

[스캐너가 있으면]
  S-2 → S-1 → S-4 → S-6 → U-5
  U-1, DC-1, DC-2, U-3
  C-1 → C-2 → C-3 → C-4
  T-1, T-2, T-3
  I-1, I-4
  B-1, E-4
```

**N-1과 소스 감사는 오늘 시작할 수 있다.**

## 결과 기록

각 spike의 결과를 이 파일에 직접 기록한다.

```text
| ID | 상태 | 날짜 | 결과 요약 | 상세 |
|---|---|---|---|---|
| S-2 | 대기 | — | — | — |
| N-1 | 대기 | — | — | — |
...
```

**"대기 / 진행 / 통과 / 실패 / 조건부"** 다섯 상태를 쓴다.
실패한 spike는 지우지 않는다. 왜 그 경로를 택하지 않았는지의 기록이 된다.

## 결과 표

| ID | 상태 | 날짜 | 결과 |
|---|---|---|---|
| S-1 | 대기 | | |
| S-2 | 대기 | | |
| S-3 | 대기 | | |
| S-4 | 대기 | | |
| S-5 | 대기 | | |
| S-6 | 대기 | | |
| S-6b | 대기 | | |
| S-7 | 대기 | | |
| S-8 | 대기 | | |
| E-1 | 대기 | | |
| E-2 | 대기 | | |
| E-3 | 대기 | | |
| E-4 | 대기 | | |
| N-1 | **통과** | 2026-08-05 | 9/9 비트 동일. M4 규모 증가 없음 |
| N-2 | **통과** | 2026-08-05 | I-2 와 동일(별칭). 이후 양방향 상호운용까지 확인 |
| N-3 | **통과** | 2026-08-05 | 병합 6 케이스. float 비트 + UInt16 양쪽 일치 |
| N-4 | **통과** | 2026-08-05 | 정렬 9 케이스. 시프트 복원·조기 종료 경로 포함 |
| I-1 | 대기 | | |
| I-2 | **통과** | 2026-08-05 | MM big-endian, ICC/TransferFunction 없음 |
| I-3 | 대기 | | |
| I-4 | 대기 | | |
| C-1 | 대기 | | |
| C-2 | 대기 | | |
| C-3 | 대기 | | |
| C-4 | 대기 | | |
| T-1 | 대기 | | |
| T-2 | 대기 | | |
| T-3 | 대기 | | |
| U-1 | 대기 | | |
| U-2 | 대기 | | |
| U-3 | 대기 | | |
| U-4 | 대기 | | |
| U-5 | 대기 | | |
| DC-1 | 대기 | | |
| DC-2 | 대기 | | |
| DC-3 | 대기 | | |
| B-1 | 대기 | | |
| B-2 | 대기 | | |
| B-3 | 대기 | | |
| B-4 | 대기 | | |
| D-1 | 대기 | | |
| D-2 | 대기 | | |
| D-3 | 대기 | | |
