// SPDX-License-Identifier: GPL-2.0-or-later
//
// 파리티 기준 출력 — **저장소의 실제 구현**을 그대로 호출한다.
//
// `@testable import` 로 internal 심볼에 접근하므로 소스 복사가 없다.
// 복사본을 두면 원본이 바뀌어도 파리티가 통과해버린다.
//
// windows/tests/parity_dump.cpp 와 같은 key=value 줄을 내야 한다.
// tools/parity-check.sh 가 둘을 diff 한다.

@testable import SANEPluginCore
import Foundation
import CoreImage
import CoreGraphics

func emit(_ k: String, _ v: String) { print("\(k)=\(v)") }

func rangeText(_ r: ScannerOptionRange?) -> String {
    guard let r = r else { return "<nil>" }
    let stepText: String
    if let st = r.step { stepText = String(st) } else { stepText = "nil" }
    return String(r.minimum) + ".." + String(r.maximum) + " step=" + stepText
}

// =========================================================================
// sane/option_dump
// =========================================================================

let dump = """
Options specific to device `genesys:libusb:001:002':
  Scan Mode:
    --mode Color|Gray [Color]
        Selects the scan mode.
    --source Transparency Adapter|Transparency Adapter Infrared [Transparency Adapter]
        Selects the scan source.
    --resolution 7200|3600|2400|1200|600dpi [600]
        Sets the resolution.
    --depth 8|16 [16]
        Number of bits per sample.
  Geometry:
    -l 0..36.33mm [0]
    -t 0..44.25mm [0]
    -x 0..36.33mm [36.33]
    -y 0..44.25mm [44.25]
  Enhancement:
    --brightness -100..100 (in steps of 1) [0]
    --contrast -100..100 (in steps of 1) [inactive]
    --preview[=(yes|no)] [no]

"""

let d = SaneOptionDump(dump)
emit("names", d.optionNames.sorted().joined(separator: ","))
emit("inactive", d.inactiveOptionNames.sorted().joined(separator: ","))
emit("mode.enum", d.enumValues("mode").joined(separator: "|"))
emit("source.enum", d.enumValues("source").joined(separator: "|"))
emit("mode.selected", d.selectedEnumValue("mode") ?? "<nil>")
emit("contrast.enum", d.enumValues("contrast").joined(separator: "|"))
emit("depth.int", d.intTokens("depth").map(String.init).joined(separator: ","))
emit("x.range", rangeText(d.numericRange("x")))
emit("brightness.range", rangeText(d.numericRange("brightness")))
emit("contrast.range", rangeText(d.numericRange("contrast")))
emit("x.unit", d.rangeUnit("x") ?? "<nil>")
switch d.resolutionSpec {
case .list(let v): emit("resolution", "list:" + v.map(String.init).joined(separator: ","))
case .range(let a, let b): emit("resolution", "range:\(a)..\(b)")
case .none: emit("resolution", "none")
}

let inactiveDepth = SaneOptionDump("    --depth 8 [inactive]\n")
emit("inactiveDepth.int", inactiveDepth.intTokens("depth").map(String.init).joined(separator: ","))
emit("inactiveDepth.constraint",
     inactiveDepth.constraintIntTokens("depth").map(String.init).joined(separator: ","))

let cs = SaneOptionDump("    --depth 8|14 [8]\n")
emit("coolscan.depth", cs.intTokens("depth").map(String.init).joined(separator: ","))

let pel = SaneOptionDump("    -x 0..3600pel [3600]\n")
emit("pel.unit", pel.rangeUnit("x") ?? "<nil>")

let noUnit = SaneOptionDump("    --scan-exposure-time 0..65535 [11000]\n")
emit("noUnit.unit", noUnit.rangeUnit("scan-exposure-time") ?? "<nil>")

// CRLF — 알려진 divergence. Swift 는 "\r\n" 을 한 Character 로 보아 줄을 못 나눈다.
// 근거: windows_docs/02-frontend-contract/option-dump-parser.md §2.2.1
let crlf = SaneOptionDump("    --mode Color|Gray [Color]\r\n    --depth 8|16 [16]\r\n")
emit("crlf.mode", crlf.enumValues("mode").joined(separator: "|"))
emit("crlf.depth", crlf.intTokens("depth").map(String.init).joined(separator: ","))

let dup = SaneOptionDump("    --mode Color [Color]\n    --mode Gray|Lineart [Gray]\n")
emit("dup.mode", dup.enumValues("mode").joined(separator: "|"))

let rangeRes = SaneOptionDump("    --resolution 50..6400dpi [600]\n")
switch rangeRes.resolutionSpec {
case .range(let a, let b): emit("rangeRes", "range:\(a)..\(b)")
default: emit("rangeRes", "other")
}

// =========================================================================
// sane/device_list
// =========================================================================

let listOut = """
device `coolscan3:usb:libusb:001:002' is a Nikon LS-50 ED film scanner
device `epson2:libusb:001:005' is a Epson GT-X970 flatbed scanner
device `genesys:libusb:001:003' is a PLUSTEK OpticFilm 8100 film scanner
device `pieusb:libusb:002:004' is a PIE/Reflecta ProScan 10T slide scanner
device `net:host.local:genesys:libusb:001:002' is a Remote Thing multi-function peripheral
device `v4l:/dev/video0' is a Noname Webcam virtual device
garbage line that should be ignored
device `weird:x' is a SingleToken scanner
"""

func describe(_ x: SANEBackend.ListedDevice) -> String {
    return x.devname + "|" + x.vendor + "|" + x.model + "|" + x.deviceType
}

for (i, item) in SANEBackend.parseDeviceList(listOut).enumerated() {
    emit("L[\(i)]", describe(item))
}

let formatted = "genesys:libusb:001:003\tPLUSTEK\tOpticFilm 8100\tfilm scanner\n"
    + "epson2:libusb:001:005\t Epson \t GT-X970 \t flatbed scanner \n"
    + "broken-line-without-tabs\n"
    + "\tEmptyDev\tm\tt\n"
for (i, item) in SANEBackend.parseFormattedDeviceList(formatted).enumerated() {
    emit("F[\(i)]", describe(item))
}

let deviceStrings = [
    "genesys:libusb:001:002", "epson2:net:host:1", "coolscan:scsi:0:1:2",
    "pie:/dev/sg0", "x:firewire:1", "y:ieee1394:2", "plain", "net:h:genesys:libusb:1:2",
]
for s in deviceStrings {
    emit("backend[" + s + "]", SANEBackend.backendName(of: s))
    emit("conn[" + s + "]", SANEBackend.connectionType(of: s).rawValue)
    emit("volatile[" + s + "]", String(SANEBackend.isVolatileUSBSelector(s)))
}

let backends = ["genesys", "epson2", "coolscan3", "pieusb", "pie", "coolscan", "net", "unknown"]
for b in backends {
    emit("stable[" + b + "]", String(SANEBackend.supportsStableBackendSelector(b)))
    emit("film[" + b + "]", String(SANEBackend.isDedicatedFilmBackend(b)))
    emit("watchdog[" + b + "]", String(SANEBackend.usesAutomaticAcquisitionWatchdog(backend: b)))
}

let vendors = ["PLUSTEK", "Epson", "pie/reflecta", "NIKON CORP.", "gt-x970",
               "a1b2", "  spaced  out  ", "x", ""]
for v in vendors {
    emit("cap[" + v + "]", v.capitalized)
}

// =========================================================================
// sane/capabilities
// =========================================================================

func capsText(_ c: ScannerCapabilities) -> String {
    var parts: [String] = []
    parts.append("res=" + c.supportedResolutions.map { String($0.dpi) }.joined(separator: ","))
    parts.append("modes=" + c.supportedModes.map { $0.rawValue }.joined(separator: ","))
    parts.append("depths=" + c.supportedBitDepths.map { String($0.rawValue) }.joined(separator: ","))
    parts.append("src=" + (c.sourceModes ?? []).joined(separator: "/"))
    parts.append("tp=" + (c.transparencyModes ?? []).joined(separator: "/"))
    parts.append("prev=" + String(c.supportsPreview))
    parts.append("transp=" + String(c.supportsTransparency))
    parts.append("ir=" + String(c.supportsInfrared))
    parts.append("mexp=" + String(c.supportsMultiExposure))
    parts.append("area=" + String(c.supportsScanArea))
    parts.append("pos=" + String(c.supportsPositionedScanArea))
    parts.append("bright=" + rangeText(c.brightnessRange))
    parts.append("contrast=" + rangeText(c.contrastRange))
    parts.append("hwexp=" + rangeText(c.hardwareExposureRange))
    parts.append("ox=" + rangeText(c.scanOriginXRange))
    parts.append("oy=" + rangeText(c.scanOriginYRange))
    parts.append("w=" + rangeText(c.scanWidthRange))
    parts.append("h=" + rangeText(c.scanHeightRange))
    parts.append("min=" + String(c.minScanArea.originXMM) + "," + String(c.minScanArea.originYMM)
                 + "," + String(c.minScanArea.widthMM) + "," + String(c.minScanArea.heightMM))
    parts.append("max=" + String(c.maxScanArea.originXMM) + "," + String(c.maxScanArea.originYMM)
                 + "," + String(c.maxScanArea.widthMM) + "," + String(c.maxScanArea.heightMM))
    parts.append("unit=" + c.scanAreaUnit.rawValue)
    parts.append("disabled=" + (c.disabledReasons ?? [:]).keys.sorted().joined(separator: ","))
    return parts.joined(separator: " ")
}

emit("caps.genesys", capsText(SANEBackend.parseCapabilities(dump, deviceTypeHint: "film scanner", backendHint: "genesys")))

let epsonDump = """
    --mode Lineart|Gray|Color [Lineart]
    --source Flatbed|Transparency Unit|TPU8x10 [Flatbed]
    --resolution 50..12800dpi [50]
    --depth 8|16 [inactive]
    -l 0..215.9mm [0]
    -t 0..297.18mm [0]
    -x 0..215.9mm [215.9]
    -y 0..297.18mm [297.18]
    --scan-exposure-time 0..65535 [11000]
"""
emit("caps.epson2", capsText(SANEBackend.parseCapabilities(epsonDump, deviceTypeHint: "flatbed scanner", backendHint: "epson2")))

let coolscanDump = """
    --depth 8|14 [8]
    --infrared[=(yes|no)] [no]
    -x 0..3600pel [3600]
    -y 0..5400pel [5400]
"""
emit("caps.coolscan3", capsText(SANEBackend.parseCapabilities(coolscanDump, deviceTypeHint: "film scanner", backendHint: "coolscan3")))

emit("caps.empty", capsText(SANEBackend.parseCapabilities("", deviceTypeHint: nil, backendHint: nil)))

