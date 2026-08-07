import Foundation
import Darwin
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

private struct ScanRequestEnvelope: Decodable {
    var protocolVersion: Int?
    var requestID: UUID?
}

/// scan 이벤트의 requestID와 엄격히 증가하는 sequence를 한 곳에서 직렬화한다.
private final class ProtocolV2Emitter: @unchecked Sendable {
    private let requestID: UUID
    private let lock = NSLock()
    private var nextSequence: UInt64 = 0

    init(requestID: UUID) {
        self.requestID = requestID
    }

    func emit(
        type: String,
        phase: String? = nil,
        fraction: Double? = nil,
        message: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        path: String? = nil,
        resolutionDPI: Int? = nil,
        bitDepth: Int? = nil,
        irPath: String? = nil,
        hasInfrared: Bool? = nil,
        warnings: [String]? = nil,
        appliedOptions: PluginAppliedScanOptionsV2? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }
        let event = PluginScanEventV2(
            type: type,
            requestID: requestID,
            sequence: nextSequence,
            phase: phase,
            fraction: fraction,
            message: message,
            width: width,
            height: height,
            path: path,
            resolutionDPI: resolutionDPI,
            bitDepth: bitDepth,
            irPath: irPath,
            hasInfrared: hasInfrared,
            warnings: warnings,
            appliedOptions: appliedOptions
        )
        nextSequence += 1
        guard let data = try? JSONEncoder().encode(event) else { return }
        FileHandle.standardOutput.write(data + Data([0x0A]))
    }
}

