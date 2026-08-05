// SPDX-License-Identifier: GPL-2.0-or-later
//
// 검사 순서와 메시지 문구를 바꾸지 않는다.
// 근거: windows_docs/02-frontend-contract/exact-option-contract.md §3

#include "wire/request.h"

#include <algorithm>
#include <cmath>

namespace negaflow::wire {

namespace {

using sane::ErrorCode;
using sane::ScannerError;

[[nodiscard]] ScannerError rejected(std::string message) {
    // Swift 는 이 11개 조건을 전부 `.unsupportedOption` 으로 던진다.
    return ScannerError{ErrorCode::UnsupportedOption, std::move(message)};
}

/// Swift `trimmingCharacters(in: .whitespacesAndNewlines)` 후 빈 문자열인가.
///
/// Swift 의 문자 집합은 유니코드 공백 전체를 포함하지만, 여기서 판정하는 것은
/// "비어 있는가"뿐이다. ASCII 공백만 봐도 결론이 같은 입력이 대부분이고,
/// 다른 결론이 나오는 입력(U+00A0 등)은 어차피 뒤의 장치 조회에서 걸린다.
[[nodiscard]] bool isBlank(std::string_view s) noexcept {
    return std::all_of(s.begin(), s.end(), [](unsigned char c) {
        return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
    });
}

[[nodiscard]] bool isFinite(double v) noexcept { return std::isfinite(v); }

[[nodiscard]] std::string asciiUpper(std::string_view s) {
    std::string out(s);
    for (char& c : out) {
        if (c >= 'a' && c <= 'z') c = static_cast<char>(c - 'a' + 'A');
    }
    return out;
}

/// 파일이 아니라 장치로 열리는 이름. 확장자가 붙어도 마찬가지다(`NUL.tiff`).
[[nodiscard]] bool isReservedDeviceName(std::string_view component) {
    // 확장자를 떼고 본다. `CON.tiff` 도 `CON` 이다.
    const auto dot = component.find('.');
    const std::string stem = asciiUpper(dot == std::string_view::npos ? component
                                                                     : component.substr(0, dot));
    static const char* const kNames[] = {"CON", "PRN", "AUX", "NUL"};
    for (const char* n : kNames) {
        if (stem == n) return true;
    }
    if (stem.size() == 4 && (stem.compare(0, 3, "COM") == 0 || stem.compare(0, 3, "LPT") == 0)) {
        return stem[3] >= '1' && stem[3] <= '9';
    }
    return false;
}

/// macOS 원본과 같은 판정. **파리티 전용이다.**
///
/// Swift: `URL(fileURLWithPath: p).path == p && (p as NSString).isAbsolutePath`
///
/// **이 검사는 실제로는 정규화를 하지 않는다.** 이름과 문서가 그렇게 읽히지만
/// 실측(2026-08-05)은 다르다 — `URL(fileURLWithPath:).path` 는 **후행 슬래시만**
/// 없앤다. `..` 도 `.` 도 `//` 도 그대로 남는다.
///
/// ```text
/// "/tmp/../frame.tiff"          → 그대로. 통과
/// "/tmp/./frame.tiff"           → 그대로. 통과
/// "/tmp//frame.tiff"            → 그대로. 통과
/// "/tmp/a/../../../etc/passwd"  → 그대로. **통과한다**
/// "/tmp/frame/"                 → "/tmp/frame". 입력과 달라 거부
/// ```
///
/// 즉 macOS 의 9번 가드는 "`/` 로 시작하고 후행 슬래시가 없다"에 지나지 않는다.
/// **경로 탈출을 막지 못한다.** Windows 정책은 이것을 그대로 베끼지 않는다
/// (`isNormalizedWindowsAbsolute` 가 `..` 을 거부한다) — 의도된 divergence이며
/// exact-option-contract §3.1 과 §3.2 가 소유한다.
///
/// 여기서 원본을 그대로 재현하는 이유는 하나다: **파리티가 나머지 10개 가드를
/// 끝까지 대조할 수 있어야 한다.** production 정책은 이것이 아니다.
[[nodiscard]] bool isNormalizedPosixAbsolute(std::string_view path) noexcept {
    if (path.empty() || path.front() != '/') return false;
    // 후행 `/` 만 정규화에서 사라진다. 루트 자신("/")은 예외다.
    if (path.size() > 1 && path.back() == '/') return false;
    return true;
}

/// 제품 정책. `X:\...` 드라이브 절대 경로만 통과한다.
[[nodiscard]] bool isNormalizedWindowsAbsolute(std::string_view path) noexcept {
    // 장치 네임스페이스와 UNC 를 먼저 쳐낸다. 정규화를 우회하는 형태들이다.
    // UNC(\\server\share)와 장치 네임스페이스(\\?\ 와 \\.\)가 여기 걸린다.
    if (path.rfind("\\\\", 0) == 0) return false;
    if (path.rfind("\\??\\", 0) == 0) return false;

    // `X:\` 로 시작해야 한다. `C:foo`(드라이브 상대)와 `\foo`(루트 상대)는 거부.
    if (path.size() < 4) return false;
    const char drive = path[0];
    const bool isLetter = (drive >= 'A' && drive <= 'Z') || (drive >= 'a' && drive <= 'z');
    if (!isLetter || path[1] != ':' || path[2] != '\\') return false;

    // 슬래시는 Win32 가 받아들이지만 정규화하면 역슬래시로 바뀐다.
    // §3.1 이 "GetFullPathNameW 결과가 입력과 바이트 동일"을 요구하므로 거부한다.
    if (path.find('/') != std::string_view::npos) return false;

    const std::string_view rest = path.substr(3);
    if (rest.empty()) return false;  // `C:\` 는 디렉터리다. 파일 경로가 아니다.

    std::size_t start = 0;
    while (start <= rest.size()) {
        std::size_t end = rest.find('\\', start);
        if (end == std::string_view::npos) end = rest.size();
        const std::string_view component = rest.substr(start, end - start);

        if (component.empty()) return false;                 // `C:\a\\b` 또는 후행 `\`
        if (component == "." || component == "..") return false;
        if (component.back() == '.' || component.back() == ' ') return false;  // Win32 가 잘라낸다
        if (component.find(':') != std::string_view::npos) return false;       // ADS
        if (isReservedDeviceName(component)) return false;

        // 제어 문자와 Win32 가 금지하는 문자.
        for (unsigned char c : component) {
            if (c < 0x20) return false;
            if (c == '<' || c == '>' || c == '"' || c == '|' || c == '?' || c == '*') return false;
        }
        if (end == rest.size()) break;
        start = end + 1;
    }
    return true;
}

}  // namespace

bool isAcceptableOutputPath(std::string_view path, PathPolicy policy) noexcept {
    switch (policy) {
        case PathPolicy::WindowsAbsolute:
            return isNormalizedWindowsAbsolute(path);
        case PathPolicy::PosixAbsolute:
            return isNormalizedPosixAbsolute(path);
    }
    return false;
}

sane::ValidationResult validateScanRequest(const ScanRequestV2& request,
                                           PathPolicy policy,
                                           sane::ScanOptions* out) {
    // ① protocolVersion
    if (request.protocolVersion != 2) {
        return rejected("protocolVersion은 2여야 합니다.");
    }
    // ② deviceID
    if (isBlank(request.deviceID)) {
        return rejected("deviceID가 비어 있습니다.");
    }
    // ③ bitDepth
    std::optional<sane::BitDepth> bitDepth;
    if (request.bitDepth == 8) bitDepth = sane::BitDepth::Eight;
    if (request.bitDepth == 16) bitDepth = sane::BitDepth::Sixteen;
    if (!bitDepth) {
        return rejected("지원하지 않는 bitDepth: " + std::to_string(request.bitDepth));
    }
    // ④ colorMode — lineart/infrared 는 **인식은 되나 거부한다.**
    const auto colorMode = sane::colorModeFromRawValue(request.colorMode);
    if (!colorMode ||
        !(*colorMode == sane::ColorMode::Color || *colorMode == sane::ColorMode::Gray)) {
        return rejected("지원하지 않는 colorMode: " + request.colorMode);
    }
    // ⑤ filmType
    const auto filmType = sane::filmTypeFromRawValue(request.filmType);
    if (!filmType) {
        return rejected("지원하지 않는 filmType: " + request.filmType);
    }
    // ⑥ scanArea
    if (!isFinite(request.scanArea.originXMM) || !isFinite(request.scanArea.originYMM) ||
        !isFinite(request.scanArea.widthMM) || !isFinite(request.scanArea.heightMM) ||
        !(request.scanArea.originXMM >= 0) || !(request.scanArea.originYMM >= 0) ||
        !(request.scanArea.widthMM > 0) || !(request.scanArea.heightMM > 0)) {
        return rejected("scanArea가 유효하지 않습니다.");
    }
    // ⑦ hardwareExposureTime — null 이거나 > 0
    if (request.hardwareExposureTime && !(*request.hardwareExposureTime > 0)) {
        return rejected("hardwareExposureTime이 유효하지 않습니다.");
    }
    // ⑧ brightness/contrast — null 이거나 유한
    if ((request.brightnessAdjustment && !isFinite(*request.brightnessAdjustment)) ||
        (request.contrastAdjustment && !isFinite(*request.contrastAdjustment))) {
        return rejected("brightness/contrast 값이 유효하지 않습니다.");
    }
    // ⑨ outputPath — **여기만 플랫폼별로 판정이 갈린다.** 문구는 같다.
    if (!isAcceptableOutputPath(request.outputPath, policy)) {
        return rejected("outputPath는 정규화된 절대 경로여야 합니다.");
    }
    // ⑩ capabilityToken — UTF-8 1 MiB 이하
    if (request.capabilityToken && request.capabilityToken->size() > 1048576) {
        return rejected("capabilityToken이 허용 크기를 초과했습니다.");
    }
    // ⑪ preview / full 상호 배타 계약
    if (request.preview) {
        if (!(request.resolutionDPI == 0 && !request.infrared && !request.multiExposure &&
              !request.hardwareExposureTime && request.outputRawTIFF == false)) {
            return rejected("preview 요청 옵션 계약이 일치하지 않습니다.");
        }
    } else {
        if (!(request.resolutionDPI > 0)) {
            return rejected("full scan resolutionDPI는 양수여야 합니다.");
        }
        if (!request.outputRawTIFF) {
            return rejected("full scan은 outputRawTIFF=true만 지원합니다.");
        }
        if (request.multiExposure && request.hardwareExposureTime) {
            return rejected("multiExposure와 단일 hardwareExposureTime을 동시에 적용할 수 없습니다.");
        }
    }

    if (out) {
        out->scannerID = request.deviceID;
        out->resolutionDPI = request.resolutionDPI;
        out->bitDepth = *bitDepth;
        out->colorMode = *colorMode;
        out->filmType = *filmType;
        out->scanArea = request.scanArea;
        out->infraredEnabled = request.infrared;
        out->multiExposureEnabled = request.multiExposure;
        out->hardwareExposureTime = request.hardwareExposureTime;
        out->brightnessAdjustment = request.brightnessAdjustment;
        out->contrastAdjustment = request.contrastAdjustment;
        out->outputRawTIFF = request.outputRawTIFF;
    }
    return std::nullopt;
}

}  // namespace negaflow::wire
