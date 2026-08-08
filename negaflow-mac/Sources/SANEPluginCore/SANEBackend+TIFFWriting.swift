import Foundation
import CoreGraphics
import CoreImage
import ImageIO

extension SANEBackend {
    static func renderRGBAf(
        _ image: CIImage,
        width: Int,
        height: Int,
        context: CIContext,
        colorSpace linear: CGColorSpace
    ) -> [Float] {
        var buffer = [Float](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { rawBuffer in
            context.render(
                image,
                toBitmap: rawBuffer.baseAddress!,
                rowBytes: width * 4 * MemoryLayout<Float>.size,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            )
        }
        return buffer
    }

    /// 패스 간 정렬 오프셋 추정. 다운샘플 피라미드로 거칠게 찾고 풀해상도에서 미세보정한다.
    /// 필름 이송(세로/feed 축) 흔들림이 3600dpi에서 수십 픽셀에 달하므로 세로(dy)를 넓게 탐색한다.

    static func writeLinearTIFF(_ image: CIImage, to url: URL) throws {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let context = CIContext(options: [
            .workingColorSpace: linear,
            .outputColorSpace: linear,
        ])
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBAh, colorSpace: linear) else {
            throw ScannerError(.ioFailure, "multi-pass TIFF 이미지 생성 실패")
        }
        try? FileManager.default.removeItem(at: url)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil) else {
            throw ScannerError(.ioFailure, "multi-pass TIFF 출력 생성 실패")
        }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScannerError(.ioFailure, "multi-pass TIFF 출력 저장 실패")
        }
    }

    static func writeRGB16TIFF(_ pixels: [UInt16], width: Int, height: Int, to url: URL) throws {
        let bigEndianPixels = pixels.map(\.bigEndian)
        var data = Data(count: bigEndianPixels.count * MemoryLayout<UInt16>.size)
        data.withUnsafeMutableBytes { destination in
            bigEndianPixels.withUnsafeBytes { source in
                destination.copyMemory(from: source)
            }
        }
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
              ) else {
            throw ScannerError(.ioFailure, "multi-sample RGB16 이미지 생성 실패")
        }
        try? FileManager.default.removeItem(at: url)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil) else {
            throw ScannerError(.ioFailure, "multi-sample TIFF 출력 생성 실패")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScannerError(.ioFailure, "multi-sample TIFF 출력 저장 실패")
        }
    }
}
