import Foundation

// MARK: - Vendored scanner model types
//
// 이 플러그인은 negaflow 저장소에 의존하지 않는 독립 프로그램이다. SANE 백엔드 코드가 쓰는
// 최소 모델 타입을 여기에 자체적으로 담는다(원래 negaflow ScannerKit/Chromabase 정의를 미러링).
// 값들은 SANE 스캐닝에 필요한 만큼만 포함한다.

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
    public var widthMM: Double
    public var heightMM: Double
    public init(widthMM: Double = 36.0, heightMM: Double = 24.0) {
        self.widthMM = widthMM; self.heightMM = heightMM
    }
    public static let fullFrame35mm = ScanArea()
}

public enum ScanAreaUnit: String, Codable, Sendable {
    case millimeter
    case inch
    case pixel
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

public struct ScannerCapabilities: Codable, Sendable, Equatable {
    public var supportedResolutions: [Resolution]
    public var supportedModes: [ColorMode]
    public var supportedBitDepths: [BitDepth]
    public var supportsPreview: Bool
    public var supportsTransparency: Bool
    public var supportsInfrared: Bool
    public var supportsMultiExposure: Bool
    public var supportsScanArea: Bool
    public var supportsLampWarmupStatus: Bool
    public var maxScanArea: ScanArea
    public var minScanArea: ScanArea
    public var scanAreaUnit: ScanAreaUnit
    public var outputFormats: [String]
    public var estimatedScanSpeeds: [Int: Double]

    public init(
        supportedResolutions: [Resolution] = [.r900, .r1800, .r3600, .r7200],
        supportedModes: [ColorMode] = [.color, .gray, .infrared],
        supportedBitDepths: [BitDepth] = [.eight, .sixteen],
        supportsPreview: Bool = true,
        supportsTransparency: Bool = true,
        supportsInfrared: Bool = true,
        supportsMultiExposure: Bool = false,
        supportsScanArea: Bool = true,
        supportsLampWarmupStatus: Bool = true,
        maxScanArea: ScanArea = .fullFrame35mm,
        minScanArea: ScanArea = ScanArea(widthMM: 4, heightMM: 4),
        scanAreaUnit: ScanAreaUnit = .millimeter,
        outputFormats: [String] = ["tiff", "jpeg"],
        estimatedScanSpeeds: [Int: Double] = [900: 4, 1800: 9, 3600: 28, 7200: 95]
    ) {
        self.supportedResolutions = supportedResolutions
        self.supportedModes = supportedModes
        self.supportedBitDepths = supportedBitDepths
        self.supportsPreview = supportsPreview
        self.supportsTransparency = supportsTransparency
        self.supportsInfrared = supportsInfrared
        self.supportsMultiExposure = supportsMultiExposure
        self.supportsScanArea = supportsScanArea
        self.supportsLampWarmupStatus = supportsLampWarmupStatus
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
    public var outputRawTIFF: Bool
    public var temporaryOutputURL: URL?

    public init(
        scannerID: String, resolution: Resolution = .r3600, bitDepth: BitDepth = .sixteen,
        colorMode: ColorMode = .color, filmType: FilmType = .colorNegative,
        scanArea: ScanArea = .fullFrame35mm, infraredEnabled: Bool = false,
        multiExposureEnabled: Bool = false, hardwareExposureTime: Int? = nil,
        outputRawTIFF: Bool = true, temporaryOutputURL: URL? = nil
    ) {
        self.scannerID = scannerID; self.resolution = resolution; self.bitDepth = bitDepth
        self.colorMode = colorMode; self.filmType = filmType; self.scanArea = scanArea
        self.infraredEnabled = infraredEnabled; self.multiExposureEnabled = multiExposureEnabled
        self.hardwareExposureTime = hardwareExposureTime; self.outputRawTIFF = outputRawTIFF
        self.temporaryOutputURL = temporaryOutputURL
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

    public init(
        rawFileURL: URL, previewImage: Data? = nil, width: Int, height: Int,
        resolution: Resolution, bitDepth: BitDepth, colorSpace: String = "Generic RGB",
        hasInfraredChannel: Bool = false, infraredFileURL: URL? = nil, scanDuration: Double = 0,
        backendUsed: BackendType = .sane, warnings: [String] = []
    ) {
        self.rawFileURL = rawFileURL; self.previewImage = previewImage
        self.width = width; self.height = height; self.resolution = resolution
        self.bitDepth = bitDepth; self.colorSpace = colorSpace
        self.hasInfraredChannel = hasInfraredChannel; self.infraredFileURL = infraredFileURL
        self.scanDuration = scanDuration; self.backendUsed = backendUsed; self.warnings = warnings
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
