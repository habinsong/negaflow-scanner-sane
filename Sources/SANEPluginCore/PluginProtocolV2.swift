import Foundation

/// negaflow scanner plugin protocol v2의 scan 요청.
/// v2는 요청을 임의로 보정하지 않으며, 적용할 수 없는 값은 scan 시작 전에 실패한다.
public struct PluginScanRequestV2: Codable, Sendable, Equatable {
    public var protocolVersion: Int
    public var requestID: UUID
    public var deviceID: String
    public var resolutionDPI: Int
    public var bitDepth: Int
    public var colorMode: String
    public var filmType: String
    public var preview: Bool
    public var multiExposure: Bool
    public var infrared: Bool
    public var brightnessAdjustment: Double?
    public var contrastAdjustment: Double?
    public var scanArea: ScanArea
    public var hardwareExposureTime: Int?
    public var outputRawTIFF: Bool
    public var capabilityToken: String?
    public var outputPath: String

    public func validatedOptions() throws -> ScanOptions {
        guard protocolVersion == 2 else {
            throw ScannerError(.unsupportedOption, "protocolVersion은 2여야 합니다.")
        }
        guard !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScannerError(.unsupportedOption, "deviceID가 비어 있습니다.")
        }
        guard let bitDepth = BitDepth(rawValue: bitDepth) else {
            throw ScannerError(.unsupportedOption, "지원하지 않는 bitDepth: \(self.bitDepth)")
        }
        guard let colorMode = ColorMode(rawValue: colorMode),
              colorMode == .color || colorMode == .gray else {
            throw ScannerError(.unsupportedOption, "지원하지 않는 colorMode: \(self.colorMode)")
        }
        guard let filmType = FilmType(rawValue: filmType) else {
            throw ScannerError(.unsupportedOption, "지원하지 않는 filmType: \(self.filmType)")
        }
        guard scanArea.originXMM.isFinite,
              scanArea.originYMM.isFinite,
              scanArea.widthMM.isFinite,
              scanArea.heightMM.isFinite,
              scanArea.originXMM >= 0,
              scanArea.originYMM >= 0,
              scanArea.widthMM > 0,
              scanArea.heightMM > 0 else {
            throw ScannerError(.unsupportedOption, "scanArea가 유효하지 않습니다.")
        }
        guard hardwareExposureTime.map({ $0 > 0 }) ?? true else {
            throw ScannerError(.unsupportedOption, "hardwareExposureTime이 유효하지 않습니다.")
        }
        guard brightnessAdjustment.map(\.isFinite) ?? true,
              contrastAdjustment.map(\.isFinite) ?? true else {
            throw ScannerError(.unsupportedOption, "brightness/contrast 값이 유효하지 않습니다.")
        }
        guard URL(fileURLWithPath: outputPath).path == outputPath,
              (outputPath as NSString).isAbsolutePath else {
            throw ScannerError(.unsupportedOption, "outputPath는 정규화된 절대 경로여야 합니다.")
        }
        guard capabilityToken.map({ $0.utf8.count <= 1_048_576 }) ?? true else {
            throw ScannerError(.unsupportedOption, "capabilityToken이 허용 크기를 초과했습니다.")
        }
        if preview {
            guard resolutionDPI == 0,
                  !infrared,
                  !multiExposure,
                  hardwareExposureTime == nil,
                  outputRawTIFF == false else {
                throw ScannerError(.unsupportedOption, "preview 요청 옵션 계약이 일치하지 않습니다.")
            }
        } else {
            guard resolutionDPI > 0 else {
                throw ScannerError(.unsupportedOption, "full scan resolutionDPI는 양수여야 합니다.")
            }
            guard outputRawTIFF else {
                throw ScannerError(.unsupportedOption, "full scan은 outputRawTIFF=true만 지원합니다.")
            }
            guard !(multiExposure && hardwareExposureTime != nil) else {
                throw ScannerError(
                    .unsupportedOption,
                    "multiExposure와 단일 hardwareExposureTime을 동시에 적용할 수 없습니다."
                )
            }
        }

