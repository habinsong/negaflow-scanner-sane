import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import SANEPluginCore

/// V500 Photo 의 IR 패스는 컬러 패스와 스캔마다 다른 양만큼 어긋난다. 먼지로 그 양을 재서 맞춘다.
final class SANEBackendInfraredRegistrationTests: XCTestCase {

    func testWeightedLineRecoversInterceptAndSlope() {
        let (a, b) = SANEBackend.weightedLine(
            x: [0, 100, 200, 300], y: [5, 7, 9, 11], w: [1, 2, 1, 3]
        )
        XCTAssertEqual(a, 5, accuracy: 1e-9)
        XCTAssertEqual(b, 0.02, accuracy: 1e-9)
    }

    func testShiftFollowsLinearModel() {
        let registration = InfraredRegistration(dy0: -3, dyPerRow: 0.001, dx0: 7, dxPerRow: -0.0002)
        let shift = registration.shift(atRow: 4000)
        XCTAssertEqual(shift.dy, 1, accuracy: 1e-9)
        XCTAssertEqual(shift.dx, 6.2, accuracy: 1e-9)
    }

    func testEstimatesShiftBetweenColorAndInfraredDust() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ir-registration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let colorWidth = 480, colorHeight = 360
        let dy = 10, dx = 6        // IR 내용이 컬러보다 아래·오른쪽으로 밀린 양(컬러 픽셀)
        var rng = SystemRandomNumberGeneratorFixed(seed: 7)
        var color = [UInt16](repeating: 0, count: colorWidth * colorHeight)
        var infrared = [UInt16](repeating: 0, count: (colorWidth / 2) * (colorHeight / 2))
        for i in 0..<color.count { color[i] = UInt16(40000 + Int(rng.next() % 600) - 300) }
        for i in 0..<infrared.count { infrared[i] = UInt16(52000 + Int(rng.next() % 600) - 300) }
        for _ in 0..<60 {
            let x = 20 + Int(rng.next() % 420), y = 20 + Int(rng.next() % 300)
            Self.disk(&color, width: colorWidth, height: colorHeight, cx: x, cy: y, radius: 4, value: 15000)
            Self.disk(
                &infrared, width: colorWidth / 2, height: colorHeight / 2,
                cx: (x + dx) / 2, cy: (y + dy) / 2, radius: 2, value: 22000
            )
        }
        let colorURL = dir.appendingPathComponent("color.tiff")
        let infraredURL = dir.appendingPathComponent("ir.tiff")
        try Self.writeGray16(color, width: colorWidth, height: colorHeight, to: colorURL)
        try Self.writeGray16(infrared, width: colorWidth / 2, height: colorHeight / 2, to: infraredURL)

        let registration = try XCTUnwrap(SANEBackend.estimateInfraredRegistration(
            colorURL: colorURL, infraredURL: infraredURL, minPointsPerBand: 30
        ))
        let middle = registration.shift(atRow: Double(colorHeight) / 2)
        XCTAssertEqual(middle.dy, Double(dy), accuracy: 2)
        XCTAssertEqual(middle.dx, Double(dx), accuracy: 2)
        XCTAssertEqual(registration.dyPerRow * Double(colorHeight), 0, accuracy: 3)
    }

    func testReturnsNilWithoutDust() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ir-registration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var rng = SystemRandomNumberGeneratorFixed(seed: 3)
        let flat = (0..<(120 * 90)).map { _ in UInt16(40000 + Int(rng.next() % 600) - 300) }
        let colorURL = dir.appendingPathComponent("color.tiff")
        let infraredURL = dir.appendingPathComponent("ir.tiff")
        try Self.writeGray16(flat, width: 120, height: 90, to: colorURL)
        try Self.writeGray16(flat, width: 120, height: 90, to: infraredURL)
        XCTAssertNil(try SANEBackend.estimateInfraredRegistration(
            colorURL: colorURL, infraredURL: infraredURL, minPointsPerBand: 30
        ))
    }

    func testResampleWithRegistrationMovesContentUpAndLeft() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ir-register-\(UUID().uuidString).tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let width = 200, height = 150
        var pixels = [UInt16](repeating: 60000, count: width * height)
        Self.disk(&pixels, width: width, height: height, cx: 100, cy: 80, radius: 1, value: 0)
        try Self.writeGray16(pixels, width: width, height: height, to: url)

        // 컬러 격자는 2 배. IR 의 (100, 80) 은 컬러 (200, 160). 8 행 4 열 올리고 당기면 (196, 152).
        let registration = InfraredRegistration(dy0: 8, dyPerRow: 0, dx0: 4, dxPerRow: 0)
        try SANEBackend.resampleGray16TIFF(at: url, width: 400, height: 300, registration: registration)

        let values = try Self.grayValues(of: url)
        let darkest = try XCTUnwrap(values.indices.min { values[$0] < values[$1] })
        XCTAssertEqual(Double(darkest % 400), 196, accuracy: 3)
        XCTAssertEqual(Double(darkest / 400), 152, accuracy: 3)
        // 아래쪽 가장자리는 원본 밖이라 흰색으로 남는다.
        XCTAssertEqual(values[299 * 400 + 50], 65535)
    }

    // MARK: helpers

    private struct SystemRandomNumberGeneratorFixed {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
    }

    private static func disk(
        _ pixels: inout [UInt16], width: Int, height: Int, cx: Int, cy: Int, radius: Int, value: UInt16
    ) {
        for y in max(0, cy - radius)...min(height - 1, cy + radius) {
            for x in max(0, cx - radius)...min(width - 1, cx + radius)
            where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius {
                pixels[y * width + x] = value
            }
        }
    }

    private static func writeGray16(_ pixels: [UInt16], width: Int, height: Int, to url: URL) throws {
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
