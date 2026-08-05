// negaflow-scanner-sane — Windows adapter
// wire/cli 구현. 계약과 근거는 cli.h 에 있다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#include "wire/cli.h"

namespace negaflow::wire {

std::string usageText() {
    // macOS 문구를 그대로 옮긴다. 두 줄만 다르다 — 그 둘은 Windows 에서
    // no-op 이므로 macOS 설명("과거 negaflow가 비활성화한 백엔드 복구")을
    // 그대로 쓰면 거짓말이 된다(D-05).
    return "negaflow-scanner-sane — negaflow SANE scanner plugin\n"
           "usage:\n"
           "  negaflow-scanner-sane detect\n"
           "  negaflow-scanner-sane capabilities <deviceId>\n"
           "  negaflow-scanner-sane scan   (scan options JSON on stdin)\n"
           "  negaflow-scanner-sane repair-sane-config (no-op: this platform uses a "
           "private SANE configuration)\n"
           "  negaflow-scanner-sane tune-sane          (repair-sane-config 호환 별칭)\n"
           "  negaflow-scanner-sane restore-sane       (no-op: this platform uses a "
           "private SANE configuration)\n";
}

CliPlan planCli(const std::vector<std::string>& argv, UnknownSubcommandPolicy policy) {
    // macOS: `arguments.count > 1 ? arguments[1] : "help"`
    const std::string subcommand = argv.size() > 1 ? argv[1] : std::string("help");

    CliPlan plan;

    if (subcommand == "detect") {
        plan.command = Subcommand::Detect;
        return plan;
    }
    if (subcommand == "capabilities") {
        plan.command = Subcommand::Capabilities;
        if (argv.size() <= 2) {
            // macOS `fail()` 과 같은 접두·문구·코드다.
            plan.exitCode = 1;
            plan.diagnostics.push_back(
                {Stream::Stderr,
                 std::string(kDiagnosticPrefix) + "usage: capabilities <deviceId>\n"});
            return plan;
        }
        plan.argument = argv[2];
        return plan;
    }
    if (subcommand == "scan") {
        plan.command = Subcommand::Scan;
        return plan;
    }
    if (subcommand == "repair-sane-config" || subcommand == "tune-sane") {
        plan.command = Subcommand::RepairSaneConfig;
        return plan;
    }
    if (subcommand == "restore-sane") {
        plan.command = Subcommand::RestoreSane;
        return plan;
    }

    // 알 수 없는 것과 인자 없음. **usage 는 stderr 다** — stdout 은 프로토콜
    // 전용이라 배너가 섞이면 호스트의 JSON 파싱이 깨진다(§7).
    plan.command = Subcommand::Help;
    plan.diagnostics.push_back({Stream::Stderr, usageText()});
    if (policy == UnknownSubcommandPolicy::ExitTwo && subcommand != "help") {
        plan.exitCode = 2;
    } else {
        plan.exitCode = 0;
    }
    return plan;
}

}  // namespace negaflow::wire
