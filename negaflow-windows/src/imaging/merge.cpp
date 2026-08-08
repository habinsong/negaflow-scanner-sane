// SPDX-License-Identifier: GPL-2.0-or-later
//
// 이 파일의 연산 순서·분기 순서·누적 순서가 전부 계약이다.
// 근거: docs/04-imaging/exposure-merge.md §4
//       docs/04-imaging/numerical-parity.md §3

#include "imaging/merge.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>

#include "util/numeric.h"

namespace negaflow::imaging {

namespace {

[[nodiscard]] inline std::size_t idx(long long i) noexcept {
    return static_cast<std::size_t>(i);
}

/// 노출 정규화 배율. `normalizeExposure` 와 `NormalizedView` 가 **같은 식**을
/// 써야 하므로 한 곳에 둔다. 갈리면 지연 계산이 조용히 다른 값을 낸다.
[[nodiscard]] inline float exposureScale(int exposureTime, int referenceExposure) noexcept {
    // exposureTime 이 0 이면 inf 가 된다. Swift 도 막지 않는다 — 호출자가 막는다.
    return static_cast<float>(referenceExposure) / static_cast<float>(exposureTime);
}

/// 정규화된 픽셀을 **배열로 만들지 않고** 필요할 때 계산한다.
///
/// 정규화는 스칼라 곱 하나다. 12 패스 7200 dpi 에서 이 배열을 미리 만들면
/// 13 GB 를 더 쓴다 — 곱셈 한 번보다 메모리가 비싸다.
///
/// **비트 동일이 성립하는 이유**: `normalizeExposure` 도 `out[i] *= scale` 을
/// 한 번 할 뿐이다. 같은 피연산자로 같은 연산을 하므로 반올림까지 같다.
/// 알파를 1 로 덮어쓰는 것까지 그대로 재현한다.
/// 근거: docs/04-imaging/exposure-merge.md §7.2
struct NormalizedView {
    std::span<const float> raw;
    float scale = 1.0f;

