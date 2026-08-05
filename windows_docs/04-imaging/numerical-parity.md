# 수치 동등성

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 검증 명세
목적: 같은 입력에 대해 macOS와 Windows 구현이 같은 출력을 낸다는 것을 증명한다

관련 문서:

- [exposure-merge](exposure-merge.md)
- [tiff-validation](tiff-validation.md)
- [option-dump-parser](../02-frontend-contract/option-dump-parser.md)
- [conformance-fixtures](../05-protocol/conformance-fixtures.md)

## 0. N-1 결과 — 통과 (2026-08-05)

**이 문서의 가장 큰 위험이 해소됐다.**

16-bit TIFF 를 `TIFFLoader.loadScannerTIFF` 로 읽고 `renderRGBAf` 로 렌더한
결과가 `Float(v) / 65535.0` 과 **9개 값 전부 비트 단위로 일치**했다
(0, 1, 2, 255, 256, 32767, 32768, 65534, 65535 / 최대 오차 0).

즉 Core Image 로드 경로는 **감마 변환도 색 변환도 하지 않는다.** 단순
정규화다.

```cpp
// Windows 구현은 이것으로 충분하다. Core Image 를 모사할 필요가 없다.
float toLinear(uint16_t v) { return static_cast<float>(v) / 65535.0f; }
```

§7 의 선택지 (a) macOS 변경 / (b) Core Image 모사 / (c) 허용 오차 도입 중
**어느 것도 발동하지 않는다.** roadmap 의 "N-1 실패 시 M4 대폭 증가" 위험도
해소됐다.

상세: [spike-checklist](../99-plan/spike-checklist.md) N-1

### 0.1 N-3 / N-4 결과 — 통과 (2026-08-05)

`imaging/align`과 `imaging/merge`가 이식됐고, 파리티 하네스가 **저장소의
실제 Swift 구현**과 대조한다.

```text
N-4  정렬     estimateIntegerOffset 9 케이스 전부 같은 (dx, dy)
              시프트 복원 확인: (-3,5) → (3,-5), factor 2 케이스 포함
              평탄 이미지·좁은 이미지·정렬되지 않는 노이즈 포함

N-3  병합     mergeHardwareExposureBitmap 6 케이스
              float 결과(비트 패턴)와 UInt16 결과를 **둘 다** 대조
              신뢰 가중치 5분기를 전부 지나는 합성 입력

N-2  입출력   양방향 상호운용 (아래 §0.3)
```

**float와 UInt16을 둘 다 비교하는 것이 중요하다.** 양자화가 절삭이라
1 ULP 차이는 대개 같은 `UInt16`으로 떨어진다. UInt16만 보면 놓친다.

남은 한계는 정직하게: 이것은 **macOS에서 C++와 Swift를 대조한 것**이고,
Windows에서 컴파일한 결과를 대조한 것이 아니다.

**다만 "`/fp:precise` 면 되겠지"는 이제 아니라는 것이 확인됐다**(2026-08-05
조사). §5 를 볼 것 — `#pragma fp_contract(off)` 를 강제 포함으로 넣었다.

### 0.2 CIImage RGBAf 왕복은 항등이다 (2026-08-05, 실측)

Swift 쪽 병합 진입점이 `[CIImage]`를 받으므로, 파리티는 합성 `[Float]`를
CIImage로 감싸 넣는다. 그 왕복이 값을 바꾸면 비교가 무의미해진다.

```text
[Float] → CIImage(bitmapData:, format: .RGBAf, colorSpace: linearSRGB)
        → renderRGBAf → [Float]

결과: 전부 비트 동일
      Y 뒤집힘 없음 (extent = (0,0,4,3), 행 순서 보존)
      1 초과 값 보존 (2.75 → 2.75)
      음수 값 보존 (-0.25 → -0.25)  ← 클램프하지 않는다
      알파 보존
```

