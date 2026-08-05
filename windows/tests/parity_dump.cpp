// SPDX-License-Identifier: GPL-2.0-or-later
//
// parity_dump — Swift 구현과 같은 입력에 같은 판정을 내는지 비교하기 위한 덤퍼.
//
// 같은 key=value 줄을 내는 Swift 짝과 출력을 diff 한다.
// 골든 픽스처 corpus(M1)가 생기기 전까지의 임시 수단이며,
// corpus 가 생기면 이 파일은 러너로 대체된다.
// 근거: windows_docs/05-protocol/conformance-fixtures.md

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <cstring>
#include <tuple>
#include <utility>
#include <string>
#include <vector>

#include "imaging/align.h"
#include "imaging/merge.h"
#ifdef NEGAFLOW_HAVE_LIBTIFF
#include "imaging/tiff_io.h"
#endif
#include "sane/capabilities.h"
#include "wire/event.h"
#include "wire/json.h"
#include "wire/protocol.h"
#include "wire/request.h"
#ifdef NEGAFLOW_HAVE_RAPIDJSON
#include "wire/parse.h"
#endif
#include "sane/media.h"
#include "process/progress.h"
#include "sane/args.h"
#include "sane/validate.h"
#include "sane/device_list.h"
#include "sane/option_dump.h"
#include "util/numeric.h"

namespace {

using negaflow::sane::OptionDump;
using negaflow::sane::ResolutionSpec;

void emit(const std::string& k, const std::string& v) {
    std::printf("%s=%s\n", k.c_str(), v.c_str());
}

std::string join(const std::vector<std::string>& v, const char* sep) {
    std::string out;
    for (size_t i = 0; i < v.size(); ++i) {
        if (i) out += sep;
        out += v[i];
    }
    return out;
}

std::string joinInts(const std::vector<int>& v, const char* sep) {
    std::string out;
    for (size_t i = 0; i < v.size(); ++i) {
        if (i) out += sep;
        out += std::to_string(v[i]);
    }
    return out;
}

// Swift 의 String(Double) 과 같은 표기를 만든다.
// Swift 는 정수여도 "0.0" 처럼 소수점을 남긴다.
std::string swiftDouble(double v) {
    std::string s = negaflow::util::saneNumber(v);
    if (s.find('.') == std::string::npos && s.find("inf") == std::string::npos) s += ".0";
    return s;
}

std::string rangeText(const std::optional<negaflow::util::OptionRange>& r) {
    if (!r) return "<nil>";
    const std::string step = r->step ? swiftDouble(*r->step) : std::string("nil");
    return swiftDouble(r->minimum) + ".." + swiftDouble(r->maximum) + " step=" + step;
}

const char* kDump = R"(Options specific to device `genesys:libusb:001:002':
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

)";

// --- imaging/align 용 합성 이미지 ------------------------------------------
//
// Swift 짝과 **비트 단위로 같은** 입력을 만들어야 한다. 그래서 부동소수점
// 난수 대신 정수 해시로 값을 만든다 — 32비트 무부호 산술은 두 언어에서
// 동일하게 정의돼 있다(Swift 는 &* / &+, C++ 는 unsigned 의 모듈러 연산).

std::uint32_t hash32(std::uint32_t x) {
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}

/// 8×8 블록 구조(정렬이 물릴 거친 신호) + 픽셀 단위 미세 변화.
float sceneChannel(int x, int y, int channel, std::uint32_t seed) {
    const std::uint32_t u = static_cast<std::uint32_t>(x + 1024);
    const std::uint32_t v = static_cast<std::uint32_t>(y + 1024);
    const std::uint32_t h = hash32((u >> 3) * 2654435761u + (v >> 3) * 40503u +
                                   static_cast<std::uint32_t>(channel) * 7u + seed);
    const float blocky = static_cast<float>(h >> 16) / 65535.0f;
    const std::uint32_t g = hash32(u * 374761393u + v * 668265263u + seed +
                                   static_cast<std::uint32_t>(channel));
    const float fine = static_cast<float>(g >> 24) / 255.0f;
    return blocky * 0.8f + fine * 0.2f;
}

/// 정렬되지 않는 노이즈. 목적지 좌표로 계산하므로 시프트를 따라가지 않는다.
float jitterDelta(int x, int y, int channel, std::uint32_t jitterSeed) {
    const std::uint32_t j =
        hash32(static_cast<std::uint32_t>(y * 8191 + x + channel * 131) + jitterSeed);
    return (static_cast<float>(j >> 22) / 1023.0f - 0.5f) * 0.05f;
}

std::vector<float> makeImage(int width,
                             int height,
                             std::uint32_t seed,
                             int shiftX,
                             int shiftY,
                             std::uint32_t jitterSeed) {
    std::vector<float> out(static_cast<std::size_t>(width * height * 4), 0.0f);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const std::size_t i = static_cast<std::size_t>((y * width + x) * 4);
            for (int c = 0; c < 3; ++c) {
                float value = sceneChannel(x + shiftX, y + shiftY, c, seed);
                if (jitterSeed != 0) value += jitterDelta(x, y, c, jitterSeed);
                out[i + static_cast<std::size_t>(c)] = value;
            }
            out[i + 3] = 1.0f;
        }
    }
    return out;
}

std::vector<float> makeFlatImage(int width, int height, float value) {
    std::vector<float> out(static_cast<std::size_t>(width * height * 4), 0.0f);
    for (int p = 0; p < width * height; ++p) {
        const std::size_t i = static_cast<std::size_t>(p * 4);
        out[i] = value;
        out[i + 1] = value;
        out[i + 2] = value;
        out[i + 3] = 1.0f;
    }
    return out;
}

/// 노출 패스 하나. 신뢰 가중치 5분기를 **전부** 지나도록 값 대역을 흩는다.
///
/// 대역은 목적지 좌표로 정하고 장면 세부만 시프트한다 — 픽셀별 raw 대역을
/// 고정한 채 정렬 신호만 움직이기 위해서다.
std::vector<float> makeExposureImage(int width,
                                     int height,
                                     std::uint32_t seed,
                                     int pass,
                                     int shiftX,
                                     int shiftY) {
    std::vector<float> out(static_cast<std::size_t>(width * height * 4), 0.0f);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const std::size_t i = static_cast<std::size_t>((y * width + x) * 4);
            for (int c = 0; c < 3; ++c) {
                const float s = sceneChannel(x + shiftX, y + shiftY, c,
                                             seed + static_cast<std::uint32_t>(pass) * 101u);
                const std::uint32_t band =
                    hash32(static_cast<std::uint32_t>((y * width + x) * 3 + c) + seed) % 5u;
                float v = 0.0f;
                switch (band) {
                    case 0: v = 0.99f + s * 0.01f; break;    // 클리핑 (>= 0.985)
                    case 1: v = 0.90f + s * 0.08f; break;    // 클리핑 경계
                    case 2: v = s * 0.006f; break;           // 암부 (<= 0.006)
                    case 3: v = 0.006f + s * 0.029f; break;  // 암부 경계
                    default: v = 0.1f + s * 0.7f; break;     // 정상
                }
                out[i + static_cast<std::size_t>(c)] = v;
            }
            out[i + 3] = 1.0f;
        }
    }
    return out;
}

/// Float 는 비트 패턴으로 비교한다. 십진 표기는 반올림으로 차이를 숨긴다.
std::string fbits(float f) {
    std::uint32_t bits = 0;
    std::memcpy(&bits, &f, sizeof(bits));
    char buf[16];
    std::snprintf(buf, sizeof(buf), "%08x", bits);
    return std::string(buf);
}

}  // namespace

