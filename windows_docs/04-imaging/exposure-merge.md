# 다중 노출 병합

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 이식 정본
코드 근거: `SANEBackend+ExposureMerge.swift`, `SANEBackend+ExposureMergingCore.swift`,
`SANEBackend+Alignment.swift`, `SANEBackend+TIFFWriting.swift`

관련 문서:

- [numerical-parity](numerical-parity.md)
- [tiff-validation](tiff-validation.md)
- [exact-option-contract](../02-frontend-contract/exact-option-contract.md)

## 1. 이 기능이 무엇인가

스캐너의 `--scan-exposure-time`을 바꿔가며 여러 번 스캔하고, 그 결과를
하나의 16-bit TIFF로 합친다. 필름 네거티브의 어두운 부분(= 원본 밀도가
높은 부분)에서 신호를 끌어올리는 것이 목적이다.

**소프트웨어 밝기 조정이 아니다.** 실제 하드웨어 노출 시간을 바꾼다.
`--scan-exposure-time` 옵션이 없거나 필요한 값 전부를 정확히 지원하지
않으면 기능 자체가 꺼진다.

## 2. 노출 계획

```text
hardwareExposureTimes = [11_000, 14_000, 30_000]
hardwareExposureSamplesPerStop = clamp(NEGAFLOW_HWEXP_SAMPLES ?? 1, 1, 4)

hardwareExposurePlan() = hardwareExposureTimes.flatMap { exposure in
    Array(repeating: exposure, count: samplesPerStop)
}
```

기본(samplesPerStop=1): `[11000, 14000, 30000]` — 3 패스.
최대(4): `[11000×4, 14000×4, 30000×4]` — 12 패스.

같은 노출의 반복 샘플은 무작위/색 노이즈를 줄이고, 서로 다른 노출은
클리핑/저신호 영역을 메운다.

**단위**: `--scan-exposure-time`의 단위는 백엔드가 정한다. 이 값들은
특정 장치에서 측정된 것이며 프로토콜은 단위를 정의하지 않는다
(negaflow 본체 windows_docs `10-scanner/protocol-contract.md` §7.2 필드 표:
"unit is adapter capability contract").

## 3. 전체 흐름 (`startSoftwareMultiPassScan`)

```text
1. 노출 계획 생성, 패스 수만큼 임시 URL 생성
2. media 해석 및 2단계 검증 (한 번만)
3. 각 패스:
     passOptions.hardwareExposureTime = plan[i]
     진행률 base = 0.08 + i * (0.70 / passCount)
     runSingleAcquisition(..., scanProgressRange: base...(base + 0.70/passCount))
4. 진행률 0.82: "Merging exposure brackets"
5. mergeHardwareExposureScans(urls, plan, outputURL)
6. warnings에 노출 계획 설명 추가
7. IR 요청 시:
     irStrategy가 별도 패스면 IR 획득
     아니면 "Infrared skipped: this device's IR method cannot be combined
             with multi-exposure passes." 경고
8. 결과 검증 (3단계)
9. defer: NEGAFLOW_KEEP_MULTIPASS가 아니면 중간 TIFF 삭제
```

**media를 한 번만 해석한다.** 패스마다 다시 해석하면 장치를 여러 번
열게 되고, 그것이 전용 필름 스캐너에서 위험하다.

## 4. 병합 알고리즘

### 4.1 진입점

```text
mergeHardwareExposureScans(sampleURLs, exposureTimes, outputURL):
    images = sampleURLs.map { TIFFLoader.loadScannerTIFF($0) }
    로드 실패가 하나라도 있으면 → ioFailure
    bitmap = mergeHardwareExposureBitmap(images, exposureTimes)
    writeRGB16TIFF(bitmap.pixels, ..., outputURL)
```

### 4.2 기준 노출

```text
referenceExposureTime(from times):
    unique = Set(times) 정렬
    → unique[unique.count / 2]      ← 중앙값
```

`[11000, 14000, 30000]` → unique 3개 → 인덱스 1 → **14000**.

`referenceIndex`는 `exposureTimes`에서 기준값에 가장 가까운 **첫** 원소의
인덱스다.

```text
exposureTimes.enumerated()
    .min { abs($0.element - reference) < abs($1.element - reference) }?
    .offset ?? 0
```