// preferredTransparencySource / fixedDepth / minimumPositiveScanDimension
let srcSets: [[String]] = [
    ["Flatbed", "Transparency Unit", "TPU8x10"],
    ["Transparency Adapter", "Transparency Adapter Infrared"],
    ["Transparency Adapter Infrared"],
    ["Flatbed"],
    [],
]
for (i, ss) in srcSets.enumerated() {
    emit("pref[\(i)]", SANEBackend.preferredTransparencySource(in: ss) ?? "<nil>")
}

let depthDumps = [
    "    --depth 8|16 [16]\n",
    "    --depth 8 [inactive]\n",
    "    --depth 14 [inactive]\n",
    "    --depth 8|16 [inactive]\n",
    "    --mode Color [Color]\n",
]
for (i, dd) in depthDumps.enumerated() {
    let o = SaneOptionDump(dd)
    emit("fixed[\(i)].epson2", SANEBackend.fixedDepth(o, backendHint: "epson2").map { String($0.rawValue) } ?? "<nil>")
    emit("fixed[\(i)].genesys", SANEBackend.fixedDepth(o, backendHint: "genesys").map { String($0.rawValue) } ?? "<nil>")
}

for (i, ss) in [["transparency adapter"], ["TPU"], ["Film Holder"], ["Slide"], ["Flatbed"], ["ADF"]].enumerated() {
    emit("isTp[\(i)]", String(SANEBackend.isTransparencySource(ss[0])))
    emit("isIr[\(i)]", String(SANEBackend.isInfraredValue(ss[0])))
}
emit("isIr.exact", String(SANEBackend.isInfraredValue("ir")))
emit("isIr.word", String(SANEBackend.isInfraredValue("Infrared")))

// =========================================================================
// sane/media
// =========================================================================

func mediaText(_ m: SANEBackend.MediaSelection) -> String {
    func o(_ v: String?) -> String { v ?? "<nil>" }
    func oi(_ v: Int?) -> String { v.map(String.init) ?? "<nil>" }
    func ol(_ v: Int?) -> String { v.map(String.init) ?? "<nil>" }
    func od(_ v: Double?) -> String { v.map { String($0) } ?? "<nil>" }
    var p: [String] = []
    p.append("src=" + o(m.source))
    p.append("mode=" + o(m.mode))
    p.append("ft=" + o(m.filmType))
    p.append("ftOpt=" + o(m.filmTypeOptionName))
    p.append("depth=" + oi(m.depthArgument))
    p.append("fixed=" + (m.fixedDepth.map { String($0.rawValue) } ?? "<nil>"))
    p.append("dpi=" + oi(m.resolvedDPI))
    p.append("ox=" + od(m.originXMM))
    p.append("oy=" + od(m.originYMM))
    p.append("w=" + od(m.widthMM))
    p.append("h=" + od(m.heightMM))
    p.append("halign=" + String(m.heightAlignmentMM))
    p.append("prev=" + String(m.hasPreviewOption))
    p.append("bright=" + String(m.hasBrightnessOption))
    p.append("contrast=" + String(m.hasContrastOption))
    p.append("hwexp=" + String(m.hasScanExposureOption))
    p.append("hasMode=" + String(m.hasModeOption))
    p.append("hasDepth=" + String(m.hasDepthOption))
    p.append("hasFt=" + String(m.hasFilmTypeOption))
    p.append("hasAdv=" + String(m.hasAdvanceOption))
    p.append("cc=" + o(m.colorCorrection))
    p.append("gc=" + o(m.gammaCorrection))
    p.append("hasCC=" + String(m.hasColorCorrectionOption))
    p.append("hasGC=" + String(m.hasGammaCorrectionOption))
    p.append("brRange=" + rangeText(m.brightnessRange))
    p.append("srMM=" + od(m.scanSurfaceRightMM))
    p.append("sbMM=" + od(m.scanSurfaceBottomMM))
    switch m.irStrategy {
    case .none: p.append("ir=none")
    case .separateSource(let v): p.append("ir=src:" + v)
    case .separateMode(let v): p.append("ir=mode:" + v)
    case .cleanImage(let v): p.append("ir=clean:" + v)
    }
    p.append("irMode=" + o(m.irPassMode))
    p.append("film=" + String(m.dedicatedFilmDevice))
    p.append("px=" + ol(m.originXPixels) + "," + ol(m.originYPixels) + ","
             + ol(m.widthPixels) + "," + ol(m.heightPixels) + ","
             + ol(m.rightPixels) + "," + ol(m.bottomPixels))
    p.append("corner=" + String(m.usesCornerPixelGeometry))
    return p.joined(separator: " ")
}

func makeOptions(id: String, dpi: Int, depth: BitDepth, mode: ColorMode, film: FilmType,
                 area: ScanArea, ir: Bool) -> ScanOptions {
    return ScanOptions(
        scannerID: id, resolution: Resolution(dpi), bitDepth: depth, colorMode: mode,
        filmType: film, scanArea: area, infraredEnabled: ir, multiExposureEnabled: false,
        hardwareExposureTime: nil, brightnessAdjustment: nil, contrastAdjustment: nil,
        outputRawTIFF: true, temporaryOutputURL: nil, capabilityToken: nil)
}

let frame = ScanArea(originXMM: 0, originYMM: 0, widthMM: 36, heightMM: 24)

// genesys 16-bit — 톤 조정이 억제돼야 한다
emit("media.genesys16", mediaText(SANEBackend.resolveMedia(
    dump: dump,
    options: makeOptions(id: "sane-genesys:libusb:1:2", dpi: 3600, depth: .sixteen,
                         mode: .color, film: .colorNegative, area: frame, ir: false),
    deviceTypeHint: "film scanner")))

// genesys 8-bit — 톤 조정이 살아 있어야 한다
emit("media.genesys8", mediaText(SANEBackend.resolveMedia(
    dump: dump,
    options: makeOptions(id: "sane-genesys:libusb:1:2", dpi: 1200, depth: .eight,
                         mode: .color, film: .colorNegative, area: frame, ir: false),
    deviceTypeHint: "film scanner")))

// genesys + IR 요청
emit("media.genesysIR", mediaText(SANEBackend.resolveMedia(
    dump: dump,
    options: makeOptions(id: "sane-genesys:libusb:1:2", dpi: 3600, depth: .sixteen,
                         mode: .color, film: .colorNegative, area: frame, ir: true),
    deviceTypeHint: "film scanner")))

// 지원하지 않는 dpi — resolvedDPI 가 nil 이어야 한다(스냅 금지)
emit("media.badDPI", mediaText(SANEBackend.resolveMedia(
    dump: dump,
    options: makeOptions(id: "sane-genesys:libusb:1:2", dpi: 2000, depth: .sixteen,
                         mode: .color, film: .colorNegative, area: frame, ir: false),
    deviceTypeHint: "film scanner")))

// epson2 — 색/감마 보정 + 정수 mm 높이 정렬
let epson2Dump = """
    --mode Lineart|Gray|Color [Color]
    --source Flatbed|Transparency Unit|TPU8x10 [Flatbed]
    --film-type Positive Film|Negative Film [Positive Film]
    --color-correction None|User defined [None]
    --gamma-correction Default|User defined (Gamma=1.0)|User defined (Gamma=1.8) [Default]
    --resolution 50..12800dpi [50]
    --depth 8|16 [16]
    -l 0..215.9mm [0]
    -t 0..297.18mm [0]
    -x 0..215.9mm [215.9]
    -y 0..297.18mm [297.18]
"""
emit("media.epson2", mediaText(SANEBackend.resolveMedia(
    dump: epson2Dump,
    options: makeOptions(id: "sane-epson2:libusb:1:5", dpi: 1200, depth: .sixteen,
                         mode: .color, film: .colorNegative,
                         area: ScanArea(originXMM: 0, originYMM: 0, widthMM: 36, heightMM: 23.5),
                         ir: false),
    deviceTypeHint: "flatbed scanner")))

// coolscan3 — --mode 없음, pel 지오메트리, --negative 는 항상 no
let coolscan3Dump = """
    --depth 8|14 [8]
    --negative[=(yes|no)] [no]
    --resolution 4000dpi [4000]
    -x 0..3600pel [3600]
    -y 0..5400pel [5400]
"""
emit("media.coolscan3", mediaText(SANEBackend.resolveMedia(
    dump: coolscan3Dump,
    options: makeOptions(id: "sane-coolscan3:libusb:1:2", dpi: 4000, depth: .sixteen,
                         mode: .color, film: .colorNegative, area: frame, ir: false),
    deviceTypeHint: "film scanner")))

// pieusb — advance 옵션
let pieusbDump = """
    --mode Color|RGBI [Color]
    --advance[=(yes|no)] [yes]
    --clean-image[=(yes|no)] [no]
    --resolution 3600dpi [3600]
    -x 0..36mm [36]
    -y 0..24mm [24]
"""
emit("media.pieusb", mediaText(SANEBackend.resolveMedia(
    dump: pieusbDump,
    options: makeOptions(id: "sane-pieusb:libusb:2:4", dpi: 3600, depth: .sixteen,
                         mode: .color, film: .colorPositive, area: frame, ir: true),
    deviceTypeHint: "slide scanner")))

// 빈 덤프 — 아무것도 추정하지 않는다
emit("media.empty", mediaText(SANEBackend.resolveMedia(
    dump: "",
    options: makeOptions(id: "sane-genesys:libusb:1:2", dpi: 3600, depth: .sixteen,
                         mode: .color, film: .colorNegative, area: frame, ir: false),
    deviceTypeHint: nil)))

// 필름 극성 4종
for ft in [FilmType.colorNegative, .colorPositive, .bwNegative, .bwPositive] {
    let m = SANEBackend.resolveMedia(
        dump: epson2Dump,
        options: makeOptions(id: "sane-epson2:libusb:1:5", dpi: 1200, depth: .sixteen,
                             mode: .color, film: ft, area: frame, ir: false),
        deviceTypeHint: "flatbed scanner")
    emit("polarity[" + ft.rawValue + "]", m.filmType ?? "<nil>")
}

// epson2 감마 2단 규칙 — private 이므로 resolveMedia 를 통해 확인한다.
let gammaABDump = """
    --mode Color [Color]
    --color-correction None|User defined [None]
    --gamma-correction Default|User defined [Default]
    --resolution 1200dpi [1200]
"""
let mAB = SANEBackend.resolveMedia(
    dump: gammaABDump,
    options: makeOptions(id: "sane-epson2:libusb:1:5", dpi: 1200, depth: .sixteen,
                         mode: .color, film: .colorNegative, area: frame, ir: false),
    deviceTypeHint: "flatbed scanner")
emit("gamma.AB", mAB.gammaCorrection ?? "<nil>")
emit("cc.none", mAB.colorCorrection ?? "<nil>")

let gammaDDump = """
    --mode Color [Color]
    --gamma-correction Default|User defined (Gamma=1.0)|User defined (Gamma=1.8) [Default]
    --resolution 1200dpi [1200]
"""
let mD = SANEBackend.resolveMedia(
    dump: gammaDDump,
    options: makeOptions(id: "sane-epson2:libusb:1:5", dpi: 1200, depth: .sixteen,
                         mode: .color, film: .colorNegative, area: frame, ir: false),
    deviceTypeHint: "flatbed scanner")
