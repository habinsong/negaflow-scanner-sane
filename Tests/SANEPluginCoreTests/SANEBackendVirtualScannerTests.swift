import Foundation
import XCTest
@testable import SANEPluginCore

final class SANEBackendVirtualScannerTests: XCTestCase {
    func testEpsonV700V750V800V850PreviewAndPositionedScansUseTPU8x10() async throws {
        XCTAssertEqual(VirtualSANEDevice.epsonFilmFlatbeds.count, 4)

        for device in VirtualSANEDevice.epsonFilmFlatbeds {
            let fixture = try VirtualScanimageFixture(device: device)
            defer { fixture.cleanup() }
            let backend = SANEBackend(scanimagePath: fixture.executableURL.path)

            let detected = try await backend.detectScanners()
            let descriptor = try XCTUnwrap(detected.only, device.name)
            XCTAssertEqual(descriptor.model, device.model, device.name)
            XCTAssertEqual(descriptor.connectionType, .usb, device.name)
            XCTAssertEqual(descriptor.verifiedStatus, .compatibleTarget, device.name)

            let report = try await backend.getCapabilitiesReport(scannerID: descriptor.id)
            let capabilities = report.capabilities
            XCTAssertTrue(capabilities.supportsPreview, device.name)
            XCTAssertTrue(capabilities.supportsTransparency, device.name)
            XCTAssertTrue(capabilities.supportsPositionedScanArea, device.name)
            XCTAssertEqual(capabilities.maxScanArea.widthMM, 203.2, accuracy: 0.001, device.name)
            XCTAssertEqual(capabilities.maxScanArea.heightMM, 254, accuracy: 0.001, device.name)
            XCTAssertTrue(capabilities.supportedResolutions.contains(device.fullScanResolution), device.name)

            let preview = ScanOptions(
                scannerID: descriptor.id,
                resolution: .preview,
                bitDepth: .eight,
                colorMode: .color,
                filmType: .colorNegative,
                scanArea: device.previewArea,
                outputRawTIFF: false,
                temporaryOutputURL: fixture.outputURL("preview.tiff"),
                capabilityToken: report.capabilityToken
            )
            let previewResult = try await backend.startPreviewScan(preview) { _ in }
            XCTAssertEqual(previewResult.width, 80, device.name)
            XCTAssertEqual(previewResult.height, 100, device.name)
            XCTAssertEqual(previewResult.bitDepth, .eight, device.name)

            let first = ScanOptions(
                scannerID: descriptor.id,
                resolution: device.fullScanResolution,
                bitDepth: .sixteen,
                colorMode: .color,
                filmType: .colorNegative,
                scanArea: ScanArea(originXMM: 10, originYMM: 20, widthMM: 36, heightMM: 24),
                outputRawTIFF: true,
                temporaryOutputURL: fixture.outputURL("first.tiff"),
                capabilityToken: report.capabilityToken
            )
            var second = first
            second.scanArea = ScanArea(originXMM: 90, originYMM: 120, widthMM: 36, heightMM: 24)
            second.temporaryOutputURL = fixture.outputURL("second.tiff")

            let firstResult = try await backend.startFullScan(first) { _ in }
            let secondResult = try await backend.startFullScan(second) { _ in }
            XCTAssertEqual(firstResult.width, 60, device.name)
            XCTAssertEqual(firstResult.height, 40, device.name)
            XCTAssertEqual(secondResult.width, 60, device.name)
            XCTAssertEqual(secondResult.height, 40, device.name)
            XCTAssertNotEqual(
                try Data(contentsOf: firstResult.rawFileURL),
                try Data(contentsOf: secondResult.rawFileURL),
                "서로 다른 Epson ROI가 같은 가상 획득 결과를 반환했습니다: \(device.name)"
            )

            let log = try fixture.invocations()
            XCTAssertTrue(
                log.contains("-A -d \(device.address) --source TPU8x10"),
                device.name
            )
            XCTAssertTrue(
                log.contains("--source TPU8x10 --mode Color"),
                device.name
            )
            XCTAssertTrue(
                log.contains("--film-type Negative Film"),
                device.name
            )
            XCTAssertTrue(
                log.contains("--color-correction None --gamma-correction User defined"),
                device.name
            )
            XCTAssertTrue(log.contains("-l 10 -t 20 -x 36 -y 24"), device.name)
            XCTAssertTrue(log.contains("-l 90 -t 120 -x 36 -y 24"), device.name)
            let optionReads = log.split(separator: "\n").filter { $0.hasPrefix("-A ") }
            XCTAssertEqual(
                optionReads.count,
                2,
                "Epson은 capability의 base/source 조회 뒤 실제 scan에서 -A를 다시 실행하지 않아야 합니다: \(device.name)"
            )
            let acquisitions = log.split(separator: "\n").filter {
                !$0.hasPrefix("-L") && !$0.hasPrefix("-f") && !$0.hasPrefix("-A")
            }
            XCTAssertTrue(
                acquisitions.allSatisfy { $0.contains("-d epson2 ") },
                "단일 epson2 USB 장치는 주소가 바뀌어도 유효한 backend 선택자를 써야 합니다: \(device.name)"
            )
        }
    }

