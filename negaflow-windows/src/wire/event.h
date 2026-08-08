// negaflow-scanner-sane — Windows adapter
// wire/event — scan 이벤트와 적용 옵션의 JSON 형태.
//
// 이식 원본: Sources/SANEPluginCore/PluginProtocolV2.swift
//            (PluginScanEventV2, PluginAppliedScanOptionsV2)
// 정본 문서: docs/05-protocol/wire-contract.md §4.2.1, §5
//
// ## 이 파일이 존재하는 이유 — 생략과 null 이 갈린다
//
// ```text
// PluginScanEventV2            합성 Codable  → 옵셔널이 nil 이면 **키 생략**
// PluginAppliedScanOptionsV2   명시적 encode → 옵셔널이 nil 이면 **null 명시**
// ```
//
// **후자가 예외이고 그 예외가 의도적이다.** 호스트가 `appliedOptions` 의 12키를
// 필수로 요구한다(본체 `10-scanner/protocol-contract.md` §9.1: "key omission은
// decode failure입니다"). 그 문장의 적용 범위는 `appliedOptions` 하나뿐인데,
// 이것을 "모든 옵셔널 키는 항상 있어야 한다"로 읽으면 macOS 실측과 정면으로
// 충돌한다(wire-contract §4.2.1 표).
//
// 그리고 이 구분은 우리 쪽 추론이 아니다 — 본체 문서 §20 이
// "v1 omitted-vs-null serialization 일치"를 **Windows 인수 gate** 로 적고 있다.
// 바꿔 쓰면 gate 에서 걸린다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "sane/media.h"
#include "wire/json.h"

namespace negaflow::wire {

/// 결과에 실린 **실제 적용 옵션**.
///
/// `scanArea` 는 요청과 다를 수 있다(epson2 정수 mm 정렬). 호스트는 이 값으로
/// 결과 픽셀을 검증하므로 요청값이 아니라 **보낸 값**을 담는다.
struct AppliedScanOptionsV2 {
    std::string deviceID;
    int resolutionDPI = 0;
    int bitDepth = 16;
    std::string colorMode;
    std::string filmType;
    sane::ScanArea scanArea{};
    bool infrared = false;
    bool multiExposure = false;
    std::optional<int> hardwareExposureTime;
    std::optional<double> brightnessAdjustment;
    std::optional<double> contrastAdjustment;
    bool outputRawTIFF = true;
};

/// scan 진행 중 stdout 으로 나가는 NDJSON 한 줄.
struct ScanEventV2 {
    std::string type;
    std::string requestID;  ///< UUID. Swift 는 **대문자**로 인코딩한다
    std::uint64_t sequence = 0;

    std::optional<std::string> phase;
    std::optional<double> fraction;
    std::optional<std::string> message;
    std::optional<int> width;
    std::optional<int> height;
    std::optional<std::string> path;
    std::optional<int> resolutionDPI;
    std::optional<int> bitDepth;
    std::optional<std::string> irPath;
    std::optional<bool> hasInfrared;
    std::optional<std::vector<std::string>> warnings;
    std::optional<AppliedScanOptionsV2> appliedOptions;
};

/// `ScanArea` → JSON. 옵셔널이 없으므로 4키가 항상 나온다.
[[nodiscard]] JsonValue encodeScanArea(const sane::ScanArea& area);

/// 적용 옵션 → JSON. **12키가 항상 나온다.** nil 은 `null` 이다.
[[nodiscard]] JsonValue encodeAppliedOptions(const AppliedScanOptionsV2& options);

/// 이벤트 → JSON. **nil 옵셔널은 키가 없다.**
///
/// `protocolVersion` 은 항상 2 이며 생성자가 넣는다(Swift 와 같다).
[[nodiscard]] JsonValue encodeScanEvent(const ScanEventV2& event);

}  // namespace negaflow::wire
