import Foundation
import CoreGraphics
import CoreImage
import ImageIO

extension SANEBackend {
    /// scanimage -A 출력을 ScannerCapabilities로 변환한다.
    /// 형식 예: `--resolution 7200|3600|2400|1200|600dpi [600]`
    ///
    /// IR·소스는 모델명이 아니라 실제 옵션에서 감지한다(백엔드/기기/버전마다 다름).
    ///   • genesys "i" 필름스캐너: 일반 transparency 모드 + infrared 모드/소스를 노출한다.
    ///   • epson2 플랫베드: --source Flatbed|Transparency Unit(TPU), --film-type. IR은 미노출.
    static func parseCapabilities(_ dump: String) -> ScannerCapabilities {
        var resolutions: [Resolution] = []
        var bitDepths: [BitDepth] = []
        var supportsHardwareExposure = false

        let sources = parseSources(dump)             // --source 열거값(원문)
        let modeValues = parseModeValues(dump)        // --mode 열거값(소문자)

        for raw in dump.split(separator: "\n") {
            let line = String(raw)
            // --depth 16 [16]
            if let r = captureAfter(line, option: "--depth") {
                for tok in r.split(whereSeparator: { $0 == " " || $0 == "|" }) {
                    if let v = Int(tok), let d = BitDepth(rawValue: v) { bitDepths.append(d) }
                }
            }
            // --resolution 7200|3600|2400|1200|600dpi [600]
            if let r = captureAfter(line, option: "--resolution") {
                for tok in r.split(whereSeparator: { $0 == "|" || $0 == " " }) {
                    let cleaned = tok.replacingOccurrences(of: "dpi", with: "")
                    if let v = Int(cleaned) { resolutions.append(Resolution(v)) }
                }
            }
            if line.contains("--scan-exposure-time") { supportsHardwareExposure = true }
        }

        var modes: [ColorMode] = []
        if modeValues.contains(where: { $0.contains("color") }) { modes.append(.color) }
        if modeValues.contains(where: { $0.contains("gray") || $0.contains("grey") }) { modes.append(.gray) }
        if modeValues.contains(where: { $0.contains("lineart") }) { modes.append(.lineart) }
        if modeValues.contains(where: { $0.contains("infrared") }) { modes.append(.infrared) }

        let supportsTransparency = sources.contains { isTransparencySource($0) }
        // IR: infrared 소스(예: "Transparency Adapter Infrared") 또는 infrared 모드가 노출될 때만.
        let infraredViaSource = sources.contains { isInfraredValue($0) }
        let infraredViaMode = modeValues.contains { $0.contains("infrared") }
        let supportsInfrared = infraredViaSource || infraredViaMode

        // 디폴트 보정 (비어 있으면 genesys 8200i 검증값)
        if resolutions.isEmpty { resolutions = [.r900, .r1800, .r3600, .r7200] }
        if modes.isEmpty { modes = [.color, .gray] }
        if bitDepths.isEmpty { bitDepths = [.eight, .sixteen] }

        return ScannerCapabilities(
            supportedResolutions: resolutions.sorted(),
            supportedModes: modes,
            supportedBitDepths: bitDepths,
            supportsPreview: true,
            supportsTransparency: supportsTransparency,
            supportsInfrared: supportsInfrared,
            supportsMultiExposure: supportsHardwareExposure,
            supportsScanArea: true,
            supportsLampWarmupStatus: true,
            outputFormats: ["tiff", "pnm"]
        )
    }

    // MARK: 옵션 열거 파싱

    /// `--source` 열거값을 반환한다. 예: "Flatbed|Transparency Unit [Flatbed]" → ["Flatbed","Transparency Unit"].
    static func parseSources(_ dump: String) -> [String] {
        for raw in dump.split(separator: "\n") {
            let line = String(raw)
            if let after = captureAfter(line, option: "--source") { return splitEnumValues(after) }
        }
        return []
    }

    /// `--mode` 열거값(소문자)을 반환한다.
    static func parseModeValues(_ dump: String) -> [String] {
        for raw in dump.split(separator: "\n") {
            let line = String(raw)
            if let after = captureAfter(line, option: "--mode") {
                return splitEnumValues(after).map { $0.lowercased() }
            }
        }
        return []
    }

    /// "A|B|C [default]" 형태에서 `[기본값]`을 떼고 `|`로 나눠 열거값 배열을 만든다.
    static func splitEnumValues(_ s: String) -> [String] {
        var v = s
        if let bracket = v.firstIndex(of: "[") { v = String(v[..<bracket]) }
        return v.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// 투과/필름 소스인지(Transparency Adapter/TPA, Transparency Unit/TPU, Film ...).
    static func isTransparencySource(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("transparency") || l.contains("tpa") || l.contains("tpu") || l.contains("film")
    }

    /// infrared 소스/모드 값인지.
    static func isInfraredValue(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("infrared") || l == "ir"
    }

    private static func captureAfter(_ line: String, option: String) -> String? {
        guard let r = line.range(of: option) else { return nil }
        let after = line[r.upperBound...]
        return after.trimmingCharacters(in: .whitespaces)
    }
}
