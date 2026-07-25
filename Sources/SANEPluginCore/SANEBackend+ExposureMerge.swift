import Foundation
import CoreGraphics
import CoreImage
import ImageIO

extension SANEBackend {
    static func averageMultiSampleScans(sampleURLs: [URL], outputURL: URL) throws {
        let images = sampleURLs.compactMap { TIFFLoader.loadScannerTIFF($0) }
        guard images.count == sampleURLs.count, !images.isEmpty else {
            throw ScannerError(.ioFailure, "multi-sample TIFF 로드 실패")
        }
        let bitmap = try averageMultiSampleBitmap(images)
        try writeRGB16TIFF(bitmap.pixels, width: bitmap.width, height: bitmap.height, to: outputURL)
    }

    static func mergeHardwareExposureScans(sampleURLs: [URL], exposureTimes: [Int], outputURL: URL) throws {
        let images = sampleURLs.compactMap { TIFFLoader.loadScannerTIFF($0) }
        guard images.count == sampleURLs.count, !images.isEmpty else {
            throw ScannerError(.ioFailure, "hardware exposure TIFF 로드 실패")
        }
        let bitmap = try mergeHardwareExposureBitmap(images, exposureTimes: exposureTimes)
        try writeRGB16TIFF(bitmap.pixels, width: bitmap.width, height: bitmap.height, to: outputURL)
    }

    static func averageMultiSampleScans(_ images: [CIImage]) -> CIImage {
        guard let first = images.first else {
            return CIImage.empty()
        }
        guard let linear = CGColorSpace(name: CGColorSpace.linearSRGB),
              let averaged = try? alignedAverageRGBAf(images, colorSpace: linear) else {
            return first
        }
        return CIImage(
            bitmapData: Data(bytes: averaged.pixels, count: averaged.pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: averaged.width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: averaged.width, height: averaged.height),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    static func averageMultiSampleBitmap(_ images: [CIImage]) throws -> (pixels: [UInt16], width: Int, height: Int) {
        guard !images.isEmpty,
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else {
            throw ScannerError(.ioFailure, "multi-sample TIFF 로드 실패")
        }
        let averaged = try alignedAverageRGBAf(images, colorSpace: linear)
        var pixels = [UInt16](repeating: 0, count: averaged.width * averaged.height * 3)
        var out = 0
        for index in stride(from: 0, to: averaged.pixels.count, by: 4) {
            pixels[out] = UInt16(min(max(averaged.pixels[index], 0), 1) * 65535)
            pixels[out + 1] = UInt16(min(max(averaged.pixels[index + 1], 0), 1) * 65535)
            pixels[out + 2] = UInt16(min(max(averaged.pixels[index + 2], 0), 1) * 65535)
            out += 3
        }
        return (pixels, averaged.width, averaged.height)
    }

    static func mergeHardwareExposureBitmap(
        _ images: [CIImage],
        exposureTimes: [Int]
    ) throws -> (pixels: [UInt16], width: Int, height: Int) {
        guard images.count == exposureTimes.count, !images.isEmpty,
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else {
            throw ScannerError(.ioFailure, "hardware exposure 입력 오류")
        }
        guard let referenceExposure = referenceExposureTime(from: exposureTimes),
              referenceExposure > 0 else {
            throw ScannerError(.ioFailure, "hardware exposure 기준값 오류")
        }
        let normalized = try alignedExposureNormalizedRGBAf(
            images,
            exposureTimes: exposureTimes,
            referenceExposure: referenceExposure,
            colorSpace: linear
        )
        var pixels = [UInt16](repeating: 0, count: normalized.width * normalized.height * 3)
        var out = 0
        for index in stride(from: 0, to: normalized.pixels.count, by: 4) {
            pixels[out] = UInt16(min(max(normalized.pixels[index], 0), 1) * 65535)
            pixels[out + 1] = UInt16(min(max(normalized.pixels[index + 1], 0), 1) * 65535)
            pixels[out + 2] = UInt16(min(max(normalized.pixels[index + 2], 0), 1) * 65535)
            out += 3
        }
        return (pixels, normalized.width, normalized.height)
    }

    static func referenceExposureTime(from exposureTimes: [Int]) -> Int? {
        let unique = Array(Set(exposureTimes)).sorted()
        guard !unique.isEmpty else { return nil }
        return unique[unique.count / 2]
    }
}