int main() {
    const OptionDump d{kDump};

    std::vector<std::string> names(d.optionNames().begin(), d.optionNames().end());
    std::vector<std::string> inactive(d.inactiveOptionNames().begin(),
                                      d.inactiveOptionNames().end());
    emit("names", join(names, ","));
    emit("inactive", join(inactive, ","));
    emit("mode.enum", join(d.enumValues("mode"), "|"));
    emit("source.enum", join(d.enumValues("source"), "|"));
    emit("mode.selected", d.selectedEnumValue("mode").value_or("<nil>"));
    emit("contrast.enum", join(d.enumValues("contrast"), "|"));
    emit("depth.int", joinInts(d.intTokens("depth"), ","));
    emit("x.range", rangeText(d.numericRange("x")));
    emit("brightness.range", rangeText(d.numericRange("brightness")));
    emit("contrast.range", rangeText(d.numericRange("contrast")));
    emit("x.unit", d.rangeUnit("x").value_or("<nil>"));

    const auto spec = d.resolutionSpec();
    if (spec.kind == ResolutionSpec::Kind::List) {
        emit("resolution", "list:" + joinInts(spec.list, ","));
    } else if (spec.kind == ResolutionSpec::Kind::Range) {
        emit("resolution",
             "range:" + std::to_string(spec.min) + ".." + std::to_string(spec.max));
    } else {
        emit("resolution", "none");
    }

    const OptionDump inactiveDepth{"    --depth 8 [inactive]\n"};
    emit("inactiveDepth.int", joinInts(inactiveDepth.intTokens("depth"), ","));
    emit("inactiveDepth.constraint", joinInts(inactiveDepth.constraintIntTokens("depth"), ","));

    const OptionDump cs{"    --depth 8|14 [8]\n"};
    emit("coolscan.depth", joinInts(cs.intTokens("depth"), ","));

    const OptionDump pel{"    -x 0..3600pel [3600]\n"};
    emit("pel.unit", pel.rangeUnit("x").value_or("<nil>"));

    const OptionDump noUnit{"    --scan-exposure-time 0..65535 [11000]\n"};
    emit("noUnit.unit", noUnit.rangeUnit("scan-exposure-time").value_or("<nil>"));

    // CRLF — **의도적 divergence.** Swift 는 "\r\n" 을 한 Character 로 보아
    // 줄 분리 자체가 일어나지 않는다(첫 옵션만 남는다). C++ 는 바이트 단위로
    // 나누므로 정상 파싱한다. 아래 두 줄은 Swift 와 일치하지 않는 것이 정답이다.
    // 근거: windows_docs/02-frontend-contract/option-dump-parser.md §2.2
    const OptionDump crlf{"    --mode Color|Gray [Color]\r\n    --depth 8|16 [16]\r\n"};
    emit("crlf.mode", join(crlf.enumValues("mode"), "|"));
    emit("crlf.depth", joinInts(crlf.intTokens("depth"), ","));

    const OptionDump dup{"    --mode Color [Color]\n    --mode Gray|Lineart [Gray]\n"};
    emit("dup.mode", join(dup.enumValues("mode"), "|"));

    const OptionDump rangeRes{"    --resolution 50..6400dpi [600]\n"};
    const auto rr = rangeRes.resolutionSpec();
    if (rr.kind == ResolutionSpec::Kind::Range) {
        emit("rangeRes", "range:" + std::to_string(rr.min) + ".." + std::to_string(rr.max));
    } else {
        emit("rangeRes", "other");
    }

    // =====================================================================
    // sane/device_list
    // =====================================================================

    const char* kListOut =
        "device `coolscan3:usb:libusb:001:002' is a Nikon LS-50 ED film scanner\n"
        "device `epson2:libusb:001:005' is a Epson GT-X970 flatbed scanner\n"
        "device `genesys:libusb:001:003' is a PLUSTEK OpticFilm 8100 film scanner\n"
        "device `pieusb:libusb:002:004' is a PIE/Reflecta ProScan 10T slide scanner\n"
        "device `net:host.local:genesys:libusb:001:002' is a Remote Thing multi-function peripheral\n"
        "device `v4l:/dev/video0' is a Noname Webcam virtual device\n"
        "garbage line that should be ignored\n"
        "device `weird:x' is a SingleToken scanner";

    const auto describe = [](const negaflow::sane::ListedDevice& x) {
        return x.devname + "|" + x.vendor + "|" + x.model + "|" + x.deviceType;
    };

    {
        const auto listed = negaflow::sane::parseDeviceList(kListOut);
        for (size_t i = 0; i < listed.size(); ++i) {
            emit("L[" + std::to_string(i) + "]", describe(listed[i]));
        }
    }

    {
        const char* kFormatted =
            "genesys:libusb:001:003\tPLUSTEK\tOpticFilm 8100\tfilm scanner\n"
            "epson2:libusb:001:005\t Epson \t GT-X970 \t flatbed scanner \n"
            "broken-line-without-tabs\n"
            "\tEmptyDev\tm\tt\n";
        const auto listed = negaflow::sane::parseFormattedDeviceList(kFormatted);
        for (size_t i = 0; i < listed.size(); ++i) {
            emit("F[" + std::to_string(i) + "]", describe(listed[i]));
        }
    }

    for (const char* s : {"genesys:libusb:001:002", "epson2:net:host:1", "coolscan:scsi:0:1:2",
                          "pie:/dev/sg0", "x:firewire:1", "y:ieee1394:2", "plain",
                          "net:h:genesys:libusb:1:2"}) {
        emit(std::string("backend[") + s + "]", negaflow::sane::backendName(s));
        emit(std::string("conn[") + s + "]",
             std::string(negaflow::sane::connectionTypeRawValue(negaflow::sane::connectionType(s))));
        emit(std::string("volatile[") + s + "]",
             negaflow::sane::isVolatileUSBSelector(s) ? "true" : "false");
    }

    for (const char* b : {"genesys", "epson2", "coolscan3", "pieusb", "pie", "coolscan", "net",
                          "unknown"}) {
        emit(std::string("stable[") + b + "]",
             negaflow::sane::supportsStableBackendSelector(b) ? "true" : "false");
        emit(std::string("film[") + b + "]",
             negaflow::sane::isDedicatedFilmBackend(b) ? "true" : "false");
        emit(std::string("watchdog[") + b + "]",
             negaflow::sane::usesAutomaticAcquisitionWatchdog(b) ? "true" : "false");
    }

    for (const char* v : {"PLUSTEK", "Epson", "pie/reflecta", "NIKON CORP.", "gt-x970", "a1b2",
                          "  spaced  out  ", "x", ""}) {
        emit(std::string("cap[") + v + "]", negaflow::sane::capitalized(v));
    }

        // =====================================================================
    // sane/capabilities
    // =====================================================================

    const auto capsText = [](const negaflow::sane::ScannerCapabilities& c) {
        std::string out;
        const auto add = [&out](const std::string& p) {
            if (!out.empty()) out += " ";
            out += p;
        };
        std::string res;
        for (size_t i = 0; i < c.supportedResolutionsDPI.size(); ++i) {
            if (i) res += ",";
            res += std::to_string(c.supportedResolutionsDPI[i]);
        }
        add("res=" + res);
        std::string modes;
        for (size_t i = 0; i < c.supportedModes.size(); ++i) {
            if (i) modes += ",";
            modes += std::string(negaflow::sane::colorModeRawValue(c.supportedModes[i]));
        }
        add("modes=" + modes);
        std::string depths;
        for (size_t i = 0; i < c.supportedBitDepths.size(); ++i) {
            if (i) depths += ",";
            depths += std::to_string(static_cast<int>(c.supportedBitDepths[i]));
        }
        add("depths=" + depths);
        add("src=" + join(c.sourceModes, "/"));
        add("tp=" + join(c.transparencyModes, "/"));
        add(std::string("prev=") + (c.supportsPreview ? "true" : "false"));
        add(std::string("transp=") + (c.supportsTransparency ? "true" : "false"));
        add(std::string("ir=") + (c.supportsInfrared ? "true" : "false"));
        add(std::string("mexp=") + (c.supportsMultiExposure ? "true" : "false"));
        add(std::string("area=") + (c.supportsScanArea ? "true" : "false"));
        add(std::string("pos=") + (c.supportsPositionedScanArea ? "true" : "false"));
        add("bright=" + rangeText(c.brightnessRange));
        add("contrast=" + rangeText(c.contrastRange));
        add("hwexp=" + rangeText(c.hardwareExposureRange));
        add("ox=" + rangeText(c.scanOriginXRange));
        add("oy=" + rangeText(c.scanOriginYRange));
        add("w=" + rangeText(c.scanWidthRange));
        add("h=" + rangeText(c.scanHeightRange));
        add("min=" + swiftDouble(c.minScanArea.originXMM) + "," +
            swiftDouble(c.minScanArea.originYMM) + "," + swiftDouble(c.minScanArea.widthMM) + "," +
            swiftDouble(c.minScanArea.heightMM));
        add("max=" + swiftDouble(c.maxScanArea.originXMM) + "," +
            swiftDouble(c.maxScanArea.originYMM) + "," + swiftDouble(c.maxScanArea.widthMM) + "," +
            swiftDouble(c.maxScanArea.heightMM));
        add("unit=" + std::string(negaflow::sane::scanAreaUnitRawValue(c.scanAreaUnit)));
        std::string keys;
        for (const auto& kv : c.disabledReasons) {
            if (!keys.empty()) keys += ",";
            keys += kv.first;
        }
        add("disabled=" + keys);
        return out;
    };

    emit("caps.genesys",
         capsText(negaflow::sane::parseCapabilities(d, "film scanner", "genesys")));

    const char* kEpson =
        "    --mode Lineart|Gray|Color [Lineart]\n"
        "    --source Flatbed|Transparency Unit|TPU8x10 [Flatbed]\n"
        "    --resolution 50..12800dpi [50]\n"
        "    --depth 8|16 [inactive]\n"
        "    -l 0..215.9mm [0]\n"
        "    -t 0..297.18mm [0]\n"
        "    -x 0..215.9mm [215.9]\n"
        "    -y 0..297.18mm [297.18]\n"
        "    --scan-exposure-time 0..65535 [11000]";
    emit("caps.epson2", capsText(negaflow::sane::parseCapabilities(OptionDump{kEpson},
                                                                  "flatbed scanner", "epson2")));

    const char* kCoolscan =
        "    --depth 8|14 [8]\n"
        "    --infrared[=(yes|no)] [no]\n"
        "    -x 0..3600pel [3600]\n"
        "    -y 0..5400pel [5400]";
    emit("caps.coolscan3", capsText(negaflow::sane::parseCapabilities(
                               OptionDump{kCoolscan}, "film scanner", "coolscan3")));

    emit("caps.empty", capsText(negaflow::sane::parseCapabilities(OptionDump{""}, "", "")));

    {
        const std::vector<std::vector<std::string>> srcSets{
            {"Flatbed", "Transparency Unit", "TPU8x10"},
            {"Transparency Adapter", "Transparency Adapter Infrared"},
            {"Transparency Adapter Infrared"},
            {"Flatbed"},
            {},
        };
        for (size_t i = 0; i < srcSets.size(); ++i) {
            emit("pref[" + std::to_string(i) + "]",
                 negaflow::sane::preferredTransparencySource(srcSets[i]).value_or("<nil>"));
        }
    }

    {
        const std::vector<std::string> depthDumps{
            "    --depth 8|16 [16]\n", "    --depth 8 [inactive]\n",
            "    --depth 14 [inactive]\n", "    --depth 8|16 [inactive]\n",
            "    --mode Color [Color]\n",
        };
        for (size_t i = 0; i < depthDumps.size(); ++i) {
            const OptionDump o{depthDumps[i]};
            const auto e = negaflow::sane::fixedDepth(o, "epson2");
            const auto g = negaflow::sane::fixedDepth(o, "genesys");
            emit("fixed[" + std::to_string(i) + "].epson2",
                 e ? std::to_string(static_cast<int>(*e)) : "<nil>");
            emit("fixed[" + std::to_string(i) + "].genesys",
                 g ? std::to_string(static_cast<int>(*g)) : "<nil>");
        }
    }

    {
        const std::vector<std::string> vals{"transparency adapter", "TPU", "Film Holder",
                                            "Slide", "Flatbed", "ADF"};
        for (size_t i = 0; i < vals.size(); ++i) {
            emit("isTp[" + std::to_string(i) + "]",
                 negaflow::sane::isTransparencySource(vals[i]) ? "true" : "false");
            emit("isIr[" + std::to_string(i) + "]",
                 negaflow::sane::isInfraredValue(vals[i]) ? "true" : "false");
        }
    }
    emit("isIr.exact", negaflow::sane::isInfraredValue("ir") ? "true" : "false");
    emit("isIr.word", negaflow::sane::isInfraredValue("Infrared") ? "true" : "false");

        // =====================================================================
    // sane/media
    // =====================================================================

    using negaflow::sane::BitDepth;
    using negaflow::sane::ColorMode;
    using negaflow::sane::FilmType;
    using negaflow::sane::MediaSelection;
    using negaflow::sane::ScanArea;
    using negaflow::sane::ScanOptions;

    const auto oS = [](const std::optional<std::string>& v) { return v.value_or("<nil>"); };
    const auto oI = [](const std::optional<int>& v) {
        return v ? std::to_string(*v) : std::string("<nil>");
    };
    const auto oL = [](const std::optional<long long>& v) {
        return v ? std::to_string(*v) : std::string("<nil>");
    };
    const auto oD = [](const std::optional<double>& v) {
        return v ? swiftDouble(*v) : std::string("<nil>");
    };

    const auto mediaText = [&](const MediaSelection& m) {
        std::string out;
        const auto add = [&out](const std::string& p) {
            if (!out.empty()) out += " ";
            out += p;
        };
        add("src=" + oS(m.source));
        add("mode=" + oS(m.mode));
        add("ft=" + oS(m.filmType));
        add("ftOpt=" + oS(m.filmTypeOptionName));
        add("depth=" + oI(m.depthArgument));
        add("fixed=" + (m.fixedDepth ? std::to_string(static_cast<int>(*m.fixedDepth))
                                     : std::string("<nil>")));
        add("dpi=" + oI(m.resolvedDPI));
        add("ox=" + oD(m.originXMM));
        add("oy=" + oD(m.originYMM));
        add("w=" + oD(m.widthMM));
        add("h=" + oD(m.heightMM));
        add("halign=" + swiftDouble(m.heightAlignmentMM));
        add(std::string("prev=") + (m.hasPreviewOption ? "true" : "false"));
        add(std::string("bright=") + (m.hasBrightnessOption ? "true" : "false"));
        add(std::string("contrast=") + (m.hasContrastOption ? "true" : "false"));
        add(std::string("hwexp=") + (m.hasScanExposureOption ? "true" : "false"));
        add(std::string("hasMode=") + (m.hasModeOption ? "true" : "false"));
        add(std::string("hasDepth=") + (m.hasDepthOption ? "true" : "false"));
        add(std::string("hasFt=") + (m.hasFilmTypeOption ? "true" : "false"));
        add(std::string("hasAdv=") + (m.hasAdvanceOption ? "true" : "false"));
        add("cc=" + oS(m.colorCorrection));
        add("gc=" + oS(m.gammaCorrection));
        add(std::string("hasCC=") + (m.hasColorCorrectionOption ? "true" : "false"));
        add(std::string("hasGC=") + (m.hasGammaCorrectionOption ? "true" : "false"));
        add("brRange=" + rangeText(m.brightnessRange));
        add("srMM=" + oD(m.scanSurfaceRightMM));
        add("sbMM=" + oD(m.scanSurfaceBottomMM));
        switch (m.irStrategy.kind) {
            case negaflow::sane::IRStrategy::Kind::None: add("ir=none"); break;
            case negaflow::sane::IRStrategy::Kind::SeparateSource:
                add("ir=src:" + m.irStrategy.value);
                break;
            case negaflow::sane::IRStrategy::Kind::SeparateMode:
                add("ir=mode:" + m.irStrategy.value);
                break;
            case negaflow::sane::IRStrategy::Kind::CleanImage:
                add("ir=clean:" + m.irStrategy.value);
                break;
        }
        add("irMode=" + oS(m.irPassMode));
        add(std::string("film=") + (m.dedicatedFilmDevice ? "true" : "false"));
        add("px=" + oL(m.originXPixels) + "," + oL(m.originYPixels) + "," + oL(m.widthPixels) +
            "," + oL(m.heightPixels) + "," + oL(m.rightPixels) + "," + oL(m.bottomPixels));
        add(std::string("corner=") + (m.usesCornerPixelGeometry ? "true" : "false"));
        return out;
    };

    const auto makeOptions = [](const char* id, int dpi, BitDepth depth, ColorMode mode,
                                FilmType film, ScanArea area, bool ir) {
        ScanOptions o;
        o.scannerID = id;
        o.resolutionDPI = dpi;
        o.bitDepth = depth;
        o.colorMode = mode;
        o.filmType = film;
        o.scanArea = area;
        o.infraredEnabled = ir;
        return o;
    };

    const ScanArea frame{0.0, 0.0, 36.0, 24.0};

    emit("media.genesys16",
         mediaText(negaflow::sane::resolveMedia(
             d, makeOptions("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen, ColorMode::Color,
                            FilmType::ColorNegative, frame, false),
             "film scanner")));
    emit("media.genesys8",
         mediaText(negaflow::sane::resolveMedia(
             d, makeOptions("sane-genesys:libusb:1:2", 1200, BitDepth::Eight, ColorMode::Color,
                            FilmType::ColorNegative, frame, false),
             "film scanner")));
    emit("media.genesysIR",
         mediaText(negaflow::sane::resolveMedia(
             d, makeOptions("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen, ColorMode::Color,
                            FilmType::ColorNegative, frame, true),
             "film scanner")));
    emit("media.badDPI",
         mediaText(negaflow::sane::resolveMedia(
             d, makeOptions("sane-genesys:libusb:1:2", 2000, BitDepth::Sixteen, ColorMode::Color,
                            FilmType::ColorNegative, frame, false),
             "film scanner")));

    const char* kEpson2 =
        "    --mode Lineart|Gray|Color [Color]\n"
        "    --source Flatbed|Transparency Unit|TPU8x10 [Flatbed]\n"
        "    --film-type Positive Film|Negative Film [Positive Film]\n"
        "    --color-correction None|User defined [None]\n"
        "    --gamma-correction Default|User defined (Gamma=1.0)|User defined (Gamma=1.8) [Default]\n"
        "    --resolution 50..12800dpi [50]\n"
        "    --depth 8|16 [16]\n"
        "    -l 0..215.9mm [0]\n"
        "    -t 0..297.18mm [0]\n"
        "    -x 0..215.9mm [215.9]\n"
        "    -y 0..297.18mm [297.18]";
    const OptionDump epson2Dump{kEpson2};
    emit("media.epson2",
         mediaText(negaflow::sane::resolveMedia(
             epson2Dump,
             makeOptions("sane-epson2:libusb:1:5", 1200, BitDepth::Sixteen, ColorMode::Color,
                         FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 23.5}, false),
             "flatbed scanner")));

    const char* kCoolscan3 =
        "    --depth 8|14 [8]\n"
        "    --negative[=(yes|no)] [no]\n"
        "    --resolution 4000dpi [4000]\n"
        "    -x 0..3600pel [3600]\n"
        "    -y 0..5400pel [5400]";
    emit("media.coolscan3",
         mediaText(negaflow::sane::resolveMedia(
             OptionDump{kCoolscan3},
             makeOptions("sane-coolscan3:libusb:1:2", 4000, BitDepth::Sixteen, ColorMode::Color,
                         FilmType::ColorNegative, frame, false),
             "film scanner")));

    const char* kPieusb =
        "    --mode Color|RGBI [Color]\n"
        "    --advance[=(yes|no)] [yes]\n"
        "    --clean-image[=(yes|no)] [no]\n"
        "    --resolution 3600dpi [3600]\n"
        "    -x 0..36mm [36]\n"
        "    -y 0..24mm [24]";
    emit("media.pieusb",
         mediaText(negaflow::sane::resolveMedia(
             OptionDump{kPieusb},
             makeOptions("sane-pieusb:libusb:2:4", 3600, BitDepth::Sixteen, ColorMode::Color,
                         FilmType::ColorPositive, frame, true),
             "slide scanner")));

    emit("media.empty",
         mediaText(negaflow::sane::resolveMedia(
             OptionDump{""},
             makeOptions("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen, ColorMode::Color,
                         FilmType::ColorNegative, frame, false),
             "")));

    for (const auto ft : {FilmType::ColorNegative, FilmType::ColorPositive, FilmType::BwNegative,
                          FilmType::BwPositive}) {
        const auto m = negaflow::sane::resolveMedia(
            epson2Dump,
            makeOptions("sane-epson2:libusb:1:5", 1200, BitDepth::Sixteen, ColorMode::Color, ft,
                        frame, false),
            "flatbed scanner");
        emit(std::string("polarity[") + std::string(negaflow::sane::filmTypeRawValue(ft)) + "]",
             oS(m.filmType));
    }

    {
        const char* kGammaAB =
            "    --mode Color [Color]\n"
            "    --color-correction None|User defined [None]\n"
            "    --gamma-correction Default|User defined [Default]\n"
            "    --resolution 1200dpi [1200]";
        const auto mAB = negaflow::sane::resolveMedia(
            OptionDump{kGammaAB},
            makeOptions("sane-epson2:libusb:1:5", 1200, BitDepth::Sixteen, ColorMode::Color,
                        FilmType::ColorNegative, frame, false),
            "flatbed scanner");
        emit("gamma.AB", oS(mAB.gammaCorrection));
        emit("cc.none", oS(mAB.colorCorrection));

        const char* kGammaD =
            "    --mode Color [Color]\n"
            "    --gamma-correction Default|User defined (Gamma=1.0)|User defined (Gamma=1.8) "
            "[Default]\n"
            "    --resolution 1200dpi [1200]";
        const auto mD = negaflow::sane::resolveMedia(
            OptionDump{kGammaD},
            makeOptions("sane-epson2:libusb:1:5", 1200, BitDepth::Sixteen, ColorMode::Color,
                        FilmType::ColorNegative, frame, false),
            "flatbed scanner");
        emit("gamma.D", oS(mD.gammaCorrection));

        const char* kModes =
            "    --mode Lineart|Gray|Color|Infrared [Color]\n"
            "    --resolution 1200dpi [1200]";
        for (const auto cm : {ColorMode::Color, ColorMode::Gray}) {
            const auto m = negaflow::sane::resolveMedia(
                OptionDump{kModes},
                makeOptions("sane-x:libusb:1:1", 1200, BitDepth::Sixteen, cm,
                            FilmType::ColorNegative, frame, false),
                "");
            emit(std::string("pick[") + std::string(negaflow::sane::colorModeRawValue(cm)) + "]",
                 oS(m.mode));
            emit(std::string("irPass[") + std::string(negaflow::sane::colorModeRawValue(cm)) + "]",
                 oS(m.irPassMode));
        }
    }

        // =====================================================================
    // sane/validate — exact-option-contract §8.2 거부 목록
    // =====================================================================

    const auto validateText = [](const ScanOptions& o, const MediaSelection& m) {
        const auto e = negaflow::sane::validateExactOptions(o, m);
        return e ? e->description() : std::string("ok");
    };
    const auto vcheck = [&](const std::string& label, const char* dumpText,
                            const ScanOptions& o, const char* hint) {
        const OptionDump od{dumpText};
        const auto m = negaflow::sane::resolveMedia(od, o, hint);
        emit("V[" + label + "]", validateText(o, m));
    };

    const ScanArea gFrame{0.0, 0.0, 36.0, 24.0};

    vcheck("ok.genesys", kDump,
           makeOptions("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, gFrame, false),
           "film scanner");
    vcheck("dpi.unsupported", kDump,
           makeOptions("sane-genesys:libusb:1:2", 2000, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, gFrame, false),
           "film scanner");

    const char* kNoPreview =
        "    --mode Color [Color]\n    --depth 16 [16]\n    --resolution 3600dpi [3600]\n"
        "    -x 0..36mm [36]\n    -y 0..24mm [24]";
    vcheck("preview.missing", kNoPreview,
           makeOptions("sane-x:libusb:1:1", 0, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, gFrame, false),
           "");

    const char* kFixed8 =
        "    --mode Color [Color]\n    --depth 8 [inactive]\n    --resolution 3600dpi [3600]\n"
        "    -x 0..36mm [36]\n    -y 0..24mm [24]";
    vcheck("depth.fixedMismatch", kFixed8,
           makeOptions("sane-x:libusb:1:1", 3600, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, gFrame, false),
           "");
    vcheck("depth.fixedMatch", kFixed8,
           makeOptions("sane-x:libusb:1:1", 3600, BitDepth::Eight, ColorMode::Color,
                       FilmType::ColorNegative, gFrame, false),
           "");

    const char* kNoDepth =
        "    --mode Color [Color]\n    --resolution 3600dpi [3600]\n"
        "    -x 0..36mm [36]\n    -y 0..24mm [24]";
    vcheck("depth.missing", kNoDepth,
           makeOptions("sane-genesys:libusb:1:1", 3600, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, gFrame, false),
           "");

    const char* kColorOnly =
        "    --mode Color [Color]\n    --depth 16 [16]\n    --resolution 3600dpi [3600]\n"
        "    -x 0..36mm [36]\n    -y 0..24mm [24]";
    {
        auto o = makeOptions("sane-x:libusb:1:1", 3600, BitDepth::Sixteen, ColorMode::Color,
                             FilmType::ColorNegative, gFrame, false);
        o.colorMode = ColorMode::Gray;
        vcheck("mode.grayMissing", kColorOnly, o, "");
    }

    const char* kNoMode =
        "    --depth 16 [16]\n    --resolution 3600dpi [3600]\n"
        "    -x 0..36mm [36]\n    -y 0..24mm [24]";
    vcheck("mode.noneNonDedicated", kNoMode,
           makeOptions("sane-genesys:libusb:1:1", 3600, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, gFrame, false),
           "");
    {
        auto o = makeOptions("sane-coolscan3:libusb:1:1", 3600, BitDepth::Sixteen,
                             ColorMode::Color, FilmType::ColorNegative, gFrame, false);
        o.colorMode = ColorMode::Gray;
        vcheck("mode.noneDedicatedGray", kNoMode, o, "film scanner");
    }

    const char* kReflective =
        "    --mode Color [Color]\n    --source Flatbed [Flatbed]\n    --depth 16 [16]\n"
        "    --resolution 3600dpi [3600]\n    -x 0..36mm [36]\n    -y 0..24mm [24]";
    vcheck("source.reflectiveOnly", kReflective,
           makeOptions("sane-x:libusb:1:1", 3600, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, gFrame, false),
           "");

    vcheck("pieusb.noAdvance", kColorOnly,
           makeOptions("sane-pieusb:libusb:2:4", 3600, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorPositive, gFrame, false),
           "slide scanner");

    const char* kEpsonNoNone =
        "    --mode Color [Color]\n    --color-correction Auto|User defined [Auto]\n"
        "    --depth 16 [16]\n    --resolution 3600dpi [3600]\n"
        "    -x 0..36mm [36]\n    -y 0..24mm [24]";
    vcheck("epson2.noColorNone", kEpsonNoNone,
           makeOptions("sane-epson2:libusb:1:5", 3600, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, gFrame, false),
           "");

    const char* kEpsonNoGamma =
        "    --mode Color [Color]\n    --gamma-correction Default|Auto [Default]\n"
        "    --depth 16 [16]\n    --resolution 3600dpi [3600]\n"
        "    -x 0..36mm [36]\n    -y 0..24mm [24]";
    vcheck("epson2.noGamma", kEpsonNoGamma,
           makeOptions("sane-epson2:libusb:1:5", 3600, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, gFrame, false),
           "");

    vcheck("area.widthOutOfRange", kDump,
           makeOptions("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, ScanArea{0.0, 0.0, 40.0, 24.0}, false),
           "film scanner");

    // Swift 쪽 noOriginDump 와 같은 내용이어야 한다(--mode 있음).
    vcheck("area.originNoLT", kColorOnly,
           makeOptions("sane-genesys:libusb:1:1", 3600, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, ScanArea{2.0, 0.0, 34.0, 24.0}, false),
           "");

    {
        auto o = makeOptions("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen, ColorMode::Color,
                             FilmType::ColorNegative, gFrame, false);
        o.brightnessAdjustment = 0.0;
        vcheck("bright.zeroNoRange", kDump, o, "film scanner");
        o.brightnessAdjustment = 5.0;
        vcheck("bright.fiveNoRange", kDump, o, "film scanner");
    }

    {
        auto o = makeOptions("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen, ColorMode::Color,
                             FilmType::ColorNegative, gFrame, false);
        o.hardwareExposureTime = 11000;
        vcheck("exposure.noOption", kDump, o, "film scanner");
    }

    {
        auto o = makeOptions("sane-genesys:libusb:1:2", 3600, BitDepth::Eight, ColorMode::Color,
                             FilmType::ColorNegative, gFrame, false);
        o.multiExposureEnabled = true;
        vcheck("mexp.eightBit", kDump, o, "film scanner");
    }
    {
        auto o = makeOptions("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen, ColorMode::Color,
                             FilmType::ColorNegative, gFrame, false);
        o.multiExposureEnabled = true;
        vcheck("mexp.noPlan", kDump, o, "film scanner");
    }

    vcheck("ir.none", kColorOnly,
           makeOptions("sane-x:libusb:1:1", 3600, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, gFrame, true),
           "");
    vcheck("ir.ok", kDump,
           makeOptions("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, gFrame, true),
           "film scanner");

        // =====================================================================
    // sane/args — makeScanimageArgs (배열 순서까지 비교)
    // =====================================================================

    using negaflow::sane::AcquisitionPass;

    const auto acheck = [&](const std::string& label, const char* dumpText,
                            const ScanOptions& o, const char* hint, const char* dev,
                            AcquisitionPass pass, std::optional<int> bright) {
        const OptionDump od{dumpText};
        const auto m = negaflow::sane::resolveMedia(od, o, hint);
        const auto a = negaflow::sane::makeScanimageArgs(dev, o, m, pass, bright);
        emit("A[" + label + "]", join(a, " "));
    };

    const ScanArea aFrame{0.0, 0.0, 36.0, 24.0};

    acheck("genesys.main", kDump,
           makeOptions("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, aFrame, false),
           "film scanner", "genesys:libusb:001:002", AcquisitionPass::Main, std::nullopt);
    acheck("genesys.ir", kDump,
           makeOptions("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, aFrame, true),
           "film scanner", "genesys:libusb:001:002", AcquisitionPass::Infrared, std::nullopt);
    acheck("genesys.preview", kDump,
           makeOptions("sane-genesys:libusb:1:2", 0, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, aFrame, false),
           "film scanner", "genesys:libusb:001:002", AcquisitionPass::Main, std::nullopt);

    {
        auto o = makeOptions("sane-genesys:libusb:1:2", 1200, BitDepth::Eight, ColorMode::Color,
                             FilmType::ColorNegative, aFrame, false);
        acheck("genesys.brightOverride", kDump, o, "film scanner", "genesys:libusb:001:002",
               AcquisitionPass::Main, 7);
        o.brightnessAdjustment = -12.5;
        acheck("genesys.brightDouble", kDump, o, "film scanner", "genesys:libusb:001:002",
               AcquisitionPass::Main, std::nullopt);
    }

    const char* kEpson2Args =
        "    --mode Lineart|Gray|Color [Color]\n"
        "    --source Flatbed|Transparency Unit|TPU8x10 [Flatbed]\n"
        "    --film-type Positive Film|Negative Film [Positive Film]\n"
        "    --color-correction None|User defined [None]\n"
        "    --gamma-correction Default|User defined (Gamma=1.0)|User defined (Gamma=1.8) [Default]\n"
        "    --resolution 50..12800dpi [50]\n"
        "    --depth 8|16 [16]\n"
        "    -l 0..215.9mm [0]\n"
        "    -t 0..297.18mm [0]\n"
        "    -x 0..215.9mm [215.9]\n"
        "    -y 0..297.18mm [297.18]";
    acheck("epson2.main", kEpson2Args,
           makeOptions("sane-epson2:libusb:1:5", 1200, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 23.5}, false),
           "flatbed scanner", "epson2:libusb:001:005", AcquisitionPass::Main, std::nullopt);

    const char* kCoolscan3Args =
        "    --depth 8|14 [8]\n"
        "    --negative[=(yes|no)] [no]\n"
        "    --resolution 4000dpi [4000]\n"
        "    -x 0..6000pel [6000]\n"
        "    -y 0..6000pel [6000]";
    acheck("coolscan3.main", kCoolscan3Args,
           makeOptions("sane-coolscan3:libusb:1:2", 4000, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, aFrame, false),
           "film scanner", "coolscan3:usb:libusb:001:002", AcquisitionPass::Main, std::nullopt);

    const char* kPieusbArgs =
        "    --mode Color|RGBI [Color]\n"
        "    --advance[=(yes|no)] [yes]\n"
        "    --resolution 3600dpi [3600]\n"
        "    -x 0..36mm [36]\n"
        "    -y 0..24mm [24]\n"
        "    --depth 16 [16]";
    acheck("pieusb.main", kPieusbArgs,
           makeOptions("sane-pieusb:libusb:2:4", 3600, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorPositive, aFrame, false),
           "slide scanner", "pieusb:libusb:002:004", AcquisitionPass::Main, std::nullopt);

    const char* kCorner =
        "    --mode Color [Color]\n"
        "    --depth 16 [16]\n"
        "    --resolution 4000dpi [4000]\n"
        "    --tl-x 0..6000pel [0]\n"
        "    --tl-y 0..6000pel [0]\n"
        "    --br-x 0..6000pel [6000]\n"
        "    --br-y 0..6000pel [6000]";
    acheck("corner.main", kCorner,
           makeOptions("sane-x:libusb:1:1", 4000, BitDepth::Sixteen, ColorMode::Color,
                       FilmType::ColorNegative, aFrame, false),
           "", "x:libusb:001:001", AcquisitionPass::Main, std::nullopt);

    {
        auto o = makeOptions("sane-x:libusb:1:1", 3600, BitDepth::Sixteen, ColorMode::Color,
                             FilmType::ColorNegative, aFrame, false);
        o.hardwareExposureTime = 14000;
        const char* kExp =
            "    --mode Color [Color]\n"
            "    --depth 16 [16]\n"
            "    --resolution 3600dpi [3600]\n"
            "    --scan-exposure-time 0..65535 [11000]\n"
            "    -x 0..36mm [36]\n"
            "    -y 0..24mm [24]";
        acheck("exposure.main", kExp, o, "", "x:libusb:001:001", AcquisitionPass::Main,
               std::nullopt);
    }

        // --- capability 재조회 / 덤프 재사용 판정 -------------------------------

    {
        const std::vector<std::tuple<std::string, std::string, std::string>> reuseCases{
            {"genesys.singleTP", "    --source Transparency Adapter [Transparency Adapter]\n",
             "genesys"},
            {"genesys.tpPlusIR",
             "    --source Transparency Adapter|Transparency Adapter Infrared [Transparency "
             "Adapter]\n",
             "genesys"},
            {"genesys.flatbedToo", "    --source Flatbed|Transparency Adapter [Flatbed]\n",
             "genesys"},
            {"epson2.singleTP", "    --source Transparency Unit [Transparency Unit]\n", "epson2"},
            {"genesys.reflectiveOnly", "    --source Flatbed [Flatbed]\n", "genesys"},
        };
        for (const auto& [label, dumpText, backend] : reuseCases) {
            emit("reuse[" + label + "]",
                 negaflow::sane::canReuseSinglePassOptionsDump(OptionDump{dumpText}, backend)
                     ? "true"
                     : "false");
        }
    }

    {
        const std::vector<std::tuple<std::string, std::string, std::string>> redumpCases{
            {"genesys",
             "    --source Flatbed|Transparency Adapter [Flatbed]\n"
             "    --mode Color|Gray [Color]\n    --depth 8|16 [16]\n",
             "genesys:libusb:001:002"},
            {"epson2.inactiveDepth",
             "    --source Flatbed|Transparency Unit [Flatbed]\n"
             "    --mode Lineart|Gray|Color [Lineart]\n    --depth 8|16 [inactive]\n"
             "    --color-correction None|User defined [None]\n"
             "    --gamma-correction Default|User defined (Gamma=1.0) [Default]\n",
             "epson2:libusb:001:005"},
            {"noop", "    --mode Color [Color]\n    --depth 16 [16]\n", "x:libusb:1:1"},
            {"coolscan3", "    --depth 8|14 [8]\n", "coolscan3:usb:libusb:001:002"},
        };
        for (const auto& [label, dumpText, dev] : redumpCases) {
            const auto a =
                negaflow::sane::capabilityRedumpArguments(OptionDump{dumpText}, dev);
            emit("redump[" + label + "]", a ? join(*a, " ") : std::string("<nil>"));
        }
    }

        // =====================================================================
    // process/progress
    // =====================================================================

    {
        const std::vector<std::pair<std::string, std::string>> samples{
            {"empty", ""},
            {"one", "Progress: 12.3%\n"},
            {"comma", "Progress: 45,6%\n"},
            {"many", "Progress: 1%\nProgress: 50%\nProgress: 99.9%\n"},
            {"paren", "Progress: (34/512)\n"},
            {"mixed", "Progress: (1/10)\nProgress: 25%\nProgress: (5/10)\n"},
            {"noColon", "progress 77%\n"},
            {"upper", "PROGRESS: 5%\n"},
            {"clamp", "Progress: 150%\n"},
            {"noise", "scanimage: rounded value of br-y from 23.5 to 24\nProgress: 3%\n"},
            {"truncated", "Progr"},
            {"threeDigits", "Progress: 100%\n"},
        };
        for (const auto& [label, text] : samples) {
            emit("prog.count[" + label + "]",
                 std::to_string(negaflow::process::progressRecordCount(text)));
            const auto f = negaflow::process::progressFraction(text);
            emit("prog.frac[" + label + "]", f ? swiftDouble(*f) : std::string("<nil>"));
        }
    }

    {
        const std::vector<std::pair<std::string, std::string>> samples{
            {"empty", ""},
            {"invalidArg", "scanimage: open of device x failed: Invalid argument"},
            {"busy", "scanimage: open of device x failed: Device busy"},
            {"noSuch", "No such device"},
            {"io", "I/O error"},
            {"denied", "Access to resource has been denied"},
            {"resourceBusy", "Resource busy"},
            {"notConnected", "Scanner not connected"},
            {"rounded", "scanimage: rounded value of resolution from 2000 to 2400"},
            {"ROUNDED", "ROUNDED VALUE OF x"},
            {"other", "something else entirely"},
        };
        for (const auto& [label, text] : samples) {
            emit("stale[" + label + "]",
                 negaflow::process::isStaleDeviceError(text) ? "true" : "false");
            emit("inexact[" + label + "]",
                 negaflow::process::containsInexactOptionWarning(text) ? "true" : "false");
        }
    }

    // =====================================================================
    // imaging/align — 정렬. 전부 Float 이므로 비트 패턴으로 비교한다.
    // 근거: windows_docs/04-imaging/numerical-parity.md §4
    // =====================================================================
    {
        using namespace negaflow::imaging;

        const std::vector<std::pair<std::string, float>> trustSamples{
            {"neg", -0.5f},      {"zero", 0.0f},       {"lo", 0.006f},
            {"loJust", 0.0061f}, {"loMid", 0.02f},     {"loEdge", 0.035f},
            {"loOver", 0.0351f}, {"mid", 0.5f},        {"hiEdge", 0.90f},
            {"hiMid", 0.94f},    {"hiTop", 0.985f},    {"hiJust", 0.9849f},
            {"one", 1.0f},       {"over", 1.5f},
        };
        for (const auto& [label, v] : trustSamples) {
            emit("align.trust[" + label + "]", fbits(exposureTrustWeight(v)));
        }

        const std::vector<std::tuple<std::string, float, float, float>> mixSamples{
            {"t0", 0.25f, 0.75f, 0.0f},    {"t1", 0.25f, 0.75f, 1.0f},
            {"half", 0.25f, 0.75f, 0.5f},  {"under", 0.25f, 0.75f, -0.3f},
            {"over", 0.25f, 0.75f, 1.7f},  {"third", 0.1f, 0.9f, 1.0f / 3.0f},
            {"desc", 0.9f, 0.1f, 0.37f},
        };
        for (const auto& [label, a, b, t] : mixSamples) {
            emit("align.mix[" + label + "]", fbits(mix(a, b, t)));
        }

        const std::vector<std::tuple<std::string, float, float, float>> stepSamples{
            {"below", 0.82f, 0.97f, 0.5f},   {"e0", 0.82f, 0.97f, 0.82f},
            {"mid", 0.82f, 0.97f, 0.9f},     {"e1", 0.82f, 0.97f, 0.97f},
            {"above", 0.82f, 0.97f, 1.0f},   {"lowBand", 0.010f, 0.045f, 0.02f},
            {"lowE0", 0.010f, 0.045f, 0.01f}, {"equalLt", 0.5f, 0.5f, 0.4f},
            {"equalEq", 0.5f, 0.5f, 0.5f},   {"equalGt", 0.5f, 0.5f, 0.6f},
            {"reversed", 0.97f, 0.82f, 0.9f},
        };
        for (const auto& [label, e0, e1, x] : stepSamples) {
            emit("align.step[" + label + "]", fbits(smoothstep(e0, e1, x)));
        }

        const std::vector<std::tuple<std::string, int, int, int, int, int>> srcSamples{
            {"inside", 4, 3, 1, 0, 0},   {"shift", 4, 3, 2, -2, -1}, {"left", 0, 0, 0, -1, 0},
            {"top", 0, 0, 0, 0, -1},     {"right", 7, 0, 0, 1, 0},   {"bottom", 0, 5, 0, 0, 1},
            {"corner", 7, 5, 2, 0, 0},
        };
        for (const auto& [label, x, y, ch, ox, oy] : srcSamples) {
            const auto i = alignedSourceIndex(x, y, ch, Offset{ox, oy}, 8, 6);
            emit("align.srcidx[" + label + "]", i ? std::to_string(*i) : std::string("<nil>"));
        }

        // estimateIntegerOffset — 정수 결과. 한 픽셀만 달라도 병합이 전부 달라진다.
        struct AlignCase {
            const char* label;
            int width;
            int height;
            std::uint32_t seed;
            int shiftX;
            int shiftY;
            std::uint32_t jitter;
        };
        const std::vector<AlignCase> alignCases{
            {"same", 80, 64, 7, 0, 0, 0},        // 개선 없음 → 0.85 게이트
            {"shiftX2", 80, 64, 7, 2, 0, 0},
            {"shiftY3", 80, 64, 7, 0, 3, 0},
            {"shiftXY", 80, 64, 7, -3, 5, 0},
            {"jitter", 80, 64, 7, 1, -2, 1234},  // 정렬되지 않는 노이즈 포함
            {"factor2", 192, 192, 11, 4, -6, 0}, // min(w,h)/96 = 2 → factor 2
            {"narrowW", 6, 40, 3, 1, 1, 0},      // dw <= 6 → (0,0)
            {"shortH", 40, 5, 3, 1, 1, 0},       // dh <= 6 → (0,0)
        };
        for (const auto& c : alignCases) {
            const auto reference = makeImage(c.width, c.height, c.seed, 0, 0, 0);
            const auto sample =
                makeImage(c.width, c.height, c.seed, c.shiftX, c.shiftY, c.jitter);
            const Offset o = estimateIntegerOffset(reference, sample, c.width, c.height);
            emit(std::string("align.offset[") + c.label + "]",
                 std::to_string(o.x) + "," + std::to_string(o.y));
        }

        {  // 평탄한 이미지 → 텍스처 가드가 (0,0) 으로 보낸다
            const auto flat = makeFlatImage(80, 64, 0.5f);
            const auto shifted = makeImage(80, 64, 7, 2, 2, 0);
            const Offset o = estimateIntegerOffset(flat, shifted, 80, 64);
            emit("align.offset[flatRef]", std::to_string(o.x) + "," + std::to_string(o.y));
        }

        // accumulateAligned — 누적 순서까지 같아야 한다.
        for (const auto& [label, ox, oy] : std::vector<std::tuple<std::string, int, int>>{
                 {"zero", 0, 0}, {"pos", 2, 1}, {"neg", -3, -2}, {"outX", 9, 0}}) {
            const int w = 8, h = 6;
            const auto sample = makeImage(w, h, 5, 0, 0, 0);
            std::vector<float> accumulator(static_cast<std::size_t>(w * h * 4), 0.0f);
            std::vector<float> counts(static_cast<std::size_t>(w * h), 0.0f);
            accumulateAligned(sample, Offset{ox, oy}, w, h, accumulator, counts);

            std::string countText;
            for (std::size_t i = 0; i < counts.size(); ++i) {
                if (i) countText += ",";
                countText += fbits(counts[i]);
            }
            emit("align.accum[" + label + "].counts", countText);

            float total = 0.0f;  // 인덱스 순 Float 누적 — 순서가 결과를 바꾼다
            for (float v : accumulator) total += v;
            emit("align.accum[" + label + "].sum", fbits(total));

            std::string headText;
            for (std::size_t i = 0; i < 12; ++i) {
                if (i) headText += ",";
                headText += fbits(accumulator[i]);
            }
            emit("align.accum[" + label + "].head", headText);
        }
    }

    // =====================================================================
    // imaging/merge — 다중 노출 병합. **P0 비트 동일 대상이다.**
    //
    // float 결과와 UInt16 결과를 **둘 다** 비교한다. 양자화가 절삭이라
    // 1 ULP 차이는 대개 같은 UInt16 으로 떨어져 UInt16 만 보면 놓친다.
    // 근거: windows_docs/04-imaging/numerical-parity.md §3.1, §3.4
    // =====================================================================
    {
        using namespace negaflow::imaging;

        const std::vector<std::pair<std::string, std::vector<int>>> refSamples{
            {"empty", {}},
            {"single", {14000}},
            {"plan3", {11000, 14000, 30000}},
            {"dupes", {11000, 11000, 14000, 30000}},       // 중복 제거 후 3개 → 14000
            {"reversed", {30000, 14000, 11000}},
            {"allSame", {5, 5, 5}},
            {"even4", {1, 2, 3, 4}},                        // 짝수 → 위쪽 중앙
            {"even6", {1, 2, 3, 4, 5, 6}},
            {"samples2", {11000, 11000, 14000, 14000, 30000, 30000}},
        };
        for (const auto& [label, times] : refSamples) {
            const auto r = negaflow::util::referenceExposureTime(times);
            emit("merge.ref[" + label + "]",
                 r ? std::to_string(*r) : std::string("<nil>"));
        }

        struct MergeCase {
            const char* label;
            int width;
            int height;
            std::uint32_t seed;
            std::vector<int> exposures;
            std::vector<std::pair<int, int>> shifts;  // 패스별 (dx, dy)
            bool dumpFloat;                           // float 결과까지 낼 것인가
        };
        const std::vector<MergeCase> mergeCases{
            {"basic", 16, 12, 21, {11000, 14000, 30000}, {{0, 0}, {0, 0}, {0, 0}}, true},
            {"shifted", 40, 30, 33, {11000, 14000, 30000}, {{0, 0}, {2, -1}, {-1, 3}}, false},
            {"samples2",
             16,
             12,
             21,
             {11000, 11000, 14000, 14000, 30000, 30000},
             {{0, 0}, {1, 0}, {0, 0}, {0, 1}, {0, 0}, {-1, 0}},
             false},
            {"singlePass", 16, 12, 21, {14000}, {{0, 0}}, true},
            {"noShort", 16, 12, 21, {14000, 30000}, {{0, 0}, {0, 0}}, false},
            {"noLong", 16, 12, 21, {11000, 14000}, {{0, 0}, {0, 0}}, false},
        };

        for (const auto& c : mergeCases) {
            std::vector<std::vector<float>> storage;
            storage.reserve(c.exposures.size());
            for (std::size_t p = 0; p < c.exposures.size(); ++p) {
                storage.push_back(makeExposureImage(c.width, c.height, c.seed, static_cast<int>(p),
                                                    c.shifts[p].first, c.shifts[p].second));
            }
            ImageList rendered;
            rendered.reserve(storage.size());
            for (const auto& s : storage) rendered.emplace_back(s);

            if (c.dumpFloat) {
                const auto reference = negaflow::util::referenceExposureTime(c.exposures);
                const auto f = alignedExposureNormalizedRGBAf(rendered, c.exposures,
                                                              reference.value_or(0), c.width,
                                                              c.height);
                emit(std::string("merge.float[") + c.label + "].failure",
                     f.failure ? std::string(failureMessage(*f.failure)) : std::string("<nil>"));
                for (int y = 0; y < c.height; ++y) {
                    std::string row;
                    for (int x = 0; x < c.width * 4; ++x) {
                        if (x) row += ",";
                        row += fbits(f.bitmap.pixels[static_cast<std::size_t>(y * c.width * 4 + x)]);
                    }
                    emit(std::string("merge.float[") + c.label + "].row" + std::to_string(y), row);
                }
            }

            const auto m = mergeHardwareExposureBitmap(rendered, c.exposures, c.width, c.height);
            emit(std::string("merge.u16[") + c.label + "].failure",
                 m.failure ? std::string(failureMessage(*m.failure)) : std::string("<nil>"));
            for (int y = 0; y < c.height; ++y) {
                std::string row;
                for (int x = 0; x < c.width * 3; ++x) {
                    if (x) row += ",";
                    row += std::to_string(m.bitmap.pixels[static_cast<std::size_t>(y * c.width * 3 + x)]);
                }
                emit(std::string("merge.u16[") + c.label + "].row" + std::to_string(y), row);
            }
        }

        {  // 평균 경로 — production 에서는 쓰이지 않지만 테스트가 지난다.
            const int w = 16, h = 12;
            std::vector<std::vector<float>> storage;
            for (int p = 0; p < 3; ++p) {
                storage.push_back(makeExposureImage(w, h, 21, p, p, -p));
            }
            ImageList rendered;
            for (const auto& s : storage) rendered.emplace_back(s);

            const auto a = averageMultiSampleBitmap(rendered, w, h);
            emit("merge.avg.failure",
                 a.failure ? std::string(failureMessage(*a.failure)) : std::string("<nil>"));
            for (int y = 0; y < h; ++y) {
                std::string row;
                for (int x = 0; x < w * 3; ++x) {
                    if (x) row += ",";
                    row += std::to_string(a.bitmap.pixels[static_cast<std::size_t>(y * w * 3 + x)]);
                }
                emit("merge.avg.row" + std::to_string(y), row);
            }
        }
    }

    // =====================================================================
    // imaging/tiff_io — macOS ImageIO 와의 **상호운용**.
    //
    // 여기서 비교하는 것은 파일 바이트가 아니라 **디코드된 픽셀**이다.
    // 바이트 순서(II vs MM)는 달라도 되고 실제로 다르다 — 호스트가
    // libtiff/WIC 로 읽으므로 순서는 투명하다.
    // 근거: windows_docs/04-imaging/numerical-parity.md §5 (N-2)
    //
    //   tiff.roundtrip.*  Swift 가 쓴 파일 → 우리가 읽는다
    //   tiff.cross.*      우리가 쓴 파일   → Swift 가 읽는다
    //
    // 양쪽이 같아야 "우리 산출물을 macOS 가 같게 읽고, macOS 산출물을 우리가
    // 같게 읽는다"가 성립한다.
    // =====================================================================
#ifdef NEGAFLOW_HAVE_LIBTIFF
    if (const char* tmp = std::getenv("PARITY_TMP")) {
        namespace fs = std::filesystem;
        using namespace negaflow::imaging;

        const int w = 6, h = 4;
        // 정규화의 경계와 그 이웃. 0/65535 는 양끝, 32767/32768 은 0.5 근처다.
        const std::vector<std::uint16_t> marks{0, 1, 2, 255, 256, 32767, 32768, 65534, 65535};
        std::vector<std::uint16_t> pixels(static_cast<std::size_t>(w * h * 3), 0);
        for (int y = 0; y < h; ++y) {
            for (int x = 0; x < w; ++x) {
                for (int c = 0; c < 3; ++c) {
                    // 행마다 패턴을 민다. **모든 행이 같으면 위아래 뒤집힘도
                    // 행 stride 오류도 잡지 못한다** — 어느 행을 읽어도 값이
                    // 같아서 diff 가 통과해 버린다.
                    const std::size_t k =
                        (static_cast<std::size_t>(x * 3 + c) + static_cast<std::size_t>(y) * 5) %
                        marks.size();
                    pixels[static_cast<std::size_t>((y * w + x) * 3 + c)] = marks[k];
                }
            }
        }

        const fs::path cppFile = fs::path(tmp) / "cpp_write.tiff";
        const fs::path swiftFile = fs::path(tmp) / "swift_write.tiff";

        // 우리가 쓰고 우리가 읽는다. Swift 쪽은 이 **같은 파일**을 읽는다.
        const bool wrote = tiffio::writeRGB16TIFF(pixels, w, h, cppFile);
        emit("tiff.cross.wrote", wrote ? "true" : "false");
        const auto mine = tiffio::loadScannerTIFF(cppFile);
        emit("tiff.cross.loaded", mine ? "true" : "false");
        if (mine) {
            emit("tiff.cross.size", std::to_string(mine->width) + "x" + std::to_string(mine->height));
            for (int y = 0; y < h; ++y) {
                std::string row;
                for (int x = 0; x < w * 4; ++x) {
                    if (x) row += ",";
                    row += fbits(mine->pixels[static_cast<std::size_t>(y * w * 4 + x)]);
                }
                emit("tiff.cross.row" + std::to_string(y), row);
            }
        }

        // Swift 가 ImageIO 로 쓴 파일을 우리가 libtiff 로 읽는다.
        // (스크립트가 swift_dump 를 먼저 돌려 이 파일을 만들어 둔다.)
        const auto theirs = tiffio::loadScannerTIFF(swiftFile);
        emit("tiff.roundtrip.loaded", theirs ? "true" : "false");
        if (theirs) {
            emit("tiff.roundtrip.size",
                 std::to_string(theirs->width) + "x" + std::to_string(theirs->height));
            for (int y = 0; y < h; ++y) {
                std::string row;
                for (int x = 0; x < w * 4; ++x) {
                    if (x) row += ",";
                    row += fbits(theirs->pixels[static_cast<std::size_t>(y * w * 4 + x)]);
                }
                emit("tiff.roundtrip.row" + std::to_string(y), row);
            }
        }

        // 우리 산출물의 태그. **ICC 프로파일이 붙으면 본체가 감마 도메인으로
        // 읽어 색이 무너진다** — 스캔은 성공하므로 가장 늦게 발견된다.
        if (const auto tags = tiffio::readTags(cppFile)) {
            emit("tiff.cross.tags",
                 "bps=" + std::to_string(tags->bitsPerSample) +
                     " spp=" + std::to_string(tags->samplesPerPixel) +
                     " photo=" + std::to_string(tags->photometric) +
                     " planar=" + std::to_string(tags->planarConfig) +
                     " pages=" + std::to_string(tags->directoryCount) +
                     " icc=" + (tags->hasIccProfile ? "1" : "0") +
                     " transfer=" + (tags->hasTransferFunction ? "1" : "0"));
        }
    }
#endif

    // =====================================================================
    // wire/request — 1단계 검증. **가드 순서와 문구가 계약이다.**
    //
    // 11개 중 9번(outputPath)만 플랫폼별로 갈리므로, 여기서는 macOS 와 같은
    // POSIX 정책으로 돌려 **나머지 10개를 끝까지** 대조한다. Windows 정책은
    // 단위 테스트가 exact-option-contract §3.1 표를 항목별로 고정한다.
    // =====================================================================
    {
        using negaflow::wire::PathPolicy;
        using negaflow::wire::ScanRequestV2;

        // 통과하는 기준 요청. 각 케이스가 필요한 필드만 바꾼다.
        const auto base = [] {
            ScanRequestV2 r;
            r.protocolVersion = 2;
            r.deviceID = "genesys:libusb:001:002";
            r.resolutionDPI = 3600;
            r.bitDepth = 16;
            r.colorMode = "color";
            r.filmType = "colorNegative";
            r.preview = false;
            r.multiExposure = false;
            r.infrared = false;
            r.scanArea = negaflow::sane::ScanArea{0.0, 0.0, 36.0, 24.0};
            r.outputRawTIFF = true;
            r.outputPath = "/tmp/negaflow/frame.tiff";
            return r;
        }();

        std::vector<std::pair<std::string, ScanRequestV2>> cases;
        auto add = [&](const std::string& label, auto mutate) {
            ScanRequestV2 r = base;
            mutate(r);
            cases.emplace_back(label, r);
        };

        add("ok", [](ScanRequestV2&) {});
        add("v1", [](ScanRequestV2& r) { r.protocolVersion = 1; });
        add("v3", [](ScanRequestV2& r) { r.protocolVersion = 3; });
        add("emptyDevice", [](ScanRequestV2& r) { r.deviceID = ""; });
        add("blankDevice", [](ScanRequestV2& r) { r.deviceID = "   \t "; });
        add("depth12", [](ScanRequestV2& r) { r.bitDepth = 12; });
        add("depth0", [](ScanRequestV2& r) { r.bitDepth = 0; });
        add("depth8", [](ScanRequestV2& r) { r.bitDepth = 8; });
        add("modeLineart", [](ScanRequestV2& r) { r.colorMode = "lineart"; });
        add("modeInfrared", [](ScanRequestV2& r) { r.colorMode = "infrared"; });
        add("modeBogus", [](ScanRequestV2& r) { r.colorMode = "sepia"; });
        add("modeGray", [](ScanRequestV2& r) { r.colorMode = "gray"; });
        add("filmBogus", [](ScanRequestV2& r) { r.filmType = "slide"; });
        add("filmBwPositive", [](ScanRequestV2& r) { r.filmType = "bwPositive"; });
        add("areaNegOrigin", [](ScanRequestV2& r) { r.scanArea.originXMM = -1.0; });
        add("areaZeroWidth", [](ScanRequestV2& r) { r.scanArea.widthMM = 0.0; });
        add("areaNegHeight", [](ScanRequestV2& r) { r.scanArea.heightMM = -5.0; });
        add("expZero", [](ScanRequestV2& r) { r.hardwareExposureTime = 0; });
        add("expNeg", [](ScanRequestV2& r) { r.hardwareExposureTime = -1; });
        add("expOk", [](ScanRequestV2& r) { r.hardwareExposureTime = 14000; });
        add("brightOk", [](ScanRequestV2& r) { r.brightnessAdjustment = 12.5; });
        add("pathRelative", [](ScanRequestV2& r) { r.outputPath = "tmp/frame.tiff"; });
        add("pathDotDot", [](ScanRequestV2& r) { r.outputPath = "/tmp/../frame.tiff"; });
        add("pathDot", [](ScanRequestV2& r) { r.outputPath = "/tmp/./frame.tiff"; });
        add("pathDouble", [](ScanRequestV2& r) { r.outputPath = "/tmp//frame.tiff"; });
        add("pathTrailing", [](ScanRequestV2& r) { r.outputPath = "/tmp/frame/"; });
        add("pathEmpty", [](ScanRequestV2& r) { r.outputPath = ""; });
        // **macOS 는 경로 탈출을 막지 못한다.** 실측으로 확인했고, 파리티가
        // 그 사실을 고정한다. Windows 정책은 이것을 거부한다(§3.2).
        add("pathEscape", [](ScanRequestV2& r) { r.outputPath = "/tmp/a/../../../etc/passwd"; });
        add("pathRoot", [](ScanRequestV2& r) { r.outputPath = "/"; });
        add("pathDoubleLead", [](ScanRequestV2& r) { r.outputPath = "//tmp/frame.tiff"; });
        add("tokenOk", [](ScanRequestV2& r) { r.capabilityToken = std::string(1024, 'a'); });
        add("tokenLimit", [](ScanRequestV2& r) { r.capabilityToken = std::string(1048576, 'a'); });
        add("tokenOver", [](ScanRequestV2& r) { r.capabilityToken = std::string(1048577, 'a'); });
        add("previewOk", [](ScanRequestV2& r) {
            r.preview = true;
            r.resolutionDPI = 0;
            r.outputRawTIFF = false;
        });
        add("previewDPI", [](ScanRequestV2& r) {
            r.preview = true;
            r.resolutionDPI = 300;
            r.outputRawTIFF = false;
        });
        add("previewIR", [](ScanRequestV2& r) {
            r.preview = true;
            r.resolutionDPI = 0;
            r.infrared = true;
            r.outputRawTIFF = false;
        });
        add("previewRaw", [](ScanRequestV2& r) {
            r.preview = true;
            r.resolutionDPI = 0;
            r.outputRawTIFF = true;
        });
        add("fullZeroDPI", [](ScanRequestV2& r) { r.resolutionDPI = 0; });
        add("fullNoRaw", [](ScanRequestV2& r) { r.outputRawTIFF = false; });
        add("fullMultiPlusExp", [](ScanRequestV2& r) {
            r.multiExposure = true;
            r.hardwareExposureTime = 14000;
        });
        add("fullMultiOnly", [](ScanRequestV2& r) { r.multiExposure = true; });
        // 여러 조건이 동시에 틀리면 **먼저 걸리는 것**이 나와야 한다.
        add("depthBeforeMode", [](ScanRequestV2& r) {
            r.bitDepth = 12;
            r.colorMode = "sepia";
        });
        add("modeBeforeFilm", [](ScanRequestV2& r) {
            r.colorMode = "sepia";
            r.filmType = "slide";
        });
        add("areaBeforePath", [](ScanRequestV2& r) {
            r.scanArea.widthMM = 0.0;
            r.outputPath = "relative.tiff";
        });
        add("pathBeforeToken", [](ScanRequestV2& r) {
            r.outputPath = "relative.tiff";
            r.capabilityToken = std::string(1048577, 'a');
        });

        for (const auto& [label, request] : cases) {
            negaflow::sane::ScanOptions options;
            const auto result = negaflow::wire::validateScanRequest(
                request, PathPolicy::PosixAbsolute, &options);
            emit("req[" + label + "]", result ? result->message : std::string("<ok>"));
        }
    }

    // =====================================================================
    // wire/json + wire/event — **키를 정렬해 바이트로 비교한다.**
    //
    // Swift JSONEncoder 의 키 순서는 해시 기반이라 안정적이지 않다(§4.2.3).
    // 그래서 양쪽 다 정렬 출력으로 돌린다 — 그러면 이스케이프·수 표기·
    // 생략 vs null 이 전부 한 번에 검증된다.
    // **실제 wire 출력은 정렬하지 않는다.** 정렬은 여기서만 쓴다.
    // =====================================================================
    {
        using negaflow::wire::AppliedScanOptionsV2;
        using negaflow::wire::JsonValue;
        using negaflow::wire::KeyOrder;
        using negaflow::wire::ScanEventV2;

        auto dumpSorted = [](const std::string& key, const JsonValue& v) {
            const auto text = negaflow::wire::writeJson(v, KeyOrder::Sorted);
            emit(key, text ? *text : std::string("<encode failed>"));
        };

        const std::string kRequestID = "3F2504E0-4F89-11D3-9A0C-0305E82C3301";

        // ① 옵셔널이 전부 비었을 때 — 키가 4개만 나와야 한다.
        {
            ScanEventV2 e;
            e.type = "started";
            e.requestID = kRequestID;
            e.sequence = 0;
            dumpSorted("json.event[bare]", negaflow::wire::encodeScanEvent(e));
        }
        // ② 진행률.
        {
            ScanEventV2 e;
            e.type = "progress";
            e.requestID = kRequestID;
            e.sequence = 7;
            e.phase = std::string("scanning");
            e.fraction = 0.4213;
            dumpSorted("json.event[progress]", negaflow::wire::encodeScanEvent(e));
        }
        // ③ 오류 — **한국어가 UTF-8 그대로 나가야 한다.** \uXXXX 가 아니다.
        {
            ScanEventV2 e;
            e.type = "failed";
            e.requestID = kRequestID;
            e.sequence = 3;
            e.message = std::string("요청 resolution을 정확히 적용할 수 없습니다.");
            dumpSorted("json.event[korean]", negaflow::wire::encodeScanEvent(e));
        }
        // ④ Windows 경로 — 역슬래시 이스케이프. `/` 는 이스케이프하지 않는다.
        {
            ScanEventV2 e;
            e.type = "completed";
            e.requestID = kRequestID;
            e.sequence = 12;
            e.path = std::string("C:\\Users\\me\\AppData\\Local\\Temp\\a b\\frame.tiff");
            e.irPath = std::string("/tmp/x.ir.tiff");
            e.width = 10200;
            e.height = 6800;
            e.hasInfrared = true;
            dumpSorted("json.event[paths]", negaflow::wire::encodeScanEvent(e));
        }
        // ⑤ 경고 배열 — **순서가 의미다.**
        {
            ScanEventV2 e;
            e.type = "completed";
            e.requestID = kRequestID;
            e.sequence = 5;
            e.warnings = std::vector<std::string>{"zebra", "alpha", "middle"};
            dumpSorted("json.event[warnings]", negaflow::wire::encodeScanEvent(e));
        }
        // ⑥ 빈 배열은 nil 이 아니다 — 키가 나와야 한다.
        {
            ScanEventV2 e;
            e.type = "completed";
            e.requestID = kRequestID;
            e.sequence = 6;
            e.warnings = std::vector<std::string>{};
            dumpSorted("json.event[emptyWarnings]", negaflow::wire::encodeScanEvent(e));
        }
        // ⑦ appliedOptions — **12키가 전부 나오고 셋은 null 이다.**
        {
            AppliedScanOptionsV2 a;
            a.deviceID = "genesys:libusb:001:002";
            a.resolutionDPI = 3600;
            a.bitDepth = 16;
            a.colorMode = "color";
            a.filmType = "colorNegative";
            a.scanArea = negaflow::sane::ScanArea{0.0, 0.0, 36.33, 24.0};
            a.infrared = false;
            a.multiExposure = false;
            a.outputRawTIFF = true;

            ScanEventV2 e;
            e.type = "completed";
            e.requestID = kRequestID;
            e.sequence = 20;
            e.appliedOptions = a;
            dumpSorted("json.event[appliedNil]", negaflow::wire::encodeScanEvent(e));
        }
        // ⑧ 같은 것을 값으로 채운 경우.
        {
            AppliedScanOptionsV2 a;
            a.deviceID = "epson2:libusb:002:003";
            a.resolutionDPI = 2400;
            a.bitDepth = 8;
            a.colorMode = "gray";
            a.filmType = "bwNegative";
            a.scanArea = negaflow::sane::ScanArea{1.5, 2.25, 36.33, 44.25};
            a.infrared = true;
            a.multiExposure = true;
            a.hardwareExposureTime = 14000;
            a.brightnessAdjustment = -12.5;
            a.contrastAdjustment = 0.0;
            a.outputRawTIFF = false;

            ScanEventV2 e;
            e.type = "completed";
            e.requestID = kRequestID;
            e.sequence = 21;
            e.appliedOptions = a;
            dumpSorted("json.event[appliedFull]", negaflow::wire::encodeScanEvent(e));
        }
        // ⑨ 수 표기 — 정수에 소수점이 붙으면 안 되고, 실수는 최단 왕복이어야 한다.
        {
            JsonValue j = JsonValue::object();
            j.set("int", JsonValue::integer(3600));
            j.set("intZero", JsonValue::integer(0));
            j.set("intNeg", JsonValue::integer(-7));
            j.set("big", JsonValue::integer(9007199254740991LL));
            j.set("d1", JsonValue::number(36.33));
            j.set("d2", JsonValue::number(0.1));
            j.set("d3", JsonValue::number(1.0));
            j.set("d4", JsonValue::number(-0.5));
            j.set("d5", JsonValue::number(0.4213));
            j.set("d6", JsonValue::number(1.0 / 3.0));
            dumpSorted("json.numbers", j);
        }
        // ⑩ 이스케이프.
        {
            JsonValue j = JsonValue::object();
            j.set("quote", JsonValue::string("say \"hi\""));
            j.set("backslash", JsonValue::string("C:\\a\\b"));
            j.set("slash", JsonValue::string("a/b/c"));
            j.set("newline", JsonValue::string("a\nb\tc\rd"));
            j.set("control", JsonValue::string(std::string("a\x01" "\x1f" "b")));
            j.set("korean", JsonValue::string("스캐너 오류"));
            j.set("emoji", JsonValue::string("필름 🎞"));
            dumpSorted("json.escapes", j);
        }
    }

    // =====================================================================
    // wire/protocol — detect / capabilities 응답. **전부 "생략" 쪽이다.**
    // 정렬 출력으로 바이트 비교한다.
    // =====================================================================
    {
        using negaflow::wire::KeyOrder;
        using negaflow::wire::PluginCapabilities;
        using negaflow::wire::PluginDevice;

        auto dumpSorted = [](const std::string& key, const negaflow::wire::JsonValue& v) {
            const auto text = negaflow::wire::writeJson(v, KeyOrder::Sorted);
            emit(key, text ? *text : std::string("<encode failed>"));
        };

        // ① 옵셔널이 전부 빈 장치 — 키가 4개만 나와야 한다.
        {
            PluginDevice d;
            d.id = "sane-genesys:libusb:001:002";
            d.displayName = "Plustek OpticFilm 8100";
            d.vendor = "Plustek";
            d.model = "OpticFilm 8100";
            dumpSorted("proto.device[bare]", negaflow::wire::encodeDevice(d));
        }
        // ② 실측 예시(wire-contract §4.2.1)와 같은 모양 — nil 3개는 **생략**이다.
        {
            PluginDevice d;
            d.id = "sane-genesys:libusb:001:002";
            d.displayName = "Plustek OpticFilm 8100";
            d.vendor = "Plustek";
            d.model = "OpticFilm 8100";
            d.connectionType = std::string("usb");
            d.verifiedStatus = std::string("compatibleTarget");
            d.driverVersion = std::string("genesys (SANE)");
            dumpSorted("proto.device[measured]", negaflow::wire::encodeDevice(d));
        }
        // ③ 전부 채운 장치.
        {
            PluginDevice d;
            d.id = "epson2:libusb:002:003";
            d.displayName = "Epson Perfection V850";
            d.vendor = "Epson";
            d.model = "Perfection V850";
            d.connectionType = std::string("usb");
            d.usbVendorID = std::string("0x04b8");
            d.usbProductID = std::string("0x014a");
            d.serialNumber = std::string("SN/12345");
            d.verifiedStatus = std::string("untested");
            d.driverVersion = std::string("epson2 (SANE)");
            dumpSorted("proto.device[full]", negaflow::wire::encodeDevice(d));
        }
        // ④ detect 응답 — **배열 순서는 의미다.**
        {
            PluginDevice a;
            a.id = "zebra";
            a.displayName = "Z";
            a.vendor = "Z";
            a.model = "Z";
            PluginDevice b;
            b.id = "alpha";
            b.displayName = "A";
            b.vendor = "A";
            b.model = "A";
            dumpSorted("proto.detect[two]",
                       negaflow::wire::encodeDetectResponse(std::vector<PluginDevice>{a, b}));
            dumpSorted("proto.detect[empty]",
                       negaflow::wire::encodeDetectResponse(std::vector<PluginDevice>{}));
        }
        // ⑤ 능력 — 필수 3키만.
        {
            PluginCapabilities c;
            c.resolutionsDPI = {600, 1200, 2400, 3600, 7200};
            c.modes = {"color", "gray"};
            c.bitDepths = {8, 16};
            dumpSorted("proto.caps[minimal]", negaflow::wire::encodeCapabilities(c));
        }
        // ⑥ 빈 배열도 키가 나온다 — 옵셔널이 아니기 때문이다.
        {
            PluginCapabilities c;
            dumpSorted("proto.caps[emptyRequired]", negaflow::wire::encodeCapabilities(c));
        }
        // ⑦ 범위 — **step 이 없으면 키가 없다.**
        {
            PluginCapabilities c;
            c.resolutionsDPI = {3600};
            c.modes = {"color"};
            c.bitDepths = {16};
            c.brightnessRange = negaflow::util::OptionRange{-100.0, 100.0, 1.0};
            c.scanWidthRange = negaflow::util::OptionRange{0.0, 36.33, std::nullopt};
            dumpSorted("proto.caps[ranges]", negaflow::wire::encodeCapabilities(c));
        }
        // ⑧ 빈 딕셔너리는 nil 이 아니다 — `{}` 가 나와야 한다.
        {
            PluginCapabilities c;
            c.resolutionsDPI = {3600};
            c.modes = {"color"};
            c.bitDepths = {16};
            c.disabledReasons = std::vector<std::pair<std::string, std::string>>{};
            dumpSorted("proto.caps[emptyReasons]", negaflow::wire::encodeCapabilities(c));
        }
        // ⑨ 전부 채운 능력.
        {
            PluginCapabilities c;
            c.resolutionsDPI = {600, 3600};
            c.modes = {"color", "gray"};
            c.bitDepths = {8, 16};
            c.sourceModes = std::vector<std::string>{"Transparency Adapter"};
            c.transparencyModes = std::vector<std::string>{"Transparency Adapter Infrared"};
            c.supportsPreview = true;
            c.supportsTransparency = true;
            c.supportsInfrared = false;
            c.supportsMultiExposure = false;
            c.supportsScanArea = true;
            c.supportsPositionedScanArea = true;
            c.brightnessRange = negaflow::util::OptionRange{-100.0, 100.0, 1.0};
            c.contrastRange = negaflow::util::OptionRange{-100.0, 100.0, 1.0};
            c.hardwareExposureRange = negaflow::util::OptionRange{1000.0, 60000.0, 1.0};
            c.scanOriginXRange = negaflow::util::OptionRange{0.0, 36.33, std::nullopt};
            c.scanOriginYRange = negaflow::util::OptionRange{0.0, 44.25, std::nullopt};
            c.scanWidthRange = negaflow::util::OptionRange{0.0, 36.33, std::nullopt};
            c.scanHeightRange = negaflow::util::OptionRange{0.0, 44.25, std::nullopt};
            c.disabledReasons = std::vector<std::pair<std::string, std::string>>{
                {"infrared", "이 장치는 IR 채널을 노출하지 않습니다."},
                {"multiExposure", "scan-exposure-time 옵션이 없습니다."}};
            c.minScanAreaWidthMM = 1.0;
            c.minScanAreaHeightMM = 1.0;
            c.minScanAreaOriginXMM = 0.0;
            c.minScanAreaOriginYMM = 0.0;
            c.maxScanAreaWidthMM = 36.33;
            c.maxScanAreaHeightMM = 44.25;
            c.maxScanAreaOriginXMM = 0.0;
            c.maxScanAreaOriginYMM = 0.0;
            c.scanAreaUnit = std::string("millimeter");
            c.outputFormats = std::vector<std::string>{"tiff"};
            c.capabilityToken = std::string("eyJhIjoxfQ==");
            dumpSorted("proto.caps[full]", negaflow::wire::encodeCapabilities(c));
        }
    }

#ifdef NEGAFLOW_HAVE_RAPIDJSON
    // =====================================================================
    // wire/parse — 요청 JSON 디코딩
    //
    // 대조하는 것은 **수락/거부 판정과 디코드된 값**이지 오류 문구가 아니다.
    // macOS 는 모든 디코드 실패를 `try?` 로 버리고 한 문장만 내보낸다.
    //
    // 상한은 `swiftEquivalent()` 를 쓴다. 제품 상한(4 MiB·깊이 32·중복 거부)은
    // macOS 에 대응물이 없어 여기서 대조할 수 없다 — 단위 테스트가 고정한다.
    //
    // **corpus 를 두 파일에 두 번 적는다.** 그래서 문서의 길이와 FNV-1a 를
    // 함께 찍는다. 한쪽 corpus 만 고치면 판정이 우연히 같아도 여기서 갈린다.
    //
    // 아래 둘은 **의도한 divergence 라 corpus 에 없다**(parse.h 참조):
    //   resolutionDPI 2147483648   Swift Int 은 64비트, 우리 필드는 int
    //   brightnessAdjustment 0e999 RapidJSON 토큰화가 지수를 거부한다
    // =====================================================================
    {
        struct Field {
            const char* key;
            const char* value;
        };
        // **Swift 구조체 선언 순서 그대로다.**
        static const Field kBase[] = {
            {"protocolVersion", "2"},
            {"requestID", "\"3F2504E0-4F89-11D3-9A0C-0305E82C3301\""},
            {"deviceID", "\"genesys:libusb:001:002\""},
            {"resolutionDPI", "3600"},
            {"bitDepth", "16"},
            {"colorMode", "\"color\""},
            {"filmType", "\"colorNegative\""},
            {"preview", "false"},
            {"multiExposure", "false"},
            {"infrared", "false"},
            {"scanArea", "{\"originXMM\":1,\"originYMM\":2.5,\"widthMM\":36.33,\"heightMM\":24.25}"},
            {"outputRawTIFF", "true"},
            {"outputPath", "\"/tmp/negaflow/frame.tiff\""},
        };

        const auto build = [&](const std::string& drop, const std::string& extra) {
            std::string out = "{";
            bool first = true;
            for (const auto& f : kBase) {
                if (!drop.empty() && drop == f.key) continue;
                if (!first) out += ',';
                first = false;
                out += '"';
                out += f.key;
                out += "\":";
                out += f.value;
            }
            if (!extra.empty()) {
                if (!first) out += ',';
                out += extra;
            }
            out += '}';
            return out;
        };

        const auto fnv1a = [](const std::string& s) {
            std::uint32_t h = 2166136261u;
            for (const unsigned char c : s) {
                h ^= c;
                h *= 16777619u;
            }
            return h;
        };

        // **10진 표기가 아니라 비트 패턴을 찍는다.** 표기를 맞추려다 파리티가
        // 포매팅 차이로 터지는 것을 막고, 1 ULP 차이는 그대로 드러난다.
        const auto bits = [](double d) {
            std::uint64_t u = 0;
            std::memcpy(&u, &d, sizeof u);
            char buf[32];
            std::snprintf(buf, sizeof buf, "%016llx", static_cast<unsigned long long>(u));
            return std::string(buf);
        };

        // requestID 는 제품에선 원문 반사지만(D-12) macOS 는 대문자로 재직렬화한다.
        // 그 차이는 여기 대조 대상이 아니므로 양쪽을 대문자로 맞춘다 —
        // 확인하려는 것은 **어느 UUID 를 받아들였는가**다.
        const auto upperUuid = [](std::string s) {
            for (char& c : s) {
                if (c >= 'a' && c <= 'f') c = static_cast<char>(c - 'a' + 'A');
            }
            return s;
        };

        // `deviceID` 는 **UTF-8 바이트를 16진수로** 찍는다. corpus 에 NUL
        // 이스케이프와 한글과 이모지가 들어 있는데, `printf("%s")` 는 NUL 에서
        // 잘린다 — 하네스가 값을 감추면 파리티가 무의미해진다.
        const auto hexBytes = [](const std::string& s) {
            std::string out;
            char buf[4];
            for (const unsigned char c : s) {
                std::snprintf(buf, sizeof buf, "%02x", c);
                out += buf;
            }
            return out;
        };

        struct Case {
            const char* label;
            const char* drop;
            const char* extra;
            const char* raw;  // 있으면 문서를 그대로 쓴다
        };
        static const Case kCases[] = {
            {"baseline", "", "", nullptr},
            {"unknown-key", "", "\"futureField\":123", nullptr},
            {"unknown-nested", "", "\"futureField\":{\"a\":[1,2,{\"b\":null}]}", nullptr},
            {"bright-null", "", "\"brightnessAdjustment\":null", nullptr},
            {"bright-value", "", "\"brightnessAdjustment\":0.25", nullptr},
            {"bright-int", "", "\"brightnessAdjustment\":1", nullptr},
            {"bright-negative", "", "\"brightnessAdjustment\":-12.5", nullptr},
            {"bright-subnormal", "", "\"brightnessAdjustment\":4.9e-324", nullptr},
            {"bright-underflow", "", "\"brightnessAdjustment\":1e-324", nullptr},
            {"bright-overflow", "", "\"brightnessAdjustment\":1e309", nullptr},
            {"bright-string", "", "\"brightnessAdjustment\":\"0.25\"", nullptr},
            {"bright-bool", "", "\"brightnessAdjustment\":true", nullptr},
            {"contrast-value", "", "\"contrastAdjustment\":-100", nullptr},
            {"hw-null", "", "\"hardwareExposureTime\":null", nullptr},
            {"hw-value", "", "\"hardwareExposureTime\":20000", nullptr},
            {"tok-null", "", "\"capabilityToken\":null", nullptr},
            {"tok-empty", "", "\"capabilityToken\":\"\"", nullptr},
            {"tok-value", "", "\"capabilityToken\":\"eyJhIjoxfQ==\"", nullptr},
            {"drop-deviceID", "deviceID", "", nullptr},
            {"drop-scanArea", "scanArea", "", nullptr},
            {"drop-outputPath", "outputPath", "", nullptr},
            {"null-deviceID", "deviceID", "\"deviceID\":null", nullptr},
            {"null-bitDepth", "bitDepth", "\"bitDepth\":null", nullptr},
            {"null-preview", "preview", "\"preview\":null", nullptr},
            {"dup-bitDepth", "", "\"bitDepth\":8", nullptr},
            {"dup-deviceID", "", "\"deviceID\":\"LAST\"", nullptr},
            {"dup-bright", "", "\"brightnessAdjustment\":0.5,\"brightnessAdjustment\":null", nullptr},
            {"depth-double-exact", "bitDepth", "\"bitDepth\":16.0", nullptr},
            {"depth-exponent", "bitDepth", "\"bitDepth\":1.6e1", nullptr},
            {"depth-frac", "bitDepth", "\"bitDepth\":16.5", nullptr},
            {"depth-string", "bitDepth", "\"bitDepth\":\"16\"", nullptr},
            {"dpi-int32max", "resolutionDPI", "\"resolutionDPI\":2147483647", nullptr},
            {"dpi-negative", "resolutionDPI", "\"resolutionDPI\":-1200", nullptr},
            {"dpi-minus-zero", "resolutionDPI", "\"resolutionDPI\":-0", nullptr},
            {"dpi-int64-over", "resolutionDPI", "\"resolutionDPI\":9223372036854775808", nullptr},
            {"preview-number", "preview", "\"preview\":1", nullptr},
            {"preview-string", "preview", "\"preview\":\"true\"", nullptr},
            {"mode-number", "colorMode", "\"colorMode\":3", nullptr},
            {"area-origin-absent", "scanArea",
             "\"scanArea\":{\"widthMM\":36.33,\"heightMM\":24.25}", nullptr},
            {"area-origin-null", "scanArea",
             "\"scanArea\":{\"originXMM\":null,\"originYMM\":null,\"widthMM\":36.33,\"heightMM\":24.25}",
             nullptr},
            {"area-width-absent", "scanArea", "\"scanArea\":{\"heightMM\":24.25}", nullptr},
            {"area-width-null", "scanArea",
             "\"scanArea\":{\"widthMM\":null,\"heightMM\":24.25}", nullptr},
            {"area-unknown-key", "scanArea",
             "\"scanArea\":{\"widthMM\":36.33,\"heightMM\":24.25,\"zzz\":1}", nullptr},
            {"area-dup-width", "scanArea",
             "\"scanArea\":{\"widthMM\":36.33,\"heightMM\":24.25,\"widthMM\":99}", nullptr},
            {"area-not-object", "scanArea", "\"scanArea\":42", nullptr},
            {"area-int-values", "scanArea",
             "\"scanArea\":{\"widthMM\":36,\"heightMM\":24}", nullptr},
            {"uuid-lower", "requestID",
             "\"requestID\":\"3f2504e0-4f89-11d3-9a0c-0305e82c3301\"", nullptr},
            {"uuid-mixed", "requestID",
             "\"requestID\":\"3F2504e0-4f89-11D3-9a0C-0305e82C3301\"", nullptr},
            {"uuid-nil", "requestID",
             "\"requestID\":\"00000000-0000-0000-0000-000000000000\"", nullptr},
            {"uuid-braces", "requestID",
             "\"requestID\":\"{3F2504E0-4F89-11D3-9A0C-0305E82C3301}\"", nullptr},
            {"uuid-nohyphen", "requestID",
             "\"requestID\":\"3F2504E04F8911D39A0C0305E82C3301\"", nullptr},
            {"uuid-short", "requestID",
             "\"requestID\":\"3F2504E0-4F89-11D3-9A0C-0305E82C330\"", nullptr},
            {"uuid-urn", "requestID",
             "\"requestID\":\"urn:uuid:3F2504E0-4F89-11D3-9A0C-0305E82C3301\"", nullptr},
            {"escape-solidus", "deviceID", "\"deviceID\":\"a\\/b\"", nullptr},
            {"escape-unicode", "deviceID", "\"deviceID\":\"\\uD55C\\uAE00\"", nullptr},
            {"escape-nul", "deviceID", "\"deviceID\":\"a\\u0000b\"", nullptr},
            {"escape-surrogate-pair", "deviceID", "\"deviceID\":\"\\uD83D\\uDE00\"", nullptr},
            {"escape-bad", "deviceID", "\"deviceID\":\"a\\xb\"", nullptr},
            {"escape-lone-surrogate", "deviceID", "\"deviceID\":\"\\uD800\"", nullptr},
            {"raw-control-tab", "deviceID", "\"deviceID\":\"a\tb\"", nullptr},
            {"toplevel-array", "", "", "[]"},
            {"toplevel-string", "", "", "\"x\""},
            {"empty-object", "", "", "{}"},
            {"empty-input", "", "", ""},
            {"single-quote", "", "", "{'deviceID':'x'}"},
        };

        for (const auto& c : kCases) {
            const std::string json =
                (c.raw != nullptr) ? std::string(c.raw) : build(c.drop, c.extra);
            char head[64];
            std::snprintf(head, sizeof head, "len=%zu sum=%08x ",
                          static_cast<size_t>(json.size()), fnv1a(json));
            const std::string key = std::string("parse[") + c.label + "]";

            const auto r = negaflow::wire::parseScanRequest(
                json, negaflow::wire::ParseLimits::swiftEquivalent());
            if (!r) {
                emit(key, std::string(head) + "fail");
                continue;
            }
            std::string line = head;
            line += "ok pv=" + std::to_string(r->protocolVersion);
            line += " uuid=" + upperUuid(r->requestID);
            line += " dev=" + hexBytes(r->deviceID);
            line += " dpi=" + std::to_string(r->resolutionDPI);
            line += " depth=" + std::to_string(r->bitDepth);
            line += " mode=" + r->colorMode;
            line += " film=" + r->filmType;
            line += std::string(" prev=") + (r->preview ? "1" : "0");
            line += std::string(" multi=") + (r->multiExposure ? "1" : "0");
            line += std::string(" ir=") + (r->infrared ? "1" : "0");
            line += " bright=" +
                    (r->brightnessAdjustment ? bits(*r->brightnessAdjustment) : std::string("nil"));
            line += " contrast=" +
                    (r->contrastAdjustment ? bits(*r->contrastAdjustment) : std::string("nil"));
            line += " x=" + bits(r->scanArea.originXMM);
            line += " y=" + bits(r->scanArea.originYMM);
            line += " w=" + bits(r->scanArea.widthMM);
            line += " h=" + bits(r->scanArea.heightMM);
            line += " hw=" + (r->hardwareExposureTime ? std::to_string(*r->hardwareExposureTime)
                                                      : std::string("nil"));
            line += std::string(" raw=") + (r->outputRawTIFF ? "1" : "0");
            line += " tok=" + (r->capabilityToken ? *r->capabilityToken : std::string("nil"));
            line += " path=" + r->outputPath;
            emit(key, line);
        }
    }
#endif  // NEGAFLOW_HAVE_RAPIDJSON

    return 0;
}