emit("gamma.D", mD.gammaCorrection ?? "<nil>")

// pickModeValue 도 private — mode 선택을 resolveMedia 로 확인한다.
let modeDump = """
    --mode Lineart|Gray|Color|Infrared [Color]
    --resolution 1200dpi [1200]
"""
for cm in [ColorMode.color, .gray] {
    let m = SANEBackend.resolveMedia(
        dump: modeDump,
        options: makeOptions(id: "sane-x:libusb:1:1", dpi: 1200, depth: .sixteen,
                             mode: cm, film: .colorNegative, area: frame, ir: false),
        deviceTypeHint: nil)
    emit("pick[" + cm.rawValue + "]", m.mode ?? "<nil>")
    emit("irPass[" + cm.rawValue + "]", m.irPassMode ?? "<nil>")
}

// =========================================================================
// sane/validate — exact-option-contract §8.2 거부 목록
// =========================================================================

func validateText(_ options: ScanOptions, _ media: SANEBackend.MediaSelection) -> String {
    do {
        try SANEBackend.validateExactOptions(options, media: media)
        return "ok"
    } catch let e as ScannerError {
        return e.errorDescription ?? "<nil>"
    } catch {
        return "unexpected"
    }
}

func mediaFor(_ dumpText: String, _ o: ScanOptions, _ hint: String?) -> SANEBackend.MediaSelection {
    return SANEBackend.resolveMedia(dump: dumpText, options: o, deviceTypeHint: hint)
}

func check(_ label: String, _ dumpText: String, _ o: ScanOptions, _ hint: String?) {
    emit("V[" + label + "]", validateText(o, mediaFor(dumpText, o, hint)))
}

let gFrame = ScanArea(originXMM: 0, originYMM: 0, widthMM: 36, heightMM: 24)

// 통과 케이스
check("ok.genesys", dump,
      makeOptions(id: "sane-genesys:libusb:1:2", dpi: 3600, depth: .sixteen, mode: .color,
                  film: .colorNegative, area: gFrame, ir: false), "film scanner")

// 해상도 거부
check("dpi.unsupported", dump,
      makeOptions(id: "sane-genesys:libusb:1:2", dpi: 2000, depth: .sixteen, mode: .color,
                  film: .colorNegative, area: gFrame, ir: false), "film scanner")

// preview + --preview 없음
let noPreviewDump = """
    --mode Color [Color]
    --depth 16 [16]
    --resolution 3600dpi [3600]
    -x 0..36mm [36]
    -y 0..24mm [24]
"""
check("preview.missing", noPreviewDump,
      makeOptions(id: "sane-x:libusb:1:1", dpi: 0, depth: .sixteen, mode: .color,
                  film: .colorNegative, area: gFrame, ir: false), nil)

// 심도 거부: 8-bit 고정 기기에 16-bit 요청
let fixed8Dump = """
    --mode Color [Color]
    --depth 8 [inactive]
    --resolution 3600dpi [3600]
    -x 0..36mm [36]
    -y 0..24mm [24]
"""
check("depth.fixedMismatch", fixed8Dump,
      makeOptions(id: "sane-x:libusb:1:1", dpi: 3600, depth: .sixteen, mode: .color,
                  film: .colorNegative, area: gFrame, ir: false), nil)
check("depth.fixedMatch", fixed8Dump,
      makeOptions(id: "sane-x:libusb:1:1", dpi: 3600, depth: .eight, mode: .color,
                  film: .colorNegative, area: gFrame, ir: false), nil)

// --depth 없음
let noDepthDump = """
    --mode Color [Color]
    --resolution 3600dpi [3600]
    -x 0..36mm [36]
    -y 0..24mm [24]
"""
check("depth.missing", noDepthDump,
      makeOptions(id: "sane-genesys:libusb:1:1", dpi: 3600, depth: .sixteen, mode: .color,
                  film: .colorNegative, area: gFrame, ir: false), nil)

// 색 모드: gray 요청인데 Color 만
let colorOnlyDump = """
    --mode Color [Color]
    --depth 16 [16]
    --resolution 3600dpi [3600]
    -x 0..36mm [36]
    -y 0..24mm [24]
"""
check("mode.grayMissing", colorOnlyDump,
      makeOptions(id: "sane-x:libusb:1:1", dpi: 3600, depth: .sixteen, mode: .gray,
                  film: .colorNegative, area: gFrame, ir: false), nil)

// --mode 없음 + 비전용 장치
let noModeDump = """
    --depth 16 [16]
    --resolution 3600dpi [3600]
    -x 0..36mm [36]
    -y 0..24mm [24]
"""
check("mode.noneNonDedicated", noModeDump,
      makeOptions(id: "sane-genesys:libusb:1:1", dpi: 3600, depth: .sixteen, mode: .color,
                  film: .colorNegative, area: gFrame, ir: false), nil)
check("mode.noneDedicatedGray", noModeDump,
      makeOptions(id: "sane-coolscan3:libusb:1:1", dpi: 3600, depth: .sixteen, mode: .gray,
                  film: .colorNegative, area: gFrame, ir: false), "film scanner")

// 반사 소스만
let reflectiveDump = """
    --mode Color [Color]
    --source Flatbed [Flatbed]
    --depth 16 [16]
    --resolution 3600dpi [3600]
    -x 0..36mm [36]
    -y 0..24mm [24]
"""
check("source.reflectiveOnly", reflectiveDump,
      makeOptions(id: "sane-x:libusb:1:1", dpi: 3600, depth: .sixteen, mode: .color,
                  film: .colorNegative, area: gFrame, ir: false), nil)

// pieusb + advance 없음
let pieusbNoAdvance = """
    --mode Color [Color]
    --depth 16 [16]
    --resolution 3600dpi [3600]
    -x 0..36mm [36]
    -y 0..24mm [24]
"""
check("pieusb.noAdvance", pieusbNoAdvance,
      makeOptions(id: "sane-pieusb:libusb:2:4", dpi: 3600, depth: .sixteen, mode: .color,
                  film: .colorPositive, area: gFrame, ir: false), "slide scanner")

// epson2 색/감마 보정 값 없음
let epsonNoNone = """
    --mode Color [Color]
    --color-correction Auto|User defined [Auto]
    --depth 16 [16]
    --resolution 3600dpi [3600]
    -x 0..36mm [36]
    -y 0..24mm [24]
"""
check("epson2.noColorNone", epsonNoNone,
      makeOptions(id: "sane-epson2:libusb:1:5", dpi: 3600, depth: .sixteen, mode: .color,
                  film: .colorNegative, area: gFrame, ir: false), nil)

let epsonNoGamma = """
    --mode Color [Color]
    --gamma-correction Default|Auto [Default]
    --depth 16 [16]
    --resolution 3600dpi [3600]
    -x 0..36mm [36]
    -y 0..24mm [24]
"""
check("epson2.noGamma", epsonNoGamma,
      makeOptions(id: "sane-epson2:libusb:1:5", dpi: 3600, depth: .sixteen, mode: .color,
                  film: .colorNegative, area: gFrame, ir: false), nil)

// 폭이 범위 밖
check("area.widthOutOfRange", dump,
      makeOptions(id: "sane-genesys:libusb:1:2", dpi: 3600, depth: .sixteen, mode: .color,
                  film: .colorNegative,
                  area: ScanArea(originXMM: 0, originYMM: 0, widthMM: 40, heightMM: 24),
                  ir: false), "film scanner")

// 원점 지정인데 -l/-t 없음
let noOriginDump = """
    --mode Color [Color]
    --depth 16 [16]
    --resolution 3600dpi [3600]
    -x 0..36mm [36]
    -y 0..24mm [24]
"""
check("area.originNoLT", noOriginDump,
      makeOptions(id: "sane-genesys:libusb:1:1", dpi: 3600, depth: .sixteen, mode: .color,
                  film: .colorNegative,
                  area: ScanArea(originXMM: 2, originYMM: 0, widthMM: 34, heightMM: 24),
                  ir: false), nil)

// 밝기: 0 은 범위 없어도 통과, 5 는 거부
var brightZero = makeOptions(id: "sane-genesys:libusb:1:2", dpi: 3600, depth: .sixteen,
                             mode: .color, film: .colorNegative, area: gFrame, ir: false)
brightZero.brightnessAdjustment = 0
check("bright.zeroNoRange", dump, brightZero, "film scanner")

var brightFive = brightZero
brightFive.brightnessAdjustment = 5
check("bright.fiveNoRange", dump, brightFive, "film scanner")

// 단일 노출시간
var exp = makeOptions(id: "sane-genesys:libusb:1:2", dpi: 3600, depth: .sixteen,
                      mode: .color, film: .colorNegative, area: gFrame, ir: false)
exp.hardwareExposureTime = 11000
check("exposure.noOption", dump, exp, "film scanner")

// 다중 노출: 8-bit 거부
var mexp8 = makeOptions(id: "sane-genesys:libusb:1:2", dpi: 3600, depth: .eight,
                        mode: .color, film: .colorNegative, area: gFrame, ir: false)
mexp8.multiExposureEnabled = true
check("mexp.eightBit", dump, mexp8, "film scanner")

// 다중 노출: 계획 미지원
var mexpPlan = makeOptions(id: "sane-genesys:libusb:1:2", dpi: 3600, depth: .sixteen,
                           mode: .color, film: .colorNegative, area: gFrame, ir: false)
mexpPlan.multiExposureEnabled = true
check("mexp.noPlan", dump, mexpPlan, "film scanner")

// IR 요청인데 IR 소스 없음
check("ir.none", colorOnlyDump,
      makeOptions(id: "sane-x:libusb:1:1", dpi: 3600, depth: .sixteen, mode: .color,
                  film: .colorNegative, area: gFrame, ir: true), nil)

// IR 요청 + IR 소스 있음 → 통과
check("ir.ok", dump,
      makeOptions(id: "sane-genesys:libusb:1:2", dpi: 3600, depth: .sixteen, mode: .color,
                  film: .colorNegative, area: gFrame, ir: true), "film scanner")

// =========================================================================
// sane/args — makeScanimageArgs (배열 순서까지 비교)
// =========================================================================

let backendForArgs = SANEBackend(scanimagePath: "/nonexistent/scanimage")

func argsText(_ dev: String, _ o: ScanOptions, _ m: SANEBackend.MediaSelection,
              _ pass: SANEBackend.AcquisitionPass, _ bright: Int?) -> String {
    return backendForArgs.makeScanimageArgs(
        devname: dev, options: o, media: m, pass: pass, brightness: bright
    ).joined(separator: " ")
}

func acheck(_ label: String, _ dumpText: String, _ o: ScanOptions, _ hint: String?,
            _ dev: String, _ pass: SANEBackend.AcquisitionPass, _ bright: Int?) {
    let m = SANEBackend.resolveMedia(dump: dumpText, options: o, deviceTypeHint: hint)
    emit("A[" + label + "]", argsText(dev, o, m, pass, bright))
}

