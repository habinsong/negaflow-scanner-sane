import XCTest
import Foundation
import CoreGraphics
import CoreImage
import ImageIO
@testable import SANEPluginCore

final class SANEBackendMultiSampleTests: XCTestCase {

    func testMultiSampleAverageReducesMidtoneRandomNoise() {
        let width = 48
        let height = 24
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

        func makeImage(phase: Int) -> CIImage {
            var pixels = [Float](repeating: 1, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    let sign: Float = ((x + y + phase) % 3 == 0) ? 1 : -0.5
                    let value: Float = 0.48 + sign * 0.045
                    pixels[i] = value
                    pixels[i + 1] = value
                    pixels[i + 2] = value
                    pixels[i + 3] = 1
                }
            }
            return CIImage(
                bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }

        let midtone = makeImage(phase: 0)
        let merged = SANEBackend.averageMultiSampleScans([
            makeImage(phase: 1),
            midtone,
            makeImage(phase: 2),
        ])
        let context = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var baseline = [Float](repeating: 0, count: width * height * 4)
        var output = [Float](repeating: 0, count: width * height * 4)
        context.render(midtone, toBitmap: &baseline, rowBytes: width * 4 * MemoryLayout<Float>.size,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .RGBAf, colorSpace: linear)
        context.render(merged, toBitmap: &output, rowBytes: width * 4 * MemoryLayout<Float>.size,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .RGBAf, colorSpace: linear)

        XCTAssertLessThan(lumaStandardDeviation(output), lumaStandardDeviation(baseline) * 0.45)
    }

    func testHardwareExposurePlanRepeatsEachExposureForNoiseReduction() {
        XCTAssertEqual(
            SANEBackend.hardwareExposurePlan(samplesPerStop: 2),
            [11_000, 11_000, 14_000, 14_000, 30_000, 30_000]
        )
    }

    func testMultiSampleBitmapPreservesSixteenBitChannelScale() throws {
        let width = 2
        let height = 1
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let values: [Float] = [
            1.0 / 65535.0, 2.0 / 65535.0, 3.0 / 65535.0, 1,
            300.0 / 65535.0, 400.0 / 65535.0, 500.0 / 65535.0, 1,
        ]
        let image = CIImage(
            bitmapData: Data(bytes: values, count: values.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        let bitmap = try SANEBackend.averageMultiSampleBitmap([image, image, image])

        XCTAssertEqual(bitmap.width, width)
        XCTAssertEqual(bitmap.height, height)
        XCTAssertEqual(bitmap.pixels[0], 1)
        XCTAssertEqual(bitmap.pixels[1], 2)
        XCTAssertEqual(bitmap.pixels[2], 3)
        XCTAssertEqual(bitmap.pixels[3], 300)
        XCTAssertEqual(bitmap.pixels[4], 400)
        XCTAssertEqual(bitmap.pixels[5], 500)
    }

    func testMultiSampleBitmapUsesRawArithmeticMeanWithoutMedianNormalization() throws {
        let width = 24
        let height = 12
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

        func makeSolidImage(_ value: Float) -> CIImage {
            var pixels = [Float](repeating: 1, count: width * height * 4)
            for index in stride(from: 0, to: pixels.count, by: 4) {
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
            }
            return CIImage(
                bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }

        let bitmap = try SANEBackend.averageMultiSampleBitmap([
            makeSolidImage(0.20),
            makeSolidImage(0.40),
            makeSolidImage(0.80),
        ])

        let expected = Int(((0.20 + 0.40 + 0.80) / 3.0) * 65535.0)
        XCTAssertEqual(Int(bitmap.pixels[0]), expected, accuracy: 1)
        XCTAssertEqual(Int(bitmap.pixels[1]), expected, accuracy: 1)
        XCTAssertEqual(Int(bitmap.pixels[2]), expected, accuracy: 1)
    }

    func testMultiSampleBitmapAlignsOnePixelPassShiftBeforeAveraging() throws {
        let width = 32
        let height = 20
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

        func makeEdgeImage(shiftX: Int) -> CIImage {
            var pixels = [Float](repeating: 1, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let sourceX = x - shiftX
                    let value: Float = sourceX < width / 2 ? 0.18 : 0.78
                    let offset = (y * width + x) * 4
                    pixels[offset] = value
                    pixels[offset + 1] = value
                    pixels[offset + 2] = value
                    pixels[offset + 3] = 1
                }
            }
            return CIImage(
                bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }

        let bitmap = try SANEBackend.averageMultiSampleBitmap([
            makeEdgeImage(shiftX: 0),
            makeEdgeImage(shiftX: 1),
            makeEdgeImage(shiftX: 0),
        ])

        let left = bitmap.pixels[((height / 2 * width + width / 2 - 1) * 3)]
        let right = bitmap.pixels[((height / 2 * width + width / 2) * 3)]
        XCTAssertGreaterThan(
            Int(right) - Int(left),
            30_000,
            "multi-pass 평균 전에 1px 패스 밀림을 정렬하지 않으면 에지가 흐려진다."
        )
    }

    func testMultiSampleFileMergePreservesScannerRawLinearScale() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scannerkit_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let sampleURLs = (0..<3).map { dir.appendingPathComponent("sample_\($0).tiff") }
        let outputURL = dir.appendingPathComponent("merged.tiff")
        for url in sampleURLs {
            try writeScannerRGB16TIFF(
                pixels: [0.24, 0.10, 0.07],
                width: 1,
                height: 1,
                to: url
            )
        }

        try SANEBackend.averageMultiSampleScans(sampleURLs: sampleURLs, outputURL: outputURL)
        guard let merged = TIFFLoader.loadScannerTIFF(outputURL) else {
            return XCTFail("merged scanner TIFF should load")
        }
        let context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        ])
        var pixel = [Float](repeating: 0, count: 4)
        context.render(
            merged,
            toBitmap: &pixel,
            rowBytes: 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )

        XCTAssertEqual(Double(pixel[0]), 0.24, accuracy: 0.001)
        XCTAssertEqual(Double(pixel[1]), 0.10, accuracy: 0.001)
        XCTAssertEqual(Double(pixel[2]), 0.07, accuracy: 0.001)
        XCTAssertNil(
            CGImageSourceCopyPropertiesAtIndex(
                CGImageSourceCreateWithURL(outputURL as CFURL, nil)!,
                0,
                nil
            ).flatMap { ($0 as NSDictionary)[kCGImagePropertyProfileName] },
            "merged raw scanner TIFF should not embed an ICC profile that changes scanner sample interpretation"
        )
    }

    // MARK: - SANE 환경 (GUI exit-1 버그 수정 회귀 테스트)
    //
    // GUI .app 환경에서 scanimage 가 "open of device failed: Invalid argument"
    // (exit 1)로 실패하는 근본 원인은 SANE_CONFIG_DIR / PATH 누락이었다.
    // makeSaneEnvironment() 는 반드시 Homebrew 경로를 포함해야 한다.

}
