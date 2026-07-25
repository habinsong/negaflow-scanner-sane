import Foundation
import SANEPluginCore

// MARK: - Wire protocol
//
// negaflow ↔ 플러그인 JSON 계약. negaflow(ScannerKit.ScannerPluginManifest.swift)의
// PluginDevice / PluginCapabilities / PluginScanOptions / PluginScanEvent 와 스키마가 일치해야 한다.

struct PluginDevice: Codable {
    var id: String
    var displayName: String
    var vendor: String
    var model: String
    var connectionType: String?
    var usbVendorID: String?
    var usbProductID: String?
    var serialNumber: String?
    var verifiedStatus: String?
    var driverVersion: String?
}

struct PluginDetectResponse: Codable {
    var devices: [PluginDevice]
}

struct PluginCapabilityRequest: Codable {
    var deviceID: String
    var vendor: String
    var model: String
}

struct PluginCapabilities: Codable {
    var resolutionsDPI: [Int]
    var modes: [String]
    var bitDepths: [Int]
    var sourceModes: [String]?
    var transparencyModes: [String]?
    var supportsPreview: Bool?
    var supportsTransparency: Bool?
    var supportsInfrared: Bool?
    var supportsMultiExposure: Bool?
    var supportsScanArea: Bool?
    var supportsPositionedScanArea: Bool?
    var brightnessRange: ScannerOptionRange?
    var contrastRange: ScannerOptionRange?
    var hardwareExposureRange: ScannerOptionRange?
    var scanOriginXRange: ScannerOptionRange?
    var scanOriginYRange: ScannerOptionRange?
    var scanWidthRange: ScannerOptionRange?
    var scanHeightRange: ScannerOptionRange?
    var disabledReasons: [String: String]?
    var minScanAreaWidthMM: Double?
    var minScanAreaHeightMM: Double?
    var minScanAreaOriginXMM: Double?
    var minScanAreaOriginYMM: Double?
    var maxScanAreaWidthMM: Double?
    var maxScanAreaHeightMM: Double?
    var maxScanAreaOriginXMM: Double?
    var maxScanAreaOriginYMM: Double?
    var scanAreaUnit: String?
    var outputFormats: [String]?
    var capabilityToken: String?
}
