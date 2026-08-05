// negaflow-scanner-sane — Windows adapter
// wire/request — 호스트 요청의 **입력 관문**. 1단계 검증.
//
// 이식 원본: Sources/SANEPluginCore/PluginProtocolV2.swift
//            (PluginScanRequestV2.validatedOptions)
// 정본 문서: windows_docs/02-frontend-contract/exact-option-contract.md §3
//
// **검사 순서가 계약이다.** 같은 요청이 두 OS 에서 같은 오류를 내야 한다 —
// wire v2 event schema 에 code 필드가 없어 메시지가 유일한 전달 수단이다(I-5).
// 순서를 바꾸면 먼저 걸리는 조건이 달라져 문구가 갈린다.
//
// 이 헤더는 <windows.h> 를 포함하지 않는다. 경로 판정까지 순수 문자열 처리다.
//
// ## 왜 경로 정책을 주입받는가
//
// 11개 가드 중 **9번(outputPath)만 플랫폼별로 갈린다.** macOS 는
// `URL(fileURLWithPath:).path == outputPath && isAbsolutePath` 로 POSIX 절대
// 경로를 요구하고, Windows 는 드라이브 절대 경로에 훨씬 많은 것을 요구한다
// (exact-option-contract §3.1 의 9행 표).
//
// 정책을 고정하면 파리티가 불가능해진다 — Swift 를 통과하는 경로는 Windows 에서
// 전부 거부되고, 그 반대도 마찬가지라 9번 이후 가드에 도달할 수 없다.
// 그래서 **정책을 갈아 끼울 수 있게** 했다:
//
// ```text
// WindowsAbsolute   제품 정책. 단위 테스트가 §3.1 표를 항목별로 고정한다
// PosixAbsolute     파리티 전용. Swift 원본과 가드 순서·문구를 대조한다
// ```
//
// 이렇게 나누면 "가드 순서와 메시지"(공통)와 "무엇이 유효한 경로인가"(플랫폼)를
// 각각 제대로 검증할 수 있다. 하나로 뭉치면 둘 다 어중간해진다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <optional>
#include <string>
#include <string_view>

#include "sane/media.h"
#include "sane/validate.h"

namespace negaflow::wire {

/// `outputPath` 판정 정책.
enum class PathPolicy {
    /// 제품 정책. `X:\...` 드라이브 절대 경로만 통과한다.
    WindowsAbsolute,
    /// **파리티 전용.** macOS 원본과 같은 판정(POSIX 절대 경로).
    /// production 코드에서 쓰지 않는다.
    PosixAbsolute,
};

/// 호스트가 보낸 v2 scan 요청. JSON 디코딩 결과에 대응한다.
///
/// 필드 이름과 타입은 negaflow 본체
/// (`ScannerKit/ScannerPluginManifest.swift`)와 일치해야 한다.
struct ScanRequestV2 {
    int protocolVersion = 2;
    std::string requestID;  // UUID 문자열
    std::string deviceID;
    int resolutionDPI = 0;
    int bitDepth = 16;
    std::string colorMode;
    std::string filmType;
    bool preview = false;
    bool multiExposure = false;
    bool infrared = false;
    std::optional<double> brightnessAdjustment;
    std::optional<double> contrastAdjustment;
    sane::ScanArea scanArea{};
    std::optional<int> hardwareExposureTime;
    bool outputRawTIFF = true;
    std::optional<std::string> capabilityToken;
    std::string outputPath;
};

/// `outputPath` 가 정책을 만족하는가.
///
/// **경로 문자열 비교만으로 보안을 끝내지 않는다.** 실제 파일을 만든 뒤
/// `GetFinalPathNameByHandleW` 로 최종 경로를 다시 확인하고 reparse point 가
/// 아님을 확인한다 — 그것은 Win32 계층의 일이다(child-process §7).
/// 여기서 막는 것은 **문자열 수준에서 이미 틀린 것**이다.
///
/// `WindowsAbsolute` 가 거부하는 것(exact-option-contract §3.1):
///
/// ```text
/// 드라이브 상대   C:foo            현재 디렉터리에 따라 달라진다
/// 루트 상대       \foo             현재 드라이브에 따라 달라진다
/// UNC             \\server\share   호스트 staging 은 로컬 볼륨 전제
/// 장치 네임스페이스 \\?\ \\.\ \??\  정규화를 우회한다
/// 구성요소        . .. 빈 것        상위로 탈출할 수 있다
/// 예약 이름       CON PRN NUL COM1  파일이 아니라 장치로 열린다
/// 후행 . 또는 공백                  Win32 가 조용히 잘라내 다른 파일을 연다
/// ADS             a.tiff:stream     본체가 못 읽는 곳에 쓰게 된다
/// ```
///
/// 슬래시(`/`)는 Win32 가 구분자로 받아들이지만 **거부한다** — 정규화하면
/// 입력과 바이트가 달라지고, §3.1 이 "바이트 동일"을 요구한다.
[[nodiscard]] bool isAcceptableOutputPath(std::string_view path, PathPolicy policy) noexcept;

/// 1단계 검증. 통과면 nullopt 이고 `out` 에 `ScanOptions` 가 채워진다.
///
/// 실패 메시지는 Swift 와 **글자까지 같다.** 9번(경로)만 정책에 따라 달라지는데,
/// 그 경우에도 문구는 같다 — 호스트가 보는 것은 "경로가 유효하지 않다"이지
/// "어느 규칙을 어겼는가"가 아니다.
///
/// 오류 코드는 전부 `unsupportedOption` 이다(Swift 와 같음).
[[nodiscard]] sane::ValidationResult validateScanRequest(const ScanRequestV2& request,
                                                         PathPolicy policy,
                                                         sane::ScanOptions* out);

}  // namespace negaflow::wire