    func testAllMajorSupportedOpticFilmModelsPreviewAndFullScan() async throws {
        let devices = VirtualSANEDevice.opticFilmScanners
        XCTAssertEqual(devices.count, 9)
        XCTAssertEqual(Set(devices.map(\.usbProductID)).count, devices.count)
        XCTAssertTrue(Set(devices.map(\.usbProductID)).isDisjoint(
            with: VirtualSANEDevice.unsupportedOpticFilmProductIDs
        ))

        for device in devices {
            let fixture = try VirtualScanimageFixture(device: device)
            defer { fixture.cleanup() }
            let backend = SANEBackend(scanimagePath: fixture.executableURL.path)

            let detected = try await backend.detectScanners()
            let descriptor = try XCTUnwrap(detected.only, device.name)
            XCTAssertEqual(descriptor.connectionType, .usb, device.name)
            XCTAssertEqual(descriptor.verifiedStatus, .compatibleTarget, device.name)

            let report = try await backend.getCapabilitiesReport(scannerID: descriptor.id)
            let capabilities = report.capabilities
            XCTAssertTrue(capabilities.supportsPreview, device.name)
            XCTAssertTrue(capabilities.supportsTransparency, device.name)
            XCTAssertFalse(capabilities.supportsPositionedScanArea, device.name)
            XCTAssertEqual(capabilities.supportsInfrared, device.supportsInfrared, device.name)
            XCTAssertTrue(capabilities.supportedResolutions.contains(device.fullScanResolution), device.name)

            let preview = ScanOptions(
                scannerID: descriptor.id,
                resolution: .preview,
                bitDepth: .sixteen,
                colorMode: .color,
                filmType: .colorNegative,
                scanArea: device.previewArea,
                outputRawTIFF: false,
                temporaryOutputURL: fixture.outputURL("preview.tiff"),
                capabilityToken: report.capabilityToken
            )
            let previewResult = try await backend.startPreviewScan(preview) { _ in }
            XCTAssertEqual(previewResult.width, 60, device.name)
            XCTAssertEqual(previewResult.height, 40, device.name)
            XCTAssertEqual(previewResult.bitDepth, .sixteen, device.name)

            let full = ScanOptions(
                scannerID: descriptor.id,
                resolution: device.fullScanResolution,
                bitDepth: .sixteen,
                colorMode: .color,
                filmType: .colorNegative,
                scanArea: device.previewArea,
                infraredEnabled: device.supportsInfrared,
                outputRawTIFF: true,
                temporaryOutputURL: fixture.outputURL("full.tiff"),
                capabilityToken: report.capabilityToken
            )
            let fullResult = try await backend.startFullScan(full) { _ in }
            XCTAssertEqual(fullResult.width, 60, device.name)
            XCTAssertEqual(fullResult.height, 40, device.name)
            XCTAssertEqual(fullResult.hasInfraredChannel, device.supportsInfrared, device.name)
            XCTAssertEqual(fullResult.infraredFileURL != nil, device.supportsInfrared, device.name)

            let log = try fixture.invocations()
            XCTAssertTrue(log.contains("--source Transparency Adapter --mode Color"), device.name)
            XCTAssertTrue(log.contains("--resolution 3600 --depth 16"), device.name)
            let invocations = log.split(separator: "\n").map(String.init)
            let optionReads = invocations.filter { $0.hasPrefix("-A ") }
            XCTAssertEqual(
                optionReads.count,
                1,
                "genesys는 capability에서 한 번 조회하고 preview/full scan에서 -A를 다시 실행하지 않아야 합니다: \(device.name)"
            )
            XCTAssertTrue(
                optionReads.allSatisfy {
                    $0.contains("-d \(device.address) ")
                        || $0.hasSuffix("-d \(device.address)")
                },
                "capability 조회는 발견한 전체 장치 ID를 유지해야 합니다: \(device.name)"
            )
            XCTAssertTrue(
                invocations
                    .filter { !$0.hasPrefix("-L") && !$0.hasPrefix("-f") && !$0.hasPrefix("-A") }
                    .allSatisfy { $0.contains("-d genesys ") },
                "단일 genesys USB 장치는 주소가 바뀌어도 유효한 backend 선택자를 써야 합니다: \(device.name)"
            )
            if device.supportsInfrared {
                XCTAssertTrue(log.contains("--source Transparency Adapter Infrared"), device.name)
                XCTAssertTrue(log.contains("--mode Gray"), device.name)
            }
        }
    }

