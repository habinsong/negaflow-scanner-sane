// negaflow-scanner-sane — Windows adapter
// sane/device_list — `scanimage -f` / `-L` 장치 목록 파싱과 장치 문자열 판정.
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend+Discovery.swift
//            Sources/SANEPluginCore/SANEBackend+ScanExecution.swift (isVolatileUSBSelector)
// 정본 문서: docs/02-frontend-contract/device-identity.md
//
// **모델명으로 분기하지 않는다.** 벤더·모델은 목록에서 읽은 문자열일 뿐이고,
// 능력 판정에 쓰지 않는다. 8200i 가 "OpticFilm 8100" 으로 보고되는 실측이 그 이유다.
// 근거: docs/10-lessons/field-lessons.md §10
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <string>
#include <string_view>
#include <vector>

namespace negaflow::sane {

enum class ConnectionType {
    Usb,
    Network,
    Scsi,
    FireWire,
    InternalBus,
};

/// wire 로 나가는 문자열. Swift `ConnectionType.rawValue` 와 같아야 한다.
[[nodiscard]] std::string_view connectionTypeRawValue(ConnectionType t) noexcept;

/// SANE 장치 목록 한 줄.
struct ListedDevice {
    std::string devname;     // genesys:libusb:000:010
    std::string vendor;      // PLUSTEK / Epson / Nikon
    std::string model;       // OpticFilm 8100 / GT-X970
    std::string deviceType;  // flatbed scanner / film scanner / …

    friend bool operator==(const ListedDevice&, const ListedDevice&) = default;
};

/// 장치 문자열의 백엔드 이름. 첫 ':' 앞.
///
/// `net:host:genesys:...` 는 `net` 으로 판정된다. **의도된 동작이다** —
/// 원격 경로는 지원 대상 밖이고(D-03), 중첩 파싱이 틀리면 로컬 경로까지 망가진다.
[[nodiscard]] std::string backendName(std::string_view deviceString);

/// 주소 없는 `-d <backend>` 선택자를 허용하는 백엔드인가.
///
/// SANE dll 계층이 이 형식을 backend 의 빈 장치명으로 전달한다. genesys/epson2 는
/// 빈 장치명을 첫 장치로 처리하지만 coolscan2/3 은 거부한다.
/// **USB 백엔드 전체로 일반화하면 안 된다.**
[[nodiscard]] bool supportsStableBackendSelector(std::string_view backend) noexcept;

[[nodiscard]] ConnectionType connectionType(std::string_view deviceString);

[[nodiscard]] bool isDedicatedFilmBackend(std::string_view backend) noexcept;

/// 장치를 열 때마다 바뀌는 주소를 포함한 선택자인가.
[[nodiscard]] bool isVolatileUSBSelector(std::string_view value) noexcept;

/// pieusb 는 shading/calibration 을 sane_start 안에서 동기 실행해
/// 첫 진행률이 장시간 없을 수 있다. 중간 종료는 transport 상태를 불명확하게 만든다.
[[nodiscard]] bool usesAutomaticAcquisitionWatchdog(std::string_view backend) noexcept;

/// `scanimage -L` 출력 파싱.
///
///     device `coolscan3:usb:libusb:001:002' is a Nikon LS-50 ED film scanner
///
/// 타입 접미사를 떼고 첫 토큰을 벤더, 나머지를 모델로 삼는다.
/// **번역된 문장은 파싱하지 못한다.** 그래서 `-f` 가 우선이고 `LC_ALL=C` 를 고정한다.
[[nodiscard]] std::vector<ListedDevice> parseDeviceList(std::string_view out);

/// `scanimage -f "%d\t%v\t%m\t%t%n"` 출력 파싱. 탭 4필드.
///
/// 번역에 영향받지 않으므로 이쪽이 정본 경로다.
[[nodiscard]] std::vector<ListedDevice> parseFormattedDeviceList(std::string_view out);

/// 같은 장치인가. 벤더·모델을 정규화해 비교한다.
///
/// 같은 모델 두 대가 붙어 있으면 **거부한다**(호출부). 엉뚱한 스캐너를 여는 것보다
/// 실패가 낫다 — I-9.
[[nodiscard]] bool sameIdentity(const ListedDevice& device,
                                std::string_view vendor,
                                std::string_view model);

/// 대소문자·공백을 정규화한다.
///
/// Swift 원본은 folding(caseInsensitive, diacriticInsensitive, widthInsensitive) 후
/// 공백류로 나눠 단일 공백으로 재결합한다. `LC_ALL=C` 전제이므로 여기서는 ASCII
/// 소문자화 + 공백 정규화로 같은 결과를 낸다.
[[nodiscard]] std::string normalizedIdentityComponent(std::string_view value);

/// `displayName` 용 대문자화. Swift `String.capitalized` 와 같아야 한다.
///
/// **각 단어의 첫 글자를 대문자로, 나머지를 소문자로.** `ToUpperInvariant` 나
/// "첫 글자만" 구현을 쓰면 `"PLUSTEK"` 이 그대로 남아 displayName 이 달라진다.
/// 로케일 독립이어야 한다(터키어 i 문제).
[[nodiscard]] std::string capitalized(std::string_view value);

/// detect 응답에서 devname 중복을 제거한다. **첫 항목이 이긴다.**
///
/// 호스트가 중복 routed ID 를 "첫 항목만 남기고 plugin defect 로 기록" 한다.
/// 우리가 먼저 정리하면 결과는 같고 결함 기록만 사라진다.
/// 근거: docs/05-protocol/host-requirements.md §3.1
///
/// 제거한 개수를 돌려준다(진단용).
[[nodiscard]] size_t dedupeByDevname(std::vector<ListedDevice>& devices);

}  // namespace negaflow::sane
