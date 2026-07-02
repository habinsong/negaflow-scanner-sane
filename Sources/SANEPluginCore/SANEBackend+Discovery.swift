import Foundation

extension SANEBackend {
    /// 장치 문자열의 백엔드 이름. "genesys:libusb:000:010" → "genesys", "epson2:net:..." → "epson2".
    static func backendName(of deviceString: String) -> String {
        String(deviceString.prefix(while: { $0 != ":" }))
    }

    // MARK: detect
    public func detectScanners() async throws -> [ScannerDescriptor] {
        let out = try await runScanimage(args: ["-L"])
        // 형식: `device `genesys:libusb:000:010' is a PLUSTEK OpticFilm 8100 flatbed scanner`
        //       `device `epson2:libusb:001:005' is a Epson Perfection V750 flatbed scanner`
        // 백엔드(genesys/epson2/epkowa/...)와 벤더/모델을 일반적으로 파싱한다 — 모델명 하드코딩 금지(§5.3).
        var devices: [ScannerDescriptor] = []
        let lines = out.split(separator: "\n")
        let deviceRegex = try NSRegularExpression(
            pattern: "device `([^']+)' is a ([^\\s]+)\\s+(.+?) (?:flatbed |film )?scanner"
        )
        for line in lines {
            let s = String(line)
            let range = NSRange(s.startIndex..., in: s)
            if let m = deviceRegex.firstMatch(in: s, range: range),
               let devRange = Range(m.range(at: 1), in: s),
               let vendorRange = Range(m.range(at: 2), in: s),
               let modelRange = Range(m.range(at: 3), in: s) {
                let devname = String(s[devRange])         // genesys:libusb:000:010
                let vendor = String(s[vendorRange])        // PLUSTEK / Epson
                let model = String(s[modelRange]).trimmingCharacters(in: .whitespaces)  // OpticFilm 8100 / Perfection V750
                let backend = Self.backendName(of: devname)
                let id = "sane-\(devname)"
                // genesys 는 Phase 0에서 직접 검증된 백엔드(OpticFilm 필름스캐너 — SANE은 8200i를
                // "8100"으로 보고하므로 모델명으로 8200i를 구분할 수 없다). 그 외 백엔드는 호환 목표로
                // 두고, 실제 지원 여부는 capability(-A)로 판단한다(§5.3).
                let verified: VerifiedStatus = (backend == "genesys") ? .verified : .compatibleTarget
                let display = "\(vendor.capitalized) \(model)".trimmingCharacters(in: .whitespaces)
                devices.append(ScannerDescriptor(
                    id: id,
                    displayName: display.isEmpty ? model : display,
                    vendor: vendor.capitalized,
                    model: model,
                    backendType: .sane,
                    connectionType: devname.contains(":net:") ? .network : .usb,
                    verifiedStatus: verified,
                    driverVersion: "\(backend) (SANE)"
                ))
            }
        }
        return devices
    }

    // MARK: capabilities (scanimage -A 파싱)
    public func getCapabilities(scannerID: String) async throws -> ScannerCapabilities {
        // -A 도 동일하게 현재 주소가 필요하다(scannerID 주소가 만료될 수 있음).
        let raw = scannerID.replacingOccurrences(of: "sane-", with: "")
        let devname = (try? await currentDeviceAddress(targetBackend: Self.backendName(of: raw))) ?? raw
        let dump = try await runScanimage(args: ["-A", "-d", devname])
        return Self.parseCapabilities(dump)
    }

