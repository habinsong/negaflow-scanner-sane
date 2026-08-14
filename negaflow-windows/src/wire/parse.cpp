// negaflow-scanner-sane — Windows adapter
// wire/parse 구현. 계약과 실측 근거는 parse.h 에 있다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#include "wire/parse.h"

#include <charconv>
#include <cmath>
#include <cstring>
#include <limits>
#include <system_error>
#include <utility>
#include <vector>

// RapidJSON 헤더는 **경고를 끈 채로** 들어온다. 이 프로젝트는 -Werror / /WX 다.
//
// CMake 가 이미 SYSTEM 으로 넣지만 MSVC 에서 그것이 통하려면 `/external:` 계열
// 플래그가 맞아야 하고 VS 버전을 탄다. `#pragma warning(push, 0)` 은 include
// 방식과 VS 버전에 무관하게 통한다 — 그래서 둘 다 건다.
//
// **지금은 실제로 필요 없다.** 알려진 MSVC /W4 경고 넷은 전부
// document.h / schema.h / pointer.h 에 있는데 이 파일은 그 셋을 끌어오지
// 않는다(2026-08-05 확인, `c++ -H` 로 전이 포함까지 확인함).
//
// ```text
// C4996 / STL4015   document.h  std::iterator 상속        1.1.0 에만 있다
// C5054             document.h  다른 enum 간 operator|
// C5232             document.h  C++20 재귀 비교
// C4127 (미억제)     schema.h / pointer.h  상수 조건
// ```
//
// 그래도 걸어 둔다. **누군가 나중에 `document.h` 를 넣는 순간 빌드가
// 깨지는 것보다, 그때도 조용히 넘어가는 편이 낫다.**
#ifdef _MSC_VER
#pragma warning(push, 0)
#endif
#include "rapidjson/encodedstream.h"
#include "rapidjson/error/error.h"
#include "rapidjson/memorystream.h"
#include "rapidjson/reader.h"
#ifdef _MSC_VER
#pragma warning(pop)
#endif

namespace negaflow::wire {
namespace {

// --- 값 트리 ---------------------------------------------------------------
//
// RapidJSON 의 `Document` 를 쓰지 않는 이유는 parse.h 에 적혀 있다: 수 변환이
// Swift 와 다르다. 여기서는 **원문 리터럴을 그대로 들고 있다가** 필드를 꺼낼
// 때 대상 타입에 맞춰 변환한다.
//
// 객체는 **삽입 순서를 유지하고 중복 키를 그대로 담는다.** `findMember` 가
// 첫 값을 돌려주므로 그것이 곧 macOS 의 "첫 값 우선"이다(실측).

struct Node {
    enum class Kind { Null, Bool, Number, String, Array, Object };

    Kind kind = Kind::Null;
    bool boolValue = false;
    /// Number 면 **원문 리터럴**, String 이면 이스케이프가 풀린 값.
    std::string text;
    std::vector<Node> items;                             ///< Array
    std::vector<std::pair<std::string, Node>> members;   ///< Object
};

/// 첫 번째로 일치하는 멤버. 없으면 nullptr.
const Node* findMember(const Node& object, std::string_view key) {
    for (const auto& m : object.members) {
        if (m.first == key) return &m.second;
    }
    return nullptr;
}

// --- SAX 핸들러 ------------------------------------------------------------
//
// 상한을 **파싱 중에** 건다. 다 만든 뒤 검사하면 그 사이에 메모리를 다 쓴다.

class TreeBuilder {
public:
    explicit TreeBuilder(const ParseLimits& limits) : limits_(limits) {}

    [[nodiscard]] ParseError error() const noexcept { return error_; }
    [[nodiscard]] Node& root() noexcept { return root_; }

    // RapidJSON 핸들러 계약.
    bool Null() { return addScalar(Node{Node::Kind::Null, false, {}, {}, {}}); }
    bool Bool(bool b) { return addScalar(Node{Node::Kind::Bool, b, {}, {}, {}}); }

