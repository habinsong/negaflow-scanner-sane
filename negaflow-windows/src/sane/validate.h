// negaflow-scanner-sane — Windows adapter
// sane/validate — 2단계 검증. **정확한 옵션만 적용한다.**
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend+ScanExecution.swift
//            (validateExactOptions, validateAdjustment)
// 정본 문서: windows_docs/02-frontend-contract/exact-option-contract.md
//
// I-1: 요청한 값을 정확히 적용할 수 없으면 **스캔을 시작하지 않는다.**
// 가장 가까운 값으로 스냅하지 않는다. "거의 맞으니까 괜찮다"가 없다.
//
// 깨지면: 같은 필름을 같은 설정으로 두 OS 에서 스캔했을 때 다른 픽셀이 나온다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <optional>
#include <string>

#include "sane/media.h"

namespace negaflow::sane {

/// 어댑터가 내는 오류 코드. wire 에서는 `"<code>: <message>"` 형태로 나간다.
///
/// **8개를 유지한다.** 본체는 18개 stable category 를 쓰지만 v2 event schema 에
/// code 필드가 없어 메시지 접두사가 유일한 전달 수단이다. Windows 에서만 늘리면
/// 같은 실패가 OS 마다 다른 문구로 보인다(I-5).
/// 근거: windows_docs/05-protocol/host-requirements.md §3.3
enum class ErrorCode {
    NotConnected,
    Busy,
    UnsupportedOption,
    DriverConflict,
    IoFailure,
    Cancelled,
    Timeout,
    Unknown,
};

[[nodiscard]] std::string_view errorCodeRawValue(ErrorCode c) noexcept;

struct ScannerError {
    ErrorCode code = ErrorCode::Unknown;
    std::string message;

    /// Swift `errorDescription` 과 같은 형태: 메시지가 비면 코드만.
    [[nodiscard]] std::string description() const;
};

/// 검증 결과. 통과면 nullopt.
using ValidationResult = std::optional<ScannerError>;

/// 밝기/대비 같은 조정값 검증.
///
/// **0 은 범위가 없어도 통과한다.** "조정하지 않음"과 같기 때문이다.
/// 0 이 아닌 값은 범위에 정확히 있어야 한다.
[[nodiscard]] ValidationResult validateAdjustment(std::optional<double> value,
                                                  const std::optional<util::OptionRange>& range,
                                                  std::string_view name);

/// 2단계 검증 전체.
///
/// 검사 순서가 고정돼 있다 — 같은 요청이 두 구현에서 **같은 오류 메시지**를
/// 내야 하기 때문이다. 순서를 바꾸면 먼저 걸리는 조건이 달라진다.
[[nodiscard]] ValidationResult validateExactOptions(const ScanOptions& options,
                                                    const MediaSelection& media);

}  // namespace negaflow::sane
