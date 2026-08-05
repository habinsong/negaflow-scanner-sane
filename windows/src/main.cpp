// negaflow-scanner-sane — Windows adapter
// main — 서브커맨드 디스패치와 wire 방출. **판정은 하지 않는다.**
//
// 이식 원본: Sources/negaflow-scanner-sane/main.swift
// 정본 문서: windows_docs/05-protocol/wire-contract.md §6, §7
//
// `wire/cli` 가 무엇을 할지 정하고, 이 파일은 그 판정을 받아 **실행만** 한다.
// 요청 검증은 `wire/request`, 옵션 해석은 `sane/media`, 실행 순서는
// `app/backend` 가 갖는다. 여기에 분기를 더하면 그것은 검증되지 않은 코드다.
//
// ## stdout 은 프로토콜 전용이다
//
// 진단은 전부 stderr 로 간다. 한 바이트라도 섞이면 호스트의 NDJSON 디코딩이
// 깨지고, 그것은 "플러그인이 이상한 것을 보냈다"로만 보인다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
// `WIN32_LEAN_AND_MEAN` 이 shellapi.h 를 빼므로 직접 넣는다.
// `CommandLineToArgvW` 가 거기 있다.
#include <shellapi.h>

#include <fcntl.h>
#include <io.h>
#include <stdio.h>

#include <optional>
#include <string>
#include <vector>

#include "app/backend.h"
#include "app/environment.h"
#include "process/cancel.h"
#include "sane/option_dump.h"
#include "wire/cli.h"
#include "wire/emitter.h"
#include "wire/event.h"
#include "wire/json.h"
#include "wire/parse.h"
#include "wire/protocol.h"
#include "wire/snapshot.h"
#include "wire/win_sink.h"
#include "wire/writer.h"

namespace {

using namespace negaflow;

[[nodiscard]] std::string narrow(std::wstring_view wide) {
    if (wide.empty()) return {};
    const int needed = WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                                           nullptr, 0, nullptr, nullptr);
    if (needed <= 0) return {};
    std::string out(static_cast<std::size_t>(needed), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), out.data(), needed,
                        nullptr, nullptr);
    return out;
}

/// `GetCommandLineW` 를 CRT 와 같은 규칙으로 나눈다.
///
/// **`CommandLineToArgvW` 를 쓴다.** `process/command_line` 의 인용 규칙과
/// 같은 파서이므로, 우리가 자식에게 넘기는 인자와 우리가 받는 인자가 같은
/// 계약 위에 선다(child-process §4.1).
[[nodiscard]] std::vector<std::string> commandLineArguments() {
    int count = 0;
    LPWSTR* raw = CommandLineToArgvW(GetCommandLineW(), &count);
    std::vector<std::string> args;
    if (raw == nullptr) return args;
    args.reserve(static_cast<std::size_t>(count));
    for (int i = 0; i < count; ++i) args.push_back(narrow(raw[i]));
    LocalFree(raw);
    return args;
}

/// stdin 을 끝까지 읽는다. 요청 JSON 이 여기로 온다.
[[nodiscard]] std::string readStandardInput() {
    HANDLE handle = GetStdHandle(STD_INPUT_HANDLE);
    if (handle == nullptr || handle == INVALID_HANDLE_VALUE) return {};
    (void)_setmode(_fileno(stdin), _O_BINARY);
    std::string data;
    std::vector<char> buffer(8192);
    for (;;) {
        DWORD read = 0;
        if (ReadFile(handle, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr) == 0) {
            break;
        }
        if (read == 0) break;
        data.append(buffer.data(), read);
    }
    return data;
}

/// stdin 이 파이프나 파일인가. 콘솔이면 읽지 않는다.
///
/// macOS 의 `isatty(fileno(stdin)) == 0` 대응이다. 사람이 터미널에서
/// `capabilities <id>` 만 치면 그대로 진행해야 한다 — 읽으려 들면 멈춘다.
[[nodiscard]] bool standardInputIsRedirected() {
    HANDLE handle = GetStdHandle(STD_INPUT_HANDLE);
    if (handle == nullptr || handle == INVALID_HANDLE_VALUE) return false;
    const DWORD type = GetFileType(handle);
    return type == FILE_TYPE_DISK || type == FILE_TYPE_PIPE;
}