**음수와 1 초과가 보존된다는 것이 특히 중요하다.** `normalizeExposure`가
짧은 노출을 1 이상으로 밀어 올리므로, 여기서 클램프가 걸렸다면 병합
결과가 통째로 달라졌을 것이다.

### 0.3 N-2 — 양방향 상호운용까지 확인했다 (2026-08-05)

§5 의 N-2 는 "macOS 가 쓴 것을 Windows 가 같게 읽는가"만 요구했다.
`imaging/tiff_io` 를 이식하면서 **반대 방향까지** 대조했다.

```text
libtiff 로 쓴 파일   → macOS ImageIO 로 읽기   픽셀 비트 동일
ImageIO 로 쓴 파일   → libtiff 로 읽기         픽셀 비트 동일
```

읽어 온 float 는 N-1 이 기록한 표와 **같은 비트 패턴**이다
(`0 → 00000000`, `32767 → 3effff00`, `65535 → 3f800000`).

파일 바이트는 다르다 — libtiff `II` 314 B, ImageIO `MM` 338 B.
§5 가 "바이트 순서가 달라도 픽셀 값이 같으면 통과"로 정해 둔 그대로이며,
그래서 SHA-256 비교가 아니라 디코드 후 픽셀 비교를 한다.

행마다 값을 다르게 준 픽스처라 **행 순서도 함께 검증된다.** 처음에는 모든
행이 같은 픽스처를 썼는데, 그러면 위아래 뒤집힘이나 행 stride 오류를
통과시킨다는 것을 깨닫고 고쳤다.

출력 TIFF의 색 태그 계약(프로파일을 넣지 않는다)은
[host-pipeline-contract](../10-lessons/host-pipeline-contract.md) §2가 소유한다.
수치가 같아도 태그가 붙으면 본체가 다른 도메인으로 읽는다.

## 1. 목표를 정확히 정한다

이식에서 "같다"에는 세 등급이 있다. 항목마다 어느 등급을 요구하는지 정한다.

| 등급 | 정의 | 적용 |
|---|---|---|
| **P0 비트 동일** | 출력 바이트가 완전히 같다 | 다중 노출 병합 결과, 정렬 오프셋 |
| **P1 결정 동일** | 판정(통과/거부, 선택된 값)이 같다 | 옵션 파싱, 능력 산출, 인자 생성 |
| **P2 허용오차 내** | 지정된 오차 안 | (해당 없음 — 쓰지 않는다) |

**P2를 쓰지 않는 것이 이 문서의 입장이다.** 이미지 처리에서 "거의 같다"를
허용하기 시작하면 어디까지가 허용인지 정할 근거가 없어진다. 병합은
결정론적 산술이므로 비트 동일이 달성 가능하다.

## 2. P1 — 결정 동일

### 2.1 대상

```text
SaneOptionDump 전체
resolveMedia 전체
parseCapabilities 전체
validateExactOptions 전체
makeScanimageArgs 전체
epson2AlignedHeightMM
pixelGeometryValue / pixelGeometryLength
containsExactly
```

### 2.2 위험 요소

**부동소수점 파싱**

```text
"36.33" → 36.33
```

- 로케일 독립이어야 한다. `strtod` with `"C"` locale,
  `std::from_chars`, `double.Parse(s, CultureInfo.InvariantCulture)`.
- **정확 왕복**이어야 한다. `36.33`을 파싱한 결과가 Swift `Double("36.33")`과
  비트 동일해야 `containsExactly` 판정이 같다.
- IEEE 754 binary64의 올바른 반올림 파싱은 표준이 요구하는 동작이며
  주요 구현이 모두 만족한다. `atof`의 구형 구현만 주의한다.

**부동소수점 포맷**

```text
36.33 → "36.33"
36.0  → "36"
```

`saneNumber`의 규칙은
[scanimage-invocation](../02-frontend-contract/scanimage-invocation.md) §2.2에 있다.
왕복 최단 표현이 기준이다.

**반올림**

