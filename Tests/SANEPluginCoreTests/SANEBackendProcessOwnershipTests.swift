import XCTest
import Foundation
import Darwin
@testable import SANEPluginCore

final class SANEBackendProcessOwnershipTests: XCTestCase {
    func testSequentialPositionedScansInvokeOneAcquisitionPerROIWithExactGeometry() async throws {
        let fixture = try makePositionedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = SANEBackend(scanimagePath: fixture.executableURL.path)

        var first = fixture.options
        first.scanArea = ScanArea(originXMM: 12.5, originYMM: 21.2, widthMM: 36, heightMM: 24)
        first.temporaryOutputURL = fixture.root.appendingPathComponent("roi-1.tiff")
        var second = fixture.options
        second.scanArea = ScanArea(originXMM: 100.1, originYMM: 120.2, widthMM: 36, heightMM: 24)
        second.temporaryOutputURL = fixture.root.appendingPathComponent("roi-2.tiff")

        let firstResult = try await backend.startFullScan(first) { _ in }
        let secondResult = try await backend.startFullScan(second) { _ in }

        XCTAssertEqual(firstResult.rawFileURL, first.temporaryOutputURL)
        XCTAssertEqual(secondResult.rawFileURL, second.temporaryOutputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstResult.rawFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondResult.rawFileURL.path))
        let invocations = try String(contentsOf: fixture.argumentLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(invocations.count, 2, "ROI마다 scanimage acquisition을 한 번씩 실행해야 합니다.")
        XCTAssertTrue(invocations.allSatisfy { $0.contains("-d epson2:libusb:001:005") })
        XCTAssertTrue(invocations[0].contains("-l 12.5 -t 21.2 -x 36 -y 24"))
        XCTAssertTrue(invocations[1].contains("-l 100.1 -t 120.2 -x 36 -y 24"))
        XCTAssertTrue(invocations.allSatisfy { $0.contains("--format=tiff") })
    }

    func testScanPreservesUnownedProcessUsingSameExecutable() async throws {
        let fixture = try makeFixture(blockingScan: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let unowned = try startUnownedProcess(executableURL: fixture.executableURL)
        defer { stop(unowned) }

        let backend = SANEBackend(scanimagePath: fixture.executableURL.path)
        let result = try await backend.startFullScan(fixture.options) { _ in }

        XCTAssertEqual(result.width, 1)
        XCTAssertEqual(result.height, 1)
        XCTAssertTrue(unowned.isRunning, "다른 session의 동일 scanimage executable을 종료했습니다.")
        XCTAssertNil(backend.snapshotOwnedScanProcess())
    }

    func testCancelTerminatesOnlyOwnedProcessAndConcurrentScanFailsBusy() async throws {
        let fixture = try makeFixture(blockingScan: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let unowned = try startUnownedProcess(executableURL: fixture.executableURL)
        defer { stop(unowned) }

        let backend = SANEBackend(scanimagePath: fixture.executableURL.path)
        let scanTask = Task {
            try await backend.startFullScan(fixture.options) { _ in }
        }
        let owned = try await waitForOwnedAcquisition(backend)

        var concurrentOptions = fixture.options
        concurrentOptions.temporaryOutputURL = fixture.root.appendingPathComponent("concurrent.tiff")
        do {
            _ = try await backend.startFullScan(concurrentOptions) { _ in }
            XCTFail("동일 backend의 동시 scan을 수용했습니다.")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .busy)
        }

        await backend.cancelScan()
        do {
            _ = try await scanTask.value
            XCTFail("취소한 owned scanimage가 성공으로 끝났습니다.")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .cancelled)
        }

        XCTAssertFalse(owned.isRunning)
        XCTAssertTrue(unowned.isRunning, "cancelScan이 backend가 소유하지 않은 process까지 종료했습니다.")
        XCTAssertNil(backend.snapshotOwnedScanProcess())
    }

    func testCancelTerminatesOwnedDetectionProcessWithoutPoisoningNextRequest() async throws {
        let fixture = try makeFixture(blockingScan: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = SANEBackend(scanimagePath: fixture.executableURL.path)

        let detection = Task {
            try await backend.detectScanners()
        }
        let owned = try await waitForAnyOwnedProcess(backend)
        await backend.cancelScan()

        do {
            _ = try await detection.value
            XCTFail("취소한 detect용 scanimage가 성공으로 끝났습니다.")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .cancelled)
        }
        XCTAssertFalse(owned.isRunning)
        XCTAssertNil(backend.snapshotOwnedScanProcess())

        let sessionID = try backend.beginScanSession()
        backend.endScanSession(sessionID)
    }