    func testNikonCoolscanBackendsUseExactGeometryWithoutClaimingRGBIAsInfraredTIFF() async throws {
        XCTAssertEqual(VirtualSANEDevice.nikonCoolscanScanners.count, 6)

        for device in VirtualSANEDevice.nikonCoolscanScanners {
            let fixture = try VirtualScanimageFixture(device: device)
            defer { fixture.cleanup() }
            let backend = SANEBackend(scanimagePath: fixture.executableURL.path)

            let detected = try await backend.detectScanners()
            let descriptor = try XCTUnwrap(detected.only, device.name)
            let report = try await backend.getCapabilitiesReport(scannerID: descriptor.id)
            XCTAssertTrue(report.capabilities.supportsPreview, device.name)
            XCTAssertTrue(report.capabilities.supportsTransparency, device.name)
            XCTAssertFalse(report.capabilities.supportsInfrared, device.name)
            XCTAssertEqual(report.capabilities.supportedModes, [.color], device.name)

            let preview = ScanOptions(
                scannerID: descriptor.id,
                resolution: .preview,
                bitDepth: .eight,
                colorMode: .color,
                filmType: .colorNegative,
                scanArea: device.previewArea,
                outputRawTIFF: false,
                temporaryOutputURL: fixture.outputURL("preview.tiff"),
                capabilityToken: report.capabilityToken
            )
            let previewResult = try await backend.startPreviewScan(preview) { _ in }
            XCTAssertEqual(previewResult.bitDepth, .eight, device.name)

            let full = ScanOptions(
                scannerID: descriptor.id,
                resolution: device.fullScanResolution,
                bitDepth: .sixteen,
                colorMode: .color,
                filmType: .colorNegative,
                scanArea: device.previewArea,
                infraredEnabled: false,
                outputRawTIFF: true,
                temporaryOutputURL: fixture.outputURL("full.tiff"),
                capabilityToken: report.capabilityToken
            )
            let fullResult = try await backend.startFullScan(full) { _ in }
            XCTAssertFalse(fullResult.hasInfraredChannel, device.name)
            XCTAssertNil(fullResult.infraredFileURL, device.name)

            let invocations = try fixture.invocations()
                .split(separator: "\n")
                .map(String.init)
            XCTAssertEqual(invocations.filter { $0.hasPrefix("-A ") }.count, 1, device.name)
            let acquisition = try XCTUnwrap(invocations.last, device.name)
            XCTAssertTrue(
                acquisition.contains("-d \(device.address) "),
                "coolscan3는 빈 장치명을 거부하므로 전체 장치 주소로 열어야 합니다: \(device.name)"
            )
            XCTAssertFalse(acquisition.contains("-d coolscan3 "), device.name)
            XCTAssertTrue(
                acquisition.contains("--tl-x 0 --tl-y 0 --br-x 5668 --br-y 3779"),
                device.name
            )
            XCTAssertFalse(acquisition.contains("--infrared"), device.name)
            XCTAssertFalse(acquisition.contains("--batch"), device.name)
            XCTAssertFalse(acquisition.contains("--mode"), device.name)
            XCTAssertFalse(acquisition.contains("--source"), device.name)
            XCTAssertTrue(acquisition.contains("--negative=no"), device.name)
        }
    }

