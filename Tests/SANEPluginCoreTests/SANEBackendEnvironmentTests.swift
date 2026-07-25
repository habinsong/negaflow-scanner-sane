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
            targetBackend: "genesys"
        )
        XCTAssertEqual(exact, "genesys:libusb:000:012")

        backend.invalidateAddressCache()
        do {
            _ = try await backend.currentDeviceAddress(
                targetDevice: "genesys:libusb:000:099",
                targetBackend: "genesys"
            )
            XCTFail("재연결 뒤 같은 backend 장치 중 임의의 첫 장치를 선택했습니다.")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .notConnected)
            XCTAssertTrue(error.message.contains("제조사·모델 정보가 없어"))
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
                allowSingleGenesysSelector: true
            )
            XCTFail("같은 genesys 백엔드의 다른 모델로 대체했습니다.")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .notConnected)
            XCTAssertTrue(error.message.contains("OpticFilm 8100"))
        }
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
            allowSingleGenesysSelector: false
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

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

}
