// negaflow-scanner-sane — Windows adapter
// wire/parse — 호스트 요청 JSON **디코딩**. 방출은 wire/json 에 있다.
//
// 이식 원본: Sources/negaflow-scanner-sane/main.swift (`case "scan"` 의 JSONDecoder)
//            Sources/SANEPluginCore/PluginProtocolV2.swift (PluginScanRequestV2)
//            Sources/SANEPluginCore/ScannerModel.swift     (ScanArea.init(from:))
// 정본 문서: windows_docs/05-protocol/encoding-and-json.md §6, §7
//
// ## 왜 실패 사유를 돌려주지 않는가
//
// macOS 는 **모든 디코드 실패를 한 메시지로 뭉갠다.**
//
// ```swift
// guard let wire = try? decoder.decode(PluginScanRequestV2.self, from: stdinData) else {
//     … emit(type: "error", message: "scan 옵션 JSON 파싱 실패")
// ```
//
// `try?` 가 `DecodingError` 를 통째로 버린다. 그래서 호스트가 보는 것은
// 언제나 그 한 문장이다. 여기서 사유를 만들어 내보내면 **wire 가 갈린다**(I-5).
//
// `ParseError` 는 단위 테스트와 로그를 위한 것이지 wire 로 나가지 않는다.
//
// ## 파리티 경계
//
// 위 이유로 대조할 것은 **수락/거부 판정과 디코드된 값**이지 오류 문구가 아니다.
// 그래서 파리티 덤프는 `ok`/`fail` 과 필드 값을 찍는다.
//
// ## RapidJSON 을 어디까지 쓰는가
//
// **토큰화까지만 쓴다. 수 변환은 쓰지 않는다.**
// `kParseNumbersAsStringsFlag` 로 원문 리터럴을 받아 `std::from_chars` 로
// 직접 변환한다. 이유는 실측이다(2026-08-05, RapidJSON 1.1.0):
//
// ```text
// 입력        Swift JSONDecoder   RapidJSON 수 변환   std::from_chars
// 1e-324      거부                NaN  ← 버그          out_of_range  ✅
// 1e-400      거부                0.0                 out_of_range  ✅
// 1e309       거부                거부                out_of_range  ✅
// 4.9e-324    수락 (준정규)        수락                ok            ✅
// 1e-323      수락 (준정규)        수락                ok            ✅
// ```
//
// `from_chars` 는 **모든 경계에서 Swift 와 일치했다.** 그리고 로케일에
// 의존하지 않는다 — `strtod` 는 `LC_NUMERIC` 에 따라 소수점이 달라진다.
//
// ### 그래도 남는 차이 하나 — `0e999`
//
// RapidJSON 은 **수를 문자열로 넘기는 모드에서도 지수 크기를 검사한다.**
// 가수가 0 이어도 그렇다. 그래서 `0e999` 는 토큰화에서 거부된다.
//
// ```text
//              Swift        여기
// 0e999        0.0 수락     거부 (MalformedJson)
// 0.0e400      0.0 수락     거부
// 0e-999       0.0 수락     0.0 수락        ← 음수 지수는 통과한다
// ```
//
// **고치지 않는다.** 가수가 0 인 채로 지수만 1e999 인 요청은 호스트가 보내지
// 않고, 갈리는 방향이 거부(안전한 쪽)다. 없애려면 수 토큰을 직접 훑어야 하는데
// 그러면 RapidJSON 을 쓰는 이유가 사라진다.
//
// `1e309` 는 양쪽 다 거부다 — 사유 코드만 `MalformedJson` 이고 결과는 같다.
//
// ### ⚠ 개발 환경과 Windows 가 **다른 버전을 쓴다** — 미확인 위험
//
// ```text
// macOS 개발   Homebrew rapidjson 1.1.0        (2016-08-25 릴리스. 유일한 태그다)
// Windows      vcpkg 포트 = master 스냅샷      (version-date 2025-02-26)
// ```
//
// **위 실측은 전부 1.1.0 에서 한 것이다.** vcpkg 는 1.1.0 을 주지 않는다 —
// 9년간 새 태그가 없어서 포트가 master 커밋을 고정하고 있다.
//
// 우리가 쓰는 것이 토큰화뿐이라 표면은 작다. 그래도 **`0e999` 거부는 바로 그
// 토큰화의 지수 검사에서 나온 것**이므로, master 에서 달라졌을 수 있다.
//
// 다행히 그 경우 갈리는 방향이 **macOS 와 같아지는 쪽**이라 나빠지지 않는다.
// 그래도 Windows 빌드가 서면 `testParseZeroMantissaHugeExponentDivergence` 가
// 여전히 맞는지 확인한다 — 틀리면 그 테스트를 고치고 위 표를 갱신한다.
//
// 반대로 **1.1.0 을 쓸 이유는 없다.** master 는 MSVC `/W4 /WX` + C++20 에서
// 1.1.0 이 내는 경고 넷(C4996/C5054/C5232/C4127)을 전부 고쳤다. 이 파일은
// 그 넷이 사는 `document.h` 를 애초에 끌어오지 않지만, 여유가 있는 편이 낫다.
//
// ## 실측으로 확인한 Swift 동작 (2026-08-05)
//
// ```text
// 알 수 없는 키           무시                     (중첩 객체 안에서도)
// 키 부재 / null          옵셔널이면 둘 다 nil      필수면 둘 다 실패
// 중복 키                 **첫 값**을 쓴다          ← 문서 §6.4 는 "마지막"이라 적었다
// Int 필드에 16.0 / 1.6e1 수락 → 16               정수값이면 표기는 무관
// Int 필드에 1200.5       **문서 전체가 무효 JSON** 타입 오류가 아니다
// Bool 필드에 null        typeMismatch             (String/Int 은 valueNotFound)
// 문자열 안 생 제어문자    거부                     탭·개행 모두
// 잘못된 UTF-8 바이트      **수락**                 거부하지 않는다
// UTF-8 BOM               수락
// 뒤에 붙은 쓰레기         거부                     `{...}x`, 객체 2개, 주석
// 중첩 깊이               512 근처에서 거부
// ```
//
// ## 상한을 갈아 끼울 수 있게 한 이유
//
// §6.3 이 요구하는 방어(4 MiB, 깊이 32, 4096 항목)와 중복 키 거부는
// **macOS 보다 엄격하다.** 고정하면 그 구간에서 파리티가 불가능해진다 —
// `wire/request` 의 `PathPolicy` 와 같은 문제이고 같은 해법을 쓴다.
//
// ```text
// ParseLimits::product()          제품 정책. 단위 테스트가 §6.3 을 고정한다
// ParseLimits::swiftEquivalent()  파리티 전용. macOS 와 같은 판정
// ```
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