```text
containsExactly: abs(offset - offset.rounded()) <= 1e-7
pixelGeometryValue: exactPixels.rounded()
epson2AlignedHeightMM: bottom.rounded(.up) / bottom.rounded(.down)
```

Swift `rounded()`는 half-away-from-zero다.

| 언어 | 대응 |
|---|---|
| C/C++ | `std::round` (같음) |
| C# | `Math.Round(x, MidpointRounding.AwayFromZero)` — **기본 `Math.Round(x)`는 half-to-even이라 다르다** |
| Rust | `f64::round` (같음) |

`rounded(.up)` = `std::ceil`, `rounded(.down)` = `std::floor`.

**연산 순서**

```text
mm * dpi / 25.4         ← 이 순서
(value - minimum) / step ← 이 순서
```

수학적으로 동등한 재배열이 부동소수점에서는 다른 결과를 낸다.
**소스 코드의 순서를 그대로 옮긴다.**

**컴파일러 최적화**

```text
MSVC:       /fp:precise + **#pragma fp_contract(off)**   ← 둘 다 필요하다
GCC/Clang:  -ffp-contract=off, -fno-fast-math
```

FMA 축약(`a*b + c`를 단일 명령으로)은 중간 반올림을 제거해 결과를 바꾼다.
정확도가 **올라가지만 다르다.** 동등성이 목표이므로 끈다.

**`/fp:precise` 만으로는 안 된다 — 2026-08-05 조사로 확인.**
이 문서는 원래 "`/fp:precise` (기본)"이라고만 적고 있었고, 그것을 믿고
CMakeLists 에도 "기본이지만 명시한다"고 주석이 달려 있었다. **VS 2022 에서만
맞다.**

```text
                /fp:precise 의 기본 fp_contract
VS 2019 이하     on      ← 축약이 일어난다
VS 2022 17.0+    off
```

VS 2019 의 축약은 플랫폼마다 달랐다.

```text
ARM64   스칼라와 벡터 FMA 를 **둘 다** 낸다. /arch 플래그도 필요 없다
        (FMADD 가 armv8.0-A 기본이다)
x64     벡터 FMA 만. 그것도 /arch:AVX2 이상일 때만
```

즉 **VS 2019 + ARM64 에서 `a + b*c` 는 그냥 FMA 가 된다.** `imaging/align`
과 `imaging/merge` 가 정확히 그 형태를 쓴다.

끄는 방법이 하나뿐이라는 것도 확인됐다.

```text
/fp:contract-                    **그런 플래그는 없다** (켜는 형태만 있다)
/fp:strict                       끄기는 하지만 예외 처리까지 켜서 대가가 크다
#pragma float_control(precise,on) VS 2019 에서는 축약에 영향이 없다
#pragma fp_contract(off)         **VS 2019/2022, x64/ARM64 전부에서 통한다**
```

MSVC 문서의 예제가 `/O2 /fp:fast /arch:AVX2` 로 컴파일해도 FMA 가 나오지
않음을 보인다 — `/fp:fast` 보다 세다.

CMakeLists 가 `/FI windows/src/util/msvc_fp_contract.h` 로 **모든 번역
단위에 강제 포함한다.** 어느 파일이 민감한지 사람이 판단해 헤더를 넣게 하면
언젠가 빠뜨리고, 빠뜨려도 빌드는 통과하며 결과만 조용히 달라진다.

### 축약을 꺼도 남는 것

```text
std::fma 를 직접 부르면 그대로 FMA 다        양쪽 다 그러므로 문제없다
sin/cos/pow/exp/log 는 정확 반올림이 아니다   마지막 ulp 가 갈린다
long double 폭이 다르다                       우리는 쓰지 않는다
```

이 계층이 쓰는 것은 `+ - * / sqrt` 뿐이고 그것들은 IEEE-754 가 정확히
규정한다. **초월함수를 쓰기 시작하면 이 표를 다시 읽는다.**

