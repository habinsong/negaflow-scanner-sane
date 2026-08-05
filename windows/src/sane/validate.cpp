// SPDX-License-Identifier: GPL-2.0-or-later

#include "sane/validate.h"

#include <cctype>
#include <cmath>

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

[[nodiscard]] ScannerError unsupported(std::string message) {
    return ScannerError{ErrorCode::UnsupportedOption, std::move(message)};
}

}  // namespace

std::string_view errorCodeRawValue(ErrorCode c) noexcept {
    switch (c) {
        case ErrorCode::NotConnected: return "notConnected";
        case ErrorCode::Busy: return "busy";
        case ErrorCode::UnsupportedOption: return "unsupportedOption";
        case ErrorCode::DriverConflict: return "driverConflict";
        case ErrorCode::IoFailure: return "ioFailure";
        case ErrorCode::Cancelled: return "cancelled";
        case ErrorCode::Timeout: return "timeout";
        case ErrorCode::Unknown: return "unknown";
    }
    return "unknown";
}

std::string ScannerError::description() const {
    const std::string raw(errorCodeRawValue(code));
    return message.empty() ? raw : raw + ": " + message;
}

ValidationResult validateAdjustment(std::optional<double> value,
                                    const std::optional<util::OptionRange>& range,
                                    std::string_view name) {
    if (!value.has_value()) return std::nullopt;
    // 0 은 "조정하지 않음"이므로 범위가 없어도 통과한다.
    if (*value == 0.0 && !range.has_value()) return std::nullopt;
    if (!range.has_value() || !util::containsExactly(*range, *value)) {
        return unsupported("요청 " + std::string(name) + " 값을 정확히 적용할 수 없습니다.");
    }
    return std::nullopt;
}

