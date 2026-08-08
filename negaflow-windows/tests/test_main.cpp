// SPDX-License-Identifier: GPL-2.0-or-later
//
// 최소 테스트 러너. 외부 프레임워크 의존 없음.
// 골든 픽스처 corpus 가 생기면(M1) 이 러너가 그것을 읽도록 확장한다.
// 근거: windows_docs/05-protocol/conformance-fixtures.md

#include <charconv>
#include <chrono>
#include <clocale>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <limits>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "imaging/align.h"
#include "imaging/merge.h"
#include "imaging/tiff_contract.h"
#include "wire/event.h"
#include "wire/json.h"
#include "wire/emitter.h"
#include "wire/protocol.h"
#include "wire/request.h"
#include "wire/writer.h"
#include "wire/cli.h"
#ifdef NEGAFLOW_HAVE_RAPIDJSON
#include "wire/parse.h"
#include "wire/snapshot.h"
#endif
#ifdef _WIN32
#include "process/cancel.h"
#include "process/child.h"
#include "process/watchdog.h"
#endif
#ifdef NEGAFLOW_HAVE_LIBTIFF
#include "imaging/tiff_io.h"
#endif
#include "sane/capabilities.h"
#include "sane/media.h"
#include "process/acquisition.h"
#include "process/budget.h"
#include "process/command_line.h"
#include "process/progress.h"
#include "sane/args.h"
#include "sane/validate.h"
#include "sane/device_list.h"
#include "sane/option_dump.h"
#include "util/numeric.h"

namespace {

int g_failures = 0;
int g_checks = 0;

void report(bool ok, const char* file, int line, const std::string& what) {
    ++g_checks;
    if (ok) return;
    ++g_failures;
    std::printf("FAIL  %s:%d\n      %s\n", file, line, what.c_str());
}

#define CHECK(cond) report((cond), __FILE__, __LINE__, #cond)

#define CHECK_EQ(a, b)                                                            \
    do {                                                                          \
        auto lhs_ = (a);                                                          \
        auto rhs_ = (b);                                                          \
        report(lhs_ == rhs_, __FILE__, __LINE__,                                  \
               std::string(#a " == " #b "  (left=") + toText(lhs_) +              \
                   ", right=" + toText(rhs_) + ")");                              \
    } while (0)

// CHECK_EQ 가 쓰는 오버로드 집합. 전부 쓰이지는 않지만 집합으로 유지한다.
[[maybe_unused]] std::string toText(const std::string& s) { return "\"" + s + "\""; }
[[maybe_unused]] std::string toText(bool b) { return b ? "true" : "false"; }
[[maybe_unused]] std::string toText(int v) { return std::to_string(v); }
[[maybe_unused]] std::string toText(long long v) { return std::to_string(v); }
[[maybe_unused]] std::string toText(size_t v) { return std::to_string(v); }
[[maybe_unused]] std::string toText(double v) { return std::to_string(v); }

using negaflow::sane::OptionDump;
using negaflow::sane::ResolutionSpec;
using negaflow::util::OptionRange;

// --- util/numeric ---------------------------------------------------------

void testContainsExactly() {
    OptionRange noStep{0.0, 36.33, std::nullopt};
    CHECK(negaflow::util::containsExactly(noStep, 36.33));
    CHECK(negaflow::util::containsExactly(noStep, 0.0));
    CHECK(negaflow::util::containsExactly(noStep, 12.5));
    CHECK(!negaflow::util::containsExactly(noStep, -0.1));
    CHECK(!negaflow::util::containsExactly(noStep, 36.34));
    CHECK(!negaflow::util::containsExactly(noStep, std::nan("")));
    CHECK(!negaflow::util::containsExactly(noStep, INFINITY));

    OptionRange step1{-100.0, 100.0, 1.0};
    CHECK(negaflow::util::containsExactly(step1, 0.0));
    CHECK(negaflow::util::containsExactly(step1, -100.0));
    CHECK(negaflow::util::containsExactly(step1, 100.0));
    CHECK(!negaflow::util::containsExactly(step1, 0.5));

    // step 이 소수인 경우
    OptionRange half{0.0, 10.0, 0.5};
    CHECK(negaflow::util::containsExactly(half, 2.5));
    CHECK(!negaflow::util::containsExactly(half, 2.4));

    // step <= 0 이면 연속 범위로 취급한다(Swift 와 동일)
    OptionRange zeroStep{0.0, 10.0, 0.0};
    CHECK(negaflow::util::containsExactly(zeroStep, 3.3));
}

void testSaneNumber() {
    CHECK_EQ(negaflow::util::saneNumber(36.0), std::string("36"));
    CHECK_EQ(negaflow::util::saneNumber(0.0), std::string("0"));
    CHECK_EQ(negaflow::util::saneNumber(-5.0), std::string("-5"));
    CHECK_EQ(negaflow::util::saneNumber(36.33), std::string("36.33"));
    CHECK_EQ(negaflow::util::saneNumber(44.25), std::string("44.25"));
    // 지수 표기가 새어 나가지 않아야 한다
    const std::string tiny = negaflow::util::saneNumber(0.0000001);
    CHECK(tiny.find('e') == std::string::npos);
    CHECK(tiny.find('E') == std::string::npos);
}

void testEpson2AlignedHeight() {
    OptionRange range{0.0, 300.0, std::nullopt};

    // ① 이미 정수 경계 → 그대로
    CHECK_EQ(negaflow::util::epson2AlignedHeightMM(0.0, 24.0, range, std::nullopt), 24.0);

    // ② 넓히기 성공 (0 + 23.5 → 24)
    CHECK_EQ(negaflow::util::epson2AlignedHeightMM(0.0, 23.5, range, std::nullopt), 24.0);

    // ③ 넓히면 표면을 넘음 → 좁히기 (bottom 23.5, surface 23.9)
    CHECK_EQ(negaflow::util::epson2AlignedHeightMM(0.0, 23.5, range, 23.9), 23.0);

    // ④ 둘 다 불가 → 요청값 유지
    //    범위 최대가 23.5 라 넓힐 수 없고, 좁히면 range 밖은 아니지만
    //    surface 가 막아 넓히기 실패 → 좁히기가 성공하므로 여기서는 범위를 좁힌다.
    OptionRange tight{23.5, 23.5, std::nullopt};
    CHECK_EQ(negaflow::util::epson2AlignedHeightMM(0.0, 23.5, tight, std::nullopt), 23.5);

    // 원점이 있는 경우: origin 2.25 + height 21.5 = 23.75 → 24 로 올림 → height 21.75
    CHECK_EQ(negaflow::util::epson2AlignedHeightMM(2.25, 21.5, range, std::nullopt), 21.75);

    // 비정상 입력은 그대로 돌려준다
    CHECK_EQ(negaflow::util::epson2AlignedHeightMM(0.0, 0.0, range, std::nullopt), 0.0);
}

void testPixelGeometry() {
    OptionRange pelRange{0.0, 100000.0, std::nullopt};
    // 36 mm @ 3600 dpi = 5102.36... → 5102
    const auto v = negaflow::util::pixelGeometryValue(36.0, 3600, pelRange);
    CHECK(v.has_value());
    if (v) CHECK_EQ(*v, 5102LL);

    // dpi 0 이면 실패
    CHECK(!negaflow::util::pixelGeometryValue(36.0, 0, pelRange).has_value());
    // 범위 밖이면 실패
    OptionRange small{0.0, 10.0, std::nullopt};
    CHECK(!negaflow::util::pixelGeometryValue(36.0, 3600, small).has_value());

    const auto len = negaflow::util::pixelGeometryLength(36.0, 3600);
    CHECK(len.has_value());
    if (len) CHECK_EQ(*len, 5102LL);
    // 길이는 최소 1
    CHECK(!negaflow::util::pixelGeometryLength(0.0, 3600).has_value());
}

// --- sane/option_dump -----------------------------------------------------

const char* kGenesysDump = R"(Options specific to device `genesys:libusb:001:002':
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

void testDumpBasics() {
    OptionDump d{kGenesysDump};
    CHECK(!d.empty());

    // 섹션 제목과 설명문은 걸러진다
    CHECK(!d.hasOption("Scan"));
    CHECK(!d.hasOption("Selects"));

    CHECK(d.hasOption("mode"));
    CHECK(d.hasOption("source"));
    CHECK(d.hasOption("x"));   // 단문자 옵션
    CHECK(d.hasOption("l"));
    CHECK(d.hasOption("preview"));  // bool 접미사 제거

    CHECK(d.isActive("brightness"));
    CHECK(!d.isActive("contrast"));  // [inactive]
    CHECK(d.hasOption("contrast"));  // 존재는 한다
}

void testEnumValues() {
    OptionDump d{kGenesysDump};

    const auto modes = d.enumValues("mode");
    CHECK_EQ(modes.size(), size_t{2});
    if (modes.size() == 2) {
        CHECK_EQ(modes[0], std::string("Color"));
        CHECK_EQ(modes[1], std::string("Gray"));
    }

    // 공백이 있는 열거값이 보존돼야 한다
    const auto sources = d.enumValues("source");
    CHECK_EQ(sources.size(), size_t{2});
    if (sources.size() == 2) {
        CHECK_EQ(sources[0], std::string("Transparency Adapter"));
        CHECK_EQ(sources[1], std::string("Transparency Adapter Infrared"));
    }

    // 선택값
    const auto sel = d.selectedEnumValue("mode");
    CHECK(sel.has_value());
    if (sel) CHECK_EQ(*sel, std::string("Color"));

    // 비활성 옵션은 enumValues 가 비지만 constraintEnumValues 는 값을 준다
    CHECK(d.enumValues("contrast").empty());
}

void testInactiveAsymmetry() {
    // scanimage 는 비활성 옵션도 제약을 그대로 출력한다.
    const char* dump = "    --depth 8 [inactive]\n";
    OptionDump d{dump};
    CHECK(d.hasOption("depth"));
    CHECK(!d.isActive("depth"));
    CHECK(d.intTokens("depth").empty());               // 활성 검사 있음
    CHECK_EQ(d.constraintIntTokens("depth").size(), size_t{1});  // 활성 검사 없음
    if (!d.constraintIntTokens("depth").empty()) {
        CHECK_EQ(d.constraintIntTokens("depth")[0], 8);
    }
}

void testIntTokens() {
    OptionDump d{kGenesysDump};
    const auto depths = d.intTokens("depth");
    CHECK_EQ(depths.size(), size_t{2});
    if (depths.size() == 2) {
        CHECK_EQ(depths[0], 8);
        CHECK_EQ(depths[1], 16);
    }

    // coolscan3 스타일
    OptionDump cs{"    --depth 8|14 [8]\n"};
    const auto d2 = cs.intTokens("depth");
    CHECK_EQ(d2.size(), size_t{2});
    if (d2.size() == 2) {
        CHECK_EQ(d2[0], 8);
        CHECK_EQ(d2[1], 14);
    }
}

void testNumericRangeAndUnit() {
    OptionDump d{kGenesysDump};

    const auto x = d.numericRange("x");
    CHECK(x.has_value());
    if (x) {
        CHECK_EQ(x->minimum, 0.0);
        CHECK_EQ(x->maximum, 36.33);
        CHECK(!x->step.has_value());
    }

    const auto b = d.numericRange("brightness");
    CHECK(b.has_value());
    if (b) {
        CHECK_EQ(b->minimum, -100.0);
        CHECK_EQ(b->maximum, 100.0);
        CHECK(b->step.has_value());
        if (b->step) CHECK_EQ(*b->step, 1.0);
    }

    const auto unit = d.rangeUnit("x");
    CHECK(unit.has_value());
    if (unit) CHECK_EQ(*unit, std::string("mm"));

    // 비활성 옵션은 범위를 주지 않는다
    CHECK(!d.numericRange("contrast").has_value());

    // pel 단위
    OptionDump pel{"    -x 0..3600pel [3600]\n"};
    const auto pu = pel.rangeUnit("x");
    CHECK(pu.has_value());
    if (pu) CHECK_EQ(*pu, std::string("pel"));

    // 단위 없음
    OptionDump none{"    --scan-exposure-time 0..65535 [11000]\n"};
    CHECK(!none.rangeUnit("scan-exposure-time").has_value());
    CHECK(none.numericRange("scan-exposure-time").has_value());
}

void testResolutionSpec() {
    OptionDump list{kGenesysDump};
    const auto s = list.resolutionSpec();
    CHECK(s.kind == ResolutionSpec::Kind::List);
    CHECK_EQ(s.list.size(), size_t{5});
    if (s.list.size() == 5) {
        CHECK_EQ(s.list[0], 600);    // 정렬됨
        CHECK_EQ(s.list[4], 7200);
    }

    OptionDump range{"    --resolution 50..6400dpi [600]\n"};
    const auto r = range.resolutionSpec();
    CHECK(r.kind == ResolutionSpec::Kind::Range);
    CHECK_EQ(r.min, 50);
    CHECK_EQ(r.max, 6400);

    OptionDump inactive{"    --resolution 600|1200dpi [inactive]\n"};
    CHECK(inactive.resolutionSpec().kind == ResolutionSpec::Kind::None);
}

void testCrlfAndDuplicates() {
    // CRLF 덤프가 그대로 파싱돼야 한다.
    OptionDump crlf{"    --mode Color|Gray [Color]\r\n    --depth 8|16 [16]\r\n"};
    CHECK(crlf.hasOption("mode"));
    CHECK(crlf.hasOption("depth"));
    const auto modes = crlf.enumValues("mode");
    CHECK_EQ(modes.size(), size_t{2});
    if (modes.size() == 2) CHECK_EQ(modes[1], std::string("Gray"));

    // 같은 옵션이 두 번 나오면 먼저 나온 것이 이긴다.
    OptionDump dup{"    --mode Color [Color]\n    --mode Gray|Lineart [Gray]\n"};
    const auto dm = dup.enumValues("mode");
    CHECK_EQ(dm.size(), size_t{1});
    if (!dm.empty()) CHECK_EQ(dm[0], std::string("Color"));
}

void testEmptyDump() {
    OptionDump d{""};
    CHECK(d.empty());
    CHECK(!d.hasOption("mode"));
    CHECK(d.enumValues("mode").empty());
    CHECK(!d.numericRange("x").has_value());
    CHECK(d.resolutionSpec().kind == ResolutionSpec::Kind::None);
}

// --- sane/device_list -----------------------------------------------------

void testBackendAndConnection() {
    using namespace negaflow::sane;
    CHECK_EQ(backendName("genesys:libusb:001:002"), std::string("genesys"));
    CHECK_EQ(backendName("plain"), std::string("plain"));
    // net: 중첩은 "net" 으로 판정된다 — 의도된 동작(D-03)
    CHECK_EQ(backendName("net:h:genesys:libusb:1:2"), std::string("net"));

    CHECK(connectionType("genesys:libusb:001:002") == ConnectionType::Usb);
    // Windows 는 still-image 클래스 드라이버로 열린 장치를 이렇게 부른다.
    // 실기 확인: `genesys:usbscan:000` = PLUSTEK OpticFilm 8100.
    CHECK(connectionType("genesys:usbscan:000") == ConnectionType::Usb);
    CHECK(connectionType("epson2:usbscan:001") == ConnectionType::Usb);
    CHECK(!isVolatileUSBSelector("genesys:usbscan:000"));
    CHECK(connectionType("epson2:net:host:1") == ConnectionType::Network);
    CHECK(connectionType("coolscan:scsi:0:1:2") == ConnectionType::Scsi);
    CHECK(connectionType("pie:/dev/sg0") == ConnectionType::Scsi);
    CHECK(connectionType("x:firewire:1") == ConnectionType::FireWire);
    CHECK(connectionType("plain") == ConnectionType::InternalBus);

    CHECK(isVolatileUSBSelector("genesys:libusb:1:2"));
    CHECK(!isVolatileUSBSelector("genesys:usb:1:2"));

    // 주소 없는 선택자는 genesys/epson2 에만 허용한다.
    CHECK(supportsStableBackendSelector("genesys"));
    CHECK(supportsStableBackendSelector("epson2"));
    CHECK(!supportsStableBackendSelector("coolscan3"));

    CHECK(isDedicatedFilmBackend("coolscan3"));
    CHECK(isDedicatedFilmBackend("pieusb"));
    CHECK(!isDedicatedFilmBackend("genesys"));

    // pieusb 만 watchdog 을 끈다.
    CHECK(!usesAutomaticAcquisitionWatchdog("pieusb"));
    CHECK(usesAutomaticAcquisitionWatchdog("genesys"));
}

void testParseDeviceList() {
    using namespace negaflow::sane;
    const auto v = parseDeviceList(
        "device `genesys:libusb:001:003' is a PLUSTEK OpticFilm 8100 film scanner\n"
        "garbage\n"
        "device `epson2:libusb:001:005' is a Epson GT-X970 flatbed scanner\n");
    CHECK_EQ(v.size(), size_t{2});
    if (v.size() == 2) {
        CHECK_EQ(v[0].devname, std::string("genesys:libusb:001:003"));
        CHECK_EQ(v[0].vendor, std::string("PLUSTEK"));
        CHECK_EQ(v[0].model, std::string("OpticFilm 8100"));
        CHECK_EQ(v[0].deviceType, std::string("film scanner"));
        CHECK_EQ(v[1].model, std::string("GT-X970"));
    }

    // 벤더만 있으면 모델은 벤더와 같다.
    const auto one = parseDeviceList("device `weird:x' is a SingleToken scanner\n");
    CHECK_EQ(one.size(), size_t{1});
    if (!one.empty()) {
        CHECK_EQ(one[0].vendor, std::string("SingleToken"));
        CHECK_EQ(one[0].model, std::string("SingleToken"));
        CHECK_EQ(one[0].deviceType, std::string("scanner"));
    }
}

void testParseFormattedDeviceList() {
    using namespace negaflow::sane;
    const auto v = parseFormattedDeviceList(
        "genesys:libusb:001:003\tPLUSTEK\tOpticFilm 8100\tfilm scanner\n"
        "broken-line-without-tabs\n"
        "\tEmptyDev\tm\tt\n");
    CHECK_EQ(v.size(), size_t{1});   // devname 이 빈 줄과 탭 없는 줄은 버린다
    if (!v.empty()) {
        CHECK_EQ(v[0].devname, std::string("genesys:libusb:001:003"));
        CHECK_EQ(v[0].deviceType, std::string("film scanner"));
    }

    // CRLF — Swift 는 못 하지만 C++ 는 처리한다(의도적 divergence)
    const auto crlf = parseFormattedDeviceList("a\tv\tm\tt\r\nb\tv2\tm2\tt2\r\n");
    CHECK_EQ(crlf.size(), size_t{2});
    if (crlf.size() == 2) CHECK_EQ(crlf[1].deviceType, std::string("t2"));
}

void testIdentityAndCapitalized() {
    using namespace negaflow::sane;
    ListedDevice d{"genesys:libusb:1:2", "PLUSTEK", "OpticFilm  8100", "film scanner"};
    CHECK(sameIdentity(d, "plustek", "opticfilm 8100"));      // 대소문자·공백 정규화
    CHECK(!sameIdentity(d, "plustek", "OpticFilm 8200i"));

    // Swift String.capitalized 와 일치해야 한다. 숫자는 단어 구분자다.
    CHECK_EQ(capitalized("PLUSTEK"), std::string("Plustek"));
    CHECK_EQ(capitalized("pie/reflecta"), std::string("Pie/Reflecta"));
    CHECK_EQ(capitalized("gt-x970"), std::string("Gt-X970"));
    CHECK_EQ(capitalized("a1b2"), std::string("A1B2"));
    CHECK_EQ(capitalized(""), std::string(""));
}

void testDedupe() {
    using namespace negaflow::sane;
    std::vector<ListedDevice> v{
        {"a", "V1", "M1", "t"}, {"b", "V2", "M2", "t"}, {"a", "V3", "M3", "t"}};
    const size_t removed = dedupeByDevname(v);
    CHECK_EQ(removed, size_t{1});
    CHECK_EQ(v.size(), size_t{2});
    // 첫 항목이 이긴다 — 호스트와 같은 의미론
    if (v.size() == 2) CHECK_EQ(v[0].vendor, std::string("V1"));
}

// --- sane/capabilities ----------------------------------------------------

void testCapabilitiesGenesys() {
    using namespace negaflow::sane;
    const auto c = parseCapabilities(OptionDump{kGenesysDump}, "film scanner", "genesys");

    CHECK_EQ(c.supportedResolutionsDPI.size(), size_t{5});
    if (c.supportedResolutionsDPI.size() == 5) {
        CHECK_EQ(c.supportedResolutionsDPI.front(), 600);
        CHECK_EQ(c.supportedResolutionsDPI.back(), 7200);
    }
    CHECK_EQ(c.supportedModes.size(), size_t{2});
    CHECK_EQ(c.supportedBitDepths.size(), size_t{2});
    CHECK(c.supportsTransparency);
    CHECK(c.supportsInfrared);         // source 에 Infrared 가 있다
    CHECK(c.supportsScanArea);
    CHECK(!c.supportsPositionedScanArea);  // 반사 소스가 없다
    CHECK(!c.supportsMultiExposure);       // --scan-exposure-time 없음
    CHECK(!c.supportsLampWarmupStatus);    // 항상 false
    CHECK(c.brightnessRange.has_value());
    CHECK(!c.contrastRange.has_value());   // [inactive]
    CHECK(c.scanAreaUnit == ScanAreaUnit::Millimeter);

    // 비활성/부재 사유가 기록된다
    CHECK(c.disabledReasons.count("contrast") == 1);
    CHECK(c.disabledReasons.count("multiExposure") == 1);
    CHECK(c.disabledReasons.count("infrared") == 0);  // 지원하므로 없다
}

void testCapabilitiesPositionedArea() {
    using namespace negaflow::sane;
    // 반사(Flatbed) + 투과 + l/t 범위가 전부 있어야 위치 지정을 보고한다.
    const char* dump =
        "    --source Flatbed|Transparency Unit [Flatbed]\n"
        "    -l 0..215.9mm [0]\n"
        "    -t 0..297.18mm [0]\n"
        "    -x 0..215.9mm [215.9]\n"
        "    -y 0..297.18mm [297.18]\n";
    const auto c = parseCapabilities(OptionDump{dump}, "flatbed scanner", "epson2");
    CHECK(c.supportsScanArea);
    CHECK(c.supportsPositionedScanArea);
    CHECK(c.scanOriginXRange.has_value());

    // l/t 가 없으면 위치 지정 불가
    const char* noOrigin =
        "    --source Flatbed|Transparency Unit [Flatbed]\n"
        "    -x 0..215.9mm [215.9]\n"
        "    -y 0..297.18mm [297.18]\n";
    const auto c2 = parseCapabilities(OptionDump{noOrigin}, "flatbed scanner", "epson2");
    CHECK(c2.supportsScanArea);
    CHECK(!c2.supportsPositionedScanArea);
}

void testCapabilitiesPelUnit() {
    using namespace negaflow::sane;
    const char* dump =
        "    --depth 8|14 [8]\n"
        "    -x 0..3600pel [3600]\n"
        "    -y 0..5400pel [5400]\n";
    const auto c = parseCapabilities(OptionDump{dump}, "film scanner", "coolscan3");
    CHECK(c.scanAreaUnit == ScanAreaUnit::Pixel);
    CHECK(!c.supportsScanArea);            // mm 범위가 아니므로
    CHECK(!c.scanWidthRange.has_value());
    // --mode 가 없는 전용 필름 백엔드 → Color 를 채운다
    CHECK_EQ(c.supportedModes.size(), size_t{1});
    CHECK(c.supportsTransparency);
    // 14bit 는 16bit 컨테이너로 전달된다
    CHECK_EQ(c.supportedBitDepths.size(), size_t{2});
}

void testCapabilitiesMultiExposureGate() {
    using namespace negaflow::sane;
    // 노출 계획 3개가 전부 범위에 있어야 켠다.
    const auto ok = parseCapabilities(
        OptionDump{"    --scan-exposure-time 0..65535 [11000]\n"}, "", "genesys");
    CHECK(ok.supportsMultiExposure);

    const auto tooSmall = parseCapabilities(
        OptionDump{"    --scan-exposure-time 0..20000 [11000]\n"}, "", "genesys");
    CHECK(!tooSmall.supportsMultiExposure);   // 30000 이 범위 밖
    CHECK(tooSmall.disabledReasons.count("multiExposure") == 1);
}

void testFixedDepthAndHelpers() {
    using namespace negaflow::sane;
    // 5갈래
    CHECK(!fixedDepth(OptionDump{"    --depth 8|16 [16]\n"}, "epson2").has_value());  // 활성
    CHECK(fixedDepth(OptionDump{"    --depth 8 [inactive]\n"}, "x") == BitDepth::Eight);
    CHECK(fixedDepth(OptionDump{"    --depth 14 [inactive]\n"}, "x") == BitDepth::Sixteen);
    CHECK(!fixedDepth(OptionDump{"    --depth 8|16 [inactive]\n"}, "x").has_value());  // 2개
    CHECK(fixedDepth(OptionDump{"    --mode Color [Color]\n"}, "epson2") == BitDepth::Eight);
    CHECK(!fixedDepth(OptionDump{"    --mode Color [Color]\n"}, "genesys").has_value());

    // 3갈래
    CHECK_EQ(minimumPositiveScanDimension(negaflow::util::OptionRange{1.0, 10.0, std::nullopt}), 1.0);
    CHECK_EQ(minimumPositiveScanDimension(negaflow::util::OptionRange{0.0, 10.0, 0.5}), 0.5);
    CHECK_EQ(minimumPositiveScanDimension(negaflow::util::OptionRange{0.0, 10.0, std::nullopt}), 0.1);

    // 필름 홀더용 소스 우선 — 8x10 가이드용은 유리면 초점의 다른 렌즈라 흐리다
    const auto pref = preferredTransparencySource({"Flatbed", "Transparency Unit", "TPU8x10"});
    CHECK(pref.has_value());
    if (pref) CHECK_EQ(*pref, std::string("Transparency Unit"));

    // 8x10 만 노출하는 장치에서는 그것 말고 쓸 투과 소스가 없다
    const auto only8x10 = preferredTransparencySource({"Flatbed", "TPU8x10"});
    CHECK(only8x10.has_value());
    if (only8x10) CHECK_EQ(*only8x10, std::string("TPU8x10"));

    // IR 은 본 스캔 후보에서 제외된다
    const auto p2 = preferredTransparencySource({"Transparency Adapter",
                                                 "Transparency Adapter Infrared"});
    if (p2) CHECK_EQ(*p2, std::string("Transparency Adapter"));

    // ③ 폴백은 IR 을 배제하지 않는다(원본 동작 — I-20 후보)
    const auto p3 = preferredTransparencySource({"Transparency Adapter Infrared"});
    CHECK(p3.has_value());

    // 표시상 같은 값에 붙는 rounded 경고는 실패로 보지 않는다(GT-X900 의 149.86mm)
    CHECK(!negaflow::process::containsInexactOptionWarning(
        "scanimage: rounded value of br-x from 149.86 to 149.86"));
    CHECK(negaflow::process::containsInexactOptionWarning(
        "scanimage: rounded value of br-x from 36 to 35.9"));
    CHECK(negaflow::process::containsInexactOptionWarning(
        "scanimage: rounded value of br-x from 149.86 to 149.86\n"
        "scanimage: rounded value of br-y from 36 to 35.9"));
    CHECK(negaflow::process::containsInexactOptionWarning("scanimage: rounded value of br-x"));
    CHECK(!negaflow::process::containsInexactOptionWarning("Progress: 100.0%"));

    CHECK(isTransparencySource("TPU"));
    CHECK(isTransparencySource("Film Holder"));
    CHECK(!isTransparencySource("Flatbed"));
    CHECK(isInfraredValue("ir"));
    CHECK(isInfraredValue("Transparency Adapter Infrared"));
    CHECK(!isInfraredValue("Flatbed"));
}

// --- sane/media -----------------------------------------------------------

negaflow::sane::ScanOptions makeOpts(const char* id, int dpi,
                                     negaflow::sane::BitDepth depth,
                                     negaflow::sane::FilmType film,
                                     negaflow::sane::ScanArea area, bool ir) {
    negaflow::sane::ScanOptions o;
    o.scannerID = id;
    o.resolutionDPI = dpi;
    o.bitDepth = depth;
    o.colorMode = negaflow::sane::ColorMode::Color;
    o.filmType = film;
    o.scanArea = area;
    o.infraredEnabled = ir;
    return o;
}

void testMediaGenesysToneSuppression() {
    using namespace negaflow::sane;
    const OptionDump d{kGenesysDump};
    const ScanArea frame{0.0, 0.0, 36.0, 24.0};

    // 16-bit 에서는 밝기/대비를 없는 것으로 취급한다(근거 미문서화, Q-6).
    const auto m16 = resolveMedia(
        d, makeOpts("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen,
                    FilmType::ColorNegative, frame, false), "film scanner");
    CHECK(!m16.hasBrightnessOption);
    CHECK(!m16.brightnessRange.has_value());

    // 8-bit 에서는 살아 있다.
    const auto m8 = resolveMedia(
        d, makeOpts("sane-genesys:libusb:1:2", 1200, BitDepth::Eight,
                    FilmType::ColorNegative, frame, false), "film scanner");
    CHECK(m8.hasBrightnessOption);
    CHECK(m8.brightnessRange.has_value());
}

void testMediaExactResolution() {
    using namespace negaflow::sane;
    const OptionDump d{kGenesysDump};
    const ScanArea frame{0.0, 0.0, 36.0, 24.0};

    const auto ok = resolveMedia(
        d, makeOpts("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen,
                    FilmType::ColorNegative, frame, false), "film scanner");
    CHECK(ok.resolvedDPI.has_value());
    if (ok.resolvedDPI) CHECK_EQ(*ok.resolvedDPI, 3600);

    // **지원하지 않는 dpi 는 nil 로 남는다. 가장 가까운 값으로 스냅하지 않는다(I-1).**
    const auto bad = resolveMedia(
        d, makeOpts("sane-genesys:libusb:1:2", 2000, BitDepth::Sixteen,
                    FilmType::ColorNegative, frame, false), "film scanner");
    CHECK(!bad.resolvedDPI.has_value());
}

void testMediaIRStrategy() {
    using namespace negaflow::sane;
    const OptionDump d{kGenesysDump};
    const ScanArea frame{0.0, 0.0, 36.0, 24.0};

    const auto off = resolveMedia(
        d, makeOpts("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen,
                    FilmType::ColorNegative, frame, false), "film scanner");
    CHECK(off.irStrategy.kind == IRStrategy::Kind::None);
    CHECK(!off.irStrategy.usesInfrared());

    const auto on = resolveMedia(
        d, makeOpts("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen,
                    FilmType::ColorNegative, frame, true), "film scanner");
    CHECK(on.irStrategy.kind == IRStrategy::Kind::SeparateSource);
    CHECK(on.irStrategy.needsSeparatePass());
    // IR 패스는 Gray 모드를 쓴다
    CHECK(on.irPassMode.has_value());
}

void testMediaCoolscanNegativeAlwaysNo() {
    using namespace negaflow::sane;
    const char* dump =
        "    --depth 8|14 [8]\n"
        "    --negative[=(yes|no)] [no]\n"
        "    --resolution 4000dpi [4000]\n"
        "    -x 0..3600pel [3600]\n"
        "    -y 0..5400pel [5400]\n";
    const ScanArea frame{0.0, 0.0, 36.0, 24.0};

    // **--negative 는 장치 자체 색 반전이다. 요청 filmType 과 무관하게 항상 no.**
    for (const auto ft : {FilmType::ColorNegative, FilmType::ColorPositive}) {
        const auto m = resolveMedia(
            OptionDump{dump},
            makeOpts("sane-coolscan3:libusb:1:2", 4000, BitDepth::Sixteen, ft, frame, false),
            "film scanner");
        CHECK(m.filmType.has_value());
        if (m.filmType) CHECK_EQ(*m.filmType, std::string("no"));
    }

    // --mode 가 없으므로 mode 를 보내지 않는다(보내면 scanimage 가 즉시 실패한다).
    const auto m = resolveMedia(
        OptionDump{dump},
        makeOpts("sane-coolscan3:libusb:1:2", 4000, BitDepth::Sixteen,
                 FilmType::ColorNegative, frame, false), "film scanner");
    CHECK(!m.mode.has_value());
    CHECK(!m.hasModeOption);
    // 14bit → 16bit 컨테이너
    CHECK(m.depthArgument.has_value());
    if (m.depthArgument) CHECK_EQ(*m.depthArgument, 14);
    // pel 장치이므로 mm 지오메트리를 쓰지 않는다
    CHECK(!m.widthMM.has_value());

    // 36 mm @ 4000 dpi = 5669 pel 인데 이 덤프의 -x 범위는 0..3600 이다.
    // **범위 밖이므로 nil 로 남는다** — 3600 으로 깎지 않는다(I-1).
    // 높이는 24 mm @ 4000 dpi = 3780 pel 로 0..5400 안에 들어가므로 값이 있다.
    CHECK(!m.widthPixels.has_value());
    CHECK(m.heightPixels.has_value());
    if (m.heightPixels) CHECK_EQ(*m.heightPixels, 3780LL);
}

void testMediaEpson2() {
    using namespace negaflow::sane;
    const char* dump =
        "    --mode Lineart|Gray|Color [Color]\n"
        "    --source Flatbed|Transparency Unit|TPU8x10 [Flatbed]\n"
        "    --film-type Positive Film|Negative Film [Positive Film]\n"
        "    --color-correction None|User defined [None]\n"
        "    --gamma-correction Default|User defined (Gamma=1.0)|User defined (Gamma=1.8) "
        "[Default]\n"
        "    --resolution 50..12800dpi [50]\n"
        "    --depth 8|16 [16]\n"
        "    -l 0..215.9mm [0]\n"
        "    -t 0..297.18mm [0]\n"
        "    -x 0..215.9mm [215.9]\n"
        "    -y 0..297.18mm [297.18]\n";
    const OptionDump d{dump};

    // 소수 mm 높이 → 정수 경계로 **넓힌다**(잘리지 않는 방향)
    const auto m = resolveMedia(
        d, makeOpts("sane-epson2:libusb:1:5", 1200, BitDepth::Sixteen,
                    FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 23.5}, false),
        "flatbed scanner");
    CHECK(m.heightMM.has_value());
    if (m.heightMM) CHECK_EQ(*m.heightMM, 24.0);
    CHECK_EQ(m.heightAlignmentMM, 0.5);

    // 내부 색/감마 처리를 끈다
    CHECK(m.colorCorrection.has_value());
    if (m.colorCorrection) CHECK_EQ(*m.colorCorrection, std::string("None"));
    CHECK(m.gammaCorrection.has_value());
    // ① "gamma=1.0" 규칙이 먼저 맞는다
    if (m.gammaCorrection) {
        CHECK(m.gammaCorrection->find("1.0") != std::string::npos);
    }

    // 투과 소스를 고르고, 8x10 을 우선한다
    CHECK(m.source.has_value());
    if (m.source) CHECK_EQ(*m.source, std::string("TPU8x10"));

    // 네거티브 요청 → "Negative Film"
    CHECK(m.filmType.has_value());
    if (m.filmType) CHECK_EQ(*m.filmType, std::string("Negative Film"));
}

void testMediaEmptyDumpAssumesNothing() {
    using namespace negaflow::sane;
    const auto m = resolveMedia(
        OptionDump{""},
        makeOpts("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen,
                 FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 24.0}, false), "");
    CHECK(!m.source.has_value());
    CHECK(!m.mode.has_value());
    CHECK(!m.depthArgument.has_value());
    CHECK(!m.resolvedDPI.has_value());
    CHECK(!m.widthMM.has_value());
    CHECK(!m.hasPreviewOption);
}