    func testPieusbSlideBackendsPreserveCapabilityDrivenPreviewAndFullScan() async throws {
        XCTAssertEqual(VirtualSANEDevice.pieusbScanners.count, 2)

        for device in VirtualSANEDevice.pieusbScanners {
            let fixture = try VirtualScanimageFixture(device: device)
            defer { fixture.cleanup() }
            let backend = SANEBackend(scanimagePath: fixture.executableURL.path)

            let detected = try await backend.detectScanners()
            let descriptor = try XCTUnwrap(detected.only, device.name)
            let report = try await backend.getCapabilitiesReport(scannerID: descriptor.id)
            XCTAssertTrue(report.capabilities.supportsPreview, device.name)
            XCTAssertTrue(report.capabilities.supportsTransparency, device.name)
            XCTAssertFalse(
                report.capabilities.supportsInfrared,
                "clean-image는 별도 IR 채널 capability가 아닙니다: \(device.name)"
            )

            let preview = ScanOptions(
                scannerID: descriptor.id,
                resolution: .preview,
                bitDepth: .eight,
                colorMode: .color,
                filmType: .colorPositive,
                scanArea: device.previewArea,
                outputRawTIFF: false,
                temporaryOutputURL: fixture.outputURL("preview.tiff"),
                capabilityToken: report.capabilityToken
            )
            _ = try await backend.startPreviewScan(preview) { _ in }

            let full = ScanOptions(
                scannerID: descriptor.id,
                resolution: device.fullScanResolution,
                bitDepth: .sixteen,
                colorMode: .color,
                filmType: .colorPositive,
                scanArea: device.previewArea,
                outputRawTIFF: true,
                temporaryOutputURL: fixture.outputURL("full.tiff"),
                capabilityToken: report.capabilityToken
            )
            let result = try await backend.startFullScan(full) { _ in }
            XCTAssertFalse(result.hasInfraredChannel, device.name)

            let invocations = try fixture.invocations()
                .split(separator: "\n")
                .map(String.init)
            XCTAssertEqual(invocations.filter { $0.hasPrefix("-A ") }.count, 1, device.name)
            let fullInvocation = try XCTUnwrap(
                invocations.last { $0.contains("--resolution 3600") },
                device.name
            )
            XCTAssertTrue(
                fullInvocation.contains("-d \(device.address) "),
                "축약이 필요하지 않은 backend는 발견한 전체 장치 주소를 유지해야 합니다: \(device.name)"
            )
            XCTAssertTrue(fullInvocation.contains("--mode Color"), device.name)
            XCTAssertFalse(fullInvocation.contains("--clean-image=yes"), device.name)
            XCTAssertTrue(fullInvocation.contains("--advance=no"), device.name)
        }
    }

    func testLegacyConnectionsAreNotReportedAsUSBAndVirtualDevicesAreNotVerified() {
        XCTAssertEqual(SANEBackend.connectionType(of: "coolscan3:scsi:/dev/sg0"), .scsi)
        XCTAssertEqual(SANEBackend.connectionType(of: "coolscan3:firewire:scanner0"), .fireWire)
        XCTAssertEqual(SANEBackend.connectionType(of: "epson2:net:192.168.0.2"), .network)
        XCTAssertEqual(SANEBackend.connectionType(of: "genesys:libusb:000:010"), .usb)
        XCTAssertEqual(SANEBackend.connectionType(of: "vendor:internal:0"), .internalBus)
    }

    func testTPU8x10IsPreferredWithoutSelectingInfraredSource() {
        XCTAssertEqual(
            SANEBackend.preferredTransparencySource(in: [
                "Flatbed",
                "Transparency Unit",
                "Transparency Unit Infrared",
                "TPU8x10",
            ]),
            "TPU8x10"
        )
        XCTAssertEqual(
            SANEBackend.preferredTransparencySource(in: [
                "Transparency Adapter",
                "Transparency Adapter Infrared",
            ]),
            "Transparency Adapter"
        )
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
