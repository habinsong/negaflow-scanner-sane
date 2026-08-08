// negaflow-scanner-sane — Windows adapter
// util/numeric — 순수 수치 유틸.
//
// 이식 원본: Sources/SANEPluginCore/ScannerModel.swift (ScannerOptionRange)
//            Sources/SANEPluginCore/SANEBackend+Discovery.swift
//            Sources/SANEPluginCore/SANEBackend+ScanExecution.swift (saneNumber)
//
// 이 헤더는 <windows.h> 도 libtiff 도 포함하지 않는다. sane_logic 계약이다.
// 근거: windows_docs/06-build/toolchain-and-layout.md §4.1
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <optional>
#include <span>
#include <string>

namespace negaflow::util {

/// SANE 옵션의 수치 제약. step 이 없으면 연속 범위다.
///
/// Swift 원본: ScannerOptionRange
struct OptionRange {
    double minimum = 0.0;
    double maximum = 0.0;
    std::optional<double> step;
};

/// 값이 범위 안에 **정확히** 존재하는가.
///
/// 가장 가까운 값으로 스냅하지 않는다. 이것이 I-1(정확한 옵션 계약)의 바닥이다.
/// 근거: windows_docs/02-frontend-contract/exact-option-contract.md
///
/// Swift 원본:
///     guard value.isFinite, value >= minimum, value <= maximum else { return false }
///     guard let step, step > 0 else { return true }
///     let offset = (value - minimum) / step
///     return abs(offset - offset.rounded()) <= 1e-7
///
/// `offset.rounded()` 는 Swift 기본값인 "half away from zero" 다.
/// C++ 의 std::round 가 같은 규칙이므로 그대로 쓴다(std::nearbyint 아님 — 그것은
/// 현재 반올림 모드를 따르며 기본이 half-to-even 이다).
[[nodiscard]] bool containsExactly(const OptionRange& range, double value) noexcept;

/// `scanimage` 인자로 넣을 수 형식.
///
/// Swift 원본:
///     if value.rounded() == value { return String(Int(value)) }
///     return String(value)
///
/// **로케일 독립이어야 한다.** 한국어/독일어 Windows 에서 소수점이 ','
/// 가 되는 순간 scanimage 가 파싱에 실패한다.
/// 지수 표기를 내지 않는다.
[[nodiscard]] std::string saneNumber(double value);

/// epson2 의 정수 mm 절삭을 무해화한 높이.
///
/// backend/epson2-ops.c 의 e2_init_parameters:
///     ((int) SANE_UNFIX(s->val[OPT_BR_Y].w) / MM_PER_INCH * dpi + 0.5) - s->top
/// `(int)` 캐스트가 나눗셈보다 먼저 걸린다(1.4.0, master 동일).
///
/// **넓히는 쪽을 먼저 시도한다.** 좁히면 필름이 잘리고, 넓히면 여백이 조금 더
/// 들어올 뿐이다. 실패 방향을 고르는 문제이지 정확도 문제가 아니다.
/// 근거: windows_docs/10-lessons/driver-option-reference.md §14.1
///
/// 넷 중 하나를 돌려준다: 그대로 / 올림 / 내림 / 요청값.
[[nodiscard]] double epson2AlignedHeightMM(double originYMM,
                                           double heightMM,
                                           const OptionRange& range,
                                           std::optional<double> surfaceBottomMM) noexcept;

/// mm → pel 좌표(원점·경계용). 범위에 정확히 존재하지 않으면 nullopt.
///
/// coolscan 계열은 -x/-y 가 pel 단위다. mm 값을 넘기면 36 mm 가 36픽셀이 된다.
[[nodiscard]] std::optional<long long> pixelGeometryValue(double millimeters,
                                                          int dpi,
                                                          const OptionRange& range) noexcept;

/// mm → pel 길이(폭·높이용). 범위 검사가 없고 최소 1을 요구한다.
[[nodiscard]] std::optional<long long> pixelGeometryLength(double millimeters,
                                                           int unitDPI) noexcept;

/// 다중 노출 병합의 기준 노출 시간 — **고유값을 정렬한 뒤 가운데**.
///
/// Swift 원본:
///     let unique = Array(Set(exposureTimes)).sorted()
///     guard !unique.isEmpty else { return nil }
///     return unique[unique.count / 2]
///
/// 중복을 먼저 제거하므로 `[11000, 11000, 14000, 30000]` 도 `[11000, 14000, 30000]`
/// 과 같은 14000 을 낸다. 표본 반복(samplesPerStop)이 기준을 흔들지 않게 하는
/// 것이 이 순서의 목적이다.
///
/// 짝수 개면 위쪽 중앙이다(`count / 2` 는 절삭 나눗셈).
/// 근거: windows_docs/04-imaging/exposure-merge.md §4.2
///
/// 이 함수가 `imaging` 이 아니라 여기 있는 것은 porting-map §2.7 의 배정이다 —
/// 순수 정수 연산이라 imaging 을 링크하지 않는 곳에서도 쓸 수 있다.
[[nodiscard]] std::optional<int> referenceExposureTime(std::span<const int> exposureTimes);

}  // namespace negaflow::util
