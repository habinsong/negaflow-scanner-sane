// SPDX-License-Identifier: GPL-2.0-or-later

#include "wire/json.h"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <cstdio>
#include <system_error>

namespace negaflow::wire {

JsonValue JsonValue::boolean(bool v) {
    JsonValue j;
    j.kind_ = Kind::Bool;
    j.boolValue_ = v;
    return j;
}

JsonValue JsonValue::integer(std::int64_t v) {
    JsonValue j;
    j.kind_ = Kind::Int;
    j.intValue_ = v;
    return j;
}

JsonValue JsonValue::number(double v) {
    JsonValue j;
    j.kind_ = Kind::Double;
    j.doubleValue_ = v;
    return j;
}

JsonValue JsonValue::string(std::string v) {
    JsonValue j;
    j.kind_ = Kind::String;
    j.stringValue_ = std::move(v);
    return j;
}

JsonValue JsonValue::array() {
    JsonValue j;
    j.kind_ = Kind::Array;
    return j;
}

JsonValue JsonValue::object() {
    JsonValue j;
    j.kind_ = Kind::Object;
    return j;
}

void JsonValue::push(JsonValue v) {
    if (kind_ != Kind::Array) return;
    array_.push_back(std::move(v));
}

void JsonValue::set(std::string key, JsonValue v) {
    if (kind_ != Kind::Object) return;
    object_.emplace_back(std::move(key), std::move(v));
}

std::string escapeJsonString(std::string_view s) {
    std::string out;
    out.reserve(s.size() + 2);
    out += '"';
    for (unsigned char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            case '/':
                // **`/` 를 이스케이프한다.** JSON 표준상 선택이지만 Swift
                // `JSONEncoder` 의 기본이 그렇다 — 실측(2026-08-05)으로 확인했고,
                // 문서 §2.3 은 정반대로 적혀 있었다.
                //
                // 제품 코드(main.swift)가 옵션 없는 `JSONEncoder()` 를 쓰므로
                // 실제 wire 출력이 `\/` 다. I-5 는 **같은 형태**를 요구한다.
                //
                // macOS 가 `.withoutEscapingSlashes` 를 켜면 여기도 함께 바꾼다
                // (I-20: 양 플랫폼 동시 적용). 한쪽만 바꾸면 골든이 갈린다.
                out += "\\/";
                break;
            default:
                if (c < 0x20) {
                    // 축약형이 없는 제어 문자만 \u00XX 로. 소문자 hex 는
                    // Swift JSONEncoder 와 같다.
                    char buf[7];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    // **비ASCII 는 그대로 흘려보낸다.** UTF-8 바이트를 건드리지
                    // 않는다. `/` 도 이스케이프하지 않는다.
                    out += static_cast<char>(c);
                }
                break;
        }
    }
    out += '"';
    return out;
}

std::optional<std::string> jsonNumber(double v) {
    // NaN/Inf 는 JSON 에 없다. Swift 는 여기서 인코딩을 실패시킨다.
    if (!std::isfinite(v)) return std::nullopt;

    // std::to_chars(double) 는 **로케일 독립**이고 왕복 최단 표현을 낸다.
    // std::ostream 과 printf 는 로케일 의존이라 독일어 환경에서 "36,33" 이 된다.
    char buf[64];
    auto [ptr, ec] = std::to_chars(buf, buf + sizeof(buf), v);
    if (ec != std::errc{}) return std::nullopt;
    std::string out(buf, ptr);

    // to_chars 는 지수 표기를 쓸 수 있다(1e+20). JSON 은 허용하지만 Swift 는
    // 큰 값에서 같은 형태를 내므로 그대로 둔다 — wire 에 그런 값이 오지 않는다.
    return out;
}

void JsonValue::render(KeyOrder order, std::string& out, bool& ok) const {
    if (!ok) return;
    const JsonValue& value = *this;
    switch (value.kind_) {
        case JsonValue::Kind::Null:
            out += "null";
            break;
        case JsonValue::Kind::Bool:
            out += value.boolValue_ ? "true" : "false";
            break;
        case JsonValue::Kind::Int: {
            char buf[32];
            auto [ptr, ec] = std::to_chars(buf, buf + sizeof(buf), value.intValue_);
            if (ec != std::errc{}) {
                ok = false;
                return;
            }
            // **소수점을 붙이지 않는다.** 3600 이지 3600.0 이 아니다.
            out.append(buf, ptr);
            break;
        }
        case JsonValue::Kind::Double: {
            const auto text = jsonNumber(value.doubleValue_);
            if (!text) {
                ok = false;  // NaN/Inf
                return;
            }
            out += *text;
            break;
        }
        case JsonValue::Kind::String:
            out += escapeJsonString(value.stringValue_);
            break;
        case JsonValue::Kind::Array:
            out += '[';
            for (std::size_t i = 0; i < value.array_.size(); ++i) {
                if (i) out += ',';
                // **배열 순서는 의미다.** 정렬하지 않는다.
                value.array_[i].render(order, out, ok);
                if (!ok) return;
            }
            out += ']';
            break;
        case JsonValue::Kind::Object: {
            out += '{';
            // 정렬은 **복사본에서** 한다. 값 자체의 삽입 순서는 계약이므로 보존한다.
            std::vector<const std::pair<std::string, JsonValue>*> ordered;
            ordered.reserve(value.object_.size());
            for (const auto& f : value.object_) ordered.push_back(&f);
            if (order == KeyOrder::Sorted) {
                std::sort(ordered.begin(), ordered.end(),
                          [](const auto* a, const auto* b) { return a->first < b->first; });
            }
            for (std::size_t i = 0; i < ordered.size(); ++i) {
                if (i) out += ',';
                out += escapeJsonString(ordered[i]->first);
                out += ':';
                ordered[i]->second.render(order, out, ok);
                if (!ok) return;
            }
            out += '}';
            break;
        }
    }
}

std::optional<std::string> writeJson(const JsonValue& value, KeyOrder order) {
    std::string out;
    bool ok = true;
    value.render(order, out, ok);
    if (!ok) return std::nullopt;
    return out;
}

}  // namespace negaflow::wire
