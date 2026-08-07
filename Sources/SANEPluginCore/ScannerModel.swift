import Foundation

// MARK: - Plugin-local scanner protocol model types
//
// 이 플러그인은 negaflow 저장소에 의존하지 않는 독립 프로그램이다. SANE 백엔드 코드가 쓰는
// 최소 JSON 계약 타입을 여기에 둔다. 같은 저자가 작성한 negaflow ScannerKit 계약과 호환되는
// 필드만 유지하며, 이 파일은 플러그인의 GPL-2.0-or-later 배포물에 포함한다.

public enum FilmType: String, Codable, Sendable, CaseIterable {
    case colorNegative
    case colorPositive
    case bwNegative
    case bwPositive

    public var requiresInversion: Bool {
        switch self {
        case .colorNegative, .bwNegative: return true
        case .colorPositive, .bwPositive: return false
        }
    }
}

public enum BackendType: String, Codable, Sendable {
    case imageCaptureCore
    case sane
    case plugin
    case mock
}

public enum ConnectionType: String, Codable, Sendable {
    case usb
    case network
    case scsi
    case fireWire
    case internalBus
}

public enum VerifiedStatus: String, Codable, Sendable {
    case verified
    case compatibleTarget
    case experimental
}

public enum ColorMode: String, Codable, Sendable, CaseIterable {
    case color
    case gray
    case lineart
    case infrared
}

public enum BitDepth: Int, Codable, Sendable, CaseIterable {
    case eight = 8
    case sixteen = 16
}

public struct Resolution: Codable, Sendable, Equatable, Comparable, Hashable {
    public let dpi: Int
    public init(_ dpi: Int) { self.dpi = dpi }
    public static let preview = Resolution(0)
    public static func < (lhs: Resolution, rhs: Resolution) -> Bool { lhs.dpi < rhs.dpi }
    public var displayName: String { dpi == 0 ? "Preview" : "\(dpi)" }
}

public extension Resolution {
    static let r900  = Resolution(900)
    static let r1800 = Resolution(1800)
    static let r3600 = Resolution(3600)
    static let r7200 = Resolution(7200)
}

public struct ScanArea: Codable, Sendable, Equatable {
    public var originXMM: Double
    public var originYMM: Double
    public var widthMM: Double
    public var heightMM: Double
    public init(
        originXMM: Double = 0,
        originYMM: Double = 0,
        widthMM: Double = 36.0,
        heightMM: Double = 24.0
    ) {
        self.originXMM = originXMM
        self.originYMM = originYMM
        self.widthMM = widthMM
        self.heightMM = heightMM
    }
    public static let fullFrame35mm = ScanArea()

    private enum CodingKeys: String, CodingKey {
        case originXMM
        case originYMM
        case widthMM
        case heightMM
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originXMM = try container.decodeIfPresent(Double.self, forKey: .originXMM) ?? 0
        originYMM = try container.decodeIfPresent(Double.self, forKey: .originYMM) ?? 0
        widthMM = try container.decode(Double.self, forKey: .widthMM)
        heightMM = try container.decode(Double.self, forKey: .heightMM)
    }
}

public enum ScanAreaUnit: String, Codable, Sendable {
    case millimeter
    case inch
    case pixel
}

public struct ScannerOptionRange: Codable, Sendable, Equatable {
    public var minimum: Double
    public var maximum: Double
    public var step: Double?

    public init(minimum: Double, maximum: Double, step: Double? = nil) {
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
    }

    public func clamped(_ value: Double) -> Double {
        min(max(value, minimum), maximum)
    }

    public func containsExactly(_ value: Double) -> Bool {
        guard value.isFinite, value >= minimum, value <= maximum else { return false }
        guard let step, step > 0 else { return true }
        let offset = (value - minimum) / step
        return abs(offset - offset.rounded()) <= 1e-7
    }
}

public struct ScannerDescriptor: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var displayName: String
    public var vendor: String
    public var model: String
    public var backendType: BackendType
    public var connectionType: ConnectionType
    public var usbVendorID: String?
    public var usbProductID: String?
    public var serialNumber: String?
    public var verifiedStatus: VerifiedStatus
    public var firmwareVersion: String?
    public var driverVersion: String?

    public init(
        id: String, displayName: String, vendor: String, model: String,
        backendType: BackendType, connectionType: ConnectionType = .usb,
        usbVendorID: String? = nil, usbProductID: String? = nil, serialNumber: String? = nil,
        verifiedStatus: VerifiedStatus = .compatibleTarget,
        firmwareVersion: String? = nil, driverVersion: String? = nil
    ) {
        self.id = id; self.displayName = displayName; self.vendor = vendor; self.model = model
        self.backendType = backendType; self.connectionType = connectionType
        self.usbVendorID = usbVendorID; self.usbProductID = usbProductID; self.serialNumber = serialNumber
        self.verifiedStatus = verifiedStatus; self.firmwareVersion = firmwareVersion; self.driverVersion = driverVersion
    }
}

