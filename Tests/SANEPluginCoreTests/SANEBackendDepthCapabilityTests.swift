import XCTest
@testable import SANEPluginCore

/// 심도(`--depth`) capability 회귀 테스트.
///
/// 아래 두 덤프는 Epson GT-X980(= V850, epson2 백엔드) 실기에서 받은 `scanimage -A` 출력이다.
/// 모드를 적용하지 않은 상태에서는 `--depth`가 비활성이라 지원 심도가 통째로 비어 보이고,
/// 그 상태의 capability를 앱에 넘기면 심도 선택·프리뷰·스캔이 모두 잠긴다.
final class SANEBackendDepthCapabilityTests: XCTestCase {

    /// `--source TPU8x10`만 적용한 상태(기본 모드 Lineart).
    private let lineartDefaultDump = """
    All options specific to device `epson2:libusb:002:002':
        --mode Lineart|Gray|Color [Lineart]
        --depth 8|12|14|16bit [inactive]
        --brightness -4..3 [0]
        --resolution 50|100|300|600|1200|2400|3200|4800|6400|9600|12800dpi [25]
        --preview[=(yes|no)] [no]
        -l 0..215.9mm [0]
        -t 0..297.18mm [0]
        -x 0..203.2mm [203.2]
        -y 0..254mm [254]
        --source Flatbed|Transparency Unit|TPU8x10 [TPU8x10]
        --film-type Positive Film|Negative Film|Positive Slide|Negative Slide [Positive Film]
    """

    /// `--source TPU8x10 --mode Color`를 적용한 상태.
    private let colorDump = """
    All options specific to device `epson2:libusb:002:002':
        --mode Lineart|Gray|Color [Color]
        --depth 8|12|14|16bit [8]
        --brightness -4..3 [0]
        --resolution 50|100|300|600|1200|2400|3200|4800|6400|9600|12800dpi [25]
        --preview[=(yes|no)] [no]
        -l 0..215.9mm [0]
        -t 0..297.18mm [0]
        -x 0..203.2mm [203.2]
        -y 0..254mm [254]
        --source Flatbed|Transparency Unit|TPU8x10 [TPU8x10]
        --film-type Positive Film|Negative Film|Positive Slide|Negative Slide [Positive Film]
    """

    private func gtx980Options(bitDepth: BitDepth = .sixteen) -> ScanOptions {
        var options = ScanOptions.strongDefault(scannerID: "sane-epson2:libusb:002:002")
        options.resolution = Resolution(3200)
        options.bitDepth = bitDepth
        return options
    }

    // MARK: 모드 미적용 덤프 = 심도 없음

    func testLineartDefaultDumpReportsNoBitDepth() {
        let capabilities = SANEBackend.parseCapabilities(lineartDefaultDump, backendHint: "epson2")
        XCTAssertTrue(
            capabilities.supportedBitDepths.isEmpty,
            "epson2는 Lineart 상태에서 --depth를 비활성으로 내리므로 이 덤프만으로는 심도를 알 수 없다."
        )
        XCTAssertTrue(capabilities.supportsPreview, "심도와 무관하게 --preview는 활성이다.")
    }

    // MARK: capability 재조회에 모드를 싣는다

    func testCapabilityDumpAppliesColorModeWithTransparencySource() {
        XCTAssertEqual(SANEBackend.capabilityDumpMode(in: lineartDefaultDump), "Color")
        XCTAssertEqual(
            SANEBackend.capabilityRedumpArguments(
                baseDump: lineartDefaultDump,
                devname: "epson2:libusb:002:002"
            ),
            ["-A", "-d", "epson2:libusb:002:002", "--source", "TPU8x10", "--mode", "Color"]
        )
    }

    /// 심도를 되살리려면 모드가 필요하지만 투과 소스가 없는 장치도 재조회한다.
    func testDepthOnlyRedumpAppliesModeWithoutSource() {
        let noSourceDump = lineartDefaultDump.replacingOccurrences(
            of: "    --source Flatbed|Transparency Unit|TPU8x10 [TPU8x10]\n",
            with: ""
        )
        XCTAssertEqual(
            SANEBackend.capabilityRedumpArguments(baseDump: noSourceDump, devname: "epson2:libusb:002:002"),
            ["-A", "-d", "epson2:libusb:002:002", "--mode", "Color"]
        )
    }

