import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import SANEPluginCore

/// Epson V500 Photo 의 IR 모드는 800 dpi 와 1600 dpi 만 받는다. 본 스캔이 그 밖의 해상도이면
/// IR 은 가까운 해상도로 읽고 본 스캔의 픽셀 격자로 늘린다.
final class SANEBackendInfraredResolutionTests: XCTestCase {

    func testFallbackKeepsRequestedResolutionWhenAvailable() {
        XCTAssertNil(SANEBackend.infraredFallbackDPI(requested: 800, available: [800, 1600]))
        XCTAssertNil(SANEBackend.infraredFallbackDPI(requested: 1600, available: [800, 1600]))
    }

    func testFallbackPicksLargestResolutionBelowRequest() {
        XCTAssertEqual(SANEBackend.infraredFallbackDPI(requested: 6400, available: [800, 1600]), 1600)
        XCTAssertEqual(SANEBackend.infraredFallbackDPI(requested: 3200, available: [800, 1600]), 1600)
        XCTAssertEqual(SANEBackend.infraredFallbackDPI(requested: 1200, available: [800, 1600]), 800)
    }

    func testFallbackUsesLowestResolutionWhenRequestIsBelowAll() {
        XCTAssertEqual(SANEBackend.infraredFallbackDPI(requested: 200, available: [800, 1600]), 800)
    }

    func testFallbackWithoutList() {
        XCTAssertNil(SANEBackend.infraredFallbackDPI(requested: 6400, available: []))
    }

    func testResampleKeepsSixteenBitGrayAndScalesToRequestedSize() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ir-resample-\(UUID().uuidString).tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.writeGradientTIFF(to: url, width: 8, height: 6)

        try SANEBackend.resampleGray16TIFF(at: url, width: 32, height: 24)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 32)
        XCTAssertEqual(image.height, 24)
        XCTAssertEqual(image.bitsPerComponent, 16)
        XCTAssertEqual(image.colorSpace?.model, .monochrome)
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.tiff")
    }

    func testResamplePreservesValueRange() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ir-range-\(UUID().uuidString).tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.writeGradientTIFF(to: url, width: 8, height: 6)

        try SANEBackend.resampleGray16TIFF(at: url, width: 32, height: 24)

        let values = try Self.grayValues(of: url)
        let low = try XCTUnwrap(values.min())
        let high = try XCTUnwrap(values.max())
        // 8 단계 가로 기울기(0...65535)를 늘려도 양 끝 값이 크게 변하지 않는다.
        XCTAssertLessThan(low, 4000)
        XCTAssertGreaterThan(high, 61000)
        // 8-bit 로 접힌 값은 모두 257 의 배수다. 16-bit 정밀도가 남아 있으면 그렇지 않은 값이 있다.
        XCTAssertTrue(values.contains { $0 % 257 != 0 })
    }

    // MARK: helpers

    private static func writeGradientTIFF(to url: URL, width: Int, height: Int) throws {
        var pixels = [UInt16](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = UInt16(Double(x) / Double(width - 1) * 65535)
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 16,
            bytesPerRow: width * 2, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue
                | CGBitmapInfo.byteOrder16Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private static func grayValues(of url: URL) throws -> [UInt16] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let data = try XCTUnwrap(image.dataProvider?.data)
        let count = image.width * image.height
        let length = CFDataGetLength(data)
        XCTAssertGreaterThanOrEqual(length, count * 2)
        var values = [UInt16](repeating: 0, count: count)
        let littleEndian = image.bitmapInfo.contains(.byteOrder16Little)
        let bytes = CFDataGetBytePtr(data)!
        for i in 0..<count {
            let b0 = UInt16(bytes[2 * i]), b1 = UInt16(bytes[2 * i + 1])
            values[i] = littleEndian ? (b1 << 8 | b0) : (b0 << 8 | b1)
        }
        return values
    }
}