**빌드뿐 아니라 검증 도구에도 같은 플래그를 건다.** `tools/parity-check.sh`가
이 플래그 없이 컴파일하고 있어서 `imaging/align`을 붙이자마자 1 ULP 차이로
터졌다. clang은 C++에서 `-ffp-contract=on`이 기본이다. 실제 사건 기록:
[field-lessons](../10-lessons/field-lessons.md) §9b.2.

### 2.3 검증 방법

**언어 중립 골든 파일**

```text
fixtures/media/
    genesys-opticfilm-8200i-color-16bit-3600dpi/
        input-dump.txt          scanimage -A 출력 전문
        input-options.json      ScanOptions
        input-devicetype.txt    "film scanner"
        expected-media.json     MediaSelection 전체 필드
        expected-args.json      makeScanimageArgs 결과 배열
        expected-validate.json  { "result": "ok" } 또는 { "error": "..." }
```

Swift 테스트와 Windows 테스트가 같은 디렉터리를 읽고 같은 결과를 낸다.

**생성 방법**: 현재 Swift 테스트에서 골든 파일을 덤프하는 모드를 추가한다.
`SANEBackendTests.swift`(880행)와 `SANEBackendVirtualScannerTests.swift`(358행)가
이미 이 데이터를 가지고 있으므로 추출이 어렵지 않다.

**MediaSelection 직렬화**: 현재 `Codable`이 아니다. 테스트용
직렬화를 추가한다. 필드 순서와 nil 표현(키 생략 vs `null`)을 고정한다.
**`null`을 명시하는 쪽을 선택한다** — 키 생략은 오타를 숨긴다.

## 3. P0 — 비트 동일

### 3.1 대상

```text
mergeHardwareExposureBitmap 결과 [UInt16]
averageMultiSampleBitmap 결과 [UInt16]
estimateIntegerOffset 결과 (Int, Int)
```

### 3.2 첫 번째 관문 — 로드 경로

```text
macOS:  TIFF → CGImage → CIImage(.colorSpace: linearSRGB)
              → CIContext(workingColorSpace: linear, outputColorSpace: linear)
                .render(toBitmap:, format: .RGBAf, colorSpace: linear)
              → [Float]

Windows: TIFF → libtiff uint16 → Float(v) / 65535.0
```

**두 경로가 같은 float를 만드는가?**

이것이 P0의 전제이며, 검증하지 않으면 나머지가 무의미하다.

**가설**: 입력 색공간, working 색공간, 출력 색공간이 모두 linearSRGB이므로
Core Image가 색 변환을 하지 않고, uint16을 `v / 65535.0`으로 정규화만 한다.

**검증 방법** (parity spike N-1):

```text
1. 알려진 픽셀 값을 가진 16-bit RGB TIFF를 만든다
   값: 0, 1, 2, 255, 256, 32767, 32768, 65534, 65535
   그리고 각 채널이 서로 다른 조합
2. macOS에서 TIFFLoader.loadScannerTIFF + renderRGBAf 실행
3. 결과 [Float]를 hex로 덤프 (비트 패턴)
4. Float(v) / 65535.0의 비트 패턴과 비교
```

**결과별 대응**:

| 결과 | 대응 |
|---|---|
| 정확히 일치 | Windows에서 직접 나눗셈. 가장 좋은 시나리오 |
| 정규화 방식이 다름 (예: `/65536.0`, `/32768.0`) | 그 방식을 그대로 구현 |
| 감마/색 변환이 개입 | **심각.** macOS 코드에 의도치 않은 변환이 있다는 뜻. 별도 조사 필요 |
| 미세한 차이 (ULP 수준) | 원인 파악. Core Image의 내부 정밀도 문제일 수 있음 |

**세 번째와 네 번째가 나오면 P0을 포기하고 P1으로 내려야 할 수 있다.**
그 경우 "Windows 결과가 macOS와 다르다"는 것을 제품 사실로 문서화하고,
어느 쪽이 옳은지 별도로 판단한다.