/// 초점 지정. 장치가 focus/autofocus 옵션을 실제로 노출할 때만 의미가 있다(epson2 평판 등).
/// 두 방식은 상호배타다 — 오토포커스를 켜면 수동 위치는 무시되므로 타입으로 갈라 둔다.
public enum ScanFocus: Codable, Sendable, Equatable {
    /// 스캔 직전 장치 오토포커스. GT-X900 실측으로 컷당 약 50초가 더 든다.
    case auto
    /// 장치 focus 위치를 직접 지정. 한 번 찾아둔 값을 배치 내내 재사용하는 경로다.
    case manual(Int)
}

public struct ScannerCapabilities: Codable, Sendable, Equatable {
    public var supportedResolutions: [Resolution]
    public var supportedModes: [ColorMode]
    public var supportedBitDepths: [BitDepth]
    public var sourceModes: [String]?
    public var transparencyModes: [String]?
    public var supportsPreview: Bool
    public var supportsTransparency: Bool
    public var supportsInfrared: Bool
    public var supportsMultiExposure: Bool
    public var supportsScanArea: Bool
    public var supportsPositionedScanArea: Bool
    public var supportsLampWarmupStatus: Bool
    public var brightnessRange: ScannerOptionRange?
    public var contrastRange: ScannerOptionRange?
    public var hardwareExposureRange: ScannerOptionRange?
    /// 수동 초점 위치 범위. nil이면 이 장치/옵션 조합에서 수동 초점을 쓸 수 없다.
    public var focusRange: ScannerOptionRange?
    public var supportsAutofocus: Bool
    public var scanOriginXRange: ScannerOptionRange?
    public var scanOriginYRange: ScannerOptionRange?
    public var scanWidthRange: ScannerOptionRange?
    public var scanHeightRange: ScannerOptionRange?
    public var disabledReasons: [String: String]?
    public var maxScanArea: ScanArea
    public var minScanArea: ScanArea
    public var scanAreaUnit: ScanAreaUnit
    public var outputFormats: [String]
    public var estimatedScanSpeeds: [Int: Double]

    public init(
        supportedResolutions: [Resolution] = [],
        supportedModes: [ColorMode] = [],
        supportedBitDepths: [BitDepth] = [],
        sourceModes: [String] = [],
        transparencyModes: [String] = [],
        supportsPreview: Bool = false,
        supportsTransparency: Bool = false,
        supportsInfrared: Bool = false,
        supportsMultiExposure: Bool = false,
        supportsScanArea: Bool = false,
        supportsPositionedScanArea: Bool = false,
        supportsLampWarmupStatus: Bool = false,
        brightnessRange: ScannerOptionRange? = nil,
        contrastRange: ScannerOptionRange? = nil,
        hardwareExposureRange: ScannerOptionRange? = nil,
        focusRange: ScannerOptionRange? = nil,
        supportsAutofocus: Bool = false,
        scanOriginXRange: ScannerOptionRange? = nil,
        scanOriginYRange: ScannerOptionRange? = nil,
        scanWidthRange: ScannerOptionRange? = nil,
        scanHeightRange: ScannerOptionRange? = nil,
        disabledReasons: [String: String] = [:],
        maxScanArea: ScanArea = ScanArea(widthMM: 0, heightMM: 0),
        minScanArea: ScanArea = ScanArea(widthMM: 0, heightMM: 0),
        scanAreaUnit: ScanAreaUnit = .millimeter,
        outputFormats: [String] = [],
        estimatedScanSpeeds: [Int: Double] = [:]
    ) {
        self.supportedResolutions = supportedResolutions
        self.supportedModes = supportedModes
        self.supportedBitDepths = supportedBitDepths
        self.sourceModes = sourceModes
        self.transparencyModes = transparencyModes
        self.supportsPreview = supportsPreview
        self.supportsTransparency = supportsTransparency
        self.supportsInfrared = supportsInfrared
        self.supportsMultiExposure = supportsMultiExposure
        self.supportsScanArea = supportsScanArea
        self.supportsPositionedScanArea = supportsPositionedScanArea
        self.supportsLampWarmupStatus = supportsLampWarmupStatus
        self.brightnessRange = brightnessRange
        self.contrastRange = contrastRange
        self.hardwareExposureRange = hardwareExposureRange
        self.focusRange = focusRange
        self.supportsAutofocus = supportsAutofocus
        self.scanOriginXRange = scanOriginXRange
        self.scanOriginYRange = scanOriginYRange
        self.scanWidthRange = scanWidthRange
        self.scanHeightRange = scanHeightRange
        self.disabledReasons = disabledReasons
        self.maxScanArea = maxScanArea
        self.minScanArea = minScanArea
        self.scanAreaUnit = scanAreaUnit
        self.outputFormats = outputFormats
        self.estimatedScanSpeeds = estimatedScanSpeeds
    }
}

public struct ScanOptions: Codable, Sendable, Equatable {
    public var scannerID: String
    public var resolution: Resolution
    public var bitDepth: BitDepth
    public var colorMode: ColorMode
    public var filmType: FilmType
    public var scanArea: ScanArea
    public var infraredEnabled: Bool
    public var multiExposureEnabled: Bool
    public var hardwareExposureTime: Int?
    public var brightnessAdjustment: Double?
    public var contrastAdjustment: Double?
    /// nil이면 초점을 지정하지 않는다 — 장치 기본값 그대로다(기존 동작).
    public var focus: ScanFocus?
    public var outputRawTIFF: Bool
    public var temporaryOutputURL: URL?
    public var capabilityToken: String?