    func testCancelWhileIdleDoesNotPoisonNextScanSession() async throws {
        let fixture = try makeFixture(blockingScan: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = SANEBackend(scanimagePath: fixture.executableURL.path)

        await backend.cancelScan()

        let result = try await backend.startFullScan(fixture.options) { _ in }
        XCTAssertEqual(result.width, 1)
        XCTAssertEqual(result.height, 1)
    }

    func testProcessImplementationContainsNoGlobalNameKillOrShellInterpolation() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/SANEPluginCore/SANEBackend+Process.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("pgrep"))
        XCTAssertFalse(source.contains("pkill"))
        XCTAssertFalse(source.contains("launchPath = \"/bin/sh\""))
        XCTAssertFalse(source.contains("arguments = [\"-c\""))
    }

    private struct Fixture {
        var root: URL
        var executableURL: URL
        var argumentLogURL: URL
        var options: ScanOptions
    }

    private func makeFixture(blockingScan: Bool) throws -> Fixture {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-sane-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceTIFF = root.appendingPathComponent("source.tiff")
        try writeScannerRGB16TIFF(pixels: [0.1, 0.2, 0.3], width: 1, height: 1, to: sourceTIFF)
        let executableURL = root.appendingPathComponent("scanimage-owned-fixture")
        let acquisition = blockingScan
            ? "exec /bin/sleep 30"
            : "exec /bin/cat \(shellQuote(sourceTIFF.path))"
        let script = """
        #!/bin/sh
        if [ "$1" = "hold" ]; then
          trap 'exit 0' TERM INT
          while :; do /bin/sleep 1; done
        fi
        if [ "$1" = "-L" ]; then
          echo "device \\`genesys:libusb:000:010' is a PLUSTEK Ownership Test film scanner"
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
        \(acquisition)
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        var options = ScanOptions.strongDefault(scannerID: "sane-genesys:libusb:000:010")
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        options.temporaryOutputURL = root.appendingPathComponent("output.tiff")
        return Fixture(
            root: root,
            executableURL: executableURL,
            argumentLogURL: root.appendingPathComponent("arguments.log"),
            options: options
        )
    }

    private func makePositionedFixture() throws -> Fixture {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-sane-positioned-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceTIFF = root.appendingPathComponent("source.tiff")
        try writeScannerRGB16TIFF(
            pixels: [
                0.1, 0.2, 0.3,
                0.2, 0.3, 0.4,
                0.3, 0.4, 0.5,
                0.4, 0.5, 0.6,
                0.5, 0.6, 0.7,
                0.6, 0.7, 0.8,
            ],
            width: 3,
            height: 2,
            to: sourceTIFF
        )
        let executableURL = root.appendingPathComponent("scanimage-positioned-fixture")
        let argumentLogURL = root.appendingPathComponent("arguments.log")
        let script = """
        #!/bin/sh
        if [ "$1" = "-L" ]; then
          echo "device \\`epson2:libusb:001:005' is a Epson Position Test flatbed scanner"
          exit 0
        fi
        if [ "$1" = "-A" ]; then
          echo "--mode Color|Gray [Color]"
          echo "--source Flatbed|Transparency Unit [Transparency Unit]"
          echo "--preview[=(yes|no)] [no]"
          echo "--depth 8|16 [16]"
          echo "--resolution 3600dpi [3600]"
          echo "-l 0..215mm (in steps of 0.1) [0]"
          echo "-t 0..297mm (in steps of 0.1) [0]"
          echo "-x 1..215mm (in steps of 0.1) [215]"
          echo "-y 1..297mm (in steps of 0.1) [297]"
          exit 0
        fi
        printf '%s\\n' "$*" >> \(shellQuote(argumentLogURL.path))
        exec /bin/cat \(shellQuote(sourceTIFF.path))
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        var options = ScanOptions.strongDefault(scannerID: "sane-epson2:libusb:001:005")
        options.scanArea = ScanArea(widthMM: 36, heightMM: 24)
        return Fixture(
            root: root,
            executableURL: executableURL,
            argumentLogURL: argumentLogURL,
            options: options
        )
    }

    private func startUnownedProcess(executableURL: URL) throws -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["hold"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private func waitForOwnedAcquisition(_ backend: SANEBackend) async throws -> Process {
        for _ in 0..<200 {
            if let process = backend.snapshotOwnedScanProcess(),
               process.isRunning,
               process.arguments?.contains("--format=tiff") == true {
                return process
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw ScannerError(.timeout, "owned scanimage acquisition을 관찰하지 못했습니다.")
    }

    private func waitForAnyOwnedProcess(_ backend: SANEBackend) async throws -> Process {
        for _ in 0..<200 {
            if let process = backend.snapshotOwnedScanProcess(), process.isRunning {
                return process
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw ScannerError(.timeout, "owned scanimage process를 관찰하지 못했습니다.")
    }

    private func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        var deadline = Date().addingTimeInterval(1)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            deadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        XCTAssertFalse(process.isRunning, "테스트 보조 process가 제한 시간 안에 종료되지 않았습니다.")
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