    bool RawNumber(const char* str, rapidjson::SizeType length, bool) {
        Node n;
        n.kind = Node::Kind::Number;
        n.text.assign(str, length);
        return addScalar(std::move(n));
    }

    bool String(const char* str, rapidjson::SizeType length, bool) {
        if (length > limits_.maxStringBytes) return fail(ParseError::StringTooLong);
        Node n;
        n.kind = Node::Kind::String;
        n.text.assign(str, length);
        return addScalar(std::move(n));
    }

    bool Key(const char* str, rapidjson::SizeType length, bool) {
        if (length > limits_.maxStringBytes) return fail(ParseError::StringTooLong);
        pendingKey_.assign(str, length);
        hasPendingKey_ = true;
        if (limits_.duplicateKeys == DuplicateKeyPolicy::Reject && !stack_.empty()) {
            for (const auto& m : stack_.back().members) {
                if (m.first == pendingKey_) return fail(ParseError::DuplicateKey);
            }
        }
        return true;
    }

    bool StartObject() { return startContainer(Node::Kind::Object); }
    bool StartArray() { return startContainer(Node::Kind::Array); }
    bool EndObject(rapidjson::SizeType) { return endContainer(); }
    bool EndArray(rapidjson::SizeType) { return endContainer(); }

    // `kParseNumbersAsStringsFlag` 를 켜면 아래 다섯은 호출되지 않는다.
    // 그래도 방어적으로 실패시킨다 — 조용히 값이 사라지는 것보다 낫다.
    bool Int(int) { return fail(ParseError::MalformedJson); }
    bool Uint(unsigned) { return fail(ParseError::MalformedJson); }
    bool Int64(std::int64_t) { return fail(ParseError::MalformedJson); }
    bool Uint64(std::uint64_t) { return fail(ParseError::MalformedJson); }
    bool Double(double) { return fail(ParseError::MalformedJson); }

private:
    bool fail(ParseError e) {
        if (error_ == ParseError::None) error_ = e;
        return false;
    }

    bool startContainer(Node::Kind kind) {
        if (static_cast<std::size_t>(stack_.size()) + 1 >
            static_cast<std::size_t>(limits_.maxDepth)) {
            return fail(ParseError::DepthExceeded);
        }
        Node n;
        n.kind = kind;
        keyForLevel_.push_back(hasPendingKey_ ? std::move(pendingKey_) : std::string{});
        hasPendingKey_ = false;
        pendingKey_.clear();
        stack_.push_back(std::move(n));
        return true;
    }

    bool endContainer() {
        Node done = std::move(stack_.back());
        stack_.pop_back();
        std::string key = std::move(keyForLevel_.back());
        keyForLevel_.pop_back();
        if (stack_.empty()) {
            root_ = std::move(done);
            return true;
        }
        return attach(std::move(done), std::move(key));
    }

    bool addScalar(Node n) {
        if (stack_.empty()) {
            root_ = std::move(n);
            return true;
        }
        std::string key;
        if (hasPendingKey_) {
            key = std::move(pendingKey_);
            hasPendingKey_ = false;
            pendingKey_.clear();
        }
        return attach(std::move(n), std::move(key));
    }

    bool attach(Node n, std::string key) {
        Node& parent = stack_.back();
        if (parent.kind == Node::Kind::Object) {
            if (parent.members.size() >= limits_.maxContainerItems) {
                return fail(ParseError::TooManyItems);
            }
            parent.members.emplace_back(std::move(key), std::move(n));
        } else {
            if (parent.items.size() >= limits_.maxContainerItems) {
                return fail(ParseError::TooManyItems);
            }
            parent.items.push_back(std::move(n));
        }
        return true;
    }

