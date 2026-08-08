// negaflow-scanner-sane — Windows adapter
// imaging/align — 패스 간 정수 오프셋 추정과 정렬 누적.
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend+Alignment.swift (203행, 전량)
//
// **전부 순수 함수이고 전부 부동소수점이다.** 즉 L5 수치 동등성의 주 대상이며
// 이 파일의 모든 연산 순서가 계약이다.
// 근거: docs/06-build/porting-map.md §2.5
//       docs/04-imaging/exposure-merge.md §6
//       docs/04-imaging/numerical-parity.md §4
//
// 이 헤더는 <windows.h> 도 libtiff 도 포함하지 않는다. 순수 산술뿐이다.
//
// 픽셀 버퍼는 RGBA float 인터리브다: [r0,g0,b0,a0, r1,g1,b1,a1, ...].
// 인덱싱은 (y*width + x)*4 + channel — Swift 원본과 같다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstddef>
#include <optional>
#include <span>
#include <vector>

namespace negaflow::imaging {

/// 정수 픽셀 오프셋. Swift 의 튜플 `(x: Int, y: Int)` 대응.
struct Offset {
    int x = 0;
    int y = 0;

    friend bool operator==(const Offset&, const Offset&) = default;
};

/// 오프셋을 적용한 소스 인덱스. 범위를 벗어나면 nullopt.
///
/// Swift 원본:
///     let sx = x + offset.x
///     let sy = y + offset.y
///     guard sx >= 0, sx < width, sy >= 0, sy < height else { return nil }
///     return (sy * width + sx) * 4 + channel
[[nodiscard]] std::optional<std::size_t> alignedSourceIndex(int x,
                                                            int y,
                                                            int channel,
                                                            Offset offset,
                                                            int width,
                                                            int height) noexcept;

/// 원시 센서값의 신뢰 가중치.
///
/// **분기 순서가 계약이다.** raw = 0.99 는 첫 조건에서 0.02 를 받고
/// 두 번째 조건에 도달하지 않는다.
/// 근거: docs/04-imaging/exposure-merge.md §4.6
///
/// Swift 원본:
///     if rawValue >= 0.985 { return 0.02 }
///     if rawValue >= 0.90  { return max(0.05, (0.985 - rawValue) / 0.085) }
///     if rawValue <= 0.006 { return 0.02 }
///     if rawValue <= 0.035 { return max(0.05, (rawValue - 0.006) / 0.029) }
///     return 1
[[nodiscard]] float exposureTrustWeight(float rawValue) noexcept;

/// 선형 보간. `amount` 를 0…1 로 클램프한 뒤 섞는다.
///
/// Swift 의 `min`/`max` 는 인자 순서에 따라 NaN 전파가 갈린다.
/// `min(max(amount, 0), 1)` 의 순서를 그대로 유지한다 — std::min/std::max 가
/// 같은 순서로 같은 결과를 낸다(둘 다 첫 인자를 NaN 일 때 돌려준다).
[[nodiscard]] float mix(float a, float b, float amount) noexcept;

/// GLSL smoothstep. edge0 == edge1 이면 계단 함수가 된다.
///
/// Swift 원본:
///     guard edge0 != edge1 else { return x >= edge1 ? 1 : 0 }
///     let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
///     return t * t * (3 - 2 * t)
[[nodiscard]] float smoothstep(float edge0, float edge1, float x) noexcept;

/// 기준 이미지에 대한 샘플 이미지의 정수 오프셋.
///
/// 다운샘플 탐색 → 조기 종료 판정 → 풀해상도 미세보정의 3단이다.
/// **결과는 정수이므로 완전 일치를 요구한다.** 1픽셀만 달라져도 병합 결과가
/// 전부 달라진다.
/// 근거: docs/04-imaging/numerical-parity.md §4
///
/// 동률에서는 먼저 탐색한 오프셋이 이긴다(`error < bestError`, 엄격 비교).
/// 탐색 순서(dy 외부, dx 내부, 음수부터)를 유지한다.
///
/// `reference`/`sample` 은 RGBA float, 길이 width*height*4 이상이어야 한다.
[[nodiscard]] Offset estimateIntegerOffset(std::span<const float> reference,
                                           std::span<const float> sample,
                                           int width,
                                           int height);

/// 오프셋을 적용해 RGB 를 누적하고 픽셀별 카운트를 올린다.
///
/// 범위를 벗어나는 소스는 건너뛴다 — **카운트도 증가하지 않는다.**
/// 알파(채널 3)는 건드리지 않는다.
///
/// `accumulator` 는 width*height*4, `counts` 는 width*height 여야 한다.
void accumulateAligned(std::span<const float> sample,
                       Offset offset,
                       int width,
                       int height,
                       std::span<float> accumulator,
                       std::span<float> counts) noexcept;

/// Swift 에서 `private` 인 내부 단계들.
///
/// Swift 쪽이 `private static` 이라 `@testable import` 로도 부를 수 없으므로
/// **파리티 대상이 아니다.** 여기 노출하는 것은 C++ 단위 테스트로 각 단계를
/// 고정해, `estimateIntegerOffset` 이 어긋났을 때 원인을 좁히기 위해서다.
namespace detail {

struct Downsampled {
    std::vector<float> luma;
    int width = 0;
    int height = 0;
};

/// factor×factor 블록 평균 휘도 → 3×3 박스 블러.
/// 휘도 = R*0.2126 + G*0.7152 + B*0.0722, 블록 합에 1/(factor*factor) 를 곱한다.
[[nodiscard]] Downsampled downsampledLuma(std::span<const float> pixels,
                                          int width,
                                          int height,
                                          int factor);

/// 분리형 3×3 박스 블러.
///
/// **경계를 처리하지 않는다.** 가장자리 한 줄은 블러되지 않은 원본이 남는다.
/// 이것은 버그처럼 보이지만 그대로 옮긴다 — 고치면 정렬 결과가 달라진다.
/// 근거: docs/04-imaging/exposure-merge.md §6.2
[[nodiscard]] std::vector<float> boxBlur3(const std::vector<float>& buf, int width, int height);

/// 오프셋 (dx, dy) 에서의 평균 절대 차. 누적은 double 이다(Swift 원본과 같음).
/// 비교 불가면 std::numeric_limits<double>::max() — Swift .greatestFiniteMagnitude.
[[nodiscard]] double downsampledError(std::span<const float> ref,
                                      std::span<const float> smp,
                                      int width,
                                      int height,
                                      int dx,
                                      int dy) noexcept;

/// 가로 인접 차의 평균. 텍스처 가드용.
[[nodiscard]] double downsampledTexture(std::span<const float> luma,
                                        int width,
                                        int height) noexcept;

/// 풀해상도 서브샘플 휘도 오차. step = max(1, min(w,h)/256).
[[nodiscard]] double fullResLumaError(std::span<const float> reference,
                                      std::span<const float> sample,
                                      int width,
                                      int height,
                                      int dx,
                                      int dy) noexcept;

}  // namespace detail

}  // namespace negaflow::imaging