let aFrame = ScanArea(originXMM: 0, originYMM: 0, widthMM: 36, heightMM: 24)

acheck("genesys.main", dump,
       makeOptions(id: "sane-genesys:libusb:1:2", dpi: 3600, depth: .sixteen, mode: .color,
                   film: .colorNegative, area: aFrame, ir: false),
       "film scanner", "genesys:libusb:001:002", .main, nil)

acheck("genesys.ir", dump,
       makeOptions(id: "sane-genesys:libusb:1:2", dpi: 3600, depth: .sixteen, mode: .color,
                   film: .colorNegative, area: aFrame, ir: true),
       "film scanner", "genesys:libusb:001:002", .infrared, nil)

acheck("genesys.preview", dump,
       makeOptions(id: "sane-genesys:libusb:1:2", dpi: 0, depth: .sixteen, mode: .color,
                   film: .colorNegative, area: aFrame, ir: false),
       "film scanner", "genesys:libusb:001:002", .main, nil)

// 8-bit 이면 밝기 옵션이 살아 있다 → override 가 실린다
var brightOpts = makeOptions(id: "sane-genesys:libusb:1:2", dpi: 1200, depth: .eight,
                             mode: .color, film: .colorNegative, area: aFrame, ir: false)
acheck("genesys.brightOverride", dump, brightOpts, "film scanner",
       "genesys:libusb:001:002", .main, 7)

brightOpts.brightnessAdjustment = -12.5
acheck("genesys.brightDouble", dump, brightOpts, "film scanner",
       "genesys:libusb:001:002", .main, nil)

// epson2 — 색/감마 보정 + film-type + 높이 정렬
let epson2ArgsDump = """
    --mode Lineart|Gray|Color [Color]
    --source Flatbed|Transparency Unit|TPU8x10 [Flatbed]
    --film-type Positive Film|Negative Film [Positive Film]
    --color-correction None|User defined [None]
    --gamma-correction Default|User defined (Gamma=1.0)|User defined (Gamma=1.8) [Default]
    --resolution 50..12800dpi [50]
    --depth 8|16 [16]
    -l 0..215.9mm [0]
    -t 0..297.18mm [0]
    -x 0..215.9mm [215.9]
    -y 0..297.18mm [297.18]
"""
acheck("epson2.main", epson2ArgsDump,
       makeOptions(id: "sane-epson2:libusb:1:5", dpi: 1200, depth: .sixteen, mode: .color,
                   film: .colorNegative,
                   area: ScanArea(originXMM: 0, originYMM: 0, widthMM: 36, heightMM: 23.5),
                   ir: false),
       "flatbed scanner", "epson2:libusb:001:005", .main, nil)

// coolscan3 — --mode 없음, --negative=no, pel 지오메트리
let coolscan3ArgsDump = """
    --depth 8|14 [8]
    --negative[=(yes|no)] [no]
    --resolution 4000dpi [4000]
    -x 0..6000pel [6000]
    -y 0..6000pel [6000]
"""
acheck("coolscan3.main", coolscan3ArgsDump,
       makeOptions(id: "sane-coolscan3:libusb:1:2", dpi: 4000, depth: .sixteen, mode: .color,
                   film: .colorNegative, area: aFrame, ir: false),
       "film scanner", "coolscan3:usb:libusb:001:002", .main, nil)

// pieusb — --advance=no
let pieusbArgsDump = """
    --mode Color|RGBI [Color]
    --advance[=(yes|no)] [yes]
    --resolution 3600dpi [3600]
    -x 0..36mm [36]
    -y 0..24mm [24]
    --depth 16 [16]
"""
acheck("pieusb.main", pieusbArgsDump,
       makeOptions(id: "sane-pieusb:libusb:2:4", dpi: 3600, depth: .sixteen, mode: .color,
                   film: .colorPositive, area: aFrame, ir: false),
       "slide scanner", "pieusb:libusb:002:004", .main, nil)

// 코너 pel 지오메트리
let cornerDump = """
    --mode Color [Color]
    --depth 16 [16]
    --resolution 4000dpi [4000]
    --tl-x 0..6000pel [0]
    --tl-y 0..6000pel [0]
    --br-x 0..6000pel [6000]
    --br-y 0..6000pel [6000]
"""
acheck("corner.main", cornerDump,
       makeOptions(id: "sane-x:libusb:1:1", dpi: 4000, depth: .sixteen, mode: .color,
                   film: .colorNegative, area: aFrame, ir: false),
       nil, "x:libusb:001:001", .main, nil)

// 노출 시간
var expOpts = makeOptions(id: "sane-x:libusb:1:1", dpi: 3600, depth: .sixteen, mode: .color,
                          film: .colorNegative, area: aFrame, ir: false)
expOpts.hardwareExposureTime = 14000
let expDump = """
    --mode Color [Color]
    --depth 16 [16]
    --resolution 3600dpi [3600]
    --scan-exposure-time 0..65535 [11000]
    -x 0..36mm [36]
    -y 0..24mm [24]
"""
acheck("exposure.main", expDump, expOpts, nil, "x:libusb:001:001", .main, nil)

// --- capability 재조회 / 덤프 재사용 판정 -----------------------------------

let reuseCases: [(String, String, String)] = [
    ("genesys.singleTP", "    --source Transparency Adapter [Transparency Adapter]\n", "genesys"),
    ("genesys.tpPlusIR", "    --source Transparency Adapter|Transparency Adapter Infrared [Transparency Adapter]\n", "genesys"),
    ("genesys.flatbedToo", "    --source Flatbed|Transparency Adapter [Flatbed]\n", "genesys"),
    ("epson2.singleTP", "    --source Transparency Unit [Transparency Unit]\n", "epson2"),
    ("genesys.reflectiveOnly", "    --source Flatbed [Flatbed]\n", "genesys"),
]
for (label, dumpText, backend) in reuseCases {
    emit("reuse[" + label + "]",
         String(SANEBackend.canReuseSinglePassOptionsDump(dumpText, backend: backend)))
}

let redumpCases: [(String, String, String)] = [
    ("genesys", "    --source Flatbed|Transparency Adapter [Flatbed]\n    --mode Color|Gray [Color]\n    --depth 8|16 [16]\n", "genesys:libusb:001:002"),
    ("epson2.inactiveDepth", "    --source Flatbed|Transparency Unit [Flatbed]\n    --mode Lineart|Gray|Color [Lineart]\n    --depth 8|16 [inactive]\n    --color-correction None|User defined [None]\n    --gamma-correction Default|User defined (Gamma=1.0) [Default]\n", "epson2:libusb:001:005"),
    ("noop", "    --mode Color [Color]\n    --depth 16 [16]\n", "x:libusb:1:1"),
    ("coolscan3", "    --depth 8|14 [8]\n", "coolscan3:usb:libusb:001:002"),
]
for (label, dumpText, dev) in redumpCases {
    let a = SANEBackend.capabilityRedumpArguments(baseDump: dumpText, devname: dev)
    emit("redump[" + label + "]", a.map { $0.joined(separator: " ") } ?? "<nil>")
}

// =========================================================================
// process/progress — 진행률 파싱과 stderr 분류 (순수 부분만)
// =========================================================================

let progressSamples: [(String, String)] = [
    ("empty", ""),
    ("one", "Progress: 12.3%\n"),
    ("comma", "Progress: 45,6%\n"),
    ("many", "Progress: 1%\nProgress: 50%\nProgress: 99.9%\n"),
    ("paren", "Progress: (34/512)\n"),
    ("mixed", "Progress: (1/10)\nProgress: 25%\nProgress: (5/10)\n"),
    ("noColon", "progress 77%\n"),
    ("upper", "PROGRESS: 5%\n"),
    ("clamp", "Progress: 150%\n"),
    ("noise", "scanimage: rounded value of br-y from 23.5 to 24\nProgress: 3%\n"),
    ("truncated", "Progr"),
    ("threeDigits", "Progress: 100%\n"),
]
for (label, text) in progressSamples {
    emit("prog.count[" + label + "]", String(SANEBackend.scanimageProgressRecordCount(in: text)))
    emit("prog.frac[" + label + "]",
         SANEBackend.scanimageProgressFraction(in: text).map { String($0) } ?? "<nil>")
}

let stderrSamples: [(String, String)] = [
    ("empty", ""),
    ("invalidArg", "scanimage: open of device x failed: Invalid argument"),
    ("busy", "scanimage: open of device x failed: Device busy"),
    ("noSuch", "No such device"),
    ("io", "I/O error"),
    ("denied", "Access to resource has been denied"),
    ("resourceBusy", "Resource busy"),
    ("notConnected", "Scanner not connected"),
    ("rounded", "scanimage: rounded value of resolution from 2000 to 2400"),
    ("ROUNDED", "ROUNDED VALUE OF x"),
    ("other", "something else entirely"),
]
for (label, text) in stderrSamples {
    emit("stale[" + label + "]", String(SANEBackend.isStaleDeviceError(text)))
    emit("inexact[" + label + "]", String(SANEBackend.containsInexactOptionWarning(text)))
}

// =========================================================================
// imaging/align — 정렬. 전부 Float 이므로 비트 패턴으로 비교한다.
// 근거: windows_docs/04-imaging/numerical-parity.md §4
// =========================================================================

/// Float 는 비트 패턴으로 비교한다. 십진 표기는 반올림으로 차이를 숨긴다.
func fbits(_ f: Float) -> String { String(format: "%08x", f.bitPattern) }

/// C++ 짝과 **비트 단위로 같은** 입력을 만든다. 32비트 무부호 산술은
/// 두 언어에서 동일하게 정의돼 있다(Swift &* / &+, C++ unsigned 모듈러).
func hash32(_ x0: UInt32) -> UInt32 {
    var x = x0
    x ^= x >> 16
    x = x &* 0x7feb_352d
    x ^= x >> 15
    x = x &* 0x846c_a68b
    x ^= x >> 16
    return x
}

/// 8×8 블록 구조(정렬이 물릴 거친 신호) + 픽셀 단위 미세 변화.
func sceneChannel(_ x: Int, _ y: Int, _ channel: Int, _ seed: UInt32) -> Float {
    let u = UInt32(truncatingIfNeeded: x + 1024)
    let v = UInt32(truncatingIfNeeded: y + 1024)
    let h = hash32((u >> 3) &* 2_654_435_761 &+ (v >> 3) &* 40503
        &+ UInt32(truncatingIfNeeded: channel) &* 7 &+ seed)
    let blocky = Float(h >> 16) / 65535.0
    let g = hash32(u &* 374_761_393 &+ v &* 668_265_263 &+ seed
        &+ UInt32(truncatingIfNeeded: channel))
    let fine = Float(g >> 24) / 255.0
    return blocky * 0.8 + fine * 0.2
}

