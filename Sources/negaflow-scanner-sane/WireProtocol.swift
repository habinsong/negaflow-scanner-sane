import Foundation

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

struct PluginCapabilities: Codable {
    var resolutionsDPI: [Int]
    var modes: [String]
    var bitDepths: [Int]
    var supportsPreview: Bool?
    var supportsTransparency: Bool?
    var supportsInfrared: Bool?
    var supportsMultiExposure: Bool?
    var supportsScanArea: Bool?
    var maxScanAreaWidthMM: Double?
    var maxScanAreaHeightMM: Double?
    var outputFormats: [String]?
}

struct PluginScanOptions: Codable {
    var deviceID: String
    var resolutionDPI: Int
    var bitDepth: Int
    var colorMode: String
    var filmType: String
    var preview: Bool
    var multiExposure: Bool
    var infrared: Bool?          // IR 지원 기기에서 적외선 채널/모드로 스캔(옵션, 없으면 false)
    var outputPath: String
}

struct PluginScanEvent: Codable {
    var type: String
    var phase: String?
    var fraction: Double?
    var message: String?
    var width: Int?
    var height: Int?
    var path: String?
    var resolutionDPI: Int?
    var bitDepth: Int?
}