/// JSON 한 줄을 stdout 으로. **JSON + LF 를 한 번에 쓴다.**
[[nodiscard]] bool emitLine(wire::ByteSink& sink, const wire::JsonValue& value) {
    const std::optional<std::string> json = wire::writeJson(value);
    if (!json) return false;
    std::string line = *json;
    line.push_back('\n');
    return wire::writeAll(line, sink) != wire::WriteOutcome::Failed;
}

void fail(std::string_view message) {
    wire::writeDiagnostic(std::string(wire::kDiagnosticPrefix) + std::string(message) + "\n");
}

// --- capabilities → wire DTO ----------------------------------------------

[[nodiscard]] wire::PluginCapabilities toWireCapabilities(const sane::ScannerCapabilities& caps,
                                                          std::string token) {
    wire::PluginCapabilities wireCaps;
    wireCaps.resolutionsDPI = caps.supportedResolutionsDPI;
    for (const auto mode : caps.supportedModes) {
        wireCaps.modes.emplace_back(sane::colorModeRawValue(mode));
    }
    for (const auto depth : caps.supportedBitDepths) {
        wireCaps.bitDepths.push_back(static_cast<int>(depth));
    }
    wireCaps.sourceModes = caps.sourceModes;
    wireCaps.transparencyModes = caps.transparencyModes;
    wireCaps.supportsPreview = caps.supportsPreview;
    wireCaps.supportsTransparency = caps.supportsTransparency;
    wireCaps.supportsInfrared = caps.supportsInfrared;
    wireCaps.supportsMultiExposure = caps.supportsMultiExposure;
    wireCaps.supportsScanArea = caps.supportsScanArea;
    wireCaps.supportsPositionedScanArea = caps.supportsPositionedScanArea;
    wireCaps.brightnessRange = caps.brightnessRange;
    wireCaps.contrastRange = caps.contrastRange;
    wireCaps.hardwareExposureRange = caps.hardwareExposureRange;
    wireCaps.scanOriginXRange = caps.scanOriginXRange;
    wireCaps.scanOriginYRange = caps.scanOriginYRange;
    wireCaps.scanWidthRange = caps.scanWidthRange;
    wireCaps.scanHeightRange = caps.scanHeightRange;
    // **빈 map 이어도 키를 낸다.** `{}` 는 nil 이 아니다(wire-contract §4.2.1).
    std::vector<std::pair<std::string, std::string>> reasons;
    reasons.reserve(caps.disabledReasons.size());
    for (const auto& [key, value] : caps.disabledReasons) reasons.emplace_back(key, value);
    wireCaps.disabledReasons = std::move(reasons);
    wireCaps.minScanAreaWidthMM = caps.minScanArea.widthMM;
    wireCaps.minScanAreaHeightMM = caps.minScanArea.heightMM;
    wireCaps.minScanAreaOriginXMM = caps.minScanArea.originXMM;
    wireCaps.minScanAreaOriginYMM = caps.minScanArea.originYMM;
    wireCaps.maxScanAreaWidthMM = caps.maxScanArea.widthMM;
    wireCaps.maxScanAreaHeightMM = caps.maxScanArea.heightMM;
    wireCaps.maxScanAreaOriginXMM = caps.maxScanArea.originXMM;
    wireCaps.maxScanAreaOriginYMM = caps.maxScanArea.originYMM;
    wireCaps.scanAreaUnit = std::string(sane::scanAreaUnitRawValue(caps.scanAreaUnit));
    wireCaps.outputFormats = caps.outputFormats;
    wireCaps.capabilityToken = std::move(token);
    return wireCaps;
}

// --- 서브커맨드 -------------------------------------------------------------

[[nodiscard]] int runDetect(app::Backend& backend, wire::ByteSink& sink) {
    std::vector<wire::PluginDevice> devices;
    // macOS `fail("detect 실패: \(error.localizedDescription)")` 와 같은 조립이다.
    if (auto error = backend.detect(&devices)) {
        fail("detect 실패: " + error->description());
        return 1;
    }
    if (!emitLine(sink, wire::encodeDetectResponse(devices))) {
        fail("detect 응답을 인코딩하지 못했습니다.");
        return 1;
    }
    return 0;
}