/// 정렬되지 않는 노이즈. 목적지 좌표로 계산하므로 시프트를 따라가지 않는다.
func jitterDelta(_ x: Int, _ y: Int, _ channel: Int, _ jitterSeed: UInt32) -> Float {
    let j = hash32(UInt32(truncatingIfNeeded: y * 8191 + x + channel * 131) &+ jitterSeed)
    return (Float(j >> 22) / 1023.0 - 0.5) * 0.05
}

func makeImage(_ width: Int, _ height: Int, _ seed: UInt32,
               _ shiftX: Int, _ shiftY: Int, _ jitterSeed: UInt32) -> [Float] {
    var out = [Float](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            for c in 0..<3 {
                var value = sceneChannel(x + shiftX, y + shiftY, c, seed)
                if jitterSeed != 0 { value += jitterDelta(x, y, c, jitterSeed) }
                out[i + c] = value
            }
            out[i + 3] = 1
        }
    }
    return out
}

func makeFlatImage(_ width: Int, _ height: Int, _ value: Float) -> [Float] {
    var out = [Float](repeating: 0, count: width * height * 4)
    for p in 0..<(width * height) {
        let i = p * 4
        out[i] = value
        out[i + 1] = value
        out[i + 2] = value
        out[i + 3] = 1
    }
    return out
}

let trustSamples: [(String, Float)] = [
    ("neg", -0.5), ("zero", 0.0), ("lo", 0.006),
    ("loJust", 0.0061), ("loMid", 0.02), ("loEdge", 0.035),
    ("loOver", 0.0351), ("mid", 0.5), ("hiEdge", 0.90),
    ("hiMid", 0.94), ("hiTop", 0.985), ("hiJust", 0.9849),
    ("one", 1.0), ("over", 1.5),
]
for (label, v) in trustSamples {
    emit("align.trust[" + label + "]", fbits(SANEBackend.exposureTrustWeight(v)))
}

let mixSamples: [(String, Float, Float, Float)] = [
    ("t0", 0.25, 0.75, 0.0), ("t1", 0.25, 0.75, 1.0),
    ("half", 0.25, 0.75, 0.5), ("under", 0.25, 0.75, -0.3),
    ("over", 0.25, 0.75, 1.7), ("third", 0.1, 0.9, Float(1.0) / Float(3.0)),
    ("desc", 0.9, 0.1, 0.37),
]
for (label, a, b, t) in mixSamples {
    emit("align.mix[" + label + "]", fbits(SANEBackend.mix(a, b, t)))
}

let stepSamples: [(String, Float, Float, Float)] = [
    ("below", 0.82, 0.97, 0.5), ("e0", 0.82, 0.97, 0.82),
    ("mid", 0.82, 0.97, 0.9), ("e1", 0.82, 0.97, 0.97),
    ("above", 0.82, 0.97, 1.0), ("lowBand", 0.010, 0.045, 0.02),
    ("lowE0", 0.010, 0.045, 0.01), ("equalLt", 0.5, 0.5, 0.4),
    ("equalEq", 0.5, 0.5, 0.5), ("equalGt", 0.5, 0.5, 0.6),
    ("reversed", 0.97, 0.82, 0.9),
]
for (label, e0, e1, x) in stepSamples {
    emit("align.step[" + label + "]", fbits(SANEBackend.smoothstep(edge0: e0, edge1: e1, x: x)))
}

let srcSamples: [(String, Int, Int, Int, Int, Int)] = [
    ("inside", 4, 3, 1, 0, 0), ("shift", 4, 3, 2, -2, -1), ("left", 0, 0, 0, -1, 0),
    ("top", 0, 0, 0, 0, -1), ("right", 7, 0, 0, 1, 0), ("bottom", 0, 5, 0, 0, 1),
    ("corner", 7, 5, 2, 0, 0),
]
for (label, x, y, ch, ox, oy) in srcSamples {
    let i = SANEBackend.alignedSourceIndex(x: x, y: y, channel: ch,
                                           offset: (x: ox, y: oy), width: 8, height: 6)
    emit("align.srcidx[" + label + "]", i.map(String.init) ?? "<nil>")
}

// estimateIntegerOffset — 정수 결과. 한 픽셀만 달라도 병합이 전부 달라진다.
let alignCases: [(String, Int, Int, UInt32, Int, Int, UInt32)] = [
    ("same", 80, 64, 7, 0, 0, 0),          // 개선 없음 → 0.85 게이트
    ("shiftX2", 80, 64, 7, 2, 0, 0),
    ("shiftY3", 80, 64, 7, 0, 3, 0),
    ("shiftXY", 80, 64, 7, -3, 5, 0),
    ("jitter", 80, 64, 7, 1, -2, 1234),    // 정렬되지 않는 노이즈 포함
    ("factor2", 192, 192, 11, 4, -6, 0),   // min(w,h)/96 = 2 → factor 2
    ("narrowW", 6, 40, 3, 1, 1, 0),        // dw <= 6 → (0,0)
    ("shortH", 40, 5, 3, 1, 1, 0),         // dh <= 6 → (0,0)
]
for (label, width, height, seed, shiftX, shiftY, jitter) in alignCases {
    let reference = makeImage(width, height, seed, 0, 0, 0)
    let sample = makeImage(width, height, seed, shiftX, shiftY, jitter)
    let o = SANEBackend.estimateIntegerOffset(reference: reference, sample: sample,
                                              width: width, height: height)
    emit("align.offset[" + label + "]", String(o.x) + "," + String(o.y))
}

do {  // 평탄한 이미지 → 텍스처 가드가 (0,0) 으로 보낸다
    let flat = makeFlatImage(80, 64, 0.5)
    let shifted = makeImage(80, 64, 7, 2, 2, 0)
    let o = SANEBackend.estimateIntegerOffset(reference: flat, sample: shifted,
                                              width: 80, height: 64)
    emit("align.offset[flatRef]", String(o.x) + "," + String(o.y))
}

// accumulateAligned — 누적 순서까지 같아야 한다.
for (label, ox, oy) in [("zero", 0, 0), ("pos", 2, 1), ("neg", -3, -2), ("outX", 9, 0)] {
    let w = 8, h = 6
    let sample = makeImage(w, h, 5, 0, 0, 0)
    var accumulator = [Float](repeating: 0, count: w * h * 4)
    var counts = [Float](repeating: 0, count: w * h)
    SANEBackend.accumulateAligned(sample, offset: (x: ox, y: oy), width: w, height: h,
                                  into: &accumulator, counts: &counts)

    emit("align.accum[" + label + "].counts", counts.map(fbits).joined(separator: ","))

    var total: Float = 0  // 인덱스 순 Float 누적 — 순서가 결과를 바꾼다
    for v in accumulator { total += v }
    emit("align.accum[" + label + "].sum", fbits(total))

    emit("align.accum[" + label + "].head",
         accumulator.prefix(12).map(fbits).joined(separator: ","))
}

// =========================================================================
// imaging/merge — 다중 노출 병합. **P0 비트 동일 대상이다.**
//
// Swift 쪽 진입점이 [CIImage] 를 받으므로 합성 float 를 CIImage 로 감싼다.
// 그 왕복(bitmapData → renderRGBAf)이 **비트 단위 항등**임을 먼저 실측했다:
// Y 뒤집힘 없음, 1 초과·음수 값도 그대로 보존.
// 이것이 성립하지 않으면 아래 비교는 무의미하다.
// =========================================================================

/// 노출 패스 하나. 신뢰 가중치 5분기를 **전부** 지나도록 값 대역을 흩는다.
///
/// 대역은 목적지 좌표로 정하고 장면 세부만 시프트한다 — 픽셀별 raw 대역을
/// 고정한 채 정렬 신호만 움직이기 위해서다.
func makeExposureImage(_ width: Int, _ height: Int, _ seed: UInt32,
                       _ pass: Int, _ shiftX: Int, _ shiftY: Int) -> [Float] {
    var out = [Float](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            for c in 0..<3 {
                let s = sceneChannel(x + shiftX, y + shiftY, c,
                                     seed &+ UInt32(truncatingIfNeeded: pass) &* 101)
                let band = hash32(UInt32(truncatingIfNeeded: (y * width + x) * 3 + c) &+ seed) % 5
                var v: Float = 0
                switch band {
                case 0: v = 0.99 + s * 0.01     // 클리핑 (>= 0.985)
                case 1: v = 0.90 + s * 0.08     // 클리핑 경계
                case 2: v = s * 0.006           // 암부 (<= 0.006)
                case 3: v = 0.006 + s * 0.029   // 암부 경계
                default: v = 0.1 + s * 0.7      // 정상
                }
                out[i + c] = v
            }
            out[i + 3] = 1
        }
    }
    return out
}

let linearSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!

func asCIImage(_ pixels: [Float], _ width: Int, _ height: Int) -> CIImage {
    CIImage(
        bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
        bytesPerRow: width * 4 * MemoryLayout<Float>.size,
        size: CGSize(width: width, height: height),
        format: .RGBAf,
        colorSpace: linearSpace
    )
}

let refSamples: [(String, [Int])] = [
    ("empty", []),
    ("single", [14000]),
    ("plan3", [11000, 14000, 30000]),
    ("dupes", [11000, 11000, 14000, 30000]),        // 중복 제거 후 3개 → 14000
    ("reversed", [30000, 14000, 11000]),
    ("allSame", [5, 5, 5]),
    ("even4", [1, 2, 3, 4]),                        // 짝수 → 위쪽 중앙
    ("even6", [1, 2, 3, 4, 5, 6]),
    ("samples2", [11000, 11000, 14000, 14000, 30000, 30000]),
]
for (label, times) in refSamples {
    let r = SANEBackend.referenceExposureTime(from: times)
    emit("merge.ref[" + label + "]", r.map(String.init) ?? "<nil>")
}

let mergeCases: [(String, Int, Int, UInt32, [Int], [(Int, Int)], Bool)] = [
    ("basic", 16, 12, 21, [11000, 14000, 30000], [(0, 0), (0, 0), (0, 0)], true),
    ("shifted", 40, 30, 33, [11000, 14000, 30000], [(0, 0), (2, -1), (-1, 3)], false),
    ("samples2", 16, 12, 21, [11000, 11000, 14000, 14000, 30000, 30000],
     [(0, 0), (1, 0), (0, 0), (0, 1), (0, 0), (-1, 0)], false),
    ("singlePass", 16, 12, 21, [14000], [(0, 0)], true),
    ("noShort", 16, 12, 21, [14000, 30000], [(0, 0), (0, 0)], false),
    ("noLong", 16, 12, 21, [11000, 14000], [(0, 0), (0, 0)], false),
]

