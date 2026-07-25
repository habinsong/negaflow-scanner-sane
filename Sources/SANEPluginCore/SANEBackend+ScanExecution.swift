import Foundation
import CoreGraphics
import ImageIO

extension SANEBackend {
    /// 한 번의 scanimage 실행이 담당하는 패스 종류.
    enum AcquisitionPass: Sendable, Equatable {
        case main       // RGB(또는 요청 모드) 본 스캔
        case infrared   // 별도 IR 패스(genesys 소스 교체 / epson2 커스텀 모드 교체)
    }

    public func startPreviewScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        guard options.resolution == .preview,
              !options.infraredEnabled,
              !options.multiExposureEnabled else {
            throw ScannerError(.unsupportedOption, "preview 옵션을 플러그인 내부에서 변환할 수 없습니다.")
        }
        return try await startFullScan(options, progress: progress)
    }

    public func startFullScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        let scanSessionID = try beginScanSession()
        defer { endScanSession(scanSessionID) }

        let outURL = options.temporaryOutputURL
            ?? Self.makeTempURL(prefix: "negaflow_scan", suffix: ".tiff")

        if options.multiExposureEnabled, options.resolution != .preview {
            return try await startSoftwareMultiPassScan(options, outputURL: outURL, progress: progress)
        }

        // 중요: USB 장치 주소(libusb:bus:dev)는 스캐너 리셋/재열거로 매번 바뀐다.
        // scannerID에 박힌 과거 주소로 open하면 "Invalid argument"로 실패한다.
        // 따라서 스캔 직전에 반드시 scanimage -L 로 현재 주소를 다시 얻는다.
        // 소스/모드/깊이/해상도/IR을 장치 옵션에서 한 번 해석(주소가 바뀌어도 media는 불변).
        let media = try await resolveValidatedMedia(options: options)
        progress(ScanProgress(phase: .warmingLamp, fraction: 0.02, message: "Warming lamp"))
        progress(ScanProgress(phase: .scanningRGB, fraction: 0.1, message: "Scanning RGB"))

        let t0 = Date()
        var warnings: [String] = []
        var infraredURL: URL? = nil

        try await runSingleAcquisition(
            options: options,
            media: media,
            pass: .main,
            outputURL: outURL,
            brightness: nil,
            staleRetryProgress: 0.05,
            scanProgressRange: 0.08...(media.usesInfrared && media.irStrategy.needsSeparatePass ? 0.78 : 0.92),
            progress: progress
        )
        if media.usesInfrared, media.irStrategy.needsSeparatePass {
            let (irURL, irWarnings) = await acquireInfraredPass(
                options: options, media: media, mainOutputURL: outURL, progress: progress
            )
            infraredURL = irURL
            warnings += irWarnings
        }
        if case .cleanImage = media.irStrategy {
            warnings.append("IR dust removal applied inside the SANE backend (--clean-image); no separate IR channel file.")
        }

        let duration = Date().timeIntervalSince(t0)
        let result = try validatedScanResult(
            options: options,
            outputURL: outURL,
            infraredURL: infraredURL,
            duration: duration,
            warnings: warnings
        )
        progress(ScanProgress(phase: .complete, fraction: 1.0, message: "Scan complete"))
        return result
    }

    private func startSoftwareMultiPassScan(
        _ options: ScanOptions,
        outputURL: URL,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        let t0 = Date()
        let exposurePlan = Self.hardwareExposurePlan()
        let passCount = exposurePlan.count
        let labels = (0..<passCount).map { "sample\($0 + 1)" }
        let urls = labels.map { Self.makeTempURL(prefix: "negaflow_multipass_\($0)", suffix: ".tiff") }
        defer {
            if !Self.shouldKeepMultiPassArtifacts {
                for url in urls {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }

        let media = try await resolveValidatedMedia(options: options)
        progress(ScanProgress(phase: .warmingLamp, fraction: 0.02, message: "Warming lamp"))
        for index in 0..<passCount {
            let base = 0.08 + Double(index) * (0.70 / Double(passCount))
            var passOptions = options
            passOptions.hardwareExposureTime = exposurePlan[index]
            progress(ScanProgress(
                phase: .scanningRGB,
                fraction: base,
                message: "Exposure bracket \(index + 1)/\(passCount) @ \(exposurePlan[index])"
            ))
            try await runSingleAcquisition(
                options: passOptions,
                media: media,
                pass: .main,
                outputURL: urls[index],
                brightness: nil,
                staleRetryProgress: base,
                scanProgressRange: base...(base + 0.70 / Double(passCount)),
                progress: progress
            )
        }

        progress(ScanProgress(phase: .processingNegative, fraction: 0.82, message: "Merging exposure brackets"))
        do {
            try Self.mergeHardwareExposureScans(
                sampleURLs: urls,
                exposureTimes: exposurePlan,
                outputURL: outputURL
            )
        } catch {
            self.lastError = ScannerError(.ioFailure, "multi-sample merge failed: \(error.localizedDescription)")
            throw lastError!
        }

        var warnings = [
            "Hardware scan-exposure-time bracket \(Self.hardwareExposureTimes) used with \(Self.hardwareExposureSamplesPerStop) sample(s) per exposure; same-exposure samples reduce random/color noise before clipped/low-signal regions are filled from alternate exposures."
        ]
        if Self.shouldKeepMultiPassArtifacts {
            warnings.append("Multi-pass intermediate TIFFs kept: \(urls.map(\.path).joined(separator: ", "))")
        }

        // IR: 별도 패스 전략(genesys 소스/epson2 모드)만 다중노출과 조합 가능.
        var infraredURL: URL? = nil
        if media.usesInfrared {
            if media.irStrategy.needsSeparatePass {
                let (irURL, irWarnings) = await acquireInfraredPass(
                    options: options, media: media, mainOutputURL: outputURL, progress: progress
                )
                infraredURL = irURL
                warnings += irWarnings
            } else {
                warnings.append("Infrared skipped: this device's IR method cannot be combined with multi-exposure passes.")
            }
        }

        let duration = Date().timeIntervalSince(t0)
        let result = try validatedScanResult(
            options: options,
            outputURL: outputURL,
            infraredURL: infraredURL,
            duration: duration,
            warnings: warnings
        )
        progress(ScanProgress(phase: .complete, fraction: 1.0, message: "Multi-Exposure scan complete"))
        return result
    }

    // MARK: protocol v2 exact-option / artifact contract

    struct ScannedTIFFMetadata: Sendable, Equatable {
        var width: Int
        var height: Int
        var bitDepth: BitDepth
        var colorMode: ColorMode
    }

    private func resolveValidatedMedia(options: ScanOptions) async throws -> MediaSelection {
        do {
            let media = try await resolveMedia(options: options)
            try Self.validateExactOptions(options, media: media)
            return media
        } catch let error as ScannerError {
            lastError = error
            throw error
        } catch {
            let scannerError = ScannerError(.ioFailure, error.localizedDescription)
            lastError = scannerError
            throw scannerError
        }
    }

    static func validateExactOptions(_ options: ScanOptions, media: MediaSelection) throws {
        if options.resolution == .preview {
            guard media.hasPreviewOption else {
                throw ScannerError(.unsupportedOption, "scanimage -A에 --preview가 없습니다.")
            }
        } else {
            guard media.resolvedDPI == options.resolution.dpi else {
                throw ScannerError(
                    .unsupportedOption,
                    "요청 resolution \(options.resolution.dpi)dpi를 정확히 적용할 수 없습니다."
                )
            }
        }

        guard media.hasDepthOption, let depth = media.depthArgument else {
            throw ScannerError(.unsupportedOption, "요청 bitDepth를 정확히 적용할 --depth가 없습니다.")
        }
        switch options.bitDepth {
        case .eight where depth != 8:
            throw ScannerError(.unsupportedOption, "8-bit 요청을 정확히 적용할 수 없습니다.")
        case .sixteen where depth <= 8:
            throw ScannerError(.unsupportedOption, "16-bit 요청을 정확히 적용할 수 없습니다.")
        default:
            break
        }

        if media.hasModeOption, let mode = media.mode {
            let normalizedMode = mode.lowercased()
            switch options.colorMode {
            case .color where !normalizedMode.contains("color"):
                throw ScannerError(.unsupportedOption, "color 요청을 정확히 적용할 수 없습니다.")
            case .gray where !(normalizedMode.contains("gray") || normalizedMode.contains("grey")):
                throw ScannerError(.unsupportedOption, "gray 요청을 정확히 적용할 수 없습니다.")
            case .lineart, .infrared:
                throw ScannerError(.unsupportedOption, "lineart/infrared primary mode는 protocol v2에서 지원하지 않습니다.")
            default:
                break
            }
        } else {
            guard media.dedicatedFilmDevice, options.colorMode == .color else {
                throw ScannerError(.unsupportedOption, "요청 colorMode를 정확히 적용할 --mode가 없습니다.")
            }
        }

        if let source = media.source, !isTransparencySource(source) {
            throw ScannerError(.unsupportedOption, "투과 필름 source를 정확히 선택할 수 없습니다.")
        }
        if media.hasFilmTypeOption, media.filmType == nil {
            throw ScannerError(.unsupportedOption, "요청 filmType polarity를 정확히 적용할 수 없습니다.")
        }

        if media.usesCornerPixelGeometry {
            guard media.originXPixels != nil,
                  media.originYPixels != nil,
                  media.rightPixels != nil,
                  media.bottomPixels != nil else {
                throw ScannerError(.unsupportedOption, "요청 scanArea를 pel 모서리 좌표로 적용할 수 없습니다.")
            }
        } else if media.widthPixels != nil, media.heightPixels != nil {
            if media.originXPixels == nil || media.originYPixels == nil {
                guard options.scanArea.originXMM == 0, options.scanArea.originYMM == 0 else {
                    throw ScannerError(.unsupportedOption, "요청 scanArea 원점을 pel 단위로 적용할 수 없습니다.")
                }
            }
        } else if options.resolution == .preview, media.dedicatedFilmDevice {
            guard options.scanArea.originXMM == 0, options.scanArea.originYMM == 0 else {
                throw ScannerError(.unsupportedOption, "preview scanArea 원점을 적용할 수 없습니다.")
            }
        } else {
            guard let widthRange = media.scanWidthRange,
                  let heightRange = media.scanHeightRange,
                  widthRange.containsExactly(options.scanArea.widthMM),
                  heightRange.containsExactly(options.scanArea.heightMM),
                  media.widthMM == options.scanArea.widthMM,
                  media.heightMM == options.scanArea.heightMM else {
                throw ScannerError(.unsupportedOption, "요청 scanArea를 mm 또는 pel 단위로 정확히 적용할 수 없습니다.")
            }
            if let leftRange = media.scanLeftRange, let topRange = media.scanTopRange {
                guard leftRange.containsExactly(options.scanArea.originXMM),
                      topRange.containsExactly(options.scanArea.originYMM),
                      media.originXMM == options.scanArea.originXMM,
                      media.originYMM == options.scanArea.originYMM else {
                    throw ScannerError(.unsupportedOption, "요청 scanArea 원점을 mm 단위로 정확히 적용할 수 없습니다.")
                }
            } else if options.scanArea.originXMM != 0 || options.scanArea.originYMM != 0 {
                throw ScannerError(.unsupportedOption, "요청 scanArea 원점을 적용할 -l/-t 옵션이 없습니다.")
            }
        }

        try validateAdjustment(
            options.brightnessAdjustment,
            range: media.brightnessRange,
            name: "brightness"
        )
        try validateAdjustment(
            options.contrastAdjustment,
            range: media.contrastRange,
            name: "contrast"
        )
        if let exposure = options.hardwareExposureTime {
            guard media.hasScanExposureOption,
                  media.hardwareExposureRange?.containsExactly(Double(exposure)) == true else {
                throw ScannerError(
                    .unsupportedOption,
                    "요청 hardwareExposureTime을 정확히 적용할 수 없습니다."
                )
            }
        }

        if options.multiExposureEnabled {
            guard options.colorMode == .color, options.bitDepth == .sixteen else {
                throw ScannerError(.unsupportedOption, "Multi-Exposure는 16-bit color 출력만 지원합니다.")
            }
            guard media.hasScanExposureOption,
                  let range = media.hardwareExposureRange,
                  hardwareExposureTimes.allSatisfy({ range.containsExactly(Double($0)) }) else {
                throw ScannerError(.unsupportedOption, "Multi-Exposure 노출 계획을 장치가 정확히 지원하지 않습니다.")
            }
            if options.infraredEnabled, !media.irStrategy.needsSeparatePass {
                throw ScannerError(
                    .unsupportedOption,
                    "이 장치의 IR 방식은 Multi-Exposure와 정확히 결합할 수 없습니다."
                )
            }
        }

        if options.infraredEnabled {
            switch media.irStrategy {
            case .separateSource, .separateMode:
                break
            case .none, .cleanImage:
                throw ScannerError(.unsupportedOption, "별도 IR 채널을 정확히 획득할 수 없습니다.")
            }
        }
    }

    private static func validateAdjustment(
        _ value: Double?,
        range: ScannerOptionRange?,
        name: String
    ) throws {
        guard let value else { return }
        guard range?.containsExactly(value) == true else {
            throw ScannerError(.unsupportedOption, "요청 \(name) 값을 정확히 적용할 수 없습니다.")
        }
    }

    static func validatedScannedTIFF(
        at url: URL,
        expectedBitDepth: BitDepth,
        expectedColorMode: ColorMode
    ) throws -> ScannedTIFFMetadata {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        } catch {
            throw ScannerError(.ioFailure, "scanimage 출력 파일을 읽을 수 없습니다.")
        }
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              (values.fileSize ?? 0) > 0 else {
            throw ScannerError(.ioFailure, "scanimage 출력이 비어 있거나 regular file이 아닙니다.")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetType(source) as String? == "public.tiff" else {
            throw ScannerError(.ioFailure, "scanimage 출력 형식이 단일 TIFF가 아닙니다.")
        }
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary),
              image.width > 0,
              image.height > 0,
              let actualBitDepth = BitDepth(rawValue: image.bitsPerComponent) else {
            throw ScannerError(.ioFailure, "scanimage TIFF를 실제 이미지로 decode할 수 없습니다.")
        }
        let actualColorMode: ColorMode
        switch image.colorSpace?.model {
        case .rgb:
            actualColorMode = .color
        case .monochrome:
            actualColorMode = .gray
        default:
            throw ScannerError(.ioFailure, "scanimage TIFF color model이 RGB/Gray가 아닙니다.")
        }
        guard actualBitDepth == expectedBitDepth else {
            throw ScannerError(
                .ioFailure,
                "scanimage TIFF bitDepth 불일치: requested \(expectedBitDepth.rawValue), actual \(actualBitDepth.rawValue)"
            )
        }
        guard actualColorMode == expectedColorMode else {
            throw ScannerError(
                .ioFailure,
                "scanimage TIFF colorMode 불일치: requested \(expectedColorMode.rawValue), actual \(actualColorMode.rawValue)"
            )
        }
        return ScannedTIFFMetadata(
            width: image.width,
            height: image.height,
            bitDepth: actualBitDepth,
            colorMode: actualColorMode
        )
    }

    private func validatedScanResult(
        options: ScanOptions,
        outputURL: URL,
        infraredURL: URL?,
        duration: TimeInterval,
        warnings: [String]
    ) throws -> ScanResult {
        do {
            let metadata = try Self.validatedScannedTIFF(
                at: outputURL,
                expectedBitDepth: options.bitDepth,
                expectedColorMode: options.colorMode
            )
            if options.infraredEnabled {
                guard let infraredURL else {
                    throw ScannerError(.ioFailure, "요청한 별도 IR 채널 결과가 없습니다.")
                }
                let infrared = try Self.validatedScannedTIFF(
                    at: infraredURL,
                    expectedBitDepth: options.bitDepth,
                    expectedColorMode: .gray
                )
                guard infrared.width == metadata.width,
                      infrared.height == metadata.height else {
                    throw ScannerError(.ioFailure, "RGB/IR TIFF 픽셀 크기가 일치하지 않습니다.")
                }
            } else if infraredURL != nil {
                throw ScannerError(.ioFailure, "요청하지 않은 IR 채널 결과가 생성됐습니다.")
            }
            return ScanResult(
                rawFileURL: outputURL,
                width: metadata.width,
                height: metadata.height,
                resolution: options.resolution,
                bitDepth: metadata.bitDepth,
                colorSpace: metadata.colorMode == .color ? "RGB" : "Gray",
                hasInfraredChannel: infraredURL != nil,
                infraredFileURL: infraredURL,
                scanDuration: duration,
                backendUsed: .sane,
                warnings: warnings
            )
        } catch let error as ScannerError {
            try? FileManager.default.removeItem(at: outputURL)
            if let infraredURL { try? FileManager.default.removeItem(at: infraredURL) }
            lastError = error
            throw error
        }
    }

    private static var shouldKeepMultiPassArtifacts: Bool {
        let value = ProcessInfo.processInfo.environment["NEGAFLOW_KEEP_MULTIPASS"] ?? ""
        return value == "1" || value.lowercased() == "true"
    }

    // MARK: 단일 획득 (재시도 포함)

    func runSingleAcquisition(
        options: ScanOptions,
        media: MediaSelection,
        pass: AcquisitionPass,
        outputURL: URL,
        brightness: Int?,
        staleRetryProgress: Double,
        scanProgressRange: ClosedRange<Double>,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws {
        var lastStderr = ""
        for attempt in 0..<2 {
            if attempt > 0 {
                invalidateAddressCache()
            }
            do {
                let devname = try await resolveDeviceAddress(
                    for: options,
                    media: media,
                    forceRefresh: attempt > 0
                )
                let args = makeScanimageArgs(
                    devname: devname,
                    options: options,
                    media: media,
                    pass: pass,
                    brightness: brightness
                )
                let ec = try await runScanimageTo(
                    args: args,
                    outputURL: outputURL,
                    phase: pass == .infrared ? .scanningIR : .scanningRGB,
                    progressRange: scanProgressRange,
                    progress: progress
                )
                let stderr = takeStderr()
                if isScanCancellationRequested() {
                    throw ScannerError(.cancelled, "스캔이 취소되었습니다.")
                }
                if ec == 0 {
                    if Self.containsInexactOptionWarning(stderr) {
                        throw ScannerError(
                            .unsupportedOption,
                            "SANE가 요청 옵션을 다른 값으로 반올림했습니다: \(stderr)"
                        )
                    }
                    return
                }
                lastStderr = stderr
                if attempt == 0, Self.isStaleDeviceError(lastStderr) {
                    progress(ScanProgress(
                        phase: .warmingLamp,
                        fraction: staleRetryProgress,
                        message: "Re-detecting scanner"
                    ))
                    continue
                }
                let detail = lastStderr.isEmpty ? "scanimage exit \(ec)" : "scanimage exit \(ec): \(lastStderr)"
                self.lastError = ScannerError(.ioFailure, detail)
                throw lastError!
            } catch let err as ScannerError {
                throw err
            } catch {
                self.lastError = ScannerError(.ioFailure, error.localizedDescription)
                throw error
            }
        }
        let detail = lastStderr.isEmpty ? "scanimage 재시도 실패" : "scanimage 재시도 실패: \(lastStderr)"
        self.lastError = ScannerError(.ioFailure, detail)
        throw lastError!
    }

    // MARK: 별도 IR 패스 (genesys IR 소스 / epson2 커스텀 Infrared 모드)

    /// RGB 본 스캔 후 같은 지오메트리/해상도로 IR 채널을 한 번 더 읽는다.
    /// IR 실패는 본 스캔을 무효화하지 않는다(경고로 보고).
    private func acquireInfraredPass(
        options: ScanOptions,
        media: MediaSelection,
        mainOutputURL: URL,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async -> (URL?, [String]) {
        let irURL = Self.infraredURL(for: mainOutputURL)
        progress(ScanProgress(phase: .scanningIR, fraction: 0.86, message: "Scanning infrared"))
        do {
            try await runSingleAcquisition(
                options: options,
                media: media,
                pass: .infrared,
                outputURL: irURL,
                brightness: nil,
                staleRetryProgress: 0.86,
                scanProgressRange: 0.80...0.96,
                progress: progress
            )
        } catch {
            try? FileManager.default.removeItem(at: irURL)
            return (nil, ["Infrared pass failed: \(error.localizedDescription)"])
        }
        let (w, h) = Self.imageSize(at: irURL)
        guard w > 0, h > 0 else {
            try? FileManager.default.removeItem(at: irURL)
            return (nil, ["Infrared pass produced an unreadable image; IR channel dropped."])
        }
        return (irURL, [])
    }

    static func infraredURL(for outputURL: URL) -> URL {
        let base = outputURL.deletingPathExtension()
        let ext = outputURL.pathExtension.isEmpty ? "tiff" : outputURL.pathExtension
        return base.appendingPathExtension("ir").appendingPathExtension(ext)
    }

    /// "open of device ... failed: Invalid argument" 등 USB 주소가 만료됐을 때
    /// 나타나는 전형적 오류인지 판별. 이 경우 주소를 다시 얻어 재시도하면 보통 성공한다.
    static func isStaleDeviceError(_ stderr: String) -> Bool {
        let s = stderr.lowercased()
        return s.contains("invalid argument")
            || s.contains("open of device")
            || s.contains("failed to open")
            || s.contains("device busy")
            || s.contains("no such device")
            || s.contains("i/o error")
            || s.contains("device i/o")
    }

    static func containsInexactOptionWarning(_ stderr: String) -> Bool {
        stderr.lowercased().contains("rounded value of")
    }

    private func resolveDeviceAddress(
        for options: ScanOptions,
        media: MediaSelection,
        forceRefresh: Bool
    ) async throws -> String {
        if !forceRefresh, let acquisitionDevice = media.acquisitionDevice {
            return acquisitionDevice
        }
        let raw = options.scannerID.replacingOccurrences(of: "sane-", with: "")
        return try await currentDeviceAddressWithRetry(
            targetDevice: raw,
            targetBackend: Self.backendName(of: raw),
            expectedIdentity: media.expectedDeviceIdentity
        )
    }

    private func currentDeviceAddressWithRetry(
        targetDevice: String?,
        targetBackend: String?,
        expectedIdentity: DeviceIdentity?
    ) async throws -> String {
        var lastError: Error?
        for attempt in 0..<5 {
            do {
                return try await currentDeviceAddress(
                    targetDevice: targetDevice,
                    targetBackend: targetBackend,
                    expectedIdentity: expectedIdentity,
                    allowSingleGenesysSelector: true,
                    ownedByScanSession: true
                )
            } catch {
                lastError = error
                if attempt < 4 {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
            }
        }
        throw lastError ?? ScannerError(.notConnected, "scanimage -L 이 장치를 찾지 못함")
    }

    // MARK: scanimage 인자 생성

    /// 장치가 실제 노출하는 옵션(MediaSelection)만으로 인자를 만든다.
    /// 없는 옵션에 플래그를 넘기면 scanimage 가 즉시 실패하므로(coolscan3 의 --mode 등),
    /// nil 필드는 전부 생략한다. IR 패스는 소스/모드만 교체하고 지오메트리/해상도/깊이를
    /// 본 스캔과 동일하게 유지한다(먼지 맵 정렬을 위해 픽셀 격자가 같아야 함).
    func makeScanimageArgs(
        devname: String,
        options: ScanOptions,
        media: MediaSelection,
        pass: AcquisitionPass = .main,
        brightness: Int? = nil
    ) -> [String] {
        var args: [String] = ["-d", devname, "-p"]

        var mode = media.mode
        var source = media.source
        if pass == .infrared {
            switch media.irStrategy {
            case .separateSource(let irSource):
                source = irSource
                mode = media.irPassMode ?? media.mode
            case .separateMode(let irMode):
                mode = irMode
            case .none, .cleanImage:
                break
            }
        }
        if let source { args += ["--source", source] }
        if let mode { args += ["--mode", mode] }

        if pass == .main {
            if let filmType = media.filmType { args += ["--film-type", filmType] }
            if media.hasBrightnessOption {
                if let brightness {
                    args += ["--brightness=\(brightness)"]
                } else if let brightness = options.brightnessAdjustment {
                    args += ["--brightness=\(Self.saneNumber(brightness))"]
                }
            }
            if media.hasContrastOption, let contrast = options.contrastAdjustment {
                args += ["--contrast=\(Self.saneNumber(contrast))"]
            }
            if media.hasScanExposureOption, let exposureTime = options.hardwareExposureTime {
                args += ["--scan-exposure-time=\(exposureTime)"]
            }
            if case .cleanImage(let optionName) = media.irStrategy {
                args += ["--\(optionName)=yes"]
            }
            if options.resolution == .preview, media.hasPreviewOption {
                args += ["--preview=yes"]
            }
        }

        if let dpi = media.resolvedDPI { args += ["--resolution", "\(dpi)"] }
        if let depth = media.depthArgument { args += ["--depth", "\(depth)"] }
        if media.usesCornerPixelGeometry,
           let left = media.originXPixels,
           let top = media.originYPixels,
           let right = media.rightPixels,
           let bottom = media.bottomPixels {
            args += [
                "--tl-x", "\(left)",
                "--tl-y", "\(top)",
                "--br-x", "\(right)",
                "--br-y", "\(bottom)",
            ]
        } else if let x = media.originXMM, let y = media.originYMM {
            args += ["-l", Self.saneNumber(x), "-t", Self.saneNumber(y)]
        } else if let x = media.originXPixels, let y = media.originYPixels {
            args += ["-l", "\(x)", "-t", "\(y)"]
        }
        if let w = media.widthMM, let h = media.heightMM {
            args += ["-x", Self.saneNumber(w), "-y", Self.saneNumber(h)]
        } else if let w = media.widthPixels, let h = media.heightPixels {
            args += ["-x", "\(w)", "-y", "\(h)"]
        }
        args += ["--format=tiff"]
        return args
    }

    private static func saneNumber(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(value)
    }
}

extension SANEBackend.IRStrategy {
    /// 별도 스캔 패스가 필요한 전략인지(소스 교체/모드 교체).
    var needsSeparatePass: Bool {
        switch self {
        case .separateSource, .separateMode: return true
        case .none, .cleanImage: return false
        }
    }
}