void testMediaCleanImageUnreachable() {
    using namespace negaflow::sane;
    // pieusb 의 --clean-image 가 있어도 IRStrategy::CleanImage 를 만들지 않는다.
    // **도달 불가 상태를 유지한다** — 연결하면 IR 파일 없는 결과가 성공으로 나간다.
    const char* dump =
        "    --mode Color|RGBI [Color]\n"
        "    --advance[=(yes|no)] [yes]\n"
        "    --clean-image[=(yes|no)] [no]\n"
        "    --resolution 3600dpi [3600]\n"
        "    -x 0..36mm [36]\n"
        "    -y 0..24mm [24]\n";
    const auto m = resolveMedia(
        OptionDump{dump},
        makeOpts("sane-pieusb:libusb:2:4", 3600, BitDepth::Sixteen,
                 FilmType::ColorPositive, ScanArea{0.0, 0.0, 36.0, 24.0}, true), "slide scanner");
    CHECK(m.irStrategy.kind != IRStrategy::Kind::CleanImage);
    CHECK(m.hasAdvanceOption);   // --advance=no 를 보내야 한다
}

// --- sane/validate --------------------------------------------------------

std::string validateOf(const char* dump, const negaflow::sane::ScanOptions& o,
                       const char* hint) {
    using namespace negaflow::sane;
    const OptionDump od{dump};
    const auto m = resolveMedia(od, o, hint);
    const auto e = validateExactOptions(o, m);
    return e ? e->description() : std::string("ok");
}

void testValidatePassesGoodRequest() {
    using namespace negaflow::sane;
    const auto o = makeOpts("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen,
                            FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 24.0}, false);
    CHECK_EQ(validateOf(kGenesysDump, o, "film scanner"), std::string("ok"));
}

void testValidateRejectsInexactResolution() {
    using namespace negaflow::sane;
    // **스냅하지 않는다.** 2000dpi 는 목록에 없으므로 거부다.
    const auto o = makeOpts("sane-genesys:libusb:1:2", 2000, BitDepth::Sixteen,
                            FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 24.0}, false);
    const auto msg = validateOf(kGenesysDump, o, "film scanner");
    CHECK(msg != "ok");
    CHECK(msg.find("2000dpi") != std::string::npos);
}

void testValidateFixedDepth() {
    using namespace negaflow::sane;
    const char* fixed8 =
        "    --mode Color [Color]\n    --depth 8 [inactive]\n"
        "    --resolution 3600dpi [3600]\n    -x 0..36mm [36]\n    -y 0..24mm [24]\n";

    // 8-bit 고정 기기에 16-bit 요청 → 거부
    auto o16 = makeOpts("sane-x:libusb:1:1", 3600, BitDepth::Sixteen,
                        FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 24.0}, false);
    CHECK(validateOf(fixed8, o16, "") != "ok");

    // 8-bit 요청 → 통과
    auto o8 = makeOpts("sane-x:libusb:1:1", 3600, BitDepth::Eight,
                       FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 24.0}, false);
    CHECK_EQ(validateOf(fixed8, o8, ""), std::string("ok"));
}

void testValidateBackendRequirements() {
    using namespace negaflow::sane;
    const char* plain =
        "    --mode Color [Color]\n    --depth 16 [16]\n"
        "    --resolution 3600dpi [3600]\n    -x 0..36mm [36]\n    -y 0..24mm [24]\n";

    // pieusb 는 --advance 가 없으면 거부한다(필름 배치가 예상 없이 움직인다).
    const auto pie = makeOpts("sane-pieusb:libusb:2:4", 3600, BitDepth::Sixteen,
                              FilmType::ColorPositive, ScanArea{0.0, 0.0, 36.0, 24.0}, false);
    const auto msg = validateOf(plain, pie, "slide scanner");
    CHECK(msg != "ok");
    CHECK(msg.find("advance") != std::string::npos);

    // 같은 덤프라도 genesys 면 통과한다 — 백엔드별 조건이다.
    const auto gen = makeOpts("sane-genesys:libusb:1:1", 3600, BitDepth::Sixteen,
                              FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 24.0}, false);
    CHECK_EQ(validateOf(plain, gen, ""), std::string("ok"));
}

void testValidateEpson2Corrections() {
    using namespace negaflow::sane;
    // color-correction 옵션이 있는데 "None" 값이 없으면 거부한다.
    const char* noNone =
        "    --mode Color [Color]\n    --color-correction Auto|User defined [Auto]\n"
        "    --depth 16 [16]\n    --resolution 3600dpi [3600]\n"
        "    -x 0..36mm [36]\n    -y 0..24mm [24]\n";
    const auto o = makeOpts("sane-epson2:libusb:1:5", 3600, BitDepth::Sixteen,
                            FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 24.0}, false);
    CHECK(validateOf(noNone, o, "") != "ok");

    // gamma-correction 도 마찬가지.
    const char* noGamma =
        "    --mode Color [Color]\n    --gamma-correction Default|Auto [Default]\n"
        "    --depth 16 [16]\n    --resolution 3600dpi [3600]\n"
        "    -x 0..36mm [36]\n    -y 0..24mm [24]\n";
    CHECK(validateOf(noGamma, o, "") != "ok");
}

void testValidateAdjustmentZeroRule() {
    using namespace negaflow::sane;
    // **0 은 범위가 없어도 통과한다**("조정하지 않음"과 같으므로).
    CHECK(!validateAdjustment(0.0, std::nullopt, "brightness").has_value());
    // 0 이 아니면 범위가 필요하다.
    CHECK(validateAdjustment(5.0, std::nullopt, "brightness").has_value());
    // 범위가 있으면 정확히 들어가야 한다.
    const negaflow::util::OptionRange r{-100.0, 100.0, 1.0};
    CHECK(!validateAdjustment(5.0, r, "brightness").has_value());
    CHECK(validateAdjustment(5.5, r, "brightness").has_value());
    // nullopt 는 항상 통과
    CHECK(!validateAdjustment(std::nullopt, std::nullopt, "brightness").has_value());
}

void testValidateMultiExposureAndIR() {
    using namespace negaflow::sane;
    const ScanArea frame{0.0, 0.0, 36.0, 24.0};

    // 다중 노출은 16-bit color 만
    auto m8 = makeOpts("sane-genesys:libusb:1:2", 3600, BitDepth::Eight,
                       FilmType::ColorNegative, frame, false);
    m8.multiExposureEnabled = true;
    const auto msg8 = validateOf(kGenesysDump, m8, "film scanner");
    CHECK(msg8 != "ok");
    CHECK(msg8.find("16-bit color") != std::string::npos);

    // 노출 계획을 장치가 지원하지 않으면 거부
    auto mp = makeOpts("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen,
                       FilmType::ColorNegative, frame, true);
    mp.multiExposureEnabled = true;
    CHECK(validateOf(kGenesysDump, mp, "film scanner") != "ok");

    // IR 요청인데 IR 소스가 없으면 거부
    const char* noIR =
        "    --mode Color [Color]\n    --depth 16 [16]\n"
        "    --resolution 3600dpi [3600]\n    -x 0..36mm [36]\n    -y 0..24mm [24]\n";
    const auto irReq = makeOpts("sane-x:libusb:1:1", 3600, BitDepth::Sixteen,
                                FilmType::ColorNegative, frame, true);
    CHECK(validateOf(noIR, irReq, "") != "ok");

    // IR 소스가 있으면 통과
    const auto irOK = makeOpts("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen,
                               FilmType::ColorNegative, frame, true);
    CHECK_EQ(validateOf(kGenesysDump, irOK, "film scanner"), std::string("ok"));
}

void testErrorCodeFormat() {
    using namespace negaflow::sane;
    // wire 형태: "<code>: <message>", 메시지가 비면 코드만.
    const ScannerError e1{ErrorCode::UnsupportedOption, "x"};
    const ScannerError e2{ErrorCode::Timeout, ""};
    CHECK_EQ(e1.description(), std::string("unsupportedOption: x"));
    CHECK_EQ(e2.description(), std::string("timeout"));
    CHECK_EQ(std::string(errorCodeRawValue(ErrorCode::NotConnected)),
             std::string("notConnected"));
}

// --- sane/args ------------------------------------------------------------

std::string argsOf(const char* dump, const negaflow::sane::ScanOptions& o, const char* hint,
                   const char* dev, negaflow::sane::AcquisitionPass pass,
                   std::optional<int> bright) {
    using namespace negaflow::sane;
    const OptionDump od{dump};
    const auto m = resolveMedia(od, o, hint);
    const auto a = makeScanimageArgs(dev, o, m, pass, bright);
    std::string out;
    for (size_t i = 0; i < a.size(); ++i) {
        if (i) out += " ";
        out += a[i];
    }
    return out;
}

void testArgsOrderAndShape() {
    using namespace negaflow::sane;
    const auto o = makeOpts("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen,
                            FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 24.0}, false);
    const auto s = argsOf(kGenesysDump, o, "film scanner", "genesys:libusb:001:002",
                          AcquisitionPass::Main, std::nullopt);

    // 항상 -d <dev> -p 로 시작하고 --format=tiff 로 끝난다.
    CHECK(s.rfind("-d genesys:libusb:001:002 -p", 0) == 0);
    CHECK(s.size() >= 14 && s.compare(s.size() - 14, 14, "--format=tiff") != 0);
    CHECK(s.find("--format=tiff") != std::string::npos);

    // --source 가 --mode 보다 앞
    CHECK(s.find("--source") < s.find("--mode"));
    // --resolution 이 지오메트리보다 앞
    CHECK(s.find("--resolution") < s.find("-x"));
}

