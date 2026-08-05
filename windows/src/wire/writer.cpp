// negaflow-scanner-sane — Windows adapter
// wire/writer 구현. 계약과 근거는 writer.h 에 있다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#include "wire/writer.h"

namespace negaflow::wire {

WriteOutcome writeAll(std::string_view bytes, ByteSink& sink, int maxStalledAttempts) {
    if (bytes.empty()) return WriteOutcome::Ok;
    if (maxStalledAttempts < 1) return WriteOutcome::Failed;

    std::size_t offset = 0;
    int stalled = 0;

    while (offset < bytes.size()) {
        const WriteAttempt attempt = sink.writeSome(bytes.data() + offset, bytes.size() - offset);

        switch (attempt.status) {
            case WriteAttempt::Status::BrokenPipe:
                // 호스트가 먼저 끝냈다. 재시도하지 않는다 — 다시 써도 같다.
                return WriteOutcome::HostGone;

            case WriteAttempt::Status::Fatal:
                return WriteOutcome::Failed;

            case WriteAttempt::Status::Ok:
            case WriteAttempt::Status::Retryable:
                break;
        }

        // **남은 것보다 많이 썼다고 하면 믿지 않는다.** 그대로 더하면
        // offset 이 끝을 넘어가고, 다음 반복에서 길이 계산이 음수로 감긴다.
        const std::size_t remaining = bytes.size() - offset;
        const std::size_t advanced = attempt.written > remaining ? remaining : attempt.written;

        if (advanced == 0) {
            if (++stalled >= maxStalledAttempts) return WriteOutcome::Failed;
            continue;
        }

        offset += advanced;
        stalled = 0;  // 진행이 있었으면 예산을 되돌린다.
    }

    return WriteOutcome::Ok;
}

}  // namespace negaflow::wire