for (label, width, height, seed, exposures, shifts, dumpFloat) in mergeCases {
    let images = (0..<exposures.count).map { p in
        asCIImage(makeExposureImage(width, height, seed, p, shifts[p].0, shifts[p].1),
                  width, height)
    }

    if dumpFloat {
        let reference = SANEBackend.referenceExposureTime(from: exposures) ?? 0
        let f = try! SANEBackend.alignedExposureNormalizedRGBAf(
            images, exposureTimes: exposures, referenceExposure: reference,
            colorSpace: linearSpace)
        emit("merge.float[" + label + "].failure", "<nil>")
        for y in 0..<height {
            var row = ""
            for x in 0..<(width * 4) {
                if x != 0 { row += "," }
                row += fbits(f.pixels[y * width * 4 + x])
            }
            emit("merge.float[" + label + "].row" + String(y), row)
        }
    }

    let m = try! SANEBackend.mergeHardwareExposureBitmap(images, exposureTimes: exposures)
    emit("merge.u16[" + label + "].failure", "<nil>")
    for y in 0..<height {
        var row = ""
        for x in 0..<(width * 3) {
            if x != 0 { row += "," }
            row += String(m.pixels[y * width * 3 + x])
        }
        emit("merge.u16[" + label + "].row" + String(y), row)
    }
}

do {  // 평균 경로 — production 에서는 쓰이지 않지만 테스트가 지난다.
    let w = 16, h = 12
    let images = (0..<3).map { p in
        asCIImage(makeExposureImage(w, h, 21, p, p, -p), w, h)
    }
    let a = try! SANEBackend.averageMultiSampleBitmap(images)
    emit("merge.avg.failure", "<nil>")
    for y in 0..<h {
        var row = ""
        for x in 0..<(w * 3) {
            if x != 0 { row += "," }
            row += String(a.pixels[y * w * 3 + x])
        }
        emit("merge.avg.row" + String(y), row)
    }
}

// =========================================================================
// imaging/tiff_io — macOS ImageIO 와의 **상호운용**.
//
// 파일 바이트가 아니라 **디코드된 픽셀**을 비교한다. 바이트 순서(II vs MM)는
// 달라도 되고 실제로 다르다 — 호스트가 libtiff/WIC 로 읽으므로 투명하다.
//
//   tiff.roundtrip.*  Swift 가 쓴 파일 → C++ 이 읽는다
//   tiff.cross.*      C++ 이 쓴 파일   → Swift 가 읽는다
// =========================================================================

if let tmp = ProcessInfo.processInfo.environment["PARITY_TMP"],
   ProcessInfo.processInfo.environment["PARITY_TIFF"] != nil {
    let w = 6, h = 4
    // 정규화의 경계와 그 이웃. 0/65535 는 양끝, 32767/32768 은 0.5 근처다.
    let marks: [UInt16] = [0, 1, 2, 255, 256, 32767, 32768, 65534, 65535]
    var pixels = [UInt16](repeating: 0, count: w * h * 3)
    for y in 0..<h {
        for x in 0..<w {
            for c in 0..<3 {
                // 행마다 패턴을 민다. **모든 행이 같으면 위아래 뒤집힘도
                // 행 stride 오류도 잡지 못한다.**
                pixels[(y * w + x) * 3 + c] = marks[(x * 3 + c + y * 5) % marks.count]
            }
        }
    }

    let base = URL(fileURLWithPath: tmp)
    let cppFile = base.appendingPathComponent("cpp_write.tiff")
    let swiftFile = base.appendingPathComponent("swift_write.tiff")

    /// TIFF 를 읽어 RGBA float 로. C++ loadScannerTIFF 와 같은 자리다.
    func loadFloats(_ url: URL) -> [Float]? {
        guard let image = TIFFLoader.loadScannerTIFF(url) else { return nil }
        let extent = image.extent.integral
        let context = CIContext(options: [
            .workingColorSpace: linearSpace,
            .outputColorSpace: linearSpace,
        ])
        return SANEBackend.renderRGBAf(image.cropped(to: extent),
                                       width: Int(extent.width), height: Int(extent.height),
                                       context: context, colorSpace: linearSpace)
    }

    func emitRows(_ prefix: String, _ floats: [Float]) {
        for y in 0..<h {
            var row = ""
            for x in 0..<(w * 4) {
                if x != 0 { row += "," }
                row += fbits(floats[y * w * 4 + x])
            }
            emit(prefix + ".row" + String(y), row)
        }
    }

    // C++ 이 libtiff 로 쓴 파일을 macOS ImageIO 로 읽는다.
    // (스크립트가 cpp_dump 를 먼저 한 번 돌려 이 파일을 만들어 둔다.)
    emit("tiff.cross.wrote", "true")
    let crossed = loadFloats(cppFile)
    emit("tiff.cross.loaded", crossed != nil ? "true" : "false")
    if let crossed {
        emit("tiff.cross.size", String(w) + "x" + String(h))
        emitRows("tiff.cross", crossed)
    }

    // 우리가 ImageIO 로 쓰고 우리가 읽는다. C++ 은 이 **같은 파일**을 읽는다.
    try? FileManager.default.removeItem(at: swiftFile)
    try! SANEBackend.writeRGB16TIFF(pixels, width: w, height: h, to: swiftFile)
    let mine = loadFloats(swiftFile)
    emit("tiff.roundtrip.loaded", mine != nil ? "true" : "false")
    if let mine {
        emit("tiff.roundtrip.size", String(w) + "x" + String(h))
        emitRows("tiff.roundtrip", mine)
    }

    // C++ 이 쓴 파일의 태그. **ICC 프로파일이 붙으면 본체가 감마 도메인으로
    // 읽어 색이 무너진다.** Swift 쪽은 C++ 이 낸 값을 그대로 기대값으로 적는다 —
    // 여기 있는 문자열이 곧 "우리가 써야 하는 태그"의 명세다.
    emit("tiff.cross.tags",
         "bps=16 spp=3 photo=2 planar=1 pages=1 icc=0 transfer=0")
}

// =========================================================================
// wire/request — 1단계 검증. **가드 순서와 문구가 계약이다.**
//
// 11개 중 9번(outputPath)만 플랫폼별로 갈린다. C++ 쪽은 여기와 같은 POSIX
// 정책으로 돌려 나머지 10개를 끝까지 대조한다.
// =========================================================================

func makeRequest(
    protocolVersion: Int = 2,
    deviceID: String = "genesys:libusb:001:002",
    resolutionDPI: Int = 3600,
    bitDepth: Int = 16,
    colorMode: String = "color",
    filmType: String = "colorNegative",
    preview: Bool = false,
    multiExposure: Bool = false,
    infrared: Bool = false,
    brightnessAdjustment: Double? = nil,
    contrastAdjustment: Double? = nil,
    scanArea: ScanArea = ScanArea(originXMM: 0, originYMM: 0, widthMM: 36, heightMM: 24),
    hardwareExposureTime: Int? = nil,
    outputRawTIFF: Bool = true,
    capabilityToken: String? = nil,
    outputPath: String = "/tmp/negaflow/frame.tiff"
) -> PluginScanRequestV2 {
    PluginScanRequestV2(
        protocolVersion: protocolVersion,
        requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        deviceID: deviceID,
        resolutionDPI: resolutionDPI,
        bitDepth: bitDepth,
        colorMode: colorMode,
        filmType: filmType,
        preview: preview,
        multiExposure: multiExposure,
        infrared: infrared,
        brightnessAdjustment: brightnessAdjustment,
        contrastAdjustment: contrastAdjustment,
        scanArea: scanArea,
        hardwareExposureTime: hardwareExposureTime,
        outputRawTIFF: outputRawTIFF,
        capabilityToken: capabilityToken,
        outputPath: outputPath
    )
}

let requestCases: [(String, PluginScanRequestV2)] = [
    ("ok", makeRequest()),
    ("v1", makeRequest(protocolVersion: 1)),
    ("v3", makeRequest(protocolVersion: 3)),
    ("emptyDevice", makeRequest(deviceID: "")),
    ("blankDevice", makeRequest(deviceID: "   \t ")),
    ("depth12", makeRequest(bitDepth: 12)),
    ("depth0", makeRequest(bitDepth: 0)),
    ("depth8", makeRequest(bitDepth: 8)),
    ("modeLineart", makeRequest(colorMode: "lineart")),
    ("modeInfrared", makeRequest(colorMode: "infrared")),
    ("modeBogus", makeRequest(colorMode: "sepia")),
    ("modeGray", makeRequest(colorMode: "gray")),
    ("filmBogus", makeRequest(filmType: "slide")),
    ("filmBwPositive", makeRequest(filmType: "bwPositive")),
    ("areaNegOrigin", makeRequest(scanArea: ScanArea(originXMM: -1, originYMM: 0, widthMM: 36, heightMM: 24))),
    ("areaZeroWidth", makeRequest(scanArea: ScanArea(originXMM: 0, originYMM: 0, widthMM: 0, heightMM: 24))),
    ("areaNegHeight", makeRequest(scanArea: ScanArea(originXMM: 0, originYMM: 0, widthMM: 36, heightMM: -5))),
    ("expZero", makeRequest(hardwareExposureTime: 0)),
    ("expNeg", makeRequest(hardwareExposureTime: -1)),
    ("expOk", makeRequest(hardwareExposureTime: 14000)),
    ("brightOk", makeRequest(brightnessAdjustment: 12.5)),
    ("pathRelative", makeRequest(outputPath: "tmp/frame.tiff")),
    ("pathDotDot", makeRequest(outputPath: "/tmp/../frame.tiff")),
    ("pathDot", makeRequest(outputPath: "/tmp/./frame.tiff")),
    ("pathDouble", makeRequest(outputPath: "/tmp//frame.tiff")),
    ("pathTrailing", makeRequest(outputPath: "/tmp/frame/")),
    ("pathEmpty", makeRequest(outputPath: "")),
    // **macOS 는 경로 탈출을 막지 못한다.** 실측으로 확인했고 파리티가 고정한다.
    ("pathEscape", makeRequest(outputPath: "/tmp/a/../../../etc/passwd")),
    ("pathRoot", makeRequest(outputPath: "/")),
    ("pathDoubleLead", makeRequest(outputPath: "//tmp/frame.tiff")),
    ("tokenOk", makeRequest(capabilityToken: String(repeating: "a", count: 1024))),
    ("tokenLimit", makeRequest(capabilityToken: String(repeating: "a", count: 1_048_576))),
    ("tokenOver", makeRequest(capabilityToken: String(repeating: "a", count: 1_048_577))),
    ("previewOk", makeRequest(resolutionDPI: 0, preview: true, outputRawTIFF: false)),
    ("previewDPI", makeRequest(resolutionDPI: 300, preview: true, outputRawTIFF: false)),
    ("previewIR", makeRequest(resolutionDPI: 0, preview: true, infrared: true, outputRawTIFF: false)),
    ("previewRaw", makeRequest(resolutionDPI: 0, preview: true, outputRawTIFF: true)),
    ("fullZeroDPI", makeRequest(resolutionDPI: 0)),
    ("fullNoRaw", makeRequest(outputRawTIFF: false)),
    ("fullMultiPlusExp", makeRequest(multiExposure: true, hardwareExposureTime: 14000)),
    ("fullMultiOnly", makeRequest(multiExposure: true)),
    // 여러 조건이 동시에 틀리면 **먼저 걸리는 것**이 나와야 한다.
    ("depthBeforeMode", makeRequest(bitDepth: 12, colorMode: "sepia")),
    ("modeBeforeFilm", makeRequest(colorMode: "sepia", filmType: "slide")),
    ("areaBeforePath", makeRequest(scanArea: ScanArea(originXMM: 0, originYMM: 0, widthMM: 0, heightMM: 24), outputPath: "relative.tiff")),
    ("pathBeforeToken", makeRequest(capabilityToken: String(repeating: "a", count: 1_048_577), outputPath: "relative.tiff")),
]