[[nodiscard]] int runCapabilities(app::Backend& backend,
                                  wire::ByteSink& sink,
                                  const std::string& deviceID) {
    std::optional<wire::DeviceIdentity> expected;
    if (standardInputIsRedirected()) {
        const std::string body = readStandardInput();
        if (!body.empty()) {
            // macOS 는 `try?` 로 감싼다 — 해석하지 못하면 힌트 없이 진행한다.
            if (const auto request =
                    wire::parseCapabilityRequest(body, wire::ParseLimits::product())) {
                const auto trimmedNonEmpty = [](const std::string& s) {
                    return s.find_first_not_of(" \t\r\n\f\v") != std::string::npos;
                };
                if (request->deviceID == deviceID && trimmedNonEmpty(request->vendor) &&
                    trimmedNonEmpty(request->model)) {
                    expected = wire::DeviceIdentity{request->vendor, request->model};
                }
            }
        }
    }

    app::CapabilityReport report;
    if (auto error = backend.capabilities(deviceID, expected, &report)) {
        fail("capabilities 실패: " + error->description());
        return 1;
    }
    const wire::PluginCapabilities wireCaps =
        toWireCapabilities(report.capabilities, report.capabilityToken);
    if (!emitLine(sink, wire::encodeCapabilities(wireCaps))) {
        fail("capabilities 응답을 인코딩하지 못했습니다.");
        return 1;
    }
    return 0;
}

/// 오류 이벤트 한 줄. sequence 를 소비하므로 emitter 를 거친다.
void emitError(wire::EventEmitter& emitter, wire::ByteSink& sink, std::string message) {
    const std::optional<std::string> line = emitter.emit(wire::makeErrorEvent(std::move(message)));
    if (!line) return;
    (void)wire::writeAll(*line, sink);
}

[[nodiscard]] wire::AppliedScanOptionsV2 makeAppliedOptions(const wire::ScanRequestV2& request,
                                                            const sane::ScanArea& appliedArea) {
    wire::AppliedScanOptionsV2 applied;
    applied.deviceID = request.deviceID;
    applied.resolutionDPI = request.resolutionDPI;
    applied.bitDepth = request.bitDepth;
    applied.colorMode = request.colorMode;
    applied.filmType = request.filmType;
    // **요청값이 아니라 실제로 보낸 값이다**(epson2 정수 mm 정렬).
    applied.scanArea = appliedArea;
    applied.infrared = request.infrared;
    applied.multiExposure = request.multiExposure;
    applied.hardwareExposureTime = request.hardwareExposureTime;
    applied.brightnessAdjustment = request.brightnessAdjustment;
    applied.contrastAdjustment = request.contrastAdjustment;
    applied.outputRawTIFF = request.outputRawTIFF;
    return applied;
}

[[nodiscard]] int runScan(app::Backend& backend, wire::ByteSink& sink) {
    const std::string body = readStandardInput();
    const wire::ParseLimits limits = wire::ParseLimits::product();

    const std::optional<wire::ScanRequestV2> request = wire::parseScanRequest(body, limits);
    if (!request) {
        // macOS 와 같다: 봉투에서 requestID 를 건질 수 있으면 wire 로,
        // 아니면 stderr 로. **사유는 싣지 않는다** — 문구가 갈리면 안 된다.
        const auto envelope = wire::parseScanRequestEnvelope(body, limits);
        if (envelope && envelope->protocolVersion == 2 && envelope->requestID) {
            wire::EventEmitter emitter{*envelope->requestID};
            emitError(emitter, sink, "scan 옵션 JSON 파싱 실패");
        } else {
            fail("scan 옵션 JSON 파싱 실패");
        }
        return 1;
    }

    wire::EventEmitter emitter{request->requestID};

    sane::ScanOptions options;
    if (auto validation =
            wire::validateScanRequest(*request, wire::PathPolicy::WindowsAbsolute, &options)) {
        emitError(emitter, sink, validation->description());
        return 1;
    }

    const app::ProgressCallback progress = [&](const app::ProgressEvent& event) {
        wire::ScanEventV2 wireEvent;
        wireEvent.type = "progress";
        wireEvent.phase = event.phase;
        wireEvent.fraction = event.fraction;
        wireEvent.message = event.message;
        if (const auto line = emitter.emit(std::move(wireEvent))) {
            (void)wire::writeAll(*line, sink);
        }
    };

    app::ScanOutcome outcome;
    if (auto scanError = backend.scan(options, request->capabilityToken, request->outputPath,
                                      progress, &outcome)) {
        emitError(emitter, sink, scanError->description());
        return 1;
    }

    // macOS 가 결과를 내보내기 전에 거는 계약 확인. 여기서 어긋나면 우리가
    // 적용한 것과 호스트가 기대하는 것이 다르다.
    if (outcome.outputPath.string() != request->outputPath ||
        static_cast<int>(outcome.bitDepth) != request->bitDepth ||
        outcome.hasInfrared != request->infrared) {
        emitError(emitter, sink,
                  sane::ScannerError{sane::ErrorCode::IoFailure,
                                     "scan 결과가 protocol v2 요청/적용 계약과 일치하지 "
                                     "않습니다."}
                      .description());
        return 1;
    }

    wire::ScanEventV2 result;
    result.type = "result";
    result.width = outcome.width;
    result.height = outcome.height;
    result.path = outcome.outputPath.string();
    result.resolutionDPI = request->resolutionDPI;
    result.bitDepth = static_cast<int>(outcome.bitDepth);
    if (outcome.infraredPath) result.irPath = outcome.infraredPath->string();
    result.hasInfrared = outcome.hasInfrared;
    if (!outcome.warnings.empty()) result.warnings = outcome.warnings;
    result.appliedOptions = makeAppliedOptions(*request, outcome.appliedScanArea);

    const std::optional<std::string> line = emitter.emit(std::move(result));
    if (!line) {
        emitError(emitter, sink, "result 이벤트를 인코딩하지 못했습니다.");
        return 1;
    }
    (void)wire::writeAll(*line, sink);
    return 0;
}

