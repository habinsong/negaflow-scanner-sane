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
            --contrast -50..50 (in steps of 1) [0]
            --gamma-table 0..65535,... [inactive]
        """
        let cap = SANEBackend.parseCapabilities(dump)
        XCTAssertTrue(cap.supportedResolutions.contains(.r7200))
        XCTAssertTrue(cap.supportedResolutions.contains(.r3600))
        XCTAssertTrue(cap.supportedModes.contains(.color))
        XCTAssertTrue(cap.supportedBitDepths.contains(.sixteen))
        XCTAssertTrue(cap.supportsTransparency)
        XCTAssertFalse(cap.supportsInfrared)   // genesys 비-i 모델은 IR 노출 안 함
        XCTAssertFalse(cap.supportsMultiExposure, "brightness/gamma-table은 센서 노출 브라케팅이 아니다.")
        XCTAssertEqual(cap.sourceModes, ["Transparency Adapter"])
        XCTAssertEqual(cap.transparencyModes, ["Transparency Adapter"])
        XCTAssertEqual(cap.brightnessRange, ScannerOptionRange(minimum: -100, maximum: 100, step: 1))
        XCTAssertEqual(cap.contrastRange, ScannerOptionRange(minimum: -50, maximum: 50, step: 1))
        XCTAssertEqual(cap.disabledReasons?["multiExposure"],
                       "scanimage -A에 --scan-exposure-time이 없어 실제 다중노출을 켤 수 없습니다.")
    }

    func testInactiveOptionsAreNeverAdvertisedOrSent() {
        let dump = """
            --mode Color|Gray [inactive]
            --source Flatbed|Transparency Unit [inactive]
            --preview[=(yes|no)] [inactive]
            --depth 8|16 [inactive]
            --resolution 600|2400dpi [inactive]
            --brightness -100..100 (in steps of 1) [inactive]
            -x 1..36mm [inactive]
            -y 1..24mm [inactive]
        """
        let parsed = SaneOptionDump(dump)
        XCTAssertTrue(parsed.hasOption("source"))
        XCTAssertFalse(parsed.isActive("source"))
        XCTAssertTrue(parsed.enumValues("source").isEmpty)
        XCTAssertNil(parsed.numericRange("brightness"))
        XCTAssertEqual(parsed.resolutionSpec, .none)

        let capabilities = SANEBackend.parseCapabilities(dump)
        XCTAssertTrue(capabilities.supportedModes.isEmpty)
        XCTAssertTrue(capabilities.supportedBitDepths.isEmpty)
        XCTAssertTrue(capabilities.supportedResolutions.isEmpty)
        XCTAssertFalse(capabilities.supportsPreview)
        XCTAssertFalse(capabilities.supportsTransparency)
        XCTAssertFalse(capabilities.supportsScanArea)

        let media = SANEBackend.resolveMedia(
            dump: dump,
            options: .strongDefault(scannerID: "sane-genesys:libusb:000:010")
        )
        XCTAssertNil(media.source)
        XCTAssertNil(media.mode)
        XCTAssertFalse(media.hasPreviewOption)
        XCTAssertFalse(media.hasBrightnessOption)
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
        XCTAssertEqual(cap.hardwareExposureRange, ScannerOptionRange(minimum: 11000, maximum: 65535))
    }

    func testParseCapabilitiesReadsMillimeterGeometryAsMaxScanArea() {
        let dump = """
            --mode Color|Gray [Gray]
            --resolution 7200|3600|600dpi [600]
            -l 0..36.33mm [0]
            -t 0..25mm [0]
            -x 0..36.33mm [36.33]
            -y 0..25mm [25]
        """
        let cap = SANEBackend.parseCapabilities(dump)
        XCTAssertTrue(cap.supportsScanArea)
        XCTAssertEqual(cap.minScanArea.widthMM, 0.1, accuracy: 0.001)
        XCTAssertEqual(cap.minScanArea.heightMM, 0.1, accuracy: 0.001)
        XCTAssertEqual(cap.maxScanArea.widthMM, 36.33, accuracy: 0.001)
        XCTAssertEqual(cap.maxScanArea.heightMM, 25, accuracy: 0.001)
        XCTAssertEqual(cap.scanAreaUnit, .millimeter)
    }

    func testPositionedScanAreaRequiresReflectiveAndTransparencySourcesWithXYOriginControls() {
        let flatbedDump = """
            --mode Color|Gray [Color]
            --source Flatbed|Transparency Unit [Transparency Unit]
            --depth 8|16 [16]
            --resolution 600|2400|4800dpi [600]
            -l 1..215.9mm (in steps of 0.1) [1]
            -t 2..297mm (in steps of 0.1) [2]
            -x 1..215.9mm (in steps of 0.1) [215.9]
            -y 1..297mm (in steps of 0.1) [297]
        """
        let flatbed = SANEBackend.parseCapabilities(flatbedDump)

        XCTAssertTrue(flatbed.supportsPositionedScanArea)
        XCTAssertEqual(
            flatbed.scanOriginXRange,
            ScannerOptionRange(minimum: 1, maximum: 215.9, step: 0.1)
        )
        XCTAssertEqual(
            flatbed.scanWidthRange,
            ScannerOptionRange(minimum: 1, maximum: 215.9, step: 0.1)
        )
        XCTAssertEqual(flatbed.maxScanArea.originXMM, 1, accuracy: 0.001)
        XCTAssertEqual(flatbed.maxScanArea.originYMM, 2, accuracy: 0.001)

        let dedicatedFilmDump = flatbedDump.replacingOccurrences(
            of: "Flatbed|Transparency Unit",
            with: "Transparency Adapter"
        )
        XCTAssertFalse(SANEBackend.parseCapabilities(dedicatedFilmDump).supportsPositionedScanArea)
    }

    func testPositionedScanAreaIsResolvedAndEmittedBeforeSize() throws {
        let dump = """
            --mode Color|Gray [Color]
            --source Flatbed|Transparency Unit [Transparency Unit]
            --depth 8|16 [16]
            --resolution 3600dpi [3600]
            -l 0..215mm (in steps of 0.1) [0]
            -t 0..297mm (in steps of 0.1) [0]
            -x 1..215mm (in steps of 0.1) [215]
            -y 1..297mm (in steps of 0.1) [297]
        """
        var options = ScanOptions.strongDefault(scannerID: "sane-epson2:libusb:001:005")
        options.scanArea = ScanArea(originXMM: 12.5, originYMM: 21.2, widthMM: 36, heightMM: 24)
        let media = SANEBackend.resolveMedia(dump: dump, options: options)

        XCTAssertNoThrow(try SANEBackend.validateExactOptions(options, media: media))
        XCTAssertEqual(media.originXMM, 12.5)
        XCTAssertEqual(media.originYMM, 21.2)
        let args = SANEBackend(scanimagePath: "/tmp/scanimage").makeScanimageArgs(
            devname: "epson2:libusb:001:005",
            options: options,
            media: media
        )
        XCTAssertEqual(argValue(args, "-l"), "12.5")
        XCTAssertEqual(argValue(args, "-t"), "21.2")
        XCTAssertLessThan(try XCTUnwrap(args.firstIndex(of: "--source")), try XCTUnwrap(args.firstIndex(of: "-l")))
        XCTAssertLessThan(try XCTUnwrap(args.firstIndex(of: "-l")), try XCTUnwrap(args.firstIndex(of: "-x")))
    }

    func testSaneScanArgsIncludeHardwareExposureTimeWhenRequested() {
        let backend = SANEBackend(scanimagePath: "/tmp/sane-head-install/bin/scanimage")
        var options = ScanOptions.strongDefault(scannerID: "sane-genesys:libusb:000:010")
        options.bitDepth = .eight
        options.hardwareExposureTime = 30_000
        options.brightnessAdjustment = -12
        options.contrastAdjustment = 8
        let media = SANEBackend.MediaSelection(
            source: "Transparency Adapter", mode: "Color", filmType: nil,
            depthArgument: 8, resolvedDPI: 3600,
            widthMM: 36.33, heightMM: 25,
            hasPreviewOption: true, hasBrightnessOption: true,
            hasContrastOption: true, hasScanExposureOption: true
        )

        let args = backend.makeScanimageArgs(
            devname: "genesys:libusb:000:010",
            options: options,
            media: media
        )

        XCTAssertTrue(args.contains("--scan-exposure-time=30000"))
        XCTAssertTrue(args.contains("-p"))
        XCTAssertTrue(args.contains("--brightness=-12"))
        XCTAssertTrue(args.contains("--contrast=8"))
        XCTAssertTrue(argValue(args, "--source") == "Transparency Adapter")
        XCTAssertTrue(argValue(args, "--mode") == "Color")
        XCTAssertEqual(argValue(args, "-x"), "36.33")
        XCTAssertEqual(argValue(args, "-y"), "25")
    }

    func testGenesysSixteenBitOmitsEightBitOnlyToneAdjustments() throws {
        let dump = """
            --mode Color|Gray [Color]
            --source Transparency Adapter [Transparency Adapter]
            --depth 8|16 [8]
            --brightness -100..100 (in steps of 1) [0]
            --contrast -100..100 (in steps of 1) [0]
            --resolution 3600dpi [3600]
            --preview[=(yes|no)] [no]
            -l 0..36mm [0]
            -t 0..24mm [0]
            -x 1..36mm [36]
            -y 1..24mm [24]
        """
        var options = ScanOptions.strongDefault(scannerID: "sane-genesys:libusb:000:010")
        options.bitDepth = .sixteen
        options.resolution = Resolution(3600)
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        let media = SANEBackend.resolveMedia(dump: dump, options: options)

        XCTAssertFalse(media.hasBrightnessOption)
        XCTAssertFalse(media.hasContrastOption)
        XCTAssertNil(media.brightnessRange)
        XCTAssertNil(media.contrastRange)
        XCTAssertNoThrow(try SANEBackend.validateExactOptions(options, media: media))

        let args = SANEBackend(scanimagePath: "/tmp/scanimage").makeScanimageArgs(
            devname: "genesys:libusb:000:010",
            options: options,
            media: media
        )
        XCTAssertFalse(args.contains { $0.hasPrefix("--brightness") })
        XCTAssertFalse(args.contains { $0.hasPrefix("--contrast") })

        options.brightnessAdjustment = 1
        XCTAssertThrowsError(try SANEBackend.validateExactOptions(options, media: media))
    }

    func testScanimageProgressParserHandlesCarriageReturnAndFractionalPercent() {
        XCTAssertEqual(SANEBackend.scanimageProgressFraction(in: "Progress: 32%\r") ?? -1, 0.32, accuracy: 0.0001)
        XCTAssertEqual(SANEBackend.scanimageProgressFraction(in: "noise\rProgress: 87.5%\r") ?? -1, 0.875, accuracy: 0.0001)
        XCTAssertNil(SANEBackend.scanimageProgressFraction(in: "warming lamp"))
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
        // Epson V750(stock 빌드): Flatbed|TPU 소스 + film-type. IR 모드는 미노출 → false.
        let dump = """
        All options specific to device `epson2:libusb:001:005':
            --mode Color|Gray|Lineart [Color]
            --source Flatbed|Transparency Unit [Flatbed]
            --film-type Positive Film|Negative Film [Positive Film]
            --depth 8|16 [8]
            --resolution 4800|3200|1600|800dpi [800]
        """
        let cap = SANEBackend.parseCapabilities(dump)
        XCTAssertFalse(cap.supportsInfrared, "epson2 stock 빌드는 IR을 노출하지 않으므로 false여야 한다.")
        XCTAssertTrue(cap.supportsTransparency, "Transparency Unit(TPU)이 있으면 투과 지원.")
    }

    func testParseCapabilitiesEpsonCustomBuildDetectsInfraredMode() {
        // SANE_FRAME_IR 커스텀 빌드의 epson2(GT-X800/GT-X900/GT-X980): --mode 에 Infrared 노출.
        let dump = """
            --mode Lineart|Gray|Color|Infrared [Color]
            --source Flatbed|Transparency Unit|TPU8x10 [Flatbed]
            --film-type Positive Film|Negative Film [Positive Film]
            --depth 8|16 [8]
            --resolution 4800|6400dpi [800]
        """
        let cap = SANEBackend.parseCapabilities(dump)
        XCTAssertTrue(cap.supportsInfrared)
        XCTAssertFalse(cap.supportedModes.contains(.infrared), "IR은 primary color mode가 아니라 별도 채널 capability다.")
        XCTAssertEqual(cap.transparencyModes, ["Transparency Unit", "TPU8x10"], "TPU8x10 도 투과 소스다.")
    }

    func testParseCapabilitiesCoolscanDoesNotExposeRGBIAsSeparateInfraredTIFF() {
        // sane-coolscan3(Nikon LS-50 ED): --source/--mode 없음, --infrared bool, depth 8|14, pel 지오메트리.
        let dump = """
        All options specific to device `coolscan3:usb:libusb:001:002':
            --infrared[=(yes|no)] [no]
            --depth 8|14 [8]
            --resolution 4000|2000|1333|1000|800|667|571|500dpi [4000]
            --preview[=(yes|no)] [no]
            --negative[=(yes|no)] [no]
            -l 0..5959pel [0]
            -t 0..3946pel [0]
            -x 0..5959pel [5959]
            -y 0..3946pel [3946]
        """
        let cap = SANEBackend.parseCapabilities(
            dump,
            deviceTypeHint: "film scanner",
            backendHint: "coolscan3"
        )
        XCTAssertFalse(cap.supportsInfrared, "stock scanimage가 RGBI 프레임을 별도 IR TIFF로 분리하지 못합니다.")
        XCTAssertTrue(cap.disabledReasons?["infrared"]?.contains("RGBI") == true)
        XCTAssertTrue(cap.supportsTransparency, "--source 가 없는 전용 필름 스캐너는 투과 전용 장치다.")
        XCTAssertEqual(cap.supportedBitDepths, [.eight, .sixteen], "depth 14는 16bit 컨테이너로 전달된다.")
        XCTAssertTrue(cap.supportedResolutions.contains(Resolution(4000)))
        XCTAssertEqual(cap.scanAreaUnit, .pixel)
        XCTAssertFalse(cap.supportsScanArea, "pel 단위 범위를 mm scanArea capability로 보고하면 안 된다.")
        XCTAssertFalse(cap.supportsMultiExposure)
    }

    func testParseCapabilitiesPieusbDetectsCleanImage() {
        // sane-pieusb(Reflecta ProScan 7200): RGBI 모드 + clean-image(백엔드 내부 IR 먼지 제거).
        let dump = """
            --mode Lineart|Halftone|Gray|Color|RGBI [Color]
            --depth 1|8|16 [8]
            --resolution 900|1800|3600|7200dpi [900]
            --clean-image[=(yes|no)] [no]
            --correct-infrared[=(yes|no)] [no]
            --fast-infrared[=(yes|no)] [no]
        """
        let cap = SANEBackend.parseCapabilities(dump, deviceTypeHint: "slide scanner")
        XCTAssertFalse(cap.supportsInfrared, "--clean-image는 별도 IR 채널을 반환하지 않는다.")
        XCTAssertEqual(
            cap.disabledReasons?["infrared"],
            "--clean-image는 별도 IR 채널을 반환하지 않아 IR 채널 기능으로 사용할 수 없습니다."
        )
        XCTAssertTrue(cap.supportsTransparency, "소스 없는 슬라이드 스캐너는 투과 전용.")
        XCTAssertTrue(cap.supportedModes.contains(.color))
    }

    func testParseCapabilitiesResolutionRangeProducesUsableList() {
        // 일부 백엔드(avision 등)는 해상도를 범위로 노출한다.
        let dump = """
            --mode Color|Gray [Color]
            --resolution 50..6400dpi (in steps of 1) [300]
            --source Flatbed|Transparency Unit [Flatbed]
        """
        let cap = SANEBackend.parseCapabilities(dump)
        XCTAssertTrue(cap.supportedResolutions.contains(Resolution(6400)), "범위 최대값은 반드시 포함.")
        XCTAssertTrue(cap.supportedResolutions.contains(Resolution(2400)))
        XCTAssertTrue(cap.supportedResolutions.contains(.r3600))
        XCTAssertFalse(cap.supportedResolutions.contains(Resolution(7200)), "범위 밖 값은 제외.")
    }

    // MARK: - resolveMedia

    func testResolveMediaKeepsRGBSourceAndPlansInfraredSourcePass() {
        // genesys "i": IR을 켜도 본 스캔은 일반 투과 소스로, IR은 별도 패스로 계획해야 한다.
        let dump = """
            --mode Color|Gray [Color]
            --source Transparency Adapter|Transparency Adapter Infrared [Transparency Adapter]
            --depth 16 [16]
            --resolution 7200|3600|1800|900dpi [3600]
        """
        var opts = ScanOptions.strongDefault(scannerID: "sane-genesys:libusb:000:010")
        opts.infraredEnabled = true
        let media = SANEBackend.resolveMedia(dump: dump, options: opts)
        XCTAssertEqual(media.source, "Transparency Adapter", "본 스캔 소스는 IR이 아닌 투과 소스여야 한다.")
        XCTAssertEqual(media.irStrategy, .separateSource("Transparency Adapter Infrared"))
        XCTAssertEqual(media.irPassMode, "Gray", "IR 패스는 단채널이므로 Gray 모드를 우선한다.")
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
        opts.infraredEnabled = true    // stock epson2엔 IR 소스/모드 없음 → 무시돼야 한다.
        let media = SANEBackend.resolveMedia(dump: dump, options: opts)
        XCTAssertEqual(media.source, "Transparency Unit")
        XCTAssertEqual(media.filmType, "Negative Film")
        XCTAssertEqual(media.irStrategy, .none, "IR 옵션이 없으면 요청해도 IR로 처리하지 않는다.")
    }

    func testResolveMediaEpsonPositiveUsesSlideAndNegativeUsesFilm() {
        let dump = """
            --mode Color [Color]
            --source Flatbed|TPU8x10 [TPU8x10]
            --film-type Positive Film|Negative Film|Positive Slide|Negative Slide [Positive Film]
        """
        var positive = ScanOptions.strongDefault(scannerID: "sane-epson2:libusb:001:005")
        positive.filmType = .colorPositive
        XCTAssertEqual(
            SANEBackend.resolveMedia(dump: dump, options: positive).filmType,
            "Positive Slide"
        )

        var negative = positive
        negative.filmType = .colorNegative
        XCTAssertEqual(
            SANEBackend.resolveMedia(dump: dump, options: negative).filmType,
            "Negative Film"
        )
    }

    func testLegacyCoolscanUsesSlideSourceWithoutHardwareInversion() {
        let dump = """
            --mode Color|Gray [Color]
            --source Slide|Automatic Slide Feeder [Slide]
            --type Positive|Negative [Positive]
            --depth 8|10 [8]
            --resolution 2700dpi [2700]
            --preview[=(yes|no)] [no]
            -l 0..2700pel [0]
            -t 0..1800pel [0]
            -x 1..2700pel [2700]
            -y 1..1800pel [1800]
        """
        var options = ScanOptions.strongDefault(scannerID: "sane-coolscan:scsi:/dev/sg0")
        options.filmType = .colorNegative
        options.resolution = Resolution(2700)
        options.scanArea = ScanArea(widthMM: 25.4, heightMM: 16.9333333333)
        let media = SANEBackend.resolveMedia(
            dump: dump,
            options: options,
            deviceTypeHint: "film scanner"
        )
        XCTAssertEqual(media.source, "Slide")
        XCTAssertEqual(media.filmTypeOptionName, "type")
        XCTAssertEqual(media.filmType, "Positive")

        let args = SANEBackend(scanimagePath: "/tmp/scanimage").makeScanimageArgs(
            devname: "coolscan:scsi:/dev/sg0",
            options: options,
            media: media
        )
        XCTAssertEqual(argValue(args, "--source"), "Slide")
        XCTAssertEqual(argValue(args, "--type"), "Positive")
        XCTAssertEqual(argValue(args, "--resolution"), "2700")
        XCTAssertEqual(argValue(args, "--depth"), "10")
        XCTAssertEqual(argValue(args, "-l"), "0")
        XCTAssertEqual(argValue(args, "-t"), "0")
        XCTAssertEqual(argValue(args, "-x"), "2700")
        XCTAssertEqual(argValue(args, "-y"), "1800")
        XCTAssertFalse(args.contains("Automatic Slide Feeder"))
    }

    func testCoolscan2PreservesDepthResolutionAndCornerGeometry() throws {
        let dump = """
            --preview[=(yes|no)] [no]
            --negative[=(yes|no)] [inactive]
            --infrared[=(yes|no)] [no]
            --depth 8|14 [8]
            --resolution 4000|2000|1000dpi [4000]
            --tl-x 0..5959pel [0]
            --tl-y 0..3946pel [0]
            --br-x 0..5959pel [5959]
            --br-y 0..3946pel [3946]
        """
        var options = ScanOptions.strongDefault(
            scannerID: "sane-coolscan2:usb:libusb:001:4000"
        )
        options.resolution = Resolution(4000)
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        let media = SANEBackend.resolveMedia(
            dump: dump,
            options: options,
            deviceTypeHint: "film scanner"
        )

        XCTAssertNil(media.filmTypeOptionName)
        XCTAssertEqual(media.depthArgument, 14)
        XCTAssertNoThrow(try SANEBackend.validateExactOptions(options, media: media))

        let args = SANEBackend(scanimagePath: "/tmp/scanimage").makeScanimageArgs(
            devname: "coolscan2:usb:libusb:001:4000",
            options: options,
            media: media
        )
        XCTAssertEqual(argValue(args, "--resolution"), "4000")
        XCTAssertEqual(argValue(args, "--depth"), "14")
        XCTAssertEqual(argValue(args, "--tl-x"), "0")
        XCTAssertEqual(argValue(args, "--tl-y"), "0")
        XCTAssertEqual(argValue(args, "--br-x"), "5668")
        XCTAssertEqual(argValue(args, "--br-y"), "3779")
        XCTAssertFalse(args.contains { $0.hasPrefix("--negative") })
        XCTAssertFalse(args.contains("--infrared"))
    }

    func testCoolscan3DisablesHardwareInversionWithEqualsSyntax() {
        let dump = """
            --negative[=(yes|no)] [no]
            --depth 8|14 [8]
            --resolution 4000dpi [4000]
            --tl-x 0..5959pel [0]
            --tl-y 0..3946pel [0]
            --br-x 0..5959pel [5959]
            --br-y 0..3946pel [3946]
        """
        var options = ScanOptions.strongDefault(
            scannerID: "sane-coolscan3:usb:libusb:001:4001"
        )
        options.filmType = .colorNegative
        options.resolution = Resolution(4000)
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        let media = SANEBackend.resolveMedia(
            dump: dump,
            options: options,
            deviceTypeHint: "film scanner"
        )

        XCTAssertEqual(media.filmTypeOptionName, "negative")
        XCTAssertEqual(media.filmType, "no")
        let args = SANEBackend(scanimagePath: "/tmp/scanimage").makeScanimageArgs(
            devname: "coolscan3:usb:libusb:001:4001",
            options: options,
            media: media
        )
        XCTAssertTrue(args.contains("--negative=no"))

        options.filmType = .colorPositive
        let positiveMedia = SANEBackend.resolveMedia(
            dump: dump,
            options: options,
            deviceTypeHint: "film scanner"
        )
        let positiveArgs = SANEBackend(scanimagePath: "/tmp/scanimage").makeScanimageArgs(
            devname: "coolscan3:usb:libusb:001:4001",
            options: options,
            media: positiveMedia
        )
        XCTAssertTrue(positiveArgs.contains("--negative=no"))
    }

    func testCombinedMillimeterGeometryRejectsAreaPastSurfaceEdge() {
        let dump = """
            --mode Color [Color]
            --source Flatbed|TPU8x10 [TPU8x10]
            --depth 16 [16]
            --resolution 3200dpi [3200]
            -l 0..215.9mm (in steps of 0.1) [0]
            -t 0..297.1mm (in steps of 0.1) [0]
            -x 1..203.2mm (in steps of 0.1) [203.2]
            -y 1..254mm (in steps of 0.1) [254]
        """
        var options = ScanOptions.strongDefault(scannerID: "sane-epson2:libusb:001:005")
        options.resolution = Resolution(3200)
        options.scanArea = ScanArea(originXMM: 200, originYMM: 0, widthMM: 20, heightMM: 24)
        let media = SANEBackend.resolveMedia(dump: dump, options: options)
        XCTAssertThrowsError(try SANEBackend.validateExactOptions(options, media: media)) { error in
            XCTAssertTrue((error as? ScannerError)?.message.contains("원점+폭") == true)
        }

        options.scanArea = ScanArea(originXMM: 200, originYMM: 0, widthMM: 10, heightMM: 24)
        let narrowerMedia = SANEBackend.resolveMedia(dump: dump, options: options)
        XCTAssertThrowsError(try SANEBackend.validateExactOptions(options, media: narrowerMedia)) { error in
            XCTAssertTrue((error as? ScannerError)?.message.contains("원점+폭") == true)
        }

        options.scanArea = ScanArea(originXMM: 0, originYMM: 240, widthMM: 36, heightMM: 20)
        let lowerMedia = SANEBackend.resolveMedia(dump: dump, options: options)
        XCTAssertThrowsError(try SANEBackend.validateExactOptions(options, media: lowerMedia)) { error in
            XCTAssertTrue((error as? ScannerError)?.message.contains("원점+높이") == true)
        }

        options.scanArea = ScanArea(originXMM: 0, originYMM: 240, widthMM: 36, heightMM: 10)
        let inBoundsMedia = SANEBackend.resolveMedia(dump: dump, options: options)
        XCTAssertNoThrow(try SANEBackend.validateExactOptions(options, media: inBoundsMedia))
    }

    func testResolveMediaEpsonCustomBuildPlansInfraredModePass() {
        let dump = """
            --mode Lineart|Gray|Color|Infrared [Color]
            --source Flatbed|Transparency Unit [Flatbed]
            --film-type Positive Film|Negative Film [Positive Film]
            --depth 8|16 [8]
        """
        var opts = ScanOptions.strongDefault(scannerID: "sane-epson2:libusb:001:005")
        opts.infraredEnabled = true
        let media = SANEBackend.resolveMedia(dump: dump, options: opts)
        XCTAssertEqual(media.mode, "Color", "본 스캔 모드는 Color 유지.")
        XCTAssertEqual(media.irStrategy, .separateMode("Infrared"))
    }

    func testResolveMediaCoolscanDoesNotClaimRGBIAsSeparateInfraredFile() {
        let dump = """
            --infrared[=(yes|no)] [no]
            --depth 8|14 [8]
            --resolution 4000|2000|1333|1000dpi [4000]
            --preview[=(yes|no)] [no]
            -x 0..5959pel [5959]
            -y 0..3946pel [3946]
        """
        var opts = ScanOptions.strongDefault(scannerID: "sane-coolscan3:usb:libusb:001:002")
        opts.infraredEnabled = true
        opts.bitDepth = .sixteen
        opts.resolution = Resolution(3600)
        let media = SANEBackend.resolveMedia(dump: dump, options: opts)
        XCTAssertNil(media.source, "--source 옵션이 없으면 전달하지 않는다.")
        XCTAssertNil(media.mode, "--mode 옵션이 없으면 전달하지 않는다.")
        XCTAssertEqual(media.depthArgument, 14, "16을 받지 않는 장치는 최대 깊이(14)로 스냅.")
        XCTAssertNil(media.resolvedDPI, "목록에 없는 3600dpi를 4000dpi로 무단 변환하면 안 된다.")
        XCTAssertNil(media.widthMM, "pel(픽셀) 단위 지오메트리에는 mm 값을 전달하지 않는다.")
        XCTAssertEqual(media.irStrategy, .none)
        XCTAssertThrowsError(try SANEBackend.validateExactOptions(opts, media: media)) { error in
            XCTAssertTrue(error.localizedDescription.contains("resolution 3600dpi"))
        }
    }

    func testResolveMediaPieusbUsesCleanImage() {
        let dump = """
            --mode Lineart|Halftone|Gray|Color|RGBI [Color]
            --depth 1|8|16 [8]
            --resolution 900|1800|3600|7200dpi [900]
            --clean-image[=(yes|no)] [no]
        """
        var opts = ScanOptions.strongDefault(scannerID: "sane-pieusb:libusb:001:008")
        opts.infraredEnabled = true
        let media = SANEBackend.resolveMedia(dump: dump, options: opts)
        XCTAssertEqual(media.mode, "Color")
        XCTAssertEqual(media.irStrategy, .none, "별도 IR 파일을 만들지 않는 clean-image는 v2 IR 요청에 쓰지 않는다.")
    }

    func testPiePreservesFixedDepthResolutionAndMillimeterGeometry() throws {
        let dump = """
            --mode Color|Gray [Color]
            --resolution 300|600|1200dpi [600]
            --preview[=(yes|no)] [no]
            -l 0..36mm [0]
            -t 0..24mm [0]
            -x 1..36mm [36]
            -y 1..24mm [24]
        """
        var options = ScanOptions.strongDefault(scannerID: "sane-pie:scsi:/dev/sg0")
        options.bitDepth = .eight
        options.resolution = Resolution(600)
        options.scanArea = ScanArea(
            originXMM: 1,
            originYMM: 2,
            widthMM: 35,
            heightMM: 22
        )
        let media = SANEBackend.resolveMedia(
            dump: dump,
            options: options,
            deviceTypeHint: "film scanner"
        )

        XCTAssertEqual(media.fixedDepth, .eight)
        XCTAssertNoThrow(try SANEBackend.validateExactOptions(options, media: media))

        let args = SANEBackend(scanimagePath: "/tmp/scanimage").makeScanimageArgs(
            devname: "pie:scsi:/dev/sg0",
            options: options,
            media: media
        )
        XCTAssertEqual(argValue(args, "--mode"), "Color")
        XCTAssertEqual(argValue(args, "--resolution"), "600")
        XCTAssertNil(argValue(args, "--depth"))
        XCTAssertEqual(argValue(args, "-l"), "1")
        XCTAssertEqual(argValue(args, "-t"), "2")
        XCTAssertEqual(argValue(args, "-x"), "35")
        XCTAssertEqual(argValue(args, "-y"), "22")
    }

    func testResolveMediaDoesNotGuessGenesysOptionsWhenDumpUnavailable() {
        var opts = ScanOptions.strongDefault(scannerID: "sane-genesys:libusb:000:010")
        opts.resolution = .r3600
        let media = SANEBackend.resolveMedia(dump: "", options: opts)
        XCTAssertNil(media.source)
        XCTAssertNil(media.mode)
        XCTAssertNil(media.depthArgument)
        XCTAssertNil(media.resolvedDPI)
    }

    func testSinglePassOptionReuseIsLimitedToDedicatedGenesysFilmSources() {
        let opticFilm = """
        --source Transparency Adapter|Transparency Adapter Infrared [Transparency Adapter]
        --mode Color|Gray [Color]
        """
        let flatbedWithTPU = """
        --source Flatbed|Transparency Unit [Flatbed]
        --mode Color|Gray [Color]
        """

        XCTAssertTrue(SANEBackend.canReuseSinglePassOptionsDump(opticFilm, backend: "genesys"))
        XCTAssertFalse(SANEBackend.canReuseSinglePassOptionsDump(flatbedWithTPU, backend: "genesys"))
        XCTAssertFalse(SANEBackend.canReuseSinglePassOptionsDump(opticFilm, backend: "epson2"))
    }

    func testResolveMediaNonGenesysFallbackOmitsRiskyFlags() {
        var opts = ScanOptions.strongDefault(scannerID: "sane-coolscan3:usb:libusb:001:002")
        opts.resolution = .r3600
        let media = SANEBackend.resolveMedia(dump: "", options: opts)
        XCTAssertNil(media.source)
        XCTAssertNil(media.mode)
        XCTAssertNil(media.depthArgument)
        XCTAssertNil(media.widthMM)
    }

    // MARK: - 인자 생성 (패스별)

    func testScanArgsOmitFlagsThatDeviceDoesNotExpose() {
        let backend = SANEBackend(scanimagePath: "/tmp/scanimage")
        var options = ScanOptions.strongDefault(scannerID: "sane-coolscan3:usb:libusb:001:002")
        options.brightnessAdjustment = -12   // coolscan3 에는 --brightness 없음 → 생략돼야 한다.
        let media = SANEBackend.MediaSelection(
            source: nil, mode: nil, filmType: nil,
            depthArgument: 14, resolvedDPI: 4000,
            widthMM: nil, heightMM: nil
        )
        let args = backend.makeScanimageArgs(devname: "coolscan3:usb:libusb:001:002", options: options, media: media)
        XCTAssertFalse(args.contains("--mode"))
        XCTAssertFalse(args.contains("--source"))
        XCTAssertFalse(args.contains { $0.hasPrefix("--brightness") })
        XCTAssertFalse(args.contains("-x"))
        XCTAssertEqual(argValue(args, "--depth"), "14")
        XCTAssertEqual(argValue(args, "--resolution"), "4000")
        XCTAssertTrue(args.contains("--format=tiff"))
    }

    func testInfraredPassArgsSwapSourceAndUseGrayMode() {
        let backend = SANEBackend(scanimagePath: "/tmp/scanimage")
        let options = ScanOptions.strongDefault(scannerID: "sane-genesys:libusb:000:010")
        var media = SANEBackend.MediaSelection(
            source: "Transparency Adapter", mode: "Color", filmType: nil,
            depthArgument: 16, resolvedDPI: 3600,
            widthMM: 36.33, heightMM: 25
        )
        media.irStrategy = .separateSource("Transparency Adapter Infrared")
        media.irPassMode = "Gray"

        let args = backend.makeScanimageArgs(
            devname: "genesys:libusb:000:010", options: options, media: media, pass: .infrared
        )
        XCTAssertEqual(argValue(args, "--source"), "Transparency Adapter Infrared")
        XCTAssertEqual(argValue(args, "--mode"), "Gray")
        XCTAssertEqual(argValue(args, "--resolution"), "3600", "IR 패스는 본 스캔과 같은 해상도여야 먼지 맵이 정렬된다.")
        XCTAssertEqual(argValue(args, "-x"), "36.33")
    }

    func testCleanImageArgsAddedInline() {
        let backend = SANEBackend(scanimagePath: "/tmp/scanimage")
        let options = ScanOptions.strongDefault(scannerID: "sane-pieusb:libusb:001:008")
        var media = SANEBackend.MediaSelection(
            source: nil, mode: "Color", filmType: nil,
            depthArgument: 16, resolvedDPI: 3600,
            widthMM: nil, heightMM: nil
        )
        media.irStrategy = .cleanImage(optionName: "clean-image")
        media.hasAdvanceOption = true
        let args = backend.makeScanimageArgs(devname: "pieusb:libusb:001:008", options: options, media: media)
        XCTAssertTrue(args.contains("--clean-image=yes"))
        XCTAssertTrue(args.contains("--advance=no"))
    }

    func testEpson2ArgsDisableBuiltInColorAndGammaProcessing() throws {
        let dump = """
        --mode Color|Gray [Color]
        --source Flatbed|TPU8x10 [TPU8x10]
        --depth 8|16 [16]
        --resolution 3600dpi [3600]
        --film-type Positive Film|Negative Film|Positive Slide|Negative Slide [Positive Film]
        --gamma-correction Default|User defined|High density printing [Default]
        --color-correction None|Built in CCT profile|User defined CCT profile [Built in CCT profile]
        -l 0..215.9mm (in steps of 0.1) [0]
        -t 0..297.1mm (in steps of 0.1) [0]
        -x 1..203.2mm (in steps of 0.1) [203.2]
        -y 1..254mm (in steps of 0.1) [254]
        """
        var options = ScanOptions.strongDefault(scannerID: "sane-epson2:libusb:002:002")
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        let media = SANEBackend.resolveMedia(dump: dump, options: options)
        XCTAssertEqual(media.colorCorrection, "None")
        XCTAssertEqual(media.gammaCorrection, "User defined")
        XCTAssertNoThrow(try SANEBackend.validateExactOptions(options, media: media))

        let args = SANEBackend(scanimagePath: "/tmp/scanimage").makeScanimageArgs(
            devname: "epson2",
            options: options,
            media: media
        )
        XCTAssertEqual(argValue(args, "--color-correction"), "None")
        XCTAssertEqual(argValue(args, "--gamma-correction"), "User defined")
    }

    func testEpson2GrayOmitsInactiveColorCorrection() throws {
        let dump = """
        --mode Color|Gray [Gray]
        --source Flatbed|TPU8x10 [TPU8x10]
        --depth 8|16 [16]
        --resolution 3600dpi [3600]
        --gamma-correction Default|User defined [User defined]
        --color-correction None|Built in CCT profile [inactive]
        --brightness -4..3 [inactive]
        -l 0..215.9mm [0]
        -t 0..297.1mm [0]
        -x 1..203.2mm [203.2]
        -y 1..254mm [254]
        """
        var options = ScanOptions.strongDefault(scannerID: "sane-epson2:libusb:002:002")
        options.colorMode = .gray
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        let media = SANEBackend.resolveMedia(dump: dump, options: options)
        XCTAssertNil(media.colorCorrection)
        XCTAssertEqual(media.gammaCorrection, "User defined")
        XCTAssertNoThrow(try SANEBackend.validateExactOptions(options, media: media))

        let args = SANEBackend(scanimagePath: "/tmp/scanimage").makeScanimageArgs(
            devname: "epson2",
            options: options,
            media: media
        )
        XCTAssertNil(argValue(args, "--color-correction"))
        XCTAssertEqual(argValue(args, "--gamma-correction"), "User defined")
        XCTAssertFalse(args.contains { $0.hasPrefix("--brightness") })
    }

    func testEpson2PrefersExplicitGammaOnePointZero() {
        let dump = """
        --mode Color [Color]
        --source TPU8x10 [TPU8x10]
        --depth 16 [16]
        --resolution 3600dpi [3600]
        --gamma-correction User defined (Gamma=1.0)|User defined (Gamma=1.8) [User defined (Gamma=1.8)]
        -l 0..215.9mm [0]
        -t 0..297.1mm [0]
        -x 1..203.2mm [203.2]
        -y 1..254mm [254]
        """
        var options = ScanOptions.strongDefault(scannerID: "sane-epson2:libusb:002:002")
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        let media = SANEBackend.resolveMedia(dump: dump, options: options)
        XCTAssertEqual(media.gammaCorrection, "User defined (Gamma=1.0)")
    }

    // MARK: - 장치 목록(-L) 파싱

    func testParseDeviceListHandlesMultipleVendorsAndTypes() {
        let out = """
        device `genesys:libusb:000:010' is a PLUSTEK OpticFilm 8100 flatbed scanner
        device `epson2:libusb:001:005' is a Epson GT-X970 flatbed scanner
        device `coolscan3:usb:libusb:001:002' is a Nikon LS-50 ED film scanner
        device `pieusb:libusb:001:008' is a PIE/Reflecta ProScan 7200 slide scanner
        device `pixma:04A91749' is a CANON Canon PIXMA MP560 multi-function peripheral
        """
        let devices = SANEBackend.parseDeviceList(out)
        XCTAssertEqual(devices.count, 5)
        XCTAssertEqual(devices[0].vendor, "PLUSTEK")
        XCTAssertEqual(devices[0].model, "OpticFilm 8100")
        XCTAssertEqual(devices[0].deviceType, "flatbed scanner")
        XCTAssertEqual(devices[2].devname, "coolscan3:usb:libusb:001:002")
        XCTAssertEqual(devices[2].vendor, "Nikon")
        XCTAssertEqual(devices[2].model, "LS-50 ED")
        XCTAssertEqual(devices[2].deviceType, "film scanner")
        XCTAssertEqual(devices[3].vendor, "PIE/Reflecta")
        XCTAssertEqual(devices[3].model, "ProScan 7200")
        XCTAssertEqual(devices[4].deviceType, "multi-function peripheral")
    }

    func testBackendNameParsing() {
        XCTAssertEqual(SANEBackend.backendName(of: "genesys:libusb:000:010"), "genesys")
        XCTAssertEqual(SANEBackend.backendName(of: "epson2:net:192.168.0.2"), "epson2")
        XCTAssertEqual(SANEBackend.backendName(of: "coolscan3:usb:libusb:001:002"), "coolscan3")
    }

    // MARK: - 해상도 스냅

    func testSnapResolutionListPicksNearestPreferringHigherOnTie() {
        let spec = SaneOptionDump.ResolutionSpec.list([500, 667, 1000, 1333, 2000, 4000])
        XCTAssertEqual(SaneOptionDump.snapResolution(3600, to: spec), 4000)
        XCTAssertEqual(SaneOptionDump.snapResolution(4000, to: spec), 4000)
        XCTAssertEqual(SaneOptionDump.snapResolution(100, to: spec), 500)
    }

    func testSnapResolutionRangeClamps() {
        let spec = SaneOptionDump.ResolutionSpec.range(min: 50, max: 6400)
        XCTAssertEqual(SaneOptionDump.snapResolution(7200, to: spec), 6400)
        XCTAssertEqual(SaneOptionDump.snapResolution(3600, to: spec), 3600)
        XCTAssertEqual(SaneOptionDump.snapResolution(10, to: spec), 50)
    }

    /// IR 패스는 그림이 아니라 측정값이다. 장치 기본 감마로 찍히면 신호가 흰쪽 끝에 몰려
    /// 잘리고(GT-X900 실측: 프레임의 2~3.4%가 65535 에 고정), 초점면이 다르면 결함 지도가
    /// 결함 옆에 놓인다. 두 값은 본 스캔과 반드시 같아야 한다.
    func testInfraredPassInheritsGammaTableAndFocusFromMainPass() {
        let dump = """
        All options specific to device `epson2:libusb:000:010':
            --mode Lineart|Gray|Color|Infrared [Lineart]
            --depth 8|12|14|16bit [16]
            --gamma-correction Default|User defined|High density printing [Default]
            --color-correction None|Built in CCT profile|User defined CCT profile [Built in CCT profile]
            --resolution 50|100|1200|2400|3200|4800|6400dpi [25]
            --focus 0..254 [89]
            --autofocus[=(yes|no)] [no]
            --source Flatbed|Transparency Unit|TPU8x10 [Transparency Unit]
            --film-type Positive Film|Negative Film|Positive Slide|Negative Slide [Positive Film]
            -l 0..215.9mm [0]
            -t 0..297.18mm [0]
            -x 0..215.9mm [215.9]
            -y 0..297.18mm [297.18]
        """
        var options = ScanOptions.strongDefault(scannerID: "sane-epson2:libusb:000:010")
        options.filmType = .colorNegative
        options.resolution = Resolution(2400)
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        options.infraredEnabled = true
        options.focus = .manual(72)
        let media = SANEBackend.resolveMedia(
            dump: dump, options: options, deviceTypeHint: "flatbed"
        )
        XCTAssertEqual(media.irStrategy, .separateMode("Infrared"))

        let backend = SANEBackend(scanimagePath: "/tmp/scanimage")
        let main = backend.makeScanimageArgs(
            devname: "epson2:libusb:000:010", options: options, media: media, pass: .main
        )
        let infrared = backend.makeScanimageArgs(
            devname: "epson2:libusb:000:010", options: options, media: media, pass: .infrared
        )

        XCTAssertEqual(argValue(main, "--mode"), "Color")
        XCTAssertEqual(argValue(infrared, "--mode"), "Infrared")
        // 같아야 하는 것: 감마 테이블, 초점, 지오메트리/해상도/깊이.
        XCTAssertEqual(argValue(infrared, "--gamma-correction"), "User defined")
        XCTAssertEqual(argValue(infrared, "--gamma-correction"),
                       argValue(main, "--gamma-correction"))
        XCTAssertTrue(infrared.contains("--focus=72"))
        XCTAssertTrue(infrared.contains("--autofocus=no"))
        XCTAssertEqual(argValue(infrared, "--resolution"), argValue(main, "--resolution"))
        XCTAssertEqual(argValue(infrared, "--depth"), argValue(main, "--depth"))
        for flag in ["-l", "-t", "-x", "-y"] {
            XCTAssertEqual(argValue(infrared, flag), argValue(main, flag), "\(flag) 불일치")
        }
        // 달라야 하는 것: 그림 쪽 보정은 IR 측정에 얹지 않는다.
        XCTAssertNil(argValue(infrared, "--color-correction"))
        XCTAssertNil(argValue(infrared, "--film-type"))
    }

    func testAutofocusRequestReachesBothPasses() {
        let dump = """
            --mode Gray|Color|Infrared [Color]
            --depth 16 [16]
            --gamma-correction Default|User defined [Default]
            --resolution 2400|3200dpi [2400]
            --focus 0..254 [89]
            --autofocus[=(yes|no)] [no]
            --source Flatbed|Transparency Unit [Transparency Unit]
            -l 0..215.9mm [0]
            -t 0..297.18mm [0]
            -x 0..215.9mm [215.9]
            -y 0..297.18mm [297.18]
        """
        var options = ScanOptions.strongDefault(scannerID: "sane-epson2:libusb:000:010")
        options.resolution = Resolution(2400)
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        options.infraredEnabled = true
        options.focus = .auto
        let media = SANEBackend.resolveMedia(
            dump: dump, options: options, deviceTypeHint: "flatbed"
        )
        let infrared = SANEBackend(scanimagePath: "/tmp/scanimage").makeScanimageArgs(
            devname: "epson2:libusb:000:010", options: options, media: media, pass: .infrared
        )
        XCTAssertTrue(infrared.contains("--autofocus=yes"))
    }
}
