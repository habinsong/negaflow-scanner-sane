import CoreGraphics
import Foundation
import ImageIO
@testable import SANEPluginCore

struct VirtualSANEDevice: Sendable {
    let name: String
    let vendor: String
    let model: String
    let backend: String
    let address: String
    let deviceType: String
    let usbProductID: String
    let baseOptionDump: String
    let optionDump: String
    let previewArea: ScanArea
    let fullScanResolution: Resolution
    let supportsInfrared: Bool

    var scannerID: String { "sane-\(address)" }

    static let epsonFilmFlatbeds: [VirtualSANEDevice] = [
        epson(name: "Epson Perfection V700", model: "Perfection V700 Photo", productID: "0x012c"),
        epson(name: "Epson Perfection V750", model: "Perfection V750 Photo", productID: "0x012c"),
        epson(name: "Epson Perfection V800", model: "Perfection V800 Photo", productID: "0x0151"),
        epson(name: "Epson Perfection V850", model: "Perfection V850 Pro", productID: "0x0151"),
    ]

    static let opticFilmScanners: [VirtualSANEDevice] = [
        opticFilm(name: "OpticFilm 7200", productID: "0x0807", resolutions: [900, 1800, 3600, 7200]),
        opticFilm(name: "OpticFilm 7200 v2", productID: "0x0c07", resolutions: [900, 1800, 3600, 7200]),
        opticFilm(name: "OpticFilm 7200i", productID: "0x0c04", resolutions: [900, 1800, 3600, 7200], infrared: true),
        opticFilm(name: "OpticFilm 7300", productID: "0x0c12", resolutions: [900, 1800, 3600, 7200]),
        opticFilm(name: "OpticFilm 7400", productID: "0x0c3a", resolutions: [600, 1200, 1800, 3600, 7200]),
        opticFilm(name: "OpticFilm 7500i", productID: "0x0c13", resolutions: [900, 1800, 3600, 7200], infrared: true),
        opticFilm(name: "OpticFilm 7600i", productID: "0x0c3b", resolutions: [900, 1800, 3600, 7200], infrared: true),
        opticFilm(name: "OpticFilm 8100", productID: "0x130c", resolutions: [600, 1200, 2400, 3600, 7200]),
        opticFilm(name: "OpticFilm 8200i", productID: "0x130d", resolutions: [900, 1800, 3600, 7200], infrared: true),
    ]

    static let nikonCoolscanScanners: [VirtualSANEDevice] = [
        coolscan(name: "Nikon LS-30", address: "coolscan3:scsi:/dev/sg0"),
        coolscan(name: "Nikon LS-40 ED", address: "coolscan3:usb:libusb:001:4000"),
        coolscan(name: "Nikon LS-50 ED", address: "coolscan3:usb:libusb:001:4001"),
        coolscan(name: "Nikon LS-2000", address: "coolscan3:scsi:/dev/sg1"),
        coolscan(name: "Nikon LS-4000 ED", address: "coolscan3:firewire:scanner0"),
        coolscan(name: "Nikon LS-8000 ED", address: "coolscan3:firewire:scanner1"),
    ]

    static let pieusbScanners: [VirtualSANEDevice] = [
        pieusb(name: "Reflecta ProScan 7200", productID: "0x0145"),
        pieusb(name: "Reflecta DigitDia 6000", productID: "0x0142"),
    ]

    static let unsupportedOpticFilmProductIDs: Set<String> = ["0x1825"]

    private static func epson(name: String, model: String, productID: String) -> VirtualSANEDevice {
        VirtualSANEDevice(
            name: name,
            vendor: "Epson",
            model: model,
            backend: "epson2",
            address: "epson2:libusb:001:\(productID.dropFirst(2))",
            deviceType: "flatbed scanner",
            usbProductID: productID,
            baseOptionDump: epsonOptionDump(
                selectedSource: "Flatbed",
                widthMM: 215.9,
                heightMM: 297.18
            ),
            optionDump: epsonOptionDump(
                selectedSource: "TPU8x10",
                widthMM: 203.2,
                heightMM: 254
            ),
            previewArea: ScanArea(widthMM: 203.2, heightMM: 254),
            fullScanResolution: Resolution(2400),
            supportsInfrared: false
        )
    }

    private static func opticFilm(
        name: String,
        productID: String,
        resolutions: [Int],
        infrared: Bool = false
    ) -> VirtualSANEDevice {
        let sources = infrared
            ? "Transparency Adapter|Transparency Adapter Infrared"
            : "Transparency Adapter"
        let optionDump = """
        All options specific to device `genesys':
          Scan Mode:
            --mode Color|Gray [Gray]
            --source \(sources) [Transparency Adapter]
            --preview[=(yes|no)] [no]
            --depth 16 [16]
            --resolution \(resolutions.map(String.init).joined(separator: "|"))dpi [\(resolutions.first ?? 3600)]
          Geometry:
            -l 0..36.33mm [0]
            -t 0..25mm [0]
            -x 0..36.33mm [36.33]
            -y 0..25mm [25]
        """
        return VirtualSANEDevice(
            name: name,
            vendor: "PLUSTEK",
            model: name,
            backend: "genesys",
            address: "genesys:libusb:000:\(productID.dropFirst(2))",
            deviceType: "film scanner",
            usbProductID: productID,
            baseOptionDump: optionDump,
            optionDump: optionDump,
            previewArea: ScanArea(widthMM: 36, heightMM: 24),
            fullScanResolution: Resolution(3600),
            supportsInfrared: infrared
        )
    }