void testArgsIRPassKeepsGrid() {
    using namespace negaflow::sane;
    const auto o = makeOpts("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen,
                            FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 24.0}, true);
    const auto main = argsOf(kGenesysDump, o, "film scanner", "genesys:libusb:001:002",
                             AcquisitionPass::Main, std::nullopt);
    const auto ir = argsOf(kGenesysDump, o, "film scanner", "genesys:libusb:001:002",
                           AcquisitionPass::Infrared, std::nullopt);

    // IR 패스는 소스를 IR 소스로 바꾼다
    CHECK(ir.find("Transparency Adapter Infrared") != std::string::npos);
    // **해상도·심도·지오메트리는 본 스캔과 같아야 한다**(먼지 맵 정렬).
    CHECK(ir.find("--resolution 3600") != std::string::npos);
    CHECK(ir.find("--depth 16") != std::string::npos);
    CHECK(ir.find("-x 36") != std::string::npos);
    CHECK(main.find("--resolution 3600") != std::string::npos);
    CHECK(main.find("-x 36") != std::string::npos);
}

void testArgsOmitsAbsentOptions() {
    using namespace negaflow::sane;
    // coolscan3 은 --mode 가 없다. **보내면 scanimage 가 즉시 실패한다.**
    const char* dump =
        "    --depth 8|14 [8]\n    --negative[=(yes|no)] [no]\n"
        "    --resolution 4000dpi [4000]\n    -x 0..6000pel [6000]\n    -y 0..6000pel [6000]\n";
    const auto o = makeOpts("sane-coolscan3:libusb:1:2", 4000, BitDepth::Sixteen,
                            FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 24.0}, false);
    const auto s = argsOf(dump, o, "film scanner", "coolscan3:usb:libusb:001:002",
                          AcquisitionPass::Main, std::nullopt);
    CHECK(s.find("--mode") == std::string::npos);
    CHECK(s.find("--source") == std::string::npos);
    // --negative 는 bool 이라 `=값` 형태이고 항상 no 다
    CHECK(s.find("--negative=no") != std::string::npos);
}

void testArgsBackendSpecific() {
    using namespace negaflow::sane;
    // pieusb → --advance=no
    const char* pie =
        "    --mode Color|RGBI [Color]\n    --advance[=(yes|no)] [yes]\n"
        "    --resolution 3600dpi [3600]\n    -x 0..36mm [36]\n    -y 0..24mm [24]\n"
        "    --depth 16 [16]\n";
    const auto po = makeOpts("sane-pieusb:libusb:2:4", 3600, BitDepth::Sixteen,
                             FilmType::ColorPositive, ScanArea{0.0, 0.0, 36.0, 24.0}, false);
    CHECK(argsOf(pie, po, "slide scanner", "pieusb:libusb:002:004", AcquisitionPass::Main,
                 std::nullopt)
              .find("--advance=no") != std::string::npos);

    // epson2 → 색/감마 보정
    const char* eps =
        "    --mode Color [Color]\n"
        "    --color-correction None|User defined [None]\n"
        "    --gamma-correction Default|User defined (Gamma=1.0) [Default]\n"
        "    --resolution 1200dpi [1200]\n    --depth 16 [16]\n"
        "    -x 0..215.9mm [215.9]\n    -y 0..297.18mm [297.18]\n";
    const auto eo = makeOpts("sane-epson2:libusb:1:5", 1200, BitDepth::Sixteen,
                             FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 24.0}, false);
    const auto es = argsOf(eps, eo, "flatbed scanner", "epson2:libusb:001:005",
                           AcquisitionPass::Main, std::nullopt);
    CHECK(es.find("--color-correction None") != std::string::npos);
    CHECK(es.find("Gamma=1.0") != std::string::npos);
}

void testArgsBrightnessOverride() {
    using namespace negaflow::sane;
    // 8-bit 이어야 genesys 에서 밝기 옵션이 살아 있다
    auto o = makeOpts("sane-genesys:libusb:1:2", 1200, BitDepth::Eight,
                      FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 24.0}, false);

    // override 가 있으면 정수로 나간다
    CHECK(argsOf(kGenesysDump, o, "film scanner", "d", AcquisitionPass::Main, 7)
              .find("--brightness=7") != std::string::npos);

    // 없으면 요청값을 saneNumber 로 포맷한다
    o.brightnessAdjustment = -12.5;
    CHECK(argsOf(kGenesysDump, o, "film scanner", "d", AcquisitionPass::Main, std::nullopt)
              .find("--brightness=-12.5") != std::string::npos);

    // 16-bit 이면 genesys 에서 밝기를 아예 보내지 않는다
    auto o16 = makeOpts("sane-genesys:libusb:1:2", 3600, BitDepth::Sixteen,
                        FilmType::ColorNegative, ScanArea{0.0, 0.0, 36.0, 24.0}, false);
    o16.brightnessAdjustment = -12.5;
    CHECK(argsOf(kGenesysDump, o16, "film scanner", "d", AcquisitionPass::Main, std::nullopt)
              .find("--brightness") == std::string::npos);
}

// --- process/command_line — 인자 주입 방어 (I-15) --------------------------

void testQuoteArgument() {
    using negaflow::process::quoteArgument;
    // 공백·따옴표가 없으면 그대로
    CHECK_EQ(quoteArgument("simple"), std::string("simple"));
    CHECK_EQ(quoteArgument("genesys:libusb:001:002"), std::string("genesys:libusb:001:002"));
    CHECK_EQ(quoteArgument("--format=tiff"), std::string("--format=tiff"));

    // 공백이 있으면 감싼다
    CHECK_EQ(quoteArgument("Transparency Adapter"), std::string("\"Transparency Adapter\""));

    // 빈 인자는 사라지면 안 된다
    CHECK_EQ(quoteArgument(""), std::string("\"\""));

    // 따옴표 이스케이프
    CHECK_EQ(quoteArgument("a\"b"), std::string("\"a\\\"b\""));

    // 닫는 따옴표 앞 백슬래시는 2배 — 안 그러면 따옴표를 이스케이프해버린다
    CHECK_EQ(quoteArgument("ends with\\"), std::string("\"ends with\\\\\""));

    // 백슬래시는 따옴표 앞에서만 2배가 된다
    CHECK_EQ(quoteArgument("a\\b c"), std::string("\"a\\b c\""));
}

void testBuildCommandLine() {
    using negaflow::process::buildCommandLine;
    // 설치 경로에 공백이 들어간다 — argv[0] 도 감싸야 한다
    const auto cl = buildCommandLine("C:\\Program Files\\sane\\scanimage.exe",
                                     {"-d", "genesys:libusb:001:002", "-p", "--format=tiff"});
    CHECK(cl.rfind("\"C:\\Program Files\\sane\\scanimage.exe\"", 0) == 0);
    CHECK(cl.find(" -d genesys:libusb:001:002 -p --format=tiff") != std::string::npos);
}

void testIsSafeDeviceName() {
    using negaflow::process::isSafeDeviceName;
    // 정상 SANE 장치명
    CHECK(isSafeDeviceName("genesys:libusb:001:002"));
    CHECK(isSafeDeviceName("coolscan3:usb:libusb:001:002"));
    CHECK(isSafeDeviceName("net:host.local:genesys:libusb:1:2"));
    CHECK(isSafeDeviceName("pie:/dev/sg0"));

    // **거부 — 이스케이프하지 않는다.**
    CHECK(!isSafeDeviceName(""));
    CHECK(!isSafeDeviceName("-d"));              // 옵션으로 해석된다
    CHECK(!isSafeDeviceName("a b"));             // 공백
    CHECK(!isSafeDeviceName("a\"b"));             // 따옴표
    CHECK(!isSafeDeviceName("a&b"));             // 셸 메타문자
    CHECK(!isSafeDeviceName("a|b"));
    CHECK(!isSafeDeviceName("a>b"));
    CHECK(!isSafeDeviceName("a%b"));
    CHECK(!isSafeDeviceName("a\nb"));            // 개행
    CHECK(!isSafeDeviceName(std::string(600, 'x')));  // 너무 김
}

// --- process/budget — D-32 -------------------------------------------------

