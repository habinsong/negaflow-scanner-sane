// SPDX-License-Identifier: GPL-2.0-or-later
//
// 이 파일의 모든 연산 순서는 계약이다. 수학적으로 동등한 재배열이
// 부동소수점에서는 다른 결과를 낸다.
// 근거: windows_docs/04-imaging/numerical-parity.md §2.2 "연산 순서"

#include "imaging/align.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <limits>

namespace negaflow::imaging {

namespace {

/// Swift `.greatestFiniteMagnitude` 대응.
constexpr double kGreatestFiniteMagnitude = std::numeric_limits<double>::max();

/// 인덱싱용 캐스트. 호출부에서 이미 범위를 보장한다.
[[nodiscard]] inline std::size_t idx(int i) noexcept { return static_cast<std::size_t>(i); }

}  // namespace

std::optional<std::size_t> alignedSourceIndex(int x,
                                              int y,
                                              int channel,
                                              Offset offset,
                                              int width,
                                              int height) noexcept {
    const int sx = x + offset.x;
    const int sy = y + offset.y;
    if (!(sx >= 0 && sx < width && sy >= 0 && sy < height)) return std::nullopt;
    return idx((sy * width + sx) * 4 + channel);
}

float exposureTrustWeight(float rawValue) noexcept {
    // 분기 순서가 계약이다. 위 조건이 걸리면 아래는 평가되지 않는다.
    if (rawValue >= 0.985f) return 0.02f;
    if (rawValue >= 0.90f) return std::max(0.05f, (0.985f - rawValue) / 0.085f);
    if (rawValue <= 0.006f) return 0.02f;
    if (rawValue <= 0.035f) return std::max(0.05f, (rawValue - 0.006f) / 0.029f);
    return 1.0f;
}

float mix(float a, float b, float amount) noexcept {
    const float t = std::min(std::max(amount, 0.0f), 1.0f);
    return a + (b - a) * t;
}

float smoothstep(float edge0, float edge1, float x) noexcept {
    // Swift: guard edge0 != edge1 else { ... }  ← NaN 이면 != 가 참이라 통과한다.
    // C++ 의 == 는 NaN 에서 거짓이므로 같은 흐름이 된다.
    if (edge0 == edge1) return x >= edge1 ? 1.0f : 0.0f;
    const float t = std::min(std::max((x - edge0) / (edge1 - edge0), 0.0f), 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

namespace detail {

Downsampled downsampledLuma(std::span<const float> pixels, int width, int height, int factor) {
    const int dw = width / factor;
    const int dh = height / factor;
    if (!(dw > 0 && dh > 0)) return {};

    std::vector<float> out(idx(dw * dh), 0.0f);
    const float inv = 1.0f / static_cast<float>(factor * factor);
    for (int by = 0; by < dh; ++by) {
        const int y0 = by * factor;
        for (int bx = 0; bx < dw; ++bx) {
            const int x0 = bx * factor;
            float sum = 0.0f;
            for (int yy = y0; yy < y0 + factor; ++yy) {
                const int row = yy * width;
                for (int xx = x0; xx < x0 + factor; ++xx) {
                    const std::size_t i = idx((row + xx) * 4);
                    sum += pixels[i] * 0.2126f + pixels[i + 1] * 0.7152f + pixels[i + 2] * 0.0722f;
                }
            }
            out[idx(by * dw + bx)] = sum * inv;
        }
    }
    return Downsampled{boxBlur3(out, dw, dh), dw, dh};
}

std::vector<float> boxBlur3(const std::vector<float>& buf, int width, int height) {
    if (!(width >= 3 && height >= 3)) return buf;
    const float third = 1.0f / 3.0f;

    // 가로 3탭: buf 를 읽고 tmp 에 쓴다. x = 0 과 x = width-1 은 복사본 그대로 남는다.
    std::vector<float> tmp = buf;
    for (int y = 0; y < height; ++y) {
        const int r = y * width;
        for (int x = 1; x < width - 1; ++x) {
            tmp[idx(r + x)] = (buf[idx(r + x - 1)] + buf[idx(r + x)] + buf[idx(r + x + 1)]) * third;
        }
    }

    // 세로 3탭: tmp 를 읽고 out 에 쓴다. y = 0 과 y = height-1 은 그대로 남는다.
    std::vector<float> out = tmp;
    for (int y = 1; y < height - 1; ++y) {
        for (int x = 0; x < width; ++x) {
            out[idx(y * width + x)] = (tmp[idx((y - 1) * width + x)] + tmp[idx(y * width + x)] +
                                       tmp[idx((y + 1) * width + x)]) *
                                      third;
        }
    }
    return out;
}

double downsampledError(std::span<const float> ref,
                        std::span<const float> smp,
                        int width,
                        int height,
                        int dx,
                        int dy) noexcept {
    const int inset = 2 + std::max(std::abs(dx), std::abs(dy));
    if (!(width > 2 * inset && height > 2 * inset)) return kGreatestFiniteMagnitude;

    double total = 0.0;
    long long count = 0;
    for (int y = inset; y < height - inset; ++y) {
        const int rRow = y * width;
        const int sRow = (y + dy) * width;
        for (int x = inset; x < width - inset; ++x) {
            // 뺄셈은 Float 로, 절대값과 누적은 Double 로. 이 비대칭이 원본이다.
            total += std::fabs(static_cast<double>(ref[idx(rRow + x)] - smp[idx(sRow + x + dx)]));
            count += 1;
        }
    }
    return count == 0 ? kGreatestFiniteMagnitude : total / static_cast<double>(count);
}

double downsampledTexture(std::span<const float> luma, int width, int height) noexcept {
    double total = 0.0;
    long long count = 0;
    for (int y = 1; y < height - 1; ++y) {
        const int row = y * width;
        for (int x = 1; x < width - 1; ++x) {
            total += std::fabs(static_cast<double>(luma[idx(row + x)] - luma[idx(row + x + 1)]));
            count += 1;
        }
    }
    return count == 0 ? 0.0 : total / static_cast<double>(count);
}

double fullResLumaError(std::span<const float> reference,
                        std::span<const float> sample,
                        int width,
                        int height,
                        int dx,
                        int dy) noexcept {
    const int step = std::max(1, std::min(width, height) / 256);
    const int inset = 4 + std::max(std::abs(dx), std::abs(dy));
    if (!(width > 2 * inset && height > 2 * inset)) return kGreatestFiniteMagnitude;

    double total = 0.0;
    long long count = 0;
    for (int y = inset; y < height - inset; y += step) {
        const int sy = y + dy;
        for (int x = inset; x < width - inset; x += step) {
            const std::size_t r = idx((y * width + x) * 4);
            const std::size_t s = idx((sy * width + x + dx) * 4);
            const float rl =
                reference[r] * 0.2126f + reference[r + 1] * 0.7152f + reference[r + 2] * 0.0722f;
            const float sl =
                sample[s] * 0.2126f + sample[s + 1] * 0.7152f + sample[s + 2] * 0.0722f;
            total += std::fabs(static_cast<double>(rl - sl));
            count += 1;
        }
    }
    return count == 0 ? kGreatestFiniteMagnitude : total / static_cast<double>(count);
}

}  // namespace detail

Offset estimateIntegerOffset(std::span<const float> reference,
                             std::span<const float> sample,
                             int width,
                             int height) {
    // 다운샘플 배율은 이미지 크기에 적응(작은 이미지/테스트에선 1px 정렬도 가능하게).
    const int factor = std::max(1, std::min(8, std::min(width, height) / 96));
    const detail::Downsampled r = detail::downsampledLuma(reference, width, height, factor);
    const detail::Downsampled s = detail::downsampledLuma(sample, width, height, factor);
    const int dw = r.width;
    const int dh = r.height;
    if (!(dw > 6 && dh > 6)) return Offset{0, 0};

    // 텍스처 가드는 휘도 레벨에 상대적으로 둔다 — 네거티브 raw 는 절대 휘도가 낮아
    // (ADC 일부만 사용) 고정 임계면 구조가 충분한데도 항상 스킵돼 (0,0) 으로 빠진다.
    float sum = 0.0f;  // Swift: ref.reduce(0, +) — 인덱스 순 Float 누적
    for (float v : r.luma) sum += v;
    const float refMean =
        std::max(sum / static_cast<float>(std::max<std::size_t>(r.luma.size(), 1)), 1e-6f);
    if (!(detail::downsampledTexture(r.luma, dw, dh) > static_cast<double>(refMean) * 0.008)) {
        return Offset{0, 0};
    }

    const double baseline = detail::downsampledError(r.luma, s.luma, dw, dh, 0, 0);
    Offset best{0, 0};
    double bestError = baseline;
    const int yRange = std::max(1, std::min(96 / factor, (dh - 6) / 2));  // 세로/이송 축 — 넓게
    const int xRange = std::max(1, std::min(16 / factor, (dw - 6) / 2));  // 가로/크로스피드 — 좁게
    for (int dy = -yRange; dy <= yRange; ++dy) {
        for (int dx = -xRange; dx <= xRange; ++dx) {
            const double error = detail::downsampledError(r.luma, s.luma, dw, dh, dx, dy);
            // 엄격 비교 — 동률에서는 먼저 탐색한 오프셋이 이긴다.
            if (error < bestError) {
                bestError = error;
                best = Offset{dx, dy};
            }
        }
    }
    if (!(bestError < baseline * 0.85)) return Offset{0, 0};

    // 풀해상도 미세보정: 다운샘플 최적점(×factor) 주변 ±factor(세로)·±2(가로).
    int fx = best.x * factor;
    int fy = best.y * factor;
    double fineError = detail::fullResLumaError(reference, sample, width, height, fx, fy);

    // **범위 평가 시점이 계약이다.** Swift 의 for-in 은 범위를 루프 진입 시 한 번
    // 평가한다. 바깥 범위는 초기 fy 로 한 번, 안쪽 범위는 바깥 반복마다 **그 시점의
    // fx** 로 다시 평가된다. fx 가 갱신되면 안쪽 탐색 창이 따라 움직인다.
    // 두 범위를 모두 루프 밖에서 한 번만 계산하면 결과가 달라진다.
    const int dyLo = fy - factor;
    const int dyHi = fy + factor;
    for (int dy = dyLo; dy <= dyHi; ++dy) {
        const int dxLo = fx - 2;  // 매 바깥 반복마다 현재 fx 로 다시 잡는다.
        const int dxHi = fx + 2;
        for (int dx = dxLo; dx <= dxHi; ++dx) {
            const double error = detail::fullResLumaError(reference, sample, width, height, dx, dy);
            if (error < fineError) {
                fineError = error;
                fx = dx;
                fy = dy;
            }
        }
    }
    return Offset{fx, fy};
}

void accumulateAligned(std::span<const float> sample,
                       Offset offset,
                       int width,
                       int height,
                       std::span<float> accumulator,
                       std::span<float> counts) noexcept {
    for (int y = 0; y < height; ++y) {
        const int sy = y + offset.y;
        if (!(sy >= 0 && sy < height)) continue;
        for (int x = 0; x < width; ++x) {
            const int sx = x + offset.x;
            if (!(sx >= 0 && sx < width)) continue;
            const std::size_t source = idx((sy * width + sx) * 4);
            const std::size_t destination = idx((y * width + x) * 4);
            accumulator[destination] += sample[source];
            accumulator[destination + 1] += sample[source + 1];
            accumulator[destination + 2] += sample[source + 2];
            counts[idx(y * width + x)] += 1.0f;
        }
    }
}

}  // namespace negaflow::imaging