        return ScanOptions(
            scannerID: deviceID,
            resolution: Resolution(resolutionDPI),
            bitDepth: bitDepth,
            colorMode: colorMode,
            filmType: filmType,
            scanArea: scanArea,
            infraredEnabled: infrared,
            multiExposureEnabled: multiExposure,
            hardwareExposureTime: hardwareExposureTime,
            brightnessAdjustment: brightnessAdjustment,
            contrastAdjustment: contrastAdjustment,
            outputRawTIFF: outputRawTIFF,
            temporaryOutputURL: URL(fileURLWithPath: outputPath),
            capabilityToken: capabilityToken
        )
    }
}

/// protocol v2 result에 포함되는 실제 적용 옵션.
/// 생성 시 요청값을 그대로 보존하며, backend가 정확히 적용·검증한 뒤에만 전송한다.
public struct PluginAppliedScanOptionsV2: Codable, Sendable, Equatable {
    public var deviceID: String
    public var resolutionDPI: Int
    public var bitDepth: Int
    public var colorMode: String
    public var filmType: String
    public var scanArea: ScanArea
    public var infrared: Bool
    public var multiExposure: Bool
    public var hardwareExposureTime: Int?
    public var brightnessAdjustment: Double?
    public var contrastAdjustment: Double?
    public var outputRawTIFF: Bool

    public init(request: PluginScanRequestV2) {
        deviceID = request.deviceID
        resolutionDPI = request.resolutionDPI
        bitDepth = request.bitDepth
        colorMode = request.colorMode
        filmType = request.filmType
        scanArea = request.scanArea
        infrared = request.infrared
        multiExposure = request.multiExposure
        hardwareExposureTime = request.hardwareExposureTime
        brightnessAdjustment = request.brightnessAdjustment
        contrastAdjustment = request.contrastAdjustment
        outputRawTIFF = request.outputRawTIFF
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case resolutionDPI
        case bitDepth
        case colorMode
        case filmType
        case scanArea
        case infrared
        case multiExposure
        case hardwareExposureTime
        case brightnessAdjustment
        case contrastAdjustment
        case outputRawTIFF
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(resolutionDPI, forKey: .resolutionDPI)
        try container.encode(bitDepth, forKey: .bitDepth)
        try container.encode(colorMode, forKey: .colorMode)
        try container.encode(filmType, forKey: .filmType)
        try container.encode(scanArea, forKey: .scanArea)
        try container.encode(infrared, forKey: .infrared)
        try container.encode(multiExposure, forKey: .multiExposure)
        try container.encode(hardwareExposureTime, forKey: .hardwareExposureTime)
        try container.encode(brightnessAdjustment, forKey: .brightnessAdjustment)
        try container.encode(contrastAdjustment, forKey: .contrastAdjustment)
        try container.encode(outputRawTIFF, forKey: .outputRawTIFF)
    }
}

public struct PluginScanEventV2: Codable, Sendable, Equatable {
    public var type: String
    public var protocolVersion: Int
    public var requestID: UUID
    public var sequence: UInt64
    public var phase: String?
    public var fraction: Double?
    public var message: String?
    public var width: Int?
    public var height: Int?
    public var path: String?
    public var resolutionDPI: Int?
    public var bitDepth: Int?
    public var irPath: String?
    public var hasInfrared: Bool?
    public var warnings: [String]?
    public var appliedOptions: PluginAppliedScanOptionsV2?

    public init(
        type: String,
        requestID: UUID,
        sequence: UInt64,
        phase: String? = nil,
        fraction: Double? = nil,
        message: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        path: String? = nil,
        resolutionDPI: Int? = nil,
        bitDepth: Int? = nil,
        irPath: String? = nil,
        hasInfrared: Bool? = nil,
        warnings: [String]? = nil,
        appliedOptions: PluginAppliedScanOptionsV2? = nil
    ) {
        self.type = type
        protocolVersion = 2
        self.requestID = requestID
        self.sequence = sequence
        self.phase = phase
        self.fraction = fraction
        self.message = message
        self.width = width
        self.height = height
        self.path = path
        self.resolutionDPI = resolutionDPI
        self.bitDepth = bitDepth
        self.irPath = irPath
        self.hasInfrared = hasInfrared
        self.warnings = warnings
        self.appliedOptions = appliedOptions
    }
}
