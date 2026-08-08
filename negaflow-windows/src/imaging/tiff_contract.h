// negaflow-scanner-sane — Windows adapter
// imaging/tiff_contract — TIFF 태그 판정. **순수 부분만.**
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend+ScanExecution.swift
//            (validatedScannedTIFF)
// 정본 문서: docs/04-imaging/tiff-validation.md §3
//
// ## 왜 `imaging/tiff` 가 셋으로 나뉘는가
//
// `process/` 와 같은 이유다 — 전부 플랫폼 의존이라고 보면 macOS 에서
// 아무것도 검증할 수 없는데, **판정 로직은 플랫폼과 무관하다.**
//
// ```text
// 순수 (여기)                    태그 값 → 통과/거부 판정. 메시지 문구.
// libtiff (imaging/tiff_io)      파일에서 태그와 픽셀을 읽고 쓴다.
//                                libtiff 는 macOS 에서도 빌드되므로 검증 가능.
// Win32 (미착수)                 §3.1 파일 계층. GetFileInformationByHandle,
//                                reparse point 거부, TOCTOU 방지.
// ```
//
// 이 헤더는 <windows.h> 도 <tiffio.h> 도 포함하지 않는다.
//
// ## 메시지가 곧 계약이다
//
// wire v2 event schema 에 code 필드가 없어서 **메시지 접두사가 유일한
// 전달 수단이다.** 같은 실패가 두 OS 에서 다른 문구로 보이면 안 된다(I-5).
// 그래서 macOS 가 검출하는 실패는 Swift 와 **글자까지 같은 문구**를 쓴다.
// 근거: docs/05-protocol/host-requirements.md §3.3
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstdint>
#include <optional>
#include <string>

#include "sane/capabilities.h"

namespace negaflow::imaging {

/// TIFF 태그 상수. libtiff 헤더를 끌어오지 않으려고 직접 둔다.
///
/// TIFF 6.0 규격 값이며 바뀌지 않는다. `imaging/tiff_io` 가
/// `static_assert` 로 libtiff 의 값과 일치함을 컴파일 시점에 확인한다 —
/// 여기 숫자가 틀리면 빌드가 깨지도록 유지한다.
namespace tifftag {

inline constexpr std::uint16_t kPhotometricMinIsWhite = 0;
inline constexpr std::uint16_t kPhotometricMinIsBlack = 1;
inline constexpr std::uint16_t kPhotometricRGB = 2;

inline constexpr std::uint16_t kPlanarConfigContig = 1;
inline constexpr std::uint16_t kPlanarConfigSeparate = 2;

inline constexpr std::uint16_t kSampleFormatUInt = 1;
inline constexpr std::uint16_t kSampleFormatInt = 2;
inline constexpr std::uint16_t kSampleFormatIEEEFP = 3;

inline constexpr std::uint16_t kCompressionNone = 1;

}  // namespace tifftag

/// 판정에 필요한 태그만 모은 것. 읽는 주체(libtiff / WIC / 테스트)와 무관하다.
struct TiffTags {
    std::uint32_t width = 0;
    std::uint32_t height = 0;
    std::uint16_t bitsPerSample = 0;
    std::uint16_t samplesPerPixel = 0;
    std::uint16_t photometric = 0;
    std::uint16_t planarConfig = tifftag::kPlanarConfigContig;

    /// 태그가 **없을 수 있다.** 없으면 UINT 로 본다(TIFF 규격 기본값).
    std::optional<std::uint16_t> sampleFormat;

    /// EXTRASAMPLES 로 명시된 추가 샘플 수.
    std::uint16_t extraSamples = 0;

    std::uint16_t compression = tifftag::kCompressionNone;

    /// IFD(페이지) 개수. **1이 아니면 거부한다.**
    std::uint32_t directoryCount = 1;

    /// BigTIFF(`II+\0` / `MM\0+`)인가. `scanimage` 는 만들지 않는다.
    bool bigTiff = false;

