// SPDX-License-Identifier: GPL-2.0-or-later

#include "process/acquisition.h"

#include "process/progress.h"

namespace negaflow::process {

int attemptCount(std::string_view backend) noexcept {
    // pieusb: full scan 이 슬라이드 이동을 수반할 수 있다. 재시도하면 다른
    // 프레임을 덮어쓴다. **성능이 아니라 물리적 부작용 문제다.**
    return backend == "pieusb" ? 1 : 2;
}

RetryDecision decideRetry(std::string_view backend,
                          int attempt,
                          int total,
                          const AcquisitionOutcome& outcome) {
    // 1. 취소는 재시도하지 않는다.
    if (outcome.cancelled) return RetryDecision::Fail;

    // 2. 종료 코드가 0이어도 요청이 스냅됐으면 **결과를 버린다**(I-1).
    //    이 한 줄이 "요청한 해상도로 스캔했다"와 "비슷한 해상도로 스캔했다"를 가른다.
    if (outcome.exitCode == 0) {
        if (containsInexactOptionWarning(outcome.stderrText)) return RetryDecision::Fail;
        return RetryDecision::Succeed;
    }

    const bool firstAttempt = (attempt == 0);
    const bool hasRetryLeft = firstAttempt && total > 1;

    // 3. genesys: 첫 진행률이 오지 않은 채 타임아웃이면 한 번 다시 연다.
    //    주소가 낡았을 가능성이 높다(open 마다 libusb 주소가 바뀐다).
    //
    //    **구조적 판정이다.** macOS 는 오류 메시지에 "첫 이미지 데이터"가 들어
    //    있는지를 본다. 그 문구를 바꾸면 재시도가 조용히 사라진다.
    if (hasRetryLeft && backend == "genesys" &&
        outcome.timeoutKind == TimeoutKind::FirstProgress) {
        return RetryDecision::Retry;
    }

    // 4. 진행이 전혀 없었고 stale 장치 오류로 보이면 주소를 다시 얻어 재시도.
    if (hasRetryLeft && !outcome.madeProgress && isStaleDeviceError(outcome.stderrText)) {
        return RetryDecision::Retry;
    }

    return RetryDecision::Fail;
}

std::string acquisitionFailureDetail(int exitCode, std::string_view stderrText) {
    const std::string base = "scanimage exit " + std::to_string(exitCode);
    if (stderrText.empty()) return base;
    return base + ": " + std::string(stderrText);
}

std::string retriesExhaustedDetail(std::string_view lastStderr) {
    if (lastStderr.empty()) return "scanimage 재시도 실패";
    return "scanimage 재시도 실패: " + std::string(lastStderr);
}

}  // namespace negaflow::process
