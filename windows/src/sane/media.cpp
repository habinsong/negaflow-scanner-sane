// SPDX-License-Identifier: GPL-2.0-or-later

#include "sane/media.h"

#include <algorithm>
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

[[nodiscard]] std::string_view trim(std::string_view s) {
    constexpr std::string_view kSpace = " \t\v\f\r\n";
    const auto b = s.find_first_not_of(kSpace);
    if (b == std::string_view::npos) return {};
    const auto e = s.find_last_not_of(kSpace);
    return s.substr(b, e - b + 1);
}

[[nodiscard]] bool equalsIgnoreCase(std::string_view a, std::string_view b) {
    return toLower(a) == toLower(b);
}

[[nodiscard]] std::string removeSpaces(std::string_view s) {
    std::string out;
    out.reserve(s.size());
    for (char c : s) {
        if (c != ' ') out.push_back(c);
    }
    return out;
}

/// 코너 pel 지오메트리에서 쓸 단위 dpi.
[[nodiscard]] std::optional<int> maximumResolutionDPI(const OptionDump& opts) {
    const auto spec = opts.resolutionSpec();
    if (spec.kind == ResolutionSpec::Kind::List) {
        if (spec.list.empty()) return std::nullopt;
        return *std::max_element(spec.list.begin(), spec.list.end());
    }
    if (spec.kind == ResolutionSpec::Kind::Range) return spec.max;
    return std::nullopt;
}

/// `rangeUnit(name) == unit` 일 때만 범위를 준다.
[[nodiscard]] std::optional<util::OptionRange> rangeWithUnit(const OptionDump& opts,
                                                            const char* name,
                                                            std::string_view unit) {
    const auto u = opts.rangeUnit(name);
    if (!u.has_value() || *u != unit) return std::nullopt;
    return opts.numericRange(name);
}

}  // namespace

std::string_view filmTypeRawValue(FilmType t) noexcept {
    switch (t) {
        case FilmType::ColorNegative: return "colorNegative";
        case FilmType::ColorPositive: return "colorPositive";
        case FilmType::BwNegative: return "bwNegative";
        case FilmType::BwPositive: return "bwPositive";
    }
    return "colorNegative";
}

std::optional<FilmType> filmTypeFromRawValue(std::string_view s) {
    if (s == "colorNegative") return FilmType::ColorNegative;
    if (s == "colorPositive") return FilmType::ColorPositive;
    if (s == "bwNegative") return FilmType::BwNegative;
    if (s == "bwPositive") return FilmType::BwPositive;
    return std::nullopt;
}

bool requiresInversion(FilmType t) noexcept {
    return t == FilmType::ColorNegative || t == FilmType::BwNegative;
}

std::optional<std::string> pickModeValue(const std::vector<std::string>& values,
                                         ColorMode colorMode) {
    if (values.empty()) return std::nullopt;
    for (const auto& v : values) {
        const std::string l = toLower(v);
        bool want = false;
        switch (colorMode) {
            case ColorMode::Gray: want = contains(l, "gray") || contains(l, "grey"); break;
            case ColorMode::Lineart: want = contains(l, "lineart") || contains(l, "binary"); break;
            case ColorMode::Infrared: want = contains(l, "infrared"); break;
            case ColorMode::Color: want = contains(l, "color"); break;
        }
        if (want) return v;
    }
    return std::nullopt;
}

std::optional<std::string> epsonRawColorCorrection(const OptionDump& opts) {
    for (const auto& v : opts.constraintEnumValues("color-correction")) {
        if (equalsIgnoreCase(trim(v), "None")) return v;
    }
    return std::nullopt;
}

std::optional<std::string> epsonRawGammaCorrection(const OptionDump& opts) {
    const auto values = opts.constraintEnumValues("gamma-correction");
    // ① "gamma=1.0" 포함 (D 레벨: 기본이 Gamma=1.8 이라 덮어써야 한다)
    for (const auto& v : values) {
        if (contains(removeSpaces(toLower(v)), "gamma=1.0")) return v;
    }
    // ② "User defined" (A/B 레벨: 초기화 때 항등 램프를 올린다)
    for (const auto& v : values) {
        if (equalsIgnoreCase(trim(v), "User defined")) return v;
    }
    return std::nullopt;
}

