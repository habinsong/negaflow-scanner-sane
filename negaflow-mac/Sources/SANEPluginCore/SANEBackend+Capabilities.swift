import Foundation

extension SANEBackend {
    /// scanimage -A 출력을 ScannerCapabilities로 변환한다.
    /// 형식 예: `--resolution 7200|3600|2400|1200|600dpi [600]`
    ///
    /// IR·소스·깊이·지오메트리는 모델명이 아니라 실제 옵션에서 감지한다(백엔드/기기/버전마다 다름).
    ///   • genesys "i" 필름스캐너: transparency 소스 + infrared 소스를 노출한다.
    ///   • epson2 플랫베드: --source Flatbed|Transparency Unit(TPU8x10 포함), --film-type.
    ///     IR 모드는 SANE_FRAME_IR 커스텀 빌드에서만 노출된다.
    ///   • coolscan3(Nikon): --source/--mode 없음, --depth 8|14, 지오메트리 pel 단위.
    ///     --infrared는 stock scanimage가 별도 IR TIFF로 전달하지 못하는 RGBI 프레임이므로 미지원.
    ///   • pieusb(Reflecta/PIE): --clean-image bool(백엔드 내부 IR 먼지 제거), --mode 에 RGBI.
    ///
    /// deviceTypeHint: scanimage -L 의 장치 타입 문자열("film scanner" 등). --source 옵션이 없는
    /// 전용 필름/슬라이드 스캐너의 투과 지원 판정에 쓴다.
    static func parseCapabilities(
        _ dump: String,
        deviceTypeHint: String? = nil,
        backendHint: String? = nil
    ) -> ScannerCapabilities {
        let opts = SaneOptionDump(dump)

        let sources = opts.enumValues("source")
        let modeValuesOriginal = opts.enumValues("mode")
        let modeValues = modeValuesOriginal.map { $0.lowercased() }
        let transparencyModes = sources.filter { isTransparencySource($0) }
        let brightnessRange = opts.numericRange("brightness")
        let contrastRange = opts.numericRange("contrast")
        let hardwareExposureRange = opts.numericRange("scan-exposure-time")
        // 초점은 활성 옵션일 때만 노출한다. epson2 평판은 source에 따라 기본값이 달라지므로
        // 범위를 그대로 올려 호스트가 실제 값을 고르게 한다.
        let focusRange = opts.isActive("focus") ? opts.numericRange("focus") : nil
        let supportsAutofocus = opts.isActive("autofocus")
        let resolutionRange = opts.numericRange("resolution")
        let supportsHardwareExposure = hardwareExposureRange.map { range in
            SANEBackend.hardwareExposureTimes.allSatisfy { range.containsExactly(Double($0)) }
        } ?? false

        // 해상도: 열거형(7200|3600|…dpi)과 범위형(50..6400dpi) 모두 지원.
        var resolutions: [Resolution] = []
        switch opts.resolutionSpec {
        case .list(let dpis):
            resolutions = dpis.map { Resolution($0) }
        case .range(let min, let max):
            let standards = [
                100, 150, 300, 600, 1200, 2400, 3200, 3600, 4800, 6400, 7200, 9600, 12800,
            ]
            var dpis = standards.filter {
                $0 >= min
                    && $0 <= max
                    && resolutionRange?.containsExactly(Double($0)) == true
            }
            if resolutionRange?.containsExactly(Double(max)) == true, !dpis.contains(max) {
                dpis.append(max)
            }
            resolutions = dpis.map { Resolution($0) }
        case .none:
            break
        }

        // 비트깊이: 8 초과(10/12/14/16비트 ADC)는 모두 16비트 컨테이너로 전달된다(SANE 규격).
        // 활성 --depth가 없으면 고정 심도 기기일 수 있다(§fixedDepth) — 이때는 옵션을 보내지
        // 않고 그 심도로만 스캔한다.
        var bitDepths: [BitDepth] = []
        let depthTokens = opts.intTokens("depth")
        if depthTokens.contains(8) { bitDepths.append(.eight) }
        if depthTokens.contains(where: { $0 > 8 }) { bitDepths.append(.sixteen) }
        if bitDepths.isEmpty, let fixed = fixedDepth(opts, backendHint: backendHint) {
            bitDepths = [fixed]
        }

        var modes: [ColorMode] = []
        if modeValues.contains(where: { $0.contains("color") }) { modes.append(.color) }
        if modeValues.contains(where: { $0.contains("gray") || $0.contains("grey") }) { modes.append(.gray) }

        // 투과: 투과 소스가 있거나, --source 자체가 없는 전용 필름/슬라이드 스캐너(coolscan3 등).
        let typeHint = (deviceTypeHint ?? "").lowercased()
        let dedicatedFilmDevice = !opts.isActive("source")
            && (
                typeHint.contains("film")
                    || typeHint.contains("slide")
                    || isDedicatedFilmBackend(backendHint)
            )
        if modes.isEmpty, dedicatedFilmDevice {
            // 일부 전용 필름 백엔드는 --mode가 없고 출력 프레임 형식으로 Color를 고정한다.
            // 실제 결과 TIFF의 채널 수는 획득 뒤 다시 검증한다.
            modes.append(.color)
        }
        let supportsTransparency = !transparencyModes.isEmpty || dedicatedFilmDevice

        // Host의 IR capability는 별도 IR 채널 파일을 뜻한다. clean-image는 백엔드 내부
        // 보정만 수행하므로 IR 채널 capability로 보고하지 않는다.
        let infraredViaSource = sources.contains { isInfraredValue($0) }
        let infraredViaMode = modeValues.contains { $0.contains("infrared") }
        let supportsInfrared = infraredViaSource || infraredViaMode

        // 스캔 영역: mm 단위 범위가 노출될 때만 host의 물리 영역 계약으로 보고한다.
        var minScanArea = ScanArea(widthMM: 0, heightMM: 0)
        var maxScanArea = ScanArea(widthMM: 0, heightMM: 0)
        var scanAreaUnit = ScanAreaUnit.millimeter
        var supportsScanArea = false
        var supportsPositionedScanArea = false
        if opts.rangeUnit("x") == "mm", opts.rangeUnit("y") == "mm",
           let xRange = opts.numericRange("x"), let yRange = opts.numericRange("y"),
           xRange.maximum > 0, yRange.maximum > 0 {
            supportsScanArea = true
            let leftRange = opts.rangeUnit("l") == "mm" ? opts.numericRange("l") : nil
            let topRange = opts.rangeUnit("t") == "mm" ? opts.numericRange("t") : nil
            let surfaceOriginX = leftRange?.minimum ?? 0
            let surfaceOriginY = topRange?.minimum ?? 0
            minScanArea = ScanArea(
                originXMM: surfaceOriginX,
                originYMM: surfaceOriginY,
                widthMM: minimumPositiveScanDimension(xRange),
                heightMM: minimumPositiveScanDimension(yRange)
            )
            maxScanArea = ScanArea(
                originXMM: surfaceOriginX,
                originYMM: surfaceOriginY,
                widthMM: xRange.maximum,
                heightMM: yRange.maximum
            )
            let hasReflectiveSource = sources.contains { !isTransparencySource($0) && !isInfraredValue($0) }
            supportsPositionedScanArea = !transparencyModes.isEmpty
                && hasReflectiveSource
                && leftRange != nil
                && topRange != nil
        } else if opts.rangeUnit("x") == "pel" || opts.rangeUnit("y") == "pel" {
            scanAreaUnit = .pixel
        }

        var disabledReasons: [String: String] = [:]
        if !supportsTransparency {
            disabledReasons["transparency"] = "scanimage -A의 --source에 Transparency/TPU/Film 항목이 없습니다."
        }
        if !supportsInfrared {
            if backendHint == "coolscan3", opts.hasOption("infrared") {
                disabledReasons["infrared"] =
                    "coolscan3의 --infrared는 RGBI 프레임이며 stock scanimage가 별도 IR TIFF로 전달하지 못합니다."
            } else if opts.hasOption("clean-image") {
                disabledReasons["infrared"] =
                    "--clean-image는 별도 IR 채널을 반환하지 않아 IR 채널 기능으로 사용할 수 없습니다."
            } else {
                disabledReasons["infrared"] =
                    "scanimage -A에 별도 IR 채널을 획득할 활성 source/mode가 없습니다."
            }
        }
        if !supportsHardwareExposure {
            disabledReasons["multiExposure"] = opts.hasOption("scan-exposure-time")
                ? "--scan-exposure-time 범위가 필요한 노출 계획을 모두 지원하지 않습니다."
                : "scanimage -A에 --scan-exposure-time이 없어 실제 다중노출을 켤 수 없습니다."
        }
        if brightnessRange == nil {
            disabledReasons["brightness"] = opts.hasOption("brightness")
                ? "현재 스캔 옵션 조합에서 --brightness가 비활성입니다."
                : "scanimage -A에 --brightness 옵션이 없습니다."
        }
        if contrastRange == nil {
            disabledReasons["contrast"] = opts.hasOption("contrast")
                ? "현재 스캔 옵션 조합에서 --contrast가 비활성입니다."
                : "scanimage -A에 --contrast 옵션이 없습니다."
        }
        if focusRange == nil {
            disabledReasons["focus"] = opts.hasOption("focus")
                ? "현재 스캔 옵션 조합에서 --focus가 비활성입니다."
                : "scanimage -A에 --focus 옵션이 없습니다."
        }
        if !supportsAutofocus {
            disabledReasons["autofocus"] = opts.hasOption("autofocus")
                ? "현재 스캔 옵션 조합에서 --autofocus가 비활성입니다."
                : "scanimage -A에 --autofocus 옵션이 없습니다."
        }
        if !supportsScanArea {
            disabledReasons["scanArea"] = "scanimage -A에 mm 단위 -x/-y 범위가 없어 요청 영역을 정확히 적용할 수 없습니다."
        }

        return ScannerCapabilities(
            supportedResolutions: resolutions.sorted(),
            supportedModes: modes,
            supportedBitDepths: bitDepths,
            sourceModes: sources,
            transparencyModes: transparencyModes,
            supportsPreview: opts.isActive("preview"),
            supportsTransparency: supportsTransparency,
            supportsInfrared: supportsInfrared,
            supportsMultiExposure: supportsHardwareExposure,
            supportsScanArea: supportsScanArea,
            supportsPositionedScanArea: supportsPositionedScanArea,
            supportsLampWarmupStatus: false,
            brightnessRange: brightnessRange,
            contrastRange: contrastRange,
            hardwareExposureRange: hardwareExposureRange,
            focusRange: focusRange,
            supportsAutofocus: supportsAutofocus,
            scanOriginXRange: opts.rangeUnit("l") == "mm" ? opts.numericRange("l") : nil,
            scanOriginYRange: opts.rangeUnit("t") == "mm" ? opts.numericRange("t") : nil,
            scanWidthRange: opts.rangeUnit("x") == "mm" ? opts.numericRange("x") : nil,
            scanHeightRange: opts.rangeUnit("y") == "mm" ? opts.numericRange("y") : nil,
            disabledReasons: disabledReasons,
            maxScanArea: maxScanArea,
            minScanArea: minScanArea,
            scanAreaUnit: scanAreaUnit,
            outputFormats: ["tiff"]
        )
    }

