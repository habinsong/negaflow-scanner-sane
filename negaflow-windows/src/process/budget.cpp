// SPDX-License-Identifier: GPL-2.0-or-later

#include "process/budget.h"

#include <algorithm>

namespace negaflow::process {

namespace {

using ms = std::chrono::milliseconds;

}  // namespace

std::string_view commandName(Command c) noexcept {
    switch (c) {
        case Command::Detect: return "detect";
        case Command::Capabilities: return "capabilities";
        case Command::Scan: return "scan";
        case Command::Other: return "other";
    }
    return "other";
}

Duration hostCeiling(Command c) noexcept {
    // 본체 negaflow-windows/docs `10-scanner/plugin-architecture.md` §11.
    switch (c) {
        case Command::Detect: return ms{90'000};
        case Command::Capabilities: return ms{180'000};
        case Command::Scan: return ms{7'200'000};
        case Command::Other: return ms{60'000};
    }
    return ms{60'000};
}

std::optional<Duration> totalBudget(Command c) noexcept {
    switch (c) {
        case Command::Detect: return ms{75'000};        // 90 - 15 여유
        case Command::Capabilities: return ms{150'000};  // 180 - 30 여유
        case Command::Scan: return std::nullopt;         // I-7 — 총 상한 없음
        case Command::Other: return ms{50'000};          // 60 - 10 여유
    }
    return ms{50'000};
}

std::optional<Duration> CommandBudget::remaining(TimePoint now) const noexcept {
    const auto total = totalBudget(command_);
    if (!total.has_value()) return std::nullopt;
    const auto elapsed = std::chrono::duration_cast<Duration>(now - start_);
    const auto left = *total - elapsed;
    return left > Duration::zero() ? left : Duration::zero();
}

bool CommandBudget::exhausted(TimePoint now) const noexcept {
    const auto left = remaining(now);
    if (!left.has_value()) return false;  // 총 예산이 없으면 소진되지 않는다
    return *left < kMinimumUsefulCall;
}

std::optional<Duration> CommandBudget::nextCallTimeout(TimePoint now) const noexcept {
    const auto left = remaining(now);
    if (!left.has_value()) {
        // Scan: 총 예산이 없다. 호출당 상한만 건다.
        return kPerCallCeiling;
    }
    if (*left < kMinimumUsefulCall) return std::nullopt;
    return std::min(*left, kPerCallCeiling);
}

}  // namespace negaflow::process
