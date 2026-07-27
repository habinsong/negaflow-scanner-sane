import Foundation

private struct SANECapabilitySnapshot: Codable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var deviceID: String
    var backend: String
    var acquisitionDevice: String
    var deviceIdentity: SANEBackend.DeviceIdentity?
    var deviceType: String?
    var optionDump: String
    /// optionDump가 실제로 적용해 조회한 모드. 다른 모드 요청에는 이 덤프를 재사용하지 않는다.
    var validatedMode: ColorMode?
}

extension SANEBackend {
    /// 장치 문자열의 백엔드 이름. "genesys:libusb:000:010" → "genesys", "epson2:net:..." → "epson2".
    static func backendName(of deviceString: String) -> String {
        String(deviceString.prefix(while: { $0 != ":" }))
    }

    /// 주소 없는 `-d backend` 선택자를 실제 재열거 회피가 필요한 백엔드에만 허용한다.
    ///
    /// SANE의 dll 계층은 이 형식을 backend의 빈 장치명으로 전달한다. genesys와 epson2는
    /// 빈 장치명을 첫 장치로 처리하지만, coolscan2/3처럼 거부하는 구현도 있으므로 USB
    /// 백엔드 전체로 일반화하면 안 된다.
    static func supportsStableBackendSelector(_ backend: String) -> Bool {
        backend == "genesys" || backend == "epson2"
    }

    static func connectionType(of deviceString: String) -> ConnectionType {
        let value = deviceString.lowercased()
        if value.contains(":net:") { return .network }
        if value.contains(":scsi:") || value.contains("/dev/sg") { return .scsi }
        if value.contains(":firewire:")
            || value.contains(":ieee1394:")
            || value.contains(":ieee-1394:") {
            return .fireWire
        }
        if value.contains(":usb:") || value.contains(":libusb:") { return .usb }
        return .internalBus
    }

    static func isDedicatedFilmBackend(_ backend: String?) -> Bool {
        guard let backend else { return false }
        return ["coolscan", "coolscan2", "coolscan3", "pie", "pieusb"].contains(backend)
    }

    /// SANE 장치 목록 한 줄 파싱 결과.
    struct ListedDevice: Sendable, Equatable {
        var devname: String     // genesys:libusb:000:010
        var vendor: String      // PLUSTEK / Epson / Nikon / PIE/Reflecta
        var model: String       // OpticFilm 8100 / GT-X970 / LS-50 ED
        var deviceType: String  // flatbed scanner / film scanner / …
    }

    /// scanimage -L 이 내는 장치 타입 접미사(백엔드 자유 문자열). 긴 것부터 매치한다.
    private static let deviceTypeSuffixes = [
        "multi-function peripheral", "flatbed scanner", "film scanner", "slide scanner",
        "sheetfed scanner", "sheet-fed scanner", "handheld scanner", "hand-held scanner",
        "frame grabber", "virtual device", "video camera", "still camera", "scanner",
    ]

