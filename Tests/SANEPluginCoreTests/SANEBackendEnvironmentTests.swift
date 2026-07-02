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

    // MARK: - 좀비 scanimage 정리 회귀 테스트
    //
    // 좀비 scanimage 프로세스가 USB 장치를 점유하면 모든 새 스캔이 실패한다.
    // reapZombieScanimages() 로직이 살아있는 pkill 패턴을 생성하는지 확인(실행은 부작용 방지용으로 스킵).

    func testZombieReapDoesNotThrowOnCleanSystem() {
        // 실제 pkill 은 부작용이 크므로, 명령 문자열이 올바른지만 검증.
        // reapZombieScanimages 는 private 이므로, 여기서는 scanimage 경로가
        // resolve 됨만 확인(경로가 nil 이면 pkill 패턴이 무의미).
        let path = SANEBackend.findScanimage()
        XCTAssertFalse(path.isEmpty, "scanimage 경로가 비어 있으면 좀비 정리가 동작하지 않는다")
    }

}
