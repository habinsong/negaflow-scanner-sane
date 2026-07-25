import XCTest
import Foundation
import CoreGraphics
import CoreImage
@testable import SANEPluginCore

final class SANEBackendHardwareExposureTests: XCTestCase {

    func testHardwareExposureMergeUsesShortExposureForClippedHighlights() throws {
        let width = 4
        let height = 1
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

        func makeImage(_ values: [Float]) -> CIImage {
            var pixels = [Float]()
            for value in values {
                pixels += [value, value, value, 1]
            }
            return CIImage(
                bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }

        let exposureTimes = [11_000, 14_000, 30_000]
        let sceneAtReference: [Float] = [0.08, 0.24, 0.72, 0.96]
        let images = exposureTimes.map { exposure -> CIImage in
            let scale = Float(exposure) / 14_000.0
            return makeImage(sceneAtReference.map { min($0 * scale, 1.0) })
        }

        let bitmap = try SANEBackend.mergeHardwareExposureBitmap(images, exposureTimes: exposureTimes)
        let highlight = Double(bitmap.pixels[9]) / 65535.0

        XCTAssertGreaterThan(highlight, 0.93)
        XCTAssertLessThan(highlight, 1.0, "긴 노출 클립값 1.0을 그대로 쓰지 않고 짧은 노출에서 복원해야 한다.")
    }

    func testHardwareExposureMergePreservesNormalExposureMidtones() throws {
        let width = 5
        let height = 1
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

        func makeImage(_ values: [Float]) -> CIImage {
            var pixels = [Float]()
            for value in values {
                pixels += [value, value, value, 1]
            }
            return CIImage(
                bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }

        let exposureTimes = [11_000, 14_000, 30_000]
        let sceneAtReference: [Float] = [0.02, 0.12, 0.32, 0.55, 0.76]
        let images = exposureTimes.map { exposure -> CIImage in
            let scale = Float(exposure) / 14_000.0
            return makeImage(sceneAtReference.map { min($0 * scale, 1.0) })
        }

        let bitmap = try SANEBackend.mergeHardwareExposureBitmap(images, exposureTimes: exposureTimes)

        for pixel in 1..<sceneAtReference.count {
            let output = Double(bitmap.pixels[pixel * 3]) / 65535.0
            XCTAssertEqual(
                output,
                Double(sceneAtReference[pixel]),
                accuracy: 0.025,
                "중간톤은 14k 기준 패스의 raw 스케일을 유지해야 한다."
            )
        }
    }

    func testHardwareExposureMergeAveragesRepeatedNormalExposureNoise() throws {
        let width = 3
        let height = 1
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

        func makeImage(_ values: [Float]) -> CIImage {
            var pixels = [Float]()
            for value in values {
                pixels += [value, value, value, 1]
            }
            return CIImage(
                bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }

        let images = [
            makeImage([0.12, 0.35, 0.88]),
            makeImage([0.12, 0.35, 0.88]),
            makeImage([0.20, 0.48, 0.76]),
            makeImage([0.20, 0.52, 0.76]),
            makeImage([0.36, 0.90, 1.0]),
            makeImage([0.36, 0.90, 1.0]),
        ]
        let exposureTimes = [11_000, 11_000, 14_000, 14_000, 30_000, 30_000]

        let bitmap = try SANEBackend.mergeHardwareExposureBitmap(images, exposureTimes: exposureTimes)
        let midtone = Double(bitmap.pixels[4]) / 65535.0

        XCTAssertEqual(
            midtone,
            0.50,
            accuracy: 0.015,
            "동일 14k 노출 반복 샘플은 HDR merge 전에 평균되어 랜덤 노이즈를 줄여야 한다."
        )
    }

    func testHardwareExposureMergeKeepsLongExposureFromDominatingShadows() throws {
        let width = 1
        let height = 1
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

        func makeImage(_ value: Float) -> CIImage {
            let pixels: [Float] = [value, value, value, 1]
            return CIImage(
                bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }

        let exposureTimes = [11_000, 14_000, 30_000]
        let images = [
            makeImage(0.007),
            makeImage(0.012),
            makeImage(0.080),
        ]

        let bitmap = try SANEBackend.mergeHardwareExposureBitmap(images, exposureTimes: exposureTimes)
        let output = Double(bitmap.pixels[0]) / 65535.0

        XCTAssertLessThan(output, 0.030, "long exposure가 암부 저신호를 전부 지배하면 색비/컬러 노이즈가 long pass 바이어스를 따라간다.")
        XCTAssertGreaterThan(output, 0.012, "긴 노출 보강은 완전히 끄지 말고 최저 신호의 계조만 보강해야 한다.")
    }

}