    /// 이미 `--depth`가 활성이고 투과 소스도 없으면 장치를 다시 열지 않는다.
    /// 전용 필름 스캐너는 연속 open에서 다음 acquisition이 실패할 수 있다.
    func testActiveDepthWithoutTransparencySourceSkipsRedump() {
        let singlePassDump = """
            --mode Color|Gray [Color]
            --depth 8|16 [16]
            --resolution 3600dpi [3600]
        """
        XCTAssertNil(
            SANEBackend.capabilityRedumpArguments(baseDump: singlePassDump, devname: "pieusb:001:002")
        )
    }

    func testCapabilityDumpFallsBackToGrayWhenColorIsAbsent() {
        let grayOnly = lineartDefaultDump.replacingOccurrences(
            of: "--mode Lineart|Gray|Color [Lineart]",
            with: "--mode Lineart|Gray [Lineart]"
        )
        XCTAssertEqual(SANEBackend.capabilityDumpMode(in: grayOnly), "Gray")
    }

    func testCapabilityDumpModeIsNilWhenDeviceHasNoModeOption() {
        let noMode = lineartDefaultDump.replacingOccurrences(
            of: "    --mode Lineart|Gray|Color [Lineart]\n",
            with: ""
        )
        XCTAssertNil(SANEBackend.capabilityDumpMode(in: noMode))
    }

    // MARK: 모드 적용 덤프 = 심도 정상 보고

    func testColorModeDumpReportsEightAndSixteenBit() {
        let capabilities = SANEBackend.parseCapabilities(colorDump, backendHint: "epson2")
        XCTAssertEqual(capabilities.supportedBitDepths, [.eight, .sixteen])
        XCTAssertEqual(capabilities.transparencyModes, ["Transparency Unit", "TPU8x10"])
        XCTAssertFalse(capabilities.supportsInfrared, "stock epson2 빌드는 IR 채널을 노출하지 않는다.")
    }

    func testColorModeDumpSendsRequestedDepth() throws {
        let options = gtx980Options()
        let media = SANEBackend.resolveMedia(dump: colorDump, options: options)

        XCTAssertNil(media.fixedDepth, "활성 --depth가 있으면 고정 심도 경로로 가지 않는다.")
        XCTAssertEqual(media.depthArgument, 16)
        XCTAssertNoThrow(try SANEBackend.validateExactOptions(options, media: media))

        let args = SANEBackend(scanimagePath: "/tmp/scanimage").makeScanimageArgs(
            devname: "epson2:libusb:002:002",
            options: options,
            media: media
        )
        XCTAssertEqual(argValue(args, "--depth"), "16")
    }

    // MARK: 고정 심도 기기

    /// 비활성이면서 값이 하나뿐인 `--depth`는 그 값이 곧 장치의 고정 심도다.
    func testInactiveSingleTokenDepthBecomesFixedDepth() throws {
        let fixedEightDump = colorDump.replacingOccurrences(
            of: "--depth 8|12|14|16bit [8]",
            with: "--depth 8 [inactive]"
        )
        let capabilities = SANEBackend.parseCapabilities(fixedEightDump, backendHint: "epson2")
        XCTAssertEqual(capabilities.supportedBitDepths, [.eight])

        let options = gtx980Options(bitDepth: .eight)
        let media = SANEBackend.resolveMedia(dump: fixedEightDump, options: options)
        XCTAssertEqual(media.fixedDepth, .eight)
        XCTAssertNil(media.depthArgument)
        XCTAssertNoThrow(try SANEBackend.validateExactOptions(options, media: media))

        let args = SANEBackend(scanimagePath: "/tmp/scanimage").makeScanimageArgs(
            devname: "epson2:libusb:002:002",
            options: options,
            media: media
        )
        XCTAssertNil(argValue(args, "--depth"), "고정 심도 기기에 --depth를 보내면 scanimage가 실패한다.")
    }

