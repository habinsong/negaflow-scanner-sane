// SPDX-License-Identifier: GPL-2.0-or-later

#include "sane/capabilities.h"

#include <algorithm>
#include <array>
#include <cctype>

#include "sane/device_list.h"

namespace negaflow::sane {

namespace {

[[nodiscard]] std::string toLower(std::string_view s) {
    std::string out;
    out.reserve(s.size());
    for (char c : s) out.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
    return out;
}

[[nodiscard]] bool contains(std::string_view h, std::string_view n) {
    return h.find(n) != std::string_view::npos;
}

[[nodiscard]] std::string removeSpaces(std::string_view s) {
    std::string out;
    out.reserve(s.size());
    for (char c : s) {
        if (c != ' ') out.push_back(c);
    }
    return out;
}

/// 범위형 해상도에서 노출할 표준 후보. 임의 dpi 를 노출하지 않는다 —
/// UI 가 자유 입력을 허용하면 사용자가 step 밖 값을 넣어 2단계에서 거부당한다.
constexpr std::array<int, 13> kStandardResolutions{100,  150,  300,  600,  1200,  2400, 3200,
                                                   3600, 4800, 6400, 7200, 9600, 12800};

}  // namespace

std::string_view colorModeRawValue(ColorMode m) noexcept {
    switch (m) {
        case ColorMode::Color: return "color";
        case ColorMode::Gray: return "gray";
        case ColorMode::Lineart: return "lineart";
        case ColorMode::Infrared: return "infrared";
    }
    return "color";
}

std::optional<ColorMode> colorModeFromRawValue(std::string_view s) {
    if (s == "color") return ColorMode::Color;
    if (s == "gray") return ColorMode::Gray;
    if (s == "lineart") return ColorMode::Lineart;
    if (s == "infrared") return ColorMode::Infrared;
    return std::nullopt;
}

std::string_view scanAreaUnitRawValue(ScanAreaUnit u) noexcept {
    switch (u) {
        case ScanAreaUnit::Millimeter: return "millimeter";
        case ScanAreaUnit::Inch: return "inch";
        case ScanAreaUnit::Pixel: return "pixel";
    }
    return "millimeter";
}

bool isTransparencySource(std::string_view s) {
    const std::string l = toLower(s);
    return contains(l, "transparency") || contains(l, "tpa") || contains(l, "tpu") ||
           contains(l, "film") || contains(l, "slide");
}

bool isInfraredValue(std::string_view s) {
    const std::string l = toLower(s);
    return contains(l, "infrared") || l == "ir";
}

std::optional<std::string> preferredTransparencySource(const std::vector<std::string>& sources) {
    std::vector<const std::string*> visible;
    for (const auto& s : sources) {
        if (isTransparencySource(s) && !isInfraredValue(s)) visible.push_back(&s);
    }

    // ① 8x10 우선(더 큰 투과 영역)
    for (const auto* s : visible) {
        if (contains(removeSpaces(toLower(*s)), "8x10")) return *s;
    }
    // ② IR 아닌 투과 소스의 첫 값
    if (!visible.empty()) return *visible.front();
    // ③ 투과 소스인 첫 값 — IR 을 배제하지 않는다(원본 동작 그대로)
    for (const auto& s : sources) {
        if (isTransparencySource(s)) return s;
    }
    return std::nullopt;
}

std::optional<BitDepth> fixedDepth(const OptionDump& opts, std::string_view backendHint) {
    if (!opts.hasOption("depth")) {
        // 구형 기기: --depth 자체가 없으면 8-bit 고정으로 본다.
        if (backendHint == "epson2" || backendHint == "pie") return BitDepth::Eight;
        return std::nullopt;
    }
    if (opts.isActive("depth")) return std::nullopt;

    const auto tokens = opts.constraintIntTokens("depth");
    if (tokens.size() != 1) return std::nullopt;
    const int only = tokens.front();
    if (only == 8) return BitDepth::Eight;
    // 9~16bit ADC 는 전부 16bit 컨테이너로 전달된다(SANE 규격).
    return only > 8 ? std::optional<BitDepth>{BitDepth::Sixteen} : std::nullopt;
}

double minimumPositiveScanDimension(const util::OptionRange& range) {
    if (range.minimum > 0.0) return range.minimum;
    if (range.step.has_value() && *range.step > 0.0) return std::min(*range.step, range.maximum);
    return std::min(0.1, range.maximum);
}

ScannerCapabilities parseCapabilities(const OptionDump& opts,
                                      std::string_view deviceTypeHint,
                                      std::string_view backendHint) {
    ScannerCapabilities caps;

    const auto sources = opts.enumValues("source");
    const auto modeValuesOriginal = opts.enumValues("mode");
    std::vector<std::string> modeValues;
    modeValues.reserve(modeValuesOriginal.size());
    for (const auto& m : modeValuesOriginal) modeValues.push_back(toLower(m));

    std::vector<std::string> transparencyModes;
    for (const auto& s : sources) {
        if (isTransparencySource(s)) transparencyModes.push_back(s);
    }

    const auto brightnessRange = opts.numericRange("brightness");
    const auto contrastRange = opts.numericRange("contrast");
    const auto hardwareExposureRange = opts.numericRange("scan-exposure-time");
    const auto resolutionRange = opts.numericRange("resolution");

    // 노출 계획 세 값이 **전부** 범위에 정확히 있어야 다중 노출을 켠다.
    bool supportsHardwareExposure = false;
    if (hardwareExposureRange.has_value()) {
        supportsHardwareExposure = true;
        for (int t : kHardwareExposureTimes) {
            if (!util::containsExactly(*hardwareExposureRange, static_cast<double>(t))) {
                supportsHardwareExposure = false;
                break;
            }
        }
    }

    // --- 해상도 ---
    const auto spec = opts.resolutionSpec();
    std::vector<int> resolutions;
    if (spec.kind == ResolutionSpec::Kind::List) {
        resolutions = spec.list;
    } else if (spec.kind == ResolutionSpec::Kind::Range) {
        for (int v : kStandardResolutions) {
            if (v >= spec.min && v <= spec.max && resolutionRange.has_value() &&
                util::containsExactly(*resolutionRange, static_cast<double>(v))) {
                resolutions.push_back(v);
            }
        }
        if (resolutionRange.has_value() &&
            util::containsExactly(*resolutionRange, static_cast<double>(spec.max)) &&
            std::find(resolutions.begin(), resolutions.end(), spec.max) == resolutions.end()) {
            resolutions.push_back(spec.max);
        }
    }

    // --- 비트 심도 ---
    const auto depthTokens = opts.intTokens("depth");
    std::vector<BitDepth> bitDepths;
    if (std::find(depthTokens.begin(), depthTokens.end(), 8) != depthTokens.end()) {
        bitDepths.push_back(BitDepth::Eight);
    }
    if (std::any_of(depthTokens.begin(), depthTokens.end(), [](int v) { return v > 8; })) {
        bitDepths.push_back(BitDepth::Sixteen);
    }
    if (bitDepths.empty()) {
        if (const auto fixed = fixedDepth(opts, backendHint)) bitDepths.push_back(*fixed);
    }

    // --- 색 모드 ---
    std::vector<ColorMode> modes;
    if (std::any_of(modeValues.begin(), modeValues.end(),
                    [](const std::string& m) { return contains(m, "color"); })) {
        modes.push_back(ColorMode::Color);
    }
    if (std::any_of(modeValues.begin(), modeValues.end(), [](const std::string& m) {
            return contains(m, "gray") || contains(m, "grey");
        })) {
        modes.push_back(ColorMode::Gray);
    }

    // --- 투과 ---
    const std::string typeHint = toLower(deviceTypeHint);
    const bool dedicatedFilmDevice =
        !opts.isActive("source") && (contains(typeHint, "film") || contains(typeHint, "slide") ||
                                     isDedicatedFilmBackend(backendHint));
    if (modes.empty() && dedicatedFilmDevice) {
        // 일부 전용 필름 백엔드는 --mode 가 없고 출력 프레임 형식으로 Color 를 고정한다.
        // 실제 채널 수는 획득 뒤 TIFF 검증이 다시 확인한다.
        modes.push_back(ColorMode::Color);
    }
    const bool supportsTransparency = !transparencyModes.empty() || dedicatedFilmDevice;

    // --- IR ---
    // 호스트의 IR 능력은 **별도 IR 채널 파일**을 뜻한다. clean-image 는 백엔드
    // 내부 보정만 하므로 IR 채널로 보고하지 않는다.
    const bool infraredViaSource =
        std::any_of(sources.begin(), sources.end(),
                    [](const std::string& s) { return isInfraredValue(s); });
    const bool infraredViaMode =
        std::any_of(modeValues.begin(), modeValues.end(),
                    [](const std::string& m) { return contains(m, "infrared"); });
    const bool supportsInfrared = infraredViaSource || infraredViaMode;

    // --- 스캔 영역 ---
    ScanArea minScanArea{0.0, 0.0, 0.0, 0.0};
    ScanArea maxScanArea{0.0, 0.0, 0.0, 0.0};
    ScanAreaUnit scanAreaUnit = ScanAreaUnit::Millimeter;
    bool supportsScanArea = false;
    bool supportsPositionedScanArea = false;

    const auto unitX = opts.rangeUnit("x");
    const auto unitY = opts.rangeUnit("y");
    const auto xRange = opts.numericRange("x");
    const auto yRange = opts.numericRange("y");

    if (unitX.has_value() && *unitX == "mm" && unitY.has_value() && *unitY == "mm" &&
        xRange.has_value() && yRange.has_value() && xRange->maximum > 0.0 &&
        yRange->maximum > 0.0) {
        supportsScanArea = true;
        const auto unitL = opts.rangeUnit("l");
        const auto unitT = opts.rangeUnit("t");
        const auto leftRange =
            (unitL.has_value() && *unitL == "mm") ? opts.numericRange("l") : std::nullopt;
        const auto topRange =
            (unitT.has_value() && *unitT == "mm") ? opts.numericRange("t") : std::nullopt;
        const double surfaceOriginX = leftRange.has_value() ? leftRange->minimum : 0.0;
        const double surfaceOriginY = topRange.has_value() ? topRange->minimum : 0.0;

        minScanArea = ScanArea{surfaceOriginX, surfaceOriginY,
                               minimumPositiveScanDimension(*xRange),
                               minimumPositiveScanDimension(*yRange)};
        maxScanArea = ScanArea{surfaceOriginX, surfaceOriginY, xRange->maximum, yRange->maximum};

        const bool hasReflectiveSource =
            std::any_of(sources.begin(), sources.end(), [](const std::string& s) {
                return !isTransparencySource(s) && !isInfraredValue(s);
            });
        // 4조건 전부 참일 때만. 투과 전용 기기는 위치 지정을 보고하지 않는다.
        supportsPositionedScanArea = !transparencyModes.empty() && hasReflectiveSource &&
                                     leftRange.has_value() && topRange.has_value();
    } else if ((unitX.has_value() && *unitX == "pel") || (unitY.has_value() && *unitY == "pel")) {
        scanAreaUnit = ScanAreaUnit::Pixel;
    }

    // --- disabledReasons ---
    std::map<std::string, std::string> reasons;
    if (!supportsTransparency) {
        reasons["transparency"] = "scanimage -A의 --source에 Transparency/TPU/Film 항목이 없습니다.";
    }
    if (!supportsInfrared) {
        if (backendHint == "coolscan3" && opts.hasOption("infrared")) {
            reasons["infrared"] =
                "coolscan3의 --infrared는 RGBI 프레임이며 stock scanimage가 별도 IR TIFF로 "
                "전달하지 못합니다.";
        } else if (opts.hasOption("clean-image")) {
            reasons["infrared"] =
                "--clean-image는 별도 IR 채널을 반환하지 않아 IR 채널 기능으로 사용할 수 "
                "없습니다.";
        } else {
            reasons["infrared"] = "scanimage -A에 별도 IR 채널을 획득할 활성 source/mode가 없습니다.";
        }
    }
    if (!supportsHardwareExposure) {
        reasons["multiExposure"] =
            opts.hasOption("scan-exposure-time")
                ? "--scan-exposure-time 범위가 필요한 노출 계획을 모두 지원하지 않습니다."
                : "scanimage -A에 --scan-exposure-time이 없어 실제 다중노출을 켤 수 없습니다.";
    }
    if (!brightnessRange.has_value()) {
        reasons["brightness"] = opts.hasOption("brightness")
                                    ? "현재 스캔 옵션 조합에서 --brightness가 비활성입니다."
                                    : "scanimage -A에 --brightness 옵션이 없습니다.";
    }
    if (!contrastRange.has_value()) {
        reasons["contrast"] = opts.hasOption("contrast")
                                  ? "현재 스캔 옵션 조합에서 --contrast가 비활성입니다."
                                  : "scanimage -A에 --contrast 옵션이 없습니다.";
    }
    if (!supportsScanArea) {
        reasons["scanArea"] =
            "scanimage -A에 mm 단위 -x/-y 범위가 없어 요청 영역을 정확히 적용할 수 없습니다.";
    }

    std::sort(resolutions.begin(), resolutions.end());

    const auto mmRange = [&opts](const char* name) -> std::optional<util::OptionRange> {
        const auto unit = opts.rangeUnit(name);
        if (!unit.has_value() || *unit != "mm") return std::nullopt;
        return opts.numericRange(name);
    };

    caps.supportedResolutionsDPI = std::move(resolutions);
    caps.supportedModes = std::move(modes);
    caps.supportedBitDepths = std::move(bitDepths);
    caps.sourceModes = sources;
    caps.transparencyModes = std::move(transparencyModes);
    caps.supportsPreview = opts.isActive("preview");
    caps.supportsTransparency = supportsTransparency;
    caps.supportsInfrared = supportsInfrared;
    caps.supportsMultiExposure = supportsHardwareExposure;
    caps.supportsScanArea = supportsScanArea;
    caps.supportsPositionedScanArea = supportsPositionedScanArea;
    caps.supportsLampWarmupStatus = false;
    caps.brightnessRange = brightnessRange;
    caps.contrastRange = contrastRange;
    caps.hardwareExposureRange = hardwareExposureRange;
    caps.scanOriginXRange = mmRange("l");
    caps.scanOriginYRange = mmRange("t");
    caps.scanWidthRange = mmRange("x");
    caps.scanHeightRange = mmRange("y");
    caps.disabledReasons = std::move(reasons);
    caps.maxScanArea = maxScanArea;
    caps.minScanArea = minScanArea;
    caps.scanAreaUnit = scanAreaUnit;
    caps.outputFormats = {"tiff"};
    return caps;
}

}  // namespace negaflow::sane