**주의**: Swift `min(by:)`는 "엄격히 작으면 교체"이므로 동률에서 첫 원소가
남는다. Windows 구현에서 `std::min_element`나 LINQ `MinBy`가 같은
동률 처리를 하는지 확인해야 한다.

### 4.3 정규화

```text
normalizeExposure(pixels, exposureTime, referenceExposure):
    scale = Float(reference) / Float(exposureTime)
    각 RGB 채널 *= scale
    알파 = 1
```

즉 짧은 노출은 값이 커지고 긴 노출은 작아진다. 선형 응답을 가정한다.

`Float`(binary32)로 계산한다. `Double`로 바꾸면 결과가 달라진다.

### 4.4 픽셀별 병합 (`mergedHardwareExposureValue`)

각 (x, y, channel)에 대해:

```text
referenceSource = alignedSourceIndex(x, y, ch, offsets[referenceIndex], w, h)
fallback = (y*w + x)*4 + ch
baselineIndex = referenceSource ?? min(fallback, normalized[refIdx].count - 1)
baselineRaw = rendered[referenceIndex][baselineIndex]        ← 정규화 전 값

value = alternateExposureValue(matching: { $0 == reference })
        ?? normalized[referenceIndex][baselineIndex]

if let short = alternateExposureValue(matching: { $0 < reference }) {
    amount = smoothstep(edge0: 0.82, edge1: 0.97, x: baselineRaw)
    value = mix(value, short, amount)
}

if let long = alternateExposureValue(matching: { $0 > reference }) {
    amount = (1 - smoothstep(edge0: 0.010, edge1: 0.045, x: baselineRaw)) * 0.48
    value = mix(value, long, amount)
}

→ clamp(value, 0, 1)
```

의미:

- 기준 노출의 **정규화 전** 값이 밝을수록(0.82~0.97) 짧은 노출 쪽으로 섞는다
  (클리핑 회피).
- 기준 노출 값이 어두울수록(0.010~0.045) 긴 노출 쪽으로 최대 0.48만큼 섞는다
  (저신호 보강).
- 두 혼합은 순차적으로 적용된다. 짧은 노출 혼합의 결과에 긴 노출을 섞는다.

**상수 0.82, 0.97, 0.010, 0.045, 0.48은 튜닝값이다.** 근거가 코드에 없다.
이식 시 정확히 같은 값을 쓰고, 바꾸지 않는다.

### 4.5 대체 노출 가중 평균

```text
alternateExposureValue(matching predicate):
    weightedSum = 0, weightSum = 0
    predicate(exposureTimes[i])인 모든 i에 대해:
        source = alignedSourceIndex(x, y, ch, offsets[i], w, h)
        source가 nil이면 건너뜀
        rawValue = rendered[i][source]              ← 정규화 전
        weight = exposureTrustWeight(rawValue)
        weightedSum += normalized[i][source] * weight   ← 정규화 후
        weightSum += weight
    weightSum <= 0.0001이면 → nil
    → weightedSum / weightSum
```

**가중치는 정규화 전 값으로, 합산은 정규화 후 값으로** 한다.
이 비대칭이 핵심이다 — 신뢰도는 센서 원시값이 결정하고, 값은 노출 보정된
것을 써야 한다.

### 4.6 신뢰 가중치 (`exposureTrustWeight`)

```text
raw >= 0.985           → 0.02          클리핑
raw >= 0.90            → max(0.05, (0.985 - raw) / 0.085)
raw <= 0.006           → 0.02          암부 노이즈
raw <= 0.035           → max(0.05, (raw - 0.006) / 0.029)
그 외                  → 1.0
```

**분기 순서가 계약이다.** `raw = 0.99`는 첫 조건에서 0.02를 받고
두 번째 조건에 도달하지 않는다.

### 4.7 보조 함수

```text
mix(a, b, t)     = a + (b - a) * clamp(t, 0, 1)
smoothstep(e0, e1, x):
    e0 == e1 이면 → x >= e1 ? 1 : 0
    t = clamp((x - e0) / (e1 - e0), 0, 1)
    → t * t * (3 - 2*t)
alignedSourceIndex(x, y, ch, offset, w, h):
    sx = x + offset.x, sy = y + offset.y
    범위 밖이면 nil
    → (sy*w + sx)*4 + ch
```

## 5. 단순 평균 경로

