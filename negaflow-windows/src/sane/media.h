// negaflow-scanner-sane — Windows adapter
// sane/media — 요청 + 옵션 덤프 → "이 장치와 대화하는 법".
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend+Discovery.swift (resolveMedia)
// 정본 문서: windows_docs/02-frontend-contract/capability-model.md
//            windows_docs/10-lessons/driver-option-reference.md
//
// **이식에서 가장 큰 단일 함수다**(약 290행). 백엔드별 분기가 여기 몰려 있다.
//
// 값이 nullopt 이면 그 플래그를 **아예 전달하지 않는다**(장치 기본값 사용).
// 없는 옵션에 플래그를 넘기면 scanimage 가 즉시 실패한다(coolscan3 의 --mode 등).
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <optional>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

#include "sane/capabilities.h"
#include "sane/option_dump.h"
#include "util/numeric.h"

namespace negaflow::sane {

enum class FilmType { ColorNegative, ColorPositive, BwNegative, BwPositive };

[[nodiscard]] std::string_view filmTypeRawValue(FilmType t) noexcept;
[[nodiscard]] std::optional<FilmType> filmTypeFromRawValue(std::string_view s);
[[nodiscard]] bool requiresInversion(FilmType t) noexcept;

/// IR 획득 방식. **전부 -A 덤프에서 감지한다. 모델명 하드코딩 금지.**
struct IRStrategy {
    enum class Kind { None, SeparateSource, SeparateMode, CleanImage };
    Kind kind = Kind::None;
    std::string value;  // 소스명 / 모드명 / 옵션명

    /// 별도 스캔 패스가 필요한 전략인가.
    [[nodiscard]] bool needsSeparatePass() const noexcept {
        return kind == Kind::SeparateSource || kind == Kind::SeparateMode;
    }
    [[nodiscard]] bool usesInfrared() const noexcept { return kind != Kind::None; }

    friend bool operator==(const IRStrategy&, const IRStrategy&) = default;
};

/// 스캔 요청(호스트가 준 것). `PluginScanRequestV2.validatedOptions()` 의 결과에 대응.
struct ScanOptions {
    std::string scannerID;   // "sane-genesys:libusb:001:002"
    int resolutionDPI = 0;   // 0 = preview
    BitDepth bitDepth = BitDepth::Sixteen;
    ColorMode colorMode = ColorMode::Color;
    FilmType filmType = FilmType::ColorNegative;
    ScanArea scanArea{};
    bool infraredEnabled = false;
    bool multiExposureEnabled = false;
    std::optional<int> hardwareExposureTime;
    std::optional<double> brightnessAdjustment;
    std::optional<double> contrastAdjustment;
    bool outputRawTIFF = true;
};

/// 장치가 실제 노출하는 옵션으로 해석한 결과.
struct MediaSelection {
    std::optional<std::string> source;
    std::optional<std::string> mode;
    std::optional<std::string> filmType;
    std::optional<std::string> filmTypeOptionName;
    std::optional<int> depthArgument;
    /// `--depth` 가 없거나 비활성인 고정 심도 기기의 실제 심도.
    /// 값이 있으면 `--depth` 를 보내지 않으며, 요청 심도가 다르면 스캔 전에 실패시킨다.
    std::optional<BitDepth> fixedDepth;
    std::optional<int> resolvedDPI;

    std::optional<double> originXMM;
    std::optional<double> originYMM;
    std::optional<double> widthMM;
    std::optional<double> heightMM;
    /// epson2 정수 mm 절삭을 무해화하려고 heightMM 에 더한 보정량. 0 이면 무보정.
    double heightAlignmentMM = 0.0;

    bool hasPreviewOption = false;
    bool hasBrightnessOption = false;
    bool hasContrastOption = false;
    bool hasScanExposureOption = false;
    bool hasModeOption = false;
    bool hasDepthOption = false;
    bool hasFilmTypeOption = false;
    /// pieusb 의 `--advance` 기본값이 yes 다. 확인되면 **항상 no** 를 보낸다.
    bool hasAdvanceOption = false;

    /// epson2 내부 색/감마 처리를 끄려고 장치가 노출한 원문 enum 값.
    std::optional<std::string> colorCorrection;
    std::optional<std::string> gammaCorrection;
    bool hasColorCorrectionOption = false;
    bool hasGammaCorrectionOption = false;

    std::optional<util::OptionRange> brightnessRange;
    std::optional<util::OptionRange> contrastRange;
    std::optional<util::OptionRange> hardwareExposureRange;
    std::optional<util::OptionRange> resolutionRange;
    std::optional<util::OptionRange> scanLeftRange;
    std::optional<util::OptionRange> scanTopRange;
    std::optional<util::OptionRange> scanWidthRange;
    std::optional<util::OptionRange> scanHeightRange;
    std::optional<double> scanSurfaceRightMM;
    std::optional<double> scanSurfaceBottomMM;

    IRStrategy irStrategy;
    std::optional<std::string> irPassMode;  // 별도 IR 패스의 --mode (Gray 우선)