bool canReuseSinglePassOptionsDump(const OptionDump& opts, std::string_view backend) {
    if (backend != "genesys") return false;
    std::vector<std::string> nonInfrared;
    for (const auto& s : opts.enumValues("source")) {
        if (!isInfraredValue(s)) nonInfrared.push_back(s);
    }
    if (nonInfrared.size() != 1) return false;
    return isTransparencySource(nonInfrared.front());
}

std::optional<std::string> capabilityDumpMode(const OptionDump& opts) {
    const auto modeValues = opts.enumValues("mode");
    if (auto color = pickModeValue(modeValues, ColorMode::Color)) return color;
    return pickModeValue(modeValues, ColorMode::Gray);
}

std::optional<ColorMode> validatedColorMode(const OptionDump& opts,
                                            std::string_view backend,
                                            std::string_view deviceTypeHint) {
    if (const auto selected = opts.selectedEnumValue("mode")) {
        const std::string lowered = toLower(*selected);
        if (contains(lowered, "color")) return ColorMode::Color;
        if (contains(lowered, "gray") || contains(lowered, "grey")) return ColorMode::Gray;
        return std::nullopt;
    }
    const std::string type = toLower(deviceTypeHint);
    if (!opts.isActive("mode") && (contains(type, "film") || contains(type, "slide") ||
                                   isDedicatedFilmBackend(backend))) {
        return ColorMode::Color;
    }
    return std::nullopt;
}

std::optional<std::vector<std::string>> capabilityRedumpArguments(const OptionDump& baseDump,
                                                                  std::string_view devname) {
    const std::string backend = backendName(devname);
    const auto source = preferredTransparencySource(baseDump.enumValues("source"));
    const bool depthNeedsMode = baseDump.hasOption("depth") && !baseDump.isActive("depth");

    std::optional<std::string> mode;
    if (source.has_value() || depthNeedsMode) mode = capabilityDumpMode(baseDump);

    const auto selectedMode = mode.has_value() ? mode : baseDump.selectedEnumValue("mode");

    std::optional<std::string> colorCorrection;
    if (backend == "epson2" && selectedMode.has_value() &&
        contains(toLower(*selectedMode), "color")) {
        colorCorrection = epsonRawColorCorrection(baseDump);
    }
    std::optional<std::string> gammaCorrection;
    if (backend == "epson2") gammaCorrection = epsonRawGammaCorrection(baseDump);

    if (!source.has_value() && !mode.has_value() && !colorCorrection.has_value() &&
        !gammaCorrection.has_value()) {
        return std::nullopt;
    }

    std::vector<std::string> args{"-A", "-d", std::string(devname)};
    if (source.has_value()) {
        args.emplace_back("--source");
        args.push_back(*source);
    }
    if (mode.has_value()) {
        args.emplace_back("--mode");
        args.push_back(*mode);
    }
    if (colorCorrection.has_value()) {
        args.emplace_back("--color-correction");
        args.push_back(*colorCorrection);
    }
    if (gammaCorrection.has_value()) {
        args.emplace_back("--gamma-correction");
        args.push_back(*gammaCorrection);
    }
    return args;
}

