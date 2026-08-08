// SPDX-License-Identifier: GPL-2.0-or-later

#include "process/watchdog.h"

#include <algorithm>
#include <chrono>

#include "process/progress.h"

namespace negaflow::process {

namespace {

/// UTF-8 시퀀스 한가운데를 자르지 않는 꼬리 시작점.
///
/// Swift 는 Character 단위로 `suffix(160)` 을 하므로 애초에 못 자른다.
/// 바이트로 자르면 다음 chunk 와 이어 붙일 때 깨진 바이트가 남는다 —
/// 진행률 정규식은 ASCII 라 판정에는 영향이 없지만, 같은 버퍼가 오류
/// 메시지로 흘러가지 않도록 경계를 맞춰 둔다.
[[nodiscard]] std::size_t utf8TailStart(const std::string& text, std::size_t want) {
    if (text.size() <= want) return 0;
    std::size_t start = text.size() - want;
    // 후속 바이트(10xxxxxx)면 앞으로 물러선다. 최대 3바이트면 충분하다.
    for (int i = 0; i < 3 && start < text.size(); ++i) {
        if ((static_cast<unsigned char>(text[start]) & 0xC0u) != 0x80u) break;
        ++start;
    }
    return start;
}

[[nodiscard]] std::string trimmed(std::string_view s) {
    const auto isSpace = [](unsigned char c) {
        return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
    };
    std::size_t begin = 0;
    std::size_t end = s.size();
    while (begin < end && isSpace(static_cast<unsigned char>(s[begin]))) ++begin;
    while (end > begin && isSpace(static_cast<unsigned char>(s[end - 1]))) --end;
    return std::string{s.substr(begin, end - begin)};
}

}  // namespace

ProgressTracker::Update ProgressTracker::append(std::string_view chunk) {
    stderrAll_.append(chunk);

    const int previousCount = progressRecordCount(buffer_);
    std::string combined = buffer_;
    combined.append(chunk);

    Update update;
    update.madeProgress = progressRecordCount(combined) > previousCount;
    update.fraction = progressFraction(combined);

    const std::size_t start = utf8TailStart(combined, kProgressBufferTail);
    buffer_.assign(combined, start, combined.size() - start);
    return update;
}

std::string ProgressTracker::takeStderr() {
    std::string result = trimmed(stderrAll_);
    stderrAll_.clear();
    return result;
}

AcquisitionWatchdog::~AcquisitionWatchdog() {
    (void)finish();
}

void AcquisitionWatchdog::start(Duration firstTimeout,
                                Duration stallTimeout,
                                std::function<void()> onTimeout) {
    std::unique_lock lock(mutex_);
    if (finished_ || started_) return;
    started_ = true;
    stallTimeout_ = stallTimeout;
    deadline_ = std::chrono::steady_clock::now() + firstTimeout;
    onTimeout_ = std::move(onTimeout);
    thread_ = std::thread(&AcquisitionWatchdog::run, this);
}

void AcquisitionWatchdog::markProgress() {
    {
        std::unique_lock lock(mutex_);
        if (finished_ || timedOut_ != TimeoutKind::None) return;
        observedProgress_ = true;
        deadline_ = std::chrono::steady_clock::now() + stallTimeout_;
    }
    cv_.notify_all();
}

AcquisitionWatchdog::Result AcquisitionWatchdog::finish() {
    std::thread joinable;
    Result result;
    {
        std::unique_lock lock(mutex_);
        finished_ = true;
        result.kind = timedOut_;
        result.observedProgress = observedProgress_;
        joinable = std::move(thread_);
    }
    cv_.notify_all();
    if (joinable.joinable()) joinable.join();
    return result;
}

void AcquisitionWatchdog::run() {
    std::function<void()> fire;
    {
        std::unique_lock lock(mutex_);
        for (;;) {
            if (finished_) return;
            const TimePoint deadline = deadline_;
            if (cv_.wait_until(lock, deadline) == std::cv_status::no_timeout) {
                // 깨어난 이유가 진행률이면 deadline_ 이 밀려 있다. 다시 잰다.
                continue;
            }
            if (finished_) return;
            // 자는 사이에 markProgress 가 마감을 밀었을 수 있다.
            if (std::chrono::steady_clock::now() < deadline_) continue;
            timedOut_ = observedProgress_ ? TimeoutKind::Stalled : TimeoutKind::FirstProgress;
            fire = onTimeout_;
            break;
        }
    }
    // **락 밖에서 부른다.** 콜백이 자식을 죽이면서 stderr 스레드를 깨우고,
    // 그 스레드가 markProgress 로 이 락을 다시 잡으려 할 수 있다.
    if (fire) fire();
}

}  // namespace negaflow::process
