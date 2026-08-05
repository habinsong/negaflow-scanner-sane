// negaflow-scanner-sane — Windows adapter
// imaging/merge — 다중 노출 병합과 다중 표본 평균.
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend+ExposureMergingCore.swift (217행, 전량)
//            Sources/SANEPluginCore/SANEBackend+ExposureMerge.swift (병합 코어 부분)
// 정본 문서: windows_docs/04-imaging/exposure-merge.md §4, §5
//
// **P0 비트 동일 대상이다.** 결과가 macOS 와 한 비트라도 다르면 같은 필름을
// 두 OS 에서 스캔했을 때 다른 픽셀이 나온다.
// 근거: windows_docs/04-imaging/numerical-parity.md §3.1
//
// ## Core Image 를 걷어냈다
//
// macOS 는 TIFF → CGImage → CIImage(linearSRGB) → CIContext.render(.RGBAf) 로
// float 를 얻는다. spike N-1 이 그 경로가 `Float(v) / 65535.0` 과 **비트 동일**
// 임을 증명했으므로, Windows 는 libtiff 로 읽어 직접 나눈다.
// 이 헤더는 이미 float 가 된 뒤를 다루므로 로드 방식과 무관하다.
// 근거: windows_docs/04-imaging/numerical-parity.md §0
//
// 픽셀 버퍼는 RGBA float 인터리브다: [r0,g0,b0,a0, r1,g1,b1,a1, ...].
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstdint>
#include <optional>
#include <span>
#include <string_view>
#include <vector>

#include "imaging/align.h"