### 3.3 두 번째 관문 — 산술

로드가 같으면 나머지는 순수 산술이다. 다음을 지키면 비트 동일이 나온다.

- `Float`(binary32)를 쓴다. `double`로 승격하지 않는다.
- 연산 순서를 유지한다.
- FP 축약을 끈다.
- 누적 합의 순서를 유지한다(SIMD 금지 —
  [exposure-merge](exposure-merge.md) §7.4).
- `clamp`/`min`/`max`의 NaN 처리를 확인한다.
  Swift `min(max(v, 0), 1)`에서 `v`가 NaN이면 결과는 구현 정의다.
  입력에 NaN이 없어야 하지만 방어적으로 같은 순서를 유지한다.

### 3.4 세 번째 관문 — 쓰기

```text
UInt16(clamp(f, 0, 1) * 65535)
```

Swift `UInt16(Float)`는 **절삭**(truncation)이다. 반올림이 아니다.

```text
0.5 * 65535 = 32767.5 → UInt16 → 32767
```

C++ `static_cast<uint16_t>(f)`도 절삭이다. 같다.
C# `(ushort)f`도 절삭이다. 같다.

**`Math.Round` 후 캐스트로 "개선"하지 않는다.**

범위를 벗어난 값의 변환은 Swift에서 런타임 트랩이다. clamp가 선행하므로
발생하지 않지만, NaN이 들어오면 트랩한다. Windows에서는 UB다.
**clamp 전에 NaN 검사를 추가하는 것을 권장한다** — 양쪽 모두에.

### 3.5 검증

```text
fixtures/merge/
    3-exposure-basic/
        sample1.tiff  (11000)
        sample2.tiff  (14000)
        sample3.tiff  (30000)
        exposures.json
        expected.tiff
        expected-sha256.txt
```

**입력 TIFF는 합성한다.** 실제 스캔 결과는 크고 재현이 어렵다.
작은 합성 이미지(예: 64×64)로 알고리즘의 모든 분기를 통과하게 만든다.

포함해야 할 패턴:

- 클리핑 영역 (raw >= 0.985)
- 클리핑 경계 (0.90 ~ 0.985)
- 암부 (raw <= 0.006)
- 암부 경계 (0.006 ~ 0.035)
- 정상 영역
- 채널별로 다른 조합
- 정렬 오프셋이 발생하도록 샘플 간 이동이 있는 패턴
- 텍스처가 부족해 정렬이 (0,0)으로 빠지는 평탄한 패턴
- 극단 오프셋(범위 밖 소스 참조)

## 4. 정렬 결과의 동등성

`estimateIntegerOffset`은 정수를 돌려주므로 비트 동일 판정이 쉽다.
그러나 내부의 부동소수점 비교(`error < bestError`)가 미세하게 달라지면
**다른 정수**가 나올 수 있다.

특히 위험한 지점:

```text
if error < bestError { bestError = error; best = (dx, dy) }
```

두 오프셋의 오차가 극히 가까울 때 부동소수점 차이가 선택을 뒤집는다.
그리고 정렬 오프셋이 1픽셀 달라지면 병합 결과가 전부 달라진다.

**대응**:

1. `downsampledError`와 `fullResLumaError`가 `Double`을 쓰는지 확인한다.
   현재 코드는 `Double`이다(`total: Double`). Windows도 `double`.
2. 누적 순서를 유지한다.
3. **동률 처리를 명시한다.** 현재는 "엄격히 작을 때만 교체"이므로
   먼저 탐색한 오프셋이 이긴다. 탐색 순서(`dy` 외부, `dx` 내부, 음수부터)를
   유지한다.
4. 골든 픽스처에 "오차가 근접한" 케이스를 넣는다.

## 5. Spike 명세

### N-1 — 로드 경로 동등성

§3.2 참조. **이식에서 가장 먼저 해야 할 이미징 검증이다.**