/// D-05: Windows 빌드는 `dll.conf` 를 수정하지 않는다. 활성 백엔드 목록만
/// 읽어 보고한다 — 진단에 유용하고, 없는 파일을 고치는 척하지 않는다.
[[nodiscard]] int runSaneConfigNoop(const app::ScanimageLocation& location, bool restore) {
    std::string text;
    if (restore) {
        text = "no backup to restore (this platform uses a private SANE configuration)\n";
    } else {
        text = "repair: notNeeded (this platform uses a private SANE configuration)\n";
        text += "scanimage: ";
        text += location.found ? location.path.string() : location.failure;
        text += "\n";
    }
    wire::writeDiagnostic(text);
    return 0;
}

}  // namespace

int main() {
    const std::vector<std::string> argv = commandLineArguments();
    // 기본값은 macOS 와 같은 쪽이다. 바꾸는 것은 사용자에게 보이는 동작
    // 변경이라 D 번호가 필요하다(cli.h).
    const wire::CliPlan plan = wire::planCli(argv);

    for (const auto& diagnostic : plan.diagnostics) {
        if (diagnostic.stream == wire::Stream::Stderr) {
            wire::writeDiagnostic(diagnostic.text);
        }
    }
    if (plan.exitCode) return *plan.exitCode;

    process::ProcessOwnership ownership;
    // 콘솔부터 확보한다. 없으면 `scanimage` 에 CTRL_BREAK 를 보낼 방법이
    // 없어 취소가 강제 종료로만 끝나고, 전송 도중에 죽은 스캐너는 전원을
    // 다시 넣기 전까지 돌아오지 않는다. 표준 핸들은 그 안에서 되돌린다.
    (void)process::ensureConsoleForCancellation();
    // 호스트 취소(A). 제어 핸들러 표는 콘솔을 만들 때 초기화되므로 이 순서를
    // 지킨다. 그래도 콘솔이 없으면 안전망은 Job Object 다 — 어댑터가 강제
    // 종료돼도 scanimage 가 남지 않는다.
    process::installConsoleCancellation(&ownership);

    app::ScanimageLocation location = app::findScanimage();
    app::Backend backend{location, ownership};
    wire::StdoutSink sink;

    switch (plan.command) {
        case wire::Subcommand::Detect:
            return runDetect(backend, sink);
        case wire::Subcommand::Capabilities:
            return runCapabilities(backend, sink, plan.argument);
        case wire::Subcommand::Scan:
            return runScan(backend, sink);
        case wire::Subcommand::RepairSaneConfig:
            return runSaneConfigNoop(location, /*restore=*/false);
        case wire::Subcommand::RestoreSane:
            return runSaneConfigNoop(location, /*restore=*/true);
        case wire::Subcommand::Help:
            return 0;
    }
    return 0;
}
