import Foundation
import CoreGraphics
import CoreImage
import ImageIO

extension SANEBackend {
    static func findScanimage() -> String {
        let candidates = [
            "/opt/homebrew/opt/sane-backends-negaflow/bin/scanimage",
            "/usr/local/opt/sane-backends-negaflow/bin/scanimage",
            "/opt/homebrew/bin/scanimage",
            "/usr/local/bin/scanimage",
            "/usr/bin/scanimage",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        return "scanimage"
    }

    /// SANE 설정 디렉토리(dll.conf, genesys.conf 등이 있는 곳)를 찾는다.
    /// Homebrew 로 설치한 경우 기본 컴파일 경로에 없으므로 SANE_CONFIG_DIR 가 필요하다.
    /// scanimage 가 이 디렉토리를 못 찾으면 "open of device failed: Invalid argument".
    static func findSaneConfigDir(
        scanimagePath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        // 선택된 scanimage와 같은 keg의 설정을 우선한다. patched scanimage에
        // stock SANE_CONFIG_DIR가 섞이면 Coolscan backend 패치가 우회될 수 있다.
        let selectedScanimage = scanimagePath ?? environment["NEGAFLOW_SCANIMAGE_PATH"]
        let selectedConfigDir = selectedScanimage
            .map {
                URL(fileURLWithPath: $0)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("etc/sane.d")
                    .path
            }
        if let selectedConfigDir,
           FileManager.default.fileExists(atPath: selectedConfigDir) {
            return selectedConfigDir
        }
        // 같은 keg 설정이 없을 때만 명시적 환경변수를 보존한다.
        if let v = environment["SANE_CONFIG_DIR"],
           FileManager.default.fileExists(atPath: v) { return v }
        let candidates = [
            "/opt/homebrew/etc/sane.d",
            "/usr/local/etc/sane.d",
            "/etc/sane.d",
        ]
        for c in candidates {
            if FileManager.default.fileExists(atPath: c) { return c }
        }
        return nil
    }

    /// GUI .app 환경에서는 기본 PATH 가 /usr/bin:/bin 뿐이라 scanimage 가
    /// 의존하는 동적 라이브러리(libsane)나 SANE_CONFIG_DIR 를 못 찾는다.
    /// 따라서 Process 에 명시적으로 환경을 주입한다.
    static func makeSaneEnvironment(
        scanimagePath: String? = nil,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = baseEnvironment
        // scanimage -A/--help 파싱은 영문 옵션명과 "." 소수점을 계약으로 사용한다.
        env["LC_ALL"] = "C"
        env["LANG"] = "C"
        // Homebrew 경로를 PATH 앞에 추가(libsane*.dylib 해석 + 일반 도구 접근).
        let selectedScanimage = scanimagePath ?? baseEnvironment["NEGAFLOW_SCANIMAGE_PATH"]
        let toolPrefix = selectedScanimage
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        let pathPrefixes = [
            toolPrefix,
            "/opt/homebrew/bin", "/opt/homebrew/sbin",
            "/usr/local/bin", "/usr/local/sbin",
        ]
            .compactMap { $0 }
            .joined(separator: ":")
        let existing = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "\(pathPrefixes):\(existing)"
        // SANE 설정 디렉토리.
        if let cfg = findSaneConfigDir(
            scanimagePath: selectedScanimage,
            environment: baseEnvironment
        ) {
            env["SANE_CONFIG_DIR"] = cfg
        }
        // SANE dll backend가 동적 backend를 찾을 때 실제로 읽는 검색 경로.
        // SANE_BACKENDS_PATH라는 환경변수는 upstream SANE 1.4 계약에 없다.
        let selectedLibDir = selectedScanimage
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/sane").path }
        let selectedLibDirs = [selectedLibDir]
            .compactMap { $0 }
            .filter { FileManager.default.fileExists(atPath: $0) }
        if !selectedLibDirs.isEmpty {
            // 선택한 scanimage와 backend를 한 keg에서 가져와야 patched Coolscan
            // backend가 stock 환경변수에 의해 우회되지 않는다.
            let selectedPath = selectedLibDirs.joined(separator: ":")
            if let existing = env["LD_LIBRARY_PATH"], !existing.isEmpty {
                env["LD_LIBRARY_PATH"] = "\(selectedPath):\(existing)"
            } else {
                env["LD_LIBRARY_PATH"] = selectedPath
            }
        }
        return env
    }

    public static func makeTempURL(prefix: String, suffix: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("\(prefix)_\(UUID().uuidString)\(suffix)")
    }

    public static func imageSize(at url: URL) -> (Int, Int) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
              let w = props["PixelWidth"] as? Int,
              let h = props["PixelHeight"] as? Int
        else { return (0, 0) }
        return (w, h)
    }
}
