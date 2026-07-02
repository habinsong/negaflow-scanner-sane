import Foundation

extension SANEBackend {
    public func cancelScan() async {
        // 진행 중인 scanimage 프로세스를 즉시 종료한다.
        // 단순 Task.cancel() 로는 잡히지 않는다 — 실제 Process 를 죽여야 USB 가 풀린다.
        if let proc = currentProcess, proc.isRunning {
            proc.terminate()
            // 0.5초 후에도 살아있으면 강제 kill.
            try? await Task.sleep(nanoseconds: 500_000_000)
            if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
        }
        currentProcess = nil
    }

    /// 시작 전에 이전 scanimage 좀비 프로세스를 정리한다.
    /// 좀비가 USB 장치를 붙잡고 있으면 새 스캔이 "Invalid argument" 로 실패한다
    /// (실제로 발생한 버그). scanimage 바이너리 경로로 ps 를 돌려 잔류분을 죽인다.
    ///
    /// 최적화: 잔류 프로세스가 실제로 존재할 때만 정리 + 대기. 이전에는 매 스캔마다
    /// 무조건 1초 대기를 해서 배치/단일 스캔 모두 지연의 원인이 됐다. pgrep 로
    /// 잔류분이 없으면 즉시 반환(0초 비용).
    func reapZombieScanimages() {
        let path = scanimage
        // 1) 잔류 scanimage 가 있는지 먼저 확인(비활성 pkill).
        let probe = Process()
        probe.launchPath = "/bin/sh"
        probe.arguments = ["-c", "pgrep -f '\(path)' || true"]
        let probePipe = Pipe()
        probe.standardOutput = probePipe
        try? probe.run(); probe.waitUntilExit()
        let out = (try? probePipe.fileHandleForReading.readToEnd()) ?? Data()
        let count = String(data: out, encoding: .utf8)?
            .split(separator: "\n")
            .filter { !$0.isEmpty }
            .count ?? 0
        guard count > 0 else { return }   // 잔류 없음 → 즉시 반환(1초 대기 생략)

        // 2) 잔류가 있으면 정리.
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "pkill -9 -f '\(path)' || true"]
        try? task.run()
        task.waitUntilExit()
        // USB 해제 대기(좀비가 있었을 때만).
        Thread.sleep(forTimeInterval: 1.0)
    }

    func runScanimage(args: [String]) async throws -> String {
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
        let outQ = DispatchQueue(label: "negaflow.sane.stdout")
        let errQ = DispatchQueue(label: "negaflow.sane.stderr")
        try proc.run()
        let outWork = DispatchWorkItem { outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile() }
        let errWork = DispatchWorkItem { errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile() }
        outQ.async(execute: outWork)
        errQ.async(execute: errWork)
        proc.waitUntilExit()
        // 두 drain 작업이 끝날 때까지 대기.
        outWork.wait()
        errWork.wait()
        lastStderr = String(data: errBox.data, encoding: .utf8) ?? ""
        return String(data: outBox.data, encoding: .utf8) ?? ""
    }

    /// 백그라운드 drain 스레드가 안전하게 쓸 수 있는 버퍼 홀더.
    private final class BufferBox: @unchecked Sendable {
        var data = Data()
    }

    func runScanimageTo(args: [String], outputURL: URL,
                                progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> Int32 {
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
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
            errPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
                if let chunk = try? fh.readToEnd(), let s = String(data: chunk, encoding: .utf8) {
                    self?.appendStderr(s)
                }
            }
            proc.terminationHandler = { [weak self] p in
                errPipe.fileHandleForReading.readabilityHandler = nil
                if let rest = try? errPipe.fileHandleForReading.readToEnd(),
                   let s = String(data: rest, encoding: .utf8) {
                    self?.appendStderr(s)
                }
                try? handle?.close()
                // 프로세스 추적 해제 — 좀비 방지.
                self?.clearCurrentProcess(p)
                cont.resume(returning: p.terminationStatus)
            }
            do {
                try proc.run()
                self.trackCurrentProcess(proc)
            } catch {
                try? handle?.close()
                cont.resume(throwing: error)
            }
        }
    }

    func trackCurrentProcess(_ p: Process) { currentProcess = p }
    func clearCurrentProcess(_ p: Process) {
        if let cp = currentProcess, cp.processIdentifier == p.processIdentifier { currentProcess = nil }
    }

    func appendStderr(_ s: String) { stderrBuffer += s }
    func takeStderr() -> String {
        let s = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        stderrBuffer = ""
        lastStderr = s
        return s
    }



    /// 인스턴스용 환경 — 정적 버전에 캐시된 기본 디바이스를 얹는다.
    /// SANE_DEFAULT_DEVICE 가 있으면 scanimage -L 가 probe 없이 그 장치를 바로 연다.
    func makeSaneEnvironmentWithDefaultDevice() -> [String: String] {
        var env = Self.makeSaneEnvironment()
        // 캐시된 주소가 유효하면 기본 디바이스로 주입.
        if let cached = cachedAddress,
           Date().timeIntervalSince(cachedAddressAt) < addressCacheTTL {
            env["SANE_DEFAULT_DEVICE"] = cached
        }
        return env
    }
}
