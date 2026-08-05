// SPDX-License-Identifier: GPL-2.0-or-later
//
// 메시지 문구를 바꾸지 않는다. 호스트가 파싱하지는 않지만 사용자에게 그대로
// 보이고, 같은 실패가 두 OS 에서 다르게 보이면 I-5 위반이다.

#include "imaging/tiff_contract.h"

namespace negaflow::imaging {

namespace {

using sane::BitDepth;
using sane::ColorMode;

/// Swift `BitDepth(rawValue:)` — 8 과 16 만 있다.
[[nodiscard]] std::optional<BitDepth> bitDepthFromSamples(std::uint16_t bitsPerSample) noexcept {
    if (bitsPerSample == 8) return BitDepth::Eight;
    if (bitsPerSample == 16) return BitDepth::Sixteen;
    return std::nullopt;
}

[[nodiscard]] std::string depthText(BitDepth d) {
    return std::to_string(static_cast<int>(d));
}

}  // namespace

std::optional<ColorMode> colorModeFromTags(const TiffTags& tags) noexcept {
    if (tags.photometric == tifftag::kPhotometricRGB && tags.samplesPerPixel >= 3) {
        return ColorMode::Color;
    }
    // MINISWHITE 도 여기서는 Gray 로 판정된다. macOS 가 그렇게 보기 때문이다.
    // 거부는 validateStrictTags 가 한다 — 검사 순서를 맞추기 위해서다.
    if ((tags.photometric == tifftag::kPhotometricMinIsBlack ||
         tags.photometric == tifftag::kPhotometricMinIsWhite) &&
        tags.samplesPerPixel == 1) {
        return ColorMode::Gray;
    }
    return std::nullopt;
}

TiffValidation validateContainer(const TiffTags& tags) {
    // Swift: CGImageSourceGetCount(source) == 1
    if (tags.directoryCount != 1) {
        return "scanimage 출력 형식이 단일 TIFF가 아닙니다.";
    }
    return std::nullopt;
}

TiffValidation validateImage(const TiffTags& tags,
                             BitDepth expectedBitDepth,
                             ColorMode expectedColorMode) {
    // Swift 는 decode 성공 / width / height / BitDepth(rawValue:) 를 **한 guard 에서**
    // 본다. 그래서 bitsPerSample = 12 인 파일도 "decode할 수 없습니다" 가 나온다.
    const auto actualBitDepth = bitDepthFromSamples(tags.bitsPerSample);
    if (!(tags.width > 0) || !(tags.height > 0) || !actualBitDepth) {
        return "scanimage TIFF를 실제 이미지로 decode할 수 없습니다.";
    }

    const auto actualColorMode = colorModeFromTags(tags);
    if (!actualColorMode) {
        return "scanimage TIFF color model이 RGB/Gray가 아닙니다.";
    }

    // **색 모드를 심도보다 먼저 본다.** 둘 다 틀린 파일에서 어느 메시지가
    // 나오는지가 갈리므로 순서를 바꾸지 않는다.
    if (*actualBitDepth != expectedBitDepth) {
        return "scanimage TIFF bitDepth 불일치: requested " + depthText(expectedBitDepth) +
               ", actual " + depthText(*actualBitDepth);
    }
    if (*actualColorMode != expectedColorMode) {
        return "scanimage TIFF colorMode 불일치: requested " +
               std::string(sane::colorModeRawValue(expectedColorMode)) + ", actual " +
               std::string(sane::colorModeRawValue(*actualColorMode));
    }
    return std::nullopt;
}

TiffValidation validateStrictTags(const TiffTags& tags) {
    // BigTIFF — scanimage 는 만들지 않는다. 4 GB 초과 대응은 Q-11 에서 정한다.
    if (tags.bigTiff) {
        return "scanimage 출력이 BigTIFF입니다. 표준 TIFF만 지원합니다.";
    }

    // float TIFF 를 16-bit 정수로 오인하면 값이 통째로 엉뚱해진다.
    // 태그가 없으면 규격 기본값(UINT)이므로 통과다.
    if (tags.sampleFormat && *tags.sampleFormat != tifftag::kSampleFormatUInt) {
        return "scanimage TIFF sample format이 부호 없는 정수가 아닙니다.";
    }

    // SEPARATE 는 채널이 평면별로 떨어져 있어 (y*w+x)*spp+c 인덱싱이 깨진다.
    if (tags.planarConfig != tifftag::kPlanarConfigContig) {
        return "scanimage TIFF planar configuration이 interleaved가 아닙니다.";
    }

    // MINISWHITE 는 0 이 흰색이다. 밀도 의미가 반전되면 IR 처리가 정확히
    // 반대로 동작한다 — 스캔은 성공하고 검증도 통과하므로 가장 늦게 발견된다.
    if (tags.photometric == tifftag::kPhotometricMinIsWhite) {
        return "scanimage TIFF photometric이 MINISWHITE입니다. 밝기 의미가 반전됩니다.";
    }

    // RGB 에서 채널이 3개를 넘으면 그 여분이 무엇인지 명시돼 있어야 한다.
    if (tags.photometric == tifftag::kPhotometricRGB && tags.samplesPerPixel > 3 &&
        tags.extraSamples == 0) {
        return "scanimage TIFF에 정체가 명시되지 않은 추가 샘플이 있습니다.";
    }
    return std::nullopt;
}

TiffValidation validateScannedTiffTags(const TiffTags& tags,
                                       BitDepth expectedBitDepth,
                                       ColorMode expectedColorMode) {
    if (auto container = validateContainer(tags)) return container;
    if (auto image = validateImage(tags, expectedBitDepth, expectedColorMode)) return image;
    return validateStrictTags(tags);
}

TiffValidation validateFileAttributes(bool isRegularFile,
                                      bool isSymbolicLink,
                                      std::uint64_t fileSize) {
    if (!isRegularFile || isSymbolicLink || fileSize == 0) {
        return "scanimage 출력이 비어 있거나 regular file이 아닙니다.";
    }
    return std::nullopt;
}

}  // namespace negaflow::imaging
