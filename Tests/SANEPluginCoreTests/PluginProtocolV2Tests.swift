import XCTest
import Foundation
import CoreGraphics
import ImageIO
@testable import SANEPluginCore

final class PluginProtocolV2Tests: XCTestCase {
    private let requestID = UUID(uuidString: "7A91B43D-90F8-41E2-B71D-04D17CD9E03B")!

    func testSourceManifestDeclaresProtocolV2() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(manifest["schemaVersion"] as? Int, 1)
        XCTAssertEqual(manifest["protocolVersion"] as? Int, 2)
        XCTAssertEqual(manifest["pluginVersion"] as? String, "1.0.2")
    }

    func testHostV2RequestDecodesWithoutGuessingAndPreservesExactOptions() throws {
        let request = try JSONDecoder().decode(
            PluginScanRequestV2.self,
            from: Data(validRequestJSON.utf8)
        )
        let options = try request.validatedOptions()

        XCTAssertEqual(request.requestID, requestID)
        XCTAssertEqual(options.scannerID, "sane-genesys:libusb:000:010")
        XCTAssertEqual(options.resolution, .r3600)
        XCTAssertEqual(options.bitDepth, .sixteen)
        XCTAssertEqual(options.colorMode, .color)
        XCTAssertEqual(options.filmType, .colorNegative)
        XCTAssertEqual(options.scanArea, ScanArea(widthMM: 36, heightMM: 24))
        XCTAssertEqual(options.brightnessAdjustment, -1)
        XCTAssertEqual(options.contrastAdjustment, 2)
        XCTAssertEqual(options.temporaryOutputURL?.path, "/tmp/negaflow-v2.tiff")
    }

    func testLegacyScanAreaJSONDefaultsOriginToZero() throws {
        let area = try JSONDecoder().decode(
            ScanArea.self,
            from: Data(#"{"widthMM":36,"heightMM":24}"#.utf8)
        )

        XCTAssertEqual(area, ScanArea(originXMM: 0, originYMM: 0, widthMM: 36, heightMM: 24))
    }

    func testInvalidV2EnumsAndPreviewMutationsFailExplicitly() throws {
        let invalidMode = validRequestJSON.replacingOccurrences(
            of: "\"colorMode\":\"color\"",
            with: "\"colorMode\":\"CMYK\""
        )
        let invalidRequest = try JSONDecoder().decode(
            PluginScanRequestV2.self,
            from: Data(invalidMode.utf8)
        )
        XCTAssertThrowsError(try invalidRequest.validatedOptions()) { error in
            XCTAssertTrue(error.localizedDescription.contains("colorMode"))
        }

        var preview = try JSONDecoder().decode(
            PluginScanRequestV2.self,
            from: Data(validRequestJSON.utf8)
        )
        preview.preview = true
        XCTAssertThrowsError(try preview.validatedOptions()) { error in
            XCTAssertTrue(error.localizedDescription.contains("preview 요청 옵션 계약"))
        }
    }

    func testPreviewAcceptsDeviceReportedSixteenBitDepth() throws {
        var preview = try JSONDecoder().decode(
            PluginScanRequestV2.self,
            from: Data(validRequestJSON.utf8)
        )
        preview.preview = true
        preview.resolutionDPI = 0
        preview.bitDepth = 16
        preview.outputRawTIFF = false

        let options = try preview.validatedOptions()

        XCTAssertEqual(options.resolution, .preview)
        XCTAssertEqual(options.bitDepth, .sixteen)
    }

    func testAppliedOptionsEncodingIncludesRequiredNullKeys() throws {
        let request = try JSONDecoder().decode(
            PluginScanRequestV2.self,
            from: Data(validRequestJSON.utf8)
        )
        var withoutAdjustments = request
        withoutAdjustments.hardwareExposureTime = nil
        withoutAdjustments.brightnessAdjustment = nil
        withoutAdjustments.contrastAdjustment = nil
        let event = PluginScanEventV2(
            type: "result",
            requestID: requestID,
            sequence: 3,
            width: 10,
            height: 8,
            path: request.outputPath,
            resolutionDPI: request.resolutionDPI,
            bitDepth: request.bitDepth,
            hasInfrared: false,
            appliedOptions: PluginAppliedScanOptionsV2(request: withoutAdjustments)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any]
        )
        let applied = try XCTUnwrap(object["appliedOptions"] as? [String: Any])

        XCTAssertEqual(object["protocolVersion"] as? Int, 2)
        XCTAssertEqual(object["sequence"] as? Int, 3)
        XCTAssertTrue(applied.keys.contains("hardwareExposureTime"))
        XCTAssertTrue(applied.keys.contains("brightnessAdjustment"))
        XCTAssertTrue(applied.keys.contains("contrastAdjustment"))
        XCTAssertTrue(applied["hardwareExposureTime"] is NSNull)
        XCTAssertTrue(applied["brightnessAdjustment"] is NSNull)
        XCTAssertTrue(applied["contrastAdjustment"] is NSNull)
    }

    func testExactMediaValidationRejectsResolutionSnappingAndMissingAreaControl() throws {
        var options = ScanOptions.strongDefault(scannerID: "sane-coolscan3:usb:libusb:001:002")
        options.resolution = Resolution(3600)
        let pixelGeometryDump = """
            --mode Color|Gray [Color]
            --depth 8|14 [8]
            --resolution 4000|2000|1000dpi [4000]
            -x 0..5959pel [5959]
            -y 0..3946pel [3946]
        """
        let unsupportedResolution = SANEBackend.resolveMedia(dump: pixelGeometryDump, options: options)
        XCTAssertNil(unsupportedResolution.resolvedDPI)
        XCTAssertThrowsError(try SANEBackend.validateExactOptions(options, media: unsupportedResolution)) {
            XCTAssertTrue($0.localizedDescription.contains("resolution 3600dpi"))
        }

        options.resolution = Resolution(4000)
        let missingAreaDump = """
            --mode Color|Gray [Color]
            --depth 8|14 [8]
            --resolution 4000|2000|1000dpi [4000]
        """
        let unsupportedArea = SANEBackend.resolveMedia(dump: missingAreaDump, options: options)
        XCTAssertThrowsError(try SANEBackend.validateExactOptions(options, media: unsupportedArea)) {
            XCTAssertTrue($0.localizedDescription.contains("scanArea"))
        }
    }

    func testExactMediaValidationAcceptsOnlyFullyReportedControls() throws {
        let dump = """
            --mode Color|Gray [Color]
            --source Transparency Adapter [Transparency Adapter]
            --depth 8|16 [16]
            --resolution 900|1800|3600|7200dpi [3600]
            --preview[=(yes|no)] [no]
            --brightness -100..100 (in steps of 1) [0]
            --contrast -100..100 (in steps of 1) [0]
            --scan-exposure-time 11000..65535 (in steps of 1) [14000]
            -x 1..36.33mm (in steps of 0.01) [36.33]
            -y 1..25mm (in steps of 0.01) [25]
        """
        var options = ScanOptions.strongDefault(scannerID: "sane-genesys:libusb:000:010")
        options.bitDepth = .eight
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        options.brightnessAdjustment = -1
        options.contrastAdjustment = 2
        let media = SANEBackend.resolveMedia(dump: dump, options: options)

        XCTAssertNoThrow(try SANEBackend.validateExactOptions(options, media: media))
        XCTAssertEqual(media.widthMM, 36)
        XCTAssertEqual(media.heightMM, 24)
        XCTAssertEqual(media.resolvedDPI, 3600)
    }

    func testCapabilitiesDoNotInventMissingControlsOrCleanImageIRChannel() {
        let empty = SANEBackend.parseCapabilities("")
        XCTAssertTrue(empty.supportedResolutions.isEmpty)
        XCTAssertTrue(empty.supportedModes.isEmpty)
        XCTAssertTrue(empty.supportedBitDepths.isEmpty)
        XCTAssertFalse(empty.supportsPreview)
        XCTAssertFalse(empty.supportsScanArea)
        XCTAssertFalse(empty.supportsInfrared)

        let cleanImageOnly = SANEBackend.parseCapabilities("""
            --mode Color|Gray [Color]
            --depth 8|16 [16]
            --resolution 900|1800|3600dpi [3600]
            --clean-image[=(yes|no)] [no]
        """, deviceTypeHint: "film scanner")
        XCTAssertFalse(cleanImageOnly.supportsInfrared)

        let coolscanRGBI = SANEBackend.parseCapabilities(
            "--infrared[=(yes|no)] [no]",
            deviceTypeHint: "film scanner",
            backendHint: "coolscan3"
        )
        XCTAssertFalse(
            coolscanRGBI.supportsInfrared,
            "coolscan3의 RGBI 프레임을 stock scanimage가 별도 IR TIFF로 반환한다고 오인하면 안 됩니다."
        )
        XCTAssertTrue(coolscanRGBI.disabledReasons?["infrared"]?.contains("RGBI") == true)
    }

    func testDecodedTIFFMetadataMustMatchRequestedBitDepthColorAndFormat() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rgb16 = root.appendingPathComponent("rgb16.tiff")
        let rgb8 = root.appendingPathComponent("rgb8.tiff")
        let gray16 = root.appendingPathComponent("gray16.tiff")
        let disguisedPNG = root.appendingPathComponent("not-really-tiff.tiff")
        try writeImage(to: rgb16, bitDepth: .sixteen, colorMode: .color, type: "public.tiff" as CFString)
        try writeImage(to: rgb8, bitDepth: .eight, colorMode: .color, type: "public.tiff" as CFString)
        try writeImage(to: gray16, bitDepth: .sixteen, colorMode: .gray, type: "public.tiff" as CFString)
        try writeImage(to: disguisedPNG, bitDepth: .eight, colorMode: .color, type: "public.png" as CFString)

        let metadata = try SANEBackend.validatedScannedTIFF(
            at: rgb16,
            expectedBitDepth: .sixteen,
            expectedColorMode: .color
        )
        XCTAssertEqual(metadata.width, 10)
        XCTAssertEqual(metadata.height, 8)
        XCTAssertEqual(metadata.bitDepth, .sixteen)
        XCTAssertEqual(metadata.colorMode, .color)

        XCTAssertThrowsError(try SANEBackend.validatedScannedTIFF(
            at: rgb8,
            expectedBitDepth: .sixteen,
            expectedColorMode: .color
        )) { XCTAssertTrue($0.localizedDescription.contains("bitDepth 불일치")) }
        XCTAssertThrowsError(try SANEBackend.validatedScannedTIFF(
            at: gray16,
            expectedBitDepth: .sixteen,
            expectedColorMode: .color
        )) { XCTAssertTrue($0.localizedDescription.contains("colorMode 불일치")) }
        XCTAssertThrowsError(try SANEBackend.validatedScannedTIFF(
            at: disguisedPNG,
            expectedBitDepth: .eight,
            expectedColorMode: .color
        )) { XCTAssertTrue($0.localizedDescription.contains("단일 TIFF")) }
    }

    private var validRequestJSON: String {
        """
        {
          "protocolVersion":2,
          "requestID":"\(requestID.uuidString)",
          "deviceID":"sane-genesys:libusb:000:010",
          "resolutionDPI":3600,
          "bitDepth":16,
          "colorMode":"color",
          "filmType":"colorNegative",
          "preview":false,
          "multiExposure":false,
          "infrared":false,
          "brightnessAdjustment":-1,
          "contrastAdjustment":2,
          "scanArea":{"widthMM":36,"heightMM":24},
          "hardwareExposureTime":null,
          "outputRawTIFF":true,
          "outputPath":"/tmp/negaflow-v2.tiff"
        }
        """
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-sane-v2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeImage(
        to url: URL,
        bitDepth: BitDepth,
        colorMode: ColorMode,
        type: CFString
    ) throws {
        let bits = bitDepth.rawValue
        let components = colorMode == .color ? 4 : 1
        let bitmapInfo: UInt32
        let colorSpace: CGColorSpace
        if colorMode == .color {
            bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0)
            colorSpace = CGColorSpaceCreateDeviceRGB()
        } else {
            bitmapInfo = CGImageAlphaInfo.none.rawValue
                | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0)
            colorSpace = CGColorSpaceCreateDeviceGray()
        }
        guard let context = CGContext(
            data: nil,
            width: 10,
            height: 8,
            bitsPerComponent: bits,
            bytesPerRow: 10 * components * (bits / 8),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw ScannerError(.ioFailure, "test image 생성 실패")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScannerError(.ioFailure, "test image 저장 실패")
        }
    }
}
