// SPDX-License-Identifier: GPL-2.0-or-later
//
// 키를 넣는 순서 = Swift 의 선언 순서다. 실제 wire 에서 키 순서는 계약이
// 아니지만(JSONEncoder 가 해시 순서를 쓴다), 선언 순서를 따르면 원본과
// 대조하기 쉽다.

#include "wire/protocol.h"

namespace negaflow::wire {

namespace {

/// 문자열 배열 → JSON 배열. **순서를 유지한다.**
[[nodiscard]] JsonValue stringArray(const std::vector<std::string>& values) {
    JsonValue array = JsonValue::array();
    for (const auto& v : values) array.push(JsonValue::string(v));
    return array;
}

[[nodiscard]] JsonValue intArray(const std::vector<int>& values) {
    JsonValue array = JsonValue::array();
    for (int v : values) array.push(JsonValue::integer(v));
    return array;
}

/// 옵셔널 배열은 **없으면 키를 넣지 않는다.** 빈 배열과 부재는 다르다.
void setStringArrayIfPresent(JsonValue& object,
                             std::string key,
                             const std::optional<std::vector<std::string>>& values) {
    if (!values) return;
    object.set(std::move(key), stringArray(*values));
}

void setRangeIfPresent(JsonValue& object,
                       std::string key,
                       const std::optional<util::OptionRange>& range) {
    if (!range) return;
    object.set(std::move(key), encodeOptionRange(*range));
}

}  // namespace

JsonValue encodeOptionRange(const util::OptionRange& range) {
    JsonValue j = JsonValue::object();
    j.set("minimum", JsonValue::number(range.minimum));
    j.set("maximum", JsonValue::number(range.maximum));
    // **step 이 없으면 키가 없다.** 합성 Codable 이므로 null 을 쓰지 않는다.
    j.setIfPresent("step", range.step);
    return j;
}

JsonValue encodeDevice(const PluginDevice& device) {
    JsonValue j = JsonValue::object();
    j.set("id", JsonValue::string(device.id));
    j.set("displayName", JsonValue::string(device.displayName));
    j.set("vendor", JsonValue::string(device.vendor));
    j.set("model", JsonValue::string(device.model));
    // 여기부터 전부 생략 대상이다. `null` 을 쓰지 않는다.
    j.setIfPresent("connectionType", device.connectionType);
    j.setIfPresent("usbVendorID", device.usbVendorID);
    j.setIfPresent("usbProductID", device.usbProductID);
    j.setIfPresent("serialNumber", device.serialNumber);
    j.setIfPresent("verifiedStatus", device.verifiedStatus);
    j.setIfPresent("driverVersion", device.driverVersion);
    return j;
}

JsonValue encodeDetectResponse(const std::vector<PluginDevice>& devices) {
    JsonValue array = JsonValue::array();
    for (const auto& d : devices) array.push(encodeDevice(d));
    JsonValue j = JsonValue::object();
    j.set("devices", std::move(array));
    return j;
}

JsonValue encodeCapabilities(const PluginCapabilities& capabilities) {
    JsonValue j = JsonValue::object();
    // 이 셋은 옵셔널이 아니다 — 빈 배열이어도 키가 나온다.
    j.set("resolutionsDPI", intArray(capabilities.resolutionsDPI));
    j.set("modes", stringArray(capabilities.modes));
    j.set("bitDepths", intArray(capabilities.bitDepths));

    setStringArrayIfPresent(j, "sourceModes", capabilities.sourceModes);
    setStringArrayIfPresent(j, "transparencyModes", capabilities.transparencyModes);

    j.setIfPresent("supportsPreview", capabilities.supportsPreview);
    j.setIfPresent("supportsTransparency", capabilities.supportsTransparency);
    j.setIfPresent("supportsInfrared", capabilities.supportsInfrared);
    j.setIfPresent("supportsMultiExposure", capabilities.supportsMultiExposure);
    j.setIfPresent("supportsScanArea", capabilities.supportsScanArea);
    j.setIfPresent("supportsPositionedScanArea", capabilities.supportsPositionedScanArea);

    setRangeIfPresent(j, "brightnessRange", capabilities.brightnessRange);
    setRangeIfPresent(j, "contrastRange", capabilities.contrastRange);
    setRangeIfPresent(j, "hardwareExposureRange", capabilities.hardwareExposureRange);
    setRangeIfPresent(j, "scanOriginXRange", capabilities.scanOriginXRange);
    setRangeIfPresent(j, "scanOriginYRange", capabilities.scanOriginYRange);
    setRangeIfPresent(j, "scanWidthRange", capabilities.scanWidthRange);
    setRangeIfPresent(j, "scanHeightRange", capabilities.scanHeightRange);

    if (capabilities.disabledReasons) {
        JsonValue reasons = JsonValue::object();
        // **빈 딕셔너리는 nil 이 아니다.** `{}` 가 그대로 나간다.
        for (const auto& [key, value] : *capabilities.disabledReasons) {
            reasons.set(key, JsonValue::string(value));
        }
        j.set("disabledReasons", std::move(reasons));
    }

    j.setIfPresent("minScanAreaWidthMM", capabilities.minScanAreaWidthMM);
    j.setIfPresent("minScanAreaHeightMM", capabilities.minScanAreaHeightMM);
    j.setIfPresent("minScanAreaOriginXMM", capabilities.minScanAreaOriginXMM);
    j.setIfPresent("minScanAreaOriginYMM", capabilities.minScanAreaOriginYMM);
    j.setIfPresent("maxScanAreaWidthMM", capabilities.maxScanAreaWidthMM);
    j.setIfPresent("maxScanAreaHeightMM", capabilities.maxScanAreaHeightMM);
    j.setIfPresent("maxScanAreaOriginXMM", capabilities.maxScanAreaOriginXMM);
    j.setIfPresent("maxScanAreaOriginYMM", capabilities.maxScanAreaOriginYMM);

    j.setIfPresent("scanAreaUnit", capabilities.scanAreaUnit);
    setStringArrayIfPresent(j, "outputFormats", capabilities.outputFormats);
    j.setIfPresent("capabilityToken", capabilities.capabilityToken);
    return j;
}

}  // namespace negaflow::wire
