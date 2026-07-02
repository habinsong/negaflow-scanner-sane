import Foundation
import CoreImage
import CoreGraphics
import ImageIO

// MARK: - TIFFLoader (vendored)
//
// 멀티샘플/HDR 병합에서 스캐너 raw TIFF(16bit linear)를 읽고/쓰기 위한 최소 로더.
// 원래 negaflow Chromabase.ImageLoader의 loadScannerTIFF/saveScannerTIFF와 동일 동작을
// 이 독립 플러그인에 자체적으로 담는다(negaflow 의존 제거).
enum TIFFLoader {
    /// 스캐너 raw TIFF를 16bit linear 로 재해석해 로드한다.
    static func loadScannerTIFF(_ url: URL) -> CIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        return CIImage(cgImage: cg, options: [.colorSpace: linear])
    }

    /// 16bit linear CGImage를 LZW 무손실 TIFF로 저장한다.
    @discardableResult
    static func saveScannerTIFF(_ cg: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil)
        else { return false }
        let props: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5],  // 5 = LZW
        ]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }
}