    /// 투과/필름 소스인지(Transparency Adapter/TPA, Transparency Unit/TPU, TPU8x10, Film ...).
    static func isTransparencySource(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("transparency")
            || l.contains("tpa")
            || l.contains("tpu")
            || l.contains("film")
            || l.contains("slide")
    }

    /// Color/Gray를 적용한 덤프에서도 `--depth`가 활성이 아닐 때 장치가 고정으로 쓰는 심도.
    /// nil이면 "심도 불명"이며 추정하지 않는다.
    ///
    ///   • 옵션이 비활성인데 제약 목록이 값 하나뿐이면 그 값이 곧 고정 심도다. 값이 여럿인데
    ///     비활성이면 우리가 모르는 이유로 잠긴 상태이므로 아무 값도 고르지 않는다.
    ///   • epson2는 심도가 하나뿐인 구형 기기에서 옵션 자체를 노출하지 않고 항상 8비트로
    ///     전송한다(sane-epson2 문서).
    ///   • pie는 Color/Gray 결과의 SANE_Parameters.depth를 항상 8로 설정하며 별도 depth
    ///     옵션을 제공하지 않는다. 이 두 backend에만 적용하고, 다른 backend에서 옵션이
    ///     없다고 8비트로 추정하지 않는다.
    static func fixedDepth(_ opts: SaneOptionDump, backendHint: String?) -> BitDepth? {
        guard opts.hasOption("depth") else {
            return ["epson2", "pie"].contains(backendHint) ? .eight : nil
        }
        guard !opts.isActive("depth") else { return nil }
        let tokens = opts.constraintIntTokens("depth")
        guard tokens.count == 1, let only = tokens.first else { return nil }
        if only == 8 { return .eight }
        return only > 8 ? .sixteen : nil
    }

