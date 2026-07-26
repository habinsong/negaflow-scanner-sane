import XCTest
@testable import SANEPluginCore

final class SaneConfigTunerTests: XCTestCase {

    func testRecoveryRestoresOnlyLinesDisabledBynegaflow() {
        let oldTuned = """
        # dll.conf - Configuration file for the SANE dynamic backend loader
        # [negaflow] 비활성화: net
        # [negaflow] 비활성화: avision
        #coolscan2
        # [negaflow] 비활성화: coolscan3
        #epson
        # [negaflow] 비활성화: epson2
        # [negaflow] 비활성화: escl
        genesys
        # [negaflow] 비활성화: pieusb
        pint
        # [negaflow] 비활성화: pixma
          # [negaflow] 비활성화: fujitsu
        """

        let recovery = SaneConfigTuner.restoreNegaflowDisabledLines(in: oldTuned)
        let active = recovery.content.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        XCTAssertEqual(
            Set(active),
            ["net", "avision", "coolscan3", "epson2", "escl", "genesys", "pieusb", "pint", "pixma", "fujitsu"]
        )
        XCTAssertEqual(recovery.lines, 8)
        XCTAssertTrue(recovery.content.contains("#coolscan2"))
        XCTAssertTrue(recovery.content.contains("#epson"))
        XCTAssertFalse(recovery.content.contains(SaneConfigTuner.disabledPrefix))
    }

    func testRecoveryIsIdempotentAndNeverDisablesActiveBackends() {
        let original = """
        net
        escl
        pixma
        fujitsu
        genesys
        #coolscan2
        """

        let first = SaneConfigTuner.restoreNegaflowDisabledLines(in: original)
        let second = SaneConfigTuner.restoreNegaflowDisabledLines(in: first.content)

        XCTAssertEqual(first.content, original)
        XCTAssertEqual(first.lines, 0)
        XCTAssertEqual(second.content, original)
        XCTAssertEqual(second.lines, 0)
    }
}
