import XCTest
import Foundation
@testable import SANEPluginCore

final class SANEBackendEnvironmentTests: XCTestCase {

    func testSaneEnvironmentIncludesHomebrewPath() {
        let env = SANEBackend.makeSaneEnvironment()
        let path = env["PATH"] ?? ""
        XCTAssertTrue(path.contains("/opt/homebrew/bin") || path.contains("/usr/local/bin"),
                      "SANE 환경의 PATH 에 Homebrew 경로가 있어야 GUI 앱이 scanimage 를 찾는다. PATH=\(path)")
    }

    func testSaneEnvironmentUsesStableEnglishNumericLocale() {
        let env = SANEBackend.makeSaneEnvironment()
        XCTAssertEqual(env["LC_ALL"], "C")
        XCTAssertEqual(env["LANG"], "C")
    }

    func testSaneEnvironmentHasConfigDirWhenHomebrewInstalled() throws {
        // 이 머신에는 /opt/homebrew/etc/sane.d 가 있으므로 SANE_CONFIG_DIR 가 잡혀야 한다.
        let fm = FileManager.default
        let homebrewSane = fm.fileExists(atPath: "/opt/homebrew/etc/sane.d")
                     || fm.fileExists(atPath: "/usr/local/etc/sane.d")
        guard homebrewSane else {
            throw XCTSkip("Homebrew sane-backends 미설치 — SANE_CONFIG_DIR 검증 생략")
        }
        let env = SANEBackend.makeSaneEnvironment()
        XCTAssertNotNil(env["SANE_CONFIG_DIR"], "SANE_CONFIG_DIR 가 주입되어야 scanimage 가 백엔드 설정을 찾는다.")
        if let cfg = env["SANE_CONFIG_DIR"] {
            XCTAssertTrue(fm.fileExists(atPath: cfg))
        }
    }

