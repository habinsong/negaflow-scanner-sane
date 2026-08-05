// SPDX-License-Identifier: GPL-2.0-or-later

#include "wire/snapshot.h"

#include <array>
#include <charconv>
#include <cstdint>
#include <string>
#include <system_error>
#include <vector>

#include "wire/json.h"

// wire/parse.cpp 와 같은 이유로 경고를 끄고 넣는다. **`document.h` 를 쓰지
// 않는다** — 알려진 MSVC /W4 경고 넷이 전부 거기 있다. 여기도 SAX 만 쓴다.
#ifdef _MSC_VER
#pragma warning(push, 0)
#endif
#include "rapidjson/error/error.h"
#include "rapidjson/memorystream.h"
#include "rapidjson/reader.h"
#ifdef _MSC_VER
#pragma warning(pop)
#endif

namespace negaflow::wire {
namespace {

constexpr std::string_view kAlphabet =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// 스냅샷은 우리가 만든 평평한 객체다. 중첩은 `deviceIdentity` 하나뿐이므로
/// 일반 값 트리를 만들지 않고 **필요한 키만 받아 적는다.**
///
/// 상한을 파싱 중에 건다. 다 만든 뒤 검사하면 그 사이에 메모리를 다 쓴다.
class SnapshotHandler {
public:
    [[nodiscard]] bool ok() const noexcept { return ok_; }
    [[nodiscard]] CapabilitySnapshot& snapshot() noexcept { return snapshot_; }
    [[nodiscard]] bool sawSchemaVersion() const noexcept { return sawSchemaVersion_; }

    bool Null() { return skipScalar(); }
    bool Bool(bool) { return fail(); }
    bool Int(int v) { return integer(v); }
    bool Uint(unsigned v) { return integer(static_cast<std::int64_t>(v)); }
    bool Int64(std::int64_t v) { return integer(v); }
    bool Uint64(std::uint64_t v) { return integer(static_cast<std::int64_t>(v)); }
    bool Double(double) { return fail(); }

    bool String(const char* text, rapidjson::SizeType length, bool) {
        std::string value(text, length);
        if (depth_ == 1) {
            if (key_ == "deviceID") snapshot_.deviceID = std::move(value);
            else if (key_ == "backend") snapshot_.backend = std::move(value);
            else if (key_ == "acquisitionDevice") snapshot_.acquisitionDevice = std::move(value);
            else if (key_ == "optionDump") snapshot_.optionDump = std::move(value);
            else if (key_ == "deviceType") snapshot_.deviceType = std::move(value);
            else if (key_ == "validatedMode") snapshot_.validatedMode = std::move(value);
        } else if (depth_ == 2 && parentKey_ == "deviceIdentity") {
            if (!snapshot_.deviceIdentity) snapshot_.deviceIdentity.emplace();
            if (key_ == "vendor") snapshot_.deviceIdentity->vendor = std::move(value);
            else if (key_ == "model") snapshot_.deviceIdentity->model = std::move(value);
        }
        key_.clear();
        return true;
    }

    bool Key(const char* text, rapidjson::SizeType length, bool) {
        key_.assign(text, length);
        return true;
    }

    bool StartObject() {
        if (depth_ >= 2) return fail();
        if (depth_ == 1) {
            if (key_ != "deviceIdentity") return fail();
            parentKey_ = key_;
            snapshot_.deviceIdentity.emplace();
        }
        ++depth_;
        key_.clear();
        return true;
    }

    bool EndObject(rapidjson::SizeType) {
        --depth_;
        if (depth_ == 1) parentKey_.clear();
        key_.clear();
        return true;
    }

    bool StartArray() { return fail(); }
    bool EndArray(rapidjson::SizeType) { return fail(); }
    bool RawNumber(const char*, rapidjson::SizeType, bool) { return fail(); }

private:
    bool fail() {
        ok_ = false;
        return false;
    }

    bool skipScalar() {
        // 옵셔널이 `null` 로 실려 오면 "없음"이다. 필수 키에 null 이면
        // 뒤의 검증이 빈 문자열을 잡는다.
        key_.clear();
        return true;
    }

    bool integer(std::int64_t value) {
        if (depth_ == 1 && key_ == "schemaVersion") {
            if (value < 0 || value > 1'000'000) return fail();
            snapshot_.schemaVersion = static_cast<int>(value);
            sawSchemaVersion_ = true;
        }
        key_.clear();
        return true;
    }

