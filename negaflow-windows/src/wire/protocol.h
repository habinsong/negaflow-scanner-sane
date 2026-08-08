// negaflow-scanner-sane — Windows adapter
// wire/protocol — `detect` / `capabilities` 응답의 JSON 형태.
//
// 이식 원본: Sources/negaflow-scanner-sane/WireProtocol.swift
// 정본 문서: docs/05-protocol/wire-contract.md §3, §4
//
// ## 이 타입들은 도메인 모델이 아니라 **wire DTO** 다
//
// Swift 쪽도 그렇게 나뉘어 있다 — `ScannerCapabilities`(도메인)와
// `PluginCapabilities`(wire)가 별개다. 그 경계를 지우면 도메인 타입을 고칠
// 때마다 호스트 계약이 조용히 바뀐다.
//
// 필드 이름과 타입은 negaflow 본체
// (`ScannerKit/ScannerPluginManifest.swift`)와 일치해야 한다.
//
// ## 전부 "생략" 쪽이다
//
// `PluginDevice` / `PluginCapabilities` / `ScannerOptionRange` 는 셋 다
// 합성 Codable 이다. **옵셔널이 비면 키를 쓰지 않는다.**
// `null` 을 쓰는 것은 `PluginAppliedScanOptionsV2` 하나뿐이며 그것은
// `wire/event` 가 다룬다.
// 근거: wire-contract.md §4.2.1 실측 표
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "util/numeric.h"
#include "wire/json.h"

namespace negaflow::wire {

/// `detect` 응답의 장치 하나.
struct PluginDevice {
    std::string id;
    std::string displayName;
    std::string vendor;
    std::string model;
    std::optional<std::string> connectionType;
    std::optional<std::string> usbVendorID;
    std::optional<std::string> usbProductID;
    std::optional<std::string> serialNumber;
    std::optional<std::string> verifiedStatus;
    std::optional<std::string> driverVersion;
};

/// `capabilities` 응답.
///
/// 옵셔널이 많은 것이 계약이다 — **장치가 노출하지 않은 능력은 키가 없다.**
/// 호스트가 키 부재를 "모름"으로 받는다. `false` 를 채워 넣으면 "지원하지
/// 않음을 확인했다"는 다른 뜻이 된다.
struct PluginCapabilities {
    std::vector<int> resolutionsDPI;
    std::vector<std::string> modes;
    std::vector<int> bitDepths;

    std::optional<std::vector<std::string>> sourceModes;
    std::optional<std::vector<std::string>> transparencyModes;
    std::optional<bool> supportsPreview;
    std::optional<bool> supportsTransparency;
    std::optional<bool> supportsInfrared;
    std::optional<bool> supportsMultiExposure;
    std::optional<bool> supportsScanArea;
    std::optional<bool> supportsPositionedScanArea;

    std::optional<util::OptionRange> brightnessRange;
    std::optional<util::OptionRange> contrastRange;
    std::optional<util::OptionRange> hardwareExposureRange;
    std::optional<util::OptionRange> scanOriginXRange;
    std::optional<util::OptionRange> scanOriginYRange;
    std::optional<util::OptionRange> scanWidthRange;
    std::optional<util::OptionRange> scanHeightRange;

    /// 빈 딕셔너리(`{}`)일 수 있다. **그것은 nil 이 아니므로 생략되지 않는다.**
    std::optional<std::vector<std::pair<std::string, std::string>>> disabledReasons;

    std::optional<double> minScanAreaWidthMM;
    std::optional<double> minScanAreaHeightMM;
    std::optional<double> minScanAreaOriginXMM;
    std::optional<double> minScanAreaOriginYMM;
    std::optional<double> maxScanAreaWidthMM;
    std::optional<double> maxScanAreaHeightMM;
    std::optional<double> maxScanAreaOriginXMM;
    std::optional<double> maxScanAreaOriginYMM;

    std::optional<std::string> scanAreaUnit;
    std::optional<std::vector<std::string>> outputFormats;
    std::optional<std::string> capabilityToken;
};

/// `ScannerOptionRange` → JSON. **`step` 이 없으면 키가 없다.**
///
/// wire-contract §4.2.1 이 실측으로 확인한 것: `"step":null` 은 나오지 않는다.
[[nodiscard]] JsonValue encodeOptionRange(const util::OptionRange& range);

[[nodiscard]] JsonValue encodeDevice(const PluginDevice& device);

/// `{"devices":[...]}`. **배열 순서는 의미다** — 열거 순서를 유지한다.
[[nodiscard]] JsonValue encodeDetectResponse(const std::vector<PluginDevice>& devices);

[[nodiscard]] JsonValue encodeCapabilities(const PluginCapabilities& capabilities);

}  // namespace negaflow::wire
