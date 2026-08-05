// negaflow-scanner-sane — Windows adapter
// process/budget — 명령별 wall-time 예산. **D-32.**
//
// 정본 문서: windows_docs/05-protocol/host-requirements.md §2
//            windows_docs/03-process-and-io/timeouts-and-watchdog.md
//
// 이식 원본이 **없다.** macOS 구현에는 이 개념이 없고, 그것이 문제다.
//
// 호스트는 명령마다 wall-time 상한을 건다(plugin-architecture.md §11):
//     detect 90 s / capabilities 180 s / scan 7,200 s / 그 외 60 s
//
// 그런데 macOS 플러그인은 `scanimage` **호출 하나당** 180 s 를 쓰고,
// 한 명령이 여러 번 호출한다:
//     detect        -f 실패 → -L 폴백           최악 360 s  vs 90 s
//     capabilities  시도 3회 × (목록 + 덤프 + 재덤프)  최악 10회+ vs 180 s
//
// 호스트가 먼저 죽이면 **우리 오류 이벤트가 나가지 못하고** `plugin crashed`
// 로 분류된다. 정리 코드도 돌지 않는다. 진단 품질이 통째로 무너진다.
//
// 그래서 방향을 뒤집는다: 명령 총 예산을 먼저 정하고 호출 타임아웃을 역산한다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <chrono>
#include <optional>
#include <string_view>

namespace negaflow::process {

using Duration = std::chrono::milliseconds;
using TimePoint = std::chrono::steady_clock::time_point;

enum class Command { Detect, Capabilities, Scan, Other };

[[nodiscard]] std::string_view commandName(Command c) noexcept;

/// 호스트가 정한 상한. 우리가 지켜야 하는 바깥 경계다.
[[nodiscard]] Duration hostCeiling(Command c) noexcept;

/// 우리 총 예산. 호스트 상한에서 여유를 뺀 값.
///
/// 여유가 필요한 이유: 프로세스 시작·JSON 인코딩·파일 정리·오류 이벤트 전송이
/// 마지막 `scanimage` 호출 **뒤에** 일어난다. 그 시간을 남겨두지 않으면
/// 오류를 보고하는 도중에 죽는다.
///
/// `Scan` 은 총 예산이 없다(nullopt) — I-7. 진행률이 계속 오는 한 몇 시간짜리
/// 스캔도 허용하고, 호스트의 7,200 s 가 최종 안전망이다.
[[nodiscard]] std::optional<Duration> totalBudget(Command c) noexcept;

/// 개별 `scanimage` 호출에 걸 수 있는 상한(예산과 무관한 절대 상한).
/// macOS 의 `utilityProcessTimeout` 에 해당하며, 이제는 **상한으로만** 쓴다.
inline constexpr Duration kPerCallCeiling = std::chrono::milliseconds{180'000};

/// 명령 하나의 남은 예산을 추적한다.
///
/// **시간을 주입받는다.** 내부에서 시계를 읽지 않으므로 테스트가 결정적이다.
class CommandBudget {
public:
    CommandBudget(Command command, TimePoint start) noexcept
        : command_(command), start_(start) {}

    [[nodiscard]] Command command() const noexcept { return command_; }

    /// 남은 시간. 총 예산이 없는 명령(Scan)은 nullopt.
    [[nodiscard]] std::optional<Duration> remaining(TimePoint now) const noexcept;

    /// 예산을 다 썼는가. 총 예산이 없으면 항상 false.
    [[nodiscard]] bool exhausted(TimePoint now) const noexcept;

    /// 다음 `scanimage` 호출에 걸 타임아웃.
    ///
    /// nullopt 이면 **호출하지 말아야 한다** — 시작해도 호스트가 먼저 죽인다.
    /// 그 경우 지금 timeout 오류를 내는 편이 진단에 낫다.
    ///
    /// 총 예산이 없는 명령은 `kPerCallCeiling` 을 그대로 준다.
    [[nodiscard]] std::optional<Duration> nextCallTimeout(TimePoint now) const noexcept;

private:
    Command command_;
    TimePoint start_;
};

/// 호출 하나를 시작하기에 의미 있는 최소 시간.
///
/// 이보다 적게 남았으면 시작하지 않는다. `scanimage` 프로세스 생성만으로도
/// 수십 ms 가 들고, 그보다 짧은 타임아웃은 "실패를 위한 실행"이다.
inline constexpr Duration kMinimumUsefulCall = std::chrono::milliseconds{500};

}  // namespace negaflow::process
