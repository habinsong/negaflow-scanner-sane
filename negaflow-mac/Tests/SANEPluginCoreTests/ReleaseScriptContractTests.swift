import Foundation
import XCTest

final class ReleaseScriptContractTests: XCTestCase {
    func testInstallerNotarizesStandalonePackageBeforeEmbeddingItInDMG() throws {
        let script = try source(named: "scripts/build-installer.sh")
        let packageNotarization = try XCTUnwrap(
            script.range(of: #"notarize_artifact "$BUILT_PKG" "pkg""#)
        )
        let packageCopy = try XCTUnwrap(
            script.range(of: #"cp "$BUILT_PKG" "$DMG_ROOT/$DMG_PKG_NAME""#)
        )
        let diskImageNotarization = try XCTUnwrap(
            script.range(of: #"notarize_artifact "$BUILT_DMG" "dmg""#)
        )

        XCTAssertLessThan(packageNotarization.lowerBound, packageCopy.lowerBound)
        XCTAssertLessThan(packageCopy.lowerBound, diskImageNotarization.lowerBound)
    }

    func testDistributionVerifierValidatesBothStapledContainers() throws {
        let verifier = try source(named: "scripts/verify-installer.sh")

        XCTAssertTrue(verifier.contains(#"xcrun stapler validate "$PKG""#))
        XCTAssertTrue(verifier.contains(#"spctl --assess --type install --verbose=4 "$PKG""#))
        XCTAssertTrue(verifier.contains(#"xcrun stapler validate "$DMG""#))
    }

    func testStandaloneReleaseIncludesMatchingSourceArchive() throws {
        let packager = try source(named: "scripts/package-release.sh")
        let verifier = try source(named: "scripts/verify-release.sh")

        XCTAssertTrue(packager.contains("scripts/create-source-archive.sh"))
        XCTAssertTrue(
            packager.contains(#"cp "$STAGING/$SOURCE_NAME" "$PLUGIN_DIR/$SOURCE_NAME""#)
        )
        XCTAssertTrue(packager.contains(#""$ZIP_NAME" "$DSYM_NAME" "$SOURCE_NAME""#))
        XCTAssertTrue(verifier.contains(#"test -s "$PACKAGED_SOURCE""#))
        XCTAssertTrue(verifier.contains(#"tar -tzf "$SOURCE_ARCHIVE""#))
    }

    func testSourceArchiveIsReproducible() throws {
        let root = packageRoot
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-source-repro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let first = temporary.appendingPathComponent("first.tar.gz")
        let second = temporary.appendingPathComponent("second.tar.gz")

        try runSourceArchiver(root: root, output: first)
        try runSourceArchiver(root: root, output: second)

        XCTAssertEqual(try Data(contentsOf: first), try Data(contentsOf: second))
    }

    func testDistributionWorkflowBuildsAndVerifiesBothReleaseSurfaces() throws {
        let workflow = try source(named: ".github/workflows/distribution.yml")

        XCTAssertTrue(workflow.contains("environment: distribution"))
        XCTAssertTrue(workflow.contains("NEGAFLOW_RELEASE_MODE: distribution"))
        XCTAssertTrue(workflow.contains("NEGAFLOW_INSTALLER_MODE: distribution"))
        XCTAssertTrue(workflow.contains("NEGAFLOW_CODESIGN_IDENTITY"))
        XCTAssertTrue(workflow.contains("NEGAFLOW_INSTALLER_SIGN_IDENTITY"))
        XCTAssertTrue(workflow.contains("NEGAFLOW_NOTARY_PRIVATE_KEY_BASE64"))
        XCTAssertTrue(workflow.contains("scripts/verify-release.sh"))
        XCTAssertTrue(workflow.contains("scripts/verify-installer.sh"))
        // 산출물은 macOS 트리 안에 쌓인다. 저장소 루트 기준 경로를 남겨 두면 태그를 밀
        // 때에만 도는 이 잡이 릴리즈 당일에 빈손으로 실패한다(v1.0.4에서 실제로 겪었다).
        XCTAssertTrue(workflow.contains("ARTIFACTS=negaflow-mac/.build/release-artifacts"))
        XCTAssertTrue(workflow.contains(#"cd "$ARTIFACTS""#))
        XCTAssertFalse(workflow.contains(" .build/release-artifacts"))
        XCTAssertTrue(workflow.contains("shasum -a 256 -c SHA256SUMS.txt"))
        XCTAssertTrue(workflow.contains("actions/upload-artifact@v7"))
        XCTAssertFalse(workflow.contains("NEGAFLOW_RELEASE_MODE: local"))
        XCTAssertFalse(workflow.contains("NEGAFLOW_INSTALLER_MODE: local"))
    }

    func testMacOS26WorkflowsActuallyBuildPatchedCoolscanFormula() throws {
        for path in [
            ".github/workflows/ci.yml",
            ".github/workflows/distribution.yml",
        ] {
            let workflow = try source(named: path)
            XCTAssertTrue(workflow.contains("runs-on: macos-26"), path)
            XCTAssertTrue(workflow.contains("bash negaflow-mac/scripts/install-patched-sane.sh"), path)
        }
    }

    func testInstallerBuildsAndVerifiesAppleSiliconAndUniversalVariants() throws {
        let builder = try source(named: "scripts/build-installer.sh")
        let verifier = try source(named: "scripts/verify-installer.sh")

        XCTAssertTrue(builder.contains("for architecture in arm64 universal"))
        XCTAssertTrue(builder.contains(#"lipo "$UNIVERSAL_PLUGIN_BINARY" -thin arm64"#))
        XCTAssertTrue(builder.contains(#""$INSTALLER_ARCHITECTURE""#))
        XCTAssertTrue(verifier.contains(#"[[ "$architectures" == "arm64" ]]"#))
        XCTAssertTrue(verifier.contains(#"grep -qw x86_64 <<<"$architectures""#))
    }

    func testInstallerSeparatesStandardAndPatchedCoolscanVariants() throws {
        let builder = try source(named: "scripts/build-installer.sh")
        let verifier = try source(named: "scripts/verify-installer.sh")

        XCTAssertTrue(builder.contains("NEGAFLOW_INSTALLER_VARIANT"))
        XCTAssertTrue(builder.contains(#"MIN_OS_VERSION="14.0""#))
        XCTAssertTrue(builder.contains(#"MIN_OS_VERSION="26.0""#))
        XCTAssertTrue(builder.contains(#"ARTIFACT_PLATFORM="mac14""#))
        XCTAssertTrue(builder.contains(#"ARTIFACT_PLATFORM="mac26""#))
        XCTAssertTrue(builder.contains("Installer/Scripts/postinstall-coolscan"))
        XCTAssertTrue(verifier.contains(#"EXPECTED_VARIANT="$4""#))
        XCTAssertTrue(verifier.contains(#"EXPECTED_MIN_OS="14.0""#))
        XCTAssertTrue(verifier.contains(#"EXPECTED_MIN_OS="26.0""#))
    }

    /// Swift 패키지 루트(negaflow-mac). 스크립트와 소스가 여기에 있다.
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// 저장소 루트. 워크플로처럼 플랫폼 트리 밖에 있는 것은 여기서 찾는다.
    private var repositoryRoot: URL { packageRoot.deletingLastPathComponent() }

    private func source(named relativePath: String) throws -> String {
        // `.github/` 는 저장소 루트, 나머지는 패키지 루트 기준이다.
        let base = relativePath.hasPrefix(".github/") ? repositoryRoot : packageRoot
        return try String(
            contentsOf: base.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func runSourceArchiver(root: URL, output: URL) throws {
        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            root.appendingPathComponent("scripts/create-source-archive.sh").path,
            output.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