/// 호스트가 플러그인에 보내는 종료 신호를 이 플러그인이 소유한 scanimage에 전달한다.
/// scanimage는 SIGTERM을 받으면 SANE의 sane_cancel()을 호출해 장치 점유를 해제한다.
private func installScanCancellationForwarders(
    backend: SANEBackend
) -> [DispatchSourceSignal] {
    [SIGTERM, SIGINT].map { signalNumber in
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(
            signal: signalNumber,
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        source.setEventHandler {
            Task {
                await backend.cancelScan()
            }
        }
        source.resume()
        return source
    }
}

let arguments = CommandLine.arguments
let subcommand = arguments.count > 1 ? arguments[1] : "help"
let backend = SANEBackend()
let cancellationForwarders = installScanCancellationForwarders(backend: backend)

switch subcommand {
case "detect":
    // 과거 버전이 공용 dll.conf에서 끈 백엔드만 되살린다. 사용자·배포판 주석은 보존한다.
    if SaneConfigTuner.hasLegacyFiltering {
        let result = SaneConfigTuner.recoverLegacyFiltering()
        FileHandle.standardError.write(Data("[negaflow-scanner-sane] dll.conf 레거시 필터 복구: \(result)\n".utf8))
    }
    let devices: [ScannerDescriptor]
    do {
        devices = try await backend.detectScanners()
    } catch {
        fail("detect 실패: \(error.localizedDescription)")
    }
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
        let requestData = isatty(FileHandle.standardInput.fileDescriptor) == 0
            ? FileHandle.standardInput.readDataToEndOfFile()
            : Data()
        let request = try? JSONDecoder().decode(PluginCapabilityRequest.self, from: requestData)
        let expectedIdentity = request.flatMap { request -> SANEBackend.DeviceIdentity? in
            guard request.deviceID == arguments[2],
                  !request.vendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return SANEBackend.DeviceIdentity(vendor: request.vendor, model: request.model)
        }
        let report = try await backend.getCapabilitiesReport(
            scannerID: arguments[2],
            expectedIdentity: expectedIdentity
        )
        let caps = report.capabilities
        emitLine(PluginCapabilities(
            resolutionsDPI: caps.supportedResolutions.map(\.dpi),
            modes: caps.supportedModes.map(\.rawValue),
            bitDepths: caps.supportedBitDepths.map(\.rawValue),
            sourceModes: caps.sourceModes,
            transparencyModes: caps.transparencyModes,
            supportsPreview: caps.supportsPreview,
            supportsTransparency: caps.supportsTransparency,
            supportsInfrared: caps.supportsInfrared,
            supportsMultiExposure: caps.supportsMultiExposure,
            supportsScanArea: caps.supportsScanArea,
            supportsPositionedScanArea: caps.supportsPositionedScanArea,
            brightnessRange: caps.brightnessRange,
            contrastRange: caps.contrastRange,
            hardwareExposureRange: caps.hardwareExposureRange,
            focusRange: caps.focusRange,
            supportsAutofocus: caps.supportsAutofocus,
            scanOriginXRange: caps.scanOriginXRange,
            scanOriginYRange: caps.scanOriginYRange,
            scanWidthRange: caps.scanWidthRange,
            scanHeightRange: caps.scanHeightRange,
            disabledReasons: caps.disabledReasons,
            minScanAreaWidthMM: caps.minScanArea.widthMM,
            minScanAreaHeightMM: caps.minScanArea.heightMM,
            minScanAreaOriginXMM: caps.minScanArea.originXMM,
            minScanAreaOriginYMM: caps.minScanArea.originYMM,
            maxScanAreaWidthMM: caps.maxScanArea.widthMM,
            maxScanAreaHeightMM: caps.maxScanArea.heightMM,
            maxScanAreaOriginXMM: caps.maxScanArea.originXMM,
            maxScanAreaOriginYMM: caps.maxScanArea.originYMM,
            scanAreaUnit: caps.scanAreaUnit.rawValue,
            outputFormats: caps.outputFormats,
            capabilityToken: report.capabilityToken
        ))
    } catch {
        fail("capabilities 실패: \(error.localizedDescription)")
    }

case "scan":
    let stdinData = FileHandle.standardInput.readDataToEndOfFile()
    let decoder = JSONDecoder()
    guard let wire = try? decoder.decode(PluginScanRequestV2.self, from: stdinData) else {
        if let envelope = try? decoder.decode(ScanRequestEnvelope.self, from: stdinData),
           envelope.protocolVersion == 2,
           let requestID = envelope.requestID {
            ProtocolV2Emitter(requestID: requestID).emit(type: "error", message: "scan 옵션 JSON 파싱 실패")
        } else {
            FileHandle.standardError.write(Data("[negaflow-scanner-sane] scan 옵션 JSON 파싱 실패\n".utf8))
        }
        exit(1)
    }
    let emitter = ProtocolV2Emitter(requestID: wire.requestID)
    let options: ScanOptions
    do {
        options = try wire.validatedOptions()
    } catch {
        emitter.emit(type: "error", message: error.localizedDescription)
        exit(1)
    }
    let onProgress: @Sendable (ScanProgress) -> Void = { p in
        emitter.emit(
            type: "progress",
            phase: p.phase.rawValue,
            fraction: p.fraction,
            message: p.message
        )
    }
    do {
        let result = wire.preview
            ? try await backend.startPreviewScan(options, progress: onProgress)
            : try await backend.startFullScan(options, progress: onProgress)
        guard result.rawFileURL.path == wire.outputPath,
              result.resolution.dpi == wire.resolutionDPI,
              result.bitDepth.rawValue == wire.bitDepth,
              result.hasInfraredChannel == wire.infrared else {
            throw ScannerError(.ioFailure, "scan 결과가 protocol v2 요청/적용 계약과 일치하지 않습니다.")
        }
        emitter.emit(
            type: "result",
            width: result.width,
            height: result.height,
            path: result.rawFileURL.path,
            resolutionDPI: result.resolution.dpi,
            bitDepth: result.bitDepth.rawValue,
            irPath: result.infraredFileURL?.path,
            hasInfrared: result.hasInfraredChannel,
            warnings: result.warnings.isEmpty ? nil : result.warnings,
            appliedOptions: PluginAppliedScanOptionsV2(
                request: wire,
                appliedScanArea: result.appliedScanArea
            )
        )
    } catch {
        emitter.emit(type: "error", message: error.localizedDescription)
        exit(1)
    }

case "repair-sane-config", "tune-sane":
    // tune-sane은 기존 자동화 호환 별칭이다. 두 명령 모두 과거 negaflow 주석만 복구한다.
    let result = SaneConfigTuner.recoverLegacyFiltering()
    print("repair: \(result)")
    print("active backends: \(SaneConfigTuner.activeBackends.joined(separator: ", "))")

case "restore-sane":
    let ok = SaneConfigTuner.restore()
    print(ok ? "restored from \(SaneConfigTuner.backupPath)" : "no backup to restore (\(SaneConfigTuner.backupPath))")

default:
    let help = """
    negaflow-scanner-sane — negaflow SANE scanner plugin
    usage:
      negaflow-scanner-sane detect
      negaflow-scanner-sane capabilities <deviceId>
      negaflow-scanner-sane scan   (scan options JSON on stdin)
      negaflow-scanner-sane repair-sane-config (과거 negaflow가 비활성화한 백엔드 복구)
      negaflow-scanner-sane tune-sane          (repair-sane-config 호환 별칭)
      negaflow-scanner-sane restore-sane       (최초 백업으로 전체 복구)
    """
    FileHandle.standardError.write(Data((help + "\n").utf8))
}