    private static func coolscan(name: String, address: String) -> VirtualSANEDevice {
        let optionDump = """
        All options specific to device `coolscan3':
          --preview[=(yes|no)] [no]
          --infrared[=(yes|no)] [no]
          --depth 8|14 [8]
          --resolution 4000|2000|1000dpi [4000]
          --tl-x 0..5959pel (in steps of 1) [0]
          --tl-y 0..3946pel (in steps of 1) [0]
          --br-x 0..5959pel (in steps of 1) [5959]
          --br-y 0..3946pel (in steps of 1) [3946]
        """
        return VirtualSANEDevice(
            name: name,
            vendor: "Nikon",
            model: String(name.dropFirst("Nikon ".count)),
            backend: "coolscan3",
            address: address,
            deviceType: "film scanner",
            usbProductID: "",
            baseOptionDump: optionDump,
            optionDump: optionDump,
            previewArea: ScanArea(widthMM: 36, heightMM: 24),
            fullScanResolution: Resolution(4000),
            supportsInfrared: false
        )
    }

    private static func pieusb(name: String, productID: String) -> VirtualSANEDevice {
        let optionDump = """
        All options specific to device `pieusb':
          --mode Lineart|Halftone|Gray|Color|RGBI [Color]
          --preview[=(yes|no)] [no]
          --depth 8|16 [8]
          --resolution 900|1800|3600|7200dpi [3600]
          --clean-image[=(yes|no)] [no]
          -l 0..36.33mm (in steps of 0.01) [0]
          -t 0..25mm (in steps of 0.01) [0]
          -x 1..36.33mm (in steps of 0.01) [36.33]
          -y 1..25mm (in steps of 0.01) [25]
        """
        return VirtualSANEDevice(
            name: name,
            vendor: "Reflecta",
            model: String(name.dropFirst("Reflecta ".count)),
            backend: "pieusb",
            address: "pieusb:libusb:001:\(productID.dropFirst(2))",
            deviceType: "slide scanner",
            usbProductID: productID,
            baseOptionDump: optionDump,
            optionDump: optionDump,
            previewArea: ScanArea(widthMM: 36, heightMM: 24),
            fullScanResolution: Resolution(3600),
            supportsInfrared: false
        )
    }

    private static func epsonOptionDump(
        selectedSource: String,
        widthMM: Double,
        heightMM: Double
    ) -> String {
        """
        All options specific to device `epson2':
          Scan Mode:
            --mode Lineart|Gray|Color [Color]
            --source Flatbed|Transparency Unit|TPU8x10 [\(selectedSource)]
            --preview[=(yes|no)] [no]
            --depth 8|16 [8]
            --resolution 50..6400dpi (in steps of 1) [300]
            --film-type Positive Film|Negative Film|Positive Slide|Negative Slide [Positive Film]
          Geometry:
            -l 0..\(widthMM)mm (in steps of 0.1) [0]
            -t 0..\(heightMM)mm (in steps of 0.1) [0]
            -x 1..\(widthMM)mm (in steps of 0.1) [\(widthMM)]
            -y 1..\(heightMM)mm (in steps of 0.1) [\(heightMM)]
        """
    }
}

struct VirtualScanimageFixture {
    let root: URL
    let executableURL: URL
    let invocationLogURL: URL

    init(device: VirtualSANEDevice) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-virtual-sane-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        executableURL = root.appendingPathComponent("scanimage")
        invocationLogURL = root.appendingPathComponent("invocations.log")

        let baseOptionsURL = root.appendingPathComponent("base-options.txt")
        try device.baseOptionDump.write(to: baseOptionsURL, atomically: true, encoding: .utf8)
        let optionsURL = root.appendingPathComponent("selected-options.txt")
        try device.optionDump.write(to: optionsURL, atomically: true, encoding: .utf8)