    /// -L 출력 전체를 장치 목록으로 파싱한다. 형식:
    ///   `device \`coolscan3:usb:libusb:001:002' is a Nikon LS-50 ED film scanner`
    ///   `device \`epson2:libusb:001:005' is a Epson GT-X970 flatbed scanner`
    /// 타입 접미사를 떼고 첫 토큰을 벤더, 나머지를 모델로 삼는다 — 모델명 하드코딩 금지(§5.3).
    static func parseDeviceList(_ out: String) -> [ListedDevice] {
        var devices: [ListedDevice] = []
        guard let regex = try? NSRegularExpression(pattern: "device `([^']+)' is a (.+)$") else { return devices }
        for line in out.split(separator: "\n") {
            let s = String(line)
            let range = NSRange(s.startIndex..., in: s)
            guard let m = regex.firstMatch(in: s, range: range),
                  let devRange = Range(m.range(at: 1), in: s),
                  let restRange = Range(m.range(at: 2), in: s) else { continue }
            let devname = String(s[devRange])
            var rest = String(s[restRange]).trimmingCharacters(in: .whitespaces)
            var deviceType = ""
            for suffix in deviceTypeSuffixes where rest.lowercased().hasSuffix(suffix) {
                deviceType = String(rest.suffix(suffix.count))
                rest = String(rest.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
            let tokens = rest.split(separator: " ", maxSplits: 1)
            let vendor = tokens.first.map(String.init) ?? rest
            let model = tokens.count > 1 ? String(tokens[1]).trimmingCharacters(in: .whitespaces) : vendor
            devices.append(ListedDevice(devname: devname, vendor: vendor, model: model, deviceType: deviceType))
        }
        return devices
    }

    /// scanimage 공식 `--formatted-device-list` 형식.
    /// `%d`, `%v`, `%m`, `%t`를 탭으로 분리해 번역된 `-L` 문장을 파싱하지 않는다.
    static func parseFormattedDeviceList(_ output: String) -> [ListedDevice] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { raw in
            let fields = raw.split(
                separator: "\t",
                maxSplits: 3,
                omittingEmptySubsequences: false
            ).map(String.init)
            guard fields.count == 4, !fields[0].isEmpty else { return nil }
            return ListedDevice(
                devname: fields[0],
                vendor: fields[1].trimmingCharacters(in: .whitespaces),
                model: fields[2].trimmingCharacters(in: .whitespaces),
                deviceType: fields[3].trimmingCharacters(in: .whitespaces)
            )
        }
    }

    /// 최신 scanimage에서는 구조화된 목록을 사용하고, 오래된 구현·테스트 더블은 -L로
    /// 후퇴한다. 취소와 시간 초과는 다른 프로세스를 다시 띄우지 않고 즉시 전파한다.
    func listDevices(ownedByScanSession: Bool = false) async throws -> [ListedDevice] {
        do {
            let formatted = try await runScanimage(
                args: ["-f", "%d\t%v\t%m\t%t%n"],
                ownedByScanSession: ownedByScanSession
            )
            let devices = Self.parseFormattedDeviceList(formatted)
            if !devices.isEmpty {
                cacheListedDevices(devices)
                return devices
            }
        } catch let error as ScannerError
            where error.code == .cancelled || error.code == .timeout {
            throw error
        } catch {
            // 구형 scanimage가 -f를 거부하면 아래 -L 호환 경로를 사용한다.
        }
        let legacy = try await runScanimage(
            args: ["-L"],
            ownedByScanSession: ownedByScanSession
        )
        let devices = Self.parseDeviceList(legacy)
        cacheListedDevices(devices)
        return devices
    }

    private func cacheListedDevices(_ devices: [ListedDevice]) {
        for device in devices {
            cachedDeviceTypes[device.devname] = device.deviceType
            cachedDeviceIdentities[device.devname] = DeviceIdentity(
                vendor: device.vendor,
                model: device.model
            )
        }
    }

    // MARK: detect
    public func detectScanners() async throws -> [ScannerDescriptor] {
        try await listDevices().map { device in
            let backend = Self.backendName(of: device.devname)
            let display = "\(device.vendor.capitalized) \(device.model)".trimmingCharacters(in: .whitespaces)
            return ScannerDescriptor(
                id: "sane-\(device.devname)",
                displayName: display.isEmpty ? device.model : display,
                vendor: device.vendor.capitalized,
                model: device.model,
                backendType: .sane,
                connectionType: Self.connectionType(of: device.devname),
                // backend명이나 모델명만으로 실기 검증을 추정하지 않는다. 가상 장치 테스트는
                // 호환성 증거이며 실제 개별 하드웨어 검증과 동등하지 않다.
                verifiedStatus: .compatibleTarget,
                driverVersion: "\(backend) (SANE)"
            )
        }
    }

    // MARK: capabilities (scanimage -A 파싱)
    public func getCapabilities(scannerID: String) async throws -> ScannerCapabilities {
        try await getCapabilitiesReport(scannerID: scannerID).capabilities
    }

    public func getCapabilitiesReport(
        scannerID: String,
        expectedIdentity: DeviceIdentity? = nil
    ) async throws -> SANECapabilityReport {
        let (devname, dump) = try await capabilityOptionsDump(
            scannerID: scannerID,
            expectedIdentity: expectedIdentity,
            ownedByScanSession: false
        )
        let backend = Self.backendName(
            of: scannerID.replacingOccurrences(of: "sane-", with: "")
        )
        // 토큰에 제조사·모델을 반드시 실어 보낸다. 이후 스캔은 주소가 바뀌어도 이 정보로
        // "같은 모델"임을 확인하고 재연결한다. 식별자가 비면 스캔 시점에 같은 backend의
        // 다른 스캐너로 갈아끼워도 알아챌 수 없다.
        var identity = cachedDeviceIdentity(for: devname) ?? expectedIdentity
        if identity == nil {
            identity = try? await resolveIdentity(devname: devname, backend: backend)
        }
        let snapshot = SANECapabilitySnapshot(
            schemaVersion: SANECapabilitySnapshot.currentSchemaVersion,
            deviceID: scannerID,
            backend: backend,
            acquisitionDevice: devname,
            deviceIdentity: identity,
            deviceType: cachedDeviceType(for: devname),
            optionDump: dump,
            validatedMode: Self.validatedColorMode(
                in: dump,
                backend: backend,
                deviceTypeHint: cachedDeviceType(for: devname)
            )
        )
        let token: String
        do {
            token = try JSONEncoder().encode(snapshot).base64EncodedString()
        } catch {
            throw ScannerError(.ioFailure, "capability 스냅샷 인코딩 실패: \(error.localizedDescription)")
        }
        let capabilities = Self.parseCapabilities(
            dump,
            deviceTypeHint: cachedDeviceType(for: devname),
            backendHint: backend
        )
        return SANECapabilityReport(
            capabilities: capabilities,
            capabilityToken: token
        )
    }

    /// 스캔 직전에 scanimage 장치 목록을 다시 돌려 현재 장치의 libusb 주소를 얻는다.
    ///
    /// 실측(Plustek OpticFilm 8100 + sane-backends 1.4.0):
    ///   • 장치를 **열 때마다** libusb 주소가 바뀐다. `002:001 → 002:002 → 002:001`로 번갈아 관측.
    ///   • 목록 조회(-L/-f)만으로는 주소가 바뀌지 않는다. 즉 목록은 장치를 건드리지 않는다.
    ///   • 따라서 "목록은 싸고 안전하고, open은 방금 얻은 주소를 태운다"로 다뤄야 한다.
    ///
    /// 호스트 USB 컨트롤러가 같은 device number를 재사용하면(예: 어떤 Mac에서는 그렇다) 이
    /// 문제가 드러나지 않는다. 재사용하지 않는 기기에서는 직전 주소로 open할 때마다
    /// "open of device failed: Invalid argument"가 나므로 반드시 재연결할 수 있어야 한다.
    ///
    /// 백엔드 힌트가 있으면 같은 백엔드(genesys/epson2/coolscan3/...) 장치를 고른다 —
    /// 여러 제조사 스캐너가 동시에 붙어 있어도 올바른 장치를 연다.
    func currentDeviceAddress(
        targetDevice: String? = nil,
        targetBackend: String? = nil,
        expectedIdentity: DeviceIdentity? = nil,
        allowSingleBackendSelector: Bool = false,
        ownedByScanSession: Bool = false
    ) async throws -> String {
        if let cached = liveCachedSelector(
            targetDevice: targetDevice,
            targetBackend: targetBackend,
            expectedIdentity: expectedIdentity
        ) {
            return cached
        }
        let listed = try await listDevices(ownedByScanSession: ownedByScanSession)
        let backendMatches = targetBackend.map { backend in
            listed.filter { Self.backendName(of: $0.devname) == backend }
        } ?? []
        let exactMatch = targetDevice.flatMap { target in
            listed.first { $0.devname == target }
        }
        let identityMatches = expectedIdentity.map { identity in
            backendMatches.filter { Self.sameIdentity($0, identity) }
        } ?? []
        let chosen: ListedDevice?
        if let exactMatch,
           expectedIdentity.map({ Self.sameIdentity(exactMatch, $0) }) ?? true {
            chosen = exactMatch
        } else if expectedIdentity != nil, identityMatches.count == 1 {
            chosen = identityMatches[0]
        } else if targetBackend == nil, listed.count == 1 {
            chosen = listed[0]
        } else if expectedIdentity == nil, targetBackend != nil, backendMatches.count == 1 {
            // 제조사·모델 힌트가 없어도 해당 backend 장치가 정확히 하나뿐이면 모호하지 않다.
            // 이 갈래가 없으면 open 한 번으로 주소가 바뀐 뒤 재연결이 항상 실패했다.
            // (장치가 둘 이상이면 아래에서 계속 거부한다 — 엉뚱한 스캐너를 열지 않는다.)
            chosen = backendMatches[0]
        } else {
            chosen = nil
        }
        if let chosen {
            // 주소 독립 선택자는 backend 구현이 빈 장치명을 지원하고, 같은 backend 장치가
            // 정확히 하나일 때만 쓴다. 그 밖의 backend는 방금 목록에서 확인한 전체 주소를
            // 유지해 coolscan2/3 같은 구현에 빈 장치명을 넘기지 않는다.
            let resolvedAddress: String
            if allowSingleBackendSelector,
               let targetBackend,
               Self.supportsStableBackendSelector(targetBackend),
               backendMatches.count == 1,
               chosen.devname.contains(":libusb:") {
                resolvedAddress = targetBackend
            } else {
                resolvedAddress = chosen.devname
            }
            cachedAddress = resolvedAddress
            cachedAddressBackend = targetBackend
            cachedAddressTarget = targetDevice
            cachedAddressIdentity = expectedIdentity
            cachedAddressIsStableSelector = !resolvedAddress.contains(":")
            cachedAddressAt = Date()
            cachedDeviceTypes[resolvedAddress] = chosen.deviceType
            cachedDeviceTypes[chosen.devname] = chosen.deviceType
            let identity = DeviceIdentity(vendor: chosen.vendor, model: chosen.model)
            cachedDeviceIdentities[resolvedAddress] = identity
            cachedDeviceIdentities[chosen.devname] = identity
            return resolvedAddress
        }
        invalidateAddressCache()
        if expectedIdentity != nil, identityMatches.count > 1 {
            throw ScannerError(
                .notConnected,
                "같은 제조사·모델의 \(targetBackend ?? "SANE") 장치가 여러 대라 대상 장치를 안전하게 식별할 수 없습니다."
            )
        }
        if let expectedIdentity, !backendMatches.isEmpty {
            throw ScannerError(
                .notConnected,
                "연결된 \(targetBackend ?? "SANE") 장치가 선택한 \(expectedIdentity.vendor) \(expectedIdentity.model)과 일치하지 않습니다."
            )
        }
        throw ScannerError(
            .notConnected,
            "SANE 장치 주소가 바뀌었지만 제조사·모델 정보가 없어 안전하게 재연결할 수 없습니다. 장치를 다시 검색하십시오."
        )
    }

    /// capability를 읽은 장치의 제조사·모델을 목록에서 확인한다.
    ///
    /// capability 조회 자체가 장치를 한 번 열어 주소를 바꿔놓았을 수 있으므로 이름이 정확히
    /// 맞지 않을 수 있다. 그때는 같은 backend 장치가 하나뿐일 때만 그 장치의 식별자를 쓴다 —
    /// 여러 대가 붙어 있으면 어느 쪽인지 단정할 수 없으므로 식별자 없이 둔다.
    private func resolveIdentity(
        devname: String,
        backend: String
    ) async throws -> DeviceIdentity? {
        let listed = try await listDevices()
        if let exact = listed.first(where: { $0.devname == devname }) {
            return DeviceIdentity(vendor: exact.vendor, model: exact.model)
        }
        let backendMatches = listed.filter { Self.backendName(of: $0.devname) == backend }
        guard backendMatches.count == 1, let only = backendMatches.first else { return nil }
        return DeviceIdentity(vendor: only.vendor, model: only.model)
    }

    func cachedDeviceType(for devname: String) -> String? {
        cachedDeviceTypes[devname]
    }

    func cachedDeviceIdentity(for devname: String) -> DeviceIdentity? {
        cachedDeviceIdentities[devname]
    }

    private static func sameIdentity(_ device: ListedDevice, _ identity: DeviceIdentity) -> Bool {
        normalizedIdentityComponent(device.vendor) == normalizedIdentityComponent(identity.vendor)
            && normalizedIdentityComponent(device.model) == normalizedIdentityComponent(identity.model)
    }

    private static func normalizedIdentityComponent(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// 이 프로세스에서 이미 확인해 아직 유효한 선택자. 목록 조회를 새로 하지 않는다.
    func liveCachedSelector(
        targetDevice: String?,
        targetBackend: String?,
        expectedIdentity: DeviceIdentity?
    ) -> String? {
        guard let cached = cachedAddress,
              cachedAddressBackend == targetBackend,
              cachedAddressTarget == targetDevice,
              cachedAddressIdentity == expectedIdentity,
              cachedAddressIsStableSelector
                || Date().timeIntervalSince(cachedAddressAt) < addressCacheTTL else {
            return nil
        }
        return cached
    }

    /// 캐시 강제 무효화(장치 점유/재연결 등).
    public func invalidateAddressCache() {
        cachedAddress = nil
        cachedAddressBackend = nil
        cachedAddressTarget = nil
        cachedAddressIdentity = nil
        cachedAddressIsStableSelector = false
        cachedAddressAt = .distantPast
    }

    /// 장치를 실제로 연 scanimage 실행이 끝났음을 기록한다.
    ///
    /// 장치를 한 번 열면 libusb 주소가 바뀔 수 있으므로(§currentDeviceAddress 실측) 주소 기반
    /// 선택자는 open 이후 만료로 취급한다. 죽은 주소로 여는 시도 자체는 하드웨어에 닿기 전에
    /// 즉시 실패하지만(실측 ~11ms), 그걸 방치하면 스캔 패스마다 헛된 open + 목록 재조회가
    /// 한 번씩 붙는다. backend 선택자(`genesys`)는 주소와 무관하므로 유지한다.
    func noteDeviceOpened() {
        guard !cachedAddressIsStableSelector else { return }
        invalidateAddressCache()
    }

    // MARK: media selection (source / mode / depth / resolution / geometry / IR)

    func resolveMedia(options: ScanOptions) async throws -> MediaSelection {
        if let token = options.capabilityToken {
            let snapshot = try Self.decodeCapabilitySnapshot(token, for: options)
            let raw = options.scannerID.replacingOccurrences(of: "sane-", with: "")
            let selected: (devname: String, dump: String)
            if snapshot.validatedMode == options.colorMode {
                selected = (snapshot.acquisitionDevice, snapshot.optionDump)
            } else {
                // Color에서 읽은 depth/geometry 활성 상태를 Gray 요청에 재사용하지 않는다.
                // 정상 Color 경로에는 추가 open이 없고, 실제로 다른 모드를 요청할 때만
                // 그 모드를 적용한 -A를 한 번 읽는다.
                selected = try await scanSpecificOptionsDump(
                    sourceDump: snapshot.optionDump,
                    devname: snapshot.acquisitionDevice,
                    targetDevice: raw,
                    backend: snapshot.backend,
                    expectedIdentity: snapshot.deviceIdentity,
                    options: options
                )
            }
            var media = Self.resolveMedia(
                dump: selected.dump,
                options: options,
                deviceTypeHint: snapshot.deviceType
            )
            media.acquisitionDevice = selected.devname
            media.expectedDeviceIdentity = snapshot.deviceIdentity
            return media
        }

        let (devname, sourceDump) = try await capabilityOptionsDump(
            scannerID: options.scannerID,
            expectedIdentity: nil,
            ownedByScanSession: true
        )
        // 단일 투과 소스만 가진 genesys 필름 스캐너는 장치를 연속해서 여러 번 열면 실제
        // OpticFilm에서 다음 acquisition이 실패할 수 있다. 같은 덤프를 재사용하되,
        // Flatbed/Transparency를 함께 가진 genesys 장치는 소스별 재검증을 그대로 수행한다.
        let raw = options.scannerID.replacingOccurrences(of: "sane-", with: "")
        let dump: String
        let acquisitionDevice: String
        if Self.canReuseSinglePassOptionsDump(sourceDump, backend: Self.backendName(of: devname)) {
            dump = sourceDump
            acquisitionDevice = devname
        } else {
            // capability 덤프를 읽으며 이미 장치를 열었으므로 주소가 바뀌었을 수 있다.
            (acquisitionDevice, dump) = try await scanSpecificOptionsDump(
                sourceDump: sourceDump,
                devname: devname,
                targetDevice: raw,
                backend: Self.backendName(of: raw),
                expectedIdentity: cachedDeviceIdentity(for: devname),
                options: options
            )
        }
        guard !SaneOptionDump(dump).isEmpty else {
            throw ScannerError(.ioFailure, "scanimage -A가 적용 가능한 옵션을 반환하지 않았습니다.")
        }
        var media = Self.resolveMedia(
            dump: dump,
            options: options,
            deviceTypeHint: cachedDeviceType(for: devname)
        )
        media.acquisitionDevice = acquisitionDevice
        media.expectedDeviceIdentity = cachedDeviceIdentity(for: acquisitionDevice)
            ?? cachedDeviceIdentity(for: devname)
        return media
    }

    private static func decodeCapabilitySnapshot(
        _ token: String,
        for options: ScanOptions
    ) throws -> SANECapabilitySnapshot {
        guard token.utf8.count <= 1_048_576,
              let data = Data(base64Encoded: token),
              let snapshot = try? JSONDecoder().decode(SANECapabilitySnapshot.self, from: data) else {
            throw ScannerError(.unsupportedOption, "capabilityToken을 해석할 수 없습니다. 장치 능력을 다시 조회하십시오.")
        }
        let requestedBackend = backendName(
            of: options.scannerID.replacingOccurrences(of: "sane-", with: "")
        )
        guard snapshot.schemaVersion == SANECapabilitySnapshot.currentSchemaVersion,
              snapshot.deviceID == options.scannerID,
              snapshot.backend == requestedBackend,
              !snapshot.acquisitionDevice.isEmpty,
              !SaneOptionDump(snapshot.optionDump).isEmpty else {
            throw ScannerError(.unsupportedOption, "capabilityToken이 현재 장치와 일치하지 않습니다. 장치 능력을 다시 조회하십시오.")
        }
        return snapshot
    }

    /// capability와 scan preflight 모두 현재 USB 주소에서 유효한 옵션 덤프를 얻어야 한다.
    /// SANE가 장치를 재열거하거나 잠깐 점유 중이면 주소 캐시를 버리고 제한적으로 재시도한다.
    private func capabilityOptionsDump(
        scannerID: String,
        expectedIdentity: DeviceIdentity?,
        ownedByScanSession: Bool
    ) async throws -> (devname: String, dump: String) {
        let raw = scannerID.replacingOccurrences(of: "sane-", with: "")
        let backend = Self.backendName(of: raw)
        var finalError: Error?

        for attempt in 0..<3 {
            do {
                let devname: String
                if attempt == 0, expectedIdentity == nil {
                    // detect가 넘긴 전체 SANE 장치명을 먼저 그대로 사용한다. detect는 목록만
                    // 읽고 장치를 열지 않으므로 이 주소는 아직 살아 있다. 정상 장치에서는
                    // 별도 목록 조회 프로세스 없이 capability를 한 번만 열 수 있다.
                    devname = raw
                } else {
                    devname = try await currentDeviceAddress(
                        targetDevice: raw,
                        targetBackend: backend,
                        expectedIdentity: expectedIdentity,
                        allowSingleBackendSelector: attempt == 2,
                        ownedByScanSession: ownedByScanSession
                    )
                }
                // 단일-source genesys 필름 스캐너는 추가 open을 피하면서 주 사용 모드인
                // Color 상태의 덤프를 얻는다. 다른 모드는 실제 요청 시 별도로 검증한다.
                var baseArgs = ["-A", "-d", devname]
                if backend == "genesys" {
                    baseArgs += ["--mode", "Color"]
                }
                let baseDump = try await runScanimage(
                    args: baseArgs,
                    ownedByScanSession: ownedByScanSession
                )
                guard !SaneOptionDump(baseDump).isEmpty else {
                    throw ScannerError(
                        .ioFailure,
                        "scanimage -A가 적용 가능한 옵션을 반환하지 않았습니다."
                    )
                }
                guard !Self.canReuseSinglePassOptionsDump(baseDump, backend: backend) else {
                    return (devname, baseDump)
                }
                // 위 `-A`가 이미 장치를 한 번 열었으므로 주소가 만료됐을 수 있다. 두 번째
                // `-A`가 그 때문에 실패하면 현재 선택자를 다시 확인해 한 번만 재시도한다.
                // 이 재연결이 없으면 투과 소스를 따로 가진 장치(epson2/pieusb/coolscan3 등)에서
                // capability 조회가 통째로 실패한다.
                return try await sourceSpecificOptionsDump(
                    baseDump: baseDump,
                    devname: devname,
                    targetDevice: raw,
                    backend: backend,
                    expectedIdentity: expectedIdentity,
                    ownedByScanSession: ownedByScanSession
                )
            } catch {
                finalError = error
                guard attempt < 2, Self.shouldRetryCapabilityRead(after: error) else {
                    throw error
                }
                invalidateAddressCache()
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }

        throw finalError ?? ScannerError(.ioFailure, "스캐너 옵션 조회에 실패했습니다.")
    }

    /// 직전 open으로 주소가 만료돼 다시 열어야 할 때 쓸 현재 선택자.
    ///
    /// 주소가 없는 backend 선택자는 재열거를 견디므로 재확인할 것이 없다(nil을 돌려 재시도를
    /// 멈춘다). 목록 조회는 장치를 건드리지 않으므로 이 재확인 자체는 스캐너에 무해하다.
    func reopenSelector(
        previous: String,
        targetDevice: String,
        backend: String,
        expectedIdentity: DeviceIdentity?,
        ownedByScanSession: Bool
    ) async -> String? {
        guard previous.contains(":") else { return nil }
        invalidateAddressCache()
        guard let resolved = try? await currentDeviceAddress(
            targetDevice: targetDevice,
            targetBackend: backend,
            expectedIdentity: expectedIdentity,
            allowSingleBackendSelector: false,
            ownedByScanSession: ownedByScanSession
        ), resolved != previous else {
            return nil
        }
        return resolved
    }

    static func canReuseSinglePassOptionsDump(_ dump: String, backend: String) -> Bool {
        guard backend == "genesys" else { return false }
        let sources = SaneOptionDump(dump).enumValues("source")
        let nonInfraredSources = sources.filter { !isInfraredValue($0) }
        guard nonInfraredSources.count == 1, let source = nonInfraredSources.first else {
            return false
        }
        return isTransparencySource(source)
    }

    private static func shouldRetryCapabilityRead(after error: Error) -> Bool {
        if let scannerError = error as? ScannerError {
            switch scannerError.code {
            case .busy, .notConnected, .ioFailure:
                return true
            case .unsupportedOption, .driverConflict, .cancelled, .timeout, .unknown:
                return false
            }
        }
        return isStaleDeviceError(error.localizedDescription)
    }

    /// mode/depth/resolution/preview 설정도 다른 SANE 옵션의 범위·step을 바꿀 수 있으므로,
    /// 실제 요청값을 적용한 상태에서 한 번 더 `-A`를 읽어 최종 geometry 계약을 검증한다.
    private func scanSpecificOptionsDump(
        sourceDump: String,
        devname: String,
        targetDevice: String,
        backend: String,
        expectedIdentity: DeviceIdentity?,
        options: ScanOptions
    ) async throws -> (devname: String, dump: String) {
        let preliminary = Self.resolveMedia(dump: sourceDump, options: options)
        func arguments(for device: String) -> [String] {
            var args = ["-A", "-d", device]
            if let source = preliminary.source { args += ["--source", source] }
            if let mode = preliminary.mode { args += ["--mode", mode] }
            if let dpi = preliminary.resolvedDPI { args += ["--resolution", "\(dpi)"] }
            if let depth = preliminary.depthArgument { args += ["--depth", "\(depth)"] }
            if options.resolution == .preview, preliminary.hasPreviewOption {
                args += ["--preview=yes"]
            }
            return args
        }
        var currentDevname = devname
        var lastError: Error?
        for attempt in 0..<2 {
            if attempt > 0 {
                guard let reopened = await reopenSelector(
                    previous: currentDevname,
                    targetDevice: targetDevice,
                    backend: backend,
                    expectedIdentity: expectedIdentity
                        ?? cachedDeviceIdentity(for: currentDevname),
                    ownedByScanSession: true
                ) else { break }
                currentDevname = reopened
            }
            do {
                let dump = try await runScanimage(
                    args: arguments(for: currentDevname),
                    ownedByScanSession: true
                )
                guard !SaneOptionDump(dump).isEmpty else {
                    throw ScannerError(
                        .ioFailure,
                        "최종 스캔 옵션 적용 뒤 scanimage -A가 옵션을 반환하지 않았습니다."
                    )
                }
                return (currentDevname, dump)
            } catch {
                lastError = error
                guard attempt == 0, Self.isStaleDeviceError(error.localizedDescription) else { throw error }
            }
        }
        throw lastError ?? ScannerError(.ioFailure, "최종 스캔 옵션 조회에 실패했습니다.")
    }

    /// SANE는 `source`/`mode` 설정 뒤 다른 옵션과 범위를 다시 로드할 수 있다. 투과 소스와
    /// 실제로 스캔할 모드를 고른 뒤 `-A`를 다시 요청해, 그 상태의 지오메트리와 활성 옵션을
    /// capability/scan preflight에 사용한다.
    ///
    /// `--depth`가 비활성이면 모드도 함께 적용한다. epson2는 기본 모드가 Lineart이고 그
    /// 상태에서 `--depth`를 비활성으로 내린다(실측: Epson GT-X980 = V850). 모드를 적용하지 않은
    /// 덤프만 읽으면 지원 심도가 통째로 비어 스캐너를 쓸 수 없는 것으로 오판한다. capability는
    /// 실제로 스캔할 Color(없으면 Gray) 기준으로 읽는다.
    private func sourceSpecificOptionsDump(
        baseDump: String,
        devname: String,
        targetDevice: String,
        backend: String,
        expectedIdentity: DeviceIdentity?,
        ownedByScanSession: Bool
    ) async throws -> (devname: String, dump: String) {
        guard Self.capabilityRedumpArguments(baseDump: baseDump, devname: devname) != nil else {
            return (devname, baseDump)
        }
        var currentDevname = devname
        var lastError: Error?
        for attempt in 0..<2 {
            if attempt > 0 {
                guard let reopened = await reopenSelector(
                    previous: currentDevname,
                    targetDevice: targetDevice,
                    backend: backend,
                    expectedIdentity: expectedIdentity,
                    ownedByScanSession: ownedByScanSession
                ) else { break }
                currentDevname = reopened
            }
            do {
                guard let args = Self.capabilityRedumpArguments(
                    baseDump: baseDump,
                    devname: currentDevname
                ) else {
                    return (currentDevname, baseDump)
                }
                let selectedDump = try await runScanimage(
                    args: args,
                    ownedByScanSession: ownedByScanSession
                )
                guard !SaneOptionDump(selectedDump).isEmpty else {
                    throw ScannerError(
                        .ioFailure,
                        "source/mode 선택 뒤 scanimage -A가 옵션을 반환하지 않았습니다."
                    )
                }
                return (currentDevname, selectedDump)
            } catch {
                lastError = error
                guard attempt == 0, Self.isStaleDeviceError(error.localizedDescription) else { throw error }
            }
        }
        throw lastError ?? ScannerError(.ioFailure, "source/mode 옵션 조회에 실패했습니다.")
    }

    /// capability 재조회에 적용할 모드. 이 앱이 실제로 스캔하는 Color 우선, 없으면 Gray.
    /// Lineart는 쓰지 않으므로 그 상태의 옵션을 capability로 보고하지 않는다.
    static func capabilityDumpMode(in dump: String) -> String? {
        let modeValues = SaneOptionDump(dump).enumValues("mode")
        return pickModeValue(modeValues, colorMode: .color)
            ?? pickModeValue(modeValues, colorMode: .gray)
    }

    static func validatedColorMode(
        in dump: String,
        backend: String,
        deviceTypeHint: String?
    ) -> ColorMode? {
        let opts = SaneOptionDump(dump)
        if let selected = opts.selectedEnumValue("mode")?.lowercased() {
            if selected.contains("color") { return .color }
            if selected.contains("gray") || selected.contains("grey") { return .gray }
            return nil
        }
        let type = (deviceTypeHint ?? "").lowercased()
        if !opts.isActive("mode"),
           type.contains("film") || type.contains("slide") || isDedicatedFilmBackend(backend) {
            return .color
        }
        return nil
    }

    /// 순수 함수(테스트 가능): capability 재조회 인자. nil이면 base 덤프를 그대로 쓴다.
    ///
    /// 모드는 필요할 때만 싣는다. 장치를 한 번 더 여는 것은 전용 필름 스캐너에서 다음
    /// acquisition을 깨뜨릴 수 있으므로(§canReuseSinglePassOptionsDump), 이미 `--depth`가
    /// 활성인 장치는 모드 때문에 다시 열지 않는다. 소스 때문에 어차피 다시 열 때는 같은
    /// 호출에 모드를 함께 실어 추가 open 없이 심도를 활성화한다.
    static func capabilityRedumpArguments(baseDump: String, devname: String) -> [String]? {
        let opts = SaneOptionDump(baseDump)
        let source = preferredTransparencySource(in: opts.enumValues("source"))
        let depthNeedsMode = opts.hasOption("depth") && !opts.isActive("depth")
        let mode = (source != nil || depthNeedsMode) ? capabilityDumpMode(in: baseDump) : nil
        guard source != nil || mode != nil else { return nil }
        var args = ["-A", "-d", devname]
        if let source { args += ["--source", source] }
        if let mode { args += ["--mode", mode] }
        return args
    }

    /// 순수 함수(테스트 가능): -A 덤프 + 옵션 → MediaSelection.
    /// 장치가 실제 노출하는 옵션만 사용한다. 옵션이 없거나 요청값이 정확히 없으면
    /// production preflight가 실패하며 장치 기본값을 적용값으로 추정하지 않는다.
    static func resolveMedia(
        dump: String,
        options: ScanOptions,
        deviceTypeHint: String? = nil
    ) -> MediaSelection {
        let backend = backendName(of: options.scannerID.replacingOccurrences(of: "sane-", with: ""))
        let opts = SaneOptionDump(dump)
        let normalizedDeviceType = (deviceTypeHint ?? "").lowercased()
        let dedicatedFilmDevice = !opts.isActive("source")
            && (
                normalizedDeviceType.contains("film")
                    || normalizedDeviceType.contains("slide")
                    || isDedicatedFilmBackend(backend)
            )

        // 옵션 덤프가 없으면 어떤 값도 추정하지 않는다. production 경로는 이 상태를 오류로 처리한다.
        if opts.isEmpty {
            return MediaSelection(
                source: nil, mode: nil, filmType: nil,
                depthArgument: nil, resolvedDPI: nil,
                originXMM: nil, originYMM: nil,
                widthMM: nil, heightMM: nil
            )
        }

        let sources = opts.enumValues("source")
        let modeValues = opts.enumValues("mode")

        // 소스: 투과(비-IR) 우선. --source 옵션이 없으면 생략(coolscan3 등 전용 필름 스캐너).
        let transparency = preferredTransparencySource(in: sources)
        let source: String? = sources.isEmpty ? nil : (transparency ?? sources.first)

        // 모드: 장치 원문 값에서 선택(--mode 없으면 생략).
        let mode = pickModeValue(modeValues, colorMode: options.colorMode)
        let grayMode = pickModeValue(modeValues, colorMode: .gray)
        let colorCorrectionValues = opts.enumValues("color-correction")
        let gammaCorrectionValues = opts.enumValues("gamma-correction")
        let colorCorrection = backend == "epson2"
            ? colorCorrectionValues.first {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("None") == .orderedSame
            }
            : nil
        let gammaCorrection = backend == "epson2"
            ? gammaCorrectionValues.first {
                $0.lowercased().replacingOccurrences(of: " ", with: "")
                    .contains("gamma=1.0")
            } ?? gammaCorrectionValues.first {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("User defined") == .orderedSame
            }
            : nil

        // 깊이: 16-bit host 계약은 SANE의 9...16-bit 샘플이 16-bit TIFF 컨테이너로
        // 기록되는 경우를 포함한다. 8-bit 요청을 16-bit로 바꾸거나 그 반대는 허용하지 않는다.
        // 활성 --depth가 없는 고정 심도 기기는 옵션 없이 그 심도로만 스캔한다(§fixedDepth).
        var depthArgument: Int? = nil
        let fixedDepth = Self.fixedDepth(opts, backendHint: backend)
        let depthTokens = opts.intTokens("depth").filter { $0 >= 8 }
        switch options.bitDepth {
        case .eight:
            if depthTokens.contains(8) { depthArgument = 8 }
        case .sixteen:
            depthArgument = depthTokens.contains(16) ? 16 : depthTokens.filter { $0 > 8 }.max()
        }

        // 해상도: 정확히 지원하는 값만 전달한다. 목록 밖/범위 step 밖 요청은 nil로 남겨
        // preflight에서 명시적으로 실패시키며 가장 가까운 값으로 스냅하지 않는다.
        let resolutionRange = opts.numericRange("resolution")
        let requestedDPI = options.resolution.dpi
        let resolvedDPI: Int?
        if requestedDPI <= 0 {
            resolvedDPI = nil
        } else {
            switch opts.resolutionSpec {
            case .list(let values):
                resolvedDPI = values.contains(requestedDPI) ? requestedDPI : nil
            case .range:
                resolvedDPI = resolutionRange?.containsExactly(Double(requestedDPI)) == true
                    ? requestedDPI
                    : nil
            case .none:
                resolvedDPI = nil
            }
        }

        // 지오메트리: mm 단위 장치만 전체 영역을 명시(-x/-y). pel(픽셀) 단위 장치(coolscan3)는
        // 생략 — 백엔드 기본값이 전체 프레임이고 mm 값을 넘기면 N픽셀 폭으로 오해된다.
        var originXMM: Double? = nil
        var originYMM: Double? = nil
        var widthMM: Double? = nil
        var heightMM: Double? = nil
        var originXPixels: Int? = nil
        var originYPixels: Int? = nil
        var widthPixels: Int? = nil
        var heightPixels: Int? = nil
        var rightPixels: Int? = nil
        var bottomPixels: Int? = nil
        var usesCornerPixelGeometry = false
        if opts.rangeUnit("x") == "mm", opts.rangeUnit("y") == "mm",
           let xRange = opts.numericRange("x"), let yRange = opts.numericRange("y"),
           xRange.maximum > 0, yRange.maximum > 0 {
            if xRange.containsExactly(options.scanArea.widthMM),
               yRange.containsExactly(options.scanArea.heightMM) {
                widthMM = options.scanArea.widthMM
                heightMM = options.scanArea.heightMM
            }
            if opts.rangeUnit("l") == "mm", let leftRange = opts.numericRange("l"),
               leftRange.containsExactly(options.scanArea.originXMM) {
                originXMM = options.scanArea.originXMM
            }
            if opts.rangeUnit("t") == "mm", let topRange = opts.numericRange("t"),
               topRange.containsExactly(options.scanArea.originYMM) {
                originYMM = options.scanArea.originYMM
            }
        } else if requestedDPI > 0,
                  opts.rangeUnit("x") == "pel", opts.rangeUnit("y") == "pel",
                  let xRange = opts.numericRange("x"), let yRange = opts.numericRange("y") {
            widthPixels = pixelGeometryValue(
                millimeters: options.scanArea.widthMM,
                dpi: requestedDPI,
                range: xRange
            )
            heightPixels = pixelGeometryValue(
                millimeters: options.scanArea.heightMM,
                dpi: requestedDPI,
                range: yRange
            )
            if opts.rangeUnit("l") == "pel", let leftRange = opts.numericRange("l") {
                originXPixels = pixelGeometryValue(
                    millimeters: options.scanArea.originXMM,
                    dpi: requestedDPI,
                    range: leftRange
                )
            }
            if opts.rangeUnit("t") == "pel", let topRange = opts.numericRange("t") {
                originYPixels = pixelGeometryValue(
                    millimeters: options.scanArea.originYMM,
                    dpi: requestedDPI,
                    range: topRange
                )
            }
        } else if let unitDPI = maximumResolutionDPI(in: opts),
                  opts.rangeUnit("tl-x") == "pel",
                  opts.rangeUnit("tl-y") == "pel",
                  opts.rangeUnit("br-x") == "pel",
                  opts.rangeUnit("br-y") == "pel",
                  let leftRange = opts.numericRange("tl-x"),
                  let topRange = opts.numericRange("tl-y"),
                  let rightRange = opts.numericRange("br-x"),
                  let bottomRange = opts.numericRange("br-y"),
                  let left = pixelGeometryValue(
                      millimeters: options.scanArea.originXMM,
                      dpi: unitDPI,
                      range: leftRange
                  ),
                  let top = pixelGeometryValue(
                      millimeters: options.scanArea.originYMM,
                      dpi: unitDPI,
                      range: topRange
                  ),
                  let width = pixelGeometryLength(
                      millimeters: options.scanArea.widthMM,
                      unitDPI: unitDPI
                  ),
                  let height = pixelGeometryLength(
                      millimeters: options.scanArea.heightMM,
                      unitDPI: unitDPI
                  ),
                  rightRange.containsExactly(Double(left + width - 1)),
                  bottomRange.containsExactly(Double(top + height - 1)) {
            originXPixels = left
            originYPixels = top
            rightPixels = left + width - 1
            bottomPixels = top + height - 1
            usesCornerPixelGeometry = true
        }

        // 필름 타입: epson2의 --film-type, 구형 coolscan의 --type, coolscan2/3의
        // bool --negative를 장치가 실제 노출한 이름대로 사용한다.
        var filmType: String? = nil
        let filmTypeOptionName = opts.isActive("film-type")
            ? "film-type"
            : (opts.isActive("type")
                ? "type"
                : (opts.isActive("negative") ? "negative" : nil))
        if let filmTypeOptionName,
           source == nil || source.map({ isTransparencySource($0) }) == true {
            if filmTypeOptionName == "negative",
               backend == "coolscan2" || backend == "coolscan3" {
                // 이 옵션은 필름 메타데이터가 아니라 스캐너 자체 색 반전이다.
                // negaflow가 원본 네거티브 밀도를 현상하므로 장치 반전은 항상 끈다.
                filmType = "no"
            } else {
                let preserveRawCoolscan = backend == "coolscan" && filmTypeOptionName == "type"
                let requestedPolarity = preserveRawCoolscan || !options.filmType.requiresInversion
                    ? "positive"
                    : "negative"
                let values = opts.enumValues(filmTypeOptionName)
                let polarityMatches = values.filter { $0.lowercased().contains(requestedPolarity) }
                if options.filmType.requiresInversion && !preserveRawCoolscan {
                    filmType = polarityMatches.first {
                        !$0.lowercased().contains("slide")
                    } ?? polarityMatches.first
                } else {
                    filmType = polarityMatches.first {
                        $0.lowercased().contains("slide")
                    } ?? polarityMatches.first
                }
            }
        }

        let scanLeftRange = opts.rangeUnit("l") == "mm" ? opts.numericRange("l") : nil
        let scanTopRange = opts.rangeUnit("t") == "mm" ? opts.numericRange("t") : nil
        let scanWidthRange = opts.rangeUnit("x") == "mm" ? opts.numericRange("x") : nil
        let scanHeightRange = opts.rangeUnit("y") == "mm" ? opts.numericRange("y") : nil
        let scanSurfaceRightMM = scanWidthRange.map {
            max(scanLeftRange?.maximum ?? $0.maximum, (scanLeftRange?.minimum ?? 0) + $0.maximum)
        }
        let scanSurfaceBottomMM = scanHeightRange.map {
            max(scanTopRange?.maximum ?? $0.maximum, (scanTopRange?.minimum ?? 0) + $0.maximum)
        }

        // 별도 파일로 검증할 수 있는 IR source/mode만 사용한다. coolscan3의 --infrared는
        // RGBI 한 프레임이고 stock scanimage가 이를 별도 IR TIFF로 직렬화하지 못한다.
        var irStrategy: IRStrategy = .none
        if options.infraredEnabled {
            let infraredSource = sources.first(where: { isInfraredValue($0) })
            let infraredMode = modeValues.first(where: { $0.lowercased().contains("infrared") })
            if let infraredSource {
                irStrategy = .separateSource(infraredSource)
            } else if let infraredMode {
                irStrategy = .separateMode(infraredMode)
            }
        }

        return MediaSelection(
            source: source,
            mode: mode,
            filmType: filmType,
            filmTypeOptionName: filmTypeOptionName,
            depthArgument: depthArgument,
            fixedDepth: fixedDepth,
            resolvedDPI: resolvedDPI,
            originXMM: originXMM,
            originYMM: originYMM,
            widthMM: widthMM,
            heightMM: heightMM,
            hasPreviewOption: opts.isActive("preview"),
            hasBrightnessOption: opts.isActive("brightness"),
            hasContrastOption: opts.isActive("contrast"),
            hasScanExposureOption: opts.isActive("scan-exposure-time"),
            hasModeOption: opts.isActive("mode"),
            hasDepthOption: opts.isActive("depth"),
            hasFilmTypeOption: filmTypeOptionName != nil,
            hasAdvanceOption: opts.isActive("advance"),
            colorCorrection: colorCorrection,
            gammaCorrection: gammaCorrection,
            hasColorCorrectionOption: opts.isActive("color-correction"),
            hasGammaCorrectionOption: opts.isActive("gamma-correction"),
            brightnessRange: opts.numericRange("brightness"),
            contrastRange: opts.numericRange("contrast"),
            hardwareExposureRange: opts.numericRange("scan-exposure-time"),
            resolutionRange: resolutionRange,
            scanLeftRange: scanLeftRange,
            scanTopRange: scanTopRange,
            scanWidthRange: scanWidthRange,
            scanHeightRange: scanHeightRange,
            scanSurfaceRightMM: scanSurfaceRightMM,
            scanSurfaceBottomMM: scanSurfaceBottomMM,
            irStrategy: irStrategy,
            irPassMode: grayMode,
            dedicatedFilmDevice: dedicatedFilmDevice,
            originXPixels: originXPixels,
            originYPixels: originYPixels,
            widthPixels: widthPixels,
            heightPixels: heightPixels,
            rightPixels: rightPixels,
            bottomPixels: bottomPixels,
            usesCornerPixelGeometry: usesCornerPixelGeometry
        )
    }

    private static func maximumResolutionDPI(in options: SaneOptionDump) -> Int? {
        switch options.resolutionSpec {
        case .list(let values):
            return values.max()
        case .range(_, let maximum):
            return maximum
        case .none:
            return nil
        }
    }

    private static func pixelGeometryValue(
        millimeters: Double,
        dpi: Int,
        range: ScannerOptionRange
    ) -> Int? {
        guard millimeters.isFinite, millimeters >= 0, dpi > 0 else { return nil }
        let exactPixels = millimeters * Double(dpi) / 25.4
        let roundedPixels = exactPixels.rounded()
        guard abs(exactPixels - roundedPixels) <= 0.5 + 1e-9,
              roundedPixels >= Double(Int.min),
              roundedPixels <= Double(Int.max) else {
            return nil
        }
        let value = Int(roundedPixels)
        return range.containsExactly(Double(value)) ? value : nil
    }

    private static func pixelGeometryLength(
        millimeters: Double,
        unitDPI: Int
    ) -> Int? {
        guard millimeters.isFinite, millimeters > 0, unitDPI > 0 else { return nil }
        let rounded = (millimeters * Double(unitDPI) / 25.4).rounded()
        guard rounded >= 1, rounded <= Double(Int.max) else { return nil }
        return Int(rounded)
    }

    /// --mode 열거값(원문 대소문자)에서 요청 모드에 맞는 값을 고른다.
    private static func pickModeValue(_ values: [String], colorMode: ColorMode) -> String? {
        guard !values.isEmpty else { return nil }
        let want: (String) -> Bool
        switch colorMode {
        case .gray: want = { $0.contains("gray") || $0.contains("grey") }
        case .lineart: want = { $0.contains("lineart") || $0.contains("binary") }
        case .infrared: want = { $0.contains("infrared") }
        case .color: want = { $0.contains("color") }
        }
        if let match = values.first(where: { want($0.lowercased()) }) { return match }
        return nil
    }
}
