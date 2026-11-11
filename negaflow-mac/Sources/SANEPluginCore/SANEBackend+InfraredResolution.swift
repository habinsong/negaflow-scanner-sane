import CoreGraphics
import Foundation
import ImageIO

/// 적외선 패스가 본 스캔과 같은 해상도를 지원하지 않는 장치를 위한 처리.
///
/// Epson Perfection V500 Photo 는 Infrared 모드에서 800 dpi 와 1600 dpi 만 받는다. 본 스캔이
/// 6400 dpi 이면 IR 패스를 같은 해상도로 요청할 수 없어 스캔 전체가 실패했다. 이 경우 IR 을
/// 장치가 받는 가장 가까운 해상도로 읽고, 본 스캔과 같은 픽셀 격자로 늘려 돌려준다. IR 채널은
/// 먼지 위치를 알려 주는 측정값이라 본 스캔보다 낮은 해상도에서 읽어도 지오메트리는 같다.
extension SANEBackend {

    /// 요청 해상도가 목록에 없을 때 IR 패스에 쓸 해상도.
    ///
    /// 요청 이하에서 가장 큰 값을 고른다. 요청보다 낮은 값이 하나도 없으면 가장 낮은 값을 쓴다.
    /// 요청 해상도가 목록에 있으면 nil(본 스캔과 같은 해상도)을 돌려준다.
    static func infraredFallbackDPI(requested: Int, available: [Int]) -> Int? {
        guard !available.isEmpty, !available.contains(requested) else { return nil }
        return available.filter { $0 < requested }.max() ?? available.min()
    }

    /// IR 패스의 해상도를 정한다. nil 이면 본 스캔과 같은 해상도를 쓴다.
    ///
    /// epson2 에만 적용한다. 장치를 한 번 더 여는 일이 전용 필름 스캐너의 다음 획득을 깰 수
    /// 있어(§canReuseSinglePassOptionsDump), 다른 백엔드는 지금처럼 같은 해상도로 요청한다.
    func infraredResolutionOverride(
        options: ScanOptions,
        media: MediaSelection
    ) async -> Int? {
        let backend = Self.backendName(
            of: options.scannerID.replacingOccurrences(of: "sane-", with: "")
        )
        guard backend == "epson2",
              case .separateMode(let infraredMode) = media.irStrategy,
              let requested = media.resolvedDPI,
              let devname = try? await resolveDeviceAddress(
                for: options,
                media: media,
                forceRefresh: false
              ) else { return nil }

        var args = ["-A", "-d", devname]
        if let source = media.source { args += ["--source", source] }
        args += ["--mode", infraredMode]
        guard let dump = try? await runScanimage(args: args, ownedByScanSession: true),
              case .list(let available) = SaneOptionDump(dump).resolutionSpec else {
            return nil
        }
        return Self.infraredFallbackDPI(requested: requested, available: available)
    }

    /// 16-bit Gray TIFF 를 지정한 크기로 다시 샘플링해 같은 경로에 쓴다.
    static func resampleGray16TIFF(at url: URL, width: Int, height: Int) throws {
        guard width > 0, height > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.bitsPerComponent == 16,
              let colorSpace = image.colorSpace,
              colorSpace.model == .monochrome else {
            throw ScannerError(.ioFailure, "IR TIFF 를 16-bit Gray 로 읽을 수 없어 크기를 맞추지 못했습니다.")
        }

        let little = CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
        let plain = CGImageAlphaInfo.none.rawValue
        guard let context = [little, plain].lazy.compactMap({ info in
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 16,
                bytesPerRow: 0, space: colorSpace, bitmapInfo: info
            )
        }).first else {
            throw ScannerError(.ioFailure, "IR 크기 변환용 비트맵을 만들 수 없습니다.")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".resampled-\(UUID().uuidString).tiff")
        guard let scaled = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                temporaryURL as CFURL, "public.tiff" as CFString, 1, nil
              ) else {
            throw ScannerError(.ioFailure, "IR 크기 변환 결과를 만들 수 없습니다.")
        }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw ScannerError(.ioFailure, "IR 크기 변환 결과를 쓸 수 없습니다.")
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
    }
}