    func testFindSaneConfigDirResolvesHomebrew() {
        if let dir = SANEBackend.findSaneConfigDir() {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir))
        }
    }

    func testSelectedScanimageUsesMatchingKegConfigurationAndBackends() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-sane-keg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin")
        let config = root.appendingPathComponent("etc/sane.d")
        let backends = root.appendingPathComponent("lib/sane")
        let staleConfig = root.appendingPathComponent("stock/etc/sane.d")
        let staleBackends = root.appendingPathComponent("stock/lib/sane")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backends, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staleConfig, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staleBackends, withIntermediateDirectories: true)

        let scanimage = bin.appendingPathComponent("scanimage").path
        let env = SANEBackend.makeSaneEnvironment(
            scanimagePath: scanimage,
            baseEnvironment: [
                "PATH": "/usr/bin:/bin",
                "SANE_CONFIG_DIR": staleConfig.path,
                "LD_LIBRARY_PATH": staleBackends.path,
            ]
        )

        XCTAssertEqual(env["SANE_CONFIG_DIR"], config.path)
        XCTAssertEqual(
            env["LD_LIBRARY_PATH"],
            "\(backends.path):\(staleBackends.path)"
        )
        XCTAssertNil(env["SANE_BACKENDS_PATH"])
        XCTAssertTrue(env["PATH"]?.hasPrefix("\(bin.path):") == true)
    }

    // MARK: - USB 주소 재획득 회귀 테스트
    //
    // 스캐너의 libusb 주소는 리셋마다 바뀐다(010 ↔ 011). scanimage -L 출력에서
    // 현재 주소를 올바로 파싱해 내는지 검증. 주소가 틀리면 "Invalid argument" 로 open 실패.

    func testParseDeviceAddressFromScanimageListOutput() {
        // scanimage -L 표준 출력 형식.
        let listOutput = """
        device `genesys:libusb:000:011' is a PLUSTEK OpticFilm 8100 flatbed scanner

        No scanners were identified.
        """
        // 정규식이 동일하게 동작하는지 — 첫 줄의 주소만 잡아야 함.
        let regex = try! NSRegularExpression(
            pattern: "device `genesys:(libusb:[0-9]+:[0-9]+)' is a ([^\\s]+)\\s+(.+?) (?:flatbed |film )?scanner"
        )
        let range = NSRange(listOutput.startIndex..., in: listOutput)
        let match = regex.firstMatch(in: listOutput, range: range)
        XCTAssertNotNil(match)
        if let match,
           let r = Range(match.range(at: 1), in: listOutput) {
            XCTAssertEqual(String(listOutput[r]), "libusb:000:011")
        }
    }

    func testParseOfficialFormattedDeviceListPreservesIdentityFields() {
        let output = """
        genesys:libusb:000:011	PLUSTEK	OpticFilm 8100	flatbed scanner
        epson2:libusb:001:005	EPSON	Perfection V850 Pro	flatbed scanner
        """

        XCTAssertEqual(
            SANEBackend.parseFormattedDeviceList(output),
            [
                .init(
                    devname: "genesys:libusb:000:011",
                    vendor: "PLUSTEK",
                    model: "OpticFilm 8100",
                    deviceType: "flatbed scanner"
                ),
                .init(
                    devname: "epson2:libusb:001:005",
                    vendor: "EPSON",
                    model: "Perfection V850 Pro",
                    deviceType: "flatbed scanner"
                ),
            ]
        )
    }

    func testStaleDeviceErrorDetection() {
        // USB 주소 만료 시 나타나는 전형적 오류들 → 재시도 트리거.
        XCTAssertTrue(SANEBackend.isStaleDeviceError(
            "scanimage: open of device genesys:libusb:000:010 failed: Invalid argument"))
        XCTAssertTrue(SANEBackend.isStaleDeviceError("Error during device I/O"))
        XCTAssertTrue(SANEBackend.isStaleDeviceError("scanimage: open of device ... failed: Device busy"))
        // 무관한 오류는 재시도하지 않는다.
        XCTAssertFalse(SANEBackend.isStaleDeviceError("scanimage: out of memory"))
        XCTAssertFalse(SANEBackend.isStaleDeviceError(""))
    }

    func testCapabilitiesPropagatesScanimageOpenFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-sane-open-failure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executableURL = directory.appendingPathComponent("scanimage")
        let script = """
        #!/bin/sh
        if [ "$1" = "-L" ]; then
          printf 'device \\140genesys:libusb:000:011\\047 is a PLUSTEK OpticFilm 8100 flatbed scanner\\n'
          exit 0
        fi
        printf "scanimage: open of device genesys failed: Access to resource has been denied\\n" >&2
        exit 1
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let backend = SANEBackend(scanimagePath: executableURL.path)
        do {
            _ = try await backend.getCapabilities(
                scannerID: "sane-genesys:libusb:000:011"
            )
            XCTFail("scanimage 장치 열기 실패를 빈 capability 성공으로 처리하면 안 됩니다.")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .busy)
            XCTAssertTrue(error.message.contains("Access to resource has been denied"))
        }
    }

    func testCurrentAddressSelectsExactDeviceAndRejectsAmbiguousReconnect() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-sane-multi-device-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executableURL = directory.appendingPathComponent("scanimage")
        let script = """
        #!/bin/sh
        if [ "$1" = "-L" ]; then
          echo "device \\`genesys:libusb:000:011' is a PLUSTEK OpticFilm 8100 film scanner"
          echo "device \\`genesys:libusb:000:012' is a PLUSTEK OpticFilm 8200i film scanner"
          exit 0
        fi
        exit 1
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let backend = SANEBackend(scanimagePath: executableURL.path)
        let exact = try await backend.currentDeviceAddress(
            targetDevice: "genesys:libusb:000:012",
            targetBackend: "genesys",
            allowSingleBackendSelector: true
        )
        XCTAssertEqual(exact, "genesys:libusb:000:012")

        backend.invalidateAddressCache()
        do {
            _ = try await backend.currentDeviceAddress(
                targetDevice: "genesys:libusb:000:099",
                targetBackend: "genesys",
                allowSingleBackendSelector: true
            )
            XCTFail("재연결 뒤 같은 backend 장치 중 임의의 첫 장치를 선택했습니다.")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .notConnected)
            XCTAssertTrue(error.message.contains("제조사·모델 정보가 없어"))
        }
    }

    func testBackendOnlySelectorIsLimitedToGenesysAndEpson2() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-sane-selector-policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executableURL = directory.appendingPathComponent("scanimage")
        let script = """
        #!/bin/sh
        if [ "$1" = "-f" ]; then
          printf 'genesys:libusb:000:011\\tPLUSTEK\\tOpticFilm 8100\\tfilm scanner\\n'
          printf 'epson2:libusb:001:005\\tEPSON\\tPerfection V850 Pro\\tflatbed scanner\\n'
          printf 'coolscan3:usb:libusb:001:4001\\tNikon\\tLS-50 ED\\tfilm scanner\\n'
          printf 'coolscan2:usb:libusb:001:4000\\tNikon\\tLS-40 ED\\tfilm scanner\\n'
          printf 'pieusb:libusb:001:0145\\tReflecta\\tProScan 7200\\tslide scanner\\n'
          printf 'avision:libusb:001:0099\\tAvision\\tUnknown USB\\tflatbed scanner\\n'
          exit 0
        fi
        exit 1
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let cases = [
            ("genesys:libusb:000:011", "genesys", "genesys"),
            ("epson2:libusb:001:005", "epson2", "epson2"),
            (
                "coolscan3:usb:libusb:001:4001",
                "coolscan3",
                "coolscan3:usb:libusb:001:4001"
            ),
            (
                "coolscan2:usb:libusb:001:4000",
                "coolscan2",
                "coolscan2:usb:libusb:001:4000"
            ),
            ("pieusb:libusb:001:0145", "pieusb", "pieusb:libusb:001:0145"),
            ("avision:libusb:001:0099", "avision", "avision:libusb:001:0099"),
        ]

        for (targetDevice, targetBackend, expected) in cases {
            let backend = SANEBackend(scanimagePath: executableURL.path)
            let resolved = try await backend.currentDeviceAddress(
                targetDevice: targetDevice,
                targetBackend: targetBackend,
                allowSingleBackendSelector: true
            )
            XCTAssertEqual(resolved, expected, targetBackend)
        }
    }

    func testReconnectRejectsDifferentModelEvenWhenItIsTheOnlyGenesysDevice() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-sane-wrong-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executableURL = directory.appendingPathComponent("scanimage")
        let script = """
        #!/bin/sh
        if [ "$1" = "-f" ]; then
          printf 'genesys:libusb:000:012\\tPLUSTEK\\tOpticFilm 8200i\\tfilm scanner\\n'
          exit 0
        fi
        exit 1
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let backend = SANEBackend(scanimagePath: executableURL.path)
        do {
            _ = try await backend.currentDeviceAddress(
                targetDevice: "genesys:libusb:000:011",
                targetBackend: "genesys",
                expectedIdentity: .init(vendor: "PLUSTEK", model: "OpticFilm 8100"),
                allowSingleBackendSelector: true
            )
            XCTFail("같은 genesys 백엔드의 다른 모델로 대체했습니다.")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .notConnected)
            XCTAssertTrue(error.message.contains("OpticFilm 8100"))
        }
    }

    /// 장치를 한 번 열면 libusb 주소가 바뀌는 실기(Plustek OpticFilm 8100)에서, 제조사·모델
    /// 힌트 없이도 해당 backend 장치가 하나뿐이면 새 주소로 재연결해야 한다.
    ///
    /// 예전에는 이 경우 `chosen`이 nil이 되어 "제조사·모델 정보가 없어 …"로 즉시 실패했고,
    /// capabilities/scan이 통째로 막혔다. USB 컨트롤러가 device number를 재사용하는 Mac에서는
    /// 주소가 안 바뀌어 증상이 안 보이지만, 재사용하지 않는 Mac에서는 항상 재현된다.
    func testReconnectsToSoleBackendDeviceAtNewAddressWithoutIdentityHint() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-sane-sole-device-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executableURL = directory.appendingPathComponent("scanimage")
        // detect가 본 주소는 002:001 이었지만, 그 뒤의 open으로 002:002 로 바뀐 상태.
        let script = """
        #!/bin/sh
        if [ "$1" = "-f" ]; then
          printf 'genesys:libusb:002:002\\tPLUSTEK\\tOpticFilm 8100\\tfilm scanner\\n'
          exit 0
        fi
        exit 1
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let backend = SANEBackend(scanimagePath: executableURL.path)
        let resolved = try await backend.currentDeviceAddress(
            targetDevice: "genesys:libusb:002:001",
            targetBackend: "genesys"
        )
        XCTAssertEqual(resolved, "genesys:libusb:002:002")
    }

    /// 장치를 연 뒤에는 캐시된 주소 기반 선택자를 더 이상 신뢰하지 않는다.
    /// (주소 없는 backend 선택자는 재열거를 견디므로 유지한다.)
    func testCachedAddressIsDroppedAfterDeviceOpenButStableSelectorSurvives() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-sane-open-invalidates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executableURL = directory.appendingPathComponent("scanimage")
        let script = """
        #!/bin/sh
        if [ "$1" = "-f" ]; then
          printf 'genesys:libusb:002:002\\tPLUSTEK\\tOpticFilm 8100\\tfilm scanner\\n'
          exit 0
        fi
        exit 1
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let backend = SANEBackend(scanimagePath: executableURL.path)
        _ = try await backend.currentDeviceAddress(
            targetDevice: "genesys:libusb:002:001",
            targetBackend: "genesys"
        )
        XCTAssertNotNil(
            backend.liveCachedSelector(
                targetDevice: "genesys:libusb:002:001",
                targetBackend: "genesys",
                expectedIdentity: nil
            )
        )
        backend.noteDeviceOpened()
        XCTAssertNil(
            backend.liveCachedSelector(
                targetDevice: "genesys:libusb:002:001",
                targetBackend: "genesys",
                expectedIdentity: nil
            ),
            "open 뒤에도 주소 기반 선택자를 재사용하면 죽은 주소로 스캔을 건다."
        )

        _ = try await backend.currentDeviceAddress(
            targetDevice: "genesys:libusb:002:001",
            targetBackend: "genesys",
            allowSingleBackendSelector: true
        )
        backend.noteDeviceOpened()
        XCTAssertEqual(
            backend.liveCachedSelector(
                targetDevice: "genesys:libusb:002:001",
                targetBackend: "genesys",
                expectedIdentity: nil
            ),
            "genesys",
            "주소가 없는 backend 선택자는 재열거를 견디므로 유지해야 한다."
        )
    }

    /// 투과 소스를 따로 고르는 장치(epson2/pieusb/coolscan3/2소스 genesys 등)는 capability를
    /// 읽을 때 `-A`를 두 번 연다. 첫 open이 USB 주소를 바꿔버리면 두 번째 open이 죽은 주소를
    /// 쓰게 되어 capability 조회 전체가 실패했다. 두 번째 open은 주소를 다시 확인해야 한다.
    func testCapabilityReadReopensDeviceWhenFirstOpenChangedTheAddress() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-sane-reopen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executableURL = directory.appendingPathComponent("scanimage")
        let stateURL = directory.appendingPathComponent("addr")
        try "001".write(to: stateURL, atomically: true, encoding: .utf8)
        // 장치를 열 때마다(-A) 주소가 001 <-> 002 로 뒤집힌다. 목록 조회는 주소를 바꾸지 않는다.
        let script = """
        #!/bin/sh
        STATE=\(shellQuote(stateURL.path))
        CUR=$(cat "$STATE")
        if [ "$1" = "-f" ]; then
          printf 'epson2:libusb:002:%s\\tEpson\\tGT-X970\\tflatbed scanner\\n' "$CUR"
          exit 0
        fi
        DEV=""; prev=""
        for a in "$@"; do [ "$prev" = "-d" ] && DEV="$a"; prev="$a"; done
        if [ "$DEV" != "epson2:libusb:002:$CUR" ]; then
          echo "scanimage: open of device $DEV failed: Invalid argument" >&2
          exit 1
        fi
        if [ "$CUR" = "001" ]; then echo 002 > "$STATE"; else echo 001 > "$STATE"; fi
        echo "--mode Color|Gray [Color]"
        echo "--source Flatbed|Transparency Unit [Transparency Unit]"
        echo "--depth 8|16 [16]"
        echo "--resolution 3200dpi [3200]"
        echo "--preview[=(yes|no)] [no]"
        echo "-l 0..215mm (in steps of 0.1) [0]"
        echo "-t 0..297mm (in steps of 0.1) [0]"
        echo "-x 1..215mm (in steps of 0.1) [215]"
        echo "-y 1..297mm (in steps of 0.1) [297]"
        exit 0
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let backend = SANEBackend(scanimagePath: executableURL.path)
        let report = try await backend.getCapabilitiesReport(
            scannerID: "sane-epson2:libusb:002:001",
            expectedIdentity: .init(vendor: "Epson", model: "GT-X970")
        )
        XCTAssertTrue(report.capabilities.supportsTransparency)
        XCTAssertFalse(report.capabilityToken.isEmpty)
    }

    func testEpsonCapabilityAndScanFollowReloadedInactiveBrightnessState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-sane-epson-reload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceTIFF = directory.appendingPathComponent("source.tiff")
        let previewOutputTIFF = directory.appendingPathComponent("preview.tiff")
        let outputTIFF = directory.appendingPathComponent("output.tiff")
        let invocationLog = directory.appendingPathComponent("invocations.log")
        try writeScannerRGB16TIFF(
            pixels: [0.1, 0.2, 0.3],
            width: 1,
            height: 1,
            to: sourceTIFF
        )

        let executableURL = directory.appendingPathComponent("scanimage")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> \(shellQuote(invocationLog.path))
        if [ "$1" = "-f" ]; then
          printf 'epson2:libusb:000:001\\tEpson\\tGT-X900\\tflatbed scanner\\n'
          exit 0
        fi
        case " $* " in
          *" -A "*)
            case " $* " in
              *" --gamma-correction User defined "*)
                echo "--mode Lineart|Gray|Color [Color]"
                echo "--depth 8|12|14|16bit [8]"
                echo "--brightness -4..3 [inactive]"
                echo "--gamma-correction Default|User defined [User defined]"
                echo "--color-correction None|Built in CCT profile [None]"
                echo "--source Flatbed|Transparency Unit|TPU8x10 [TPU8x10]"
                echo "--film-type Positive Film|Negative Film|Positive Slide|Negative Slide [Positive Film]"
                echo "-l 0..215.9mm [0]"
                echo "-t 0..297.18mm [0]"
                echo "-x 0..203.2mm [203.2]"
                echo "-y 0..254mm [254]"
                ;;
              *)
                echo "--mode Lineart|Gray|Color [Lineart]"
                echo "--depth 8|12|14|16bit [inactive]"
                echo "--brightness -4..3 [0]"
                echo "--gamma-correction Default|User defined [Default]"
                echo "--color-correction None|Built in CCT profile [inactive]"
                echo "--source Flatbed|Transparency Unit|TPU8x10 [Flatbed]"
                echo "--film-type Positive Film|Negative Film|Positive Slide|Negative Slide [inactive]"
                echo "-l 0..215.9mm [0]"
                echo "-t 0..297.18mm [0]"
                echo "-x 0..215.9mm [215.9]"
                echo "-y 0..297.18mm [297.18]"
                ;;
            esac
            echo "--resolution 3200dpi [3200]"
            echo "--preview[=(yes|no)] [no]"
            exit 0
            ;;
        esac
        case " $* " in
          *" --gamma-correction User defined "*)
            case " $* " in
              *" --brightness="*)
                echo "scanimage: attempted to set inactive option brightness" >&2
                exit 1
                ;;
            esac
            ;;
        esac
        exec /bin/cat \(shellQuote(sourceTIFF.path))
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let backend = SANEBackend(scanimagePath: executableURL.path)
        let scannerID = "sane-epson2:libusb:000:001"
        let report = try await backend.getCapabilitiesReport(scannerID: scannerID)
        XCTAssertNil(report.capabilities.brightnessRange)
        XCTAssertEqual(report.capabilities.maxScanArea.widthMM, 203.2, accuracy: 0.000_001)
        XCTAssertEqual(report.capabilities.maxScanArea.heightMM, 254, accuracy: 0.000_001)

        var previewOptions = ScanOptions.strongDefault(scannerID: scannerID)
        previewOptions.resolution = .preview
        previewOptions.bitDepth = .sixteen
        previewOptions.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        previewOptions.temporaryOutputURL = previewOutputTIFF
        previewOptions.capabilityToken = report.capabilityToken

        _ = try await backend.startPreviewScan(previewOptions) { _ in }

        var options = ScanOptions.strongDefault(scannerID: scannerID)
        options.resolution = Resolution(3200)
        options.bitDepth = .sixteen
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        options.temporaryOutputURL = outputTIFF
        options.capabilityToken = report.capabilityToken

        _ = try await backend.startFullScan(options) { _ in }

        let invocations = try String(contentsOf: invocationLog, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertTrue(invocations.contains {
            $0.contains(
                "--source TPU8x10 --mode Color --color-correction None "
                    + "--gamma-correction User defined"
            )
        })
        let acquisitions = invocations.filter {
            !$0.hasPrefix("-L") && !$0.hasPrefix("-f") && !$0.hasPrefix("-A")
        }
        XCTAssertEqual(acquisitions.count, 2)
        XCTAssertTrue(acquisitions.contains { $0.contains("--preview=yes") })
        XCTAssertTrue(acquisitions.allSatisfy { $0.contains("--gamma-correction User defined") })
        XCTAssertTrue(acquisitions.allSatisfy { $0.contains("--film-type Negative Film") })
        XCTAssertTrue(acquisitions.allSatisfy { !$0.contains("--brightness") })
    }

    func testReconnectAcceptsSameModelAtNewAddress() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-sane-same-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executableURL = directory.appendingPathComponent("scanimage")
        let script = """
        #!/bin/sh
        if [ "$1" = "-f" ]; then
          printf 'genesys:libusb:000:014\\tPLUSTEK\\tOpticFilm 8100\\tfilm scanner\\n'
          exit 0
        fi
        exit 1
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let backend = SANEBackend(scanimagePath: executableURL.path)
        let resolved = try await backend.currentDeviceAddress(
            targetDevice: "genesys:libusb:000:011",
            targetBackend: "genesys",
            expectedIdentity: .init(vendor: "plustek", model: "  OpticFilm   8100 "),
            allowSingleBackendSelector: false
        )
        XCTAssertEqual(resolved, "genesys:libusb:000:014")
    }

    func testSuccessfulProcessStillRejectsSANEInexactRounding() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-sane-inexact-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceTIFF = directory.appendingPathComponent("source.tiff")
        try writeScannerRGB16TIFF(
            pixels: [0.1, 0.2, 0.3],
            width: 1,
            height: 1,
            to: sourceTIFF
        )
        let executableURL = directory.appendingPathComponent("scanimage")
        let script = """
        #!/bin/sh
        if [ "$1" = "-L" ]; then
          echo "device \\`genesys:libusb:000:011' is a PLUSTEK Exactness Test film scanner"
          exit 0
        fi
        if [ "$1" = "-A" ]; then
          echo "--mode Color|Gray [Color]"
          echo "--source Transparency Adapter [Transparency Adapter]"
          echo "--depth 8|16 [16]"
          echo "--resolution 3600dpi [3600]"
          echo "-x 1..36mm (in steps of 1) [36]"
          echo "-y 1..24mm (in steps of 1) [24]"
          exit 0
        fi
        echo "scanimage: rounded value of resolution from 3600 to 3599" >&2
        exec /bin/cat \(shellQuote(sourceTIFF.path))
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let backend = SANEBackend(scanimagePath: executableURL.path)
        var options = ScanOptions.strongDefault(
            scannerID: "sane-genesys:libusb:000:011"
        )
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        options.temporaryOutputURL = directory.appendingPathComponent("output.tiff")

        do {
            _ = try await backend.startFullScan(options) { _ in }
            XCTFail("SANE_INFO_INEXACT에 해당하는 반올림을 exact 적용으로 보고했습니다.")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .unsupportedOption)
            XCTAssertTrue(error.message.contains("반올림"))
        }
    }

    func testSingleGenesysFallbackIsUsedOnlyAfterExactDeviceBecomesStale() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-sane-genesys-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceTIFF = directory.appendingPathComponent("source.tiff")
        let invocationLog = directory.appendingPathComponent("invocations.log")
        try writeScannerRGB16TIFF(
            pixels: [0.1, 0.2, 0.3],
            width: 1,
            height: 1,
            to: sourceTIFF
        )
        let executableURL = directory.appendingPathComponent("scanimage")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> \(shellQuote(invocationLog.path))
        if [ "$1" = "-L" ]; then
          echo "device \\`genesys:libusb:000:011' is a PLUSTEK Reenumerating Test film scanner"
          exit 0
        fi
        if [ "$1" = "-A" ]; then
          if [ "$3" != "genesys" ]; then
            echo "scanimage: open of device $3 failed: Invalid argument" >&2
            exit 1
          fi
          echo "--mode Color|Gray [Color]"
          echo "--source Transparency Adapter [Transparency Adapter]"
          echo "--depth 8|16 [16]"
          echo "--resolution 3600dpi [3600]"
          echo "-x 1..36mm (in steps of 1) [36]"
          echo "-y 1..24mm (in steps of 1) [24]"
          exit 0
        fi
        exec /bin/cat \(shellQuote(sourceTIFF.path))
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let backend = SANEBackend(scanimagePath: executableURL.path)
        let scannerID = "sane-genesys:libusb:000:011"
        let report = try await backend.getCapabilitiesReport(scannerID: scannerID)
        var options = ScanOptions.strongDefault(scannerID: scannerID)
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        options.temporaryOutputURL = directory.appendingPathComponent("output.tiff")
        options.capabilityToken = report.capabilityToken

        _ = try await backend.startFullScan(options) { _ in }

        let invocations = try String(contentsOf: invocationLog, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(
            invocations.filter { $0.hasPrefix("-A -d genesys:") }.count,
            2
        )
        XCTAssertEqual(
            invocations.filter { $0.hasPrefix("-A -d genesys") }.count,
            3
        )
        XCTAssertEqual(
            invocations.filter {
                !$0.hasPrefix("-L") && !$0.hasPrefix("-A") && $0.contains("-d genesys ")
            }.count,
            1,
            "성공한 capability 토큰 뒤 scan은 -A 없이 검증된 단일 genesys 선택자를 사용해야 합니다."
        )
    }

    func testCapabilityTokenRedumpsOptionsWhenRequestedModeChanges() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-sane-mode-token-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executableURL = directory.appendingPathComponent("scanimage")
        let invocationLog = directory.appendingPathComponent("invocations.log")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> \(shellQuote(invocationLog.path))
        if [ "$1" = "-f" ]; then
          printf 'genesys:libusb:000:011\\tPLUSTEK\\tMode Test\\tfilm scanner\\n'
          exit 0
        fi
        case " $* " in
          *" --mode Gray "*)
            echo "--mode Color|Gray [Gray]"
            echo "--source Transparency Adapter [Transparency Adapter]"
            echo "--depth 8 [8]"
            ;;
          *)
            echo "--mode Color|Gray [Color]"
            echo "--source Transparency Adapter [Transparency Adapter]"
            echo "--depth 8|16 [16]"
            ;;
        esac
        echo "--resolution 600|3600dpi [600]"
        echo "-l 0..36mm (in steps of 1) [0]"
        echo "-t 0..24mm (in steps of 1) [0]"
        echo "-x 1..36mm (in steps of 1) [36]"
        echo "-y 1..24mm (in steps of 1) [24]"
        exit 0
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let backend = SANEBackend(scanimagePath: executableURL.path)
        let scannerID = "sane-genesys:libusb:000:011"
        let report = try await backend.getCapabilitiesReport(scannerID: scannerID)
        var options = ScanOptions.strongDefault(scannerID: scannerID)
        options.colorMode = .gray
        options.bitDepth = .eight
        options.resolution = Resolution(600)
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        options.capabilityToken = report.capabilityToken

        let sessionID = try backend.beginScanSession()
        defer { backend.endScanSession(sessionID) }
        let media = try await backend.resolveMedia(options: options)
        XCTAssertEqual(media.mode, "Gray")
        XCTAssertEqual(media.depthArgument, 8)

        let invocations = try String(contentsOf: invocationLog, encoding: .utf8)
        XCTAssertTrue(invocations.contains("-A -d genesys:libusb:000:011 --mode Color"))
        XCTAssertTrue(invocations.contains("--mode Gray --resolution 600 --depth 8"))
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

}