    /// ICCPROFILE(34675) / TRANSFERFUNCTION(301) 태그가 있는가.
    ///
    /// **검증에 쓰지 않는다.** 입력(`scanimage` 산출물)에 붙어 있어도 우리가
    /// 거부할 근거가 없기 때문이다. 이 둘이 중요한 것은 **우리가 쓰는 쪽**이다 —
    /// 프로파일이 박히면 본체가 감마 도메인으로 읽어 색이 무너지는데, 스캔은
    /// 성공하고 검증도 통과하므로 가장 늦게 발견된다.
    ///
    /// 그래서 여기 두는 목적은 둘이다: 진단(`diagnose` 서브커맨드)과,
    /// **우리 writer 가 태그를 붙이지 않았음을 테스트가 확인하는 것.**
    /// 근거: docs/10-lessons/host-pipeline-contract.md §2
    bool hasIccProfile = false;
    bool hasTransferFunction = false;
};

/// 검증 결과. 통과면 nullopt, 실패면 **그대로 사용자에게 보일 메시지**.
///
/// `sane::ValidationResult` 와 같은 관례다. 코드가 아니라 문자열을 돌려주는
/// 것은 Swift 가 `"...: requested 16, actual 8"` 처럼 값을 끼워 넣기 때문이다.
using TiffValidation = std::optional<std::string>;

/// 태그에서 색 모드를 판정한다. 판정 불가면 nullopt.
///
/// ```text
/// RGB          && spp >= 3   → Color
/// MINISBLACK   && spp == 1   → Gray
/// MINISWHITE   && spp == 1   → Gray   ← 판정은 되지만 §3.5 가 거부한다
/// 그 외                      → nullopt
/// ```
///
/// macOS 는 `CGColorSpace.model` 만 보므로 MINISWHITE/MINISBLACK 을
/// 구분하지 않는다. 여기서 나누는 것이 D-10 의 취지다.
/// 근거: docs/04-imaging/tiff-validation.md §3.3
[[nodiscard]] std::optional<sane::ColorMode> colorModeFromTags(const TiffTags& tags) noexcept;

/// 컨테이너 계층(§3.2). 단일 IFD 인가.
///
/// **멀티페이지를 통과시키면 호스트가 첫 페이지만 보고 나머지를 버린다** —
/// 조용한 데이터 손실이다.
[[nodiscard]] TiffValidation validateContainer(const TiffTags& tags);

/// 이미지 계층(§3.3). **Swift 의 검사 순서를 그대로 따른다.**
///
/// 순서가 계약인 이유: 심도와 색 모드가 **둘 다** 틀린 파일에서 어느 쪽
/// 메시지가 나오는지가 달라지면, 같은 실패가 두 OS 에서 다르게 보인다.
/// Swift 는 색 모드를 먼저 본다.
[[nodiscard]] TiffValidation validateImage(const TiffTags& tags,
                                           sane::BitDepth expectedBitDepth,
                                           sane::ColorMode expectedColorMode);

/// macOS 에 없는 추가 검사(D-10). **macOS 가 통과시킬 파일을 거부할 수 있다.**
///
/// 그래서 `validateImage` 뒤에 돌린다 — macOS 도 검출하는 실패는 먼저
/// 같은 문구로 걸러지고, 여기서는 macOS 가 놓치던 것만 남는다.
///
/// ```text
/// SAMPLEFORMAT   없거나 UINT 여야 한다. float TIFF 를 16-bit 로 오인하지 않도록
/// PLANARCONFIG   CONTIG 여야 한다. SEPARATE 는 병합 코드의 픽셀 레이아웃을 깬다
/// MINISWHITE     거부. 반전되면 GrainMend IR 이 정확히 반대로 동작한다
/// BigTIFF        거부. scanimage 는 만들지 않는다
/// EXTRASAMPLES   RGB 에서 spp > 3 이면 명시돼 있어야 한다
/// ```
///
/// 근거: docs/04-imaging/tiff-validation.md §3.4, §3.5
[[nodiscard]] TiffValidation validateStrictTags(const TiffTags& tags);

/// 컨테이너 → 이미지 → 추가 검사를 순서대로. 첫 실패에서 멈춘다.
[[nodiscard]] TiffValidation validateScannedTiffTags(const TiffTags& tags,
                                                     sane::BitDepth expectedBitDepth,
                                                     sane::ColorMode expectedColorMode);

/// 파일 계층(§3.1)의 **판정 부분**. 속성을 읽는 것은 호출자(Win32)가 한다.
///
/// Swift 원본:
///     guard values.isRegularFile == true,
///           values.isSymbolicLink != true,
///           (values.fileSize ?? 0) > 0
///
/// Windows 에서는 `GetFileInformationByHandle` 의 결과를 이 모양으로 옮긴다.
/// **핸들로 검증한 뒤 같은 핸들로 읽는다** — 경로로 다시 열면 TOCTOU 다.
[[nodiscard]] TiffValidation validateFileAttributes(bool isRegularFile,
                                                    bool isSymbolicLink,
                                                    std::uint64_t fileSize);

}  // namespace negaflow::imaging
