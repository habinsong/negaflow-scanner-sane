import Foundation

// MARK: - SANEBackend

public final class SANEBackend: ScannerBackend, @unchecked Sendable {
    public let backendType: BackendType = .sane
    let scanimage: String
    var lastError: ScannerError?

    static let multiSamplePassCount = 3
    static let hardwareExposureTimes = [11_000, 14_000, 30_000]
    static var hardwareExposureSamplesPerStop: Int {
        let raw = ProcessInfo.processInfo.environment["NEGAFLOW_HWEXP_SAMPLES"] ?? ""
        let parsed = Int(raw) ?? 1
        return min(max(parsed, 1), 4)
    }

    static func hardwareExposurePlan(samplesPerStop: Int = hardwareExposureSamplesPerStop) -> [Int] {
        hardwareExposureTimes.flatMap { exposure in
            Array(repeating: exposure, count: min(max(samplesPerStop, 1), 4))
        }
    }

    nonisolated(unsafe) var cachedAddress: String?
    nonisolated(unsafe) var cachedAddressBackend: String?
    nonisolated(unsafe) var cachedAddressAt: Date = .distantPast
    let addressCacheTTL: TimeInterval = 5.0

    var lastStderr: String = ""
    nonisolated(unsafe) var currentProcess: Process?
    nonisolated(unsafe) var stderrBuffer = ""

    /// nil이면 PATH에서 `scanimage`를 찾는다.
    public init(scanimagePath: String? = nil) {
        self.scanimage = scanimagePath
            ?? ProcessInfo.processInfo.environment["NEGAFLOW_SCANIMAGE_PATH"]
            ?? Self.findScanimage()
    }

    public func getLastError() -> ScannerError? { lastError }

    struct MediaSelection: Sendable, Equatable {
        var source: String?
        var mode: String
        var filmType: String?
        var usesInfrared: Bool
    }
}