ValidationResult validateExactOptions(const ScanOptions& options, const MediaSelection& media) {
    const bool isPreview = options.resolutionDPI == 0;

    // --- 해상도 ---
    if (isPreview) {
        if (!media.hasPreviewOption) {
            return unsupported("scanimage -A에 --preview가 없습니다.");
        }
    } else {
        if (!media.resolvedDPI.has_value() || *media.resolvedDPI != options.resolutionDPI) {
            return unsupported("요청 resolution " + std::to_string(options.resolutionDPI) +
                               "dpi를 정확히 적용할 수 없습니다.");
        }
    }

    // --- 비트 심도 ---
    if (media.fixedDepth.has_value()) {
        // 고정 심도 기기는 --depth 를 보낼 수 없다. 요청이 그 값과 같을 때만 통과.
        if (*media.fixedDepth != options.bitDepth) {
            return unsupported("이 스캐너는 " +
                               std::to_string(static_cast<int>(*media.fixedDepth)) +
                               "-bit 고정이라 " +
                               std::to_string(static_cast<int>(options.bitDepth)) +
                               "-bit 요청을 적용할 수 없습니다.");
        }
    } else {
        if (!media.hasDepthOption || !media.depthArgument.has_value()) {
            return unsupported("요청 bitDepth를 정확히 적용할 --depth가 없습니다.");
        }
        const int depth = *media.depthArgument;
        if (options.bitDepth == BitDepth::Eight && depth != 8) {
            return unsupported("8-bit 요청을 정확히 적용할 수 없습니다.");
        }
        if (options.bitDepth == BitDepth::Sixteen && depth <= 8) {
            return unsupported("16-bit 요청을 정확히 적용할 수 없습니다.");
        }
    }

    // --- 색 모드 ---
    if (media.hasModeOption && media.mode.has_value()) {
        const std::string normalizedMode = toLower(*media.mode);
        switch (options.colorMode) {
            case ColorMode::Color:
                if (!contains(normalizedMode, "color")) {
                    return unsupported("color 요청을 정확히 적용할 수 없습니다.");
                }
                break;
            case ColorMode::Gray:
                if (!(contains(normalizedMode, "gray") || contains(normalizedMode, "grey"))) {
                    return unsupported("gray 요청을 정확히 적용할 수 없습니다.");
                }
                break;
            case ColorMode::Lineart:
            case ColorMode::Infrared:
                return unsupported(
                    "lineart/infrared primary mode는 protocol v2에서 지원하지 않습니다.");
        }
    } else {
        // --mode 가 없으면 전용 필름 장치 + color 요청일 때만 통과.
        if (!media.dedicatedFilmDevice || options.colorMode != ColorMode::Color) {
            return unsupported("요청 colorMode를 정확히 적용할 --mode가 없습니다.");
        }
    }

    // --- 소스 ---
    if (media.source.has_value() && !isTransparencySource(*media.source)) {
        return unsupported("투과 필름 source를 정확히 선택할 수 없습니다.");
    }

    // --- 필름 극성 ---
    if (media.hasFilmTypeOption && !media.filmType.has_value()) {
        return unsupported("요청 filmType polarity를 정확히 적용할 수 없습니다.");
    }

    // --- 백엔드별 필수 조건 ---
    std::string scannerID = options.scannerID;
    if (scannerID.rfind("sane-", 0) == 0) scannerID.erase(0, 5);
    const std::string backend = backendName(scannerID);

    if (backend == "pieusb" && !media.hasAdvanceOption) {
        // 자동 이동을 끌 수 없는데 스캔하면 사용자의 필름 배치가 예상 없이 움직인다.
        return unsupported("pieusb의 자동 슬라이드 이동을 끌 활성 --advance 옵션이 없습니다.");
    }
    if (backend == "epson2") {
        if (media.hasColorCorrectionOption && !media.colorCorrection.has_value()) {
            return unsupported("epson2의 내부 color correction을 끌 수 없습니다.");
        }
        if (media.hasGammaCorrectionOption && !media.gammaCorrection.has_value()) {
            return unsupported("epson2의 선형 gamma 설정을 정확히 적용할 수 없습니다.");
        }
    }

    // --- 지오메트리 ---
    if (media.usesCornerPixelGeometry) {
        if (!media.originXPixels.has_value() || !media.originYPixels.has_value() ||
            !media.rightPixels.has_value() || !media.bottomPixels.has_value()) {
            return unsupported("요청 scanArea를 pel 모서리 좌표로 적용할 수 없습니다.");
        }
    } else if (media.widthPixels.has_value() && media.heightPixels.has_value()) {
        if (!media.originXPixels.has_value() || !media.originYPixels.has_value()) {
            if (options.scanArea.originXMM != 0.0 || options.scanArea.originYMM != 0.0) {
                return unsupported("요청 scanArea 원점을 pel 단위로 적용할 수 없습니다.");
            }
        }
    } else if (isPreview && media.dedicatedFilmDevice) {
        if (options.scanArea.originXMM != 0.0 || options.scanArea.originYMM != 0.0) {
            return unsupported("preview scanArea 원점을 적용할 수 없습니다.");
        }
    } else {
        // 높이는 백엔드 절삭을 무해화하려고 1mm 미만으로 정렬될 수 있다.
        // **계약은 요청값이 아니라 실제로 보낼 값을 기준으로 확인한다.**
        const double appliedHeightMM = options.scanArea.heightMM + media.heightAlignmentMM;
        const bool ok =
            media.scanWidthRange.has_value() && media.scanHeightRange.has_value() &&
            util::containsExactly(*media.scanWidthRange, options.scanArea.widthMM) &&
            util::containsExactly(*media.scanHeightRange, appliedHeightMM) &&
            std::fabs(media.heightAlignmentMM) < 1.0 + 1e-9 &&
            media.widthMM.has_value() && *media.widthMM == options.scanArea.widthMM &&
            media.heightMM.has_value() && *media.heightMM == appliedHeightMM;
        if (!ok) {
            return unsupported("요청 scanArea를 mm 또는 pel 단위로 정확히 적용할 수 없습니다.");
        }

        if (media.scanLeftRange.has_value() && media.scanTopRange.has_value()) {
            const bool originOk =
                util::containsExactly(*media.scanLeftRange, options.scanArea.originXMM) &&
                util::containsExactly(*media.scanTopRange, options.scanArea.originYMM) &&
                media.originXMM.has_value() && *media.originXMM == options.scanArea.originXMM &&
                media.originYMM.has_value() && *media.originYMM == options.scanArea.originYMM;
            if (!originOk) {
                return unsupported("요청 scanArea 원점을 mm 단위로 정확히 적용할 수 없습니다.");
            }
        } else if (options.scanArea.originXMM != 0.0 || options.scanArea.originYMM != 0.0) {
            return unsupported("요청 scanArea 원점을 적용할 -l/-t 옵션이 없습니다.");
        }

        if (media.scanSurfaceRightMM.has_value() &&
            options.scanArea.originXMM + options.scanArea.widthMM >
                *media.scanSurfaceRightMM + 1e-9) {
            return unsupported("요청 scanArea의 원점+폭이 스캔 가능한 오른쪽 경계를 넘습니다.");
        }
        if (media.scanSurfaceBottomMM.has_value() &&
            options.scanArea.originYMM + appliedHeightMM > *media.scanSurfaceBottomMM + 1e-9) {
            return unsupported("요청 scanArea의 원점+높이가 스캔 가능한 아래쪽 경계를 넘습니다.");
        }
    }

    // --- 밝기·대비 ---
    if (auto e = validateAdjustment(options.brightnessAdjustment, media.brightnessRange,
                                    "brightness")) {
        return e;
    }
    if (auto e = validateAdjustment(options.contrastAdjustment, media.contrastRange, "contrast")) {
        return e;
    }

    // --- 단일 하드웨어 노출 ---
    if (options.hardwareExposureTime.has_value()) {
        const bool ok = media.hasScanExposureOption && media.hardwareExposureRange.has_value() &&
                        util::containsExactly(*media.hardwareExposureRange,
                                              static_cast<double>(*options.hardwareExposureTime));
        if (!ok) {
            return unsupported("요청 hardwareExposureTime을 정확히 적용할 수 없습니다.");
        }
    }

    // --- 다중 노출 ---
    if (options.multiExposureEnabled) {
        if (options.colorMode != ColorMode::Color || options.bitDepth != BitDepth::Sixteen) {
            return unsupported("Multi-Exposure는 16-bit color 출력만 지원합니다.");
        }
        bool planOk = media.hasScanExposureOption && media.hardwareExposureRange.has_value();
        if (planOk) {
            // **세 값 전부**가 범위에 정확히 있어야 한다(allSatisfy).
            for (int t : kHardwareExposureTimes) {
                if (!util::containsExactly(*media.hardwareExposureRange,
                                           static_cast<double>(t))) {
                    planOk = false;
                    break;
                }
            }
        }
        if (!planOk) {
            return unsupported("Multi-Exposure 노출 계획을 장치가 정확히 지원하지 않습니다.");
        }
        if (options.infraredEnabled && !media.irStrategy.needsSeparatePass()) {
            return unsupported("이 장치의 IR 방식은 Multi-Exposure와 정확히 결합할 수 없습니다.");
        }
    }

    // --- IR ---
    if (options.infraredEnabled) {
        // None 과 CleanImage 는 별도 IR 파일을 만들지 못한다.
        if (!media.irStrategy.needsSeparatePass()) {
            return unsupported("별도 IR 채널을 정확히 획득할 수 없습니다.");
        }
    }

    return std::nullopt;
}

}  // namespace negaflow::sane