MediaSelection resolveMedia(const OptionDump& opts,
                            const ScanOptions& options,
                            std::string_view deviceTypeHint) {
    MediaSelection media;

    std::string scannerID = options.scannerID;
    if (scannerID.rfind("sane-", 0) == 0) scannerID.erase(0, 5);
    const std::string backend = backendName(scannerID);

    const std::string normalizedDeviceType = toLower(deviceTypeHint);
    const bool dedicatedFilmDevice =
        !opts.isActive("source") && (contains(normalizedDeviceType, "film") ||
                                     contains(normalizedDeviceType, "slide") ||
                                     isDedicatedFilmBackend(backend));

    // 덤프가 없으면 **어떤 값도 추정하지 않는다.** production 은 이 상태를 오류로 만든다.
    if (opts.empty()) return media;

    media.dedicatedFilmDevice = dedicatedFilmDevice;

    const auto sources = opts.enumValues("source");
    const auto modeValues = opts.enumValues("mode");

    // --- 소스: 투과(비-IR) 우선. --source 가 없으면 생략 ---
    if (!sources.empty()) {
        const auto transparency = preferredTransparencySource(sources);
        media.source = transparency.has_value() ? *transparency : sources.front();
    }

    // --- 모드 ---
    media.mode = pickModeValue(modeValues, options.colorMode);
    media.irPassMode = pickModeValue(modeValues, ColorMode::Gray);

    // --- epson2 내부 처리 끄기. **활성일 때만 값을 정한다.** ---
    if (backend == "epson2" && opts.isActive("color-correction")) {
        media.colorCorrection = epsonRawColorCorrection(opts);
    }
    if (backend == "epson2" && opts.isActive("gamma-correction")) {
        media.gammaCorrection = epsonRawGammaCorrection(opts);
    }

    // --- 심도 ---
    media.fixedDepth = fixedDepth(opts, backend);
    std::vector<int> depthTokens;
    for (int t : opts.intTokens("depth")) {
        if (t >= 8) depthTokens.push_back(t);
    }
    if (options.bitDepth == BitDepth::Eight) {
        if (std::find(depthTokens.begin(), depthTokens.end(), 8) != depthTokens.end()) {
            media.depthArgument = 8;
        }
    } else {
        if (std::find(depthTokens.begin(), depthTokens.end(), 16) != depthTokens.end()) {
            media.depthArgument = 16;
        } else {
            std::optional<int> best;
            for (int t : depthTokens) {
                if (t > 8 && (!best.has_value() || t > *best)) best = t;
            }
            media.depthArgument = best;
        }
    }

    // --- 해상도: 정확히 지원하는 값만. 스냅하지 않는다(I-1). ---
    const auto resolutionRange = opts.numericRange("resolution");
    const int requestedDPI = options.resolutionDPI;
    if (requestedDPI > 0) {
        const auto spec = opts.resolutionSpec();
        if (spec.kind == ResolutionSpec::Kind::List) {
            if (std::find(spec.list.begin(), spec.list.end(), requestedDPI) != spec.list.end()) {
                media.resolvedDPI = requestedDPI;
            }
        } else if (spec.kind == ResolutionSpec::Kind::Range) {
            if (resolutionRange.has_value() &&
                util::containsExactly(*resolutionRange, static_cast<double>(requestedDPI))) {
                media.resolvedDPI = requestedDPI;
            }
        }
    }

    // --- 지오메트리 ---
    const auto xRangeMM = rangeWithUnit(opts, "x", "mm");
    const auto yRangeMM = rangeWithUnit(opts, "y", "mm");

    if (xRangeMM.has_value() && yRangeMM.has_value() && xRangeMM->maximum > 0.0 &&
        yRangeMM->maximum > 0.0) {
        // (a) mm 단위 장치
        if (util::containsExactly(*xRangeMM, options.scanArea.widthMM) &&
            util::containsExactly(*yRangeMM, options.scanArea.heightMM)) {
            media.widthMM = options.scanArea.widthMM;
            media.heightMM = options.scanArea.heightMM;
        }
        if (const auto leftRange = rangeWithUnit(opts, "l", "mm");
            leftRange.has_value() &&
            util::containsExactly(*leftRange, options.scanArea.originXMM)) {
            media.originXMM = options.scanArea.originXMM;
        }
        if (const auto topRange = rangeWithUnit(opts, "t", "mm");
            topRange.has_value() &&
            util::containsExactly(*topRange, options.scanArea.originYMM)) {
            media.originYMM = options.scanArea.originYMM;
        }
        if (backend == "epson2" && media.heightMM.has_value()) {
            const auto topRange = rangeWithUnit(opts, "t", "mm");
            const double topMinimum = topRange.has_value() ? topRange->minimum : 0.0;
            const double requestedHeight = *media.heightMM;
            const double aligned = util::epson2AlignedHeightMM(
                options.scanArea.originYMM, requestedHeight, *yRangeMM,
                topMinimum + yRangeMM->maximum);
            media.heightAlignmentMM = aligned - requestedHeight;
            media.heightMM = aligned;
        }
    } else if (const auto xRangePel = rangeWithUnit(opts, "x", "pel"),
               yRangePel = rangeWithUnit(opts, "y", "pel");
               requestedDPI > 0 && xRangePel.has_value() && yRangePel.has_value()) {
        // (b) pel 단위 장치 — -x/-y 를 픽셀로 보낸다
        media.widthPixels =
            util::pixelGeometryValue(options.scanArea.widthMM, requestedDPI, *xRangePel);
        media.heightPixels =
            util::pixelGeometryValue(options.scanArea.heightMM, requestedDPI, *yRangePel);
        if (const auto leftRange = rangeWithUnit(opts, "l", "pel"); leftRange.has_value()) {
            media.originXPixels =
                util::pixelGeometryValue(options.scanArea.originXMM, requestedDPI, *leftRange);
        }
        if (const auto topRange = rangeWithUnit(opts, "t", "pel"); topRange.has_value()) {
            media.originYPixels =
                util::pixelGeometryValue(options.scanArea.originYMM, requestedDPI, *topRange);
        }
    } else {
        // (c) 모서리 pel 좌표(tl-x/tl-y/br-x/br-y)
        //
        // **Swift 는 이것을 if/else-if 사슬로 쓴다.** 즉 앞의 두 갈래가 조건에서
        // 탈락했을 때만 여기 온다 — 앞 갈래가 "선택됐지만 값을 못 채운" 경우에는
        // 오지 않는다. 그 구분을 잃으면 mm 장치에서 containsExactly 가 실패했을 때
        // 엉뚱하게 코너 지오메트리를 시도하게 된다.
        const auto unitDPI = maximumResolutionDPI(opts);
        const auto leftRange = rangeWithUnit(opts, "tl-x", "pel");
        const auto topRange = rangeWithUnit(opts, "tl-y", "pel");
        const auto rightRange = rangeWithUnit(opts, "br-x", "pel");
        const auto bottomRange = rangeWithUnit(opts, "br-y", "pel");
        if (unitDPI.has_value() && leftRange && topRange && rightRange && bottomRange) {
            const auto left =
                util::pixelGeometryValue(options.scanArea.originXMM, *unitDPI, *leftRange);
            const auto top =
                util::pixelGeometryValue(options.scanArea.originYMM, *unitDPI, *topRange);
            const auto width = util::pixelGeometryLength(options.scanArea.widthMM, *unitDPI);
            const auto height = util::pixelGeometryLength(options.scanArea.heightMM, *unitDPI);
            if (left && top && width && height) {
                const long long right = *left + *width - 1;
                const long long bottom = *top + *height - 1;
                if (util::containsExactly(*rightRange, static_cast<double>(right)) &&
                    util::containsExactly(*bottomRange, static_cast<double>(bottom))) {
                    media.originXPixels = *left;
                    media.originYPixels = *top;
                    media.rightPixels = right;
                    media.bottomPixels = bottom;
                    media.usesCornerPixelGeometry = true;
                }
            }
        }
    }

    // --- 필름 타입 극성 ---
    std::optional<std::string> filmTypeOptionName;
    if (opts.isActive("film-type")) {
        filmTypeOptionName = "film-type";
    } else if (opts.isActive("type")) {
        filmTypeOptionName = "type";
    } else if (opts.isActive("negative")) {
        filmTypeOptionName = "negative";
    }
    media.filmTypeOptionName = filmTypeOptionName;
    media.hasFilmTypeOption = filmTypeOptionName.has_value();

    const bool sourceIsTransparency =
        !media.source.has_value() || isTransparencySource(*media.source);
    if (filmTypeOptionName.has_value() && sourceIsTransparency) {
        if (*filmTypeOptionName == "negative" &&
            (backend == "coolscan2" || backend == "coolscan3")) {
            // **필름 메타데이터가 아니라 스캐너 자체 색 반전이다.**
            // negaflow 가 원본 네거티브 밀도를 현상하므로 장치 반전은 항상 끈다.
            media.filmType = "no";
        } else {
            const bool preserveRawCoolscan =
                backend == "coolscan" && *filmTypeOptionName == "type";
            const bool wantPositive =
                preserveRawCoolscan || !requiresInversion(options.filmType);
            const std::string requestedPolarity = wantPositive ? "positive" : "negative";

            std::vector<std::string> polarityMatches;
            for (const auto& v : opts.enumValues(*filmTypeOptionName)) {
                if (contains(toLower(v), requestedPolarity)) polarityMatches.push_back(v);
            }
            if (requiresInversion(options.filmType) && !preserveRawCoolscan) {
                // 네거티브: "slide" 가 아닌 것을 먼저
                for (const auto& v : polarityMatches) {
                    if (!contains(toLower(v), "slide")) {
                        media.filmType = v;
                        break;
                    }
                }
            } else {
                // 포지티브: "slide" 를 먼저
                for (const auto& v : polarityMatches) {
                    if (contains(toLower(v), "slide")) {
                        media.filmType = v;
                        break;
                    }
                }
            }
            if (!media.filmType.has_value() && !polarityMatches.empty()) {
                media.filmType = polarityMatches.front();
            }
        }
    }

    // --- 범위와 표면 경계 ---
    media.scanLeftRange = rangeWithUnit(opts, "l", "mm");
    media.scanTopRange = rangeWithUnit(opts, "t", "mm");
    media.scanWidthRange = xRangeMM;
    media.scanHeightRange = yRangeMM;
    if (media.scanWidthRange.has_value()) {
        const double originMin =
            media.scanLeftRange.has_value() ? media.scanLeftRange->minimum : 0.0;
        media.scanSurfaceRightMM = originMin + media.scanWidthRange->maximum;
    }
    if (media.scanHeightRange.has_value()) {
        const double originMin =
            media.scanTopRange.has_value() ? media.scanTopRange->minimum : 0.0;
        media.scanSurfaceBottomMM = originMin + media.scanHeightRange->maximum;
    }

    // --- IR ---
    // **별도 파일로 검증할 수 있는 source/mode 만 쓴다.** coolscan3 의 --infrared 는
    // RGBI 한 프레임이고 stock scanimage 가 별도 IR TIFF 로 직렬화하지 못한다.
    // IRStrategy::CleanImage 는 여기서 **만들지 않는다** — 도달 불가 상태를 유지한다.
    // 근거: windows_docs/06-build/porting-map.md §3.5
    if (options.infraredEnabled) {
        std::optional<std::string> infraredSource;
        for (const auto& s : sources) {
            if (isInfraredValue(s)) {
                infraredSource = s;
                break;
            }
        }
        std::optional<std::string> infraredMode;
        for (const auto& m : modeValues) {
            if (contains(toLower(m), "infrared")) {
                infraredMode = m;
                break;
            }
        }
        if (infraredSource.has_value()) {
            media.irStrategy = IRStrategy{IRStrategy::Kind::SeparateSource, *infraredSource};
        } else if (infraredMode.has_value()) {
            media.irStrategy = IRStrategy{IRStrategy::Kind::SeparateMode, *infraredMode};
        }
    }

    // --- 톤 조정 ---
    // genesys 16-bit 에서는 밝기/대비를 없는 것으로 취급한다.
    // **근거가 코드에 기록되지 않았다**(실기 관측 추정). 근거 없이 제거하지 않는다.
    // 근거: windows_docs/02-frontend-contract/backend-quirks.md §1.3, Q-6
    const bool supportsHardwareToneAdjustments =
        !(backend == "genesys" && options.bitDepth == BitDepth::Sixteen);

    media.hasPreviewOption = opts.isActive("preview");
    media.hasBrightnessOption = supportsHardwareToneAdjustments && opts.isActive("brightness");
    media.hasContrastOption = supportsHardwareToneAdjustments && opts.isActive("contrast");
    media.hasScanExposureOption = opts.isActive("scan-exposure-time");
    media.hasModeOption = opts.isActive("mode");
    media.hasDepthOption = opts.isActive("depth");
    media.hasAdvanceOption = opts.isActive("advance");
    media.hasColorCorrectionOption = opts.isActive("color-correction");
    media.hasGammaCorrectionOption = opts.isActive("gamma-correction");
    media.brightnessRange =
        supportsHardwareToneAdjustments ? opts.numericRange("brightness") : std::nullopt;
    media.contrastRange =
        supportsHardwareToneAdjustments ? opts.numericRange("contrast") : std::nullopt;
    media.hardwareExposureRange = opts.numericRange("scan-exposure-time");
    media.resolutionRange = resolutionRange;

    return media;
}

}  // namespace negaflow::sane
