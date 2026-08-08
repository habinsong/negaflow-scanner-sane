// swift-tools-version: 5.9
import PackageDescription

// negaflow-scanner-sane — negaflow용 SANE 필름 스캐너 플러그인(외부 프로세스)
//
// negaflow(Apache-2.0)와 완전히 독립된 프로그램이다. SANE(scanimage, GPL)로 스캐너를
// 인식/제어하고 결과를 negaflow JSON/CLI 계약으로 낸다. 이 패키지는 GPL-2.0-or-later 로 배포된다.
//
//   SANEPluginCore        : SANE 백엔드 + 모델 + TIFF 로더(라이브러리, 테스트 가능)
//   negaflow-scanner-sane : JSON/CLI 프로토콜 어댑터(얇은 실행파일)
let package = Package(
    name: "negaflow-scanner-sane",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "negaflow-scanner-sane", targets: ["negaflow-scanner-sane"]),
    ],
    targets: [
        .target(
            name: "SANEPluginCore",
            path: "Sources/SANEPluginCore",
            linkerSettings: [
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(
            name: "negaflow-scanner-sane",
            dependencies: ["SANEPluginCore"],
            path: "Sources/negaflow-scanner-sane"
        ),
        .testTarget(
            name: "SANEPluginCoreTests",
            dependencies: ["SANEPluginCore"],
            path: "Tests/SANEPluginCoreTests"
        ),
    ]
)