    bool dedicatedFilmDevice = false;

    std::optional<long long> originXPixels;
    std::optional<long long> originYPixels;
    std::optional<long long> widthPixels;
    std::optional<long long> heightPixels;
    std::optional<long long> rightPixels;
    std::optional<long long> bottomPixels;
    bool usesCornerPixelGeometry = false;
};

/// `--mode` 열거값(원문 대소문자)에서 요청 모드에 맞는 값을 고른다.
[[nodiscard]] std::optional<std::string> pickModeValue(const std::vector<std::string>& values,
                                                       ColorMode colorMode);

/// epson2 내부 색 보정을 끄는 값("None").
[[nodiscard]] std::optional<std::string> epsonRawColorCorrection(const OptionDump& opts);

/// epson2 선형 감마 값. **2단 규칙이다.**
///
///   ① 소문자·공백 제거 후 "gamma=1.0" 을 포함하는 첫 값   (D 레벨)
///   ② 없으면 트림 후 "User defined" 와 일치하는 첫 값       (A/B 레벨)
///
/// 감마를 **안 건드리는 것이 중립이 아니다** — `Default`(index 0)는 표시용 감마
/// 0x02 를 보낸다. `User defined` 만이 항등 램프(진짜 선형)다.
/// 근거: windows_docs/10-lessons/driver-option-reference.md §8.2
///
/// **비활성일 때 강제로 보내지 않는다. 되돌리지 마라.** 맥에서 커밋 `7f950dc`
/// 가 `82b7b32`("set the Epson linear gamma even when the option reports
/// inactive")를 되돌렸다. `OPT_GAMMA_CORRECTION` 의 비활성은 "지금 꺼져 있다"가
/// 아니라 **"이 하드웨어에 감마 명령이 없다"** 는 뜻이고, 그 상태에서 옵션을
/// 보내면 `attempted to set inactive option` 으로 스캔 전체가 실패한다.
/// 그래서 `resolveMedia` 는 활성일 때만 값을 정하고, 재덤프는 활성 여부와
/// 무관하게 싣는다. 되돌리려면 실기 증거가 필요하다.
[[nodiscard]] std::optional<std::string> epsonRawGammaCorrection(const OptionDump& opts);

/// 이 덤프 하나로 모든 소스를 대표할 수 있는가(추가 open 회피).
///
/// **성능 최적화가 아니라 신뢰성 요건이다.** 전용 필름 스캐너는 연속해서 여러 번
/// 열면 다음 획득이 실패할 수 있다(OpticFilm 실측). Flatbed 와 Transparency 를
/// 함께 가진 genesys 장치는 소스별 재검증을 그대로 수행한다.
/// 근거: windows_docs/02-frontend-contract/backend-quirks.md §1.2, I-8
[[nodiscard]] bool canReuseSinglePassOptionsDump(const OptionDump& opts,
                                                 std::string_view backend);

/// capability 재조회에 쓸 `-A` 인자. 재조회가 불필요하면 nullopt.
///
/// **모드는 필요할 때만 싣는다.** 장치를 한 번 더 여는 것이 위험하므로,
/// 이미 `--depth` 가 활성인 장치는 모드 때문에 다시 열지 않는다. 소스 때문에
/// 어차피 다시 열 때는 같은 호출에 모드를 함께 실어 추가 open 을 없앤다.
///
/// epson2 색/감마 값은 **활성 여부와 무관하게** 읽는다 — 앞선 옵션 적용으로
/// 활성화될 옵션을 같은 호출 뒤쪽에 배치하기 때문이다(의도된 비대칭).
[[nodiscard]] std::optional<std::vector<std::string>> capabilityRedumpArguments(
    const OptionDump& baseDump, std::string_view devname);

/// capability 재조회에 적용할 모드. Color 우선, 없으면 Gray.
/// Lineart 는 쓰지 않으므로 그 상태의 옵션을 capability 로 보고하지 않는다.
[[nodiscard]] std::optional<std::string> capabilityDumpMode(const OptionDump& opts);

/// 이 덤프가 **실제로 어느 모드에서 읽힌 것인가.**
///
/// capability 스냅샷에 실려서, 다른 모드로 스캔을 요청하면 그 덤프를
/// 재사용하지 않게 한다. Color 에서 읽은 depth/geometry 활성 상태를 Gray
/// 요청에 그대로 쓰면 적용할 수 없는 옵션을 적용 가능한 것으로 오판한다.
///
/// `--mode` 가 아예 없는 전용 필름 스캐너는 Color 로 본다 — 그 장치들은
/// 출력 프레임 형식으로 Color 를 고정한다.
[[nodiscard]] std::optional<ColorMode> validatedColorMode(const OptionDump& opts,
                                                          std::string_view backend,
                                                          std::string_view deviceTypeHint);

/// 요청 + 덤프 → MediaSelection.
[[nodiscard]] MediaSelection resolveMedia(const OptionDump& opts,
                                          const ScanOptions& options,
                                          std::string_view deviceTypeHint);

}  // namespace negaflow::sane