### N-2 — 쓰기 경로 동등성

[tiff-validation](tiff-validation.md) I-2와 같다.

```text
macOS에서 알려진 [UInt16] 배열로 writeRGB16TIFF
결과 파일의 픽셀 바이트를 hex로 덤프
Windows libtiff 구현의 결과와 비교
```

바이트 순서(`II` vs `MM`)가 달라도 **픽셀 값이 같으면 통과**로 본다.
호스트가 libtiff/WIC로 읽으므로 순서는 투명하다.
단 SHA-256 비교는 불가능해지므로, 비교는 디코드 후 픽셀 배열로 한다.

### N-3 — 전체 병합 파이프라인

```text
합성 입력 3장 → 병합 → 픽셀 배열 비교
macOS 결과와 Windows 결과가 UInt16 단위로 완전히 같은가
```

### N-4 — 정렬

```text
합성 입력에 알려진 오프셋을 주고 estimateIntegerOffset 실행
macOS와 Windows가 같은 (dx, dy)를 내는가
근접 오차 케이스 포함
```

### N-5 — 옵션 파싱 (P1)

```text
골든 픽스처 전체를 두 구현에 통과시켜
MediaSelection JSON이 일치하는지 비교
```

## 6. CI 통합

```text
[macOS runner]
  swift test --generate-parity-fixtures
  → fixtures/ 디렉터리 갱신
  → 변경이 있으면 실패 (골든 파일은 명시적으로 갱신해야 함)

[Windows runner]
  windows-test --verify-parity-fixtures
  → 같은 fixtures/를 읽고 비교
```

골든 파일은 저장소에 커밋한다. 크기가 문제되면
(병합 fixture는 작으므로 문제되지 않을 것) Git LFS를 고려한다.

**골든 파일 변경은 리뷰 대상이다.** 알고리즘을 의도적으로 바꿀 때만
갱신하며, 그때는 두 플랫폼을 함께 바꾼다.

## 7. 동등성을 포기해야 하는 경우

N-1이 실패하면(로드 경로가 다르면) 선택지는 셋이다.

**(a) macOS를 Windows에 맞춘다**

`TIFFLoader`를 직접 픽셀 읽기로 바꾼다. Core Image 의존을 없앤다.
가장 깨끗하지만 macOS 동작이 바뀌므로 회귀 위험이 있고, 이 저장소의
릴리스 절차를 다시 밟아야 한다.

**(b) Windows를 macOS에 맞춘다**

Core Image가 하는 일을 리버스 엔지니어링해 재현한다.
불투명한 동작을 추측으로 재현하는 것이므로 취약하다.

**(c) 차이를 인정하고 문서화한다**

"다중 노출 병합 결과는 플랫폼에 따라 미세하게 다를 수 있다"를
제품 사실로 명시한다. **권장하지 않는다.** negaflow의 제품 불변식이
"이미지 품질·정밀도 계약은 플랫폼에 따라 달라지지 않는다"이기 때문이다.

**권장: (a).** 다만 macOS 변경은 별도 작업으로 계획하고, 그 전까지
Windows 구현은 (b)를 임시로 쓰거나 다중 노출 기능을 비활성화한다.

## 8. 이식 체크리스트

- [ ] N-1이 통과했고 결과가 기록됐다
- [ ] FP 축약이 꺼져 있다 (빌드 플래그 확인 테스트)
- [ ] `Float` vs `double` 사용이 원본과 일치한다
- [ ] `round`가 half-away-from-zero다
- [ ] 부동소수점 파싱이 로케일 독립이다
- [ ] `UInt16` 변환이 절삭이다
- [ ] NaN 방어가 있다
- [ ] 누적 합에 SIMD를 쓰지 않았다
- [ ] 정렬 탐색 순서와 동률 처리가 같다
- [ ] 골든 픽스처가 저장소에 있고 CI가 검증한다
- [ ] 골든 파일 변경이 리뷰 대상으로 표시된다
