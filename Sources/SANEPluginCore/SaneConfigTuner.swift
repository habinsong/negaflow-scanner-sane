import Foundation

// MARK: - SaneConfigTuner
//
// 과거 버전은 scanimage -L 시간을 줄이려고 Homebrew의 공용 dll.conf에서
// Negaflow가 사용하지 않는 백엔드를 주석 처리했다. 그러나 dll.conf는 시스템의 모든
// SANE 프런트엔드가 공유하므로, 이 방식은 네트워크·복합기·문서 스캐너를 감지하지
// 못하게 만들 수 있다. 현재 구현은 백엔드를 새로 끄지 않고, 과거 Negaflow가
// 주석 처리한 줄만 복원한다.
public enum SaneConfigTuner {
    public static var configDir: String {
        if let value = ProcessInfo.processInfo.environment["SANE_CONFIG_DIR"],
           FileManager.default.fileExists(atPath: value) {
            return value
        }
        for candidate in ["/opt/homebrew/etc/sane.d", "/usr/local/etc/sane.d", "/etc/sane.d"]
        where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        return "/opt/homebrew/etc/sane.d"
    }

    public static var dllConfPath: String { configDir + "/dll.conf" }
    public static var backupPath: String { configDir + "/dll.conf.negaflow-backup" }

    static let disabledPrefix = "# [negaflow] 비활성화: "

    public enum RecoveryResult: Equatable {
        case notNeeded
        case recovered(lines: Int)
        case failed(String)
    }

    /// 과거 Negaflow가 비활성화한 줄만 다시 활성화한다.
    ///
    /// 배포판 또는 사용자가 원래 주석 처리한 줄은 그대로 두며, 최초 백업으로 전체 파일을
    /// 되감지 않으므로 이후에 추가된 사용자 설정도 보존한다. 심볼릭 링크인 경우 링크가
    /// 가리키는 파일에 원자적으로 기록해 링크 자체를 교체하지 않는다.
    @discardableResult
    public static func recoverLegacyFiltering() -> RecoveryResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: dllConfPath) else {
            return .notNeeded
        }
        guard let current = try? String(contentsOfFile: dllConfPath, encoding: .utf8) else {
            return .failed("dll.conf 읽기 실패: \(dllConfPath)")
        }

        let recovery = restoreNegaflowDisabledLines(in: current)
        guard recovery.lines > 0 else {
            return .notNeeded
        }

        let destination = URL(fileURLWithPath: dllConfPath).resolvingSymlinksInPath()
        do {
            try recovery.content.write(to: destination, atomically: true, encoding: .utf8)
            return .recovered(lines: recovery.lines)
        } catch {
            return .failed("dll.conf 복구 실패: \(error.localizedDescription)")
        }
    }

    /// 기존 CLI 호환용 별칭. 더 이상 dll.conf를 축소하지 않는다.
    @discardableResult
    public static func tune() -> RecoveryResult {
        recoverLegacyFiltering()
    }

    /// 최초 튜닝 전에 저장된 전체 백업으로 복구한다.
    ///
    /// 백업 이후 사용자가 변경한 내용까지 되돌릴 수 있으므로 자동으로 호출하지 않는다.
    @discardableResult
    public static func restore() -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: backupPath) else { return false }
        do {
            let backup = try String(contentsOfFile: backupPath, encoding: .utf8)
            let destination = URL(fileURLWithPath: dllConfPath).resolvingSymlinksInPath()
            try backup.write(to: destination, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    public static var hasLegacyFiltering: Bool {
        guard let current = try? String(contentsOfFile: dllConfPath, encoding: .utf8) else {
            return false
        }
        return current.split(separator: "\n", omittingEmptySubsequences: false).contains {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(disabledPrefix)
        }
    }

    public static var hasBackup: Bool {
        FileManager.default.fileExists(atPath: backupPath)
    }

    public static var activeBackends: [String] {
        guard let current = try? String(contentsOfFile: dllConfPath, encoding: .utf8) else {
            return []
        }
        return current.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { $0.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? $0 }
    }

    static func restoreNegaflowDisabledLines(in original: String) -> (content: String, lines: Int) {
        var restoredLineCount = 0
        let output = original.split(separator: "\n", omittingEmptySubsequences: false).map { raw -> String in
            let line = String(raw)
            let leadingWhitespace = line.prefix(while: { $0 == " " || $0 == "\t" })
            let trimmed = line.dropFirst(leadingWhitespace.count)
            guard trimmed.hasPrefix(disabledPrefix) else {
                return line
            }
            restoredLineCount += 1
            return String(leadingWhitespace) + String(trimmed.dropFirst(disabledPrefix.count))
        }
        return (output.joined(separator: "\n"), restoredLineCount)
    }
}
