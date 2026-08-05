// SPDX-License-Identifier: GPL-2.0-or-later

#include "sane/option_dump.h"

#include <algorithm>
#include <cctype>
#include <charconv>
#include <cstdlib>

namespace negaflow::sane {

namespace {

constexpr std::string_view kSpace = " \t\v\f\r\n";

[[nodiscard]] std::string_view trim(std::string_view s) {
    const auto b = s.find_first_not_of(kSpace);
    if (b == std::string_view::npos) return {};
    const auto e = s.find_last_not_of(kSpace);
    return s.substr(b, e - b + 1);
}

[[nodiscard]] char lower(char c) {
    return static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
}

[[nodiscard]] std::string toLower(std::string_view s) {
    std::string out;
    out.reserve(s.size());
    for (char c : s) out.push_back(lower(c));
    return out;
}

[[nodiscard]] bool isDigit(char c) { return c >= '0' && c <= '9'; }

/// 대소문자 무시 부분 문자열 검색.
/// LC_ALL=C 전제이므로 ASCII 만 다룬다(diacritic 은 나오지 않는다).
[[nodiscard]] bool containsCaseInsensitive(std::string_view haystack, std::string_view needle) {
    if (needle.empty()) return true;
    if (needle.size() > haystack.size()) return false;
    const std::string h = toLower(haystack);
    const std::string n = toLower(needle);
    return h.find(n) != std::string::npos;
}

/// 첫 '[' 이전만 남긴다.
[[nodiscard]] std::string_view beforeFirstBracket(std::string_view s) {
    const auto pos = s.find('[');
    return pos == std::string_view::npos ? s : s.substr(0, pos);
}

/// text[i] 부터 숫자를 읽는다. 성공하면 i 를 전진시키고 값을 준다.
/// 형식: -?\d+(\.\d+)?
[[nodiscard]] bool scanNumber(std::string_view text, size_t& i, double& out) {
    const size_t start = i;
    size_t j = i;
    if (j < text.size() && text[j] == '-') ++j;
    const size_t digitsStart = j;
    while (j < text.size() && isDigit(text[j])) ++j;
    if (j == digitsStart) {
        i = start;
        return false;
    }
    if (j + 1 < text.size() && text[j] == '.' && isDigit(text[j + 1])) {
        ++j;
        while (j < text.size() && isDigit(text[j])) ++j;
    }
    const std::string token(text.substr(start, j - start));
    // strtod 는 로케일 의존이다. 여기서는 ASCII 숫자만 다루고 C 로케일을 전제한다.
    // from_chars(double) 는 로케일 독립이라 그것을 우선 쓴다.
    double parsed = 0.0;
    const char* first = token.data();
    const char* last = token.data() + token.size();
    auto [ptr, ec] = std::from_chars(first, last, parsed);
    if (ec != std::errc{} || ptr != last) {
        i = start;
        return false;
    }
    out = parsed;
    i = j;
    return true;
}

}  // namespace

// --- 보조 파서 ------------------------------------------------------------

std::vector<std::string> parseEnumValues(std::string_view raw) {
    std::vector<std::string> out;
    std::string_view body = beforeFirstBracket(raw);
    size_t pos = 0;
    while (pos <= body.size()) {
        const auto bar = body.find('|', pos);
        const std::string_view piece =
            body.substr(pos, bar == std::string_view::npos ? std::string_view::npos : bar - pos);
        const std::string_view t = trim(piece);
        if (!t.empty()) out.emplace_back(t);
        if (bar == std::string_view::npos) break;
        pos = bar + 1;
    }
    return out;
}

bool firstNumericRange(std::string_view text, double& outMin, double& outMax) {
    for (size_t i = 0; i < text.size(); ++i) {
        size_t j = i;
        double lo = 0.0;
        if (!scanNumber(text, j, lo)) continue;
        if (j + 1 >= text.size() || text[j] != '.' || text[j + 1] != '.') continue;
        j += 2;
        double hi = 0.0;
        if (!scanNumber(text, j, hi)) continue;
        outMin = lo;
        outMax = hi;
        return true;
    }
    return false;
}

std::optional<double> firstStepValue(std::string_view text) {
    // "step of N" 또는 "steps of N" (대소문자 무시)
    const std::string low = toLower(text);
    for (size_t pos = 0;; ) {
        const auto at = low.find("step", pos);
        if (at == std::string::npos) return std::nullopt;
        size_t j = at + 4;
        if (j < low.size() && low[j] == 's') ++j;
        if (low.compare(j, 4, " of ") != 0) {
            pos = at + 1;
            continue;
        }
        j += 4;
        double v = 0.0;
        if (scanNumber(text, j, v)) return v;
        pos = at + 1;
    }
}

std::optional<std::string> firstRangeUnit(std::string_view text) {
    for (size_t i = 0; i < text.size(); ++i) {
        size_t j = i;
        double lo = 0.0;
        if (!scanNumber(text, j, lo)) continue;
        if (j + 1 >= text.size() || text[j] != '.' || text[j + 1] != '.') continue;
        j += 2;
        double hi = 0.0;
        if (!scanNumber(text, j, hi)) continue;
        while (j < text.size() && (text[j] == ' ' || text[j] == '\t')) ++j;
        const std::string_view rest = text.substr(j);
        if (rest.rfind("mm", 0) == 0) return std::string("mm");
        if (rest.rfind("pel", 0) == 0) return std::string("pel");
        return std::nullopt;
    }
    return std::nullopt;
}

// --- OptionDump -----------------------------------------------------------

OptionDump::OptionDump(std::string_view dump) {
    size_t pos = 0;
    while (pos <= dump.size()) {
        const auto nl = dump.find('\n', pos);
        const std::string_view rawLine =
            dump.substr(pos, nl == std::string_view::npos ? std::string_view::npos : nl - pos);
        pos = (nl == std::string_view::npos) ? dump.size() + 1 : nl + 1;

        // 1. 양끝 공백 제거. trim 에 '\r' 이 포함되므로 CRLF 덤프가 그대로 처리된다.
        //    (Swift 의 .whitespaces 는 '\r' 을 포함하지 않아 별도 처리가 필요했다.)
        const std::string_view line = trim(rawLine);

        // 2. '-' 로 시작하지 않으면 버린다 → 섹션 제목·설명문·헤더가 걸러진다.
        if (line.empty() || line.front() != '-') continue;

        // 3. 첫 공백 전까지가 토큰.
        const auto tokEnd = line.find_first_of(kSpace);
        const std::string_view token =
            tokEnd == std::string_view::npos ? line : line.substr(0, tokEnd);

        // 4. 앞의 '-' 를 전부 제거.
        std::string_view name = token;
        while (!name.empty() && name.front() == '-') name.remove_prefix(1);

        // 5. '[' 가 있으면 그 앞까지 → "--preview[=(yes|no)]" → "preview"
        name = beforeFirstBracket(name);

        // 6. 이름이 비면 버린다.
        if (name.empty()) continue;

        // 7. 나머지를 값으로. **먼저 나온 항목이 이긴다.**
        const std::string_view rest =
            tokEnd == std::string_view::npos ? std::string_view{} : trim(line.substr(tokEnd));

        const std::string key(name);
        if (values_.find(key) == values_.end()) {
            values_.emplace(key, std::string(rest));
            names_.insert(key);
        }

        // 8. 값에 "[inactive]" 가 있으면 비활성.
        if (containsCaseInsensitive(rest, "[inactive]")) inactive_.insert(key);
    }
}

bool OptionDump::hasOption(std::string_view name) const {
    return names_.find(std::string(name)) != names_.end();
}

bool OptionDump::isActive(std::string_view name) const {
    const std::string key(name);
    return names_.find(key) != names_.end() && inactive_.find(key) == inactive_.end();
}

std::optional<std::string> OptionDump::value(std::string_view name) const {
    const auto it = values_.find(name);
    if (it == values_.end()) return std::nullopt;
    return it->second;
}

std::vector<std::string> OptionDump::enumValues(std::string_view name) const {
    if (!isActive(name)) return {};
    const auto v = value(name);
    if (!v) return {};
    return parseEnumValues(*v);
}

std::vector<std::string> OptionDump::constraintEnumValues(std::string_view name) const {
    const auto v = value(name);
    if (!v) return {};
    return parseEnumValues(*v);
}

std::optional<std::string> OptionDump::selectedEnumValue(std::string_view name) const {
    const auto raw = value(name);
    if (!raw) return std::nullopt;
    for (const auto& candidate : enumValues(name)) {
        const std::string needle = "[" + candidate + "]";
        if (containsCaseInsensitive(*raw, needle)) return candidate;
    }
    return std::nullopt;
}

std::vector<int> OptionDump::intTokens(std::string_view name) const {
    if (!isActive(name)) return {};
    return constraintIntTokens(name);
}

std::vector<int> OptionDump::constraintIntTokens(std::string_view name) const {
    const auto raw = value(name);
    if (!raw) return {};
    std::vector<int> out;
    const std::string_view body = beforeFirstBracket(*raw);

    size_t pos = 0;
    while (pos <= body.size()) {
        const auto sep = body.find_first_of("| ", pos);
        const std::string_view piece =
            body.substr(pos, sep == std::string_view::npos ? std::string_view::npos : sep - pos);

        // Swift: Int(tok.trimmingCharacters(in: CharacterSet.decimalDigits.inverted))
        //        → 양끝에서 숫자가 아닌 문자를 전부 벗긴 뒤 정수 파싱.
        //        "600dpi" → "600". 부호도 함께 벗겨지므로 결과는 음수가 되지 않는다.
        size_t b = 0;
        size_t e = piece.size();
        while (b < e && !isDigit(piece[b])) ++b;
        while (e > b && !isDigit(piece[e - 1])) --e;
        const std::string_view core = piece.substr(b, e - b);
        if (!core.empty() && std::all_of(core.begin(), core.end(), isDigit)) {
            int parsed = 0;
            const char* first = core.data();
            const char* last = core.data() + core.size();
            auto [ptr, ec] = std::from_chars(first, last, parsed);
            if (ec == std::errc{} && ptr == last) out.push_back(parsed);
        }

        if (sep == std::string_view::npos) break;
        pos = sep + 1;
    }
    return out;
}

std::optional<util::OptionRange> OptionDump::numericRange(std::string_view name) const {
    if (!isActive(name)) return std::nullopt;
    const auto raw = value(name);
    if (!raw) return std::nullopt;
    double lo = 0.0;
    double hi = 0.0;
    if (!firstNumericRange(*raw, lo, hi)) return std::nullopt;
    util::OptionRange range;
    range.minimum = lo;
    range.maximum = hi;
    range.step = firstStepValue(*raw);
    return range;
}

std::optional<std::string> OptionDump::rangeUnit(std::string_view name) const {
    if (!isActive(name)) return std::nullopt;
    const auto raw = value(name);
    if (!raw) return std::nullopt;
    return firstRangeUnit(*raw);
}

ResolutionSpec OptionDump::resolutionSpec() const {
    ResolutionSpec spec;
    if (!isActive("resolution")) return spec;
    const auto raw = value("resolution");
    if (!raw) return spec;

    if (raw->find("..") != std::string::npos) {
        double lo = 0.0;
        double hi = 0.0;
        if (!firstNumericRange(*raw, lo, hi)) return spec;
        spec.kind = ResolutionSpec::Kind::Range;
        spec.min = static_cast<int>(lo);  // Swift: Int(bounds.0) — 절단
        spec.max = static_cast<int>(hi);
        return spec;
    }

    // 목록형. Swift: Int(tok.replacingOccurrences(of: "dpi", with: ""))
    // constraintIntTokens 와 규칙이 다르다 — 여기서는 "dpi" 만 제거하고
    // 나머지는 그대로 정수 파싱한다(부호 허용).
    const std::string_view body = beforeFirstBracket(*raw);
    std::vector<int> dpis;
    size_t pos = 0;
    while (pos <= body.size()) {
        const auto sep = body.find_first_of("| ", pos);
        const std::string_view piece =
            body.substr(pos, sep == std::string_view::npos ? std::string_view::npos : sep - pos);

        std::string tok(piece);
        for (;;) {
            const auto at = tok.find("dpi");
            if (at == std::string::npos) break;
            tok.erase(at, 3);
        }
        if (!tok.empty()) {
            int parsed = 0;
            const char* first = tok.data();
            const char* last = tok.data() + tok.size();
            auto [ptr, ec] = std::from_chars(first, last, parsed);
            if (ec == std::errc{} && ptr == last) dpis.push_back(parsed);
        }

        if (sep == std::string_view::npos) break;
        pos = sep + 1;
    }

    if (dpis.empty()) return spec;
    std::sort(dpis.begin(), dpis.end());
    spec.kind = ResolutionSpec::Kind::List;
    spec.list = std::move(dpis);
    return spec;
}

}  // namespace negaflow::sane
