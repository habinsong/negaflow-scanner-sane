// negaflow-scanner-sane — Windows adapter
// process/acquisition — 획득 재시도 정책. **순수 판정.**
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend+ScanExecution.swift
//            (runSingleAcquisition 의 정책 부분)
// 정본 문서: windows_docs/02-frontend-contract/backend-quirks.md §1.4, §5.2
//            windows_docs/03-process-and-io/timeouts-and-watchdog.md §3.5
//
// `runSingleAcquisition` 은 프로세스를 띄우는 부분과 **"다시 시도할까"를 정하는
// 부분**이 섞여 있다. 후자는 순수하므로 여기로 분리해 골든으로 검증한다.
// 백엔드 분기 2곳(genesys 첫 진행률 재시도, pieusb 재시도 금지)이 여기 있다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <string>
#include <string_view>

namespace negaflow::process {

/// watchdog 이 판정한 타임아웃 종류.
///
/// **macOS 는 이것을 오류 메시지 문자열(`"첫 이미지 데이터"`)로 판정한다.**
/// 그 문구를 영어로 바꾸면 genesys 재시도가 조용히 사라진다.
/// 이식에서는 구조적으로 싣는다 — timeouts-and-watchdog §3.5 가 승인한 개선이다.
enum class TimeoutKind {
    None,
    FirstProgress,  // 첫 진행률까지의 상한 초과
    Stalled,        // 마지막 진행률 이후 유휴 상한 초과
};

/// `scanimage` 한 번의 결과.
struct AcquisitionOutcome {
    int exitCode = 0;
    /// 진행률 레코드가 하나라도 늘었는가. **값이 아니라 개수 기준이다.**
    bool madeProgress = false;
    std::string stderrText;
    TimeoutKind timeoutKind = TimeoutKind::None;
    /// 사용자가 취소했는가. 취소는 재시도하지 않는다.
    bool cancelled = false;
};

enum class RetryDecision {
    Succeed,  // 성공. 결과를 쓴다
    Retry,    // 주소 캐시를 버리고 다시 시도
    Fail,     // 실패. 산출물을 지우고 오류를 낸다
};

/// 이 백엔드에서 허용하는 총 시도 횟수.
///
/// **pieusb 는 1회다.** full scan 자체가 다음 슬라이드 이동을 수반할 수 있어
/// 같은 요청을 자동 재시도하면 다른 프레임을 덮어쓴다.
[[nodiscard]] int attemptCount(std::string_view backend) noexcept;

/// 한 번의 결과를 보고 다음 행동을 정한다.
///
/// `attempt` 는 0-based. `total` 은 `attemptCount()` 결과.
///
/// 판정 순서:
///   1. 취소  → Fail (재시도 안 함)
///   2. exit 0 + 반올림 경고 → Fail (I-1: 결과를 버린다)
///   3. exit 0 → Succeed
///   4. genesys + 첫 진행률 타임아웃 + 첫 시도 → Retry
///   5. 첫 시도 + 진행 없음 + stale 장치 오류 → Retry
///   6. 그 외 → Fail
[[nodiscard]] RetryDecision decideRetry(std::string_view backend,
                                        int attempt,
                                        int total,
                                        const AcquisitionOutcome& outcome);

/// 최종 실패 메시지. Swift 와 같은 문구를 낸다.
///
/// stderr 가 비면 종료 코드만, 아니면 `"scanimage exit N: <stderr>"`.
[[nodiscard]] std::string acquisitionFailureDetail(int exitCode, std::string_view stderrText);

/// 재시도를 다 쓰고 실패했을 때의 메시지.
[[nodiscard]] std::string retriesExhaustedDetail(std::string_view lastStderr);

}  // namespace negaflow::process