for (label, request) in requestCases {
    do {
        _ = try request.validatedOptions()
        emit("req[" + label + "]", "<ok>")
    } catch let error as ScannerError {
        emit("req[" + label + "]", error.message)
    } catch {
        emit("req[" + label + "]", "<unexpected>")
    }
}

// =========================================================================
// wire/json + wire/event — **키를 정렬해 바이트로 비교한다.**
//
// JSONEncoder 의 키 순서는 해시 기반이라 안정적이지 않다(wire-contract §4.2.3).
// 그래서 여기서만 .sortedKeys 를 건다. **실제 wire 출력은 정렬하지 않는다.**
// 정렬하면 호스트에 나가는 바이트가 바뀌고 그것은 wire 변경이다.
// =========================================================================

let sortedEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys]
    return e
}()

func dumpSorted<T: Encodable>(_ key: String, _ value: T) {
    guard let data = try? sortedEncoder.encode(value),
          let text = String(data: data, encoding: .utf8) else {
        emit(key, "<encode failed>")
        return
    }
    emit(key, text)
}

let parityRequestID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

// ① 옵셔널이 전부 비었을 때 — 키가 4개만 나와야 한다.
dumpSorted("json.event[bare]",
           PluginScanEventV2(type: "started", requestID: parityRequestID, sequence: 0))

// ② 진행률.
dumpSorted("json.event[progress]",
           PluginScanEventV2(type: "progress", requestID: parityRequestID, sequence: 7,
                             phase: "scanning", fraction: 0.4213))

// ③ 오류 — **한국어가 UTF-8 그대로 나가야 한다.** \uXXXX 가 아니다.
dumpSorted("json.event[korean]",
           PluginScanEventV2(type: "failed", requestID: parityRequestID, sequence: 3,
                             message: "요청 resolution을 정확히 적용할 수 없습니다."))

// ④ Windows 경로 — 역슬래시 이스케이프. `/` 는 이스케이프하지 않는다.
dumpSorted("json.event[paths]",
           PluginScanEventV2(type: "completed", requestID: parityRequestID, sequence: 12,
                             width: 10200, height: 6800,
                             path: #"C:\Users\me\AppData\Local\Temp\a b\frame.tiff"#,
                             irPath: "/tmp/x.ir.tiff", hasInfrared: true))

// ⑤ 경고 배열 — **순서가 의미다.**
dumpSorted("json.event[warnings]",
           PluginScanEventV2(type: "completed", requestID: parityRequestID, sequence: 5,
                             warnings: ["zebra", "alpha", "middle"]))

// ⑥ 빈 배열은 nil 이 아니다 — 키가 나와야 한다.
dumpSorted("json.event[emptyWarnings]",
           PluginScanEventV2(type: "completed", requestID: parityRequestID, sequence: 6,
                             warnings: []))

// ⑦ appliedOptions — **12키가 전부 나오고 셋은 null 이다.**
do {
    let request = makeRequest(
        deviceID: "genesys:libusb:001:002", resolutionDPI: 3600, bitDepth: 16,
        colorMode: "color", filmType: "colorNegative",
        scanArea: ScanArea(originXMM: 0, originYMM: 0, widthMM: 36.33, heightMM: 24),
        outputRawTIFF: true)
    let applied = PluginAppliedScanOptionsV2(request: request)
    dumpSorted("json.event[appliedNil]",
               PluginScanEventV2(type: "completed", requestID: parityRequestID, sequence: 20,
                                 appliedOptions: applied))
}

// ⑧ 같은 것을 값으로 채운 경우.
do {
    let request = makeRequest(
        deviceID: "epson2:libusb:002:003", resolutionDPI: 2400, bitDepth: 8,
        colorMode: "gray", filmType: "bwNegative",
        multiExposure: true, infrared: true,
        brightnessAdjustment: -12.5, contrastAdjustment: 0.0,
        scanArea: ScanArea(originXMM: 1.5, originYMM: 2.25, widthMM: 36.33, heightMM: 44.25),
        hardwareExposureTime: 14000, outputRawTIFF: false)
    let applied = PluginAppliedScanOptionsV2(request: request)
    dumpSorted("json.event[appliedFull]",
               PluginScanEventV2(type: "completed", requestID: parityRequestID, sequence: 21,
                                 appliedOptions: applied))
}

// ⑨ 수 표기 — 정수에 소수점이 붙으면 안 되고, 실수는 최단 왕복이어야 한다.
struct ParityNumbers: Encodable {
    var big: Int
    var d1: Double
    var d2: Double
    var d3: Double
    var d4: Double
    var d5: Double
    var d6: Double
    var int: Int
    var intNeg: Int
    var intZero: Int
}
dumpSorted("json.numbers", ParityNumbers(
    big: 9_007_199_254_740_991, d1: 36.33, d2: 0.1, d3: 1.0, d4: -0.5,
    d5: 0.4213, d6: Double(1.0) / Double(3.0), int: 3600, intNeg: -7, intZero: 0))

// ⑩ 이스케이프.
struct ParityEscapes: Encodable {
    var backslash: String
    var control: String
    var emoji: String
    var korean: String
    var newline: String
    var quote: String
    var slash: String
}
dumpSorted("json.escapes", ParityEscapes(
    backslash: #"C:\a\b"#,
    control: "a\u{01}\u{1f}b",
    emoji: "필름 🎞",
    korean: "스캐너 오류",
    newline: "a\nb\tc\rd",
    quote: "say \"hi\"",
    slash: "a/b/c"))

// =========================================================================
// wire/protocol — detect / capabilities 응답. **전부 "생략" 쪽이다.**
//
// PluginDevice / PluginCapabilities 는 SANEPluginCore 가 아니라 실행 파일
// 타깃에 있다. parity-check.sh 가 **저장소의 실제 WireProtocol.swift** 를
// 함께 컴파일한다 — 복사본이 아니다.
// =========================================================================

// ① 옵셔널이 전부 빈 장치 — 키가 4개만 나와야 한다.
dumpSorted("proto.device[bare]", PluginDevice(
    id: "sane-genesys:libusb:001:002", displayName: "Plustek OpticFilm 8100",
    vendor: "Plustek", model: "OpticFilm 8100"))

// ② 실측 예시(wire-contract §4.2.1)와 같은 모양 — nil 3개는 **생략**이다.
dumpSorted("proto.device[measured]", PluginDevice(
    id: "sane-genesys:libusb:001:002", displayName: "Plustek OpticFilm 8100",
    vendor: "Plustek", model: "OpticFilm 8100", connectionType: "usb",
    verifiedStatus: "compatibleTarget", driverVersion: "genesys (SANE)"))

// ③ 전부 채운 장치.
dumpSorted("proto.device[full]", PluginDevice(
    id: "epson2:libusb:002:003", displayName: "Epson Perfection V850",
    vendor: "Epson", model: "Perfection V850", connectionType: "usb",
    usbVendorID: "0x04b8", usbProductID: "0x014a", serialNumber: "SN/12345",
    verifiedStatus: "untested", driverVersion: "epson2 (SANE)"))

// ④ detect 응답 — **배열 순서는 의미다.**
dumpSorted("proto.detect[two]", PluginDetectResponse(devices: [
    PluginDevice(id: "zebra", displayName: "Z", vendor: "Z", model: "Z"),
    PluginDevice(id: "alpha", displayName: "A", vendor: "A", model: "A"),
]))
dumpSorted("proto.detect[empty]", PluginDetectResponse(devices: []))

// ⑤ 능력 — 필수 3키만.
dumpSorted("proto.caps[minimal]", PluginCapabilities(
    resolutionsDPI: [600, 1200, 2400, 3600, 7200], modes: ["color", "gray"],
    bitDepths: [8, 16]))

// ⑥ 빈 배열도 키가 나온다 — 옵셔널이 아니기 때문이다.
dumpSorted("proto.caps[emptyRequired]", PluginCapabilities(
    resolutionsDPI: [], modes: [], bitDepths: []))

// ⑦ 범위 — **step 이 없으면 키가 없다.**
dumpSorted("proto.caps[ranges]", PluginCapabilities(
    resolutionsDPI: [3600], modes: ["color"], bitDepths: [16],
    brightnessRange: ScannerOptionRange(minimum: -100, maximum: 100, step: 1),
    scanWidthRange: ScannerOptionRange(minimum: 0, maximum: 36.33)))

// ⑧ 빈 딕셔너리는 nil 이 아니다 — `{}` 가 나와야 한다.
dumpSorted("proto.caps[emptyReasons]", PluginCapabilities(
    resolutionsDPI: [3600], modes: ["color"], bitDepths: [16],
    disabledReasons: [:]))

// ⑨ 전부 채운 능력.
dumpSorted("proto.caps[full]", PluginCapabilities(
    resolutionsDPI: [600, 3600], modes: ["color", "gray"], bitDepths: [8, 16],
    sourceModes: ["Transparency Adapter"],
    transparencyModes: ["Transparency Adapter Infrared"],
    supportsPreview: true, supportsTransparency: true, supportsInfrared: false,
    supportsMultiExposure: false, supportsScanArea: true,
    supportsPositionedScanArea: true,
    brightnessRange: ScannerOptionRange(minimum: -100, maximum: 100, step: 1),
    contrastRange: ScannerOptionRange(minimum: -100, maximum: 100, step: 1),
    hardwareExposureRange: ScannerOptionRange(minimum: 1000, maximum: 60000, step: 1),
    scanOriginXRange: ScannerOptionRange(minimum: 0, maximum: 36.33),
    scanOriginYRange: ScannerOptionRange(minimum: 0, maximum: 44.25),
    scanWidthRange: ScannerOptionRange(minimum: 0, maximum: 36.33),
    scanHeightRange: ScannerOptionRange(minimum: 0, maximum: 44.25),
    disabledReasons: [
        "infrared": "이 장치는 IR 채널을 노출하지 않습니다.",
        "multiExposure": "scan-exposure-time 옵션이 없습니다.",
    ],
    minScanAreaWidthMM: 1, minScanAreaHeightMM: 1,
    minScanAreaOriginXMM: 0, minScanAreaOriginYMM: 0,
    maxScanAreaWidthMM: 36.33, maxScanAreaHeightMM: 44.25,
    maxScanAreaOriginXMM: 0, maxScanAreaOriginYMM: 0,
    scanAreaUnit: "millimeter", outputFormats: ["tiff"],
    capabilityToken: "eyJhIjoxfQ=="))