#include "wire/request.h"

namespace negaflow::wire {

/// 같은 키가 한 객체에 두 번 나올 때.
enum class DuplicateKeyPolicy {
    /// 거부한다. **제품 정책이다** — 공격 표면을 줄인다(§6.4).
    Reject,
    /// 첫 값을 쓴다. macOS 동작(실측). **파리티 전용.**
    KeepFirst,
};

/// 파싱 상한. 요청은 신뢰할 수 없는 입력이다(§6.3).
struct ParseLimits {
    std::size_t maxDocumentBytes = 4u * 1024u * 1024u;   ///< 4 MiB
    int maxDepth = 32;                                    ///< 최상위 객체가 1
    std::size_t maxStringBytes = 2u * 1024u * 1024u;      ///< capabilityToken 여유
    std::size_t maxContainerItems = 4096;                 ///< 배열/객체 항목 수
    DuplicateKeyPolicy duplicateKeys = DuplicateKeyPolicy::Reject;

    /// 제품 정책. 위 기본값 그대로다.
    [[nodiscard]] static ParseLimits product() noexcept { return ParseLimits{}; }

    /// macOS `JSONDecoder` 와 같은 판정을 하는 설정. **파리티 전용이다.**
    ///
    /// 깊이 512 는 실측값이다(`JSONSerialization` 이 512 에서 거부한다).
    /// 나머지 셋은 macOS 에 대응하는 상한이 없어 사실상 무제한으로 둔다.
    [[nodiscard]] static ParseLimits swiftEquivalent() noexcept;
};

/// 실패 사유. **wire 로 나가지 않는다** — 단위 테스트와 로그 전용이다.
enum class ParseError {
    None,
    DocumentTooLarge,   ///< maxDocumentBytes 초과
    MalformedJson,      ///< 토큰화 실패. 문법·이스케이프·뒤에 붙은 쓰레기
    DepthExceeded,
    StringTooLong,
    TooManyItems,
    DuplicateKey,
    NotAnObject,        ///< 최상위가 객체가 아니다
    MissingKey,         ///< 필수 키 부재
    NullForRequired,    ///< 필수 키가 null
    TypeMismatch,
    NumberNotIntegral,  ///< Int 필드에 1200.5
    NumberOutOfRange,   ///< Int64 범위 밖, 또는 double 오버/언더플로
    IntegerTooWide,     ///< int32 를 넘는다. **macOS 는 여기서 갈린다** — 아래
    InvalidUuid,
};

/// 전체 디코딩이 실패했을 때 `requestID` 만이라도 건지는 봉투.
///
/// 이식 원본: `main.swift` 의 `private struct ScanRequestEnvelope`.
/// 호출자는 `protocolVersion == 2 && requestID` 일 때만 오류 이벤트를
/// wire 로 내보내고, 아니면 stderr 로 적는다 — macOS 가 그렇게 한다.
///
/// 두 필드 모두 옵셔널이라 부재/`null` 이 같다. 다만 `requestID` 가
/// **있는데 UUID 가 아니면 봉투 자체가 실패한다**(Swift `UUID?` 의 동작).
struct ScanRequestEnvelope {
    std::optional<std::int64_t> protocolVersion;
    /// 요청 문자열 그대로다. 재직렬화하지 않는다(D-12, wire-contract §5.4).
    std::optional<std::string> requestID;
};

/// 엄격한 8-4-4-4-12 16진 형태인가. 대소문자는 무시한다.
///
/// 중괄호(`{...}`), 하이픈 없는 형태, `urn:uuid:` 접두, 앞뒤 공백을
/// 전부 거부한다 — 실측한 Swift `UUID(from:)` 과 같다(§7).
[[nodiscard]] bool isValidRequestUUID(std::string_view s) noexcept;

/// 요청 JSON → `ScanRequestV2`. 실패하면 nullopt.
///
/// **`error` 는 진단용이다.** 호출자는 이것으로 wire 메시지를 만들지 않는다.
///
/// ### macOS 와 갈리는 지점 하나 — `IntegerTooWide`
///
/// Swift `Int` 는 64비트지만 `ScanRequestV2` 의 정수 필드는 `int` 다.
/// 그래서 `resolutionDPI: 2147483648` 은 macOS 에서 통과하고 여기서 거부된다.
/// 이것은 **의도한 차이이며 파리티 corpus 에 넣지 않는다**(단위 테스트가 고정한다).
///
/// 폭을 넓히는 대신 거부를 고른 이유: `ScanOptions` 까지 64비트로 바꾸면
/// `sane/media`·`sane/validate`·`sane/args` 가 전부 흔들리는데, 그것들은
/// 이미 파리티로 검증된 코드다. 입구에서 거부하는 편이 표면이 작다.
/// macOS 도 그런 값을 결국 실패시킨다 — `scanimage` 가 거부한다. 시점만 다르다.
[[nodiscard]] std::optional<ScanRequestV2> parseScanRequest(std::string_view json,
                                                            const ParseLimits& limits,
                                                            ParseError* error = nullptr);

/// 요청 JSON → 봉투. 실패하면 nullopt.
[[nodiscard]] std::optional<ScanRequestEnvelope> parseScanRequestEnvelope(
    std::string_view json, const ParseLimits& limits, ParseError* error = nullptr);

}  // namespace negaflow::wire
