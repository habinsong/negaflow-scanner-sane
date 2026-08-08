// negaflow-scanner-sane — Windows adapter
// process/watchdog — 진행률 누적과 획득 워치독.
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend+Process.swift
//            (appendScanimageStderr, AcquisitionProgressWatchdog)
// 정본 문서: docs/03-process-and-io/timeouts-and-watchdog.md
//            docs/03-process-and-io/child-process.md §10
//
// **Win32 를 포함하지 않는다.** 타이머는 `std::condition_variable` 의 시한
// 대기로 세우고, 죽이는 행위는 콜백으로 밀어낸다. 그래서 이 파일은 실기 없이
// 테스트할 수 있다 — `process/progress` 를 순수하게 유지한 것과 같은 이유다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <condition_variable>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <thread>

#include "process/acquisition.h"
#include "process/budget.h"

namespace negaflow::process {

/// stderr chunk 를 받아 진행률을 센다. **순수하다.**
///
/// macOS `appendScanimageStderr` 의 산술을 그대로 옮긴다:
///
/// ```text
/// previousCount = 레코드 수(buffer)
/// combined      = buffer + chunk
/// madeProgress  = 레코드 수(combined) > previousCount
/// fraction      = combined 의 마지막 퍼센트
/// buffer        = combined 의 마지막 160바이트
/// ```
///
/// **160 을 늘리지 않는다.** 늘리면 오래된 레코드가 다시 매치돼 진행이
/// 없는데도 있는 것으로 보인다(child-process §10.2).
class ProgressTracker {
public:
    struct Update {
        bool madeProgress = false;
        std::optional<double> fraction;
    };

    [[nodiscard]] Update append(std::string_view chunk);

    /// 지금까지 모인 stderr 전체.
    [[nodiscard]] const std::string& stderrText() const noexcept { return stderrAll_; }

    /// stderr 를 꺼내고 비운다. 앞뒤 공백을 잘라낸다(Swift `takeStderr`).
    [[nodiscard]] std::string takeStderr();

private:
    std::string buffer_;    ///< 마지막 kProgressBufferTail 바이트
    std::string stderrAll_;
};

/// 첫 진행률까지의 상한과 마지막 진행률 이후 유휴 상한을 감시한다.
///
/// **총 스캔 시간은 제한하지 않는다**(I-7). 진행률이 계속 오는 한 몇 시간짜리
/// 스캔도 허용하고, 호스트의 7,200 s 가 최종 안전망이다.
///
/// 만료하면 `onTimeout` 을 **한 번만** 부른다. 그 콜백이 자식을 죽인다 —
/// 여기서 죽이지 않는 이유는 이 클래스를 Win32 없이 테스트하기 위해서다.
class AcquisitionWatchdog {
public:
    AcquisitionWatchdog() = default;
    ~AcquisitionWatchdog();

    AcquisitionWatchdog(const AcquisitionWatchdog&) = delete;
    AcquisitionWatchdog& operator=(const AcquisitionWatchdog&) = delete;
    AcquisitionWatchdog(AcquisitionWatchdog&&) = delete;
    AcquisitionWatchdog& operator=(AcquisitionWatchdog&&) = delete;

    /// 감시를 시작한다. `finish()` 뒤에 부르면 아무 일도 하지 않는다.
    void start(Duration firstTimeout, Duration stallTimeout, std::function<void()> onTimeout);

    /// 진행률 레코드가 새로 나타났다. 마감을 `stallTimeout` 뒤로 민다.
    void markProgress();

    struct Result {
        TimeoutKind kind = TimeoutKind::None;
        bool observedProgress = false;
    };

    /// 감시를 끝내고 결과를 회수한다. **여러 번 불러도 같은 값이다.**
    Result finish();

private:
    void run();

    mutable std::mutex mutex_;
    std::condition_variable cv_;
    std::thread thread_;
    std::function<void()> onTimeout_;
    Duration stallTimeout_{0};
    TimePoint deadline_{};
    bool started_ = false;
    bool finished_ = false;
    bool observedProgress_ = false;
    TimeoutKind timedOut_ = TimeoutKind::None;
};

}  // namespace negaflow::process
