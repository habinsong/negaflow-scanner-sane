import Foundation
import CoreGraphics
import ImageIO
@testable import SANEPluginCore

func argValue(_ args: [String], _ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func lumaStandardDeviation(_ pixels: [Float]) -> Double {
    var values: [Double] = []
    values.reserveCapacity(pixels.count / 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let red = Double(pixels[index])
        let green = Double(pixels[index + 1])
        let blue = Double(pixels[index + 2])
        values.append(red * 0.2126 + green * 0.7152 + blue * 0.0722)
    }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
    return sqrt(variance)
}

func writeScannerRGB16TIFF(pixels: [Double], width: Int, height: Int, to url: URL) throws {
    let samples = pixels.map { UInt16(min(max($0, 0), 1) * 65535).bigEndian }
    let data = Data(bytes: samples, count: samples.count * MemoryLayout<UInt16>.size)
    guard let provider = CGDataProvider(data: data as CFData),
          let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 16,
            bitsPerPixel: 48,
            bytesPerRow: width * 3 * MemoryLayout<UInt16>.size,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil) else {
        throw ScannerError(.ioFailure, "test TIFF 생성 실패")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ScannerError(.ioFailure, "test TIFF 저장 실패")
    }
}
