// negaflow-scanner-sane — Windows adapter
// sane/capabilities — 옵션 덤프 → 장치 능력.
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend+Capabilities.swift
// 정본 문서: windows_docs/02-frontend-contract/capability-model.md
//
// **능력은 관측이지 약속이 아니다**(I-2). 장치가 실제로 노출한 옵션에서만
// 판정하고, 모델명으로 능력을 발명하지 않는다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "sane/option_dump.h"
#include "util/numeric.h"

namespace negaflow::sane {

enum class ColorMode { Color, Gray, Lineart, Infrared };
enum class BitDepth { Eight = 8, Sixteen = 16 };
enum class ScanAreaUnit { Millimeter, Inch, Pixel };

[[nodiscard]] std::string_view colorModeRawValue(ColorMode m) noexcept;

/// wire 문자열 → ColorMode. 모르는 값이면 nullopt.
///
/// Swift `ColorMode(rawValue:)` 대응. **`lineart`/`infrared` 도 인식한다** —
/// 인식과 허용은 다르다. 요청 검증이 그 둘을 따로 거부하며, 그래야
/// "지원하지 않는 colorMode: lineart" 라는 정확한 문구가 나온다.
[[nodiscard]] std::optional<ColorMode> colorModeFromRawValue(std::string_view s);
[[nodiscard]] std::string_view scanAreaUnitRawValue(ScanAreaUnit u) noexcept;

struct ScanArea {
    double originXMM = 0.0;
    double originYMM = 0.0;
    double widthMM = 36.0;
    double heightMM = 24.0;

    friend bool operator==(const ScanArea&, const ScanArea&) = default;
};

/// 호스트에 보고하는 능력. wire 의 `PluginCapabilities` 로 직렬화된다.
struct ScannerCapabilities {
    std::vector<int> supportedResolutionsDPI;  // 오름차순
    std::vector<ColorMode> supportedModes;
    std::vector<BitDepth> supportedBitDepths;
    std::vector<std::string> sourceModes;
    std::vector<std::string> transparencyModes;

    bool supportsPreview = false;
    bool supportsTransparency = false;
    bool supportsInfrared = false;
    bool supportsMultiExposure = false;
    bool supportsScanArea = false;
    bool supportsPositionedScanArea = false;
    bool supportsLampWarmupStatus = false;  // 항상 false

    std::optional<util::OptionRange> brightnessRange;
    std::optional<util::OptionRange> contrastRange;
    std::optional<util::OptionRange> hardwareExposureRange;
    std::optional<util::OptionRange> scanOriginXRange;
    std::optional<util::OptionRange> scanOriginYRange;
    std::optional<util::OptionRange> scanWidthRange;
    std::optional<util::OptionRange> scanHeightRange;

    /// 왜 못 쓰는지. 빈 map 일 수 있고 그때 wire 에서는 `{}` 다(null 아님).
    std::map<std::string, std::string> disabledReasons;

    ScanArea maxScanArea{0.0, 0.0, 0.0, 0.0};
    ScanArea minScanArea{0.0, 0.0, 0.0, 0.0};
    ScanAreaUnit scanAreaUnit = ScanAreaUnit::Millimeter;
    std::vector<std::string> outputFormats{"tiff"};
};

/// 다중 노출에 필요한 노출 시간 계획. 세 값 **전부**가 범위에 정확히 있어야 한다.
inline constexpr int kHardwareExposureTimes[] = {11000, 14000, 30000};

/// 투과/필름 소스인가(Transparency Adapter/TPA, Transparency Unit/TPU, TPU8x10, Film, Slide).
[[nodiscard]] bool isTransparencySource(std::string_view s);

/// IR 소스/모드 값인가.
[[nodiscard]] bool isInfraredValue(std::string_view s);

/// 본 스캔에 쓸 투과 소스를 고른다. **3단 폴백**이다.
///
///   ① IR 이 아닌 투과 소스 중 공백 제거 후 "8x10" 포함하는 첫 값
///   ② 없으면 IR 이 아닌 투과 소스의 첫 값
///   ③ 그것도 비면 투과 소스인 첫 값  ← **IR 을 배제하지 않는다**
///
/// ③ 이 잠재적 구멍이다. 투과 소스가 전부 IR 인 장치에서는 IR 소스가 본 스캔에
/// 선택된다. 알려진 대상 장치에는 해당 사례가 없어 macOS 에서 드러난 적이 없다.
/// **동작을 그대로 옮긴다** — 한쪽만 고치면 두 플랫폼이 갈린다(I-20).
/// 근거: windows_docs/10-lessons/driver-option-reference.md §5
[[nodiscard]] std::optional<std::string> preferredTransparencySource(
    const std::vector<std::string>& sources);

/// `--depth` 가 없거나 비활성인 고정 심도 기기의 실제 심도.
///
/// 5갈래다: 옵션 없음(epson2/pie → 8bit) / 활성(nil) / 토큰≠1개(nil) /
/// 유일값 8 / 유일값 >8.
[[nodiscard]] std::optional<BitDepth> fixedDepth(const OptionDump& opts,
                                                 std::string_view backendHint);

/// 범위에서 "양수인 최소 크기"를 고른다. 3갈래.
[[nodiscard]] double minimumPositiveScanDimension(const util::OptionRange& range);

/// 덤프 → 능력.
///
/// **genesys 16-bit 밝기 예외를 여기서는 적용하지 않는다.** 그 예외는
/// resolveMedia 에만 있고, 그래서 능력 응답과 검증이 어긋나는 지점이 생긴다.
/// 현재 macOS 동작 그대로다 — 바꾸려면 양 플랫폼 동시에 해야 한다(Q-7).
[[nodiscard]] ScannerCapabilities parseCapabilities(const OptionDump& opts,
                                                    std::string_view deviceTypeHint,
                                                    std::string_view backendHint);

}  // namespace negaflow::sane
