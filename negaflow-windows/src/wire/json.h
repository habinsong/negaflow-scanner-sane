// negaflow-scanner-sane — Windows adapter
// wire/json — JSON **방출**. 파싱은 여기 없다.
//
// 정본 문서: docs/05-protocol/encoding-and-json.md §2.3, §3
//            docs/05-protocol/wire-contract.md §4.2.1, §4.2.3
//
// ## 왜 라이브러리를 쓰지 않고 직접 쓰는가
//
// **키 순서를 우리가 통제해야 하기 때문이다.** 그리고 방출은 규칙이 작다 —
// 이스케이프 3종, 수 표기 2종, 그게 전부다. 파싱은 반대다(중첩 깊이, 중복 키,
// 불완전 입력) — 그쪽은 검증된 라이브러리를 쓴다(RapidJSON, M5 후반).
//
// "수동 문자열 조립을 하지 않는다"(§2.3)는 **이스케이프 없이 이어 붙이지
// 말라**는 뜻이다. 값 모델을 거쳐 한 곳에서 이스케이프하는 것은 그 경고의
// 대상이 아니다 — 오히려 그 경고가 요구하는 구조다.
//
// ## 지켜야 하는 것
//
// ```text
// `/` 를 `\/` 로 이스케이프한다       Swift JSONEncoder 의 기본이 그렇다(실측)
// 비ASCII 를 \uXXXX 로 바꾸지 않는다   오류 메시지가 한국어라 바로 드러난다
// 수는 로케일 독립                     std::to_chars. ostream/printf 는 로케일 의존
// 정수에 소수점을 붙이지 않는다        3600 이지 3600.0 이 아니다
// NaN/Inf 를 쓰지 않는다               Swift 는 인코딩을 실패시킨다
// ```
//
// ## 키 순서
//
// Swift `JSONEncoder` 의 키 순서는 **해시 기반이라 안정적이지 않다**(§4.2.3).
// 그래서 wire 골든을 바이트로 비교할 수 없다.
//
// 파리티는 **양쪽 다 정렬 출력**으로 돌려 바이트를 비교한다 — §4.2.3 이
// "굳이 하려면 그렇게 하라"고 적어 둔 방법이다. 그러면 이스케이프·수 표기·
// 생략 vs null 까지 전부 한 번에 검증된다.
//
// **실제 wire 출력은 정렬하지 않는다.** 정렬하면 호스트에 나가는 바이트가
// 바뀌고 그것은 wire 변경이다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace negaflow::wire {

/// 키 순서 정책.
enum class KeyOrder {
    /// 삽입 순서 그대로. **제품 동작이다.**
    Declaration,
    /// 키를 정렬한다. 파리티와 골든 비교 전용.
    Sorted,
};

/// JSON 값. 객체는 **삽입 순서를 유지한다**(std::map 이 아니다).
class JsonValue {
public:
    enum class Kind { Null, Bool, Int, Double, String, Array, Object };

    JsonValue() = default;  ///< null

    static JsonValue null() { return JsonValue{}; }
    static JsonValue boolean(bool v);
    static JsonValue integer(std::int64_t v);
    static JsonValue number(double v);
    static JsonValue string(std::string v);
    static JsonValue array();
    static JsonValue object();

    /// 배열에 덧붙인다. 배열이 아니면 아무 일도 하지 않는다.
    void push(JsonValue v);

    /// 객체에 키를 넣는다. **같은 키를 두 번 넣지 않는다** — 호출자 책임이다.
    void set(std::string key, JsonValue v);

    /// 값이 없으면 **키를 아예 넣지 않는다.** 합성 Codable 의 동작이다.
    ///
    /// `PluginDevice` / `PluginCapabilities` / `PluginScanEventV2` 가 이쪽이다.
    /// 근거: wire-contract.md §4.2.1 실측 표
    template <class T>
    void setIfPresent(std::string key, const std::optional<T>& v);

    /// 값이 없으면 **`null` 을 명시한다.** 명시적 `encode(to:)` 의 동작이다.
    ///
    /// **`PluginAppliedScanOptionsV2` 하나만 이쪽이다.** 호스트가 그 12키를
    /// 필수로 요구한다(본체 `10-scanner/protocol-contract.md` §9.1).
    /// 다른 타입에 이것을 쓰면 macOS 와 다른 JSON 이 되고 인수 gate 에서 걸린다.
    template <class T>
    void setOrNull(std::string key, const std::optional<T>& v);

    [[nodiscard]] Kind kind() const noexcept { return kind_; }

private:
    friend std::optional<std::string> writeJson(const JsonValue&, KeyOrder);

    /// 실제 직렬화. 실패하면 `ok` 를 false 로 만든다(NaN/Inf).
    void render(KeyOrder order, std::string& out, bool& ok) const;

    Kind kind_ = Kind::Null;
    bool boolValue_ = false;
    std::int64_t intValue_ = 0;
    double doubleValue_ = 0.0;
    std::string stringValue_;
    std::vector<JsonValue> array_;
    std::vector<std::pair<std::string, JsonValue>> object_;
};

namespace detail {

inline JsonValue toJson(bool v) { return JsonValue::boolean(v); }
inline JsonValue toJson(int v) { return JsonValue::integer(v); }
inline JsonValue toJson(std::int64_t v) { return JsonValue::integer(v); }
inline JsonValue toJson(std::uint64_t v) { return JsonValue::integer(static_cast<std::int64_t>(v)); }
inline JsonValue toJson(double v) { return JsonValue::number(v); }
inline JsonValue toJson(const std::string& v) { return JsonValue::string(v); }
inline JsonValue toJson(const JsonValue& v) { return v; }

}  // namespace detail

template <class T>
void JsonValue::setIfPresent(std::string key, const std::optional<T>& v) {
    if (!v) return;  // **키를 아예 넣지 않는다.**
    set(std::move(key), detail::toJson(*v));
}

template <class T>
void JsonValue::setOrNull(std::string key, const std::optional<T>& v) {
    set(std::move(key), v ? detail::toJson(*v) : JsonValue::null());
}

/// JSON 문자열로 쓴다. NaN/Inf 가 들어 있으면 nullopt.
///
/// Swift `JSONEncoder` 는 NaN 에서 **예외를 던진다**(기본 `.throw` 전략).
/// 조용히 `NaN` 리터럴을 쓰는 라이브러리가 있는데 그것은 비표준이고,
/// 호스트 디코더가 거부한다. 여기서도 실패로 돌린다.
[[nodiscard]] std::optional<std::string> writeJson(const JsonValue& value,
                                                   KeyOrder order = KeyOrder::Declaration);

/// JSON 문자열 이스케이프. 따옴표를 포함해 돌려준다.
///
/// `"` `\` `/` 와 제어 문자를 이스케이프한다. **비ASCII 는 건드리지 않는다.**
/// Windows 경로가 이 계약을 매번 지난다 — `C:\a` → `"C:\\a"`.
///
/// `/` 이스케이프는 JSON 표준상 선택이지만 Swift `JSONEncoder` 의 기본이라
/// 따른다(2026-08-05 실측). 문서 §2.3 은 정반대로 서술하고 있었다.
[[nodiscard]] std::string escapeJsonString(std::string_view s);

/// 왕복 가능한 최단 표현. **로케일 독립이다.**
///
/// `36.33` → `"36.33"`. `%.17g` 는 `36.329999999999998` 을 내는데 왕복은
/// 되지만 바이트가 다르고 로그로 보이면 이상하다.
/// 유한하지 않으면 nullopt.
[[nodiscard]] std::optional<std::string> jsonNumber(double v);

}  // namespace negaflow::wire