namespace negaflow::imaging {

/// 실패 사유.
///
/// `sane::ScannerError` 를 직접 쓰지 않는 것은 그 헤더가 `sane/media.h`
/// (MediaSelection, ScanOptions …) 를 끌고 오기 때문이다. imaging 은 옵션 모델을
/// 알 필요가 없다. wire 계층(M5)이 `ScannerError{IoFailure, failureMessage(f)}`
/// 로 감싼다 — Swift 는 전부 `.ioFailure` 로 던진다.
enum class Failure {
    ExposureInputMismatch,     ///< 이미지 수와 노출 수가 다르거나 비어 있다
    ExposureReferenceInvalid,  ///< 기준 노출을 정할 수 없거나 0 이하다
    ExposureSizeInvalid,       ///< 폭/높이가 0 이하다
    MultiSampleLoadFailed,     ///< 표본이 하나도 없다
    MultiSampleSizeInvalid,    ///< 폭/높이가 0 이하다
};

/// Swift 가 던지는 메시지와 **글자까지 같다.** 사용자에게 그대로 보일 수 있고,
/// 두 플랫폼의 진단을 비교할 수 있어야 한다.
/// 근거: windows_docs/04-imaging/exposure-merge.md §8
[[nodiscard]] std::string_view failureMessage(Failure f) noexcept;

/// RGBA float 결과.
struct FloatBitmap {
    std::vector<float> pixels;
    int width = 0;
    int height = 0;
};

/// RGB 16비트 결과. **알파가 없다**(채널 3개 인터리브).
struct Bitmap16 {
    std::vector<std::uint16_t> pixels;
    int width = 0;
    int height = 0;
};

/// 성공이면 `failure` 가 nullopt. `sane::ValidationResult` 와 같은 관례다.
struct FloatBitmapOutcome {
    std::optional<Failure> failure;
    FloatBitmap bitmap;
};

struct Bitmap16Outcome {
    std::optional<Failure> failure;
    Bitmap16 bitmap;
};

/// 이미 float 로 렌더된 패스들. 전부 같은 width×height 여야 한다.
using ImageList = std::vector<std::span<const float>>;

/// 노출 시간으로 값을 선형 보정한다.
///
///     scale = Float(referenceExposure) / Float(exposureTime)
///
/// 짧은 노출은 값이 커지고 긴 노출은 작아진다. **선형 응답을 가정한다.**
/// 알파는 1 로 덮어쓴다.
///
/// `Float`(binary32) 로 계산한다. **double 로 승격하면 결과가 달라진다.**
/// 근거: windows_docs/04-imaging/exposure-merge.md §4.3
[[nodiscard]] std::vector<float> normalizeExposure(std::span<const float> pixels,
                                                   int exposureTime,
                                                   int referenceExposure);

/// 같은 계산을 호출자가 준 버퍼에 쓴다. 반복 호출에서 재할당을 피한다.
/// `normalizeExposure` 가 이것을 부르므로 **구현이 하나뿐이다.**
void normalizeExposureInto(std::span<const float> pixels,
                           int exposureTime,
                           int referenceExposure,
                           std::vector<float>& out);

/// 기준 노출에 가장 가까운 **첫** 원소의 인덱스.
///
/// Swift `min(by:)` 는 "엄격히 작으면 교체"라 동률에서 첫 원소가 남는다.
/// `std::min_element` 도 같은 규칙이지만, 의존하지 않고 직접 쓴다.
/// 비어 있으면 0 이다(Swift 의 `?? 0`).
/// 근거: windows_docs/04-imaging/exposure-merge.md §4.2
[[nodiscard]] std::size_t referenceExposureIndex(std::span<const int> exposureTimes,
                                                 int referenceExposure) noexcept;

/// 정렬 + 노출 정규화 + 픽셀별 병합.
///
/// **정렬 오프셋은 정규화된 이미지로 추정한다**(raw 가 아니다). Swift 가 그렇다.
///
/// 픽셀별 수식은 §4.4 다: 기준 노출의 **정규화 전** 값이 밝으면(0.82~0.97)
/// 짧은 노출 쪽으로, 어두우면(0.010~0.045) 긴 노출 쪽으로 최대 0.48 만큼 섞는다.
/// **상수 0.82 / 0.97 / 0.010 / 0.045 / 0.48 은 튜닝값이며 근거가 코드에 없다.
/// 바꾸지 않는다.**
[[nodiscard]] FloatBitmapOutcome alignedExposureNormalizedRGBAf(const ImageList& rendered,
                                                                std::span<const int> exposureTimes,
                                                                int referenceExposure,
                                                                int width,
                                                                int height);

/// 노출 정규화 없이 정렬 후 평균만 낸다.
///
/// **production 경로에서 호출되지 않는다.** `startSoftwareMultiPassScan` 이 항상
/// 노출 병합을 쓴다. macOS 에서도 테스트만 이 경로를 지난다
/// (`SANEBackendMultiSampleTests.swift`). 이식하되 그 표시를 유지한다.
/// 근거: windows_docs/04-imaging/exposure-merge.md §5
[[nodiscard]] FloatBitmapOutcome alignedAverageRGBAf(const ImageList& rendered,
                                                     int width,
                                                     int height);

/// 병합 후 16비트 RGB 로 양자화한다.
///
/// **절삭이다. 반올림이 아니다.** `0.5 * 65535 = 32767.5 → 32767`.
/// Swift `UInt16(Float)` 와 C++ `static_cast<uint16_t>` 가 둘 다 절삭이다.
/// `std::round` 후 캐스트로 "개선"하지 않는다.
/// 근거: windows_docs/04-imaging/numerical-parity.md §3.4
[[nodiscard]] Bitmap16Outcome mergeHardwareExposureBitmap(const ImageList& rendered,
                                                          std::span<const int> exposureTimes,
                                                          int width,
                                                          int height);

/// 평균 경로의 16비트 양자화. `alignedAverageRGBAf` 와 같은 이유로 테스트 전용이다.
[[nodiscard]] Bitmap16Outcome averageMultiSampleBitmap(const ImageList& rendered,
                                                       int width,
                                                       int height);

}  // namespace negaflow::imaging
