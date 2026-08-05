// negaflow-scanner-sane — Windows adapter
// imaging/tiff_io — libtiff 로 TIFF 를 읽고 쓴다.
//
// 이식 원본: Sources/SANEPluginCore/TIFFLoader.swift (loadScannerTIFF)
//            Sources/SANEPluginCore/SANEBackend+TIFFWriting.swift (writeRGB16TIFF)
//            Sources/SANEPluginCore/SANEBackend+Environment.swift (imageSize)
// 정본 문서: windows_docs/04-imaging/tiff-validation.md §4, §5, §6
//
// **이 파일만 <tiffio.h> 를 안다.** `imaging_logic`(align/merge/tiff_contract)은
// libtiff 를 링크하지 않는다 — 그 분리가 순수 부분을 libtiff 없이 검증할 수
// 있게 해 준다.
//
// ## Core Image 계층이 필요 없다
//
// macOS 는 TIFF → CGImage → CIImage(linearSRGB 재해석) → CIContext.render 로
// float 를 얻는다. spike N-1 이 그 경로가 `Float(v) / 65535.0` 과 **비트 동일**
// 임을 증명했으므로, 여기서는 libtiff 로 읽어 그냥 나눈다.
// `.colorSpace: linearSRGB` 는 **변환이 아니라 재해석**이므로 흉내낼 것이 없다.
// 근거: windows_docs/04-imaging/numerical-parity.md §0
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstdint>
#include <filesystem>
#include <optional>
#include <span>
#include <string_view>
#include <utility>

#include "imaging/merge.h"
#include "imaging/tiff_contract.h"
#include "sane/capabilities.h"

namespace negaflow::imaging::tiffio {

/// 검증이 통과했을 때 돌려주는 것. Swift `ScannedTIFFMetadata` 대응.
struct ScannedTiffMetadata {
    int width = 0;
    int height = 0;
    sane::BitDepth bitDepth = sane::BitDepth::Sixteen;
    sane::ColorMode colorMode = sane::ColorMode::Color;
};

/// libtiff 가 마지막 호출에서 낸 메시지. 없으면 빈 문자열.
///
/// **libtiff 메시지를 삼키지 않기 위한 창구다.** libtiff 는 기본적으로
/// stderr 에 직접 뱉는데 우리 stderr 는 호스트가 진단으로 읽으므로 막아야
/// 하고, 그렇다고 끄면 "왜 못 읽었는지"가 사라진다 — 지원하지 않는 코덱을
/// 만났을 때가 대표적이다(vcpkg 에서 `tiff[zip]` 만 켜므로 JPEG-in-TIFF 는
/// 읽지 못한다). 실패를 조용히 넘기지 않는다.
/// 근거: windows_docs/10-lessons/field-lessons.md §14
///
/// 스레드 지역이며 열기 호출마다 초기화된다. 진단용이지 제어 흐름용이 아니다 —
/// 검증 메시지는 Swift 와 글자까지 같아야 하므로 여기 내용을 섞지 않는다.
[[nodiscard]] std::string_view lastTiffMessage() noexcept;

/// 판정에 필요한 태그를 읽는다. 열지 못하면 nullopt.
///
/// `directoryCount` 와 `bigTiff` 도 채운다 — 전자는 IFD 를 끝까지 훑고,
/// 후자는 파일 매직(`II+\0` / `MM\0+`)을 직접 본다.
[[nodiscard]] std::optional<TiffTags> readTags(const std::filesystem::path& path);

/// 실제로 디코드되는가(§3.3 8번).
///
/// **헤더만 읽고 통과시키면 잘린 파일이 통과한다.** 첫 스트립과 마지막
/// 스트립을 실제로 읽는다 — 전체를 읽지 않고도 가장 흔한 손상(절단)을 잡는다.
[[nodiscard]] bool verifyDecodable(const std::filesystem::path& path);

/// 스캔 결과 TIFF 검증 전체. 통과면 nullopt 이고 `out` 이 채워진다.
///
/// 순서: 파일 속성 → 컨테이너 → 이미지 → 추가 검사(D-10) → 실제 디코드.
///
/// **파일 계층은 아직 이식 도중이다.** 지금은 `std::filesystem` 으로
/// regular file / symlink / 크기만 본다. `GetFileInformationByHandle` 기반
/// 핸들 검증(TOCTOU 방지, reparse point 거부)은 Win32 계층에서 붙인다.
/// 근거: windows_docs/04-imaging/tiff-validation.md §3.1
[[nodiscard]] TiffValidation validatedScannedTIFF(const std::filesystem::path& path,
                                                  sane::BitDepth expectedBitDepth,
                                                  sane::ColorMode expectedColorMode,
                                                  ScannedTiffMetadata* out);

/// 스캐너 raw TIFF 를 RGBA float 로 읽는다. 실패하면 nullopt.
///
/// ```text
/// 16-bit  → v / 65535.0f      ← N-1 이 증명한 경로
///  8-bit  → v / 255.0f        ← 미검증. depth 8 + 다중 노출에서만 닿는다
/// gray    → R = G = B = v
/// 알파는 항상 1.0
/// ```
///
/// **색 변환을 하지 않는다.** 값을 그대로 정규화만 한다.
[[nodiscard]] std::optional<FloatBitmap> loadScannerTIFF(const std::filesystem::path& path);

/// 16-bit RGB 인터리브를 TIFF 로 쓴다. 성공하면 true.
///
/// ```text
/// PHOTOMETRIC_RGB / SAMPLESPERPIXEL 3 / BITSPERSAMPLE 16
/// PLANARCONFIG_CONTIG / SAMPLEFORMAT_UINT / ORIENTATION_TOPLEFT
/// COMPRESSION_NONE
/// ICC 프로파일을 **넣지 않는다**
/// ```
///
/// **수동 endian 변환을 하지 않는다.** macOS 구현은 `bigEndian` 으로 뒤집어
/// 넘기지만(그리고 I-2 가 결과가 옳음을 확인했지만), libtiff 는 호스트 순서
/// 값을 받아 파일 헤더에 맞춰 쓴다. 뒤집으면 값이 망가진다.
///
/// 프로파일을 넣으면 본체가 감마 도메인으로 읽어 **색이 무너진다.**
/// 스캔은 성공하고 검증도 통과하므로 가장 늦게 발견되는 실패다.
/// 근거: windows_docs/10-lessons/host-pipeline-contract.md §2
///
/// 같은 디렉터리에 임시 이름으로 쓴 뒤 rename 한다(§6.2) — 쓰기 도중
/// 죽어도 불완전한 파일이 대상 경로에 남지 않는다.
[[nodiscard]] bool writeRGB16TIFF(std::span<const std::uint16_t> pixels,
                                  int width,
                                  int height,
                                  const std::filesystem::path& path);

/// 픽셀 크기만 읽는다. **실패는 예외가 아니라 (0, 0) 이다.**
///
/// IR 패스 결과가 읽히는지 보는 용도이며, 호출자가 (0,0) 을 보고 IR 을
/// 버린다. IR 실패가 본 스캔을 무효화하지 않는 것이 계약이다(I-10).
/// 근거: windows_docs/04-imaging/tiff-validation.md §4
[[nodiscard]] std::pair<int, int> imageSize(const std::filesystem::path& path);

}  // namespace negaflow::imaging::tiffio
