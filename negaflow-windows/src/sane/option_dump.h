// negaflow-scanner-sane — Windows adapter
// sane/option_dump — `scanimage -A` 텍스트 파서.
//
// 이식 원본: Sources/SANEPluginCore/SaneOptionDump.swift
// 정본 문서: docs/02-frontend-contract/option-dump-parser.md
//
// 백엔드마다 옵션 이름·단위·형식이 다르다(genesys=mm, coolscan3=pel,
// epson2=소스 열거, pieusb=bool clean-image …). **모델명 하드코딩 없이**
// 실제 -A 덤프에서 장치가 노출하는 옵션만으로 능력과 인자를 결정한다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

#include "util/numeric.h"

namespace negaflow::sane {

/// `--resolution` 제약의 세 형태.
struct ResolutionSpec {
    enum class Kind { None, List, Range };
    Kind kind = Kind::None;
    std::vector<int> list;  // Kind::List — 오름차순 정렬
    int min = 0;            // Kind::Range
    int max = 0;
};

/// `scanimage -A` 한 덤프.
///
/// **"값을 읽을 수 있다"와 "그 값을 보낼 수 있다"는 다르다.**
/// scanimage 는 비활성 옵션도 제약 목록을 그대로 출력한다(`--depth 8 [inactive]`).
/// 그래서 활성 검사를 하는 접근자와 하지 않는 접근자가 쌍으로 있다.
class OptionDump {
public:
    OptionDump() = default;
    explicit OptionDump(std::string_view dump);

    [[nodiscard]] bool empty() const noexcept { return values_.empty(); }

    /// 옵션이 덤프에 나타나는가(활성 여부 무관).
    [[nodiscard]] bool hasOption(std::string_view name) const;

    /// 옵션이 있고 `[inactive]` 가 아닌가.
    [[nodiscard]] bool isActive(std::string_view name) const;

    /// 옵션 토큰 뒤의 원문 전체.
    [[nodiscard]] std::optional<std::string> value(std::string_view name) const;

    /// "A|B|C [default]" → {"A","B","C"}. 원문 대소문자 보존. **활성일 때만.**
    [[nodiscard]] std::vector<std::string> enumValues(std::string_view name) const;

    /// 활성 여부와 무관하게 열거 제약만 읽는다.
    ///
    /// 앞선 옵션 적용으로 활성화될 옵션을 같은 scanimage 호출 뒤쪽에 배치할 때만 쓴다
    /// (epson2 재덤프). 이 비대칭은 의도된 것이다.
    /// 근거: docs/10-lessons/driver-option-reference.md §8.3
    [[nodiscard]] std::vector<std::string> constraintEnumValues(std::string_view name) const;

    /// enum 제약 뒤 대괄호에 표시된 현재 선택값. `[inactive]` 같은 상태 표시는 제외된다
    /// (열거값 목록 안에 있는 것만 후보이므로).
    [[nodiscard]] std::optional<std::string> selectedEnumValue(std::string_view name) const;

    /// "8|14 [8]" → {8,14}. 접미사(dpi 등) 제거. **활성일 때만.**
    [[nodiscard]] std::vector<int> intTokens(std::string_view name) const;

    /// 활성 여부와 무관하게 제약 목록만. 값이 하나뿐인 고정 옵션 식별에만 쓴다.
    /// **이 값을 그대로 장치에 전송해서는 안 된다.**
    [[nodiscard]] std::vector<int> constraintIntTokens(std::string_view name) const;

    /// "-100..100 (in steps of 1) [0]" → 범위(+step). **활성일 때만.**
    [[nodiscard]] std::optional<util::OptionRange> numericRange(std::string_view name) const;

    /// 범위 옵션의 단위 접미사. "0..36.33mm [36.33]" → "mm". **활성일 때만.**
    [[nodiscard]] std::optional<std::string> rangeUnit(std::string_view name) const;

    /// `--resolution 7200|3600|600dpi [600]` → List, `50..6400dpi` → Range.
    [[nodiscard]] ResolutionSpec resolutionSpec() const;

    /// 테스트·진단용 접근자.
    [[nodiscard]] const std::set<std::string>& optionNames() const noexcept { return names_; }
    [[nodiscard]] const std::set<std::string>& inactiveOptionNames() const noexcept {
        return inactive_;
    }

private:
    std::map<std::string, std::string, std::less<>> values_;
    std::set<std::string> names_;
    std::set<std::string> inactive_;
};

// --- 파싱 보조 (테스트에서 직접 검증한다) ---------------------------------

/// "A|B|C [default]" → {"A","B","C"}. 첫 '[' 이후를 버리고 '|' 로 나눈다.
[[nodiscard]] std::vector<std::string> parseEnumValues(std::string_view raw);

/// 첫 "min..max" 를 찾는다. 정규식 `(-?\d+(?:\.\d+)?)\.\.(-?\d+(?:\.\d+)?)` 와 같다.
[[nodiscard]] bool firstNumericRange(std::string_view text, double& outMin, double& outMax);

/// 첫 "step of N" / "steps of N" 을 찾는다.
[[nodiscard]] std::optional<double> firstStepValue(std::string_view text);

/// "0..36.33mm" 뒤의 단위. mm 또는 pel 만 인정한다.
[[nodiscard]] std::optional<std::string> firstRangeUnit(std::string_view text);

}  // namespace negaflow::sane