    /// Epson V700/V750/V800/V850 계열은 필름 홀더용 투과 source와 8x10 필름 영역 가이드용
    /// source를 따로 노출한다. 8x10 쪽이 영역은 넓지만 유리면에 초점을 두는 다른 렌즈를 쓴다 —
    /// GT-X900 실측에서 같은 필름 지점을 위상상관으로 정렬해 비교하니 홀더용 source가
    /// 1.76배 선명했고(같은 조건 반복 측정 편차는 2.9%), 두 source는 좌표계도 서로 달라
    /// 프리뷰에서 잡은 영역을 본 스캔에 그대로 쓸 수 없다. 그래서 프리뷰와 본 스캔 모두
    /// 홀더용 source를 쓰고, 8x10만 있는 장치에서만 그것을 고른다.
    static func preferredTransparencySource(in sources: [String]) -> String? {
        let visibleTransparency = sources.filter {
            isTransparencySource($0) && !isInfraredValue($0)
        }
        return visibleTransparency.first { !isWideFilmAreaGuideSource($0) }
            ?? visibleTransparency.first
            ?? sources.first(where: isTransparencySource)
    }

    /// 8x10 필름 영역 가이드용 투과 source인지(필름 홀더용보다 넓지만 유리면 초점).
    static func isWideFilmAreaGuideSource(_ s: String) -> Bool {
        s.lowercased().replacingOccurrences(of: " ", with: "").contains("8x10")
    }

    /// infrared 소스/모드 값인지.
    static func isInfraredValue(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("infrared") || l == "ir"
    }

    private static func minimumPositiveScanDimension(_ range: ScannerOptionRange) -> Double {
        if range.minimum > 0 { return range.minimum }
        if let step = range.step, step > 0 { return min(step, range.maximum) }
        return min(0.1, range.maximum)
    }
}
