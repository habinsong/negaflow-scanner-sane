// negaflow-scanner-sane — Windows adapter
// wire/snapshot — `capabilityToken` 의 내용물. JSON + base64.
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend+Discovery.swift
//            (private struct SANECapabilitySnapshot)
// 정본 문서: docs/02-frontend-contract/capability-model.md
//
// ## 토큰은 **신뢰할 수 없는 입력이다**
//
// 호스트를 거쳐 돌아오고 호스트는 내용을 검사하지 않는다. 그래서
// `acquisitionDevice` 가 그대로 `-d` 인자가 되는 경로에
// `process::isSafeDeviceName` 검사가 붙는다(child-process §4.3).
// 여기서는 **디코딩만** 하고 판정은 호출자가 한다.
//
// ## 왜 `schemaVersion` 이 있는가
//
// 플러그인이 갱신되면 예전 토큰이 남아 있다. 버전이 다르면 해석하지 않고
// "능력을 다시 조회하라"고 답한다 — 낡은 덤프로 스캔하면 요청과 다른 옵션이
// 적용될 수 있다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <optional>
#include <string>
#include <string_view>

namespace negaflow::wire {

/// 장치 제조사·모델. 주소가 바뀌어도 "같은 모델"임을 확인하는 근거다.
struct DeviceIdentity {
    std::string vendor;
    std::string model;

    friend bool operator==(const DeviceIdentity&, const DeviceIdentity&) = default;
};

/// capability 조회 시점의 상태를 통째로 담는다.
struct CapabilitySnapshot {
    /// macOS 와 같은 값을 쓴다. 두 구현이 같은 형태를 유지한다는 표시다.
    static constexpr int kCurrentSchemaVersion = 3;

    int schemaVersion = kCurrentSchemaVersion;
    std::string deviceID;           ///< 요청의 `deviceID`. `sane-` 접두 포함
    std::string backend;            ///< `genesys` 등
    std::string acquisitionDevice;  ///< 실제로 연 SANE 장치 문자열
    std::optional<DeviceIdentity> deviceIdentity;
    std::optional<std::string> deviceType;  ///< `-L` 의 타입 문자열
    std::string optionDump;                 ///< `scanimage -A` 원문
    /// `optionDump` 를 실제로 적용해 읽은 모드. 다른 모드 요청에는 재사용하지 않는다.
    std::optional<std::string> validatedMode;
};

/// 토큰 최대 길이. Swift 와 같다(`token.utf8.count <= 1_048_576`).
inline constexpr std::size_t kMaxCapabilityTokenBytes = 1u << 20;

/// 스냅샷 → base64(JSON). 실패하면 nullopt(NaN 은 없으므로 사실상 성공한다).
[[nodiscard]] std::optional<std::string> encodeCapabilityToken(const CapabilitySnapshot& snapshot);

/// base64(JSON) → 스냅샷. 형태가 어긋나면 nullopt.
///
/// **`schemaVersion` 만 여기서 검사한다.** 장치 일치 여부는 호출자가 본다 —
/// 그쪽이 요청을 알고 있고, 오류 문구도 그쪽 것이다(Swift 와 같은 분담).
[[nodiscard]] std::optional<CapabilitySnapshot> decodeCapabilityToken(std::string_view token);

// --- base64 (테스트에서 직접 검증한다) ------------------------------------

[[nodiscard]] std::string base64Encode(std::string_view raw);

/// 표준 알파벳 + 패딩만 받는다. 공백·개행·URL-safe 변형은 거부한다.
[[nodiscard]] std::optional<std::string> base64Decode(std::string_view encoded);

}  // namespace negaflow::wire