// =========================================================================
// wire/parse — 요청 JSON 디코딩
//
// 대조하는 것은 **수락/거부 판정과 디코드된 값**이지 오류 문구가 아니다.
// main.swift 가 `try?` 로 DecodingError 를 버리고 한 문장만 내보내기 때문이다.
//
// **corpus 를 C++ 쪽에도 똑같이 적는다.** 그래서 문서의 길이와 FNV-1a 를
// 함께 찍는다 — 한쪽만 고치면 판정이 우연히 같아도 여기서 갈린다.
//
// 아래 둘은 **의도한 divergence 라 corpus 에 없다**(windows/src/wire/parse.h):
//   resolutionDPI 2147483648   Swift Int 은 64비트, C++ 필드는 int
//   brightnessAdjustment 0e999 RapidJSON 토큰화가 지수를 거부한다
// =========================================================================

if ProcessInfo.processInfo.environment["PARITY_RAPIDJSON"] != nil {
    // **C++ 쪽 kBase 와 순서까지 같아야 한다.**
    let parseBase: [(String, String)] = [
        ("protocolVersion", "2"),
        ("requestID", "\"3F2504E0-4F89-11D3-9A0C-0305E82C3301\""),
        ("deviceID", "\"genesys:libusb:001:002\""),
        ("resolutionDPI", "3600"),
        ("bitDepth", "16"),
        ("colorMode", "\"color\""),
        ("filmType", "\"colorNegative\""),
        ("preview", "false"),
        ("multiExposure", "false"),
        ("infrared", "false"),
        ("scanArea", "{\"originXMM\":1,\"originYMM\":2.5,\"widthMM\":36.33,\"heightMM\":24.25}"),
        ("outputRawTIFF", "true"),
        ("outputPath", "\"/tmp/negaflow/frame.tiff\""),
    ]

    func parseBuild(_ drop: String, _ extra: String) -> String {
        var parts: [String] = []
        for (k, v) in parseBase {
            if !drop.isEmpty && drop == k { continue }
            parts.append("\"\(k)\":\(v)")
        }
        if !extra.isEmpty { parts.append(extra) }
        return "{" + parts.joined(separator: ",") + "}"
    }

    func fnv1a(_ bytes: [UInt8]) -> UInt32 {
        var h: UInt32 = 2166136261
        for b in bytes {
            h ^= UInt32(b)
            h = h &* 16777619
        }
        return h
    }

    // **10진 표기가 아니라 비트 패턴을 찍는다.** 표기 차이로 터지는 것을 막고,
    // 1 ULP 차이는 그대로 드러난다.
    func bits(_ d: Double) -> String { String(format: "%016llx", d.bitPattern) }

    func hexBytes(_ s: String) -> String {
        Array(s.utf8).map { String(format: "%02x", $0) }.joined()
    }

    // (label, drop, extra, raw) — raw 가 nil 이 아니면 문서를 그대로 쓴다.
    let parseCases: [(String, String, String, String?)] = [
        ("baseline", "", "", nil),
        ("unknown-key", "", "\"futureField\":123", nil),
        ("unknown-nested", "", "\"futureField\":{\"a\":[1,2,{\"b\":null}]}", nil),
        ("bright-null", "", "\"brightnessAdjustment\":null", nil),
        ("bright-value", "", "\"brightnessAdjustment\":0.25", nil),
        ("bright-int", "", "\"brightnessAdjustment\":1", nil),
        ("bright-negative", "", "\"brightnessAdjustment\":-12.5", nil),
        ("bright-subnormal", "", "\"brightnessAdjustment\":4.9e-324", nil),
        ("bright-underflow", "", "\"brightnessAdjustment\":1e-324", nil),
        ("bright-overflow", "", "\"brightnessAdjustment\":1e309", nil),
        ("bright-string", "", "\"brightnessAdjustment\":\"0.25\"", nil),
        ("bright-bool", "", "\"brightnessAdjustment\":true", nil),
        ("contrast-value", "", "\"contrastAdjustment\":-100", nil),
        ("hw-null", "", "\"hardwareExposureTime\":null", nil),
        ("hw-value", "", "\"hardwareExposureTime\":20000", nil),
        ("tok-null", "", "\"capabilityToken\":null", nil),
        ("tok-empty", "", "\"capabilityToken\":\"\"", nil),
        ("tok-value", "", "\"capabilityToken\":\"eyJhIjoxfQ==\"", nil),
        ("drop-deviceID", "deviceID", "", nil),
        ("drop-scanArea", "scanArea", "", nil),
        ("drop-outputPath", "outputPath", "", nil),
        ("null-deviceID", "deviceID", "\"deviceID\":null", nil),
        ("null-bitDepth", "bitDepth", "\"bitDepth\":null", nil),
        ("null-preview", "preview", "\"preview\":null", nil),
        ("dup-bitDepth", "", "\"bitDepth\":8", nil),
        ("dup-deviceID", "", "\"deviceID\":\"LAST\"", nil),
        ("dup-bright", "", "\"brightnessAdjustment\":0.5,\"brightnessAdjustment\":null", nil),
        ("depth-double-exact", "bitDepth", "\"bitDepth\":16.0", nil),
        ("depth-exponent", "bitDepth", "\"bitDepth\":1.6e1", nil),
        ("depth-frac", "bitDepth", "\"bitDepth\":16.5", nil),
        ("depth-string", "bitDepth", "\"bitDepth\":\"16\"", nil),
        ("dpi-int32max", "resolutionDPI", "\"resolutionDPI\":2147483647", nil),
        ("dpi-negative", "resolutionDPI", "\"resolutionDPI\":-1200", nil),
        ("dpi-minus-zero", "resolutionDPI", "\"resolutionDPI\":-0", nil),
        ("dpi-int64-over", "resolutionDPI", "\"resolutionDPI\":9223372036854775808", nil),
        ("preview-number", "preview", "\"preview\":1", nil),
        ("preview-string", "preview", "\"preview\":\"true\"", nil),
        ("mode-number", "colorMode", "\"colorMode\":3", nil),
        ("area-origin-absent", "scanArea",
         "\"scanArea\":{\"widthMM\":36.33,\"heightMM\":24.25}", nil),
        ("area-origin-null", "scanArea",
         "\"scanArea\":{\"originXMM\":null,\"originYMM\":null,\"widthMM\":36.33,\"heightMM\":24.25}",
         nil),
        ("area-width-absent", "scanArea", "\"scanArea\":{\"heightMM\":24.25}", nil),
        ("area-width-null", "scanArea",
         "\"scanArea\":{\"widthMM\":null,\"heightMM\":24.25}", nil),
        ("area-unknown-key", "scanArea",
         "\"scanArea\":{\"widthMM\":36.33,\"heightMM\":24.25,\"zzz\":1}", nil),
        ("area-dup-width", "scanArea",
         "\"scanArea\":{\"widthMM\":36.33,\"heightMM\":24.25,\"widthMM\":99}", nil),
        ("area-not-object", "scanArea", "\"scanArea\":42", nil),
        ("area-int-values", "scanArea",
         "\"scanArea\":{\"widthMM\":36,\"heightMM\":24}", nil),
        ("uuid-lower", "requestID",
         "\"requestID\":\"3f2504e0-4f89-11d3-9a0c-0305e82c3301\"", nil),
        ("uuid-mixed", "requestID",
         "\"requestID\":\"3F2504e0-4f89-11D3-9a0C-0305e82C3301\"", nil),
        ("uuid-nil", "requestID",
         "\"requestID\":\"00000000-0000-0000-0000-000000000000\"", nil),
        ("uuid-braces", "requestID",
         "\"requestID\":\"{3F2504E0-4F89-11D3-9A0C-0305E82C3301}\"", nil),
        ("uuid-nohyphen", "requestID",
         "\"requestID\":\"3F2504E04F8911D39A0C0305E82C3301\"", nil),
        ("uuid-short", "requestID",
         "\"requestID\":\"3F2504E0-4F89-11D3-9A0C-0305E82C330\"", nil),
        ("uuid-urn", "requestID",
         "\"requestID\":\"urn:uuid:3F2504E0-4F89-11D3-9A0C-0305E82C3301\"", nil),
        ("escape-solidus", "deviceID", "\"deviceID\":\"a\\/b\"", nil),
        ("escape-unicode", "deviceID", "\"deviceID\":\"\\uD55C\\uAE00\"", nil),
        ("escape-nul", "deviceID", "\"deviceID\":\"a\\u0000b\"", nil),
        ("escape-surrogate-pair", "deviceID", "\"deviceID\":\"\\uD83D\\uDE00\"", nil),
        ("escape-bad", "deviceID", "\"deviceID\":\"a\\xb\"", nil),
        ("escape-lone-surrogate", "deviceID", "\"deviceID\":\"\\uD800\"", nil),
        ("raw-control-tab", "deviceID", "\"deviceID\":\"a\tb\"", nil),
        ("toplevel-array", "", "", "[]"),
        ("toplevel-string", "", "", "\"x\""),
        ("empty-object", "", "", "{}"),
        ("empty-input", "", "", ""),
        ("single-quote", "", "", "{'deviceID':'x'}"),
    ]

    let parseDecoder = JSONDecoder()
    for (label, drop, extra, raw) in parseCases {
        let json = raw ?? parseBuild(drop, extra)
        let bytes = Array(json.utf8)
        let head = "len=\(bytes.count) sum=" + String(format: "%08x", fnv1a(bytes)) + " "
        let key = "parse[" + label + "]"

        guard let r = try? parseDecoder.decode(PluginScanRequestV2.self, from: Data(bytes)) else {
            emit(key, head + "fail")
            continue
        }
        var line = head
        line += "ok pv=\(r.protocolVersion)"
        line += " uuid=\(r.requestID.uuidString)"
        line += " dev=" + hexBytes(r.deviceID)
        line += " dpi=\(r.resolutionDPI)"
        line += " depth=\(r.bitDepth)"
        line += " mode=\(r.colorMode)"
        line += " film=\(r.filmType)"
        line += " prev=" + (r.preview ? "1" : "0")
        line += " multi=" + (r.multiExposure ? "1" : "0")
        line += " ir=" + (r.infrared ? "1" : "0")
        line += " bright=" + (r.brightnessAdjustment.map(bits) ?? "nil")
        line += " contrast=" + (r.contrastAdjustment.map(bits) ?? "nil")
        line += " x=" + bits(r.scanArea.originXMM)
        line += " y=" + bits(r.scanArea.originYMM)
        line += " w=" + bits(r.scanArea.widthMM)
        line += " h=" + bits(r.scanArea.heightMM)
        line += " hw=" + (r.hardwareExposureTime.map { "\($0)" } ?? "nil")
        line += " raw=" + (r.outputRawTIFF ? "1" : "0")
        line += " tok=" + (r.capabilityToken ?? "nil")
        line += " path=" + r.outputPath
        emit(key, line)
    }
}
