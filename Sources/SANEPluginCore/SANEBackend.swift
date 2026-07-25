import Foundation

public struct SANECapabilityReport: Sendable, Equatable {
    public var capabilities: ScannerCapabilities
    public var capabilityToken: String

    public init(capabilities: ScannerCapabilities, capabilityToken: String) {
        self.capabilities = capabilities
        self.capabilityToken = capabilityToken
    }
}

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
    nonisolated(unsafe) var cachedAddressTarget: String?
    nonisolated(unsafe) var cachedAddressIdentity: DeviceIdentity?
    nonisolated(unsafe) var cachedAddressAt: Date = .distantPast
    /// devname → -L 장치 타입 문자열("film scanner" 등). capability 판정 힌트.
    nonisolated(unsafe) var cachedDeviceTypes: [String: String] = [:]
    /// devname → 장치가 보고한 제조사·모델. 같은 backend의 다른 모델로 잘못 재연결하지 않는다.
    nonisolated(unsafe) var cachedDeviceIdentities: [String: DeviceIdentity] = [:]
    let addressCacheTTL: TimeInterval = 5.0

    var lastStderr: String = ""
    let processLock = NSLock()
    nonisolated(unsafe) var currentProcess: Process?
    nonisolated(unsafe) var activeScanSessionID: UUID?
    nonisolated(unsafe) var scanCancellationRequested = false
    nonisolated(unsafe) var stderrBuffer = ""
    nonisolated(unsafe) var scanProgressBuffer = ""

    /// nil이면 PATH에서 `scanimage`를 찾는다.
    public init(scanimagePath: String? = nil) {
        self.scanimage = scanimagePath
            ?? ProcessInfo.processInfo.environment["NEGAFLOW_SCANIMAGE_PATH"]
            ?? Self.findScanimage()
    }

    public func getLastError() -> ScannerError? { lastError }

    /// IR(적외선) 채널 획득 방식. 백엔드/기기마다 다르다 — 전부 -A 덤프에서 감지한다.
    ///   • genesys  "i" 필름스캐너: 별도 IR 소스("Transparency Adapter Infrared")로 두 번째 패스.
    ///   • epson2 커스텀 빌드: --mode Infrared 로 두 번째 패스(stock 빌드는 미노출).
    ///   • pieusb(Reflecta/PIE): --clean-image=yes — 백엔드가 IR로 먼지 제거한 RGB를 반환(단일 패스).
    /// coolscan3의 --infrared는 SANE_FRAME_RGBI 한 프레임이며 stock scanimage가 별도 IR TIFF로
    /// 직렬화하지 못하므로, scanimage 기반 플러그인에서는 별도 IR 채널 기능으로 보고하지 않는다.
    enum IRStrategy: Sendable, Equatable {
        case none
        case separateSource(String)
        case separateMode(String)
        case cleanImage(optionName: String)
    }

    public struct DeviceIdentity: Sendable, Equatable, Codable {
        public var vendor: String
        public var model: String

        public init(vendor: String, model: String) {
            self.vendor = vendor
            self.model = model
        }
    }

    /// 장치가 실제 노출하는 옵션으로 해석한 "이 장치와 대화하는 법" 요약.
    /// 값이 nil이면 해당 플래그를 아예 전달하지 않는다(장치 기본값 사용) — 옵션이 없는
    /// 백엔드(coolscan3의 --mode 등)에 플래그를 넘기면 scanimage가 실패하기 때문.
    struct MediaSelection: Sendable, Equatable {
        var source: String?
        var mode: String?
        var filmType: String?
        var depthArgument: Int?
        var resolvedDPI: Int?
        var originXMM: Double? = nil
        var originYMM: Double? = nil
        var widthMM: Double?          // mm 단위 장치에서만 -x/-y 를 전달(pel 단위 장치는 생략=전체영역)
        var heightMM: Double?
        var hasPreviewOption: Bool = false
        var hasBrightnessOption: Bool = false
        var hasContrastOption: Bool = false
        var hasScanExposureOption: Bool = false
        var hasModeOption: Bool = false
        var hasDepthOption: Bool = false
        var hasFilmTypeOption: Bool = false
        var brightnessRange: ScannerOptionRange?
        var contrastRange: ScannerOptionRange?
        var hardwareExposureRange: ScannerOptionRange?
        var resolutionRange: ScannerOptionRange?
        var scanLeftRange: ScannerOptionRange? = nil
        var scanTopRange: ScannerOptionRange? = nil
        var scanWidthRange: ScannerOptionRange?
        var scanHeightRange: ScannerOptionRange?
        var irStrategy: IRStrategy = .none
        var irPassMode: String?       // 별도 IR 패스에서 쓸 --mode 값(Gray 우선)
        var acquisitionDevice: String?
        var expectedDeviceIdentity: DeviceIdentity?
        var dedicatedFilmDevice = false
        var originXPixels: Int?
        var originYPixels: Int?
        var widthPixels: Int?
        var heightPixels: Int?
        var rightPixels: Int?
        var bottomPixels: Int?
        var usesCornerPixelGeometry = false

        var usesInfrared: Bool { irStrategy != .none }
    }
}