`averageMultiSampleScans` / `averageMultiSampleBitmap`은 노출 정규화 없이
정렬 후 평균만 낸다.

```text
alignedAverageRGBAf(images, colorSpace):
    첫 이미지의 정수 extent를 기준으로 모두 crop 후 RGBAf 렌더
    첫 이미지를 기준으로 각 샘플의 정수 오프셋 추정
    정렬해 누적, 카운트 유지
    각 픽셀: 누적 / max(카운트, 1), 0…1 클램프, 알파 1
```

**현재 production 경로에서 호출되지 않는다.** `startSoftwareMultiPassScan`이
항상 `mergeHardwareExposureScans`를 쓴다. 테스트만 이 경로를 쓴다
(`SANEBackendMultiSampleTests.swift`).

이식 시 옮기되 "테스트 전용" 표시를 유지한다.

## 6. 정렬 (`estimateIntegerOffset`)

패스 사이에 필름이 미세하게 움직인다. 3600 dpi에서 이송 축 흔들림이
수십 픽셀에 달한다.

### 6.1 알고리즘

```text
factor = clamp(min(width, height) / 96, 1, 8)
(ref, dw, dh) = downsampledLuma(reference, w, h, factor)
(smp, _, _)   = downsampledLuma(sample, w, h, factor)

dw <= 6 또는 dh <= 6 → (0, 0)

refMean = max(ref 평균, 1e-6)
downsampledTexture(ref, dw, dh) <= refMean * 0.008 → (0, 0)

baseline = downsampledError(ref, smp, dw, dh, 0, 0)
yRange = max(1, min(96 / factor, (dh - 6) / 2))     세로: 넓게
xRange = max(1, min(16 / factor, (dw - 6) / 2))     가로: 좁게
전 범위 탐색해 최소 오차 위치 best 찾기

bestError >= baseline * 0.85 → (0, 0)              개선이 충분하지 않음

fx = best.x * factor, fy = best.y * factor
fineError = fullResLumaError(ref, smp, w, h, fx, fy)
dy ∈ [fy-factor, fy+factor], dx ∈ [fx-2, fx+2] 전수 탐색
→ (fx, fy)
```

#### 6.1.1 미세보정 루프의 범위 평가 시점이 계약이다

미세보정 루프는 그냥 이중 for 문이 아니다. **`fx`와 `fy`가 루프 안에서
갱신되고, 안쪽 범위가 그 값을 다시 읽는다.**

```swift
for dy in (fy - factor)...(fy + factor) {   // ← 루프 진입 시 한 번만 평가
    for dx in (fx - 2)...(fx + 2) {         // ← 바깥 반복마다 다시 평가
        if error < fineError { fineError = error; fx = dx; fy = dy }
    }
}
```

Swift의 `for-in`은 범위 표현식을 루프에 들어갈 때 한 번 평가한다. 바깥
범위는 **초기** `fy`로 고정되지만, 안쪽 범위 표현식은 바깥 반복마다 다시
평가되므로 **그 시점의 `fx`**를 쓴다. 더 나은 오프셋을 찾으면 가로 탐색
창이 그쪽으로 따라 움직인다.

```cpp
const int dyLo = fy - factor, dyHi = fy + factor;   // 한 번만
for (int dy = dyLo; dy <= dyHi; ++dy) {
    const int dxLo = fx - 2, dxHi = fx + 2;          // 매 반복마다 현재 fx 로
    for (int dx = dxLo; dx <= dxHi; ++dx) { ... }
}
```

**두 범위를 모두 루프 밖에서 한 번만 계산하면 결과가 달라진다.** 이것이
의도된 설계인지 우연인지는 코드에 근거가 없다. 동등성이 목표이므로
그대로 옮긴다.

### 6.2 세부 함수

**`downsampledLuma`**: factor×factor 블록 평균 → 3×3 박스 블러.

```text
휘도 = R*0.2126 + G*0.7152 + B*0.0722
블록 합 * (1 / (factor*factor))
boxBlur3: 분리형. 가로 3탭(x ∈ [1, w-2]) → 세로 3탭(y ∈ [1, h-2])
          경계 픽셀은 원본 유지
```

**주의**: `boxBlur3`은 경계를 처리하지 않는다. `tmp = buf` 복사 후
내부만 덮어쓰므로 가장자리 한 줄은 블러되지 않은 원본이다.
**이 동작을 그대로 옮긴다.** "고치면" 정렬 결과가 달라진다.

