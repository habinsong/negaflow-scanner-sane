// SPDX-License-Identifier: GPL-2.0-or-later

#include "process/progress.h"

#include <algorithm>
#include <cctype>
#include <charconv>
#include <cmath>

namespace negaflow::process {

namespace {

[[nodiscard]] char lowerAscii(char c) {
    return static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
}

[[nodiscard]] std::string toLower(std::string_view s) {
    std::string out;
    out.reserve(s.size());
    for (char c : s) out.push_back(lowerAscii(c));
    return out;
}

[[nodiscard]] bool contains(std::string_view h, std::string_view n) {
    return h.find(n) != std::string_view::npos;
}

[[nodiscard]] bool isDigit(char c) { return c >= '0' && c <= '9'; }

[[nodiscard]] bool isSpace(char c) {
    return c == ' ' || c == '\t' || c == '\v' || c == '\f' || c == '\r' || c == '\n';
}

/// `text` 의 `i` 위치에서 "progress" 를 대소문자 무시로 매치하고 위치를 전진시킨다.
[[nodiscard]] bool matchProgressKeyword(std::string_view text, size_t& i) {
    constexpr std::string_view kWord = "progress";
    if (i + kWord.size() > text.size()) return false;
    for (size_t k = 0; k < kWord.size(); ++k) {
        if (lowerAscii(text[i + k]) != kWord[k]) return false;
    }
    i += kWord.size();
    return true;
}

/// `\s*:?\s*` 를 소비한다.
void skipSeparator(std::string_view text, size_t& i) {
    while (i < text.size() && isSpace(text[i])) ++i;
    if (i < text.size() && text[i] == ':') ++i;
    while (i < text.size() && isSpace(text[i])) ++i;
}

/// `[0-9]{1,3}([.,][0-9]+)?` 를 읽는다. 성공하면 i 를 전진시킨다.
[[nodiscard]] bool scanPercentNumber(std::string_view text, size_t& i, std::string& out) {
    const size_t start = i;
    size_t digits = 0;
    while (i < text.size() && isDigit(text[i]) && digits < 3) {
        ++i;
        ++digits;
    }
    if (digits == 0) {
        i = start;
        return false;
    }
    if (i + 1 < text.size() && (text[i] == '.' || text[i] == ',') && isDigit(text[i + 1])) {
        ++i;
        while (i < text.size() && isDigit(text[i])) ++i;
    }
    out.assign(text.substr(start, i - start));
    return true;
}

/// 한 진행률 레코드를 매치한다. 성공하면 i 가 레코드 끝으로 간다.
/// `percent` 가 non-null 이고 퍼센트 형태면 숫자 문자열을 담는다.
[[nodiscard]] bool matchRecord(std::string_view text, size_t& i, std::string* percent) {
    size_t j = i;
    if (!matchProgressKeyword(text, j)) return false;
    skipSeparator(text, j);

    // 괄호 형태: \([^)]*\)
    if (j < text.size() && text[j] == '(') {
        const auto close = text.find(')', j);
        if (close == std::string_view::npos) return false;
        i = close + 1;
        if (percent) percent->clear();
        return true;
    }

    // 퍼센트 형태
    std::string number;
    if (!scanPercentNumber(text, j, number)) return false;
    while (j < text.size() && isSpace(text[j])) ++j;
    if (j >= text.size() || text[j] != '%') return false;
    ++j;
    i = j;
    if (percent) *percent = number;
    return true;
}

}  // namespace

int progressRecordCount(std::string_view text) {
    int count = 0;
    size_t i = 0;
    while (i < text.size()) {
        size_t at = i;
        if (matchRecord(text, at, nullptr)) {
            ++count;
            i = at;
        } else {
            ++i;
        }
    }
    return count;
}

std::optional<double> progressFraction(std::string_view text) {
    std::optional<std::string> last;
    size_t i = 0;
    while (i < text.size()) {
        size_t at = i;
        std::string number;
        if (matchRecord(text, at, &number)) {
            if (!number.empty()) last = number;  // 괄호 형태는 값을 주지 않는다
            i = at;
        } else {
            ++i;
        }
    }
    if (!last.has_value()) return std::nullopt;

    // 콤마 소수점을 점으로.
    std::string normalized = *last;
    std::replace(normalized.begin(), normalized.end(), ',', '.');

    double percent = 0.0;
    const char* first = normalized.data();
    const char* end = normalized.data() + normalized.size();
    auto [ptr, ec] = std::from_chars(first, end, percent);
    if (ec != std::errc{} || ptr != end || !std::isfinite(percent)) return std::nullopt;

    return std::min(std::max(percent / 100.0, 0.0), 1.0);
}

bool isStaleDeviceError(std::string_view stderrText) {
    const std::string s = toLower(stderrText);
    return contains(s, "invalid argument") || contains(s, "open of device") ||
           contains(s, "failed to open") || contains(s, "device busy") ||
           contains(s, "no such device") || contains(s, "i/o error") ||
           contains(s, "device i/o");
}

bool containsInexactOptionWarning(std::string_view stderrText) {
    // scanimage 는 요청값을 장치 표현으로 옮길 때 `rounded value of <opt> from <a> to <b>`
    // 를 남긴다. SANE 은 값을 고정소수점(1/65536)으로 들고 있어 mm 요청은 대개 정확히
    // 표현되지 않고, 그래서 **표시상 같은 값**에도 이 경고가 붙는다 — GT-X900 의 투과
    // 영역 요청이 `from 149.86 to 149.86` 으로 경고를 내면서 완주한 스캔이 통째로
    // 거절됐다. 요청이 실제로 다른 값으로 바뀐 경우에만 실패로 본다. 형식을 읽지 못하면
    // 보수적으로 경고로 취급한다.
    const std::string lowered = toLower(stderrText);
    std::size_t line = 0;
    while (line <= lowered.size()) {
        const std::size_t end = lowered.find('\n', line);
        const std::string_view text =
            std::string_view(lowered).substr(line, end == std::string::npos ? std::string::npos
                                                                            : end - line);
        line = end == std::string::npos ? lowered.size() + 1 : end + 1;
        if (!contains(text, "rounded value of")) continue;

        const std::size_t from = text.find(" from ");
        if (from == std::string_view::npos) return true;
        const std::size_t to = text.find(" to ", from + 6);
        if (to == std::string_view::npos) return true;

        const auto trim = [](std::string_view v) {
            while (!v.empty() && std::isspace(static_cast<unsigned char>(v.front()))) {
                v.remove_prefix(1);
            }
            while (!v.empty() && std::isspace(static_cast<unsigned char>(v.back()))) {
                v.remove_suffix(1);
            }
            return v;
        };
        if (trim(text.substr(from + 6, to - (from + 6))) != trim(text.substr(to + 4))) {
            return true;
        }
    }
    return false;
}

StderrClass classifyStderr(std::string_view message) {
    const std::string s = toLower(message);
    if (contains(s, "access to resource has been denied") || contains(s, "device busy") ||
        contains(s, "resource busy")) {
        return StderrClass::Busy;
    }
    if (contains(s, "no such device") || contains(s, "invalid argument") ||
        contains(s, "not connected")) {
        return StderrClass::NotConnected;
    }
    return StderrClass::IoFailure;
}

}  // namespace negaflow::process