    [[nodiscard]] float operator[](std::size_t i) const noexcept {
        // normalizeExposure 는 알파(채널 3)를 1 로 덮어쓴다.
        // 병합은 알파를 읽지 않지만 재현해 둔다 — 나중에 읽게 됐을 때
        // 조용히 달라지는 것보다 낫다.
        return (i % 4 == 3) ? 1.0f : raw[i] * scale;
    }
    [[nodiscard]] std::size_t size() const noexcept { return raw.size(); }
};

/// `alternateExposureValue` 의 술어. Swift 는 클로저를 넘기지만 세 가지뿐이다.
enum class Match {
    Equal,    ///< $0 == referenceExposure
    Shorter,  ///< $0 <  referenceExposure  — 클리핑 회피용
    Longer,   ///< $0 >  referenceExposure  — 저신호 보강용
};

[[nodiscard]] bool matches(Match m, int exposureTime, int referenceExposure) noexcept {
    switch (m) {
        case Match::Equal:
            return exposureTime == referenceExposure;
        case Match::Shorter:
            return exposureTime < referenceExposure;
        case Match::Longer:
            return exposureTime > referenceExposure;
    }
    return false;
}

/// 조건에 맞는 노출들의 신뢰도 가중 평균.
///
/// **가중치는 정규화 전(raw) 값으로, 합산은 정규화 후 값으로** 한다.
/// 이 비대칭이 핵심이다 — 신뢰도는 센서 원시값이 결정하고, 값은 노출 보정된
/// 것을 써야 한다. 근거: docs/04-imaging/exposure-merge.md §4.5
[[nodiscard]] std::optional<float> alternateExposureValue(
    int x,
    int y,
    int channel,
    const ImageList& rendered,
    const std::vector<NormalizedView>& normalized,
    std::span<const int> exposureTimes,
    const std::vector<Offset>& offsets,
    int width,
    int height,
    Match match,
    int referenceExposure) noexcept {
    float weightedSum = 0.0f;
    float weightSum = 0.0f;
    // Swift: for index in rendered.indices where predicate(exposureTimes[index])
    for (std::size_t i = 0; i < rendered.size(); ++i) {
        if (!matches(match, exposureTimes[i], referenceExposure)) continue;
        const auto source = alignedSourceIndex(x, y, channel, offsets[i], width, height);
        if (!source) continue;
        const float rawValue = rendered[i][*source];
        const float weight = exposureTrustWeight(rawValue);
        weightedSum += normalized[i][*source] * weight;
        weightSum += weight;
    }
    if (!(weightSum > 0.0001f)) return std::nullopt;
    return weightedSum / weightSum;
}

/// 한 픽셀·한 채널의 병합값.
///
/// 짧은 노출 혼합의 **결과에** 긴 노출을 섞는다. 순차 적용이며 순서를 바꾸면
/// 결과가 달라진다. 근거: docs/04-imaging/exposure-merge.md §4.4
[[nodiscard]] float mergedHardwareExposureValue(
    int x,
    int y,
    int channel,
    const ImageList& rendered,
    const std::vector<NormalizedView>& normalized,
    std::span<const int> exposureTimes,
    int referenceExposure,
    std::size_t referenceIndex,
    const std::vector<Offset>& offsets,
    int width,
    int height) noexcept {
    const auto referenceSource =
        alignedSourceIndex(x, y, channel, offsets[referenceIndex], width, height);
    const long long fallback = static_cast<long long>(y) * width * 4 + static_cast<long long>(x) * 4 +
                               channel;
    // Swift: referenceSource ?? min(fallback, normalized[referenceIndex].count - 1)
    // 버퍼 길이가 width*height*4 이므로 fallback 이 항상 더 작다. 원본 구조를 남긴다.
    const long long lastIndex = static_cast<long long>(normalized[referenceIndex].size()) - 1;
    const long long baselineIndex =
        referenceSource ? static_cast<long long>(*referenceSource) : std::min(fallback, lastIndex);
    const float baselineRaw = rendered[referenceIndex][idx(baselineIndex)];

    float value = alternateExposureValue(x, y, channel, rendered, normalized, exposureTimes, offsets,
                                         width, height, Match::Equal, referenceExposure)
                      .value_or(normalized[referenceIndex][idx(baselineIndex)]);

    if (const auto shortExposure =
            alternateExposureValue(x, y, channel, rendered, normalized, exposureTimes, offsets,
                                   width, height, Match::Shorter, referenceExposure)) {
        // 기준의 정규화 전 값이 밝을수록(클리핑에 가까울수록) 짧은 노출을 믿는다.
        const float amount = smoothstep(0.82f, 0.97f, baselineRaw);
        value = mix(value, *shortExposure, amount);
    }
    if (const auto longExposure =
            alternateExposureValue(x, y, channel, rendered, normalized, exposureTimes, offsets,
                                   width, height, Match::Longer, referenceExposure)) {
        // 어두울수록 긴 노출을 섞되 최대 0.48 까지만.
        const float amount = (1.0f - smoothstep(0.010f, 0.045f, baselineRaw)) * 0.48f;
        value = mix(value, *longExposure, amount);
    }
    return std::min(std::max(value, 0.0f), 1.0f);
}

/// float RGBA → 16비트 RGB. **절삭이다.**
///
/// NaN 방어를 넣는다. Swift 는 이 지점에서 런타임 트랩이고 C++ 는 UB 라
/// 어느 쪽도 정상 동작이 아니다. clamp 가 선행하므로 정상 입력에서는
/// 도달하지 않으며, **파리티에 NaN 을 넣지 않으므로 divergence 가 되지 않는다.**
/// 근거: docs/04-imaging/numerical-parity.md §3.4
[[nodiscard]] std::uint16_t quantizeChannel(float v) noexcept {
    const float clamped = std::isnan(v) ? 0.0f : std::min(std::max(v, 0.0f), 1.0f);
    return static_cast<std::uint16_t>(clamped * 65535.0f);
}

[[nodiscard]] Bitmap16 quantizeRGB16(const FloatBitmap& source) {
    Bitmap16 out;
    out.width = source.width;
    out.height = source.height;
    out.pixels.assign(idx(static_cast<long long>(source.width) * source.height * 3), 0);

    std::size_t o = 0;
    for (std::size_t i = 0; i + 3 < source.pixels.size(); i += 4) {
        for (std::size_t c = 0; c < 3; ++c) {
            out.pixels[o + c] = quantizeChannel(source.pixels[i + c]);
        }
        o += 3;
    }
    return out;
}

}  // namespace

std::string_view failureMessage(Failure f) noexcept {
    switch (f) {
        case Failure::ExposureInputMismatch:
            return "hardware exposure 입력 오류";
        case Failure::ExposureReferenceInvalid:
            return "hardware exposure 기준값 오류";
        case Failure::ExposureSizeInvalid:
            return "hardware exposure TIFF 크기 오류";
        case Failure::MultiSampleLoadFailed:
            return "multi-sample TIFF 로드 실패";
        case Failure::MultiSampleSizeInvalid:
            return "multi-sample TIFF 크기 오류";
    }
    return "";
}

void normalizeExposureInto(std::span<const float> pixels,
                           int exposureTime,
                           int referenceExposure,
                           std::vector<float>& out) {
    const float scale = exposureScale(exposureTime, referenceExposure);
    out.assign(pixels.begin(), pixels.end());
    // Swift: stride(from: 0, to: out.count, by: 4). 길이는 항상 4의 배수다.
    for (std::size_t i = 0; i + 3 < out.size(); i += 4) {
        out[i] *= scale;
        out[i + 1] *= scale;
        out[i + 2] *= scale;
        out[i + 3] = 1.0f;
    }
}

std::vector<float> normalizeExposure(std::span<const float> pixels,
                                     int exposureTime,
                                     int referenceExposure) {
    std::vector<float> out;
    normalizeExposureInto(pixels, exposureTime, referenceExposure, out);
    return out;
}

std::size_t referenceExposureIndex(std::span<const int> exposureTimes,
                                   int referenceExposure) noexcept {
    if (exposureTimes.empty()) return 0;  // Swift 의 `?? 0`
    std::size_t best = 0;
    long long bestDistance =
        std::llabs(static_cast<long long>(exposureTimes[0]) - referenceExposure);
    for (std::size_t i = 1; i < exposureTimes.size(); ++i) {
        const long long distance =
            std::llabs(static_cast<long long>(exposureTimes[i]) - referenceExposure);
        // 엄격히 작을 때만 교체 — 동률에서는 첫 원소가 남는다.
        if (distance < bestDistance) {
            bestDistance = distance;
            best = i;
        }
    }
    return best;
}

namespace {

/// 병합 준비 결과. 픽셀을 하나도 만들지 않는다 — 뷰와 오프셋뿐이다.
struct MergePlan {
    std::vector<NormalizedView> normalized;
    std::vector<Offset> offsets;
    std::size_t referenceIndex = 0;
};

/// 정규화 뷰와 정렬 오프셋을 만든다. 실패면 Failure.
///
/// **정렬만 정규화된 전체 배열을 요구한다.** `estimateIntegerOffset` 이
/// 풀해상도 임의 접근(`fullResLumaError`)을 하기 때문이다. 그래서 여기서만
/// 배열을 만들되 **N 장이 아니라 기준 1장 + 표본 1장**만 동시에 들고 있는다.
/// 병합 루프는 뷰로 계산하므로 배열이 필요 없다.
[[nodiscard]] std::optional<Failure> buildMergePlan(const ImageList& rendered,
                                                    std::span<const int> exposureTimes,
                                                    int referenceExposure,
                                                    int width,
                                                    int height,
                                                    MergePlan& plan) {
    // Swift: zip(rendered, exposureTimes) — 짧은 쪽에서 멈춘다.
    const std::size_t paired = std::min(rendered.size(), exposureTimes.size());
    plan.normalized.reserve(paired);
    for (std::size_t i = 0; i < paired; ++i) {
        plan.normalized.push_back(
            NormalizedView{rendered[i], exposureScale(exposureTimes[i], referenceExposure)});
    }

    plan.referenceIndex = referenceExposureIndex(exposureTimes, referenceExposure);
    // Swift 는 여기서 인덱스가 어긋나면 트랩한다. 호출자가 막는 조건이지만
    // C++ 에서는 조용한 메모리 접근이 되므로 오류로 돌린다.
    if (plan.referenceIndex >= plan.normalized.size() ||
        plan.normalized.size() != rendered.size()) {
        return Failure::ExposureInputMismatch;
    }

    // **정렬은 정규화된 이미지로 추정한다.** raw 가 아니다.
    std::vector<float> referenceNormalized;
    normalizeExposureInto(rendered[plan.referenceIndex], exposureTimes[plan.referenceIndex],
                          referenceExposure, referenceNormalized);
    std::vector<float> sampleNormalized;
    plan.offsets.reserve(paired);
    for (std::size_t i = 0; i < paired; ++i) {
        // 버퍼를 재사용한다 — 반복마다 새로 할당하면 잠깐 3장이 된다.
        normalizeExposureInto(rendered[i], exposureTimes[i], referenceExposure, sampleNormalized);
        plan.offsets.push_back(
            estimateIntegerOffset(referenceNormalized, sampleNormalized, width, height));
    }
    return std::nullopt;
}

}  // namespace

FloatBitmapOutcome alignedExposureNormalizedRGBAf(const ImageList& rendered,
                                                  std::span<const int> exposureTimes,
                                                  int referenceExposure,
                                                  int width,
                                                  int height) {
    if (!(width > 0 && height > 0)) return {Failure::ExposureSizeInvalid, {}};
    if (rendered.empty()) return {Failure::ExposureInputMismatch, {}};

    MergePlan plan;
    if (auto bad = buildMergePlan(rendered, exposureTimes, referenceExposure, width, height, plan)) {
        return {bad, {}};
    }

    FloatBitmap merged;
    merged.width = width;
    merged.height = height;
    merged.pixels.assign(idx(static_cast<long long>(width) * height * 4), 0.0f);

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const std::size_t destination = idx((static_cast<long long>(y) * width + x) * 4);
            for (int channel = 0; channel < 3; ++channel) {
                merged.pixels[destination + static_cast<std::size_t>(channel)] =
                    mergedHardwareExposureValue(x, y, channel, rendered, plan.normalized,
                                                exposureTimes, referenceExposure,
                                                plan.referenceIndex, plan.offsets, width, height);
            }
            merged.pixels[destination + 3] = 1.0f;
        }
    }
    return {std::nullopt, std::move(merged)};
}