    /// 스캔 직전에 scanimage -L 을 다시 돌려 현재 장치의 libusb 주소를 얻는다.
    ///
    /// USB 장치 주소(libusb:bus:dev)는 스캐너 리셋/재열거로 매 호출마다 바뀐다
    /// (Plustek 8200i + genesys 확인: 010 ↔ 011). scannerID 에 박힌 과거 주소로
    /// open 하면 "open of device failed: Invalid argument" 로 실패한다.
    /// 따라서 스캔 직전에 반드시 현재 주소를 다시 얻어야 한다.
    ///
    /// 매칭은 USB Vendor/Product ID(8200i = 0x07b3:0x130C)로 한다 — 주소가 아닌
    /// 안정적인 장치 식별자 기반. scannerID 접두사(sane-)를 벗긴 값이
    /// "genesys:libusb:..." 형태이므로, 그 안의 vid/pid 가 아니라 -L 의 동일
    /// 모델 문자열(PLUSTEK ... OpticFilm ...)을 기준으로 현재 주소를 찾는다.
    ///
    /// 스캔 직전 현재 장치 주소를 다시 얻는다(USB 주소는 리셋마다 바뀜). 백엔드 힌트가 있으면 같은
    /// 백엔드(genesys/epson2/...) 장치를 고른다 — 여러 백엔드 스캐너가 붙어 있어도 올바른 장치를 연다.
    func currentDeviceAddress(targetBackend: String? = nil) async throws -> String {
        if let cached = cachedAddress,
           cachedAddressBackend == targetBackend,
           Date().timeIntervalSince(cachedAddressAt) < addressCacheTTL {
            return cached
        }
        let out = try await runScanimage(args: ["-L"])
        // 백엔드 무관하게 백틱 안 장치 문자열을 모두 뽑는다.
        let regex = try NSRegularExpression(pattern: "device `([^']+)'")
        let range = NSRange(out.startIndex..., in: out)
        var deviceStrings: [String] = []
        for m in regex.matches(in: out, range: range) {
            if let r = Range(m.range(at: 1), in: out) { deviceStrings.append(String(out[r])) }
        }
        let chosen = targetBackend
            .flatMap { tb in deviceStrings.first { Self.backendName(of: $0) == tb } }
            ?? deviceStrings.first
        if let chosen {
            cachedAddress = chosen
            cachedAddressBackend = targetBackend
            cachedAddressAt = Date()
            return chosen
        }
        cachedAddress = nil
        cachedAddressAt = .distantPast
        throw ScannerError(.notConnected, "scanimage -L 이 장치를 찾지 못함 (주소 재획득 실패)")
    }

    /// 캐시 강제 무효화(장치 점유/재연결 등).
    public func invalidateAddressCache() {
        cachedAddress = nil
        cachedAddressBackend = nil
        cachedAddressAt = .distantPast
    }

    // MARK: media selection (source / mode / film-type / IR)

    func resolveMedia(options: ScanOptions) async -> MediaSelection {
        let raw = options.scannerID.replacingOccurrences(of: "sane-", with: "")
        let devname = (try? await currentDeviceAddress(targetBackend: Self.backendName(of: raw))) ?? raw
        let dump = (try? await runScanimage(args: ["-A", "-d", devname])) ?? ""
        return Self.resolveMedia(dump: dump, options: options)
    }

    /// 순수 함수(테스트 가능): -A 덤프 + 옵션 → MediaSelection.
    static func resolveMedia(dump: String, options: ScanOptions) -> MediaSelection {
        let baseMode = options.colorMode == .gray ? "Gray" : "Color"
        let sources = parseSources(dump)
        let modeValues = parseModeValues(dump)
        let transparency = sources.first(where: { isTransparencySource($0) && !isInfraredValue($0) })
            ?? sources.first(where: { isTransparencySource($0) })
        let infraredSource = sources.first(where: { isInfraredValue($0) })
        let hasInfraredMode = modeValues.contains { $0.contains("infrared") }
        let hasFilmType = dump.contains("--film-type")

        // 기본 소스: 투과 소스 우선, 없으면 파싱 결과 첫 값, 파싱 실패 시 genesys 호환 기본값.
        var source: String? = transparency ?? (sources.isEmpty ? "Transparency Adapter" : sources.first)
        var mode = baseMode
        var usesInfrared = false
        if options.infraredEnabled {
            if let infraredSource { source = infraredSource; usesInfrared = true }
            else if hasInfraredMode { mode = "Infrared"; usesInfrared = true }
        }
        var filmType: String? = nil
        if hasFilmType, let src = source, isTransparencySource(src) {
            filmType = options.filmType.requiresInversion ? "Negative Film" : "Positive Film"
        }
        return MediaSelection(source: source, mode: mode, filmType: filmType, usesInfrared: usesInfrared)
    }
}
