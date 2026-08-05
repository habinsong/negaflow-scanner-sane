// SPDX-License-Identifier: GPL-2.0-or-later

#include "process/command_line.h"

namespace negaflow::process {

namespace {

[[nodiscard]] bool needsQuoting(std::string_view arg) {
    if (arg.empty()) return true;  // 빈 인자는 "" 로 남겨야 사라지지 않는다
    return arg.find_first_of(" \t\n\v\"") != std::string_view::npos;
}

}  // namespace

std::string quoteArgument(std::string_view arg) {
    if (!needsQuoting(arg)) return std::string(arg);

    std::string out;
    out.reserve(arg.size() + 2);
    out.push_back('"');

    for (size_t i = 0;; ++i) {
        size_t backslashes = 0;
        while (i < arg.size() && arg[i] == '\\') {
            ++i;
            ++backslashes;
        }

        if (i == arg.size()) {
            // 닫는 따옴표 앞의 백슬래시는 2배로 — 그러지 않으면 따옴표를 이스케이프해버린다.
            out.append(backslashes * 2, '\\');
            break;
        }
        if (arg[i] == '"') {
            // `"` 앞의 백슬래시 2배 + 이스케이프된 따옴표
            out.append(backslashes * 2 + 1, '\\');
            out.push_back('"');
        } else {
            out.append(backslashes, '\\');
            out.push_back(arg[i]);
        }
    }

    out.push_back('"');
    return out;
}

std::string buildCommandLine(std::string_view executable,
                             const std::vector<std::string>& args) {
    std::string out = quoteArgument(executable);
    for (const auto& a : args) {
        out.push_back(' ');
        out += quoteArgument(a);
    }
    return out;
}

bool isSafeDeviceName(std::string_view name) {
    if (name.empty() || name.size() > kMaxDeviceNameLength) return false;
    if (name.front() == '-') return false;  // scanimage 가 옵션으로 읽는다

    for (char c : name) {
        const auto byte = static_cast<unsigned char>(c);
        if (byte < 0x20 || byte == 0x7F) return false;  // 제어 문자(개행·널 포함)
        switch (c) {
            case '"':
            case '\'':
            case ' ':
            case '\t':
            case '^':
            case '&':
            case '|':
            case '>':
            case '<':
            case '%':
                return false;
            default:
                break;
        }
    }
    return true;
}

}  // namespace negaflow::process