    CapabilitySnapshot snapshot_;
    std::string key_;
    std::string parentKey_;
    int depth_ = 0;
    bool ok_ = true;
    bool sawSchemaVersion_ = false;
};

}  // namespace

std::string base64Encode(std::string_view raw) {
    std::string out;
    out.reserve(((raw.size() + 2) / 3) * 4);
    std::size_t i = 0;
    while (i + 3 <= raw.size()) {
        const std::uint32_t chunk = (static_cast<unsigned char>(raw[i]) << 16) |
                                    (static_cast<unsigned char>(raw[i + 1]) << 8) |
                                    static_cast<unsigned char>(raw[i + 2]);
        out.push_back(kAlphabet[(chunk >> 18) & 0x3Fu]);
        out.push_back(kAlphabet[(chunk >> 12) & 0x3Fu]);
        out.push_back(kAlphabet[(chunk >> 6) & 0x3Fu]);
        out.push_back(kAlphabet[chunk & 0x3Fu]);
        i += 3;
    }
    const std::size_t remaining = raw.size() - i;
    if (remaining == 1) {
        const std::uint32_t chunk = static_cast<unsigned char>(raw[i]) << 16;
        out.push_back(kAlphabet[(chunk >> 18) & 0x3Fu]);
        out.push_back(kAlphabet[(chunk >> 12) & 0x3Fu]);
        out.push_back('=');
        out.push_back('=');
    } else if (remaining == 2) {
        const std::uint32_t chunk = (static_cast<unsigned char>(raw[i]) << 16) |
                                    (static_cast<unsigned char>(raw[i + 1]) << 8);
        out.push_back(kAlphabet[(chunk >> 18) & 0x3Fu]);
        out.push_back(kAlphabet[(chunk >> 12) & 0x3Fu]);
        out.push_back(kAlphabet[(chunk >> 6) & 0x3Fu]);
        out.push_back('=');
    }
    return out;
}

std::optional<std::string> base64Decode(std::string_view encoded) {
    if (encoded.size() % 4 != 0) return std::nullopt;
    static const auto table = [] {
        std::array<signed char, 256> t{};
        t.fill(-1);
        for (std::size_t i = 0; i < kAlphabet.size(); ++i) {
            t[static_cast<unsigned char>(kAlphabet[i])] = static_cast<signed char>(i);
        }
        return t;
    }();

    std::string out;
    out.reserve(encoded.size() / 4 * 3);
    for (std::size_t i = 0; i < encoded.size(); i += 4) {
        std::uint32_t chunk = 0;
        int bytes = 3;
        for (int k = 0; k < 4; ++k) {
            const char c = encoded[i + k];
            if (c == '=') {
                // 패딩은 마지막 블록의 끝에만 온다.
                if (i + 4 != encoded.size() || k < 2) return std::nullopt;
                bytes = k - 1;
                for (int rest = k; rest < 4; ++rest) {
                    if (encoded[i + rest] != '=') return std::nullopt;
                }
                chunk <<= static_cast<unsigned>(6 * (4 - k));
                break;
            }
            const signed char decoded = table[static_cast<unsigned char>(c)];
            if (decoded < 0) return std::nullopt;
            chunk = (chunk << 6) | static_cast<std::uint32_t>(decoded);
        }
        const char triple[3] = {static_cast<char>((chunk >> 16) & 0xFFu),
                                static_cast<char>((chunk >> 8) & 0xFFu),
                                static_cast<char>(chunk & 0xFFu)};
        out.append(triple, static_cast<std::size_t>(bytes));
    }
    return out;
}

std::optional<std::string> encodeCapabilityToken(const CapabilitySnapshot& snapshot) {
    JsonValue root = JsonValue::object();
    root.set("schemaVersion", JsonValue::integer(snapshot.schemaVersion));
    root.set("deviceID", JsonValue::string(snapshot.deviceID));
    root.set("backend", JsonValue::string(snapshot.backend));
    root.set("acquisitionDevice", JsonValue::string(snapshot.acquisitionDevice));
    if (snapshot.deviceIdentity) {
        JsonValue identity = JsonValue::object();
        identity.set("vendor", JsonValue::string(snapshot.deviceIdentity->vendor));
        identity.set("model", JsonValue::string(snapshot.deviceIdentity->model));
        root.set("deviceIdentity", std::move(identity));
    }
    root.setIfPresent("deviceType", snapshot.deviceType);
    root.set("optionDump", JsonValue::string(snapshot.optionDump));
    root.setIfPresent("validatedMode", snapshot.validatedMode);

    const std::optional<std::string> json = writeJson(root);
    if (!json) return std::nullopt;
    std::string token = base64Encode(*json);
    if (token.size() > kMaxCapabilityTokenBytes) return std::nullopt;
    return token;
}

std::optional<CapabilitySnapshot> decodeCapabilityToken(std::string_view token) {
    if (token.empty() || token.size() > kMaxCapabilityTokenBytes) return std::nullopt;
    const std::optional<std::string> json = base64Decode(token);
    if (!json) return std::nullopt;

    SnapshotHandler handler;
    rapidjson::MemoryStream stream(json->data(), json->size());
    rapidjson::Reader reader;
    // `kParseIterativeFlag` 로 재귀를 없앤다 — 토큰은 신뢰할 수 없는 입력이고
    // 깊이 공격으로 스택을 넘길 수 있다. **`kParseStopWhenDoneFlag` 는 쓰지
    // 않는다**: 그 플래그는 값 하나를 읽고 뒤를 무시하므로 `{...}x` 가 통과한다.
    // `wire/parse` 와 같은 판정을 유지한다.
    const auto result = reader.Parse<rapidjson::kParseIterativeFlag>(stream, handler);
    if (result.IsError() || !handler.ok()) return std::nullopt;
    if (!handler.sawSchemaVersion()) return std::nullopt;

    CapabilitySnapshot snapshot = std::move(handler.snapshot());
    if (snapshot.schemaVersion != CapabilitySnapshot::kCurrentSchemaVersion) return std::nullopt;
    if (snapshot.deviceIdentity &&
        snapshot.deviceIdentity->vendor.empty() && snapshot.deviceIdentity->model.empty()) {
        snapshot.deviceIdentity.reset();
    }
    return snapshot;
}

}  // namespace negaflow::wire