    ParseLimits limits_;
    ParseError error_ = ParseError::None;
    Node root_;
    std::vector<Node> stack_;
    /// `stack_[i]` 를 부모에 넣을 때 쓸 키. 부모가 배열이면 빈 문자열이다.
    std::vector<std::string> keyForLevel_;
    std::string pendingKey_;
    bool hasPendingKey_ = false;
};

/// 토큰화. 실패하면 nullopt 이고 `error` 에 사유가 담긴다.
std::optional<Node> tokenize(std::string_view json, const ParseLimits& limits, ParseError& error) {
    if (json.size() > limits.maxDocumentBytes) {
        error = ParseError::DocumentTooLarge;
        return std::nullopt;
    }
    // 빈 입력에서 `data()` 가 nullptr 일 수 있다. MemoryStream 이 그것을 읽는다.
    static constexpr char kEmpty[] = "";
    const char* begin = json.empty() ? kEmpty : json.data();

    rapidjson::MemoryStream ms(begin, json.size());
    // `EncodedInputStream` 이 UTF-8 BOM 을 건너뛴다 — macOS 가 BOM 을 받아들인다(실측).
    rapidjson::EncodedInputStream<rapidjson::UTF8<>, rapidjson::MemoryStream> is(ms);

    TreeBuilder builder(limits);
    rapidjson::Reader reader;
    // 반복 파서. 재귀 파서는 깊은 입력에서 스택을 넘긴다(§6.3).
    // 수는 문자열로 받는다 — 변환은 우리가 한다.
    const rapidjson::ParseResult result =
        reader.Parse<rapidjson::kParseIterativeFlag | rapidjson::kParseNumbersAsStringsFlag>(
            is, builder);

    if (!result) {
        error = builder.error() != ParseError::None ? builder.error() : ParseError::MalformedJson;
        return std::nullopt;
    }
    return std::move(builder.root());
}

// --- 수 변환 ---------------------------------------------------------------
//
// **`std::from_chars` 만 쓴다.** 로케일에 의존하지 않고, 오버플로와
// 언더플로를 둘 다 `result_out_of_range` 로 알려준다 — 그 둘이 Swift 가
// 문서를 거부하는 조건과 정확히 같다(parse.h 의 실측 표).

/// JSON 수 리터럴 → double. 문법은 RapidJSON 이 이미 검증했다.
std::optional<double> numberAsDouble(const std::string& text) {
    const char* first = text.data();
    const char* last = first + text.size();
    double value = 0.0;
    const auto result = std::from_chars(first, last, value);
    if (result.ec != std::errc{} || result.ptr != last) return std::nullopt;
    if (!std::isfinite(value)) return std::nullopt;  // 방어. from_chars 가 이미 걸러낸다.
    return value;
}

/// JSON 수 리터럴 → int64. `16.0` 과 `1.6e1` 도 16 이다(macOS 실측).
std::optional<std::int64_t> numberAsInt64(const std::string& text, ParseError& error) {
    const char* first = text.data();
    const char* last = first + text.size();

    std::int64_t direct = 0;
    const auto asInt = std::from_chars(first, last, direct);
    if (asInt.ec == std::errc{} && asInt.ptr == last) return direct;

    // 여기 오는 것은 둘 중 하나다.
    //   ① 정수 문법이 아니다        16.0, 1.6e1, 1200.5
    //   ② int64 를 넘는다           9223372036854775808
    // ①은 값이 정수면 통과, ②는 거부다. 판정은 double 을 거친다.
    double asDouble = 0.0;
    const auto viaDouble = std::from_chars(first, last, asDouble);
    if (viaDouble.ec != std::errc{} || viaDouble.ptr != last) {
        error = ParseError::NumberOutOfRange;
        return std::nullopt;
    }
    if (!std::isfinite(asDouble)) {
        error = ParseError::NumberOutOfRange;
        return std::nullopt;
    }
    if (std::trunc(asDouble) != asDouble) {
        error = ParseError::NumberNotIntegral;
        return std::nullopt;
    }
    // `static_cast<double>(INT64_MAX)` 는 2^63 으로 반올림된다. 그래서 위쪽은
    // `<` 로 비교해야 한다 — `<=` 로 쓰면 2^63 이 통과하고 캐스트가 UB 다.
    constexpr double kUpperExclusive = 9223372036854775808.0;   // 2^63
    constexpr double kLowerInclusive = -9223372036854775808.0;  // -2^63
    if (!(asDouble >= kLowerInclusive && asDouble < kUpperExclusive)) {
        error = ParseError::NumberOutOfRange;
        return std::nullopt;
    }
    return static_cast<std::int64_t>(asDouble);
}

// --- 필드 꺼내기 -----------------------------------------------------------
//
// 옵셔널 규칙: **키 부재와 `null` 이 같다**(둘 다 값 없음). 실측으로 확인했다.
// 필수 규칙: 부재는 MissingKey, `null` 은 NullForRequired. 둘 다 거부다.

bool requireNumber(const Node& node, ParseError& error, double& out) {
    if (node.kind != Node::Kind::Number) {
        error = ParseError::TypeMismatch;
        return false;
    }
    const auto v = numberAsDouble(node.text);
    if (!v) {
        error = ParseError::NumberOutOfRange;
        return false;
    }
    out = *v;
    return true;
}

bool requireInt32(const Node& node, ParseError& error, int& out) {
    if (node.kind != Node::Kind::Number) {
        error = ParseError::TypeMismatch;
        return false;
    }
    const auto wide = numberAsInt64(node.text, error);
    if (!wide) {
        if (error == ParseError::None) error = ParseError::NumberOutOfRange;
        return false;
    }
    if (*wide < std::numeric_limits<int>::min() || *wide > std::numeric_limits<int>::max()) {
        // **macOS 는 여기서 갈린다.** parse.h 의 `IntegerTooWide` 설명을 볼 것.
        error = ParseError::IntegerTooWide;
        return false;
    }
    out = static_cast<int>(*wide);
    return true;
}

bool requireBool(const Node& node, ParseError& error, bool& out) {
    if (node.kind != Node::Kind::Bool) {
        error = ParseError::TypeMismatch;
        return false;
    }
    out = node.boolValue;
    return true;
}

bool requireString(const Node& node, ParseError& error, std::string& out) {
    if (node.kind != Node::Kind::String) {
        error = ParseError::TypeMismatch;
        return false;
    }
    out = node.text;
    return true;
}

/// 필수 키를 꺼낸다. 부재/`null` 이면 실패다.
const Node* requiredMember(const Node& object, std::string_view key, ParseError& error) {
    const Node* node = findMember(object, key);
    if (node == nullptr) {
        error = ParseError::MissingKey;
        return nullptr;
    }
    if (node->kind == Node::Kind::Null) {
        error = ParseError::NullForRequired;
        return nullptr;
    }
    return node;
}

/// 옵셔널 키를 꺼낸다. **부재와 `null` 이 같다** — 둘 다 nullptr 다.
const Node* optionalMember(const Node& object, std::string_view key) {
    const Node* node = findMember(object, key);
    if (node == nullptr || node->kind == Node::Kind::Null) return nullptr;
    return node;
}

#define REQUIRE_FIELD(object, key, error, kind, out)                     \
    do {                                                                 \
        const Node* node_ = requiredMember((object), (key), (error));    \
        if (node_ == nullptr) return false;                              \
        if (!require##kind(*node_, (error), (out))) return false;        \
    } while (false)

/// `ScanArea` 는 **커스텀 디코더를 가진다**(ScannerModel.swift).
///
/// ```text
/// originXMM / originYMM   decodeIfPresent ?? 0    부재도 null 도 0
/// widthMM   / heightMM    decode (필수)           부재는 keyNotFound, null 은 valueNotFound
/// ```
bool decodeScanArea(const Node& node, ParseError& error, sane::ScanArea& out) {
    if (node.kind != Node::Kind::Object) {
        error = ParseError::TypeMismatch;
        return false;
    }
    sane::ScanArea area;
    area.originXMM = 0.0;
    area.originYMM = 0.0;
    if (const Node* x = optionalMember(node, "originXMM")) {
        if (!requireNumber(*x, error, area.originXMM)) return false;
    }
    if (const Node* y = optionalMember(node, "originYMM")) {
        if (!requireNumber(*y, error, area.originYMM)) return false;
    }
    REQUIRE_FIELD(node, "widthMM", error, Number, area.widthMM);
    REQUIRE_FIELD(node, "heightMM", error, Number, area.heightMM);
    out = area;
    return true;
}

bool decodeRequest(const Node& root, ParseError& error, ScanRequestV2& out) {
    if (root.kind != Node::Kind::Object) {
        error = ParseError::NotAnObject;
        return false;
    }
    ScanRequestV2 request;

    REQUIRE_FIELD(root, "protocolVersion", error, Int32, request.protocolVersion);

    // requestID 는 **원문 문자열을 그대로 반사한다**(D-12). 파싱해서 다시
    // 만들지 않는다 — 그러면 macOS 처럼 대문자로 정규화돼 바이트가 달라진다.
    REQUIRE_FIELD(root, "requestID", error, String, request.requestID);
    if (!isValidRequestUUID(request.requestID)) {
        error = ParseError::InvalidUuid;
        return false;
    }

    REQUIRE_FIELD(root, "deviceID", error, String, request.deviceID);
    REQUIRE_FIELD(root, "resolutionDPI", error, Int32, request.resolutionDPI);
    REQUIRE_FIELD(root, "bitDepth", error, Int32, request.bitDepth);
    REQUIRE_FIELD(root, "colorMode", error, String, request.colorMode);
    REQUIRE_FIELD(root, "filmType", error, String, request.filmType);
    REQUIRE_FIELD(root, "preview", error, Bool, request.preview);
    REQUIRE_FIELD(root, "multiExposure", error, Bool, request.multiExposure);
    REQUIRE_FIELD(root, "infrared", error, Bool, request.infrared);

    if (const Node* n = optionalMember(root, "brightnessAdjustment")) {
        double v = 0.0;
        if (!requireNumber(*n, error, v)) return false;
        request.brightnessAdjustment = v;
    }
    if (const Node* n = optionalMember(root, "contrastAdjustment")) {
        double v = 0.0;
        if (!requireNumber(*n, error, v)) return false;
        request.contrastAdjustment = v;
    }

    {
        const Node* n = requiredMember(root, "scanArea", error);
        if (n == nullptr) return false;
        if (!decodeScanArea(*n, error, request.scanArea)) return false;
    }

    if (const Node* n = optionalMember(root, "hardwareExposureTime")) {
        int v = 0;
        if (!requireInt32(*n, error, v)) return false;
        request.hardwareExposureTime = v;
    }

    REQUIRE_FIELD(root, "outputRawTIFF", error, Bool, request.outputRawTIFF);

    if (const Node* n = optionalMember(root, "autofocus")) {
        bool v = false;
        if (!requireBool(*n, error, v)) return false;
        request.autofocus = v;
    }
    if (const Node* n = optionalMember(root, "focusPosition")) {
        int v = 0;
        if (!requireInt32(*n, error, v)) return false;
        request.focusPosition = v;
    }

    if (const Node* n = optionalMember(root, "capabilityToken")) {
        std::string v;
        if (!requireString(*n, error, v)) return false;
        request.capabilityToken = std::move(v);
    }

    REQUIRE_FIELD(root, "outputPath", error, String, request.outputPath);

    out = std::move(request);
    return true;
}

#undef REQUIRE_FIELD

}  // namespace

ParseLimits ParseLimits::swiftEquivalent() noexcept {
    ParseLimits limits;
    limits.maxDocumentBytes = std::numeric_limits<std::size_t>::max();
    limits.maxDepth = 512;
    limits.maxStringBytes = std::numeric_limits<std::size_t>::max();
    limits.maxContainerItems = std::numeric_limits<std::size_t>::max();
    limits.duplicateKeys = DuplicateKeyPolicy::KeepFirst;
    return limits;
}

bool isValidRequestUUID(std::string_view s) noexcept {
    // 8-4-4-4-12. 하이픈 위치가 고정이고 나머지는 전부 16진수다.
    static constexpr std::size_t kLength = 36;
    if (s.size() != kLength) return false;

    const auto isHex = [](char c) noexcept {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    };
    for (std::size_t i = 0; i < kLength; ++i) {
        const bool hyphenPosition = (i == 8 || i == 13 || i == 18 || i == 23);
        if (hyphenPosition) {
            if (s[i] != '-') return false;
        } else if (!isHex(s[i])) {
            return false;
        }
    }
    return true;
}

std::optional<ScanRequestV2> parseScanRequest(std::string_view json,
                                              const ParseLimits& limits,
                                              ParseError* error) {
    ParseError local = ParseError::None;
    const auto root = tokenize(json, limits, local);
    if (!root) {
        if (error != nullptr) *error = local;
        return std::nullopt;
    }
    ScanRequestV2 request;
    if (!decodeRequest(*root, local, request)) {
        if (error != nullptr) *error = local;
        return std::nullopt;
    }
    if (error != nullptr) *error = ParseError::None;
    return request;
}

std::optional<CapabilityRequest> parseCapabilityRequest(std::string_view json,
                                                        const ParseLimits& limits,
                                                        ParseError* error) {
    ParseError local = ParseError::None;
    const auto root = tokenize(json, limits, local);
    if (!root) {
        if (error != nullptr) *error = local;
        return std::nullopt;
    }
    if (root->kind != Node::Kind::Object) {
        if (error != nullptr) *error = ParseError::NotAnObject;
        return std::nullopt;
    }

    CapabilityRequest request;
    const std::pair<const char*, std::string*> fields[] = {
        {"deviceID", &request.deviceID},
        {"vendor", &request.vendor},
        {"model", &request.model},
    };
    for (const auto& [key, target] : fields) {
        const Node* n = requiredMember(*root, key, local);
        if (n == nullptr || !requireString(*n, local, *target)) {
            if (error != nullptr) *error = local;
            return std::nullopt;
        }
    }
    if (error != nullptr) *error = ParseError::None;
    return request;
}

std::optional<ScanRequestEnvelope> parseScanRequestEnvelope(std::string_view json,
                                                            const ParseLimits& limits,
                                                            ParseError* error) {
    ParseError local = ParseError::None;
    const auto root = tokenize(json, limits, local);
    if (!root) {
        if (error != nullptr) *error = local;
        return std::nullopt;
    }
    if (root->kind != Node::Kind::Object) {
        if (error != nullptr) *error = ParseError::NotAnObject;
        return std::nullopt;
    }

    ScanRequestEnvelope envelope;
    // 두 필드 모두 옵셔널이다. 다만 **있는데 형태가 틀리면 봉투가 실패한다** —
    // Swift 의 `decodeIfPresent(UUID.self)` 가 그렇게 던진다.
    if (const Node* n = optionalMember(*root, "protocolVersion")) {
        int v = 0;
        if (!requireInt32(*n, local, v)) {
            if (error != nullptr) *error = local;
            return std::nullopt;
        }
        envelope.protocolVersion = v;
    }
    if (const Node* n = optionalMember(*root, "requestID")) {
        std::string v;
        if (!requireString(*n, local, v)) {
            if (error != nullptr) *error = local;
            return std::nullopt;
        }
        if (!isValidRequestUUID(v)) {
            if (error != nullptr) *error = ParseError::InvalidUuid;
            return std::nullopt;
        }
        envelope.requestID = std::move(v);
    }
    if (error != nullptr) *error = ParseError::None;
    return envelope;
}

}  // namespace negaflow::wire
