import XCTest
import Foundation
import Darwin
@testable import SANEPluginCore

final class SANEBackendProcessOwnershipTests: XCTestCase {
    func testUtilityScanimageProcessTimesOutAndReleasesOwnedSlot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-sane-utility-timeout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executableURL = directory.appendingPathComponent("scanimage")
        try """
        #!/bin/sh
        exec /bin/sleep 10
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let backend = SANEBackend(
            scanimagePath: executableURL.path,
            utilityProcessTimeout: 0.1,
            acquisitionFirstProgressTimeout: 1
        )
        let started = Date()
        do {
            _ = try await backend.runScanimage(args: ["-L"])
            XCTFail("응답하지 않는 scanimage 조회를 성공으로 처리했습니다.")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .timeout)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertNil(backend.snapshotOwnedScanProcess())
    }

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
        XCTAssertTrue(invocations.allSatisfy { $0.contains("-d epson2 ") })
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
        let fixture = try makeFixture(blockingScan: true, blockingDiscovery: true)
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

    func testFirstProgressTimeoutRetriesOnceAndCleansUpOwnedProcess() async throws {
        let fixture = try makeFixture(blockingScan: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = SANEBackend(
            scanimagePath: fixture.executableURL.path,
            acquisitionFirstProgressTimeout: 0.15
        )
        let phases = PhaseBox()

        do {
            _ = try await backend.startFullScan(fixture.options) { update in
                phases.append(update.phase)
            }
            XCTFail("첫 이미지 데이터가 없는 scanimage를 성공으로 처리했습니다.")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .timeout)
            XCTAssertTrue(error.message.contains("첫 이미지 데이터"))
        }

        let acquisitions = try String(contentsOf: fixture.argumentLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(acquisitions.count, 2, "첫 데이터 timeout은 한 번만 재시도해야 합니다.")
        XCTAssertTrue(acquisitions.allSatisfy { $0.contains("-d genesys ") })
        XCTAssertFalse(
            phases.contains(.scanningRGB),
            "scanimage가 실제 진행률을 내기 전에 RGB 스캔 진행률을 만들면 안 됩니다."
        )
        XCTAssertNil(backend.snapshotOwnedScanProcess())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.options.temporaryOutputURL!.path))
    }

    func testProgressStallAfterFirstProgressFailsWithoutRetry() async throws {
        let fixture = try makeFixture(blockingScan: false, progressBeforeDelay: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = SANEBackend(
            scanimagePath: fixture.executableURL.path,
            acquisitionFirstProgressTimeout: 0.15,
            acquisitionProgressStallTimeout: 0.15
        )

        do {
            _ = try await backend.startFullScan(fixture.options) { _ in }
            XCTFail("첫 progress 뒤 멈춘 scanimage를 성공으로 처리했습니다.")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .timeout)
            XCTAssertTrue(error.message.contains("진행률"))
        }

        let acquisitions = try String(contentsOf: fixture.argumentLogURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(acquisitions.count, 1, "이미 acquisition이 시작된 stall은 자동 재시도하면 안 됩니다.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.options.temporaryOutputURL!.path))
        XCTAssertNil(backend.snapshotOwnedScanProcess())
    }

    func testStderrNoiseDoesNotHideProgressStall() async throws {
        let fixture = try makeFixture(
            blockingScan: false,
            progressBeforeDelay: true,
            noiseDuringDelay: true
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = SANEBackend(
            scanimagePath: fixture.executableURL.path,
            acquisitionFirstProgressTimeout: 0.15,
            acquisitionProgressStallTimeout: 0.15
        )

        do {
            _ = try await backend.startFullScan(fixture.options) { _ in }
            XCTFail("새 progress 없이 stderr만 출력하는 acquisition을 성공으로 처리했습니다.")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .timeout)
            XCTAssertTrue(error.message.contains("진행률"))
        }

        let acquisitions = try String(contentsOf: fixture.argumentLogURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(acquisitions.count, 1)
    }

    func testPeriodicProgressKeepsLongRunningAcquisitionAlive() async throws {
        let fixture = try makeFixture(
            blockingScan: false,
            progressUpdatesDuringDelay: true
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = SANEBackend(
            scanimagePath: fixture.executableURL.path,
            acquisitionFirstProgressTimeout: 0.5,
            acquisitionProgressStallTimeout: 0.5
        )

        let result = try await backend.startFullScan(fixture.options) { _ in }

        XCTAssertEqual(result.width, 1)
        XCTAssertEqual(result.height, 1)
        let acquisitions = try String(contentsOf: fixture.argumentLogURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(acquisitions.count, 1)
        XCTAssertNil(backend.snapshotOwnedScanProcess())
    }

    func testUnknownProgressKeepsLongRunningAcquisitionAlive() async throws {
        let fixture = try makeFixture(
            blockingScan: false,
            unknownProgressUpdatesDuringDelay: true
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = SANEBackend(
            scanimagePath: fixture.executableURL.path,
            acquisitionFirstProgressTimeout: 0.5,
            acquisitionProgressStallTimeout: 0.5
        )

        let result = try await backend.startFullScan(fixture.options) { _ in }

        XCTAssertEqual(result.width, 1)
        XCTAssertEqual(result.height, 1)
        let acquisitions = try String(contentsOf: fixture.argumentLogURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(acquisitions.count, 1)
        XCTAssertNil(backend.snapshotOwnedScanProcess())
    }

    func testDeviceIOErrorAfterProgressIsNotRetried() async throws {
        let fixture = try makeFixture(
            blockingScan: false,
            failAfterProgress: true
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = SANEBackend(
            scanimagePath: fixture.executableURL.path,
            acquisitionFirstProgressTimeout: 0.15,
            acquisitionProgressStallTimeout: 0.15
        )

        do {
            _ = try await backend.startFullScan(fixture.options) { _ in }
            XCTFail("이미 진행된 뒤의 I/O 오류를 성공으로 처리했습니다.")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .ioFailure)
            XCTAssertTrue(error.message.lowercased().contains("device i/o"))
        }

        let acquisitions = try String(contentsOf: fixture.argumentLogURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(acquisitions.count, 1, "이미 움직인 acquisition을 자동 재시도하면 안 됩니다.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.options.temporaryOutputURL!.path))
        XCTAssertNil(backend.snapshotOwnedScanProcess())
    }

    func testPieusbIsExcludedFromAutomaticProgressWatchdog() {
        XCTAssertFalse(SANEBackend.usesAutomaticAcquisitionWatchdog(backend: "pieusb"))
        XCTAssertTrue(SANEBackend.usesAutomaticAcquisitionWatchdog(backend: "epson2"))
        XCTAssertTrue(SANEBackend.usesAutomaticAcquisitionWatchdog(backend: "genesys"))
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

    private final class PhaseBox: @unchecked Sendable {
        private let lock = NSLock()
        private var phases: [ScanPhase] = []

        func append(_ phase: ScanPhase) {
            lock.lock()
            phases.append(phase)
            lock.unlock()
        }

        func contains(_ phase: ScanPhase) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return phases.contains(phase)
        }
    }

    private func makeFixture(
        blockingScan: Bool,
        blockingDiscovery: Bool = false,
        progressBeforeDelay: Bool = false,
        progressUpdatesDuringDelay: Bool = false,
        unknownProgressUpdatesDuringDelay: Bool = false,
        failAfterProgress: Bool = false,
        noiseDuringDelay: Bool = false
    ) throws -> Fixture {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-sane-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceTIFF = root.appendingPathComponent("source.tiff")
        try writeScannerRGB16TIFF(pixels: [0.1, 0.2, 0.3], width: 1, height: 1, to: sourceTIFF)
        let executableURL = root.appendingPathComponent("scanimage-owned-fixture")
        let acquisition: String
        if blockingScan {
            acquisition = "exec /bin/sleep 30"
        } else if failAfterProgress {
            acquisition = """
            printf 'Progress: 5%%\\r' >&2
            printf 'scanimage: Error during device I/O\\n' >&2
            exit 1
            """
        } else if unknownProgressUpdatesDuringDelay {
            acquisition = """
            printf 'Progress: (unknown)\\r' >&2
            /bin/sleep 0.15
            printf 'Progress: (unknown)\\r' >&2
            /bin/sleep 0.15
            printf 'Progress: (unknown)\\r' >&2
            /bin/sleep 0.15
            printf 'Progress: (unknown)\\r' >&2
            /bin/sleep 0.15
            printf 'Progress: (unknown)\\r' >&2
            /bin/sleep 0.15
            exec /bin/cat \(shellQuote(sourceTIFF.path))
            """
        } else if progressUpdatesDuringDelay {
            acquisition = """
            printf 'Progress: 1%%\\r' >&2
            /bin/sleep 0.15
            printf 'Progress: 25%%\\r' >&2
            /bin/sleep 0.15
            printf 'Progress: 60%%\\r' >&2
            /bin/sleep 0.15
            printf 'Progress: 80%%\\r' >&2
            /bin/sleep 0.15
            printf 'Progress: 95%%\\r' >&2
            /bin/sleep 0.15
            exec /bin/cat \(shellQuote(sourceTIFF.path))
            """
        } else if progressBeforeDelay {
            if noiseDuringDelay {
                acquisition = """
                printf 'Progress: 1%%\\r' >&2
                /bin/sleep 0.06
                printf 'scanner still busy\\n' >&2
                /bin/sleep 0.06
                printf 'scanner still busy\\n' >&2
                /bin/sleep 0.3
                exec /bin/cat \(shellQuote(sourceTIFF.path))
                """
            } else {
                acquisition = """
                printf 'Progress: 1%%\\r' >&2
                /bin/sleep 0.3
                exec /bin/cat \(shellQuote(sourceTIFF.path))
                """
            }
        } else {
            acquisition = "exec /bin/cat \(shellQuote(sourceTIFF.path))"
        }
        let discovery = blockingDiscovery
            ? "exec /bin/sleep 30"
            : """
              echo "device \\`genesys:libusb:000:010' is a PLUSTEK Ownership Test film scanner"
              exit 0
              """
        let script = """
        #!/bin/sh
        if [ "$1" = "hold" ]; then
          trap 'exit 0' TERM INT
          while :; do /bin/sleep 1; done
        fi
        if [ "$1" = "-L" ]; then
          \(discovery)
        fi
        if [ "$1" = "-f" ]; then
          printf 'genesys:libusb:000:010\\tPLUSTEK\\tOwnership Test\\tfilm scanner\\n'
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
        printf '%s\\n' "$*" >> \(shellQuote(root.appendingPathComponent("arguments.log").path))
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
        if [ "$1" = "-f" ]; then
          printf 'epson2:libusb:001:005\\tEpson\\tPosition Test\\tflatbed scanner\\n'
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
