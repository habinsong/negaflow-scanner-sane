// negaflow-scanner-sane — Windows adapter
// process/progress — `scanimage -p` 진행률 파싱과 stderr 분류.
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend+Process.swift
//            Sources/SANEPluginCore/SANEBackend+ScanExecution.swift
// 정본 문서: docs/03-process-and-io/timeouts-and-watchdog.md §5
//
// **이 파일은 순수하다.** process/ 계층의 나머지는 Win32 에 묶여 있지만
// 이 판정 로직은 그렇지 않다. watchdog 전체가 이 위에 서 있으므로
// 골든으로 검증할 수 있게 분리해 둔다.
// 근거: docs/06-build/porting-map.md §2.3
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <optional>
#include <string>
#include <string_view>

namespace negaflow::process {

/// stderr 에 나타난 진행률 **레코드 개수**.
///
/// watchdog 이 보는 "진행"은 값이 증가한 것이 아니라 **레코드가 새로 나타난 것**이다.
/// 퍼센트 형태와 괄호 형태를 모두 센다 — 백엔드에 따라 `Progress: (34/512)` 가 나온다.
///
/// 원본 정규식: `(?i)progress\s*:?\s*(?:\([^)]*\)|[0-9]{1,3}(?:[.,][0-9]+)?\s*%)`
/// 수동 파서로 대체했다(language-decision §8.1) — 백트래킹이 없고 구현 차이가 없다.
[[nodiscard]] int progressRecordCount(std::string_view text);

/// **마지막** 진행률 값을 0…1 로. 없으면 nullopt.
///
/// 콤마 소수점을 받아들이지만 환경은 `LC_ALL=C` 로 고정하는 것이 정본이다.
/// 원본 정규식: `(?i)progress\s*:?\s*([0-9]{1,3}(?:[.,][0-9]+)?)\s*%`
[[nodiscard]] std::optional<double> progressFraction(std::string_view text);

/// 진행률 버퍼에서 유지할 꼬리 길이. 잘린 레코드 재조립용.
inline constexpr size_t kProgressBufferTail = 160;

/// 장치 주소가 낡아서 생긴 오류인가(재열거 후 재시도할 가치가 있는가).
[[nodiscard]] bool isStaleDeviceError(std::string_view stderrText);

/// **요청값이 조용히 스냅됐다는 경고.**
///
/// 이 한 줄이 "요청한 해상도로 스캔했다"와 "비슷한 해상도로 스캔했다"를 가른다.
/// 발견되면 결과를 버린다(I-1).
///
/// `LC_ALL=C` 가 메시지를 영어로 고정한다는 전제 위에 있다. 그 전제가 깨지면
/// 이 감지가 통째로 무력화된다 → spike S-6.
[[nodiscard]] bool containsInexactOptionWarning(std::string_view stderrText);

/// stderr 메시지 → 오류 코드 분류.
///
/// 판정 순서가 고정돼 있다. busy → notConnected → ioFailure.
enum class StderrClass { Busy, NotConnected, IoFailure };

[[nodiscard]] StderrClass classifyStderr(std::string_view message);

}  // namespace negaflow::process
