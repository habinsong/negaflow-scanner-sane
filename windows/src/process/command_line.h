// negaflow-scanner-sane — Windows adapter
// process/command_line — CreateProcessW 명령줄 조립과 인자 주입 방어.
//
// 정본 문서: windows_docs/03-process-and-io/child-process.md §4
//            windows_docs/99-plan/product-invariants.md I-15
//
// **Windows 에서 새로 생기는 위험이다.** POSIX `exec` 는 인자를 배열로 받지만
// `CreateProcessW` 는 **문자열 하나**를 받고 자식이 파싱한다. 따옴표 규칙을
// 틀리면 `acquisitionDevice` 로 인자를 주입할 수 있다.
//
// 이 파일은 순수하다 — Win32 를 포함하지 않는다. 조립 결과를 테스트할 수 있다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <string>
#include <string_view>
#include <vector>

namespace negaflow::process {

/// 인자 하나를 MSVCRT 파서 규칙에 맞게 따옴표 처리한다.
///
/// 규칙(Microsoft C 런타임):
///   - 공백/탭/따옴표가 없으면 그대로
///   - 있으면 전체를 `"` 로 감싸고
///   - `"` 앞의 백슬래시를 2배로, `"` 자체를 `\"` 로
///   - 닫는 따옴표 앞의 백슬래시도 2배로
///
/// 빈 인자는 `""` 가 된다 — 그대로 두면 사라진다.
[[nodiscard]] std::string quoteArgument(std::string_view arg);

/// 실행 파일 + 인자 → `CreateProcessW` 에 넘길 명령줄.
///
/// **argv[0] 도 따옴표 처리한다.** 설치 경로에 공백이 들어간다
/// (`C:\Users\...\Application Support` 류).
[[nodiscard]] std::string buildCommandLine(std::string_view executable,
                                           const std::vector<std::string>& args);

/// 장치명이 명령줄에 실려도 안전한가.
///
/// SANE 장치명은 실제로는 `backend:transport:addr` 형태의 ASCII 다.
/// 그 밖의 것이 오면 **이스케이프하지 않고 거부한다** — 정상 장치명에는
/// 이런 문자가 없으므로 통과시킬 이유가 없다.
///
/// 거부 대상:
///   - 비어 있음 / 너무 김
///   - 제어 문자(개행, 널 포함)
///   - 따옴표, 공백, 탭
///   - 셸 메타문자 `^ & | > < %` — 우리는 셸을 거치지 않지만 방어적으로
///   - `-` 로 시작 (scanimage 가 옵션으로 해석한다)
[[nodiscard]] bool isSafeDeviceName(std::string_view name);

/// 장치명 최대 길이. 실제 SANE 장치명은 훨씬 짧다.
inline constexpr size_t kMaxDeviceNameLength = 512;

}  // namespace negaflow::process
