import Foundation

extension SANEBackend {
    public func startPreviewScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        // 프리뷰는 저해상도 + --preview 플래그로 빠르게.
        var opts = options
        opts.resolution = .preview
        opts.bitDepth = .eight
        return try await startFullScan(opts, progress: progress)
    }

    public func startFullScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        reapZombieScanimages()

        let outURL = options.temporaryOutputURL
            ?? Self.makeTempURL(prefix: "negaflow_scan", suffix: ".tiff")

        if options.multiExposureEnabled, options.resolution != .preview {
            return try await startSoftwareMultiPassScan(options, outputURL: outURL, progress: progress)
        }

        // 중요: USB 장치 주소(libusb:bus:dev)는 스캐너 리셋/재열거로 매번 바뀐다.
        // scannerID에 박힌 과거 주소로 open하면 "Invalid argument"로 실패한다.
        // 따라서 스캔 직전에 반드시 scanimage -L 로 현재 주소를 다시 얻는다.
        // 그래도 -L 시점과 open 시점 사이에 주소가 바뀔 수 있으므로, open 실패 시
        // 캐시를 무효화하고 새 주소로 1회 재시도한다.
        progress(ScanProgress(phase: .warmingLamp, fraction: 0.02, message: "Warming lamp"))
        // 소스/모드/IR을 장치 옵션에서 한 번 해석(주소가 바뀌어도 media는 불변).
        let media = await resolveMedia(options: options)
        progress(ScanProgress(phase: media.usesInfrared ? .scanningIR : .scanningRGB,
                              fraction: 0.1,
                              message: media.usesInfrared ? "Scanning infrared" : "Scanning RGB"))

        let t0 = Date()
        try await runSingleAcquisition(
            options: options,
            media: media,
            outputURL: outURL,
            brightness: nil,
            staleRetryProgress: 0.05,
            progress: progress
        )
        let duration = Date().timeIntervalSince(t0)
        progress(ScanProgress(phase: .complete, fraction: 1.0, message: "Scan complete"))
        let (w, h) = Self.imageSize(at: outURL)
        return ScanResult(
            rawFileURL: outURL,
            width: w, height: h,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            hasInfraredChannel: media.usesInfrared,
            scanDuration: duration,
            backendUsed: .sane
        )
    }

    private func startSoftwareMultiPassScan(
        _ options: ScanOptions,
        outputURL: URL,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        let t0 = Date()
        let usesHardwareExposure = await supportsHardwareExposure(for: options)
        let exposurePlan = usesHardwareExposure ? Self.hardwareExposurePlan() : []
        let passCount = usesHardwareExposure ? exposurePlan.count : Self.multiSamplePassCount
        let labels = (0..<passCount).map { "sample\($0 + 1)" }
        let urls = labels.map { Self.makeTempURL(prefix: "negaflow_multipass_\($0)", suffix: ".tiff") }
        defer {
            if !Self.shouldKeepMultiPassArtifacts {
                for url in urls {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }

        progress(ScanProgress(phase: .warmingLamp, fraction: 0.02, message: "Warming lamp"))
        let media = await resolveMedia(options: options)
        for index in 0..<passCount {
            let base = 0.08 + Double(index) * (0.75 / Double(passCount))
            var passOptions = options
            if usesHardwareExposure {
                passOptions.hardwareExposureTime = exposurePlan[index]
            }
            progress(ScanProgress(
                phase: media.usesInfrared ? .scanningIR : .scanningRGB,
                fraction: base,
                message: usesHardwareExposure
                    ? "Exposure bracket \(index + 1)/\(passCount) @ \(exposurePlan[index])"
                    : "Multi-sample \(index + 1)/\(passCount)"
            ))
            try await runSingleAcquisition(
                options: passOptions,
                media: media,
                outputURL: urls[index],
                brightness: nil,
                staleRetryProgress: base,
                progress: progress
            )
        }

        progress(ScanProgress(phase: .processingNegative, fraction: 0.86, message: "Averaging multi-sample scan"))
        do {
            if usesHardwareExposure {
                try Self.mergeHardwareExposureScans(
                    sampleURLs: urls,
                    exposureTimes: exposurePlan,
                    outputURL: outputURL
                )
            } else {
                try Self.averageMultiSampleScans(
                    sampleURLs: urls,
                    outputURL: outputURL
                )
            }
        } catch {
            self.lastError = ScannerError(.ioFailure, "multi-sample merge failed: \(error.localizedDescription)")
            throw lastError!
        }

        let duration = Date().timeIntervalSince(t0)
        progress(ScanProgress(phase: .complete, fraction: 1.0, message: "Multi-sample scan complete"))
        let (w, h) = Self.imageSize(at: outputURL)
        var warnings = usesHardwareExposure ? [
            "Hardware scan-exposure-time bracket \(Self.hardwareExposureTimes) used with \(Self.hardwareExposureSamplesPerStop) sample(s) per exposure; same-exposure samples reduce random/color noise before clipped/low-signal regions are filled from alternate exposures."
        ] : [
            "SANE genesys does not expose scan-exposure-time on this device; averaged \(Self.multiSamplePassCount) identical 16-bit passes for random-noise reduction, not hardware HDR."
        ]
        if Self.shouldKeepMultiPassArtifacts {
            warnings.append("Multi-pass intermediate TIFFs kept: \(urls.map(\.path).joined(separator: ", "))")
        }
        return ScanResult(
            rawFileURL: outputURL,
            width: w,
            height: h,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            hasInfraredChannel: media.usesInfrared,
            scanDuration: duration,
            backendUsed: .sane,
            warnings: warnings
        )
    }

    private func supportsHardwareExposure(for options: ScanOptions) async -> Bool {
        guard let capabilities = try? await getCapabilities(scannerID: options.scannerID) else {
            return false
        }
        return capabilities.supportsMultiExposure
    }

    private static var shouldKeepMultiPassArtifacts: Bool {
        let value = ProcessInfo.processInfo.environment["NEGAFLOW_KEEP_MULTIPASS"] ?? ""
        return value == "1" || value.lowercased() == "true"
    }

    private func runSingleAcquisition(
        options: ScanOptions,
        media: MediaSelection,
        outputURL: URL,
        brightness: Int?,
        staleRetryProgress: Double,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws {
        var lastStderr = ""
        for attempt in 0..<2 {
            if attempt > 0 {
                invalidateAddressCache()
            }
            let devname = await resolveDeviceAddress(for: options)
            let args = makeScanimageArgs(devname: devname, options: options, media: media, brightness: brightness)
            do {
                let ec = try await runScanimageTo(args: args, outputURL: outputURL, progress: progress)
                if ec == 0 {
                    return
                }
                lastStderr = takeStderr()
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

    private func resolveDeviceAddress(for options: ScanOptions) async -> String {
        let raw = options.scannerID.replacingOccurrences(of: "sane-", with: "")
        if let current = try? await currentDeviceAddressWithRetry(targetBackend: Self.backendName(of: raw)) {
            return current
        }
        return raw
    }

    private func currentDeviceAddressWithRetry(targetBackend: String?) async throws -> String {
        var lastError: Error?
        for attempt in 0..<5 {
            do {
                return try await currentDeviceAddress(targetBackend: targetBackend)
            } catch {
                lastError = error
                if attempt < 4 {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
            }
        }
        throw lastError ?? ScannerError(.notConnected, "scanimage -L 이 장치를 찾지 못함")
    }

    func makeScanimageArgs(devname: String, options: ScanOptions, media: MediaSelection, brightness: Int? = nil) -> [String] {
        var args: [String] = ["-d", devname]
        args += ["--mode", media.mode]
        // 소스/필름타입은 장치가 실제 노출하는 값으로 해석됨(하드코딩 금지). nil이면 생략.
        if let source = media.source { args += ["--source", source] }
        if let filmType = media.filmType { args += ["--film-type", filmType] }
        if let brightness {
            args += ["--brightness=\(brightness)"]
        }
        if let exposureTime = options.hardwareExposureTime {
            args += ["--scan-exposure-time=\(exposureTime)"]
        }
        if options.resolution == .preview { args += ["--preview=yes"] }
        if options.resolution.dpi > 0 { args += ["--resolution", "\(options.resolution.dpi)"] }
        args += ["--depth", "\(options.bitDepth.rawValue)"]
        args += ["-x", String(format: "%.2f", options.scanArea.widthMM),
                 "-y", String(format: "%.2f", options.scanArea.heightMM)]
        args += ["--format=tiff"]
        return args
    }
}
