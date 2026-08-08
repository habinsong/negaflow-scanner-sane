// SPDX-License-Identifier: GPL-2.0-or-later

#include "sane/device_list.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <set>

namespace negaflow::sane {

namespace {

constexpr std::string_view kSpace = " \t\v\f\r\n";

[[nodiscard]] char lowerAscii(char c) {
    return static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
}

[[nodiscard]] char upperAscii(char c) {
    return static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
}

[[nodiscard]] std::string toLower(std::string_view s) {
    std::string out;
    out.reserve(s.size());
    for (char c : s) out.push_back(lowerAscii(c));
    return out;
}

[[nodiscard]] std::string_view trim(std::string_view s) {
    const auto b = s.find_first_not_of(kSpace);
    if (b == std::string_view::npos) return {};
    const auto e = s.find_last_not_of(kSpace);
    return s.substr(b, e - b + 1);
}

[[nodiscard]] bool contains(std::string_view haystack, std::string_view needle) {
    return haystack.find(needle) != std::string_view::npos;
}

[[nodiscard]] bool endsWith(std::string_view s, std::string_view suffix) {
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

/// `scanimage -L` 이 내는 장치 타입 접미사(백엔드 자유 문자열).
/// **순서가 의미를 갖는다** — 먼저 매치한 것이 이긴다. "scanner" 가 마지막인 이유다.
constexpr std::array<std::string_view, 13> kDeviceTypeSuffixes{
    "multi-function peripheral", "flatbed scanner",   "film scanner",  "slide scanner",
    "sheetfed scanner",          "sheet-fed scanner", "handheld scanner",
    "hand-held scanner",         "frame grabber",     "virtual device",
    "video camera",              "still camera",      "scanner",
};

/// 개행으로 나눈다. 빈 줄은 버린다(Swift split 기본이 omittingEmptySubsequences).
/// '\r' 은 trim 이 처리하므로 CRLF 입력도 정상 동작한다 —
/// Swift 가 못 하는 부분이며 의도적 divergence 다.
/// 근거: docs/02-frontend-contract/option-dump-parser.md §2.2.1
[[nodiscard]] std::vector<std::string_view> splitLines(std::string_view s, bool keepEmpty) {
    std::vector<std::string_view> out;
    size_t pos = 0;
    while (pos <= s.size()) {
        const auto nl = s.find('\n', pos);
        const auto piece =
            s.substr(pos, nl == std::string_view::npos ? std::string_view::npos : nl - pos);
        if (keepEmpty || !piece.empty()) out.push_back(piece);
        if (nl == std::string_view::npos) break;
        pos = nl + 1;
    }
    return out;
}

}  // namespace

std::string_view connectionTypeRawValue(ConnectionType t) noexcept {
    switch (t) {
        case ConnectionType::Usb: return "usb";
        case ConnectionType::Network: return "network";
        case ConnectionType::Scsi: return "scsi";
        case ConnectionType::FireWire: return "fireWire";
        case ConnectionType::InternalBus: return "internalBus";
    }
    return "internalBus";
}

std::string backendName(std::string_view deviceString) {
    const auto colon = deviceString.find(':');
    return std::string(colon == std::string_view::npos ? deviceString
                                                       : deviceString.substr(0, colon));
}

bool supportsStableBackendSelector(std::string_view backend) noexcept {
    return backend == "genesys" || backend == "epson2";
}

ConnectionType connectionType(std::string_view deviceString) {
    const std::string v = toLower(deviceString);
    if (contains(v, ":net:")) return ConnectionType::Network;
    if (contains(v, ":scsi:") || contains(v, "/dev/sg")) return ConnectionType::Scsi;
    if (contains(v, ":firewire:") || contains(v, ":ieee1394:") || contains(v, ":ieee-1394:")) {
        return ConnectionType::FireWire;
    }
    // `:usbscan:` 은 Windows 에서 still-image 클래스 드라이버를 통해 열린 USB
    // 장치다 — `genesys:usbscan:000`. 주소가 아니라 커널 장치 번호라 열고
    // 닫아도, 전원을 다시 넣어도 바뀌지 않으므로 volatile 이 아니다.
    if (contains(v, ":usb:") || contains(v, ":libusb:") || contains(v, ":usbscan:")) {
        return ConnectionType::Usb;
    }
    return ConnectionType::InternalBus;
}

bool isDedicatedFilmBackend(std::string_view backend) noexcept {
    return backend == "coolscan" || backend == "coolscan2" || backend == "coolscan3" ||
           backend == "pie" || backend == "pieusb";
}

bool isVolatileUSBSelector(std::string_view value) noexcept {
    return contains(value, ":libusb:");
}

bool usesAutomaticAcquisitionWatchdog(std::string_view backend) noexcept {
    return backend != "pieusb";
}

std::vector<ListedDevice> parseDeviceList(std::string_view out) {
    // 정규식 원본: device `([^']+)' is a (.+)$
    // 수동 파서로 대체한다(language-decision §8.1) — 동작이 예측 가능하고
    // std::regex 구현 차이를 피한다.
    std::vector<ListedDevice> devices;

    for (std::string_view line : splitLines(out, /*keepEmpty=*/false)) {
        const auto devStart = line.find("device `");
        if (devStart == std::string_view::npos) continue;
        const size_t nameBegin = devStart + 8;  // strlen("device `")
        const auto nameEnd = line.find('\'', nameBegin);
        if (nameEnd == std::string_view::npos) continue;

        const std::string_view devname = line.substr(nameBegin, nameEnd - nameBegin);
        if (devname.empty()) continue;

        constexpr std::string_view kIsA = " is a ";
        if (line.compare(nameEnd + 1, kIsA.size(), kIsA) != 0) continue;
        std::string_view rest = trim(line.substr(nameEnd + 1 + kIsA.size()));
        if (rest.empty()) continue;

        std::string deviceType;
        const std::string restLower = toLower(rest);
        for (std::string_view suffix : kDeviceTypeSuffixes) {
            if (!endsWith(restLower, suffix)) continue;
            // 원문 대소문자를 유지한다(Swift: rest.suffix(suffix.count)).
            deviceType = std::string(rest.substr(rest.size() - suffix.size()));
            rest = trim(rest.substr(0, rest.size() - suffix.size()));
            break;
        }

        // 첫 토큰이 벤더, 나머지가 모델. 모델이 없으면 벤더를 모델로 쓴다.
        const auto sp = rest.find(' ');
        std::string vendor;
        std::string model;
        if (sp == std::string_view::npos) {
            vendor = std::string(rest);
            model = vendor;
        } else {
            vendor = std::string(rest.substr(0, sp));
            model = std::string(trim(rest.substr(sp + 1)));
        }

        devices.push_back(ListedDevice{std::string(devname), vendor, model, deviceType});
    }
    return devices;
}

std::vector<ListedDevice> parseFormattedDeviceList(std::string_view out) {
    std::vector<ListedDevice> devices;

    for (std::string_view line : splitLines(out, /*keepEmpty=*/false)) {
        // maxSplits: 3 — 넷째 필드에 탭이 있어도 통째로 남긴다.
        std::array<std::string_view, 4> fields{};
        size_t pos = 0;
        size_t count = 0;
        for (; count < 3; ++count) {
            const auto tab = line.find('\t', pos);
            if (tab == std::string_view::npos) break;
            fields[count] = line.substr(pos, tab - pos);
            pos = tab + 1;
        }
        if (count < 3) continue;  // 필드가 4개가 아니면 버린다
        fields[3] = line.substr(pos);

        // devname 은 trim 하지 않는다(Swift 도 fields[0] 을 그대로 쓴다).
        // 단 CRLF 입력에서 마지막 필드에 '\r' 이 남으므로 trim 대상이다.
        std::string devname(fields[0]);
        if (devname.empty()) continue;

        devices.push_back(ListedDevice{std::move(devname), std::string(trim(fields[1])),
                                       std::string(trim(fields[2])),
                                       std::string(trim(fields[3]))});
    }
    return devices;
}

std::string normalizedIdentityComponent(std::string_view value) {
    // 공백류로 나눠 단일 공백으로 재결합 + ASCII 소문자화.
    std::string out;
    size_t pos = 0;
    bool first = true;
    while (pos < value.size()) {
        const auto b = value.find_first_not_of(kSpace, pos);
        if (b == std::string_view::npos) break;
        auto e = value.find_first_of(kSpace, b);
        if (e == std::string_view::npos) e = value.size();
        if (!first) out.push_back(' ');
        for (size_t i = b; i < e; ++i) out.push_back(lowerAscii(value[i]));
        first = false;
        pos = e;
    }
    return out;
}

bool sameIdentity(const ListedDevice& device, std::string_view vendor, std::string_view model) {
    return normalizedIdentityComponent(device.vendor) == normalizedIdentityComponent(vendor) &&
           normalizedIdentityComponent(device.model) == normalizedIdentityComponent(model);
}

std::string capitalized(std::string_view value) {
    // Swift String.capitalized: 각 단어의 첫 글자를 대문자로, 나머지를 소문자로.
    // 단어 경계는 영숫자가 아닌 문자다("pie/reflecta" → "Pie/Reflecta").
    std::string out;
    out.reserve(value.size());
    bool atWordStart = true;
    for (char c : value) {
        const auto byte = static_cast<unsigned char>(c);

        // 비ASCII 바이트(UTF-8 다바이트 시퀀스)는 **단어 내부**로 취급한다.
        // 그대로 두되 단어 경계를 리셋하지 않는다 — 그래야 "ÉPSON" → "Épson" 이
        // 되어 Swift 와 일치한다. 경계로 취급하면 "ÉPson" 이 나온다(실측 확인).
        //
        // 완전한 유니코드 대소문자 변환은 하지 않는다. LC_ALL=C 전제에서 SANE
        // 벤더 문자열은 ASCII 이며, 비ASCII 는 원문 보존이 가장 안전하다.
        if (byte >= 0x80) {
            out.push_back(c);
            atWordStart = false;
            continue;
        }

        // **단어는 letter 의 연속이다. 숫자는 구분자다.**
        //   "a1b2"    → "A1B2"   (숫자 뒤 letter 가 다시 단어 시작)
        //   "gt-x970" → "Gt-X970"
        // isalnum 을 쓰면 "A1b2" 가 나온다 — 파리티 검사가 잡아냈다.
        if (std::isalpha(byte) == 0) {
            out.push_back(c);
            atWordStart = true;
            continue;
        }
        out.push_back(atWordStart ? upperAscii(c) : lowerAscii(c));
        atWordStart = false;
    }
    return out;
}

size_t dedupeByDevname(std::vector<ListedDevice>& devices) {
    std::set<std::string> seen;
    size_t removed = 0;
    std::vector<ListedDevice> kept;
    kept.reserve(devices.size());
    for (auto& d : devices) {
        if (seen.insert(d.devname).second) {
            kept.push_back(std::move(d));
        } else {
            ++removed;
        }
    }
    devices = std::move(kept);
    return removed;
}

}  // namespace negaflow::sane