    /// 9비트 이상 고정 심도는 16비트 컨테이너로 전달된다(SANE 규격). 실기 미검증 경로.
    func testInactiveFourteenBitDepthIsReportedAsSixteenBitContainer() {
        let fixedFourteenDump = colorDump.replacingOccurrences(
            of: "--depth 8|12|14|16bit [8]",
            with: "--depth 14 [inactive]"
        )
        XCTAssertEqual(
            SANEBackend.parseCapabilities(fixedFourteenDump, backendHint: "epson2").supportedBitDepths,
            [.sixteen]
        )
    }

    func testFixedDepthRejectsMismatchedRequest() {
        let fixedEightDump = colorDump.replacingOccurrences(
            of: "--depth 8|12|14|16bit [8]",
            with: "--depth 8 [inactive]"
        )
        let options = gtx980Options(bitDepth: .sixteen)
        let media = SANEBackend.resolveMedia(dump: fixedEightDump, options: options)

        XCTAssertEqual(media.fixedDepth, .eight)
        XCTAssertThrowsError(try SANEBackend.validateExactOptions(options, media: media)) { error in
            XCTAssertEqual((error as? ScannerError)?.code, .unsupportedOption)
        }
    }

    /// epson2는 심도가 하나뿐인 구형 기기에서 옵션 자체를 노출하지 않고 8비트로 전송한다.
    func testEpson2WithoutDepthOptionIsFixedEightBit() {
        let noDepthDump = colorDump.replacingOccurrences(
            of: "    --depth 8|12|14|16bit [8]\n",
            with: ""
        )
        XCTAssertEqual(
            SANEBackend.parseCapabilities(noDepthDump, backendHint: "epson2").supportedBitDepths,
            [.eight]
        )

        let options = gtx980Options(bitDepth: .eight)
        let media = SANEBackend.resolveMedia(dump: noDepthDump, options: options)
        XCTAssertEqual(media.fixedDepth, .eight)
        XCTAssertNoThrow(try SANEBackend.validateExactOptions(options, media: media))
    }

    func testPieWithoutDepthOptionIsFixedEightBit() {
        let dump = """
            --mode Color|Gray [Color]
            --resolution 300|600|1200dpi [600]
            --preview[=(yes|no)] [no]
            -l 0..36mm [0]
            -t 0..24mm [0]
            -x 1..36mm [36]
            -y 1..24mm [24]
        """
        XCTAssertEqual(
            SANEBackend.parseCapabilities(dump, backendHint: "pie").supportedBitDepths,
            [.eight]
        )
        var options = ScanOptions.strongDefault(scannerID: "sane-pie:scsi:/dev/sg0")
        options.bitDepth = .eight
        options.resolution = Resolution(600)
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        let media = SANEBackend.resolveMedia(
            dump: dump,
            options: options,
            deviceTypeHint: "film scanner"
        )
        XCTAssertEqual(media.fixedDepth, .eight)
        XCTAssertNoThrow(try SANEBackend.validateExactOptions(options, media: media))
    }

    // MARK: 다른 백엔드는 추정하지 않는다

    func testOtherBackendsWithoutDepthOptionStayUnknown() {
        let noDepthDump = colorDump.replacingOccurrences(
            of: "    --depth 8|12|14|16bit [8]\n",
            with: ""
        )
        for backend in ["genesys", "coolscan3", "pieusb", nil] as [String?] {
            XCTAssertTrue(
                SANEBackend.parseCapabilities(noDepthDump, backendHint: backend).supportedBitDepths.isEmpty,
                "문서화된 계약이 없는 백엔드에서 --depth 부재를 8비트로 추정하면 안 된다: \(backend ?? "nil")"
            )
        }
    }

    /// 비활성인데 값이 여러 개면 우리가 모르는 이유로 잠긴 것이므로 아무 값도 고르지 않는다.
    func testInactiveMultiTokenDepthStaysUnknownEvenOnEpson2() {
        XCTAssertTrue(
            SANEBackend.parseCapabilities(lineartDefaultDump, backendHint: "epson2")
                .supportedBitDepths.isEmpty
        )
        XCTAssertNil(
            SANEBackend.fixedDepth(SaneOptionDump(lineartDefaultDump), backendHint: "epson2")
        )
    }
}