FloatBitmapOutcome alignedAverageRGBAf(const ImageList& rendered, int width, int height) {
    if (rendered.empty()) return {Failure::MultiSampleLoadFailed, {}};
    if (!(width > 0 && height > 0)) return {Failure::MultiSampleSizeInvalid, {}};

    // 여기서는 **raw** 를 기준으로 정렬한다(노출 정규화가 없는 경로다).
    std::vector<Offset> offsets;
    offsets.reserve(rendered.size());
    for (const auto& sample : rendered) {
        offsets.push_back(estimateIntegerOffset(rendered[0], sample, width, height));
    }

    const long long pixelCount = static_cast<long long>(width) * height;
    std::vector<float> accumulator(idx(pixelCount * 4), 0.0f);
    std::vector<float> counts(idx(pixelCount), 0.0f);
    for (std::size_t i = 0; i < rendered.size(); ++i) {
        accumulateAligned(rendered[i], offsets[i], width, height, accumulator, counts);
    }

    for (long long pixel = 0; pixel < pixelCount; ++pixel) {
        const float count = std::max(counts[idx(pixel)], 1.0f);
        const std::size_t offset = idx(pixel * 4);
        accumulator[offset] = std::min(std::max(accumulator[offset] / count, 0.0f), 1.0f);
        accumulator[offset + 1] = std::min(std::max(accumulator[offset + 1] / count, 0.0f), 1.0f);
        accumulator[offset + 2] = std::min(std::max(accumulator[offset + 2] / count, 0.0f), 1.0f);
        accumulator[offset + 3] = 1.0f;
    }
    return {std::nullopt, FloatBitmap{std::move(accumulator), width, height}};
}

