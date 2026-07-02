import Foundation
import SANEPluginCore

// MARK: - negaflow-scanner-sane
//
// negaflow 스캐너 플러그인(외부 프로세스). SANE(scanimage)로 필름 스캐너를 인식/제어하고
// 결과를 negaflow JSON/CLI 계약으로 stdout에 낸다. negaflow(Apache-2.0)와 완전히 분리된
// 독립 프로그램이며 GPL-2.0-or-later 로 배포된다(SANE는 GPL).
//
// 서브커맨드:
//   detect                         → {"devices":[...]}
//   capabilities <deviceId>        → 능력 JSON
//   scan   (옵션 JSON을 stdin으로)  → 진행률 NDJSON 스트리밍 + 최종 {"type":"result",...}

/// stdout에 한 줄 JSON을 쓰고 즉시 flush한다(진행률 실시간 스트리밍).
func emitLine(_ object: Encodable) {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(AnyEncodable(object)),
          var line = String(data: data, encoding: .utf8) else { return }
    line.append("\n")
    FileHandle.standardOutput.write(Data(line.utf8))
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("[negaflow-scanner-sane] \(message)\n".utf8))
    exit(1)
}

/// Encodable 지우개(다양한 응답 타입을 한 emit 함수로 인코딩).
struct AnyEncodable: Encodable {
    let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}

let arguments = CommandLine.arguments
let subcommand = arguments.count > 1 ? arguments[1] : "help"
let backend = SANEBackend()

switch subcommand {
case "detect":
    let devices = (try? await backend.detectScanners()) ?? []
    let wire = PluginDetectResponse(devices: devices.map { d in
        PluginDevice(
            id: d.id, displayName: d.displayName, vendor: d.vendor, model: d.model,
            connectionType: d.connectionType.rawValue,
            usbVendorID: d.usbVendorID, usbProductID: d.usbProductID, serialNumber: d.serialNumber,
            verifiedStatus: d.verifiedStatus.rawValue, driverVersion: d.driverVersion
        )
    })
    emitLine(wire)

case "capabilities":
    guard arguments.count > 2 else { fail("usage: capabilities <deviceId>") }
    do {
        let caps = try await backend.getCapabilities(scannerID: arguments[2])
        emitLine(PluginCapabilities(
            resolutionsDPI: caps.supportedResolutions.map(\.dpi),
            modes: caps.supportedModes.map(\.rawValue),
            bitDepths: caps.supportedBitDepths.map(\.rawValue),
            supportsPreview: caps.supportsPreview,
            supportsTransparency: caps.supportsTransparency,
            supportsInfrared: caps.supportsInfrared,
            supportsMultiExposure: caps.supportsMultiExposure,
            supportsScanArea: caps.supportsScanArea,
            maxScanAreaWidthMM: caps.maxScanArea.widthMM,
            maxScanAreaHeightMM: caps.maxScanArea.heightMM,
            outputFormats: caps.outputFormats
        ))
    } catch {
        fail("capabilities 실패: \(error.localizedDescription)")
    }

case "scan":
    let stdinData = FileHandle.standardInput.readDataToEndOfFile()
    guard let wire = try? JSONDecoder().decode(PluginScanOptions.self, from: stdinData) else {
        emitLine(PluginScanEvent(type: "error", message: "scan 옵션 JSON 파싱 실패"))
        exit(1)
    }
    var options = ScanOptions.strongDefault(scannerID: wire.deviceID)
    options.resolution = Resolution(wire.resolutionDPI)
    options.bitDepth = BitDepth(rawValue: wire.bitDepth) ?? .sixteen
    options.colorMode = ColorMode(rawValue: wire.colorMode) ?? .color
    options.filmType = FilmType(rawValue: wire.filmType) ?? .colorNegative
    options.multiExposureEnabled = wire.multiExposure
    options.infraredEnabled = wire.infrared ?? false
    options.temporaryOutputURL = URL(fileURLWithPath: wire.outputPath)

    let onProgress: @Sendable (ScanProgress) -> Void = { p in
        emitLine(PluginScanEvent(type: "progress", phase: p.phase.rawValue,
                                 fraction: p.fraction, message: p.message))
    }
    do {
        let result = wire.preview
            ? try await backend.startPreviewScan(options, progress: onProgress)
            : try await backend.startFullScan(options, progress: onProgress)
        emitLine(PluginScanEvent(
            type: "result", width: result.width, height: result.height,
            path: result.rawFileURL.path,
            resolutionDPI: result.resolution.dpi, bitDepth: result.bitDepth.rawValue
        ))
    } catch {
        emitLine(PluginScanEvent(type: "error", message: error.localizedDescription))
        exit(1)
    }

default:
    let help = """
    negaflow-scanner-sane — negaflow SANE scanner plugin
    usage:
      negaflow-scanner-sane detect
      negaflow-scanner-sane capabilities <deviceId>
      negaflow-scanner-sane scan   (scan options JSON on stdin)
    """
    FileHandle.standardError.write(Data((help + "\n").utf8))
}