**`downsampledError`**: 오프셋 (dx, dy)에서의 평균 절대 차.

```text
inset = 2 + max(|dx|, |dy|)
width <= 2*inset 또는 height <= 2*inset → greatestFiniteMagnitude
y ∈ [inset, height-inset), x ∈ [inset, width-inset)
total += |ref[y*w + x] - smp[(y+dy)*w + x + dx]|
→ total / count
```

**`downsampledTexture`**: 가로 인접 차의 평균.

```text
y ∈ [1, height-1), x ∈ [1, width-1)
total += |luma[y*w + x] - luma[y*w + x + 1]|
→ total / count
```

텍스처 가드가 상대적인 이유(코드 주석): 네거티브 raw는 절대 휘도가 낮아
(ADC 일부만 사용) 고정 임계면 구조가 충분한데도 항상 스킵된다.

**`fullResLumaError`**: 풀 해상도 서브샘플 비교.

```text
step = max(1, min(w, h) / 256)
inset = 4 + max(|dx|, |dy|)
y를 inset부터 step씩, x도 inset부터 step씩
RGBA 버퍼에서 직접 휘도 계산해 절대 차 누적
```

**`accumulateAligned`**: 오프셋 적용해 누적하고 카운트 증가.
범위를 벗어나는 소스는 건너뛴다(카운트도 증가하지 않음).

## 7. Windows 구현 전략

### 7.1 Core Image를 걷어낸다

현재 흐름:

```text
TIFF → CGImage → CIImage(linearSRGB 재해석)
     → CIContext.render(toBitmap:, format: .RGBAf, colorSpace: linear)
     → [Float] RGBA
```

Windows:

```text
TIFF → libtiff로 uint16 RGB 읽기
     → [Float] RGBA  (값 / 65535.0, 알파 1.0)
```

**같은 결과가 나오는가**가 [numerical-parity](numerical-parity.md)의
핵심 질문이다. `CIContext.render`가 색 변환을 하지 않는다는 것이 전제이며,
그 전제는 입력 CIImage와 출력이 같은 색공간(linearSRGB)이기 때문에
성립할 것으로 보이지만 **검증해야 한다.**

`.RGBAf`는 32-bit float 4채널이다. `[Float]` 레이아웃은
`[r0,g0,b0,a0, r1,g1,b1,a1, ...]`이며 현재 코드의 인덱싱
(`(y*width + x)*4 + channel`)과 일치한다.

### 7.2 성능

7200 dpi 35 mm = 10200 × 6800 = 약 6,900만 픽셀.
RGBA float 버퍼 하나가 **1.1 GB**다. 12 패스면 13 GB.

**현재 macOS 구현은 모든 패스를 동시에 메모리에 올린다.**
`rendered`와 `normalized` 두 배열이 있으므로 실제로는 26 GB다.

이것은 macOS에서도 문제이며, Windows에서 그대로 옮기면 즉시 OOM이다.

**대응 전략** (우선순위 순):

1. **타일 처리**: 이미지를 가로 스트립으로 나눠 처리한다. 정렬 오프셋은
   전역이므로 먼저 계산하고(다운샘플만 전체 메모리 필요), 병합은
   스트립 단위로 한다.
2. **`normalized` 배열 제거**: 정규화는 스칼라 곱이므로 필요할 때 계산한다.
   메모리가 절반이 된다. 값이 float 곱셈 한 번이므로 비용이 거의 없다.
3. **half float 저장**: `rendered`를 float16으로 저장하면 절반이 된다.
   정밀도 손실이 결과에 영향을 주는지 확인 필요.
4. **메모리 맵**: 중간 버퍼를 파일로 두고 매핑한다.

**1번과 2번을 함께 적용하는 것을 권장한다.** 정렬 계산과 병합 계산이
분리돼 있으므로 구조 변경이 크지 않다.

단 **결과가 비트 단위로 같아야 한다.** 스트립 경계에서 정렬 오프셋이
범위를 벗어나는 처리가 전체 처리와 같아야 한다.
`alignedSourceIndex`가 전역 좌표로 판정하므로, 스트립 처리 시
소스 이미지는 오프셋만큼 여유 있게 읽어야 한다.

### 7.2.1 2번은 적용했다 — 실측 (2026-08-05)

