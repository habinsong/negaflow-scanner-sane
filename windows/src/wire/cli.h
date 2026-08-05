// negaflow-scanner-sane — Windows adapter
// wire/cli — 서브커맨드 디스패치 **판정**. 실행은 하지 않는다.
//
// 이식 원본: Sources/negaflow-scanner-sane/main.swift (최상위 switch)
// 정본 문서: windows_docs/05-protocol/wire-contract.md §6
//            windows_docs/03-process-and-io/environment-and-paths.md §8 (D-05)
//
// ## 무엇이 순수한가
//
// `main.cpp` 에서 실제로 플랫폼을 타는 것은 **장치를 열고 프로세스를 띄우는
// 부분**이다. 어느 서브커맨드인지, 인자가 모자라지 않은지, 무엇을 어느
// 스트림으로 내보내고 어떤 코드로 끝낼지는 전부 문자열 판정이다.
//
// 떼어 놓으면 테스트가 된다. `main.cpp` 는 이 판정을 받아 실행만 한다.
//
// ## 여기에도 파리티가 없다 — `wire/emitter` 와 같은 이유다
//
// Swift 짝이 `main.swift` 의 최상위 `switch` 라 파리티 바이너리에 넣을 수 없다.
// 단위 테스트가 §6 표를 항목별로 고정한다.
//
// ## exit 코드는 **결정이 안 난 항목이다**
//
// macOS 는 알 수 없는 서브커맨드에 usage 를 stderr 로 내고 **exit 0** 으로
// 끝낸다. 실패가 성공으로 보인다.
//
// §6 이 이렇게 적어 두었다.
//
// ```text
// 권장: 알 수 없는 서브커맨드는 exit 2로 바꾼다.
//       단 "help"는 exit 0을 유지한다.
// ```
//
// **권장일 뿐 결정이 아니다.** 그래서 여기서 정하지 않고 정책을 주입받는다 —
// `wire/request` 의 `PathPolicy`, `wire/parse` 의 `ParseLimits` 와 같은 방식이다.
// 기본값은 **macOS 와 같은 쪽**이다. 바꾸는 것은 사용자에게 보이는 동작
// 변경이므로 D 번호를 받아야 한다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace negaflow::wire {

/// 호스트가 부르는 것은 앞의 셋뿐이다. 나머지는 사람이 쓰는 진단용이다.
enum class Subcommand {
    Detect,
    Capabilities,
    Scan,
    /// `repair-sane-config` 와 별칭 `tune-sane`. **Windows 에서는 no-op**(D-05).
    RepairSaneConfig,
    /// **Windows 에서는 no-op**(D-05).
    RestoreSane,
    /// 알 수 없는 것과 인자 없음. usage 를 낸다.
    Help,
};

/// 알 수 없는 서브커맨드의 종료 코드.
enum class UnknownSubcommandPolicy {
    /// macOS 와 같다. **기본값이다** — 바꾸는 것은 D 번호가 필요한 결정이다.
    ExitZero,
    /// wire-contract §6 의 권장. 알 수 없는 것은 2, 명시적 `help` 는 0.
    ExitTwo,
};

/// 어느 스트림으로 낼 것인가. **stdout 은 프로토콜 전용이다**(§7).
enum class Stream { Stdout, Stderr };

/// 한 줄의 진단 출력.
struct Diagnostic {
    Stream stream = Stream::Stderr;
    std::string text;  ///< 개행을 **포함한다**
};

/// argv 를 읽어 무엇을 할지 정한 결과.
struct CliPlan {
    Subcommand command = Subcommand::Help;
    /// `capabilities <deviceId>` 의 deviceId. 그 외에는 빈 문자열이다.
    std::string argument;
    /// 값이 있으면 **실행하지 않고 이 코드로 끝낸다.**
    std::optional<int> exitCode;
    /// 끝내기 전에 낼 것. 순서대로 쓴다.
    std::vector<Diagnostic> diagnostics;
};

/// macOS 가 `fail()` 로 내는 접두. 오류 문구가 갈리면 안 된다(I-5).
inline constexpr std::string_view kDiagnosticPrefix = "[negaflow-scanner-sane] ";

/// usage 텍스트. **stderr 로 나간다.**
///
/// macOS 문구를 그대로 옮기되 `repair-sane-config` / `restore-sane` 설명은
/// Windows 에서 no-op 라는 사실을 반영한다(D-05).
[[nodiscard]] std::string usageText();

/// `argv[0]` 은 프로그램 이름이다. 비어 있어도 된다.
///
/// ```text
/// 인자 없음                  Help,  exit 0,  stderr usage
/// detect                     Detect
/// capabilities <id>          Capabilities, argument=<id>
/// capabilities (인자 없음)    exit 1, stderr "[…] usage: capabilities <deviceId>"
/// scan                       Scan   (옵션 JSON 은 stdin 이다)
/// repair-sane-config         RepairSaneConfig
/// tune-sane                  RepairSaneConfig   ← 별칭
/// restore-sane               RestoreSane
/// 그 외                      Help,  정책에 따라 exit 0 또는 2
/// ```
///
/// **`capabilities` 인자 부족만 exit 1 이다.** macOS `fail()` 이 1 을 쓴다.
[[nodiscard]] CliPlan planCli(const std::vector<std::string>& argv,
                              UnknownSubcommandPolicy policy = UnknownSubcommandPolicy::ExitZero);

}  // namespace negaflow::wire
