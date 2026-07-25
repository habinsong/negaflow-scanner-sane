import Foundation
import CoreImage
import CoreGraphics
import ImageIO

// MARK: - Plugin-local TIFFLoader
//
// 멀티샘플/HDR 병합에서 스캐너 raw TIFF(16bit linear)를 읽고/쓰기 위한 최소 로더.
// 같은 저자가 작성한 Negaflow의 TIFF 입출력 계약과 같은 Apple 프레임워크 동작을 사용하지만,
// 이 플러그인이 독립적으로 빌드되도록 필요한 두 연산만 로컬에 둔다.
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
