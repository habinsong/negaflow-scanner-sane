// SPDX-License-Identifier: GPL-2.0-or-later
//
// 키를 넣는 순서 = Swift 의 선언 순서다. 실제 wire 에서 키 순서는 계약이
// 아니지만(JSONEncoder 가 해시 순서를 쓴다), 선언 순서를 따르면 사람이
// 원본과 대조하기 쉽고 골든 파일이 읽을 만해진다.

#include "wire/event.h"

namespace negaflow::wire {

JsonValue encodeScanArea(const sane::ScanArea& area) {
    JsonValue j = JsonValue::object();
    j.set("originXMM", JsonValue::number(area.originXMM));
    j.set("originYMM", JsonValue::number(area.originYMM));
    j.set("widthMM", JsonValue::number(area.widthMM));
    j.set("heightMM", JsonValue::number(area.heightMM));
    return j;
}

JsonValue encodeAppliedOptions(const AppliedScanOptionsV2& options) {
    JsonValue j = JsonValue::object();
    j.set("deviceID", JsonValue::string(options.deviceID));
    j.set("resolutionDPI", JsonValue::integer(options.resolutionDPI));
    j.set("bitDepth", JsonValue::integer(options.bitDepth));
    j.set("colorMode", JsonValue::string(options.colorMode));
    j.set("filmType", JsonValue::string(options.filmType));
    j.set("scanArea", encodeScanArea(options.scanArea));
    j.set("infrared", JsonValue::boolean(options.infrared));
    j.set("multiExposure", JsonValue::boolean(options.multiExposure));

    // **여기가 예외다.** 값이 없어도 키를 쓴다. 호스트가 필수로 요구한다.
    // 이 셋을 setIfPresent 로 바꾸면 인수 gate 에서 걸린다.
    j.setOrNull("hardwareExposureTime", options.hardwareExposureTime);
    j.setOrNull("brightnessAdjustment", options.brightnessAdjustment);
    j.setOrNull("contrastAdjustment", options.contrastAdjustment);

    j.set("outputRawTIFF", JsonValue::boolean(options.outputRawTIFF));
    return j;
}

JsonValue encodeScanEvent(const ScanEventV2& event) {
    JsonValue j = JsonValue::object();
    j.set("type", JsonValue::string(event.type));
    // Swift 는 생성자에서 2 를 넣는다. 요청에서 받아 되돌리지 않는다.
    j.set("protocolVersion", JsonValue::integer(2));
    j.set("requestID", JsonValue::string(event.requestID));
    j.set("sequence", JsonValue::integer(static_cast<std::int64_t>(event.sequence)));

    // **여기부터는 전부 생략이다.** 합성 Codable 의 동작이다.
    j.setIfPresent("phase", event.phase);
    j.setIfPresent("fraction", event.fraction);
    j.setIfPresent("message", event.message);
    j.setIfPresent("width", event.width);
    j.setIfPresent("height", event.height);
    j.setIfPresent("path", event.path);
    j.setIfPresent("resolutionDPI", event.resolutionDPI);
    j.setIfPresent("bitDepth", event.bitDepth);
    j.setIfPresent("irPath", event.irPath);
    j.setIfPresent("hasInfrared", event.hasInfrared);

    if (event.warnings) {
        JsonValue array = JsonValue::array();
        // **배열 순서는 의미다.** 정렬하지 않는다.
        for (const auto& w : *event.warnings) array.push(JsonValue::string(w));
        j.set("warnings", std::move(array));
    }
    if (event.appliedOptions) {
        j.set("appliedOptions", encodeAppliedOptions(*event.appliedOptions));
    }
    return j;
}

}  // namespace negaflow::wire