    public init(
        scannerID: String, resolution: Resolution = .r3600, bitDepth: BitDepth = .sixteen,
        colorMode: ColorMode = .color, filmType: FilmType = .colorNegative,
        scanArea: ScanArea = .fullFrame35mm, infraredEnabled: Bool = false,
        multiExposureEnabled: Bool = false, hardwareExposureTime: Int? = nil,
        brightnessAdjustment: Double? = nil, contrastAdjustment: Double? = nil,
        focus: ScanFocus? = nil,
        outputRawTIFF: Bool = true, temporaryOutputURL: URL? = nil,
        capabilityToken: String? = nil
    ) {
        self.scannerID = scannerID; self.resolution = resolution; self.bitDepth = bitDepth
        self.colorMode = colorMode; self.filmType = filmType; self.scanArea = scanArea
        self.infraredEnabled = infraredEnabled; self.multiExposureEnabled = multiExposureEnabled
        self.hardwareExposureTime = hardwareExposureTime; self.outputRawTIFF = outputRawTIFF
        self.brightnessAdjustment = brightnessAdjustment; self.contrastAdjustment = contrastAdjustment
        self.focus = focus
        self.temporaryOutputURL = temporaryOutputURL
        self.capabilityToken = capabilityToken
    }

    public static func preview(scannerID: String, filmType: FilmType = .colorNegative) -> ScanOptions {
        ScanOptions(scannerID: scannerID, resolution: .preview, bitDepth: .eight,
                    colorMode: .color, filmType: filmType, infraredEnabled: false, outputRawTIFF: false)
    }

    public static func strongDefault(scannerID: String) -> ScanOptions {
        ScanOptions(scannerID: scannerID)
    }
}

public struct ScanResult: Codable, Sendable, Equatable {
    public var rawFileURL: URL
    public var previewImage: Data?
    public var width: Int
    public var height: Int
    public var resolution: Resolution
    public var bitDepth: BitDepth
    public var colorSpace: String
    public var hasInfraredChannel: Bool
    public var infraredFileURL: URL?
    public var scanDuration: Double
    public var backendUsed: BackendType
    public var warnings: [String]
    /// 요청 복사가 아니라 실제로 scanimage에 보낸 스캔 영역. 백엔드 절삭을 피하려고
    /// 높이가 1mm 미만 정렬됐을 수 있으므로, 소비자는 이 값으로 결과를 검증해야 한다.
    public var appliedScanArea: ScanArea?

    public init(
        rawFileURL: URL, previewImage: Data? = nil, width: Int, height: Int,
        resolution: Resolution, bitDepth: BitDepth, colorSpace: String = "Generic RGB",
        hasInfraredChannel: Bool = false, infraredFileURL: URL? = nil, scanDuration: Double = 0,
        backendUsed: BackendType = .sane, warnings: [String] = [],
        appliedScanArea: ScanArea? = nil
    ) {
        self.rawFileURL = rawFileURL; self.previewImage = previewImage
        self.width = width; self.height = height; self.resolution = resolution
        self.bitDepth = bitDepth; self.colorSpace = colorSpace
        self.hasInfraredChannel = hasInfraredChannel; self.infraredFileURL = infraredFileURL
        self.scanDuration = scanDuration; self.backendUsed = backendUsed; self.warnings = warnings
        self.appliedScanArea = appliedScanArea
    }
}

public enum ScanPhase: String, Codable, Sendable {
    case idle, connecting, warmingLamp, ready, previewScanning, waitingForFilmHolder
    case scanningRGB, scanningIR, processingNegative, renderingLook, exporting
    case complete, scannerBusy, disconnected, error, backendFallbackActive
}

public struct ScanProgress: Sendable, Equatable {
    public var phase: ScanPhase
    public var fraction: Double?
    public var message: String
    public init(phase: ScanPhase, fraction: Double? = nil, message: String = "") {
        self.phase = phase; self.fraction = fraction; self.message = message
    }
}

public struct ScannerError: Error, LocalizedError, Sendable, Equatable {
    public let code: Code
    public let message: String
    public enum Code: String, Sendable {
        case notConnected, busy, unsupportedOption, driverConflict, ioFailure, cancelled, timeout, unknown
    }
    public init(_ code: Code, _ message: String = "") { self.code = code; self.message = message }
    public var errorDescription: String? { message.isEmpty ? code.rawValue : "\(code.rawValue): \(message)" }
}

public protocol ScannerBackend: AnyObject {
    var backendType: BackendType { get }
    func detectScanners() async throws -> [ScannerDescriptor]
    func getCapabilities(scannerID: String) async throws -> ScannerCapabilities
    func startPreviewScan(_ options: ScanOptions,
                          progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> ScanResult
    func startFullScan(_ options: ScanOptions,
                       progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> ScanResult
    func cancelScan() async
    func getLastError() -> ScannerError?
}
