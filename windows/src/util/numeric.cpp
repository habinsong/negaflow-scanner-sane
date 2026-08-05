// SPDX-License-Identifier: GPL-2.0-or-later

#include "util/numeric.h"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <limits>
#include <system_error>
#include <vector>

namespace negaflow::util {

namespace {

// Swift 의 Double.rounded() == "half away from zero". std::round 가 같다.
[[nodiscard]] double roundHalfAwayFromZero(double v) noexcept { return std::round(v); }

constexpr long long kMaxPel = (1LL << 62);  // 실용 상한. Int.max 대용.

}  // namespace

bool containsExactly(const OptionRange& range, double value) noexcept {
    if (!std::isfinite(value)) return false;
    if (!(value >= range.minimum) || !(value <= range.maximum)) return false;
    if (!range.step.has_value() || !(*range.step > 0.0)) return true;
    const double offset = (value - range.minimum) / *range.step;
    if (!std::isfinite(offset)) return false;
    return std::fabs(offset - roundHalfAwayFromZero(offset)) <= 1e-7;
}

std::string saneNumber(double value) {
    // Swift: value.rounded() == value → 정수로 출력
    if (std::isfinite(value) && roundHalfAwayFromZero(value) == value) {
        // Swift 는 Int(value) 로 절단한다. 이미 정수이므로 절단은 무해하다.
        const long long asInt = static_cast<long long>(value);
        char buf[32];
        auto [ptr, ec] = std::to_chars(buf, buf + sizeof(buf), asInt);
        if (ec == std::errc{}) return std::string(buf, ptr);
        return "0";
    }

    // 왕복 가능한 최단 표현. std::to_chars(double) 는 로케일 독립이다.
    // std::to_string / sprintf("%g") 는 로케일 의존이므로 쓰지 않는다.
    char buf[64];
    auto [ptr, ec] = std::to_chars(buf, buf + sizeof(buf), value);
    if (ec != std::errc{}) return "0";
    std::string out(buf, ptr);

    // 지수 표기를 내지 않는다(scanimage 가 파싱하지 못한다).
    // 근거: windows_docs/02-frontend-contract/scanimage-invocation.md
    if (out.find('e') != std::string::npos || out.find('E') != std::string::npos) {
        char fixed[128];
        auto [fptr, fec] =
            std::to_chars(fixed, fixed + sizeof(fixed), value, std::chars_format::fixed);
        if (fec == std::errc{}) return std::string(fixed, fptr);
    }
    return out;
}

double epson2AlignedHeightMM(double originYMM,
                             double heightMM,
                             const OptionRange& range,
                             std::optional<double> surfaceBottomMM) noexcept {
    if (!std::isfinite(originYMM) || !std::isfinite(heightMM) || !(heightMM > 0.0)) {
        return heightMM;
    }
    const double bottom = originYMM + heightMM;
    if (!std::isfinite(bottom)) return heightMM;
    if (std::fabs(bottom - roundHalfAwayFromZero(bottom)) <= 1e-9) return heightMM;

    // ① 넓히기 — 잘리지 않는 방향을 먼저 시도한다.
    const double grownBottom = std::ceil(bottom);
    const double grown = grownBottom - originYMM;
    const bool withinSurface =
        surfaceBottomMM.has_value() ? (grownBottom <= *surfaceBottomMM + 1e-9) : true;
    if (containsExactly(range, grown) && withinSurface) return grown;

    // ② 좁히기
    const double shrunk = std::floor(bottom) - originYMM;
    if (shrunk > 0.0 && containsExactly(range, shrunk)) return shrunk;

    // ③ 포기 — 요청값 그대로. 2단계 검증이 |정렬량| < 1 을 확인한다.
    return heightMM;
}

std::optional<long long> pixelGeometryValue(double millimeters,
                                            int dpi,
                                            const OptionRange& range) noexcept {
    if (!std::isfinite(millimeters) || millimeters < 0.0 || dpi <= 0) return std::nullopt;
    const double exactPixels = millimeters * static_cast<double>(dpi) / 25.4;
    const double roundedPixels = roundHalfAwayFromZero(exactPixels);
    if (!(std::fabs(exactPixels - roundedPixels) <= 0.5 + 1e-9)) return std::nullopt;
    if (!(roundedPixels >= -static_cast<double>(kMaxPel)) ||
        !(roundedPixels <= static_cast<double>(kMaxPel))) {
        return std::nullopt;
    }
    const long long value = static_cast<long long>(roundedPixels);
    if (!containsExactly(range, static_cast<double>(value))) return std::nullopt;
    return value;
}

std::optional<long long> pixelGeometryLength(double millimeters, int unitDPI) noexcept {
    if (!std::isfinite(millimeters) || !(millimeters > 0.0) || unitDPI <= 0) return std::nullopt;
    const double rounded = roundHalfAwayFromZero(millimeters * static_cast<double>(unitDPI) / 25.4);
    if (!(rounded >= 1.0) || !(rounded <= static_cast<double>(kMaxPel))) return std::nullopt;
    return static_cast<long long>(rounded);
}

std::optional<int> referenceExposureTime(std::span<const int> exposureTimes) {
    // Swift: Array(Set(...)).sorted() — 중복 제거 후 정렬.
    // Set 의 순회 순서는 불정이지만 뒤에 sorted() 가 오므로 결과는 결정적이다.
    std::vector<int> unique(exposureTimes.begin(), exposureTimes.end());
    std::sort(unique.begin(), unique.end());
    unique.erase(std::unique(unique.begin(), unique.end()), unique.end());
    if (unique.empty()) return std::nullopt;
    return unique[unique.size() / 2];
}

}  // namespace negaflow::util
