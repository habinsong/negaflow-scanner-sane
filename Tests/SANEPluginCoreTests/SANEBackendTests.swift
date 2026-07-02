import XCTest
@testable import SANEPluginCore

final class SANEBackendCapabilityTests: XCTestCase {

    func testParseSaneCapabilitiesDump() {
        let dump = """
        All options specific to device `genesys:libusb:000:010':
          Scan Mode:
            --mode Color|Gray [Gray]
            --depth 16 [16]
            --resolution 7200|3600|2400|1200|600dpi [600]
            --source Transparency Adapter [Transparency Adapter]
            --brightness -100..100 (in steps of 1) [0]
            --gamma-table 0..65535,... [inactive]
        """
        let cap = SANEBackend.parseCapabilities(dump)
        XCTAssertTrue(cap.supportedResolutions.contains(.r7200))
        XCTAssertTrue(cap.supportedResolutions.contains(.r3600))
        XCTAssertTrue(cap.supportedModes.contains(.color))
        XCTAssertTrue(cap.supportedBitDepths.contains(.sixteen))
        XCTAssertTrue(cap.supportsTransparency)
        XCTAssertFalse(cap.supportsInfrared)   // genesys는 IR 노출 안 함
        XCTAssertFalse(cap.supportsMultiExposure, "brightness/gamma-table은 센서 노출 브라케팅이 아니다.")
    }

    func testParseSaneCapabilitiesMarksHardwareExposureOnlyForScanExposureTime() {
        let dump = """
        All options specific to device `genesys:libusb:000:010':
          Scan Mode:
            --mode Color|Gray [Gray]
            --depth 16 [16]
            --resolution 7200|3600|2400|1200|600dpi [600]
            --source Transparency Adapter [Transparency Adapter]
            --scan-exposure-time 11000..65535 [18000] [advanced]
        """
        let cap = SANEBackend.parseCapabilities(dump)

        XCTAssertTrue(cap.supportsMultiExposure)
    }

    func testSaneScanArgsIncludeHardwareExposureTimeWhenRequested() {
        let backend = SANEBackend(scanimagePath: "/tmp/sane-head-install/bin/scanimage")
        var options = ScanOptions.strongDefault(scannerID: "sane-genesys:libusb:000:010")
        options.hardwareExposureTime = 30_000
        let media = SANEBackend.MediaSelection(source: "Transparency Adapter", mode: "Color", filmType: nil, usesInfrared: false)

        let args = backend.makeScanimageArgs(
            devname: "genesys:libusb:000:010",
            options: options,
            media: media
        )

        XCTAssertTrue(args.contains("--scan-exposure-time=30000"))
        XCTAssertTrue(argValue(args, "--source") == "Transparency Adapter")
        XCTAssertTrue(argValue(args, "--mode") == "Color")
    }

    // MARK: - IR / 소스 감지 (capability 기반)

    func testParseCapabilitiesDetectsInfraredSource() {
        // genesys "i" 필름스캐너: 일반 투과 + 적외선 소스를 노출.
        let dump = """
        All options specific to device `genesys:libusb:000:010':
            --mode Color|Gray [Color]
            --source Transparency Adapter|Transparency Adapter Infrared [Transparency Adapter]
            --depth 16 [16]
            --resolution 7200|3600|1800|900dpi [3600]
        """
        let cap = SANEBackend.parseCapabilities(dump)
        XCTAssertTrue(cap.supportsInfrared, "적외선 소스가 노출되면 IR 지원으로 감지해야 한다.")
        XCTAssertTrue(cap.supportsTransparency)
    }

    func testParseCapabilitiesEpsonTPUHasNoInfrared() {
        // Epson V750: Flatbed|TPU 소스 + film-type. epson2는 IR 미노출 → supportsInfrared=false.
        let dump = """
        All options specific to device `epson2:libusb:001:005':
            --mode Color|Gray|Lineart [Color]
            --source Flatbed|Transparency Unit [Flatbed]
            --film-type Positive Film|Negative Film [Positive Film]
            --depth 8|16 [8]
            --resolution 4800|3200|1600|800dpi [800]
        """
        let cap = SANEBackend.parseCapabilities(dump)
        XCTAssertFalse(cap.supportsInfrared, "epson2는 IR을 노출하지 않으므로 false여야 한다.")
        XCTAssertTrue(cap.supportsTransparency, "Transparency Unit(TPU)이 있으면 투과 지원.")
    }

    func testResolveMediaPicksInfraredSourceWhenRequested() {
        let dump = """
            --mode Color|Gray [Color]
            --source Transparency Adapter|Transparency Adapter Infrared [Transparency Adapter]
        """
        var opts = ScanOptions.strongDefault(scannerID: "sane-genesys:libusb:000:010")
        opts.infraredEnabled = true
        let media = SANEBackend.resolveMedia(dump: dump, options: opts)
        XCTAssertEqual(media.source, "Transparency Adapter Infrared")
        XCTAssertTrue(media.usesInfrared)
    }

    func testResolveMediaEpsonTPUSetsFilmTypeAndNoIR() {
        let dump = """
            --mode Color|Gray [Color]
            --source Flatbed|Transparency Unit [Flatbed]
            --film-type Positive Film|Negative Film [Positive Film]
        """
        var opts = ScanOptions.strongDefault(scannerID: "sane-epson2:libusb:001:005")
        opts.filmType = .colorNegative
        opts.infraredEnabled = true    // epson2엔 IR 소스/모드 없음 → 무시돼야 한다.
        let media = SANEBackend.resolveMedia(dump: dump, options: opts)
        XCTAssertEqual(media.source, "Transparency Unit")
        XCTAssertEqual(media.filmType, "Negative Film")
        XCTAssertFalse(media.usesInfrared, "IR 옵션이 없으면 요청해도 IR로 처리하지 않는다.")
    }

    func testBackendNameParsing() {
        XCTAssertEqual(SANEBackend.backendName(of: "genesys:libusb:000:010"), "genesys")
        XCTAssertEqual(SANEBackend.backendName(of: "epson2:net:192.168.0.2"), "epson2")
    }

}
