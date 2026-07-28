import Foundation

// MARK: - SaneOptionDump (scanimage -A 출력 파서)
//
// 백엔드마다 옵션 이름/단위/형식이 다르다(genesys=mm, coolscan3=pel, epson2=소스 열거,
// pieusb=bool clean-image …). 모델명 하드코딩 없이 실제 -A 덤프에서 장치가 노출하는
// 옵션만으로 능력과 인자를 결정하기 위한 공용 파서.
struct SaneOptionDump: Sendable {
    /// 옵션 이름(선행 대시 제거, bool 접미사 `[=(yes|no)]` 제거) → 옵션 토큰 뒤 원문.
    private let values: [String: String]
    let optionNames: Set<String>
    let inactiveOptionNames: Set<String>
    let isEmpty: Bool

    init(_ dump: String) {
        var parsed: [String: String] = [:]
        var inactive: Set<String> = []
        for raw in dump.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("-") else { continue }
            let token = line.prefix(while: { !$0.isWhitespace })
            var name = String(token.drop(while: { $0 == "-" }))
            if let bracket = name.firstIndex(of: "[") { name = String(name[..<bracket]) }
            guard !name.isEmpty else { continue }
            let rest = line.dropFirst(token.count).trimmingCharacters(in: .whitespaces)
            if parsed[name] == nil { parsed[name] = rest }
            if rest.lowercased().contains("[inactive]") { inactive.insert(name) }
        }
        values = parsed
        optionNames = Set(parsed.keys)
        inactiveOptionNames = inactive
        isEmpty = parsed.isEmpty
    }

    func hasOption(_ name: String) -> Bool { optionNames.contains(name) }

    func isActive(_ name: String) -> Bool {
        optionNames.contains(name) && !inactiveOptionNames.contains(name)
    }

    func value(_ name: String) -> String? { values[name] }

    /// "A|B|C [default]" → ["A","B","C"] (원문 대소문자 보존).
    func enumValues(_ name: String) -> [String] {
        guard isActive(name), let v = values[name] else { return [] }
        return Self.parseEnumValues(v)
    }

    /// 활성 여부와 무관하게 열거 제약 목록만 읽는다. 앞선 옵션 적용으로 활성화될 옵션을
    /// 같은 scanimage 호출의 뒤쪽에 배치할 때만 사용한다.
    func constraintEnumValues(_ name: String) -> [String] {
        guard let value = values[name] else { return [] }
        return Self.parseEnumValues(value)
    }

    private static func parseEnumValues(_ raw: String) -> [String] {
        var v = raw
        if let bracket = v.firstIndex(of: "[") { v = String(v[..<bracket]) }
        return v.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// enum 제약 뒤 대괄호에 표시된 현재 선택값. `[inactive]` 같은 상태 표시는 제외한다.
    func selectedEnumValue(_ name: String) -> String? {
        guard let raw = values[name] else { return nil }
        return enumValues(name).first { candidate in
            raw.range(
                of: "[\(candidate)]",
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }

    /// "8|14 [8]" → [8, 14]. 접미사(dpi 등) 제거. 비활성 옵션은 값이 없다.
    func intTokens(_ name: String) -> [Int] {
        guard isActive(name) else { return [] }
        return constraintIntTokens(name)
    }

    /// 활성 여부와 무관하게 제약 목록만 읽는다. scanimage는 비활성 옵션도 목록을 그대로
    /// 출력하므로("--depth 8 [inactive]"), 값이 하나뿐인 고정 옵션을 식별할 때만 쓴다.
    /// 이 값을 그대로 장치에 전송해서는 안 된다.
    func constraintIntTokens(_ name: String) -> [Int] {
        guard var v = values[name] else { return [] }
        if let bracket = v.firstIndex(of: "[") { v = String(v[..<bracket]) }
        return v.split(whereSeparator: { $0 == "|" || $0 == " " }).compactMap { tok in
            Int(tok.trimmingCharacters(in: CharacterSet.decimalDigits.inverted))
        }
    }

    /// "-100..100 (in steps of 1) [0]" → 범위(+step).
    func numericRange(_ name: String) -> ScannerOptionRange? {
        guard isActive(name),
              let v = values[name],
              let bounds = Self.firstNumericRange(in: v) else { return nil }
        return ScannerOptionRange(minimum: bounds.0, maximum: bounds.1, step: Self.firstStepValue(in: v))
    }

    /// 범위 옵션의 단위 접미사("mm"/"pel"). "0..36.33mm [36.33]" → "mm".
    func rangeUnit(_ name: String) -> String? {
        guard isActive(name),
              let v = values[name],
              let match = Self.firstRegexMatch(#"-?\d+(?:\.\d+)?\.\.-?\d+(?:\.\d+)?\s*(mm|pel)"#, in: v),
              match.count == 2 else { return nil }
        return match[1]
    }

    // MARK: 해상도

    enum ResolutionSpec: Equatable, Sendable {
        case list([Int])
        case range(min: Int, max: Int)
        case none
    }

    /// `--resolution 7200|3600|600dpi [600]` → list, `50..6400dpi …` → range.
    var resolutionSpec: ResolutionSpec {
        guard isActive("resolution"), let v = values["resolution"] else { return .none }
        if v.contains("..") {
            guard let bounds = Self.firstNumericRange(in: v) else { return .none }
            return .range(min: Int(bounds.0), max: Int(bounds.1))
        }
        var body = v
        if let bracket = body.firstIndex(of: "[") { body = String(body[..<bracket]) }
        let dpis = body.split(whereSeparator: { $0 == "|" || $0 == " " }).compactMap { tok -> Int? in
            Int(tok.replacingOccurrences(of: "dpi", with: ""))
        }
        return dpis.isEmpty ? .none : .list(dpis.sorted())
    }

    /// 요청 dpi를 장치가 받는 값으로 스냅. 리스트=가장 가까운 값(동률이면 큰 쪽), 범위=클램프.
    static func snapResolution(_ requested: Int, to spec: ResolutionSpec) -> Int? {
        switch spec {
        case .none:
            return nil
        case .range(let min, let max):
            return Swift.min(Swift.max(requested, min), max)
        case .list(let dpis):
            guard !dpis.isEmpty else { return nil }
            return dpis.min {
                let da = abs($0 - requested), db = abs($1 - requested)
                return da != db ? da < db : $0 > $1
            }
        }
    }

    // MARK: regex helpers

    private static func firstNumericRange(in text: String) -> (Double, Double)? {
        guard let match = firstRegexMatch(#"(-?\d+(?:\.\d+)?)\.\.(-?\d+(?:\.\d+)?)"#, in: text),
              match.count == 3,
              let minimum = Double(match[1]),
              let maximum = Double(match[2]) else { return nil }
        return (minimum, maximum)
    }

    private static func firstStepValue(in text: String) -> Double? {
        guard let match = firstRegexMatch(#"steps? of (-?\d+(?:\.\d+)?)"#, in: text),
              match.count == 2 else { return nil }
        return Double(match[1])
    }

    private static func firstRegexMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }
}