void testBudgetCeilings() {
    using namespace negaflow::process;
    // 본체가 정한 상한
    CHECK(hostCeiling(Command::Detect) == std::chrono::milliseconds{90'000});
    CHECK(hostCeiling(Command::Capabilities) == std::chrono::milliseconds{180'000});
    CHECK(hostCeiling(Command::Scan) == std::chrono::milliseconds{7'200'000});

    // 우리 예산은 항상 그보다 작아야 한다 — 오류 보고할 시간을 남긴다
    for (auto c : {Command::Detect, Command::Capabilities, Command::Other}) {
        const auto b = totalBudget(c);
        CHECK(b.has_value());
        if (b) CHECK(*b < hostCeiling(c));
    }
    // scan 만 총 예산이 없다 (I-7)
    CHECK(!totalBudget(Command::Scan).has_value());
}

void testBudgetCountdown() {
    using namespace negaflow::process;
    const TimePoint t0{};
    const CommandBudget b{Command::Detect, t0};

    // 시작 시점에는 예산이 통째로 남는다
    const auto r0 = b.remaining(t0);
    CHECK(r0.has_value());
    if (r0) CHECK(*r0 == std::chrono::milliseconds{75'000});

    // 첫 호출은 호출당 상한(180s)이 아니라 **남은 예산**으로 잘린다
    const auto c0 = b.nextCallTimeout(t0);
    CHECK(c0.has_value());
    if (c0) CHECK(*c0 == std::chrono::milliseconds{75'000});

    // 50초 경과 → 25초 남음
    const auto t50 = t0 + std::chrono::milliseconds{50'000};
    const auto c1 = b.nextCallTimeout(t50);
    CHECK(c1.has_value());
    if (c1) CHECK(*c1 == std::chrono::milliseconds{25'000});

    // **예산을 다 쓰면 호출하지 않는다.** 시작해도 호스트가 먼저 죽인다.
    const auto t75 = t0 + std::chrono::milliseconds{75'000};
    CHECK(b.exhausted(t75));
    CHECK(!b.nextCallTimeout(t75).has_value());

    // 초과해도 음수가 되지 않는다
    const auto t100 = t0 + std::chrono::milliseconds{100'000};
    const auto rNeg = b.remaining(t100);
    CHECK(rNeg.has_value());
    if (rNeg) CHECK(*rNeg == Duration::zero());
}

void testBudgetScanIsUncapped() {
    using namespace negaflow::process;
    const TimePoint t0{};
    const CommandBudget b{Command::Scan, t0};

    // 총 예산이 없으므로 소진되지 않는다 — 진행률 watchdog 이 대신 본다(I-7)
    const auto t2h = t0 + std::chrono::milliseconds{7'000'000};
    CHECK(!b.exhausted(t2h));
    CHECK(!b.remaining(t2h).has_value());

    // 호출당 상한은 그대로 건다
    const auto c = b.nextCallTimeout(t2h);
    CHECK(c.has_value());
    if (c) CHECK(*c == kPerCallCeiling);
}

void testBudgetCapabilitiesMultiCall() {
    using namespace negaflow::process;
    // macOS 문제 재현: capabilities 가 scanimage 를 여러 번 부른다.
    // 예산 구조가 없으면 10회 × 180s = 1800s 로 호스트 180s 를 10배 초과한다.
    const TimePoint t0{};
    const CommandBudget b{Command::Capabilities, t0};

    auto now = t0;
    int calls = 0;
    Duration spent = Duration::zero();
    while (const auto to = b.nextCallTimeout(now)) {
        ++calls;
        // 각 호출이 타임아웃까지 다 쓴다고 가정(최악)
        now += *to;
        spent += *to;
        if (calls > 20) break;  // 무한 루프 방어
    }
    // **총합이 예산을 넘지 않는다.**
    CHECK(spent <= std::chrono::milliseconds{150'000});
    CHECK(spent < hostCeiling(Command::Capabilities));
    CHECK(calls >= 1);
}

// --- process/acquisition — 재시도 정책 -------------------------------------

negaflow::process::AcquisitionOutcome outcomeOf(int exit, bool progressed,
                                                const char* err,
                                                negaflow::process::TimeoutKind kind,
                                                bool cancelled) {
    negaflow::process::AcquisitionOutcome o;
    o.exitCode = exit;
    o.madeProgress = progressed;
    o.stderrText = err;
    o.timeoutKind = kind;
    o.cancelled = cancelled;
    return o;
}

void testAttemptCount() {
    using namespace negaflow::process;
    // **pieusb 만 1회다.** 재시도하면 다른 프레임을 덮어쓴다.
    CHECK_EQ(attemptCount("pieusb"), 1);
    CHECK_EQ(attemptCount("genesys"), 2);
    CHECK_EQ(attemptCount("epson2"), 2);
    CHECK_EQ(attemptCount("coolscan3"), 2);
}

void testRetrySucceedsAndRejectsRounding() {
    using namespace negaflow::process;
    // exit 0 → 성공
    CHECK(decideRetry("genesys", 0, 2,
                      outcomeOf(0, true, "", TimeoutKind::None, false)) ==
          RetryDecision::Succeed);

    // **exit 0 이어도 반올림 경고가 있으면 버린다**(I-1).
    CHECK(decideRetry("genesys", 0, 2,
                      outcomeOf(0, true, "scanimage: rounded value of resolution from 2000 to 2400",
                                TimeoutKind::None, false)) == RetryDecision::Fail);
}

void testRetryCancelNeverRetries() {
    using namespace negaflow::process;
    // 취소는 재시도 대상이 아니다 — stale 오류처럼 보여도.
    CHECK(decideRetry("genesys", 0, 2,
                      outcomeOf(1, false, "Invalid argument", TimeoutKind::FirstProgress, true)) ==
          RetryDecision::Fail);
}

void testRetryGenesysFirstProgress() {
    using namespace negaflow::process;
    // genesys + 첫 진행률 타임아웃 + 첫 시도 → 재시도
    CHECK(decideRetry("genesys", 0, 2,
                      outcomeOf(1, false, "", TimeoutKind::FirstProgress, false)) ==
          RetryDecision::Retry);

    // 두 번째 시도에서는 재시도하지 않는다
    CHECK(decideRetry("genesys", 1, 2,
                      outcomeOf(1, false, "", TimeoutKind::FirstProgress, false)) ==
          RetryDecision::Fail);

    // **다른 백엔드는 이 갈래를 쓰지 않는다**
    CHECK(decideRetry("epson2", 0, 2,
                      outcomeOf(1, false, "", TimeoutKind::FirstProgress, false)) ==
          RetryDecision::Fail);

    // stall 타임아웃은 재시도 대상이 아니다 — 진행이 있었다는 뜻이므로
    CHECK(decideRetry("genesys", 0, 2,
                      outcomeOf(1, true, "", TimeoutKind::Stalled, false)) ==
          RetryDecision::Fail);
}

void testRetryStaleDevice() {
    using namespace negaflow::process;
    // 진행 없음 + stale 오류 → 재시도(주소가 낡았을 수 있다)
    CHECK(decideRetry("epson2", 0, 2,
                      outcomeOf(1, false, "open of device failed: Invalid argument",
                                TimeoutKind::None, false)) == RetryDecision::Retry);

    // **진행이 있었으면 재시도하지 않는다** — 스캔이 시작됐다는 뜻이다
    CHECK(decideRetry("epson2", 0, 2,
                      outcomeOf(1, true, "open of device failed: Invalid argument",
                                TimeoutKind::None, false)) == RetryDecision::Fail);

    // pieusb 는 total 이 1이라 재시도 갈래가 아예 없다
    CHECK(decideRetry("pieusb", 0, attemptCount("pieusb"),
                      outcomeOf(1, false, "Device busy", TimeoutKind::None, false)) ==
          RetryDecision::Fail);

    // stale 이 아닌 오류는 재시도하지 않는다
    CHECK(decideRetry("genesys", 0, 2,
                      outcomeOf(1, false, "something unrelated", TimeoutKind::None, false)) ==
          RetryDecision::Fail);
}

void testAcquisitionMessages() {
    using namespace negaflow::process;
    CHECK_EQ(acquisitionFailureDetail(3, ""), std::string("scanimage exit 3"));
    CHECK_EQ(acquisitionFailureDetail(3, "boom"), std::string("scanimage exit 3: boom"));
    CHECK_EQ(retriesExhaustedDetail(""), std::string("scanimage 재시도 실패"));
    CHECK_EQ(retriesExhaustedDetail("boom"), std::string("scanimage 재시도 실패: boom"));
}

// --- imaging/align --------------------------------------------------------
//
// `estimateIntegerOffset` 자체는 파리티 하네스가 Swift 원본과 직접 대조한다.
// 여기 있는 것은 Swift 에서 `private` 이라 파리티가 닿지 못하는 내부 단계다.
// 각 단계를 고정해 두면 파리티가 깨졌을 때 어느 단계인지 좁힐 수 있다.

/// RGBA float 이미지. 채널마다 다른 값을 넣어 채널 혼동을 잡는다.
std::vector<float> rampImage(int width, int height) {
    std::vector<float> out(static_cast<size_t>(width * height * 4), 0.0f);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const size_t i = static_cast<size_t>((y * width + x) * 4);
            out[i] = static_cast<float>(x) / 100.0f;
            out[i + 1] = static_cast<float>(y) / 100.0f;
            out[i + 2] = static_cast<float>(x + y) / 200.0f;
            out[i + 3] = 1.0f;
        }
    }
    return out;
}

void testDownsampledLuma() {
    using negaflow::imaging::detail::downsampledLuma;

    // factor 가 너비/높이를 넘으면 빈 결과.
    CHECK_EQ(downsampledLuma(rampImage(4, 4), 4, 4, 8).width, 0);
    CHECK_EQ(downsampledLuma(rampImage(4, 4), 4, 4, 8).height, 0);

    // 균일한 이미지의 블록 평균은 휘도 가중합 그대로여야 한다.
    // 가중치 합이 1 이므로 R=G=B=v 인 픽셀의 휘도는 v 다.
    std::vector<float> flat(static_cast<size_t>(8 * 8 * 4), 0.0f);
    for (int p = 0; p < 8 * 8; ++p) {
        const size_t i = static_cast<size_t>(p * 4);
        flat[i] = 0.25f;
        flat[i + 1] = 0.25f;
        flat[i + 2] = 0.25f;
        flat[i + 3] = 1.0f;
    }
    const auto d = downsampledLuma(flat, 8, 8, 2);
    CHECK_EQ(d.width, 4);
    CHECK_EQ(d.height, 4);
    bool allNear = true;
    for (float v : d.luma) allNear = allNear && std::fabs(v - 0.25f) < 1e-6f;
    CHECK(allNear);
}

void testBoxBlur3LeavesBorder() {
    using negaflow::imaging::detail::boxBlur3;

    // **경계 미처리가 계약이다.** 가장자리 한 줄은 원본이 남는다.
    // 이것을 "고치면" 정렬 결과가 달라진다.
    // 근거: windows_docs/04-imaging/exposure-merge.md §6.2
    std::vector<float> buf(25, 0.0f);
    buf[12] = 9.0f;  // 5x5 의 정중앙
    const auto out = boxBlur3(buf, 5, 5);

    CHECK_EQ(static_cast<double>(out[0]), 0.0);   // 좌상단 모서리 — 손대지 않음
    CHECK_EQ(static_cast<double>(out[4]), 0.0);   // 우상단
    CHECK_EQ(static_cast<double>(out[20]), 0.0);  // 좌하단
    CHECK_EQ(static_cast<double>(out[24]), 0.0);  // 우하단

    // 중앙은 가로 3탭 뒤 세로 3탭 → 9.0/9
    CHECK(std::fabs(out[12] - 1.0f) < 1e-6f);
    // 세로 경계(y=0) 는 가로 블러만 받는다. x=2, y=0 은 원본이 0 이므로 0.
    CHECK_EQ(static_cast<double>(out[2]), 0.0);

    // 3x3 미만이면 그대로 돌려준다.
    const std::vector<float> tiny{1.0f, 2.0f, 3.0f, 4.0f};
    CHECK(boxBlur3(tiny, 2, 2) == tiny);
}

void testDownsampledErrorGuards() {
    using negaflow::imaging::detail::downsampledError;
    const std::vector<float> a(64, 0.5f);
    const std::vector<float> b(64, 0.5f);

    // inset = 2 + max(|dx|,|dy|). 폭/높이가 2*inset 이하면 비교 불가.
    CHECK(downsampledError(a, b, 8, 8, 0, 0) == 0.0);
    CHECK(downsampledError(a, b, 8, 8, 3, 0) == std::numeric_limits<double>::max());
    CHECK(downsampledError(a, b, 4, 4, 0, 0) == std::numeric_limits<double>::max());
}

void testDownsampledTexture() {
    using negaflow::imaging::detail::downsampledTexture;

    // 완전히 평탄하면 텍스처 0 — estimateIntegerOffset 이 (0,0) 으로 빠지는 근거.
    const std::vector<float> flat(64, 0.5f);
    CHECK_EQ(downsampledTexture(flat, 8, 8), 0.0);

    // 경계를 빼고 세므로 높이가 3 미만이면 표본이 없어 0 이다.
    CHECK_EQ(downsampledTexture(flat, 8, 2), 0.0);

    // 세로 줄무늬: 인접 차의 평균이 그대로 나온다.
    std::vector<float> stripes(static_cast<size_t>(8 * 8), 0.0f);
    for (int y = 0; y < 8; ++y) {
        for (int x = 0; x < 8; ++x) {
            stripes[static_cast<size_t>(y * 8 + x)] = (x % 2 == 0) ? 0.0f : 1.0f;
        }
    }
    CHECK(std::fabs(downsampledTexture(stripes, 8, 8) - 1.0) < 1e-9);
}

void testFullResLumaErrorStep() {
    using negaflow::imaging::detail::fullResLumaError;
    const auto image = rampImage(300, 300);

    // 같은 이미지, 오프셋 0 → 오차 0.
    CHECK_EQ(fullResLumaError(image, image, 300, 300, 0, 0), 0.0);

    // inset = 4 + max(|dx|,|dy|). 이미지보다 크면 비교 불가.
    CHECK(fullResLumaError(image, image, 20, 20, 9, 0) == std::numeric_limits<double>::max());
}

void testEstimateIntegerOffsetGuards() {
    using negaflow::imaging::estimateIntegerOffset;
    using negaflow::imaging::Offset;

    // 다운샘플 결과가 6 이하면 탐색하지 않는다.
    const auto narrow = rampImage(6, 40);
    CHECK(estimateIntegerOffset(narrow, narrow, 6, 40) == (Offset{0, 0}));

    // 텍스처가 없으면 탐색하지 않는다 — 노이즈에 정렬하지 않기 위한 가드.
    std::vector<float> flat(static_cast<size_t>(40 * 40 * 4), 0.0f);
    for (int p = 0; p < 40 * 40; ++p) {
        const size_t i = static_cast<size_t>(p * 4);
        flat[i] = 0.5f;
        flat[i + 1] = 0.5f;
        flat[i + 2] = 0.5f;
        flat[i + 3] = 1.0f;
    }
    CHECK(estimateIntegerOffset(flat, flat, 40, 40) == (Offset{0, 0}));

    // 같은 이미지는 개선이 없다 → 0.85 게이트에서 (0,0).
    const auto ramp = rampImage(40, 40);
    CHECK(estimateIntegerOffset(ramp, ramp, 40, 40) == (Offset{0, 0}));
}

void testAlignedSourceIndexAndAccumulate() {
    using namespace negaflow::imaging;

    CHECK(alignedSourceIndex(0, 0, 0, Offset{-1, 0}, 8, 6) == std::nullopt);
    CHECK(alignedSourceIndex(7, 0, 0, Offset{1, 0}, 8, 6) == std::nullopt);
    CHECK(alignedSourceIndex(0, 5, 0, Offset{0, 1}, 8, 6) == std::nullopt);
    CHECK(alignedSourceIndex(4, 3, 2, Offset{0, 0}, 8, 6) == std::optional<size_t>{(3 * 8 + 4) * 4 + 2});

    // 범위 밖 소스는 건너뛴다 — **카운트도 올리지 않는다.**
    const int w = 4, h = 3;
    std::vector<float> sample(static_cast<size_t>(w * h * 4), 1.0f);
    std::vector<float> accumulator(static_cast<size_t>(w * h * 4), 0.0f);
    std::vector<float> counts(static_cast<size_t>(w * h), 0.0f);
    accumulateAligned(sample, Offset{1, 0}, w, h, accumulator, counts);

    // x = 3 은 소스가 x = 4 라 범위 밖이다.
    for (int y = 0; y < h; ++y) {
        CHECK_EQ(static_cast<double>(counts[static_cast<size_t>(y * w + 3)]), 0.0);
        CHECK_EQ(static_cast<double>(counts[static_cast<size_t>(y * w + 0)]), 1.0);
    }
    // 알파(채널 3)는 건드리지 않는다.
    CHECK_EQ(static_cast<double>(accumulator[3]), 0.0);
    CHECK_EQ(static_cast<double>(accumulator[0]), 1.0);

    // 완전히 벗어나는 오프셋은 아무것도 누적하지 않는다.
    std::vector<float> acc2(static_cast<size_t>(w * h * 4), 0.0f);
    std::vector<float> cnt2(static_cast<size_t>(w * h), 0.0f);
    accumulateAligned(sample, Offset{99, 99}, w, h, acc2, cnt2);
    float total = 0.0f;
    for (float v : cnt2) total += v;
    CHECK_EQ(static_cast<double>(total), 0.0);
}

void testExposureTrustWeightBranchOrder() {
    using negaflow::imaging::exposureTrustWeight;

    // **분기 순서가 계약이다.** 0.99 는 첫 조건(>= 0.985)에 걸려 0.02 를 받고,
    // 두 번째 조건(>= 0.90)에 도달하지 않는다.
    //
    // float 끼리 비교한다. `static_cast<double>(0.02f) != 0.02` 이므로
    // double 리터럴과 대조하면 옳은 코드가 틀린 것으로 나온다.
    CHECK(exposureTrustWeight(0.99f) == 0.02f);
    CHECK(exposureTrustWeight(0.985f) == 0.02f);
    CHECK(exposureTrustWeight(0.006f) == 0.02f);
    CHECK(exposureTrustWeight(0.5f) == 1.0f);

    // 하한 0.05 가 걸린다.
    CHECK(exposureTrustWeight(0.9849f) >= 0.05f);
    CHECK(exposureTrustWeight(0.0061f) >= 0.05f);

    // 범위 밖 값도 첫 분기로 흡수된다.
    CHECK(exposureTrustWeight(1.5f) == 0.02f);
    CHECK(exposureTrustWeight(-0.5f) == 0.02f);
}

void testMixAndSmoothstep() {
    using negaflow::imaging::mix;
    using negaflow::imaging::smoothstep;

    CHECK_EQ(static_cast<double>(mix(0.25f, 0.75f, 0.0f)), 0.25);
    CHECK_EQ(static_cast<double>(mix(0.25f, 0.75f, 1.0f)), 0.75);
    CHECK_EQ(static_cast<double>(mix(0.25f, 0.75f, -3.0f)), 0.25);  // 클램프
    CHECK_EQ(static_cast<double>(mix(0.25f, 0.75f, 4.0f)), 0.75);   // 클램프

    CHECK_EQ(static_cast<double>(smoothstep(0.82f, 0.97f, 0.5f)), 0.0);
    CHECK_EQ(static_cast<double>(smoothstep(0.82f, 0.97f, 1.0f)), 1.0);
    CHECK(std::fabs(smoothstep(0.0f, 1.0f, 0.5f) - 0.5f) < 1e-6f);

    // edge0 == edge1 이면 계단 함수.
    CHECK_EQ(static_cast<double>(smoothstep(0.5f, 0.5f, 0.4f)), 0.0);
    CHECK_EQ(static_cast<double>(smoothstep(0.5f, 0.5f, 0.5f)), 1.0);
    CHECK_EQ(static_cast<double>(smoothstep(0.5f, 0.5f, 0.6f)), 1.0);
}

// --- imaging/merge --------------------------------------------------------
//
// 병합 결과 자체는 파리티 하네스가 Swift 원본과 픽셀 단위로 대조한다
// (float 비트 패턴과 UInt16 을 둘 다 본다). 여기 있는 것은 경계 조건과
// 파리티로 만들기 어려운 경로다.

/// 모든 픽셀이 같은 값인 RGBA float 이미지.
std::vector<float> uniformImage(int width, int height, float value) {
    std::vector<float> out(static_cast<size_t>(width * height * 4), 0.0f);
    for (int p = 0; p < width * height; ++p) {
        const size_t i = static_cast<size_t>(p * 4);
        out[i] = value;
        out[i + 1] = value;
        out[i + 2] = value;
        out[i + 3] = 1.0f;
    }
    return out;
}

void testReferenceExposureTime() {
    using negaflow::util::referenceExposureTime;

    CHECK(referenceExposureTime(std::vector<int>{}) == std::nullopt);
    CHECK(referenceExposureTime(std::vector<int>{14000}) == std::optional<int>{14000});

    // 계획 [11000, 14000, 30000] → 고유 3개 → 인덱스 1 → 14000.
    const std::vector<int> plan{11000, 14000, 30000};
    CHECK(referenceExposureTime(plan) == std::optional<int>{14000});

    // **중복을 먼저 제거한다.** samplesPerStop 이 기준을 흔들면 안 된다.
    const std::vector<int> repeated{11000, 11000, 11000, 14000, 30000};
    CHECK(referenceExposureTime(repeated) == std::optional<int>{14000});

    // 입력 순서와 무관하다.
    const std::vector<int> reversed{30000, 14000, 11000};
    CHECK(referenceExposureTime(reversed) == std::optional<int>{14000});

    // 짝수 개면 count/2 가 절삭이므로 **위쪽** 중앙이다.
    const std::vector<int> even{1, 2, 3, 4};
    CHECK(referenceExposureTime(even) == std::optional<int>{3});
}

void testReferenceExposureIndexTieBreak() {
    using negaflow::imaging::referenceExposureIndex;

    const std::vector<int> plan{11000, 14000, 30000};
    CHECK_EQ(referenceExposureIndex(plan, 14000), size_t{1});

    // **동률에서는 첫 원소가 이긴다.** Swift min(by:) 가 엄격 비교이기 때문이다.
    const std::vector<int> tied{11000, 17000, 11000};  // 14000 에서 거리 3000 동률
    CHECK_EQ(referenceExposureIndex(tied, 14000), size_t{0});

    const std::vector<int> repeated{14000, 14000, 14000};
    CHECK_EQ(referenceExposureIndex(repeated, 14000), size_t{0});

    // 비어 있으면 0 (Swift 의 `?? 0`).
    CHECK_EQ(referenceExposureIndex(std::vector<int>{}, 14000), size_t{0});
}

void testNormalizeExposure() {
    using negaflow::imaging::normalizeExposure;

    const auto image = uniformImage(2, 1, 0.25f);

    // 기준과 같으면 배율 1.
    const auto same = normalizeExposure(image, 14000, 14000);
    CHECK_EQ(static_cast<double>(same[0]), 0.25);
    CHECK_EQ(static_cast<double>(same[3]), 1.0);

    // 짧은 노출은 값이 **커진다**.
    const auto shortExposure = normalizeExposure(image, 7000, 14000);
    CHECK_EQ(static_cast<double>(shortExposure[0]), 0.5);
    CHECK_EQ(static_cast<double>(shortExposure[1]), 0.5);
    CHECK_EQ(static_cast<double>(shortExposure[2]), 0.5);
    CHECK_EQ(static_cast<double>(shortExposure[3]), 1.0);  // 알파는 1 로 덮어쓴다

    // 긴 노출은 작아진다. 1 을 넘는 값도 클램프하지 않는다 — 병합 뒤에 한다.
    const auto longExposure = normalizeExposure(image, 28000, 14000);
    CHECK_EQ(static_cast<double>(longExposure[0]), 0.125);
    // float 끼리 비교한다 — static_cast<double>(1.6f) != 1.6 이다.
    const auto amplified = normalizeExposure(uniformImage(1, 1, 0.8f), 7000, 14000);
    CHECK(amplified[0] == 1.6f);
}

void testNormalizeExposureFormulaIsExact() {
    using namespace negaflow::imaging;

    // **이 항등식이 지연 정규화의 근거다.** 병합 루프는 정규화 배열을 만들지
    // 않고 `raw * scale` 을 그때그때 계산하는데, 그것이 비트 단위로 같다는
    // 보장이 여기 있다. 식이 갈리면 메모리는 줄고 결과가 조용히 달라진다.
    // 근거: windows_docs/04-imaging/exposure-merge.md §7.2
    const std::vector<int> pairs[] = {{11000, 14000}, {30000, 14000}, {14000, 14000},
                                      {1, 65535},     {7, 3}};
    const float samples[] = {0.0f,      1.0f,     0.5f,      0.006f, 0.985f,
                             0.123456f, 1.0e-7f,  0.999999f, -0.25f, 2.75f};

    for (const auto& pair : pairs) {
        const int exposureTime = pair[0];
        const int referenceExposure = pair[1];
        const float scale =
            static_cast<float>(referenceExposure) / static_cast<float>(exposureTime);

        std::vector<float> input;
        for (float v : samples) {
            input.push_back(v);
            input.push_back(v);
            input.push_back(v);
            input.push_back(0.5f);  // 알파는 덮어써져야 한다
        }
        const auto out = normalizeExposure(input, exposureTime, referenceExposure);

        bool exact = true;
        bool alphaOne = true;
        for (size_t i = 0; i + 3 < out.size(); i += 4) {
            for (size_t c = 0; c < 3; ++c) {
                if (out[i + c] != input[i + c] * scale) exact = false;
            }
            if (out[i + 3] != 1.0f) alphaOne = false;
        }
        CHECK(exact);
        CHECK(alphaOne);
    }

    // 배율이 정확히 1 이면 값이 그대로여야 한다 — 곱셈이 값을 건드리지 않는다.
    const auto identity = normalizeExposure(uniformImage(2, 2, 0.123456f), 14000, 14000);
    CHECK(identity[0] == 0.123456f);
}

void testMergeQuantizationTruncates() {
    using namespace negaflow::imaging;

    // 단일 패스 + 기준 노출 일치 → 배율 1, 혼합 없음 → 출력 = clamp(raw).
    // 그러면 양자화만 남으므로 **절삭**을 직접 확인할 수 있다.
    const int w = 8, h = 8;
    const auto image = uniformImage(w, h, 0.5f);
    ImageList rendered{image};
    const std::vector<int> exposures{14000};

    const auto out = mergeHardwareExposureBitmap(rendered, exposures, w, h);
    CHECK(!out.failure.has_value());
    CHECK_EQ(out.bitmap.width, w);
    CHECK_EQ(out.bitmap.height, h);
    CHECK_EQ(out.bitmap.pixels.size(), static_cast<size_t>(w * h * 3));  // 알파 없음

    // 0.5 * 65535 = 32767.5 → 절삭 → 32767. **반올림이면 32768 이 된다.**
    CHECK_EQ(static_cast<int>(out.bitmap.pixels[0]), 32767);
    CHECK_EQ(static_cast<int>(out.bitmap.pixels[1]), 32767);
    CHECK_EQ(static_cast<int>(out.bitmap.pixels[2]), 32767);

    // 상단은 포화한다.
    const auto white = uniformImage(w, h, 1.0f);
    ImageList whiteList{white};
    const auto top = mergeHardwareExposureBitmap(whiteList, exposures, w, h);
    CHECK(!top.failure.has_value());
    CHECK_EQ(static_cast<int>(top.bitmap.pixels[0]), 65535);

    // 음수는 0 으로 클램프된다.
    const auto negative = uniformImage(w, h, -0.3f);
    ImageList negativeList{negative};
    const auto bottom = mergeHardwareExposureBitmap(negativeList, exposures, w, h);
    CHECK(!bottom.failure.has_value());
    CHECK_EQ(static_cast<int>(bottom.bitmap.pixels[0]), 0);
}

void testMergeFailures() {
    using namespace negaflow::imaging;

    const auto image = uniformImage(4, 4, 0.5f);
    ImageList one{image};

    // 이미지 수와 노출 수가 다르다.
    const std::vector<int> two{11000, 14000};
    const auto mismatch = mergeHardwareExposureBitmap(one, two, 4, 4);
    CHECK(mismatch.failure == std::optional<Failure>{Failure::ExposureInputMismatch});

    // 비어 있다.
    const auto empty = mergeHardwareExposureBitmap(ImageList{}, std::vector<int>{}, 4, 4);
    CHECK(empty.failure == std::optional<Failure>{Failure::ExposureInputMismatch});

    // 기준 노출이 0 이하 — 정규화 배율이 0 이 되므로 진행할 수 없다.
    const std::vector<int> zero{0};
    const auto badReference = mergeHardwareExposureBitmap(one, zero, 4, 4);
    CHECK(badReference.failure == std::optional<Failure>{Failure::ExposureReferenceInvalid});

    // 크기가 0 이하.
    const std::vector<int> ok{14000};
    const auto badSize = mergeHardwareExposureBitmap(one, ok, 0, 4);
    CHECK(badSize.failure == std::optional<Failure>{Failure::ExposureSizeInvalid});

    // 평균 경로.
    const auto noSamples = averageMultiSampleBitmap(ImageList{}, 4, 4);
    CHECK(noSamples.failure == std::optional<Failure>{Failure::MultiSampleLoadFailed});
    const auto badAverageSize = averageMultiSampleBitmap(one, 4, 0);
    CHECK(badAverageSize.failure == std::optional<Failure>{Failure::MultiSampleSizeInvalid});

    // 메시지는 Swift 가 던지는 문구와 글자까지 같아야 한다.
    CHECK_EQ(std::string(failureMessage(Failure::ExposureInputMismatch)),
             std::string("hardware exposure 입력 오류"));
    CHECK_EQ(std::string(failureMessage(Failure::MultiSampleLoadFailed)),
             std::string("multi-sample TIFF 로드 실패"));
}

void testAverageMultiSampleAlpha() {
    using namespace negaflow::imaging;

    // 같은 이미지 3장의 평균은 원본과 같다 — 정렬이 (0,0) 이고 카운트가 3 이다.
    const int w = 8, h = 8;
    const auto image = uniformImage(w, h, 0.25f);
    ImageList rendered{image, image, image};

    const auto averaged = alignedAverageRGBAf(rendered, w, h);
    CHECK(!averaged.failure.has_value());
    CHECK(std::fabs(averaged.bitmap.pixels[0] - 0.25f) < 1e-6f);
    CHECK_EQ(static_cast<double>(averaged.bitmap.pixels[3]), 1.0);  // 알파는 1

    const auto quantized = averageMultiSampleBitmap(rendered, w, h);
    CHECK(!quantized.failure.has_value());
    CHECK_EQ(quantized.bitmap.pixels.size(), static_cast<size_t>(w * h * 3));
    // 0.25 * 65535 = 16383.75 → 절삭 → 16383
    CHECK_EQ(static_cast<int>(quantized.bitmap.pixels[0]), 16383);
}

// --- imaging/tiff_contract ------------------------------------------------
//
// 태그 판정은 순수하므로 libtiff 없이 전부 고정할 수 있다.
// 메시지 문구가 Swift 와 같아야 한다 — wire v2 에 code 필드가 없어서
// 메시지가 유일한 전달 수단이다(I-5).

/// 통과하는 기본값. 각 테스트가 필요한 필드만 바꾼다.
negaflow::imaging::TiffTags goodTags() {
    using namespace negaflow::imaging;
    TiffTags t;
    t.width = 100;
    t.height = 80;
    t.bitsPerSample = 16;
    t.samplesPerPixel = 3;
    t.photometric = tifftag::kPhotometricRGB;
    t.planarConfig = tifftag::kPlanarConfigContig;
    t.sampleFormat = tifftag::kSampleFormatUInt;
    t.compression = tifftag::kCompressionNone;
    t.directoryCount = 1;
    t.bigTiff = false;
    return t;
}

void testColorModeFromTags() {
    using namespace negaflow::imaging;
    using negaflow::sane::ColorMode;

    CHECK(colorModeFromTags(goodTags()) == std::optional<ColorMode>{ColorMode::Color});

    auto gray = goodTags();
    gray.photometric = tifftag::kPhotometricMinIsBlack;
    gray.samplesPerPixel = 1;
    CHECK(colorModeFromTags(gray) == std::optional<ColorMode>{ColorMode::Gray});

    // MINISWHITE 도 여기서는 Gray 다 — macOS 가 colorSpace.model 만 보기 때문.
    // 거부는 validateStrictTags 가 한다.
    auto inverted = gray;
    inverted.photometric = tifftag::kPhotometricMinIsWhite;
    CHECK(colorModeFromTags(inverted) == std::optional<ColorMode>{ColorMode::Gray});

    // RGB 인데 채널이 부족하다.
    auto shortRGB = goodTags();
    shortRGB.samplesPerPixel = 2;
    CHECK(colorModeFromTags(shortRGB) == std::nullopt);

    // gray 인데 채널이 여럿이다.
    auto fatGray = gray;
    fatGray.samplesPerPixel = 2;
    CHECK(colorModeFromTags(fatGray) == std::nullopt);

    // 팔레트 등 그 외 photometric.
    auto palette = goodTags();
    palette.photometric = 3;
    CHECK(colorModeFromTags(palette) == std::nullopt);
}

void testTiffValidationOrder() {
    using namespace negaflow::imaging;
    using negaflow::sane::BitDepth;
    using negaflow::sane::ColorMode;

    CHECK(!validateScannedTiffTags(goodTags(), BitDepth::Sixteen, ColorMode::Color).has_value());

    // 멀티페이지는 조용한 데이터 손실이므로 컨테이너 단계에서 막는다.
    auto multipage = goodTags();
    multipage.directoryCount = 2;
    CHECK_EQ(validateScannedTiffTags(multipage, BitDepth::Sixteen, ColorMode::Color)
                 .value_or(std::string{}),
             std::string("scanimage 출력 형식이 단일 TIFF가 아닙니다."));

    // bitsPerSample 12 는 Swift 에서 BitDepth(rawValue:) 가 nil 이라
    // **"decode할 수 없습니다"** 로 나온다. "bitDepth 불일치" 가 아니다.
    auto odd = goodTags();
    odd.bitsPerSample = 12;
    CHECK_EQ(validateScannedTiffTags(odd, BitDepth::Sixteen, ColorMode::Color)
                 .value_or(std::string{}),
             std::string("scanimage TIFF를 실제 이미지로 decode할 수 없습니다."));

    auto empty = goodTags();
    empty.width = 0;
    CHECK_EQ(validateScannedTiffTags(empty, BitDepth::Sixteen, ColorMode::Color)
                 .value_or(std::string{}),
             std::string("scanimage TIFF를 실제 이미지로 decode할 수 없습니다."));

    // **순서가 계약이다.** 심도와 색 모드가 둘 다 틀리면 색 모드가 먼저 나온다.
    auto both = goodTags();
    both.bitsPerSample = 8;
    both.photometric = 3;  // 판정 불가
    CHECK_EQ(validateScannedTiffTags(both, BitDepth::Sixteen, ColorMode::Color)
                 .value_or(std::string{}),
             std::string("scanimage TIFF color model이 RGB/Gray가 아닙니다."));

    auto shallow = goodTags();
    shallow.bitsPerSample = 8;
    CHECK_EQ(validateScannedTiffTags(shallow, BitDepth::Sixteen, ColorMode::Color)
                 .value_or(std::string{}),
             std::string("scanimage TIFF bitDepth 불일치: requested 16, actual 8"));

    auto grayFile = goodTags();
    grayFile.photometric = tifftag::kPhotometricMinIsBlack;
    grayFile.samplesPerPixel = 1;
    CHECK_EQ(validateScannedTiffTags(grayFile, BitDepth::Sixteen, ColorMode::Color)
                 .value_or(std::string{}),
             std::string("scanimage TIFF colorMode 불일치: requested color, actual gray"));
}

void testTiffStrictTags() {
    using namespace negaflow::imaging;
    using negaflow::sane::BitDepth;
    using negaflow::sane::ColorMode;

    // SAMPLEFORMAT 태그가 **없어도** 통과한다 — 규격 기본값이 UINT 다.
    auto missing = goodTags();
    missing.sampleFormat = std::nullopt;
    CHECK(!validateScannedTiffTags(missing, BitDepth::Sixteen, ColorMode::Color).has_value());

    // float TIFF 를 16-bit 정수로 오인하면 값이 통째로 엉뚱해진다.
    auto floatFile = goodTags();
    floatFile.sampleFormat = tifftag::kSampleFormatIEEEFP;
    CHECK_EQ(validateScannedTiffTags(floatFile, BitDepth::Sixteen, ColorMode::Color)
                 .value_or(std::string{}),
             std::string("scanimage TIFF sample format이 부호 없는 정수가 아닙니다."));

    auto separate = goodTags();
    separate.planarConfig = tifftag::kPlanarConfigSeparate;
    CHECK_EQ(validateScannedTiffTags(separate, BitDepth::Sixteen, ColorMode::Color)
                 .value_or(std::string{}),
             std::string("scanimage TIFF planar configuration이 interleaved가 아닙니다."));

    // MINISWHITE — macOS 는 통과시킨다. **여기서만 거부한다(D-10).**
    auto inverted = goodTags();
    inverted.photometric = tifftag::kPhotometricMinIsWhite;
    inverted.samplesPerPixel = 1;
    CHECK_EQ(validateScannedTiffTags(inverted, BitDepth::Sixteen, ColorMode::Gray)
                 .value_or(std::string{}),
             std::string("scanimage TIFF photometric이 MINISWHITE입니다. 밝기 의미가 반전됩니다."));

    auto big = goodTags();
    big.bigTiff = true;
    CHECK_EQ(validateScannedTiffTags(big, BitDepth::Sixteen, ColorMode::Color)
                 .value_or(std::string{}),
             std::string("scanimage 출력이 BigTIFF입니다. 표준 TIFF만 지원합니다."));

    // RGBA 인데 EXTRASAMPLES 가 없다.
    auto extra = goodTags();
    extra.samplesPerPixel = 4;
    CHECK_EQ(validateScannedTiffTags(extra, BitDepth::Sixteen, ColorMode::Color)
                 .value_or(std::string{}),
             std::string("scanimage TIFF에 정체가 명시되지 않은 추가 샘플이 있습니다."));

    // 명시돼 있으면 통과한다.
    auto declared = extra;
    declared.extraSamples = 1;
    CHECK(!validateScannedTiffTags(declared, BitDepth::Sixteen, ColorMode::Color).has_value());

    // **macOS 가 검출하는 실패가 먼저 나온다.** BigTIFF 이면서 심도도 틀리면
    // 심도 메시지가 이긴다 — 그래야 같은 파일이 두 OS 에서 같게 보인다.
    auto bigAndShallow = goodTags();
    bigAndShallow.bigTiff = true;
    bigAndShallow.bitsPerSample = 8;
    CHECK_EQ(validateScannedTiffTags(bigAndShallow, BitDepth::Sixteen, ColorMode::Color)
                 .value_or(std::string{}),
             std::string("scanimage TIFF bitDepth 불일치: requested 16, actual 8"));
}

void testTiffFileAttributes() {
    using negaflow::imaging::validateFileAttributes;
    const std::string expected = "scanimage 출력이 비어 있거나 regular file이 아닙니다.";

    CHECK(!validateFileAttributes(true, false, 1024).has_value());
    CHECK_EQ(validateFileAttributes(false, false, 1024).value_or(std::string{}), expected);
    CHECK_EQ(validateFileAttributes(true, true, 1024).value_or(std::string{}), expected);
    CHECK_EQ(validateFileAttributes(true, false, 0).value_or(std::string{}), expected);
}

// --- imaging/tiff_io ------------------------------------------------------
//
// libtiff 가 있을 때만 돈다. **순수 부분은 libtiff 없이도 전부 검증된다** —
// 그 분리를 유지하는 것이 이 계층 설계의 요점이다.

// --- wire/request ---------------------------------------------------------
//
// 가드 순서와 문구는 파리티 하네스가 Swift 원본과 45 케이스로 대조한다.
// 여기 있는 것은 **파리티가 닿을 수 없는 것** — Windows 경로 정책이다.
// macOS 에는 대응물이 없으므로(§3.1 이 새로 정한 규칙) 표를 항목별로 고정한다.

void testWindowsOutputPathPolicy() {
    using negaflow::wire::isAcceptableOutputPath;
    using negaflow::wire::PathPolicy;
    const auto win = PathPolicy::WindowsAbsolute;

    // 통과해야 하는 것.
    CHECK(isAcceptableOutputPath("C:\\Users\\me\\scan\\frame.tiff", win));
    CHECK(isAcceptableOutputPath("D:\\frame.tiff", win));
    CHECK(isAcceptableOutputPath("c:\\frame.tiff", win));   // 소문자 드라이브
    CHECK(isAcceptableOutputPath("C:\\a b\\frame.tiff", win));  // 중간 공백은 정상
    CHECK(isAcceptableOutputPath("C:\\스캔\\frame.tiff", win));  // 비ASCII 정상

    // 형태 — 드라이브 절대 경로가 아니다.
    CHECK(!isAcceptableOutputPath("C:frame.tiff", win));    // 드라이브 상대
    CHECK(!isAcceptableOutputPath("\\frame.tiff", win));    // 루트 상대
    CHECK(!isAcceptableOutputPath("frame.tiff", win));      // 상대
    CHECK(!isAcceptableOutputPath("C:\\", win));            // 디렉터리
    CHECK(!isAcceptableOutputPath("", win));
    CHECK(!isAcceptableOutputPath("1:\\frame.tiff", win));  // 드라이브 문자가 아님

    // UNC 와 장치 네임스페이스 — 정규화를 우회한다.
    CHECK(!isAcceptableOutputPath("\\\\server\\share\\frame.tiff", win));
    CHECK(!isAcceptableOutputPath("\\\\?\\C:\\frame.tiff", win));
    CHECK(!isAcceptableOutputPath("\\\\.\\C:\\frame.tiff", win));
    CHECK(!isAcceptableOutputPath("\\??\\C:\\frame.tiff", win));

    // 구성요소 — **경로 탈출을 여기서 막는다.** macOS 는 막지 못한다(§3.2).
    CHECK(!isAcceptableOutputPath("C:\\a\\..\\frame.tiff", win));
    CHECK(!isAcceptableOutputPath("C:\\a\\.\\frame.tiff", win));
    CHECK(!isAcceptableOutputPath("C:\\a\\\\frame.tiff", win));
    CHECK(!isAcceptableOutputPath("C:\\a\\frame.tiff\\", win));  // 후행 구분자

    // 슬래시 — Win32 는 받아들이지만 정규화하면 바이트가 달라진다.
    CHECK(!isAcceptableOutputPath("C:/frame.tiff", win));
    CHECK(!isAcceptableOutputPath("C:\\a/frame.tiff", win));

    // 예약 장치 이름 — 파일이 아니라 장치로 열린다. 확장자가 붙어도 같다.
    CHECK(!isAcceptableOutputPath("C:\\NUL", win));
    CHECK(!isAcceptableOutputPath("C:\\nul.tiff", win));
    CHECK(!isAcceptableOutputPath("C:\\CON.tiff", win));
    CHECK(!isAcceptableOutputPath("C:\\a\\COM1.tiff", win));
    CHECK(!isAcceptableOutputPath("C:\\LPT9", win));
    CHECK(!isAcceptableOutputPath("C:\\aux", win));
    // COM0 과 LPT0 은 예약이 아니다. 과잉 거부하지 않는다.
    CHECK(isAcceptableOutputPath("C:\\COM0.tiff", win));
    CHECK(isAcceptableOutputPath("C:\\CONSOLE.tiff", win));  // 접두사가 같을 뿐

    // 후행 점/공백 — Win32 가 조용히 잘라내 다른 파일을 연다.
    CHECK(!isAcceptableOutputPath("C:\\frame.tiff ", win));
    CHECK(!isAcceptableOutputPath("C:\\frame.tiff.", win));
    CHECK(!isAcceptableOutputPath("C:\\dir \\frame.tiff", win));

    // ADS — 본체가 못 읽는 곳에 쓰게 된다.
    CHECK(!isAcceptableOutputPath("C:\\frame.tiff:hidden", win));

    // Win32 가 금지하는 문자와 제어 문자.
    CHECK(!isAcceptableOutputPath("C:\\fra*me.tiff", win));
    CHECK(!isAcceptableOutputPath("C:\\fra?me.tiff", win));
    CHECK(!isAcceptableOutputPath("C:\\fra|me.tiff", win));
    CHECK(!isAcceptableOutputPath("C:\\fra\"me.tiff", win));
    CHECK(!isAcceptableOutputPath(std::string("C:\\fra\x01me.tiff"), win));
}

void testPosixPathPolicyMirrorsSwift() {
    using negaflow::wire::isAcceptableOutputPath;
    using negaflow::wire::PathPolicy;
    const auto posix = PathPolicy::PosixAbsolute;

    // **이 정책은 원본을 재현하는 것이 목적이지 안전한 것이 목적이 아니다.**
    // 실측(2026-08-05): URL(fileURLWithPath:).path 는 후행 슬래시만 없앤다.
    CHECK(isAcceptableOutputPath("/tmp/frame.tiff", posix));
    CHECK(isAcceptableOutputPath("/", posix));

    // macOS 가 통과시키는 것들 — 그래서 여기서도 통과시켜야 한다.
    CHECK(isAcceptableOutputPath("/tmp/../frame.tiff", posix));
    CHECK(isAcceptableOutputPath("/tmp/./frame.tiff", posix));
    CHECK(isAcceptableOutputPath("/tmp//frame.tiff", posix));
    CHECK(isAcceptableOutputPath("/tmp/a/../../../etc/passwd", posix));

    // 후행 슬래시만 걸린다.
    CHECK(!isAcceptableOutputPath("/tmp/frame/", posix));
    CHECK(!isAcceptableOutputPath("tmp/frame.tiff", posix));
    CHECK(!isAcceptableOutputPath("", posix));

    // **같은 경로가 두 정책에서 갈린다.** 이것이 의도된 divergence 다.
    CHECK(isAcceptableOutputPath("/tmp/../x.tiff", PathPolicy::PosixAbsolute));
    CHECK(!isAcceptableOutputPath("C:\\tmp\\..\\x.tiff", PathPolicy::WindowsAbsolute));
}

// --- wire/json ------------------------------------------------------------
//
// 파리티는 **정렬 출력**으로 바이트를 비교한다(Swift 키 순서가 해시라서).
// 그래서 파리티가 닿지 못하는 것이 여기 남는다:
//   - 선언 순서 출력 (제품 동작인데 파리티는 정렬만 쓴다)
//   - NaN/Inf 거부 (Swift 는 예외를 던지므로 파리티에 넣을 수 없다)
//   - 로케일 독립 (파리티는 C 로케일에서 돈다)

void testJsonDeclarationOrderIsProduction() {
    using namespace negaflow::wire;

    // **제품은 삽입 순서로 낸다.** 정렬은 파리티/골든 전용이다.
    JsonValue j = JsonValue::object();
    j.set("zebra", JsonValue::integer(1));
    j.set("alpha", JsonValue::integer(2));
    j.set("middle", JsonValue::integer(3));

    CHECK_EQ(writeJson(j, KeyOrder::Declaration).value_or(std::string{}),
             std::string(R"({"zebra":1,"alpha":2,"middle":3})"));
    CHECK_EQ(writeJson(j, KeyOrder::Sorted).value_or(std::string{}),
             std::string(R"({"alpha":2,"middle":3,"zebra":1})"));

    // 기본값이 제품 동작이어야 한다 — 실수로 정렬해 내보내면 wire 가 바뀐다.
    CHECK_EQ(writeJson(j).value_or(std::string{}),
             std::string(R"({"zebra":1,"alpha":2,"middle":3})"));

    // **배열 순서는 정렬 모드에서도 유지된다.** 배열 순서는 의미다.
    JsonValue arr = JsonValue::array();
    arr.push(JsonValue::string("z"));
    arr.push(JsonValue::string("a"));
    JsonValue wrapper = JsonValue::object();
    wrapper.set("items", arr);
    CHECK_EQ(writeJson(wrapper, KeyOrder::Sorted).value_or(std::string{}),
             std::string(R"({"items":["z","a"]})"));
}

void testJsonRejectsNonFinite() {
    using namespace negaflow::wire;

    // Swift JSONEncoder 는 NaN 에서 **예외를 던진다**(기본 .throw 전략).
    // 조용히 `NaN` 리터럴을 쓰면 비표준이고 호스트 디코더가 거부한다.
    CHECK(jsonNumber(std::nan("")) == std::nullopt);
    CHECK(jsonNumber(std::numeric_limits<double>::infinity()) == std::nullopt);
    CHECK(jsonNumber(-std::numeric_limits<double>::infinity()) == std::nullopt);

    JsonValue j = JsonValue::object();
    j.set("bad", JsonValue::number(std::nan("")));
    CHECK(writeJson(j) == std::nullopt);

    // 중첩 안쪽에 있어도 실패해야 한다 — 절반만 쓰고 성공하면 안 된다.
    JsonValue inner = JsonValue::object();
    inner.set("x", JsonValue::number(std::numeric_limits<double>::infinity()));
    JsonValue outer = JsonValue::object();
    outer.set("ok", JsonValue::integer(1));
    outer.set("inner", inner);
    CHECK(writeJson(outer) == std::nullopt);
}

void testJsonNumbersAreLocaleIndependent() {
    using namespace negaflow::wire;

    // 정상 경로.
    CHECK_EQ(jsonNumber(36.33).value_or(std::string{}), std::string("36.33"));
    CHECK_EQ(jsonNumber(1.0).value_or(std::string{}), std::string("1"));
    CHECK_EQ(jsonNumber(0.0).value_or(std::string{}), std::string("0"));
    CHECK_EQ(jsonNumber(-0.5).value_or(std::string{}), std::string("-0.5"));

    // **로케일이 소수점을 ',' 로 바꾸는 곳에서도 같아야 한다.**
    // std::ostream 이나 printf 를 썼다면 여기서 "36,33" 이 나오고 JSON 이 깨진다.
    const char* saved = std::setlocale(LC_ALL, nullptr);
    const std::string savedLocale = saved ? saved : "C";
    if (std::setlocale(LC_ALL, "de_DE.UTF-8") != nullptr) {
        CHECK_EQ(jsonNumber(36.33).value_or(std::string{}), std::string("36.33"));
        JsonValue j = JsonValue::object();
        j.set("widthMM", JsonValue::number(36.33));
        CHECK_EQ(writeJson(j).value_or(std::string{}), std::string(R"({"widthMM":36.33})"));
        std::setlocale(LC_ALL, savedLocale.c_str());
    }
    // de_DE 가 없는 시스템이면 위 블록을 건너뛴다 — 검사가 줄 뿐 거짓 통과는 아니다.
}

void testJsonEscaping() {
    using negaflow::wire::escapeJsonString;

    CHECK_EQ(escapeJsonString("plain"), std::string(R"("plain")"));
    CHECK_EQ(escapeJsonString("say \"hi\""), std::string(R"("say \"hi\"")"));
    CHECK_EQ(escapeJsonString("C:\\a"), std::string(R"("C:\\a")"));
    // `/` 는 이스케이프한다 — Swift JSONEncoder 의 기본이다(실측).
    CHECK_EQ(escapeJsonString("a/b"), std::string(R"("a\/b")"));
    CHECK_EQ(escapeJsonString("a\nb"), std::string(R"("a\nb")"));
    CHECK_EQ(escapeJsonString(std::string("a\x01" "b")), std::string(R"("a\u0001b")"));
    // 비ASCII 는 UTF-8 바이트 그대로. \uXXXX 로 바꾸지 않는다.
    CHECK_EQ(escapeJsonString("한글"), std::string("\"한글\""));
}

void testAppliedOptionsAlwaysHasTwelveKeys() {
    using namespace negaflow::wire;

    // **호스트가 12키를 필수로 요구한다.** 생략하면 decode failure 다.
    // 이 테스트가 setOrNull 을 setIfPresent 로 바꾸는 실수를 막는다.
    AppliedScanOptionsV2 options;
    options.deviceID = "d";
    options.colorMode = "color";
    options.filmType = "colorNegative";
    // hardwareExposureTime / brightnessAdjustment / contrastAdjustment 는 비어 있다.

    const auto text = writeJson(encodeAppliedOptions(options), KeyOrder::Sorted);
    CHECK(text.has_value());
    if (text) {
        CHECK(text->find("\"hardwareExposureTime\":null") != std::string::npos);
        CHECK(text->find("\"brightnessAdjustment\":null") != std::string::npos);
        CHECK(text->find("\"contrastAdjustment\":null") != std::string::npos);
        // 키 개수를 센다 — 최상위 12개.
        int colons = 0;
        int depth = 0;
        for (size_t i = 0; i < text->size(); ++i) {
            const char c = (*text)[i];
            if (c == '{') ++depth;
            if (c == '}') --depth;
            if (c == ':' && depth == 1) ++colons;
        }
        CHECK_EQ(colons, 12);
    }

    // 반대로 이벤트는 **없는 키를 쓰지 않는다.**
    ScanEventV2 event;
    event.type = "started";
    event.requestID = "3F2504E0-4F89-11D3-9A0C-0305E82C3301";
    const auto bare = writeJson(encodeScanEvent(event), KeyOrder::Sorted);
    CHECK(bare.has_value());
    if (bare) {
        CHECK(bare->find("phase") == std::string::npos);
        CHECK(bare->find("null") == std::string::npos);
    }
}

// --- wire/protocol --------------------------------------------------------
//
// 응답 형태는 파리티가 정렬 출력으로 바이트 비교한다.
// 여기 있는 것은 파리티가 닿지 못하는 **제품 키 순서**와, 생략 계약을
// 구조로 못박는 검사다.

/// 최상위 키 개수를 센다. 중첩 객체 안의 콜론은 빼고.
int topLevelKeyCount(const std::string& json) {
    int count = 0;
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (char c : json) {
        if (escaped) { escaped = false; continue; }
        if (inString) {
            if (c == '\\') escaped = true;
            else if (c == '"') inString = false;
            continue;
        }
        if (c == '"') inString = true;
        else if (c == '{' || c == '[') ++depth;
        else if (c == '}' || c == ']') --depth;
        else if (c == ':' && depth == 1) ++count;
    }
    return count;
}

void testDeviceOmitsNilKeys() {
    using namespace negaflow::wire;

    // **nil 은 생략이다. null 이 아니다.** 본체 §20 이 인수 gate 로 삼는다.
    PluginDevice bare;
    bare.id = "id";
    bare.displayName = "d";
    bare.vendor = "v";
    bare.model = "m";
    const auto bareText = writeJson(encodeDevice(bare), KeyOrder::Sorted);
    CHECK(bareText.has_value());
    if (bareText) {
        CHECK_EQ(topLevelKeyCount(*bareText), 4);
        CHECK(bareText->find("null") == std::string::npos);
        CHECK(bareText->find("serialNumber") == std::string::npos);
    }

    PluginDevice full = bare;
    full.connectionType = std::string("usb");
    full.usbVendorID = std::string("0x04b8");
    full.usbProductID = std::string("0x014a");
    full.serialNumber = std::string("SN1");
    full.verifiedStatus = std::string("untested");
    full.driverVersion = std::string("genesys (SANE)");
    const auto fullText = writeJson(encodeDevice(full), KeyOrder::Sorted);
    CHECK(fullText.has_value());
    if (fullText) CHECK_EQ(topLevelKeyCount(*fullText), 10);

    // 제품은 **선언 순서**로 낸다. 파리티는 정렬만 쓰므로 여기서 고정한다.
    CHECK_EQ(writeJson(encodeDevice(bare)).value_or(std::string{}),
             std::string(R"({"id":"id","displayName":"d","vendor":"v","model":"m"})"));
}

void testCapabilitiesOmissionContract() {
    using namespace negaflow::wire;

    // 필수 3키는 **빈 배열이어도 나온다.** 옵셔널이 아니기 때문이다.
    PluginCapabilities minimal;
    const auto minimalText = writeJson(encodeCapabilities(minimal), KeyOrder::Sorted);
    CHECK(minimalText.has_value());
    if (minimalText) {
        CHECK_EQ(topLevelKeyCount(*minimalText), 3);
        CHECK(minimalText->find("null") == std::string::npos);
        CHECK_EQ(*minimalText,
                 std::string(R"({"bitDepths":[],"modes":[],"resolutionsDPI":[]})"));
    }

    // **빈 딕셔너리는 nil 이 아니다.** `{}` 가 그대로 나간다 — 호스트가
    // "비활성 사유 없음"과 "사유를 모름"을 구분한다.
    PluginCapabilities withReasons = minimal;
    withReasons.disabledReasons = std::vector<std::pair<std::string, std::string>>{};
    const auto reasonsText = writeJson(encodeCapabilities(withReasons), KeyOrder::Sorted);
    CHECK(reasonsText.has_value());
    if (reasonsText) CHECK(reasonsText->find("\"disabledReasons\":{}") != std::string::npos);

    // **step 이 없으면 키가 없다.** ScannerOptionRange 도 합성 Codable 이다.
    PluginCapabilities withRange = minimal;
    withRange.scanWidthRange = negaflow::util::OptionRange{0.0, 36.33, std::nullopt};
    const auto rangeText = writeJson(encodeCapabilities(withRange), KeyOrder::Sorted);
    CHECK(rangeText.has_value());
    if (rangeText) {
        CHECK(rangeText->find("step") == std::string::npos);
        CHECK(rangeText->find(R"("scanWidthRange":{"maximum":36.33,"minimum":0})") !=
              std::string::npos);
    }

    // **false 와 부재는 다르다.** false 를 채워 넣으면 "지원하지 않음을
    // 확인했다"가 되고, 부재는 "모름"이다.
    PluginCapabilities withFalse = minimal;
    withFalse.supportsInfrared = false;
    const auto falseText = writeJson(encodeCapabilities(withFalse), KeyOrder::Sorted);
    CHECK(falseText.has_value());
    if (falseText) CHECK(falseText->find("\"supportsInfrared\":false") != std::string::npos);
}

void testDetectResponseShape() {
    using namespace negaflow::wire;

    CHECK_EQ(writeJson(encodeDetectResponse({})).value_or(std::string{}),
             std::string(R"({"devices":[]})"));

    // **배열 순서는 의미다.** 정렬 모드에서도 유지된다.
    PluginDevice a;
    a.id = "zebra";
    a.displayName = "Z";
    a.vendor = "Z";
    a.model = "Z";
    PluginDevice b = a;
    b.id = "alpha";
    const auto text = writeJson(encodeDetectResponse({a, b}), KeyOrder::Sorted);
    CHECK(text.has_value());
    if (text) {
        const auto first = text->find("zebra");
        const auto second = text->find("alpha");
        CHECK(first != std::string::npos && second != std::string::npos && first < second);
    }
}

// --- wire/emitter ---------------------------------------------------------
//
// **이 모듈에는 파리티가 없다.** Swift 짝(`ProtocolV2Emitter`)이 main.swift
// 안의 private 클래스라 파리티 바이너리에 넣을 수 없다. 이벤트 구성과 JSON
// 인코딩은 wire/event·wire/json 이 이미 대조하므로, 여기서 고정할 것은
// **sequence 규율**과 **줄 프레이밍** 둘뿐이다.

void testEmitterSequenceDiscipline() {
    using namespace negaflow::wire;

    EventEmitter emitter("7A91B43D-90F8-41E2-B71D-04D17CD9E03B");
    CHECK_EQ(static_cast<int>(emitter.nextSequence()), 0);

    // **0부터 1씩.** 건너뛰거나 중복되면 호스트가 이벤트 유실로 읽는다.
    for (int i = 0; i < 5; ++i) {
        ScanEventV2 e;
        e.type = "progress";
        e.phase = std::string("scanning");
        const auto line = emitter.emit(e);
        CHECK(line.has_value());
        if (line) {
            CHECK(line->find("\"sequence\":" + std::to_string(i)) != std::string::npos);
        }
        CHECK_EQ(static_cast<int>(emitter.nextSequence()), i + 1);
    }

    // **requestID 는 받은 문자열을 그대로 반사한다.** 파싱해서 다시 쓰지
    // 않는다 — Swift 는 대문자, Windows Guid 는 소문자라 형태가 갈린다(D-12).
    ScanEventV2 e;
    e.type = "started";
    e.requestID = "무시되어야 하는 값";
    const auto line = emitter.emit(e);
    CHECK(line.has_value());
    if (line) {
        CHECK(line->find("7A91B43D-90F8-41E2-B71D-04D17CD9E03B") != std::string::npos);
        CHECK(line->find("무시되어야") == std::string::npos);
    }
}

void testEmitterLineFraming() {
    using namespace negaflow::wire;

    EventEmitter emitter("R");
    ScanEventV2 e;
    e.type = "progress";
    const auto line = emitter.emit(e);
    CHECK(line.has_value());
    if (line) {
        // **개행이 정확히 하나, 맨 끝에.** 한 번의 쓰기로 나가야 하므로
        // JSON 과 개행이 한 문자열이다.
        CHECK(!line->empty() && line->back() == '\n');
        CHECK_EQ(static_cast<int>(std::count(line->begin(), line->end(), '\n')), 1);
        CHECK(line->front() == '{');
        // 개행 앞이 객체의 끝이어야 한다 — 사이에 공백이 없다.
        CHECK(line->size() >= 2 && (*line)[line->size() - 2] == '}');
    }

    // 리터럴 개행이 든 메시지는 **이스케이프돼야 한다.** 안 그러면 한 이벤트가
    // 두 줄이 되어 NDJSON 프레이밍이 깨진다.
    ScanEventV2 multiline;
    multiline.type = "error";
    multiline.message = std::string("첫 줄\n둘째 줄");
    const auto escaped = emitter.emit(multiline);
    CHECK(escaped.has_value());
    if (escaped) {
        CHECK_EQ(static_cast<int>(std::count(escaped->begin(), escaped->end(), '\n')), 1);
        CHECK(escaped->find("\\n") != std::string::npos);
    }
}

void testEmitterDoesNotConsumeSequenceOnFailure() {
    using namespace negaflow::wire;

    EventEmitter emitter("R");
    ScanEventV2 ok;
    ok.type = "progress";
    CHECK(emitter.emit(ok).has_value());
    CHECK_EQ(static_cast<int>(emitter.nextSequence()), 1);

    // NaN 은 인코딩에 실패한다. **나가지 않은 이벤트가 번호를 가져가면
    // sequence 에 구멍이 생기고 호스트는 그것을 유실로 읽는다.**
    ScanEventV2 bad;
    bad.type = "progress";
    bad.fraction = std::nan("");
    CHECK(!emitter.emit(bad).has_value());
    CHECK_EQ(static_cast<int>(emitter.nextSequence()), 1);

    // 다음 성공 이벤트가 1번을 이어받는다.
    const auto next = emitter.emit(ok);
    CHECK(next.has_value());
    if (next) CHECK(next->find("\"sequence\":1") != std::string::npos);
}

void testErrorEventHasFiveKeys() {
    using namespace negaflow::wire;

    // **error 이벤트는 5개 키가 전부다.** 필드를 더하면 macOS 와 형태가 갈린다.
    EventEmitter emitter("7A91B43D-90F8-41E2-B71D-04D17CD9E03B");
    const auto line = emitter.emit(makeErrorEvent("unsupportedOption: 지원하지 않는 bitDepth: 12"));
    CHECK(line.has_value());
    if (line) {
        std::string json = *line;
        json.pop_back();  // 개행 제거
        CHECK_EQ(topLevelKeyCount(json), 5);
        CHECK(json.find("\"type\":\"error\"") != std::string::npos);
        CHECK(json.find("\"protocolVersion\":2") != std::string::npos);
        CHECK(json.find("null") == std::string::npos);
        // 선언 순서로 나온다 — 제품 동작이다.
        CHECK(json.rfind(R"({"type":"error","protocolVersion":2,)", 0) == 0);
    }
}

#ifdef NEGAFLOW_HAVE_LIBTIFF

std::filesystem::path scratchPath(const char* name) {
    return std::filesystem::temp_directory_path() / name;
}

void testTiffWriteReadRoundTrip() {
    using namespace negaflow::imaging;

    const int w = 5, h = 3;
    // 경계값을 넣는다. 0 과 65535 는 정규화의 양끝이고 32768 은 0.5 근처다.
    std::vector<std::uint16_t> pixels(static_cast<size_t>(w * h * 3), 0);
    const std::uint16_t marks[] = {0, 1, 255, 256, 32767, 32768, 65534, 65535};
    for (size_t i = 0; i < pixels.size(); ++i) {
        pixels[i] = marks[i % (sizeof(marks) / sizeof(marks[0]))];
    }

    const auto path = scratchPath("negaflow_roundtrip.tif");
    std::error_code ec;
    std::filesystem::remove(path, ec);
    CHECK(tiffio::writeRGB16TIFF(pixels, w, h, path));

    // 임시 파일이 남지 않아야 한다 — rename 이 성공했다는 뜻이다.
    auto partial = path;
    partial += ".partial";
    CHECK(!std::filesystem::exists(partial));

    const auto tags = tiffio::readTags(path);
    CHECK(tags.has_value());
    if (tags) {
        CHECK_EQ(static_cast<int>(tags->width), w);
        CHECK_EQ(static_cast<int>(tags->height), h);
        CHECK_EQ(static_cast<int>(tags->bitsPerSample), 16);
        CHECK_EQ(static_cast<int>(tags->samplesPerPixel), 3);
        CHECK_EQ(static_cast<int>(tags->photometric), int{tifftag::kPhotometricRGB});
        CHECK_EQ(static_cast<int>(tags->planarConfig), int{tifftag::kPlanarConfigContig});
        CHECK_EQ(static_cast<int>(tags->compression), int{tifftag::kCompressionNone});
        CHECK_EQ(static_cast<int>(tags->directoryCount), 1);
        CHECK(!tags->bigTiff);
        CHECK(tags->sampleFormat == std::optional<std::uint16_t>{tifftag::kSampleFormatUInt});

        // **색 계약.** 프로파일이 박히면 본체가 감마 도메인으로 읽어 색이
        // 무너지는데, 스캔은 성공하고 검증도 통과하므로 가장 늦게 발견된다.
        CHECK(!tags->hasIccProfile);
        CHECK(!tags->hasTransferFunction);
    }

    // 읽어 온 float 가 v / 65535.0f 와 **비트 단위로** 같아야 한다(N-1).
    const auto loaded = tiffio::loadScannerTIFF(path);
    CHECK(loaded.has_value());
    if (loaded) {
        CHECK_EQ(loaded->width, w);
        CHECK_EQ(loaded->height, h);
        bool exact = true;
        bool alphaOne = true;
        for (int p = 0; p < w * h; ++p) {
            for (int c = 0; c < 3; ++c) {
                const float expected =
                    static_cast<float>(pixels[static_cast<size_t>(p * 3 + c)]) / 65535.0f;
                const float actual = loaded->pixels[static_cast<size_t>(p * 4 + c)];
                if (actual != expected) exact = false;
            }
            if (loaded->pixels[static_cast<size_t>(p * 4 + 3)] != 1.0f) alphaOne = false;
        }
        CHECK(exact);
        CHECK(alphaOne);
    }

    const auto size = tiffio::imageSize(path);
    CHECK_EQ(size.first, w);
    CHECK_EQ(size.second, h);

    std::filesystem::remove(path, ec);
}

void testTiffValidatedScannedTIFF() {
    using namespace negaflow::imaging;
    using negaflow::sane::BitDepth;
    using negaflow::sane::ColorMode;

    const int w = 4, h = 4;
    const std::vector<std::uint16_t> pixels(static_cast<size_t>(w * h * 3), 4242);
    const auto path = scratchPath("negaflow_validate.tif");
    std::error_code ec;
    std::filesystem::remove(path, ec);
    CHECK(tiffio::writeRGB16TIFF(pixels, w, h, path));

    // 우리 산출물이 우리 검증을 통과해야 한다. 통과하지 못하면 writer 나
    // 검증 계약 중 하나가 틀린 것이다.
    tiffio::ScannedTiffMetadata meta;
    CHECK(!tiffio::validatedScannedTIFF(path, BitDepth::Sixteen, ColorMode::Color, &meta)
               .has_value());
    CHECK_EQ(meta.width, w);
    CHECK_EQ(meta.height, h);
    CHECK(meta.bitDepth == BitDepth::Sixteen);
    CHECK(meta.colorMode == ColorMode::Color);

    // 기대와 어긋나면 Swift 와 같은 문구가 나와야 한다.
    CHECK_EQ(tiffio::validatedScannedTIFF(path, BitDepth::Eight, ColorMode::Color, nullptr)
                 .value_or(std::string{}),
             std::string("scanimage TIFF bitDepth 불일치: requested 8, actual 16"));
    CHECK_EQ(tiffio::validatedScannedTIFF(path, BitDepth::Sixteen, ColorMode::Gray, nullptr)
                 .value_or(std::string{}),
             std::string("scanimage TIFF colorMode 불일치: requested gray, actual color"));

    std::filesystem::remove(path, ec);
}

void testTiffMissingAndBrokenFiles() {
    using namespace negaflow::imaging;
    using negaflow::sane::BitDepth;
    using negaflow::sane::ColorMode;

    const auto missing = scratchPath("negaflow_does_not_exist.tif");
    std::error_code ec;
    std::filesystem::remove(missing, ec);

    // **IR 경로의 계약**: 실패가 예외가 아니라 (0,0) 이다.
    const auto size = tiffio::imageSize(missing);
    CHECK_EQ(size.first, 0);
    CHECK_EQ(size.second, 0);

    CHECK(!tiffio::readTags(missing).has_value());
    CHECK(!tiffio::loadScannerTIFF(missing).has_value());
    CHECK(!tiffio::verifyDecodable(missing));
    CHECK(tiffio::validatedScannedTIFF(missing, BitDepth::Sixteen, ColorMode::Color, nullptr)
              .has_value());

    // 빈 파일은 파일 계층에서 걸린다.
    const auto empty = scratchPath("negaflow_empty.tif");
    { std::ofstream create(empty, std::ios::binary); }
    CHECK_EQ(tiffio::validatedScannedTIFF(empty, BitDepth::Sixteen, ColorMode::Color, nullptr)
                 .value_or(std::string{}),
             std::string("scanimage 출력이 비어 있거나 regular file이 아닙니다."));

    // TIFF 가 아닌 내용은 컨테이너 계층에서 걸린다.
    const auto garbage = scratchPath("negaflow_garbage.tif");
    {
        std::ofstream create(garbage, std::ios::binary);
        create << "this is definitely not a TIFF file";
    }
    CHECK_EQ(tiffio::validatedScannedTIFF(garbage, BitDepth::Sixteen, ColorMode::Color, nullptr)
                 .value_or(std::string{}),
             std::string("scanimage 출력 형식이 단일 TIFF가 아닙니다."));

    // **libtiff 메시지를 삼키지 않는다.** 사용자에게 나가는 문구는 Swift 와
    // 같아야 하므로 고정돼 있지만, "왜 못 읽었는지"는 진단으로 남아야 한다.
    // 지원하지 않는 코덱을 만났을 때가 이 창구가 필요한 대표적인 경우다.
    CHECK(!tiffio::readTags(garbage).has_value());
    CHECK(!tiffio::lastTiffMessage().empty());

    // 성공한 호출 뒤에는 남아 있지 않아야 한다 — 오래된 메시지를 새 실패의
    // 원인으로 오해하면 진단이 거짓말을 한다.
    const auto clean = scratchPath("negaflow_clean.tif");
    const std::vector<std::uint16_t> ok(3 * 4, 1000);
    CHECK(tiffio::writeRGB16TIFF(ok, 2, 2, clean));
    CHECK(tiffio::readTags(clean).has_value());
    CHECK(tiffio::lastTiffMessage().empty());

    std::filesystem::remove(clean, ec);
    std::filesystem::remove(empty, ec);
    std::filesystem::remove(garbage, ec);
}

void testTiffWriteRejectsBadInput() {
    using namespace negaflow::imaging;
    const auto path = scratchPath("negaflow_reject.tif");
    std::error_code ec;
    std::filesystem::remove(path, ec);

    const std::vector<std::uint16_t> tooSmall(3, 0);
    CHECK(!tiffio::writeRGB16TIFF(tooSmall, 4, 4, path));  // 버퍼가 부족하다
    CHECK(!tiffio::writeRGB16TIFF(tooSmall, 0, 1, path));
    CHECK(!tiffio::writeRGB16TIFF(tooSmall, 1, -1, path));
    // 거부했으면 파일을 만들지 않았어야 한다.
    CHECK(!std::filesystem::exists(path));
}

#endif  // NEGAFLOW_HAVE_LIBTIFF

// --- 표준 라이브러리 특성 검사 -------------------------------------------
//
// **이식 코드가 아니라 툴체인을 잰다.** 여기가 터지면 우리 코드가 아니라
// `std::from_chars` 구현이 다른 것이다 — 그 구분이 중요해서 따로 뒀다.
//
// `wire/parse` 의 수 판정 전체가 `from_chars` 의 `result_out_of_range` 위에
// 서 있고, 그 동작을 **libc++ 에서 실측해** macOS `JSONDecoder` 와 맞췄다.
// MSVC 나 libstdc++ 이 다르게 판정하면 같은 요청이 OS 마다 다르게 처리된다.
//
// `sane/option_dump` 도 같은 함수를 쓴다(3곳). 그쪽은 scanimage 가 내는
// 평범한 수라 실질 위험이 낮지만, **파리티로 검증된 코드**라 갈리면 더 아프다.
//
// 근거: windows/src/wire/parse.h 의 실측 표

void testFromCharsOutOfRangeContract() {
    const auto classify = [](const char* text) {
        double value = 0.0;
        const char* first = text;
        const char* last = text + std::char_traits<char>::length(text);
        const auto r = std::from_chars(first, last, value);
        if (r.ptr != last) return std::string("partial");
        if (r.ec == std::errc::result_out_of_range) return std::string("out_of_range");
        if (r.ec != std::errc{}) return std::string("invalid");
        return std::string("ok");
    };

    // 정상·준정규는 수락한다. 4.9e-324 는 가장 작은 준정규다.
    CHECK_EQ(classify("1e-308"), std::string("ok"));
    CHECK_EQ(classify("1e-320"), std::string("ok"));
    CHECK_EQ(classify("1e-323"), std::string("ok"));
    CHECK_EQ(classify("4.9e-324"), std::string("ok"));
    CHECK_EQ(classify("1e308"), std::string("ok"));

    // **언더플로는 out_of_range 여야 한다.** 0 으로 조용히 내려앉으면
    // macOS 가 거부하는 요청을 Windows 가 받아들인다.
    CHECK_EQ(classify("1e-324"), std::string("out_of_range"));
    CHECK_EQ(classify("1e-400"), std::string("out_of_range"));

    // 오버플로도 out_of_range 다.
    CHECK_EQ(classify("1e309"), std::string("out_of_range"));
    CHECK_EQ(classify("1e400"), std::string("out_of_range"));

    // 가수가 0 이면 지수가 아무리 커도 정확히 0 이라 수락이다.
    CHECK_EQ(classify("0e999"), std::string("ok"));
    CHECK_EQ(classify("0e-999"), std::string("ok"));

    // 로케일 독립이어야 한다. `,` 를 소수점으로 쓰는 로케일에서도 `.` 이다.
    // (test_main 이 시작할 때 setlocale 을 부르므로 여기서 확인 가능하다.)
    double value = 0.0;
    const char* comma = "36,33";
    const auto r = std::from_chars(comma, comma + 5, value);
    CHECK(r.ptr == comma + 2);   // "36" 까지만 먹는다
    CHECK_EQ(value, 36.0);

    // 정수 경로. 2^63 은 int64 에 안 들어간다.
    std::int64_t big = 0;
    const char* overflow = "9223372036854775808";
    const auto ri = std::from_chars(overflow, overflow + 19, big);
    CHECK(ri.ec == std::errc::result_out_of_range);
}

// --- wire/writer ----------------------------------------------------------
//
// **파리티가 원리상 불가능한 모듈이다.** macOS 는 이 루프를 갖고 있지 않다 —
// `FileHandle.write` 안에서 Foundation 이 처리한다. 그래서 여기서 틀리면
// 아무도 못 잡는다. 그 전제로 테스트를 짰다.
//
// 재현하려는 실패는 넷이다.
//   ① 부분 쓰기       오프셋을 잘못 잡으면 줄이 조용히 망가진다
//   ② 0바이트 반복    상한이 없으면 무한 루프
//   ③ 파이프 끊김      즉시 멈춰야 한다
//   ④ 중간 끊김        일부만 나간 채 HostGone

/// 대본대로 답하는 sink. 실기에서 재현하기 어려운 것을 여기서 만든다.
class ScriptedSink : public negaflow::wire::ByteSink {
public:
    explicit ScriptedSink(std::vector<negaflow::wire::WriteAttempt> script)
        : script_(std::move(script)) {}

    negaflow::wire::WriteAttempt writeSome(const char* data, std::size_t size) override {
        calls.push_back(size);
        // 실제로 무엇이 넘어왔는지 남긴다 — **오프셋 오류는 여기서만 보인다.**
        negaflow::wire::WriteAttempt attempt;
        if (next_ < script_.size()) {
            attempt = script_[next_++];
        } else {
            attempt.written = size;  // 대본이 끝나면 전부 받아준다
        }
        const std::size_t take = attempt.written > size ? size : attempt.written;
        received.append(data, take);
        return attempt;
    }

    std::string received;
    std::vector<std::size_t> calls;

private:
    std::vector<negaflow::wire::WriteAttempt> script_;
    std::size_t next_ = 0;
};

void testWriterResumesPartialWrites() {
    using namespace negaflow::wire;
    const std::string line = "{\"type\":\"progress\",\"sequence\":0}\n";

    // 한 바이트씩만 받아주는 sink. 오프셋이 틀리면 내용이 어긋난다.
    ScriptedSink oneByte(std::vector<WriteAttempt>(line.size(), WriteAttempt{1, WriteAttempt::Status::Ok}));
    CHECK(writeAll(line, oneByte) == WriteOutcome::Ok);
    CHECK_EQ(oneByte.received, line);
    CHECK_EQ(static_cast<int>(oneByte.calls.size()), static_cast<int>(line.size()));
    // 매 호출의 남은 길이가 1씩 줄어야 한다.
    if (oneByte.calls.size() == line.size()) {
        CHECK_EQ(oneByte.calls.front(), line.size());
        CHECK_EQ(oneByte.calls.back(), static_cast<std::size_t>(1));
    }

    // 불규칙한 부분 쓰기.
    ScriptedSink chunky({{5, WriteAttempt::Status::Ok},
                         {0, WriteAttempt::Status::Retryable},
                         {11, WriteAttempt::Status::Ok},
                         {1, WriteAttempt::Status::Ok}});
    CHECK(writeAll(line, chunky) == WriteOutcome::Ok);
    CHECK_EQ(chunky.received, line);

    // 빈 입력은 sink 를 부르지 않는다.
    ScriptedSink untouched({});
    CHECK(writeAll("", untouched) == WriteOutcome::Ok);
    CHECK(untouched.calls.empty());
}

void testWriterStopsOnBrokenPipe() {
    using namespace negaflow::wire;
    const std::string line = "{\"type\":\"result\"}\n";

    // 첫 시도에서 끊기면 아무것도 안 나간다.
    ScriptedSink immediate({{0, WriteAttempt::Status::BrokenPipe}});
    CHECK(writeAll(line, immediate) == WriteOutcome::HostGone);
    CHECK(immediate.received.empty());
    CHECK_EQ(static_cast<int>(immediate.calls.size()), 1);  // 재시도하지 않는다

    // **중간에 끊기면 줄이 잘린 채로 나간다.** 그것이 사실이고 감추지 않는다.
    ScriptedSink midway({{6, WriteAttempt::Status::Ok},
                         {0, WriteAttempt::Status::BrokenPipe}});
    CHECK(writeAll(line, midway) == WriteOutcome::HostGone);
    CHECK_EQ(midway.received, line.substr(0, 6));

    // Fatal 은 즉시 실패다.
    ScriptedSink fatal({{0, WriteAttempt::Status::Fatal}});
    CHECK(writeAll(line, fatal) == WriteOutcome::Failed);
    CHECK_EQ(static_cast<int>(fatal.calls.size()), 1);
}

void testWriterGivesUpWhenStalled() {
    using namespace negaflow::wire;
    const std::string line = "abc\n";

    // **진행이 없으면 언젠가 포기한다.** 상한이 없으면 여기서 영원히 돈다.
    ScriptedSink stalledOk(std::vector<WriteAttempt>(200, WriteAttempt{0, WriteAttempt::Status::Ok}));
    CHECK(writeAll(line, stalledOk, 8) == WriteOutcome::Failed);
    CHECK_EQ(static_cast<int>(stalledOk.calls.size()), 8);

    ScriptedSink stalledRetry(std::vector<WriteAttempt>(200, WriteAttempt{0, WriteAttempt::Status::Retryable}));
    CHECK(writeAll(line, stalledRetry, 3) == WriteOutcome::Failed);
    CHECK_EQ(static_cast<int>(stalledRetry.calls.size()), 3);

    // 진행이 있으면 예산이 되돌아온다 — 느린 파이프가 실패로 끝나면 안 된다.
    std::vector<WriteAttempt> slow;
    for (int i = 0; i < 4; ++i) {
        slow.push_back({0, WriteAttempt::Status::Retryable});
        slow.push_back({0, WriteAttempt::Status::Retryable});
        slow.push_back({1, WriteAttempt::Status::Ok});
    }
    ScriptedSink slowSink(slow);
    CHECK(writeAll(line, slowSink, 3) == WriteOutcome::Ok);
    CHECK_EQ(slowSink.received, line);

    // 상한이 0 이하면 아무것도 하지 않고 실패다.
    ScriptedSink never({});
    CHECK(writeAll(line, never, 0) == WriteOutcome::Failed);
    CHECK(never.calls.empty());
}

void testWriterDistrustsOverlongWrite() {
    using namespace negaflow::wire;
    const std::string line = "abcd\n";
    // sink 가 요청보다 많이 썼다고 우기면 **믿지 않는다.** 그대로 더하면
    // 오프셋이 끝을 넘어가고 다음 길이 계산이 감긴다.
    ScriptedSink liar({{9999, WriteAttempt::Status::Ok}});
    CHECK(writeAll(line, liar) == WriteOutcome::Ok);
    CHECK_EQ(liar.received, line);
    CHECK_EQ(static_cast<int>(liar.calls.size()), 1);
}


// --- wire/cli -------------------------------------------------------------
//
// **파리티 없음** — Swift 짝이 main.swift 의 최상위 switch 다.
// wire-contract §6 표를 항목별로 고정한다.

void testCliDispatchTable() {
    using namespace negaflow::wire;
    const auto plan = [](std::vector<std::string> argv) { return planCli(argv); };

    CHECK(plan({"prog", "detect"}).command == Subcommand::Detect);
    CHECK(!plan({"prog", "detect"}).exitCode.has_value());
    CHECK(plan({"prog", "scan"}).command == Subcommand::Scan);
    CHECK(plan({"prog", "restore-sane"}).command == Subcommand::RestoreSane);
    // tune-sane 은 별칭이다. 기존 자동화가 쓴다.
    CHECK(plan({"prog", "repair-sane-config"}).command == Subcommand::RepairSaneConfig);
    CHECK(plan({"prog", "tune-sane"}).command == Subcommand::RepairSaneConfig);

    const auto caps = plan({"prog", "capabilities", "genesys:libusb:001:002"});
    CHECK(caps.command == Subcommand::Capabilities);
    CHECK_EQ(caps.argument, std::string("genesys:libusb:001:002"));
    CHECK(!caps.exitCode.has_value());
}

void testCliCapabilitiesNeedsDeviceId() {
    using namespace negaflow::wire;
    const auto missing = planCli({"prog", "capabilities"});
    CHECK(missing.command == Subcommand::Capabilities);
    // macOS fail() 이 1 을 쓴다. 문구도 접두까지 같다(I-5).
    CHECK(missing.exitCode.has_value() && *missing.exitCode == 1);
    CHECK_EQ(static_cast<int>(missing.diagnostics.size()), 1);
    if (!missing.diagnostics.empty()) {
        CHECK(missing.diagnostics[0].stream == Stream::Stderr);
        CHECK_EQ(missing.diagnostics[0].text,
                 std::string("[negaflow-scanner-sane] usage: capabilities <deviceId>\n"));
    }
}

void testCliUsageGoesToStderr() {
    using namespace negaflow::wire;
    // **stdout 은 프로토콜 전용이다.** usage 가 거기 섞이면 호스트 파싱이 깨진다.
    for (const std::vector<std::string>& argv :
         {std::vector<std::string>{"prog"}, std::vector<std::string>{"prog", "help"},
          std::vector<std::string>{"prog", "무엇인가"}}) {
        const auto p = planCli(argv);
        CHECK(p.command == Subcommand::Help);
        CHECK_EQ(static_cast<int>(p.diagnostics.size()), 1);
        if (!p.diagnostics.empty()) CHECK(p.diagnostics[0].stream == Stream::Stderr);
    }
    // argv 가 비어 있어도(이론상) 죽지 않는다.
    CHECK(planCli({}).command == Subcommand::Help);

    // usage 에 세 서브커맨드가 다 있어야 한다.
    const std::string usage = usageText();
    CHECK(usage.find("detect") != std::string::npos);
    CHECK(usage.find("capabilities <deviceId>") != std::string::npos);
    CHECK(usage.find("scan") != std::string::npos);
    // **Windows 에서 no-op 라는 사실이 보여야 한다**(D-05). macOS 문구를
    // 그대로 베끼면 "백엔드 복구"라고 거짓말하게 된다.
    CHECK(usage.find("no-op") != std::string::npos);
}

void testCliUnknownExitPolicyIsInjected() {
    using namespace negaflow::wire;
    // 기본은 **macOS 와 같은 쪽**이다 — 알 수 없는 것도 exit 0.
    const auto legacy = planCli({"prog", "무엇인가"}, UnknownSubcommandPolicy::ExitZero);
    CHECK(legacy.exitCode.has_value() && *legacy.exitCode == 0);

    // §6 권장을 켜면 2 다. 단 명시적 help 는 0 을 유지한다.
    const auto strict = planCli({"prog", "무엇인가"}, UnknownSubcommandPolicy::ExitTwo);
    CHECK(strict.exitCode.has_value() && *strict.exitCode == 2);
    const auto help = planCli({"prog", "help"}, UnknownSubcommandPolicy::ExitTwo);
    CHECK(help.exitCode.has_value() && *help.exitCode == 0);
    // 인자가 아예 없는 것은 "help" 로 친다 — macOS 가 그렇다.
    const auto bare = planCli({"prog"}, UnknownSubcommandPolicy::ExitTwo);
    CHECK(bare.exitCode.has_value() && *bare.exitCode == 0);
}

// --- wire/parse -----------------------------------------------------------
//
// 파리티가 수락/거부와 디코드된 값을 대조한다. 여기서 고정하는 것은 그 위의
// **제품 정책**이다 — §6.3 상한 넷과 중복 키 거부. 그 넷은 macOS 에 대응물이
// 없어서 파리티가 닿지 않는다.
//
// 실측 근거는 src/wire/parse.h 의 표에 있다(2026-08-05).

#ifdef NEGAFLOW_HAVE_RAPIDJSON

std::string requestJson(const std::string& overrides = {}, const std::string& drop = {}) {
    struct Field {
        const char* key;
        const char* value;
    };
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
        {"scanArea", "{\"originXMM\":1,\"originYMM\":2,\"widthMM\":36,\"heightMM\":24}"},
        {"outputRawTIFF", "true"},
        {"outputPath", "\"/tmp/negaflow/frame.tiff\""},
    };
    std::string out = "{";
    bool first = true;
    for (const auto& f : kBase) {
        if (drop == f.key) continue;
        if (!first) out += ',';
        first = false;
        out += '"';
        out += f.key;
        out += "\":";
        out += f.value;
    }
    if (!overrides.empty()) {
        out += ',';
        out += overrides;
    }
    out += '}';
    return out;
}

/// 기준 요청에서 키 하나만 바꾼 문서. 뒤에 붙이면 **중복 키**가 되므로
/// 원본에서 그 키를 빼고 새 값을 붙인다.
std::string requestWith(const char* key, const std::string& value) {
    return requestJson("\"" + std::string(key) + "\":" + value, key);
}

void testParseBaseline() {
    using namespace negaflow::wire;
    negaflow::wire::ParseError err = ParseError::None;
    const auto r = parseScanRequest(requestJson(), ParseLimits::product(), &err);
    CHECK(r.has_value());
    if (!r) return;
    CHECK_EQ(r->protocolVersion, 2);
    // **원문 반사다**(D-12). 대문자로 정규화하지 않는다.
    CHECK_EQ(r->requestID, std::string("3F2504E0-4F89-11D3-9A0C-0305E82C3301"));
    CHECK_EQ(r->deviceID, std::string("genesys:libusb:001:002"));
    CHECK_EQ(r->resolutionDPI, 3600);
    CHECK_EQ(r->bitDepth, 16);
    CHECK_EQ(r->colorMode, std::string("color"));
    CHECK_EQ(r->filmType, std::string("colorNegative"));
    CHECK(!r->preview);
    CHECK(r->outputRawTIFF);
    CHECK_EQ(r->scanArea.originXMM, 1.0);
    CHECK_EQ(r->scanArea.originYMM, 2.0);
    CHECK_EQ(r->scanArea.widthMM, 36.0);
    CHECK_EQ(r->scanArea.heightMM, 24.0);
    CHECK(!r->brightnessAdjustment.has_value());
    CHECK(!r->hardwareExposureTime.has_value());
    CHECK(!r->capabilityToken.has_value());
    CHECK(err == ParseError::None);
}

void testParseOptionalAbsentEqualsNull() {
    using namespace negaflow::wire;
    // **키 부재와 null 이 같다.** 옵셔널 필드 넷 전부.
    for (const char* key : {"brightnessAdjustment", "contrastAdjustment",
                            "hardwareExposureTime", "capabilityToken"}) {
        const auto absent = parseScanRequest(requestJson(), ParseLimits::product());
        const auto explicitNull =
            parseScanRequest(requestWith(key, "null"), ParseLimits::product());
        CHECK(absent.has_value());
        CHECK(explicitNull.has_value());
        if (!absent || !explicitNull) continue;
        CHECK_EQ(absent->brightnessAdjustment.has_value(),
                 explicitNull->brightnessAdjustment.has_value());
        CHECK_EQ(absent->hardwareExposureTime.has_value(),
                 explicitNull->hardwareExposureTime.has_value());
        CHECK_EQ(absent->capabilityToken.has_value(),
                 explicitNull->capabilityToken.has_value());
    }
    // 빈 문자열은 값이 **있는** 것이다. null 과 다르다.
    const auto empty = parseScanRequest(requestWith("capabilityToken", "\"\""),
                                        ParseLimits::product());
    CHECK(empty.has_value());
    if (empty) {
        CHECK(empty->capabilityToken.has_value());
        CHECK(empty->capabilityToken->empty());
    }
}

void testParseRequiredRejectsNullAndAbsent() {
    using namespace negaflow::wire;
    for (const char* key : {"protocolVersion", "requestID", "deviceID", "resolutionDPI",
                            "bitDepth", "colorMode", "filmType", "preview",
                            "multiExposure", "infrared", "scanArea", "outputRawTIFF",
                            "outputPath"}) {
        ParseError absentErr = ParseError::None;
        CHECK(!parseScanRequest(requestJson({}, key), ParseLimits::product(), &absentErr));
        CHECK(absentErr == ParseError::MissingKey);

        ParseError nullErr = ParseError::None;
        CHECK(!parseScanRequest(requestWith(key, "null"), ParseLimits::product(), &nullErr));
        CHECK(nullErr == ParseError::NullForRequired);
    }
}

void testParseUnknownKeysIgnored() {
    using namespace negaflow::wire;
    // **호스트가 새 필드를 더해도 기존 플러그인이 동작해야 한다**(§6.1).
    CHECK(parseScanRequest(requestJson("\"futureField\":123"), ParseLimits::product())
              .has_value());
    CHECK(parseScanRequest(requestJson("\"futureField\":{\"a\":[1,2,{\"b\":null}]}"),
                           ParseLimits::product())
              .has_value());
    // 중첩 객체 안의 모르는 키도 무시한다.
    CHECK(parseScanRequest(
              requestWith("scanArea", "{\"widthMM\":36,\"heightMM\":24,\"zzz\":1}"),
              ParseLimits::product())
              .has_value());
}

void testParseIntegerFormsMatchSwift() {
    using namespace negaflow::wire;
    // 값이 정수면 표기는 무관하다. macOS 가 그렇다(실측).
    for (const char* literal : {"3600", "3600.0", "3.6e3", "36e2"}) {
        const auto r = parseScanRequest(requestWith("resolutionDPI", literal),
                                        ParseLimits::product());
        CHECK(r.has_value());
        if (r) CHECK_EQ(r->resolutionDPI, 3600);
    }
    // 소수부가 있으면 거부다. **타입 오류가 아니라 문서 거부다**(macOS 도 그렇다).
    ParseError err = ParseError::None;
    CHECK(!parseScanRequest(requestWith("resolutionDPI", "1200.5"),
                            ParseLimits::product(), &err));
    CHECK(err == ParseError::NumberNotIntegral);

    // -0 은 0 이다.
    const auto zero = parseScanRequest(requestWith("resolutionDPI", "-0"),
                                       ParseLimits::product());
    CHECK(zero.has_value());
    if (zero) CHECK_EQ(zero->resolutionDPI, 0);
}

void testParseIntegerWidthDivergence() {
    using namespace negaflow::wire;
    // **여기가 macOS 와 갈리는 유일한 지점이다.** Swift Int 는 64비트라
    // 2147483648 을 받아들이고, 우리 필드는 int 라 거부한다.
    // 의도한 차이이며 파리티 corpus 에 넣지 않는다 — parse.h 참조.
    const auto edge = parseScanRequest(requestWith("resolutionDPI", "2147483647"),
                                       ParseLimits::product());
    CHECK(edge.has_value());
    if (edge) CHECK_EQ(edge->resolutionDPI, 2147483647);

    ParseError err = ParseError::None;
    CHECK(!parseScanRequest(requestWith("resolutionDPI", "2147483648"),
                            ParseLimits::product(), &err));
    CHECK(err == ParseError::IntegerTooWide);

    // int64 를 넘으면 범위 오류다(폭 문제가 아니다). macOS 도 거부한다.
    ParseError wide = ParseError::None;
    CHECK(!parseScanRequest(requestWith("resolutionDPI", "9223372036854775808"),
                            ParseLimits::product(), &wide));
    CHECK(wide == ParseError::NumberOutOfRange);
}

void testParseDoubleRangeMatchesSwift() {
    using namespace negaflow::wire;
    // 준정규는 수락, 0 으로 내려앉는 언더플로는 거부 — macOS 와 같다.
    for (const char* literal : {"1e-308", "1e-320", "4.9e-324", "1e-323", "1e308",
                                "0e-999", "-0.0", "0.0"}) {
        CHECK(parseScanRequest(requestWith("brightnessAdjustment", literal),
                               ParseLimits::product())
                  .has_value());
    }
    // 언더플로는 우리가 잡는다(from_chars 가 out_of_range 를 준다).
    for (const char* literal : {"1e-324", "1e-400"}) {
        ParseError err = ParseError::None;
        CHECK(!parseScanRequest(requestWith("brightnessAdjustment", literal),
                                ParseLimits::product(), &err));
        CHECK(err == ParseError::NumberOutOfRange);
    }
    // 오버플로는 RapidJSON 토큰화가 먼저 잡는다. **결과는 같고 사유만 다르다.**
    for (const char* literal : {"1e309", "1e400"}) {
        ParseError err = ParseError::None;
        CHECK(!parseScanRequest(requestWith("brightnessAdjustment", literal),
                                ParseLimits::product(), &err));
        CHECK(err == ParseError::MalformedJson);
    }
}

void testParseZeroMantissaHugeExponentDivergence() {
    using namespace negaflow::wire;
    // **macOS 와 갈리는 둘째 지점.** RapidJSON 은 수를 문자열로 넘기는
    // 모드에서도 지수 크기를 검사하고, 가수가 0 이어도 거부한다.
    // Swift 는 0.0 으로 받아들인다. 갈리는 방향이 거부라 안전한 쪽이다.
    // 근거: src/wire/parse.h "그래도 남는 차이 하나"
    ParseError err = ParseError::None;
    CHECK(!parseScanRequest(requestWith("brightnessAdjustment", "0e999"),
                            ParseLimits::product(), &err));
    CHECK(err == ParseError::MalformedJson);
    // 음수 지수는 통과한다 — 검사가 위쪽만 본다.
    CHECK(parseScanRequest(requestWith("brightnessAdjustment", "0e-999"),
                           ParseLimits::product())
              .has_value());
    // 정수 리터럴은 Double 필드에서 그대로 값이 된다.
    const auto one = parseScanRequest(requestWith("brightnessAdjustment", "1"),
                                      ParseLimits::product());
    CHECK(one.has_value());
    if (one && one->brightnessAdjustment) CHECK_EQ(*one->brightnessAdjustment, 1.0);
}

void testParseTypeMismatches() {
    using namespace negaflow::wire;
    const std::pair<const char*, const char*> kCases[] = {
        {"bitDepth", "\"16\""},        {"preview", "1"},
        {"preview", "\"true\""},       {"colorMode", "3"},
        {"scanArea", "42"},            {"brightnessAdjustment", "\"0.25\""},
        {"brightnessAdjustment", "true"}, {"deviceID", "[]"},
    };
    for (const auto& [key, value] : kCases) {
        ParseError err = ParseError::None;
        CHECK(!parseScanRequest(requestWith(key, value), ParseLimits::product(), &err));
        CHECK(err == ParseError::TypeMismatch);
    }
}

void testParseScanAreaCustomDecoder() {
    using namespace negaflow::wire;
    // 원점은 생략 가능하고 기본 0, 크기는 필수다(§6.2).
    const auto omitted = parseScanRequest(
        requestWith("scanArea", "{\"widthMM\":36,\"heightMM\":24}"), ParseLimits::product());
    CHECK(omitted.has_value());
    if (omitted) {
        CHECK_EQ(omitted->scanArea.originXMM, 0.0);
        CHECK_EQ(omitted->scanArea.originYMM, 0.0);
    }
    // 원점이 null 이어도 0 이다 — decodeIfPresent ?? 0.
    const auto nulled = parseScanRequest(
        requestWith("scanArea", "{\"originXMM\":null,\"originYMM\":null,\"widthMM\":36,\"heightMM\":24}"),
        ParseLimits::product());
    CHECK(nulled.has_value());
    if (nulled) CHECK_EQ(nulled->scanArea.originXMM, 0.0);

    ParseError missing = ParseError::None;
    CHECK(!parseScanRequest(requestWith("scanArea", "{\"heightMM\":24}"),
                            ParseLimits::product(), &missing));
    CHECK(missing == ParseError::MissingKey);

    ParseError nullWidth = ParseError::None;
    CHECK(!parseScanRequest(requestWith("scanArea", "{\"widthMM\":null,\"heightMM\":24}"),
                            ParseLimits::product(), &nullWidth));
    CHECK(nullWidth == ParseError::NullForRequired);
}

void testParseUuidStrictness() {
    using namespace negaflow::wire;
    CHECK(isValidRequestUUID("3F2504E0-4F89-11D3-9A0C-0305E82C3301"));
    CHECK(isValidRequestUUID("3f2504e0-4f89-11d3-9a0c-0305e82c3301"));
    CHECK(isValidRequestUUID("3F2504e0-4f89-11D3-9a0C-0305e82C3301"));
    CHECK(isValidRequestUUID("00000000-0000-0000-0000-000000000000"));
    // macOS 가 거부하는 것들(실측).
    CHECK(!isValidRequestUUID("{3F2504E0-4F89-11D3-9A0C-0305E82C3301}"));
    CHECK(!isValidRequestUUID("3F2504E04F8911D39A0C0305E82C3301"));
    CHECK(!isValidRequestUUID("3F2504E0-4F89-11D3-9A0C-0305E82C330"));
    CHECK(!isValidRequestUUID("3F2504E0-4F89-11D3-9A0C-0305E82C33011"));
    CHECK(!isValidRequestUUID("3F2504E0-4F89-11D3-9A0C-0305E82C33ZZ"));
    CHECK(!isValidRequestUUID("3F2504E0-4F89-11D3-9A0C-0305E82C3301 "));
    CHECK(!isValidRequestUUID("urn:uuid:3F2504E0-4F89-11D3-9A0C-0305E82C3301"));
    CHECK(!isValidRequestUUID(""));
    // 하이픈 자리에 16진수가 오면 안 된다.
    CHECK(!isValidRequestUUID("3F2504E0a4F89-11D3-9A0C-0305E82C330"));

    ParseError err = ParseError::None;
    CHECK(!parseScanRequest(requestWith("requestID", "\"not-a-uuid\""),
                            ParseLimits::product(), &err));
    CHECK(err == ParseError::InvalidUuid);
}

void testParseDocumentShape() {
    using namespace negaflow::wire;
    const auto limits = ParseLimits::product();

    // 최상위가 객체가 아니면 거부다.
    ParseError notObject = ParseError::None;
    CHECK(!parseScanRequest("[]", limits, &notObject));
    CHECK(notObject == ParseError::NotAnObject);
    CHECK(!parseScanRequest("\"x\"", limits));
    CHECK(!parseScanRequest("", limits));

    // 앞뒤 공백과 BOM 은 받아들인다. 뒤에 붙은 값은 거부다(macOS 와 같다).
    CHECK(parseScanRequest("  \n\t" + requestJson(), limits).has_value());
    CHECK(parseScanRequest(requestJson() + "\n", limits).has_value());
    CHECK(parseScanRequest("\xEF\xBB\xBF" + requestJson(), limits).has_value());
    CHECK(!parseScanRequest(requestJson() + "x", limits));
    CHECK(!parseScanRequest(requestJson() + requestJson(), limits));
    CHECK(!parseScanRequest(requestJson() + " // 주석", limits));

    // 수 문법과 이스케이프는 RapidJSON 이 막는다 — macOS 와 같은 판정이다.
    for (const std::string& bad : {std::string("\"resolutionDPI\":01"),
                                   std::string("\"resolutionDPI\":+1"),
                                   std::string("\"resolutionDPI\":.5"),
                                   std::string("\"resolutionDPI\":5.")}) {
        ParseError err = ParseError::None;
        const std::string key = bad.substr(1, bad.find('"', 1) - 1);
        CHECK(!parseScanRequest(requestJson(bad, key.c_str()), limits, &err));
        CHECK(err == ParseError::MalformedJson);
    }
    // 문자열 안의 생 제어문자와 잘못된 이스케이프.
    CHECK(!parseScanRequest(requestWith("deviceID", "\"a\tb\""), limits));
    CHECK(!parseScanRequest(requestWith("deviceID", "\"a\\xb\""), limits));
    CHECK(!parseScanRequest(requestWith("deviceID", "\"\\uD800\""), limits));
    // 유효한 이스케이프는 통과한다.
    CHECK(parseScanRequest(requestWith("deviceID", "\"a\\/b\""), limits).has_value());
    CHECK(parseScanRequest(requestWith("deviceID", "\"\\uD55C\\uAE00\""), limits).has_value());
}

void testParseLimitsAreProductPolicy() {
    using namespace negaflow::wire;
    const auto product = ParseLimits::product();
    const auto swiftLike = ParseLimits::swiftEquivalent();

    // ① 중복 키 — 제품은 거부, macOS 는 **첫 값**을 쓴다(실측).
    const std::string dup = requestJson("\"bitDepth\":8", "");
    ParseError dupErr = ParseError::None;
    CHECK(!parseScanRequest(dup, product, &dupErr));
    CHECK(dupErr == ParseError::DuplicateKey);
    const auto kept = parseScanRequest(dup, swiftLike);
    CHECK(kept.has_value());
    if (kept) CHECK_EQ(kept->bitDepth, 16);  // 첫 값이다. 8 이 아니다.

    // ② 깊이 — 제품 32, macOS 근사 512.
    const auto nested = [](int depth) {
        return requestJson("\"futureField\":" + std::string(static_cast<std::size_t>(depth), '[') +
                           std::string(static_cast<std::size_t>(depth), ']'));
    };
    CHECK(parseScanRequest(nested(30), product).has_value());
    ParseError deep = ParseError::None;
    CHECK(!parseScanRequest(nested(40), product, &deep));
    CHECK(deep == ParseError::DepthExceeded);
    CHECK(parseScanRequest(nested(40), swiftLike).has_value());

    // ③ 문서 크기.
    ParseLimits tiny = product;
    tiny.maxDocumentBytes = 16;
    ParseError big = ParseError::None;
    CHECK(!parseScanRequest(requestJson(), tiny, &big));
    CHECK(big == ParseError::DocumentTooLarge);

    // ④ 문자열 길이.
    ParseLimits shortStrings = product;
    shortStrings.maxStringBytes = 8;
    ParseError longStr = ParseError::None;
    CHECK(!parseScanRequest(requestJson(), shortStrings, &longStr));
    CHECK(longStr == ParseError::StringTooLong);

    // ⑤ 항목 수.
    ParseLimits fewItems = product;
    fewItems.maxContainerItems = 4;
    ParseError many = ParseError::None;
    CHECK(!parseScanRequest(requestJson(), fewItems, &many));
    CHECK(many == ParseError::TooManyItems);
}

void testParseEnvelopeFallback() {
    using namespace negaflow::wire;
    const auto limits = ParseLimits::product();

    // 전체 디코딩이 실패해도 봉투는 성립할 수 있다 — 그래야 requestID 를
    // 실은 오류 이벤트를 낼 수 있다(main.swift 의 fallback 경로).
    const std::string broken =
        "{\"protocolVersion\":2,\"requestID\":\"3F2504E0-4F89-11D3-9A0C-0305E82C3301\"}";
    CHECK(!parseScanRequest(broken, limits));
    const auto envelope = parseScanRequestEnvelope(broken, limits);
    CHECK(envelope.has_value());
    if (envelope) {
        CHECK(envelope->protocolVersion.has_value() && *envelope->protocolVersion == 2);
        CHECK(envelope->requestID.has_value());
        if (envelope->requestID) {
            CHECK_EQ(*envelope->requestID,
                     std::string("3F2504E0-4F89-11D3-9A0C-0305E82C3301"));
        }
    }

    // 두 필드 모두 옵셔널이라 없어도 봉투는 성립한다. 호출자가 걸러낸다.
    const auto bare = parseScanRequestEnvelope("{}", limits);
    CHECK(bare.has_value());
    if (bare) {
        CHECK(!bare->protocolVersion.has_value());
        CHECK(!bare->requestID.has_value());
    }

    // **있는데 UUID 가 아니면 봉투 자체가 실패한다**(Swift UUID? 의 동작).
    ParseError badUuid = ParseError::None;
    CHECK(!parseScanRequestEnvelope("{\"requestID\":\"nope\"}", limits, &badUuid));
    CHECK(badUuid == ParseError::InvalidUuid);

    // JSON 이 아예 깨졌으면 봉투도 없다 — 그때는 stderr 로 나간다.
    CHECK(!parseScanRequestEnvelope("{oops", limits));
}

// ===========================================================================
// wire/snapshot — capabilityToken. base64(JSON).
//
// 구현이 `wire_parse` 타깃에 있으므로(RapidJSON 을 아는 타깃이 하나라는 계약)
// 이 블록도 같은 조건으로 묶인다.
// ===========================================================================

void testBase64RoundTrip() {
    using namespace negaflow::wire;

    // 세 잔여 길이를 전부 지난다. 패딩이 붙는 두 경우가 실수가 나는 곳이다.
    const char* inputs[] = {"", "f", "fo", "foo", "foob", "fooba", "foobar"};
    const char* expected[] = {"", "Zg==", "Zm8=", "Zm9v", "Zm9vYg==", "Zm9vYmE=", "Zm9vYmFy"};
    for (int i = 0; i < 7; ++i) {
        CHECK_EQ(base64Encode(inputs[i]), std::string(expected[i]));
        const auto decoded = base64Decode(expected[i]);
        CHECK(decoded.has_value());
        if (decoded) CHECK_EQ(*decoded, std::string(inputs[i]));
    }

    // 0 바이트를 포함한 임의 바이트도 왕복한다.
    std::string binary;
    for (int i = 0; i < 256; ++i) binary.push_back(static_cast<char>(i));
    const auto roundTrip = base64Decode(base64Encode(binary));
    CHECK(roundTrip.has_value());
    if (roundTrip) CHECK_EQ(*roundTrip, binary);

    // **표준 알파벳과 패딩만 받는다.** 공백·개행·URL-safe 변형은 거부한다.
    CHECK(!base64Decode("Zm9v YmFy"));
    CHECK(!base64Decode("Zm9v\nYmFy"));
    CHECK(!base64Decode("Zg="));      // 길이가 4의 배수가 아니다
    CHECK(!base64Decode("Z==="));     // 패딩이 셋
    CHECK(!base64Decode("Zm9-"));     // URL-safe
    CHECK(!base64Decode("Zg==Zg=="));  // 패딩이 마지막 블록에만 와야 한다
}

void testCapabilitySnapshotRoundTrip() {
    using namespace negaflow::wire;

    CapabilitySnapshot snapshot;
    snapshot.deviceID = "sane-genesys:libusb:001:002";
    snapshot.backend = "genesys";
    snapshot.acquisitionDevice = "genesys:libusb:001:002";
    snapshot.deviceIdentity = DeviceIdentity{"Plustek", "OpticFilm 8100"};
    snapshot.deviceType = std::string("film scanner");
    snapshot.optionDump = "  --mode Color|Gray [Color]\n  -x 0..36.33mm [36.33]\n";
    snapshot.validatedMode = std::string("color");

    const auto token = encodeCapabilityToken(snapshot);
    CHECK(token.has_value());
    if (!token) return;

    const auto decoded = decodeCapabilityToken(*token);
    CHECK(decoded.has_value());
    if (!decoded) return;
    CHECK_EQ(decoded->deviceID, snapshot.deviceID);
    CHECK_EQ(decoded->backend, snapshot.backend);
    CHECK_EQ(decoded->acquisitionDevice, snapshot.acquisitionDevice);
    CHECK(decoded->deviceIdentity.has_value());
    if (decoded->deviceIdentity) {
        CHECK_EQ(decoded->deviceIdentity->vendor, std::string("Plustek"));
        CHECK_EQ(decoded->deviceIdentity->model, std::string("OpticFilm 8100"));
    }
    CHECK(decoded->deviceType.has_value());
    // **옵션 덤프가 바이트 그대로 살아 나와야 한다** — 개행과 공백이 파서의 입력이다.
    CHECK_EQ(decoded->optionDump, snapshot.optionDump);
    CHECK(decoded->validatedMode.has_value());
    if (decoded->validatedMode) CHECK_EQ(*decoded->validatedMode, std::string("color"));

    // 옵셔널이 비면 키가 없고, 없어도 해석된다.
    CapabilitySnapshot bare;
    bare.deviceID = "sane-epson2:libusb:002:003";
    bare.backend = "epson2";
    bare.acquisitionDevice = "epson2:libusb:002:003";
    bare.optionDump = "  --mode Color [Color]\n";
    const auto bareToken = encodeCapabilityToken(bare);
    CHECK(bareToken.has_value());
    if (bareToken) {
        const auto bareDecoded = decodeCapabilityToken(*bareToken);
        CHECK(bareDecoded.has_value());
        if (bareDecoded) {
            CHECK(!bareDecoded->deviceIdentity.has_value());
            CHECK(!bareDecoded->deviceType.has_value());
            CHECK(!bareDecoded->validatedMode.has_value());
        }
    }

    // 토큰은 **신뢰할 수 없는 입력이다.** 형태가 어긋나면 조용히 통과시키지 않는다.
    CHECK(!decodeCapabilityToken(""));
    CHECK(!decodeCapabilityToken("not base64!"));
    CHECK(!decodeCapabilityToken(base64Encode("{}")));                 // schemaVersion 없음
    CHECK(!decodeCapabilityToken(base64Encode("{\"schemaVersion\":2}")));  // 낡은 스키마
    CHECK(!decodeCapabilityToken(base64Encode("[1,2,3]")));            // 객체가 아니다
    CHECK(!decodeCapabilityToken(base64Encode("{\"schemaVersion\":3}x")));  // 뒤에 쓰레기
}

#endif  // NEGAFLOW_HAVE_RAPIDJSON

// ===========================================================================
// sane/media — 덤프가 어느 모드에서 읽혔는가.
// ===========================================================================

void testValidatedColorMode() {
    using namespace negaflow::sane;

    const OptionDump color{"  --mode Color|Gray [Color]\n"};
    const auto colorMode = validatedColorMode(color, "genesys", "film scanner");
    CHECK(colorMode.has_value());
    if (colorMode) CHECK(*colorMode == ColorMode::Color);

    const OptionDump gray{"  --mode Color|Gray [Gray]\n"};
    const auto grayMode = validatedColorMode(gray, "genesys", "film scanner");
    CHECK(grayMode.has_value());
    if (grayMode) CHECK(*grayMode == ColorMode::Gray);

    // Lineart 는 우리가 쓰지 않는 모드다. **추정하지 않고 nullopt 다.**
    const OptionDump lineart{"  --mode Lineart|Color [Lineart]\n"};
    CHECK(!validatedColorMode(lineart, "epson2", "flatbed scanner"));

    // `--mode` 가 없는 전용 필름 스캐너는 Color 로 고정이다.
    const OptionDump noMode{"  --depth 8|14 [14]\n"};
    const auto film = validatedColorMode(noMode, "coolscan3", "film scanner");
    CHECK(film.has_value());
    if (film) CHECK(*film == ColorMode::Color);

    // 같은 덤프라도 필름 장치가 아니면 단정하지 않는다.
    CHECK(!validatedColorMode(noMode, "epson2", "flatbed scanner"));
}

// ===========================================================================
// process/watchdog + process/child — Win32 계층. 판정 부분만 여기서 본다.
// ===========================================================================

#ifdef _WIN32

void testProgressTrackerArithmetic() {
    using negaflow::process::ProgressTracker;

    ProgressTracker tracker;

    // 레코드가 **새로 나타났는가**가 기준이다. 값의 증가가 아니다.
    auto first = tracker.append("scanimage: scanning\nProgress: 0.0%\r");
    CHECK(first.madeProgress);
    CHECK(first.fraction.has_value());
    if (first.fraction) CHECK_EQ(*first.fraction, 0.0);

    auto second = tracker.append("Progress: 42.5%\r");
    CHECK(second.madeProgress);
    CHECK(second.fraction.has_value());
    if (second.fraction) CHECK(std::abs(*second.fraction - 0.425) < 1e-12);

    // 진행률이 없는 chunk 는 진행이 아니다.
    auto idle = tracker.append("warming up\n");
    CHECK(!idle.madeProgress);

    // 레코드가 chunk 경계에서 잘려도 다음 chunk 와 합쳐 인식한다.
    ProgressTracker split;
    auto half = split.append("Progr");
    CHECK(!half.madeProgress);
    auto rest = split.append("ess: 77%\r");
    CHECK(rest.madeProgress);
    if (rest.fraction) CHECK(std::abs(*rest.fraction - 0.77) < 1e-12);

    // stderr 는 전부 모이고, 꺼내면 앞뒤 공백이 잘린 채 비워진다.
    ProgressTracker collector;
    (void)collector.append("  scanimage: boom\n  ");
    CHECK_EQ(collector.takeStderr(), std::string("scanimage: boom"));
    CHECK_EQ(collector.takeStderr(), std::string(""));

    // 꼬리를 160바이트로 자르므로 오래된 레코드는 다시 매치되지 않는다.
    ProgressTracker tail;
    (void)tail.append("Progress: 10%\r");
    (void)tail.append(std::string(400, 'x'));
    auto afterFlush = tail.append("nothing here\n");
    CHECK(!afterFlush.madeProgress);
    CHECK(!afterFlush.fraction.has_value());
}

void testWatchdogClassifiesTimeouts() {
    using negaflow::process::AcquisitionWatchdog;
    using negaflow::process::TimeoutKind;

    // 진행률이 하나도 없으면 FirstProgress 다.
    {
        AcquisitionWatchdog watchdog;
        bool fired = false;
        watchdog.start(std::chrono::milliseconds{30}, std::chrono::milliseconds{5'000},
                       [&] { fired = true; });
        std::this_thread::sleep_for(std::chrono::milliseconds{250});
        const auto result = watchdog.finish();
        CHECK(fired);
        CHECK(result.kind == TimeoutKind::FirstProgress);
        CHECK(!result.observedProgress);
    }

    // 진행률을 본 뒤 멈추면 Stalled 다.
    {
        AcquisitionWatchdog watchdog;
        bool fired = false;
        watchdog.start(std::chrono::milliseconds{5'000}, std::chrono::milliseconds{30},
                       [&] { fired = true; });
        watchdog.markProgress();
        std::this_thread::sleep_for(std::chrono::milliseconds{250});
        const auto result = watchdog.finish();
        CHECK(fired);
        CHECK(result.kind == TimeoutKind::Stalled);
        CHECK(result.observedProgress);
    }

    // 제때 끝나면 아무 일도 없다. **총 스캔 시간은 제한하지 않는다**(I-7).
    {
        AcquisitionWatchdog watchdog;
        bool fired = false;
        watchdog.start(std::chrono::milliseconds{5'000}, std::chrono::milliseconds{5'000},
                       [&] { fired = true; });
        watchdog.markProgress();
        const auto result = watchdog.finish();
        CHECK(!fired);
        CHECK(result.kind == TimeoutKind::None);
        CHECK(result.observedProgress);
    }
}

void testSanitizeUtf8() {
    using negaflow::process::sanitizeUtf8;

    // 유효한 것은 바이트 그대로 남는다 — 오류 메시지가 한국어일 수 있다.
    CHECK_EQ(sanitizeUtf8("scanimage: 실패"), std::string("scanimage: 실패"));
    CHECK_EQ(sanitizeUtf8(""), std::string(""));

    // 잘못된 바이트는 U+FFFD 로 바뀐다. **버리지 않는다** — 길이가 줄면
    // 어디가 깨졌는지 알 수 없다.
    CHECK_EQ(sanitizeUtf8("a\xFF" "b"), std::string("a\xEF\xBF\xBD" "b"));
    // 잘린 다중바이트 시퀀스.
    CHECK_EQ(sanitizeUtf8("\xED\x95"), std::string("\xEF\xBF\xBD\xEF\xBF\xBD"));
    // 과장 인코딩과 서로게이트는 유효한 것처럼 보이지만 거른다.
    CHECK_EQ(sanitizeUtf8("\xC0\xAF"), std::string("\xEF\xBF\xBD\xEF\xBF\xBD"));
    CHECK_EQ(sanitizeUtf8("\xED\xA0\x80"), std::string("\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD"));
}

void testCancellationOwnership() {
    using negaflow::process::ProcessOwnership;
    using SessionError = ProcessOwnership::SessionError;

    ProcessOwnership ownership;
    std::uint64_t first = 0;
    CHECK(ownership.beginScanSession(&first) == SessionError::None);

    // **한 백엔드 인스턴스에 세션은 하나다.**
    std::uint64_t second = 0;
    CHECK(ownership.beginScanSession(&second) == SessionError::Busy);

    // 세션 중에는 유틸리티 실행(세션 밖 프로세스)을 띄울 수 없다.
    negaflow::process::ChildHandles child;
    CHECK(ownership.adoptChild(child, /*requiresScanSession=*/false) == SessionError::Busy);
    CHECK(ownership.adoptChild(child, /*requiresScanSession=*/true) == SessionError::None);

    ownership.endScanSession(first);

    // 취소가 걸려 있으면 새 세션을 시작하지 않는다.
    ownership.requestCancellation();
    CHECK(ownership.cancellationRequested());
    std::uint64_t third = 0;
    CHECK(ownership.beginScanSession(&third) == SessionError::Cancelled);

    // 세션이 끝나면 플래그가 지워진다 — 남으면 이후 스캔이 전부 실패한다.
    std::uint64_t fourth = 0;
    CHECK(ownership.beginScanSession(&fourth) == SessionError::Cancelled);
    ownership.clearUtilityCancellation();
    CHECK(!ownership.cancellationRequested());
    CHECK(ownership.beginScanSession(&fourth) == SessionError::None);
    ownership.endScanSession(fourth);
}

#endif  // _WIN32

}  // namespace

int main() {
    testContainsExactly();
    testSaneNumber();
    testEpson2AlignedHeight();
    testPixelGeometry();

    testDumpBasics();
    testEnumValues();
    testInactiveAsymmetry();
    testIntTokens();
    testNumericRangeAndUnit();
    testResolutionSpec();
    testCrlfAndDuplicates();
    testEmptyDump();

    testBackendAndConnection();
    testParseDeviceList();
    testParseFormattedDeviceList();
    testIdentityAndCapitalized();
    testDedupe();

    testCapabilitiesGenesys();
    testCapabilitiesPositionedArea();
    testCapabilitiesPelUnit();
    testCapabilitiesMultiExposureGate();
    testFixedDepthAndHelpers();

    testMediaGenesysToneSuppression();
    testMediaExactResolution();
    testMediaIRStrategy();
    testMediaCoolscanNegativeAlwaysNo();
    testMediaEpson2();
    testMediaEmptyDumpAssumesNothing();
    testMediaCleanImageUnreachable();

    testValidatePassesGoodRequest();
    testValidateRejectsInexactResolution();
    testValidateFixedDepth();
    testValidateBackendRequirements();
    testValidateEpson2Corrections();
    testValidateAdjustmentZeroRule();
    testValidateMultiExposureAndIR();
    testErrorCodeFormat();

    testArgsOrderAndShape();
    testArgsIRPassKeepsGrid();
    testArgsOmitsAbsentOptions();
    testArgsBackendSpecific();
    testArgsBrightnessOverride();

    testQuoteArgument();
    testBuildCommandLine();
    testIsSafeDeviceName();
    testBudgetCeilings();
    testBudgetCountdown();
    testBudgetScanIsUncapped();
    testBudgetCapabilitiesMultiCall();

    testAttemptCount();
    testRetrySucceedsAndRejectsRounding();
    testRetryCancelNeverRetries();
    testRetryGenesysFirstProgress();
    testRetryStaleDevice();
    testAcquisitionMessages();

    testDownsampledLuma();
    testBoxBlur3LeavesBorder();
    testDownsampledErrorGuards();
    testDownsampledTexture();
    testFullResLumaErrorStep();
    testEstimateIntegerOffsetGuards();
    testAlignedSourceIndexAndAccumulate();
    testExposureTrustWeightBranchOrder();
    testMixAndSmoothstep();

    testReferenceExposureTime();
    testReferenceExposureIndexTieBreak();
    testNormalizeExposure();
    testNormalizeExposureFormulaIsExact();
    testMergeQuantizationTruncates();
    testMergeFailures();
    testAverageMultiSampleAlpha();

    testColorModeFromTags();
    testTiffValidationOrder();
    testTiffStrictTags();
    testTiffFileAttributes();

    testWindowsOutputPathPolicy();
    testPosixPathPolicyMirrorsSwift();
    testJsonDeclarationOrderIsProduction();
    testJsonRejectsNonFinite();
    testJsonNumbersAreLocaleIndependent();
    testJsonEscaping();
    testAppliedOptionsAlwaysHasTwelveKeys();
    testDeviceOmitsNilKeys();
    testCapabilitiesOmissionContract();
    testDetectResponseShape();
    testEmitterSequenceDiscipline();
    testEmitterLineFraming();
    testEmitterDoesNotConsumeSequenceOnFailure();
    testErrorEventHasFiveKeys();
    testFromCharsOutOfRangeContract();
    testWriterResumesPartialWrites();
    testWriterStopsOnBrokenPipe();
    testWriterGivesUpWhenStalled();
    testWriterDistrustsOverlongWrite();
    testCliDispatchTable();
    testCliCapabilitiesNeedsDeviceId();
    testCliUsageGoesToStderr();
    testCliUnknownExitPolicyIsInjected();

#ifdef NEGAFLOW_HAVE_RAPIDJSON
    testParseBaseline();
    testParseOptionalAbsentEqualsNull();
    testParseRequiredRejectsNullAndAbsent();
    testParseUnknownKeysIgnored();
    testParseIntegerFormsMatchSwift();
    testParseIntegerWidthDivergence();
    testParseDoubleRangeMatchesSwift();
    testParseZeroMantissaHugeExponentDivergence();
    testParseTypeMismatches();
    testParseScanAreaCustomDecoder();
    testParseUuidStrictness();
    testParseDocumentShape();
    testParseLimitsAreProductPolicy();
    testParseEnvelopeFallback();
#endif

#ifdef NEGAFLOW_HAVE_LIBTIFF
    testTiffWriteReadRoundTrip();
    testTiffValidatedScannedTIFF();
    testTiffMissingAndBrokenFiles();
    testTiffWriteRejectsBadInput();
#endif

    testValidatedColorMode();
#ifdef NEGAFLOW_HAVE_RAPIDJSON
    testBase64RoundTrip();
    testCapabilitySnapshotRoundTrip();
#endif

#ifdef _WIN32
    testProgressTrackerArithmetic();
    testWatchdogClassifiesTimeouts();
    testSanitizeUtf8();
    testCancellationOwnership();
#endif

    if (g_failures == 0) {
        std::printf("PASS  %d checks\n", g_checks);
        return 0;
    }
    std::printf("\n%d/%d checks failed\n", g_failures, g_checks);
    return 1;
}