Bitmap16Outcome mergeHardwareExposureBitmap(const ImageList& rendered,
                                            std::span<const int> exposureTimes,
                                            int width,
                                            int height) {
    // Swift 의 guard 순서를 그대로 지킨다 — 같은 입력에 같은 오류가 나와야 한다.
    if (rendered.size() != exposureTimes.size() || rendered.empty()) {
        return {Failure::ExposureInputMismatch, {}};
    }
    const auto referenceExposure = util::referenceExposureTime(exposureTimes);
    if (!referenceExposure || !(*referenceExposure > 0)) {
        return {Failure::ExposureReferenceInvalid, {}};
    }
    if (!(width > 0 && height > 0)) return {Failure::ExposureSizeInvalid, {}};

    MergePlan plan;
    if (auto bad = buildMergePlan(rendered, exposureTimes, *referenceExposure, width, height, plan)) {
        return {bad, {}};
    }

    // **중간 float 비트맵을 만들지 않는다.** 픽셀 하나를 계산하는 즉시 16비트로
    // 떨어뜨린다. 7200 dpi 에서 그 중간 배열 하나가 1.1 GB 다.
    //
    // 값은 `alignedExposureNormalizedRGBAf` + `quantizeRGB16` 과 **같다** —
    // 같은 `mergedHardwareExposureValue` 를 부르고 같은 `quantizeChannel` 로
    // 떨어뜨린다. 양자화는 픽셀별로 독립이라 순서가 결과를 바꾸지 않는다.
    // 파리티가 두 경로를 각각 대조한다(merge.float[...] 와 merge.u16[...]).
    Bitmap16 out;
    out.width = width;
    out.height = height;
    out.pixels.assign(idx(static_cast<long long>(width) * height * 3), 0);

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const std::size_t destination = idx((static_cast<long long>(y) * width + x) * 3);
            for (int channel = 0; channel < 3; ++channel) {
                const float value = mergedHardwareExposureValue(
                    x, y, channel, rendered, plan.normalized, exposureTimes, *referenceExposure,
                    plan.referenceIndex, plan.offsets, width, height);
                out.pixels[destination + static_cast<std::size_t>(channel)] =
                    quantizeChannel(value);
            }
        }
    }
    return {std::nullopt, std::move(out)};
}

Bitmap16Outcome averageMultiSampleBitmap(const ImageList& rendered, int width, int height) {
    if (rendered.empty()) return {Failure::MultiSampleLoadFailed, {}};
    auto averaged = alignedAverageRGBAf(rendered, width, height);
    if (averaged.failure) return {averaged.failure, {}};
    return {std::nullopt, quantizeRGB16(averaged.bitmap)};
}

}  // namespace negaflow::imaging