        let preview8URL = root.appendingPathComponent("preview-8.tiff")
        let preview16URL = root.appendingPathComponent("preview-16.tiff")
        let firstROIURL = root.appendingPathComponent("roi-first-16.tiff")
        let secondROIURL = root.appendingPathComponent("roi-second-16.tiff")
        let infraredURL = root.appendingPathComponent("infrared-16.tiff")
        let previewWidth = device.backend == "epson2" ? 80 : 60
        let previewHeight = device.backend == "epson2" ? 100 : 40
        try writeVirtualRGB8TIFF(
            width: previewWidth,
            height: previewHeight,
            seed: 17,
            to: preview8URL
        )
        try writeScannerRGB16TIFF(
            pixels: virtualRGBPixels(width: previewWidth, height: previewHeight, seed: 23),
            width: previewWidth,
            height: previewHeight,
            to: preview16URL
        )
        try writeScannerRGB16TIFF(
            pixels: virtualRGBPixels(width: 60, height: 40, seed: 41),
            width: 60,
            height: 40,
            to: firstROIURL
        )
        try writeScannerRGB16TIFF(
            pixels: virtualRGBPixels(width: 60, height: 40, seed: 83),
            width: 60,
            height: 40,
            to: secondROIURL
        )
        try writeVirtualGray16TIFF(width: 60, height: 40, seed: 59, to: infraredURL)

        let deviceLine = "device `\(device.address)' is a \(device.vendor) \(device.model) \(device.deviceType)"
        let formattedDeviceLine = "\(device.address)\t\(device.vendor)\t\(device.model)\t\(device.deviceType)"
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> \(shellQuote(invocationLogURL.path))
        if [ "$1" = "-f" ]; then
          printf '%s\\n' \(shellQuote(formattedDeviceLine))
          exit 0
        fi
        if [ "$1" = "-L" ]; then
          printf '%s\\n' \(shellQuote(deviceLine))
          exit 0
        fi
        if [ "$1" = "-A" ]; then
          case " $* " in
            *"--source TPU8x10"*) exec /bin/cat \(shellQuote(optionsURL.path)) ;;
            *) exec /bin/cat \(shellQuote(baseOptionsURL.path)) ;;
          esac
        fi
        args=" $* "
        batch_pattern=""
        for arg in "$@"; do
          case "$arg" in
            --batch=*) batch_pattern=${arg#--batch=} ;;
          esac
        done
        if [ -n "$batch_pattern" ]; then
          batch_one=$(printf '%s' "$batch_pattern" | /usr/bin/sed 's/%d/1/')
          batch_two=$(printf '%s' "$batch_pattern" | /usr/bin/sed 's/%d/2/')
          /bin/cp \(shellQuote(firstROIURL.path)) "$batch_one"
          /bin/cp \(shellQuote(infraredURL.path)) "$batch_two"
          printf 'Progress: 100%%\\r' >&2
          exit 0
        fi
        case "$args" in
          *"--source Transparency Adapter Infrared"*) source=\(shellQuote(infraredURL.path)) ;;
          *"--preview=yes"*"--depth 8"*) source=\(shellQuote(preview8URL.path)) ;;
          *"--preview=yes"*) source=\(shellQuote(preview16URL.path)) ;;
          *"-l 90 -t 120"*) source=\(shellQuote(secondROIURL.path)) ;;
          *) source=\(shellQuote(firstROIURL.path)) ;;
        esac
        printf 'Progress: 100%%\\r' >&2
        exec /bin/cat "$source"
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
    }

    func outputURL(_ name: String) -> URL {
        root.appendingPathComponent(name)
    }

    func invocations() throws -> String {
        try String(contentsOf: invocationLogURL, encoding: .utf8)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func virtualRGBPixels(width: Int, height: Int, seed: Int) -> [Double] {
    (0..<(width * height)).flatMap { index -> [Double] in
        let x = index % width
        let y = index / width
        let base = Double((x * 11 + y * 17 + seed) % 251) / 250
        return [base, fmod(base + 0.23, 1), fmod(base + 0.47, 1)]
    }
}

private func writeVirtualRGB8TIFF(width: Int, height: Int, seed: Int, to url: URL) throws {
    let values = virtualRGBPixels(width: width, height: height, seed: seed)
        .map { UInt8(min(max($0, 0), 1) * 255) }
    let data = Data(values)
    guard let provider = CGDataProvider(data: data as CFData),
          let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            bytesPerRow: width * 3,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ),
          let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.tiff" as CFString,
            1,
            nil
          ) else {
        throw ScannerError(.ioFailure, "virtual RGB8 TIFF 생성 실패")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ScannerError(.ioFailure, "virtual RGB8 TIFF 저장 실패")
    }
}

private func writeVirtualGray16TIFF(width: Int, height: Int, seed: Int, to url: URL) throws {
    let values = (0..<(width * height)).map { index in
        UInt16((index * 31 + seed) % 65_535).bigEndian
    }
    let data = Data(bytes: values, count: values.count * MemoryLayout<UInt16>.size)
    guard let provider = CGDataProvider(data: data as CFData),
          let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 16,
            bitsPerPixel: 16,
            bytesPerRow: width * MemoryLayout<UInt16>.size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ),
          let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.tiff" as CFString,
            1,
            nil
          ) else {
        throw ScannerError(.ioFailure, "virtual Gray16 TIFF 생성 실패")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ScannerError(.ioFailure, "virtual Gray16 TIFF 저장 실패")
    }
}

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