`normalized` 배열을 없앴다. 정규화는 스칼라 곱 하나이므로 배열로 들고 있을
이유가 없다.

```text
NormalizedView { raw, scale }   →  raw[i] * scale   (알파는 1)
```

**비트 동일이 성립하는 이유**: `normalizeExposure`도 `out[i] *= scale`을 한 번
할 뿐이다. 같은 피연산자로 같은 연산이므로 반올림까지 같다. 이 항등식을
단위 테스트가 고정한다.

정렬만은 정규화된 **전체 배열**을 요구한다 — `fullResLumaError`가 풀해상도
임의 접근을 하기 때문이다. 그래서 거기서만 배열을 만들되 **N장이 아니라
기준 1장 + 표본 1장**만 동시에 들고 있는다.

16비트 양자화도 중간 float 비트맵을 거치지 않게 했다. 픽셀 하나를 계산하는
즉시 떨어뜨린다.

실측(12 패스 700×500, 같은 입력·같은 출력 체크값):

```text
옛 구조   입력 64 MB → 피크 143 MB    병합 오버헤드 79 MB
현재      입력 64 MB → 피크  78 MB    병합 오버헤드 14 MB
```

오버헤드가 **5.6배** 줄었다. 남은 14 MB는 정렬용 2장과 출력 버퍼다.

7200 dpi 12 패스로 환산하면 병합 오버헤드가 약 14.5 GB → 2.6 GB다.
파리티 6 케이스가 전부 그대로 통과했다.

### 7.2.2 1번(타일 처리)은 하지 않았다 — 막히는 지점

**해도 지금은 피크가 줄지 않는다.** 호출자가 `rendered`를 이미 전부 메모리에
올려서 넘기기 때문이다. 7200 dpi 12 패스면 그것만 13.2 GB이고, 병합 루프를
스트립으로 쪼개도 그 13.2 GB는 그대로다.

진짜 해결은 **픽셀을 TIFF에서 필요할 때 읽는 것**이고, 그러려면 둘이 필요하다.

```text
1. ImageList 가 "메모리 배열"이 아니라 "행 단위 소스" 추상이어야 한다
   → imaging/tiff_io 가 행 단위 읽기를 제공해야 한다
2. 그 스트리밍을 지휘할 계층이 있어야 한다 (M5)
```

그리고 **정렬이 걸린다.** `fullResLumaError`는 후보 오프셋마다 이미지 전체를
`step` 간격으로 훑는다. 미세보정에서 후보가 15개쯤 되므로, 스트리밍하면
패스마다 TIFF를 15번 다시 읽게 된다. 성능 대가가 있는 설계 결정이며,
**검증이 끝난 `imaging/align`의 동작 표면을 건드린다.**

그래서 여기서 멈췄다. 절반만 구현하면 "비트 동일"과 "메모리 안전" 중
어느 것도 확실하지 않은 상태가 된다.

**다음 사람에게**: 이 작업은 M5의 조율 계층과 함께 설계해야 한다.
기존 병합 파리티 6 케이스가 그대로 회귀 검사가 되고, 스트립 크기를
바꿔가며 같은 결과가 나오는 케이스를 추가하면 더 좋다.

### 7.3 병렬화

픽셀별 병합은 완전히 독립적이다. 행 단위로 병렬화할 수 있다.

**단 부동소수점 결과가 달라지면 안 된다.** 각 픽셀의 계산이 독립적이므로
순서와 무관하게 같은 값이 나온다. `alternateExposureValue`의 누적만
순서 의존이며, 그 순서는 인덱스 순이므로 병렬화해도 각 픽셀 내에서는
순차다. **안전하다.**

정렬 탐색도 병렬화 가능하지만 `if error < bestError`의 순차 갱신이
동률에서 결과를 바꿀 수 있다. **정렬 탐색은 순차로 둔다.**
비용은 다운샘플된 이미지에서만 발생하므로 크지 않다.

### 7.4 SIMD

`downsampledLuma`, `downsampledError`, `fullResLumaError`,
`accumulateAligned`, `normalizeExposure`가 후보다.

**하지만 부동소수점 결과가 바뀌면 안 된다.**

| 연산 | SIMD 안전성 |
|---|---|
| 요소별 곱셈(정규화) | 안전 |
| 요소별 절대차 | 안전 |
| **누적 합** | **위험.** 순서가 바뀌면 결과가 달라진다 |

