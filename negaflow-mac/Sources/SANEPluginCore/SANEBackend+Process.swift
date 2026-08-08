import Foundation

extension SANEBackend {
    public func cancelScan() async {
        // 진행 중인 scanimage 프로세스를 즉시 종료한다.
        // 단순 Task.cancel() 로는 잡히지 않는다 — 실제 Process 를 죽여야 USB 가 풀린다.
        guard let process = requestOwnedScanCancellation(), process.isRunning else { return }
        process.terminate()
        // 같은 Process 인스턴스가 0.5초 후에도 살아 있을 때만 해당 PID를 강제 종료한다.
        try? await Task.sleep(nanoseconds: 500_000_000)
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    /// 한 backend 인스턴스에서 scan session은 하나만 허용한다. 이름/경로 기반 전역 process
    /// 검색은 하지 않으며, 이 인스턴스가 직접 생성해 보관한 Process만 취소 대상으로 삼는다.
    func beginScanSession() throws -> UUID {
        processLock.lock()
        defer { processLock.unlock() }
        if let process = currentProcess, !process.isRunning {
            currentProcess = nil
        }
        guard !scanCancellationRequested else {
            throw ScannerError(.cancelled, "스캔이 취소되었습니다.")
        }
        guard activeScanSessionID == nil, currentProcess == nil else {
            throw ScannerError(.busy, "이 plugin instance에서 scanimage가 이미 실행 중입니다.")
        }
        let sessionID = UUID()
        activeScanSessionID = sessionID
        return sessionID
    }

    func endScanSession(_ sessionID: UUID) {
        processLock.lock()
        defer { processLock.unlock() }
        guard activeScanSessionID == sessionID else { return }
        if let process = currentProcess, !process.isRunning {
            currentProcess = nil
        }
        activeScanSessionID = nil
        scanCancellationRequested = false
    }

    func snapshotOwnedScanProcess() -> Process? {
        processLock.lock()
        defer { processLock.unlock() }
        return currentProcess
    }

    private func requestOwnedScanCancellation() -> Process? {
        processLock.lock()
        defer { processLock.unlock() }
        guard activeScanSessionID != nil || currentProcess != nil else {
            return nil
        }
        scanCancellationRequested = true
        return currentProcess
    }

    func isScanCancellationRequested() -> Bool {
        processLock.lock()
        defer { processLock.unlock() }
        return scanCancellationRequested
    }

    private func launchOwnedScanProcess(
        _ process: Process,
        requiresScanSession: Bool
    ) throws {
        processLock.lock()
        defer { processLock.unlock() }
        guard currentProcess == nil,
              requiresScanSession ? activeScanSessionID != nil : activeScanSessionID == nil else {
            throw ScannerError(.busy, "소유한 scanimage process slot을 사용할 수 없습니다.")
        }
        guard !scanCancellationRequested else {
            throw ScannerError(.cancelled, "스캔이 취소되었습니다.")
        }
        try process.run()
        currentProcess = process
    }

    func runScanimage(args: [String], ownedByScanSession: Bool = false) async throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: scanimage)
        proc.arguments = args
        proc.environment = makeSaneEnvironmentWithDefaultDevice()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        // 파이프 버퍼(64KB)가 가득 차면 scanimage 가 블록한다(실제 교착 사례).
        // 반드시 proc.run() "이후에" 백그라운드에서 readDataToEndOfFile() 로 drain.
        let outBox = BufferBox()
        let errBox = BufferBox()
        let timeoutState = UtilityProcessTimeoutState()
        let outQ = DispatchQueue(label: "negaflow.sane.stdout")
        let errQ = DispatchQueue(label: "negaflow.sane.stderr")
        try launchOwnedScanProcess(
            proc,
            requiresScanSession: ownedByScanSession
        )
        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "negaflow.sane.utility-process-timeout")
        )
        timer.schedule(deadline: .now() + utilityProcessTimeout)
        timer.setEventHandler { [weak proc] in
            guard let proc, timeoutState.claimTimeout(for: proc) else { return }
            proc.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                if proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                }
            }
        }
        timer.resume()
        // `-d`가 붙은 실행만 장치를 실제로 연다. 목록 조회(-L/-f)는 주소를 바꾸지 않는다.
        let opensDevice = args.contains("-d")
        defer {
            timer.cancel()
            clearCurrentProcess(proc)
            if opensDevice { noteDeviceOpened() }
            if !ownedByScanSession {
                clearUtilityProcessCancellation()
            }
        }
        let outWork = DispatchWorkItem { outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile() }
        let errWork = DispatchWorkItem { errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile() }
        outQ.async(execute: outWork)
        errQ.async(execute: errWork)
        proc.waitUntilExit()
        // 두 drain 작업이 끝날 때까지 대기.
        outWork.wait()
        errWork.wait()
        let stderr = String(data: errBox.data, encoding: .utf8) ?? ""
        let stdout = String(data: outBox.data, encoding: .utf8) ?? ""
        lastStderr = stderr
        if isScanCancellationRequested() {
            throw ScannerError(.cancelled, "스캔이 취소되었습니다.")
        }
        if timeoutState.didTimeOut {
            throw ScannerError(
                .timeout,
                "scanimage 조회가 \(Int(utilityProcessTimeout))초 안에 끝나지 않았습니다."
            )
        }
        guard proc.terminationReason == .exit, proc.terminationStatus == 0 else {
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = detail.isEmpty
                ? "scanimage가 종료 코드 \(proc.terminationStatus)로 실패했습니다."
                : detail
            let normalized = message.lowercased()
            let code: ScannerError.Code
            if normalized.contains("access to resource has been denied")
                || normalized.contains("device busy")
                || normalized.contains("resource busy") {
                code = .busy
            } else if normalized.contains("no such device")
                || normalized.contains("invalid argument")
                || normalized.contains("not connected") {
                code = .notConnected
            } else {
                code = .ioFailure
            }
            let error = ScannerError(code, message)
            lastError = error
            throw error
        }
        return stdout
    }

    /// 백그라운드 drain 스레드가 안전하게 쓸 수 있는 버퍼 홀더.
    private final class BufferBox: @unchecked Sendable {
        var data = Data()
    }

    private final class UtilityProcessTimeoutState: @unchecked Sendable {
        private let lock = NSLock()
        private var timedOut = false

        var didTimeOut: Bool {
            lock.lock()
            defer { lock.unlock() }
            return timedOut
        }

        func claimTimeout(for process: Process) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !timedOut, process.isRunning else { return false }
            timedOut = true
            return true
        }
    }

    private enum AcquisitionTimeoutKind: Sendable {
        case firstProgress
        case stalled
    }

    /// 첫 진행률뿐 아니라 마지막 진행률 이후의 유휴 시간도 감시한다. 총 스캔 시간은
    /// 제한하지 않으며, scanimage가 progress를 계속 내는 한 고해상도 장기 스캔도 허용한다.
    private final class AcquisitionProgressWatchdog: @unchecked Sendable {
        private let lock = NSLock()
        private var timer: DispatchSourceTimer?
        private var observedProgress = false
        private var timedOut: AcquisitionTimeoutKind?
        private var finished = false
        private var stallTimeout: TimeInterval = 0
        private var deadline = DispatchTime.now()

        func start(
            firstTimeout: TimeInterval,
            stallTimeout: TimeInterval,
            process: Process
        ) {
            self.stallTimeout = stallTimeout
            let firstDeadline = DispatchTime.now() + firstTimeout
            self.deadline = firstDeadline
            let timer = DispatchSource.makeTimerSource(
                queue: DispatchQueue(label: "negaflow.sane.acquisition-progress-timeout")
            )
            timer.schedule(deadline: firstDeadline)
            timer.setEventHandler { [weak self, weak process] in
                guard let self, let process, process.isRunning,
                      self.claimTimeout() != nil else {
                    return
                }
                process.terminate()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
            }
            timer.resume()

            lock.lock()
            if finished {
                lock.unlock()
                timer.cancel()
                return
            }
            self.timer = timer
            lock.unlock()
        }

        func markProgress() {
            lock.lock()
            guard !finished, timedOut == nil else {
                lock.unlock()
                return
            }
            observedProgress = true
            let timer = self.timer
            let stallTimeout = self.stallTimeout
            let deadline = DispatchTime.now() + stallTimeout
            self.deadline = deadline
            lock.unlock()
            timer?.schedule(deadline: deadline)
        }

        func finish() -> (timeout: AcquisitionTimeoutKind?, observedProgress: Bool) {
            lock.lock()
            finished = true
            let didTimeOut = timedOut
            let didObserveProgress = observedProgress
            let timer = self.timer
            self.timer = nil
            lock.unlock()
            timer?.cancel()
            return (didTimeOut, didObserveProgress)
        }

        private func claimTimeout() -> AcquisitionTimeoutKind? {
            lock.lock()
            guard !finished, timedOut == nil else {
                lock.unlock()
                return nil
            }
            let now = DispatchTime.now()
            if now.uptimeNanoseconds < deadline.uptimeNanoseconds {
                let timer = self.timer
                let deadline = self.deadline
                lock.unlock()
                timer?.schedule(deadline: deadline)
                return nil
            }
            let kind: AcquisitionTimeoutKind = observedProgress ? .stalled : .firstProgress
            timedOut = kind
            lock.unlock()
            return kind
        }
    }

    static func usesAutomaticAcquisitionWatchdog(backend: String?) -> Bool {
        backend != "pieusb"
    }

    func runScanimageTo(
        args: [String],
        outputURL: URL,
        phase: ScanPhase,
        progressRange: ClosedRange<Double>,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> (exitCode: Int32, madeProgress: Bool) {
        return try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<(exitCode: Int32, madeProgress: Bool), Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: scanimage)
            proc.arguments = args
            proc.environment = makeSaneEnvironmentWithDefaultDevice()
            self.stderrBuffer = ""
            try? FileManager.default.removeItem(at: outputURL)
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            let handle = try? FileHandle(forWritingTo: outputURL)
            proc.standardOutput = handle
            let errPipe = Pipe()
            proc.standardError = errPipe
            self.scanProgressBuffer = ""
            let watchdog = AcquisitionProgressWatchdog()
            let stderrReadLock = NSLock()
            errPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
                stderrReadLock.lock()
                defer { stderrReadLock.unlock() }
                let chunk = fh.availableData
                guard !chunk.isEmpty else {
                    fh.readabilityHandler = nil
                    return
                }
                guard let s = String(data: chunk, encoding: .utf8) else { return }
                if self?.appendScanimageStderr(
                    s,
                    phase: phase,
                    progressRange: progressRange,
                    progress: progress
                ) == true {
                    watchdog.markProgress()
                }
            }
            proc.terminationHandler = { [weak self] p in
                errPipe.fileHandleForReading.readabilityHandler = nil
                // readabilityHandler가 이미 가져간 progress chunk까지 처리된 뒤 최종
                // stderr를 drain해야, 빠른 I/O 실패를 "진행 전"으로 오판하지 않는다.
                stderrReadLock.lock()
                if let rest = try? errPipe.fileHandleForReading.readToEnd(),
                   let s = String(data: rest, encoding: .utf8) {
                    if self?.appendScanimageStderr(
                        s,
                        phase: phase,
                        progressRange: progressRange,
                        progress: progress
                    ) == true {
                        watchdog.markProgress()
                    }
                }
                let watchdogResult = watchdog.finish()
                stderrReadLock.unlock()
                try? handle?.close()
                // 프로세스 추적 해제 — 좀비 방지.
                self?.clearCurrentProcess(p)
                // 스캔은 언제나 장치를 연다 → 종료 시 libusb 주소가 바뀐 것으로 본다.
                self?.noteDeviceOpened()
                if self?.isScanCancellationRequested() == true {
                    cont.resume(throwing: ScannerError(.cancelled, "스캔이 취소되었습니다."))
                } else if let timedOut = watchdogResult.timeout {
                    switch timedOut {
                    case .firstProgress:
                        cont.resume(throwing: ScannerError(
                            .timeout,
                            "scanimage가 \(Int(self?.acquisitionFirstProgressTimeout ?? 0))초 안에 첫 이미지 데이터를 반환하지 않았습니다."
                        ))
                    case .stalled:
                        cont.resume(throwing: ScannerError(
                            .timeout,
                            "scanimage 진행률이 \(Int(self?.acquisitionProgressStallTimeout ?? 0))초 동안 갱신되지 않았습니다."
                        ))
                    }
                } else {
                    cont.resume(returning: (
                        exitCode: p.terminationStatus,
                        madeProgress: watchdogResult.observedProgress
                    ))
                }
            }
            do {
                try self.launchOwnedScanProcess(
                    proc,
                    requiresScanSession: true
                )
                let device = args.indices
                    .first(where: { args[$0] == "-d" && args.indices.contains($0 + 1) })
                    .map { args[$0 + 1] }
                let backend = device.map(Self.backendName)
                // pieusb는 shading/calibration과 실제 acquisition을 sane_start 안에서
                // 동기 실행해 첫 progress가 장시간 없을 수 있다. 중간 종료는 transport
                // 상태를 불명확하게 만들므로 사용자 취소만 허용한다.
                if Self.usesAutomaticAcquisitionWatchdog(backend: backend) {
                    watchdog.start(
                        firstTimeout: self.acquisitionFirstProgressTimeout,
                        stallTimeout: self.acquisitionProgressStallTimeout,
                        process: proc
                    )
                }
            } catch {
                _ = watchdog.finish()
                try? handle?.close()
                cont.resume(throwing: error)
            }
        }
    }

    func clearCurrentProcess(_ process: Process) {
        processLock.lock()
        defer { processLock.unlock() }
        if currentProcess === process {
            currentProcess = nil
        }
    }

    private func clearUtilityProcessCancellation() {
        processLock.lock()
        defer { processLock.unlock() }
        guard activeScanSessionID == nil, currentProcess == nil else { return }
        scanCancellationRequested = false
    }

    func appendStderr(_ s: String) { stderrBuffer += s }

    func appendScanimageStderr(
        _ chunk: String,
        phase: ScanPhase,
        progressRange: ClosedRange<Double>,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) -> Bool {
        appendStderr(chunk)
        let previousProgressCount = Self.scanimageProgressRecordCount(in: scanProgressBuffer)
        let combined = scanProgressBuffer + chunk
        let foundProgress = Self.scanimageProgressRecordCount(in: combined) > previousProgressCount
        if let fraction = Self.scanimageProgressFraction(in: combined) {
            let mapped = progressRange.lowerBound
                + (progressRange.upperBound - progressRange.lowerBound) * fraction
            progress(ScanProgress(phase: phase, fraction: mapped, message: "Scanning"))
        }
        scanProgressBuffer = String(combined.suffix(160))
        return foundProgress
    }

    static func scanimageProgressRecordCount(in text: String) -> Int {
        let pattern = #"(?i)progress\s*:?\s*(?:\([^)]*\)|[0-9]{1,3}(?:[\.,][0-9]+)?\s*%)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func scanimageProgressFraction(in text: String) -> Double? {
        let pattern = #"(?i)progress\s*:?\s*([0-9]{1,3}(?:[\.,][0-9]+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        let number = text[range].replacingOccurrences(of: ",", with: ".")
        guard let percent = Double(number), percent.isFinite else { return nil }
        return min(max(percent / 100, 0), 1)
    }

    func takeStderr() -> String {
        let s = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        stderrBuffer = ""
        lastStderr = s
        return s
    }



    /// 인스턴스용 환경 — 정적 버전에 캐시된 기본 디바이스를 얹는다.
    /// SANE_DEFAULT_DEVICE 가 있으면 scanimage -L 가 probe 없이 그 장치를 바로 연다.
    func makeSaneEnvironmentWithDefaultDevice() -> [String: String] {
        var env = Self.makeSaneEnvironment(scanimagePath: scanimage)
        // 캐시된 주소가 유효하면 기본 디바이스로 주입. open으로 만료된 주소는 캐시에서
        // 이미 지워지므로(noteDeviceOpened) 죽은 주소가 주입되지 않는다.
        if let cached = cachedAddress,
           cachedAddressIsStableSelector || Date().timeIntervalSince(cachedAddressAt) < addressCacheTTL {
            env["SANE_DEFAULT_DEVICE"] = cached
        }
        return env
    }
}