누적 합을 벡터 레인별로 나눠 마지막에 합치면 **다른 값**이 나온다.
`downsampledError`의 `total`, `downsampledTexture`의 `total`,
`fullResLumaError`의 `total`이 전부 여기 해당한다.

**결정**:

```text
D-11  1차 구현은 스칼라로 한다. 부동소수점 결과가 macOS와 일치함을
      먼저 증명한다.
      SIMD 최적화는 그 이후, 그리고 "결과가 달라지지 않는 연산"에만
      적용한다. 누적 합은 스칼라로 남긴다.
      FMA 축약(fused multiply-add)을 컴파일러가 임의로 넣지 못하게
      한다 (MSVC: /fp:precise 기본, GCC/Clang: -ffp-contract=off).
```

## 8. 경고 메시지

```text
"Hardware scan-exposure-time bracket [11000, 14000, 30000] used with N sample(s)
 per exposure; same-exposure samples reduce random/color noise before
 clipped/low-signal regions are filled from alternate exposures."
```

배열의 문자열 표현이 Swift `[Int]`의 `description`이다.
Windows에서 같은 형식(`[11000, 14000, 30000]`)으로 만든다.

```text
"Multi-pass intermediate TIFFs kept: <경로들, ", "로 결합>"
```

```text
"Infrared skipped: this device's IR method cannot be combined with
 multi-exposure passes."
```

**문자열을 바꾸지 않는다.** 호스트가 파싱하지는 않지만 사용자에게
그대로 표시될 수 있고, 두 플랫폼의 진단 비교 가능성을 유지한다.

## 9. 이식 체크리스트

`imaging/align`·`imaging/merge` 기준(2026-08-05). 체크된 항목은 파리티
하네스나 단위 테스트가 지키고 있다는 뜻이다.

- [ ] 노출 계획 생성이 동일 (`flatMap` + `repeating`) — M5(조율부)
- [ ] `NEGAFLOW_HWEXP_SAMPLES` 클램프 1…4 — M5(조율부)
- [x] 기준 노출 = 고유값 정렬의 중앙 — `util/numeric`, 파리티 9 케이스
- [x] `referenceIndex` 동률 처리가 첫 원소 — 단위 테스트
- [x] `normalizeExposure`가 Float
- [x] `exposureTrustWeight` 5분기 순서 — 파리티 14 케이스 + 단위 테스트
- [x] `smoothstep` 상수 4개 — 파리티 11 케이스
- [x] 혼합 계수 0.48
- [x] 짧은 노출 → 긴 노출 순차 혼합
- [x] 가중치는 raw, 합산은 normalized
- [x] `weightSum <= 0.0001` 임계
- [x] `boxBlur3`의 경계 미처리 동작 — 단위 테스트가 모서리 4개를 고정
- [x] 정렬 탐색 범위 계산식
- [x] `bestError >= baseline * 0.85` 조기 종료 — 동일 이미지 케이스
- [x] 텍스처 가드 `refMean * 0.008` — 평탄 이미지 케이스
- [x] 미세 보정 범위 (±factor 세로, ±2 가로) — §6.1.1의 평가 시점 포함
- [x] `averageMultiSampleScans`가 테스트 전용으로 표시됨 — 헤더 주석
- [ ] 메모리 전략이 12 패스 7200 dpi를 견딘다 — **절반.** 병합 오버헤드는
      5.6배 줄였지만(§7.2.1) 입력 N장 상주가 남았다(§7.2.2)
- [x] 스칼라 결과가 macOS와 일치 (parity 문서)
- [x] FP 축약이 꺼져 있다 — 빌드와 **검증 도구 양쪽**
- [ ] 경고 문자열이 동일 — M5(조율부)

남은 넷 중 셋은 다중 패스 **조율**(어느 노출을 몇 번 스캔하고 경고를
어떻게 붙이는가)이라 프로세스 계층이 필요하다. 병합 코어와는 분리된다.

**메모리 전략은 아직 없다.** 현재 구현은 macOS와 같이 모든 패스를 동시에
메모리에 올린다. 7200 dpi 12 패스에서 그대로면 OOM이다(§7.2). 스트립
처리를 넣을 때 **비트 동일이 유지되는지 파리티로 확인해야 한다.**
