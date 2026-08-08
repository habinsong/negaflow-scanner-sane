// SPDX-License-Identifier: GPL-2.0-or-later

#include "app/backend.h"

#include <algorithm>
#include <chrono>
#include <system_error>
#include <thread>
#include <utility>

#include "imaging/merge.h"
#include "imaging/tiff_io.h"
#include "process/acquisition.h"
#include "process/child.h"
#include "process/command_line.h"
#include "process/progress.h"
#include "sane/args.h"
#include "sane/option_dump.h"

namespace negaflow::app {

namespace {

using sane::ErrorCode;
using sane::ScannerError;

/// 주소 캐시 수명. macOS 와 같다.
constexpr process::Duration kAddressCacheTTL = std::chrono::milliseconds{5'000};

/// 재시도 사이의 대기. macOS 의 `Task.sleep(800ms)` 와 같다.
constexpr process::Duration kRetryDelay = std::chrono::milliseconds{800};

[[nodiscard]] ScannerError error(ErrorCode code, std::string message) {
    return ScannerError{code, std::move(message)};
}

[[nodiscard]] std::string stripSanePrefix(std::string value) {
    if (value.rfind("sane-", 0) == 0) value.erase(0, 5);
    return value;
}

[[nodiscard]] std::string trimmed(std::string_view s) {
    const auto isSpace = [](unsigned char c) {
        return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
    };
    std::size_t begin = 0;
    std::size_t end = s.size();
    while (begin < end && isSpace(static_cast<unsigned char>(s[begin]))) ++begin;
    while (end > begin && isSpace(static_cast<unsigned char>(s[end - 1]))) --end;
    return std::string{s.substr(begin, end - begin)};
}

[[nodiscard]] ErrorCode codeForStderr(std::string_view message) {
    switch (process::classifyStderr(message)) {
        case process::StderrClass::Busy: return ErrorCode::Busy;
        case process::StderrClass::NotConnected: return ErrorCode::NotConnected;
        case process::StderrClass::IoFailure: break;
    }
    return ErrorCode::IoFailure;
}

/// 목록을 다시 읽어서 해결될 여지가 있는 오류인가.
[[nodiscard]] bool isRetryableAddressError(const ScannerError& e) {
    switch (e.code) {
        case ErrorCode::Cancelled:
        case ErrorCode::Timeout:
        case ErrorCode::UnsupportedOption:
        case ErrorCode::DriverConflict:
            return false;
        case ErrorCode::Busy:
        case ErrorCode::IoFailure:
            return true;
        case ErrorCode::NotConnected:
        case ErrorCode::Unknown:
            // 장치가 아직 목록에 안 뜬 경우만 재시도 가치가 있다. 여러 대가
            // 잡혀 모호하거나 다른 모델이 붙어 있으면 같은 답이 나온다.
            return e.message.find("여러 대라") == std::string::npos &&
                   e.message.find("일치하지 않습니다") == std::string::npos;
    }
    return false;
}

/// capability 조회를 다시 시도할 가치가 있는 오류인가.
[[nodiscard]] bool shouldRetryCapabilityRead(const ScannerError& e) {
    switch (e.code) {
        case ErrorCode::Busy:
        case ErrorCode::NotConnected:
        case ErrorCode::IoFailure:
            return true;
        case ErrorCode::UnsupportedOption:
        case ErrorCode::DriverConflict:
        case ErrorCode::Cancelled:
        case ErrorCode::Timeout:
        case ErrorCode::Unknown:
            return false;
    }
    return false;
}

[[nodiscard]] bool sameIdentity(const sane::ListedDevice& device, const wire::DeviceIdentity& id) {
    return sane::sameIdentity(device, id.vendor, id.model);
}

void removeQuietly(const std::filesystem::path& path) {
    std::error_code ec;
    std::filesystem::remove(path, ec);
}

[[nodiscard]] double mapProgress(double low, double high, double fraction) {
    return low + (high - low) * fraction;
}

}  // namespace

Backend::Backend(ScanimageLocation location, process::ProcessOwnership& ownership)
    : location_(std::move(location)), ownership_(ownership) {
    refreshEnvironment();
}

void Backend::refreshEnvironment() {
    std::optional<std::string> defaultDevice;
    if (cachedAddress_ &&
        (cachedAddressIsStableSelector_ ||
         std::chrono::steady_clock::now() - cachedAddressAt_ < kAddressCacheTTL)) {
        defaultDevice = cachedAddress_;
    }
    environmentBlock_ = buildScanEnvironment(location_.path, defaultDevice);
}

void Backend::beginCommand(process::Command command) {
    command_ = command;
    commandStart_ = std::chrono::steady_clock::now();
}

std::optional<process::Duration> Backend::nextCallTimeout() const {
    const process::CommandBudget budget(command_, commandStart_);
    return budget.nextCallTimeout(std::chrono::steady_clock::now());
}

// --- scanimage 실행 --------------------------------------------------------

sane::ValidationResult Backend::runScanimage(const std::vector<std::string>& args,
                                             bool ownedByScanSession,
                                             std::string* stdoutText) {
    if (!location_.found) {
        return error(ErrorCode::NotConnected, location_.failure);
    }
    if (ownership_.cancellationRequested()) {
        return error(ErrorCode::Cancelled, "스캔이 취소되었습니다.");
    }

    // D-32: 명령 총 예산에서 이 호출의 상한을 역산한다. 남은 것이 없으면
    // **시작하지 않는다** — 시작해도 호스트가 먼저 죽여서 우리 오류 이벤트가
    // 나가지 못한다.
    const std::optional<process::Duration> timeout = nextCallTimeout();
    if (!timeout) {
        return error(ErrorCode::Timeout,
                     std::string("scanimage 조회에 남은 시간이 없습니다(") +
                         std::string(process::commandName(command_)) + " 예산 초과).");
    }

    refreshEnvironment();
    const process::UtilityOutcome outcome = process::runUtility(
        location_.path, args, environmentBlock_, *timeout, ownership_, ownedByScanSession);

    // `-d` 가 붙은 실행만 장치를 실제로 연다. 목록 조회(-L/-f)는 주소를 바꾸지 않는다.
    const bool opensDevice = std::find(args.begin(), args.end(), "-d") != args.end();
    if (opensDevice) noteDeviceOpened();

    switch (outcome.status) {
        case process::LaunchStatus::Ok:
            break;
        case process::LaunchStatus::Busy:
            return error(ErrorCode::Busy,
                         "이 plugin instance에서 scanimage가 이미 실행 중입니다.");
        case process::LaunchStatus::Cancelled:
            return error(ErrorCode::Cancelled, "스캔이 취소되었습니다.");
        case process::LaunchStatus::LaunchFailed:
            return error(ErrorCode::IoFailure, outcome.launchError);
    }

    lastStderr_ = outcome.stderrText;
    if (outcome.cancelled) {
        return error(ErrorCode::Cancelled, "스캔이 취소되었습니다.");
    }
    if (outcome.timedOut) {
        const long long seconds = timeout->count() / 1000;
        return error(ErrorCode::Timeout, "scanimage 조회가 " + std::to_string(seconds) +
                                             "초 안에 끝나지 않았습니다.");
    }
    if (outcome.exitCode != 0) {
        const std::string detail = trimmed(outcome.stderrText);
        const std::string message =
            detail.empty()
                ? "scanimage가 종료 코드 " + std::to_string(outcome.exitCode) + "로 실패했습니다."
                : detail;
        return error(codeForStderr(message), message);
    }
    if (stdoutText != nullptr) *stdoutText = outcome.stdoutText;
    return std::nullopt;
}

// --- 장치 목록과 주소 ------------------------------------------------------

void Backend::cacheListedDevices(const std::vector<sane::ListedDevice>& devices) {
    for (const auto& device : devices) {
        cachedDeviceTypes_[device.devname] = device.deviceType;
        cachedDeviceIdentities_[device.devname] =
            wire::DeviceIdentity{device.vendor, device.model};
    }
}

void Backend::invalidateAddressCache() {
    cachedAddress_.reset();
    cachedAddressBackend_.reset();
    cachedAddressTarget_.reset();
    cachedAddressIdentity_.reset();
    cachedAddressIsStableSelector_ = false;
    cachedAddressAt_ = process::TimePoint{};
}

void Backend::noteDeviceOpened() {
    // 장치를 한 번 열면 libusb 주소가 바뀔 수 있다. backend 선택자(`genesys`)는
    // 주소와 무관하므로 유지한다.
    if (cachedAddressIsStableSelector_) return;
    invalidateAddressCache();
}

std::optional<std::string> Backend::cachedDeviceType(const std::string& devname) const {
    const auto it = cachedDeviceTypes_.find(devname);
    if (it == cachedDeviceTypes_.end()) return std::nullopt;
    return it->second;
}

std::optional<wire::DeviceIdentity> Backend::cachedDeviceIdentity(
    const std::string& devname) const {
    const auto it = cachedDeviceIdentities_.find(devname);
    if (it == cachedDeviceIdentities_.end()) return std::nullopt;
    return it->second;
}

sane::ValidationResult Backend::listDevices(bool ownedByScanSession,
                                            std::vector<sane::ListedDevice>* out) {
    // 정본 경로는 `-f` 다. 번역된 `-L` 문장을 파싱하지 않는다.
    std::string formatted;
    const sane::ValidationResult formattedError =
        runScanimage({"-f", "%d\t%v\t%m\t%t%n"}, ownedByScanSession, &formatted);
    if (!formattedError) {
        std::vector<sane::ListedDevice> devices = sane::parseFormattedDeviceList(formatted);
        if (!devices.empty()) {
            cacheListedDevices(devices);
            *out = std::move(devices);
            return std::nullopt;
        }
    } else if (formattedError->code == ErrorCode::Cancelled ||
               formattedError->code == ErrorCode::Timeout) {
        // 취소와 시간 초과는 다른 프로세스를 다시 띄우지 않고 즉시 전파한다.
        return formattedError;
    }

    // 구형 scanimage 가 `-f` 를 거부하면 `-L` 로 후퇴한다.
    std::string legacy;
    if (auto legacyError = runScanimage({"-L"}, ownedByScanSession, &legacy)) {
        return legacyError;
    }
    std::vector<sane::ListedDevice> devices = sane::parseDeviceList(legacy);
    cacheListedDevices(devices);
    *out = std::move(devices);
    return std::nullopt;
}

std::optional<std::string> Backend::liveCachedSelector(
    const std::optional<std::string>& targetDevice,
    const std::optional<std::string>& targetBackend,
    const std::optional<wire::DeviceIdentity>& expectedIdentity) const {
    if (!cachedAddress_) return std::nullopt;
    if (cachedAddressBackend_ != targetBackend) return std::nullopt;
    if (cachedAddressTarget_ != targetDevice) return std::nullopt;
    if (cachedAddressIdentity_ != expectedIdentity) return std::nullopt;
    const bool fresh = std::chrono::steady_clock::now() - cachedAddressAt_ < kAddressCacheTTL;
    if (!cachedAddressIsStableSelector_ && !fresh) return std::nullopt;
    return cachedAddress_;
}

sane::ValidationResult Backend::currentDeviceAddress(
    const std::optional<std::string>& targetDevice,
    const std::optional<std::string>& targetBackend,
    const std::optional<wire::DeviceIdentity>& expectedIdentity,
    bool allowSingleBackendSelector,
    bool ownedByScanSession,
    std::string* out) {
    if (const auto cached = liveCachedSelector(targetDevice, targetBackend, expectedIdentity)) {
        *out = *cached;
        return std::nullopt;
    }

    std::vector<sane::ListedDevice> listed;
    if (auto listError = listDevices(ownedByScanSession, &listed)) return listError;

    std::vector<const sane::ListedDevice*> backendMatches;
    if (targetBackend) {
        for (const auto& device : listed) {
            if (sane::backendName(device.devname) == *targetBackend) {
                backendMatches.push_back(&device);
            }
        }
    }
    const sane::ListedDevice* exactMatch = nullptr;
    if (targetDevice) {
        for (const auto& device : listed) {
            if (device.devname == *targetDevice) {
                exactMatch = &device;
                break;
            }
        }
    }
    std::vector<const sane::ListedDevice*> identityMatches;
    if (expectedIdentity) {
        for (const auto* device : backendMatches) {
            if (sameIdentity(*device, *expectedIdentity)) identityMatches.push_back(device);
        }
    }

    const sane::ListedDevice* chosen = nullptr;
    if (exactMatch != nullptr &&
        (!expectedIdentity || sameIdentity(*exactMatch, *expectedIdentity))) {
        chosen = exactMatch;
    } else if (expectedIdentity && identityMatches.size() == 1) {
        chosen = identityMatches.front();
    } else if (!targetBackend && listed.size() == 1) {
        chosen = &listed.front();
    } else if (!expectedIdentity && targetBackend && backendMatches.size() == 1) {
        // 제조사·모델 힌트가 없어도 해당 backend 장치가 정확히 하나뿐이면
        // 모호하지 않다. 이 갈래가 없으면 open 한 번으로 주소가 바뀐 뒤
        // 재연결이 항상 실패했다.
        chosen = backendMatches.front();
    }

    if (chosen != nullptr) {
        std::string resolved = chosen->devname;
        // 주소 독립 선택자는 backend 가 빈 장치명을 지원하고 같은 backend
        // 장치가 정확히 하나일 때만 쓴다. coolscan2/3 은 빈 장치명을 거부한다.
        if (allowSingleBackendSelector && targetBackend &&
            sane::supportsStableBackendSelector(*targetBackend) && backendMatches.size() == 1 &&
            chosen->devname.find(":libusb:") != std::string::npos) {
            resolved = *targetBackend;
        }
        cachedAddress_ = resolved;
        cachedAddressBackend_ = targetBackend;
        cachedAddressTarget_ = targetDevice;
        cachedAddressIdentity_ = expectedIdentity;
        cachedAddressIsStableSelector_ = resolved.find(':') == std::string::npos;
        cachedAddressAt_ = std::chrono::steady_clock::now();
        cachedDeviceTypes_[resolved] = chosen->deviceType;
        cachedDeviceTypes_[chosen->devname] = chosen->deviceType;
        const wire::DeviceIdentity identity{chosen->vendor, chosen->model};
        cachedDeviceIdentities_[resolved] = identity;
        cachedDeviceIdentities_[chosen->devname] = identity;
        *out = std::move(resolved);
        return std::nullopt;
    }

    invalidateAddressCache();
    const std::string backendLabel = targetBackend ? *targetBackend : std::string("SANE");
    if (expectedIdentity && identityMatches.size() > 1) {
        return error(ErrorCode::NotConnected,
                     "같은 제조사·모델의 " + backendLabel +
                         " 장치가 여러 대라 대상 장치를 안전하게 식별할 수 없습니다.");
    }
    if (expectedIdentity && !backendMatches.empty()) {
        return error(ErrorCode::NotConnected,
                     "연결된 " + backendLabel + " 장치가 선택한 " + expectedIdentity->vendor + " " +
                         expectedIdentity->model + "과 일치하지 않습니다.");
    }
    return error(ErrorCode::NotConnected,
                 "SANE 장치 주소가 바뀌었지만 제조사·모델 정보가 없어 안전하게 재연결할 수 "
                 "없습니다. 장치를 다시 검색하십시오.");
}

std::optional<std::string> Backend::reopenSelector(
    const std::string& previous,
    const std::string& targetDevice,
    const std::string& backend,
    const std::optional<wire::DeviceIdentity>& expectedIdentity,
    bool ownedByScanSession) {
    // 주소 없는 backend 선택자는 재열거를 견디므로 재확인할 것이 없다.
    if (previous.find(':') == std::string::npos) return std::nullopt;
    invalidateAddressCache();
    std::string resolved;
    if (currentDeviceAddress(targetDevice, backend, expectedIdentity,
                             /*allowSingleBackendSelector=*/false, ownedByScanSession, &resolved)) {
        return std::nullopt;
    }
    if (resolved == previous) return std::nullopt;
    return resolved;
}

// --- detect ----------------------------------------------------------------

sane::ValidationResult Backend::detect(std::vector<wire::PluginDevice>* out) {
    beginCommand(process::Command::Detect);
    std::vector<sane::ListedDevice> listed;
    // **문구를 여기서 만들지 않는다.** macOS 는 `main.swift` 가
    // `fail("detect 실패: \(error.localizedDescription)")` 로 조립한다.
    // 양쪽에서 접두를 붙이면 코드 이름이 두 번 나온다.
    if (auto listError = listDevices(/*ownedByScanSession=*/false, &listed)) return listError;
    // 호스트가 중복 routed ID 를 "첫 항목만 남기고 plugin defect 로 기록" 한다.
    // 우리가 먼저 정리하면 결과는 같고 결함 기록만 사라진다.
    (void)sane::dedupeByDevname(listed);

    out->clear();
    out->reserve(listed.size());
    for (const auto& device : listed) {
        const std::string backend = sane::backendName(device.devname);
        const std::string vendor = sane::capitalized(device.vendor);
        std::string display = trimmed(vendor + " " + device.model);
        wire::PluginDevice wireDevice;
        wireDevice.id = "sane-" + device.devname;
        wireDevice.displayName = display.empty() ? device.model : display;
        wireDevice.vendor = vendor;
        wireDevice.model = device.model;
        wireDevice.connectionType =
            std::string(sane::connectionTypeRawValue(sane::connectionType(device.devname)));
        // backend 명이나 모델명만으로 실기 검증을 추정하지 않는다.
        wireDevice.verifiedStatus = std::string("compatibleTarget");
        wireDevice.driverVersion = backend + " (SANE)";
        out->push_back(std::move(wireDevice));
    }
    return std::nullopt;
}

// --- 옵션 덤프 -------------------------------------------------------------

sane::ValidationResult Backend::sourceSpecificOptionsDump(
    const std::string& baseDump,
    const std::string& devname,
    const std::string& targetDevice,
    const std::string& backend,
    const std::optional<wire::DeviceIdentity>& expectedIdentity,
    bool ownedByScanSession,
    std::string* outDevname,
    std::string* outDump) {
    const sane::OptionDump base{baseDump};
    if (!sane::capabilityRedumpArguments(base, devname)) {
        *outDevname = devname;
        *outDump = baseDump;
        return std::nullopt;
    }

    std::string currentDevname = devname;
    std::optional<ScannerError> lastError;
    for (int attempt = 0; attempt < 2; ++attempt) {
        if (attempt > 0) {
            const auto reopened = reopenSelector(currentDevname, targetDevice, backend,
                                                 expectedIdentity, ownedByScanSession);
            if (!reopened) break;
            currentDevname = *reopened;
        }
        const auto args = sane::capabilityRedumpArguments(base, currentDevname);
        if (!args) {
            *outDevname = currentDevname;
            *outDump = baseDump;
            return std::nullopt;
        }
        std::string selected;
        auto runError = runScanimage(*args, ownedByScanSession, &selected);
        if (!runError) {
            if (sane::OptionDump{selected}.empty()) {
                return error(ErrorCode::IoFailure,
                             "source/mode 선택 뒤 scanimage -A가 옵션을 반환하지 않았습니다.");
            }
            *outDevname = currentDevname;
            *outDump = std::move(selected);
            return std::nullopt;
        }
        lastError = runError;
        if (attempt != 0 || !process::isStaleDeviceError(runError->message)) return runError;
    }
    if (lastError) return lastError;
    return error(ErrorCode::IoFailure, "source/mode 옵션 조회에 실패했습니다.");
}

sane::ValidationResult Backend::capabilityOptionsDump(
    const std::string& scannerID,
    const std::optional<wire::DeviceIdentity>& expectedIdentity,
    bool ownedByScanSession,
    std::string* devnameOut,
    std::string* dumpOut) {
    const std::string raw = stripSanePrefix(scannerID);
    const std::string backend = sane::backendName(raw);
    std::optional<ScannerError> finalError;

    for (int attempt = 0; attempt < 3; ++attempt) {
        std::string devname;
        if (attempt == 0 && !expectedIdentity) {
            // detect 가 넘긴 전체 SANE 장치명을 먼저 그대로 쓴다. detect 는
            // 목록만 읽고 장치를 열지 않으므로 이 주소는 아직 살아 있다.
            devname = raw;
        } else {
            if (auto addressError = currentDeviceAddress(raw, backend, expectedIdentity,
                                                         /*allowSingleBackendSelector=*/attempt == 2,
                                                         ownedByScanSession, &devname)) {
                finalError = addressError;
                if (attempt >= 2 || !shouldRetryCapabilityRead(*addressError)) return addressError;
                invalidateAddressCache();
                std::this_thread::sleep_for(kRetryDelay);
                continue;
            }
        }

        // 단일 source genesys 필름 스캐너는 추가 open 을 피하면서 주 사용 모드인
        // Color 상태의 덤프를 얻는다.
        std::vector<std::string> baseArgs{"-A", "-d", devname};
        if (backend == "genesys") {
            baseArgs.emplace_back("--mode");
            baseArgs.emplace_back("Color");
        }
        std::string baseDump;
        if (auto dumpError = runScanimage(baseArgs, ownedByScanSession, &baseDump)) {
            finalError = dumpError;
            if (attempt >= 2 || !shouldRetryCapabilityRead(*dumpError)) return dumpError;
            invalidateAddressCache();
            std::this_thread::sleep_for(kRetryDelay);
            continue;
        }
        const sane::OptionDump parsedBase{baseDump};
        if (parsedBase.empty()) {
            const auto emptyError =
                error(ErrorCode::IoFailure, "scanimage -A가 적용 가능한 옵션을 반환하지 않았습니다.");
            finalError = emptyError;
            if (attempt >= 2) return emptyError;
            invalidateAddressCache();
            std::this_thread::sleep_for(kRetryDelay);
            continue;
        }
        if (sane::canReuseSinglePassOptionsDump(parsedBase, backend)) {
            *devnameOut = devname;
            *dumpOut = std::move(baseDump);
            return std::nullopt;
        }

        std::string selectedDevname;
        std::string selectedDump;
        if (auto sourceError =
                sourceSpecificOptionsDump(baseDump, devname, raw, backend, expectedIdentity,
                                          ownedByScanSession, &selectedDevname, &selectedDump)) {
            finalError = sourceError;
            if (attempt >= 2 || !shouldRetryCapabilityRead(*sourceError)) return sourceError;
            invalidateAddressCache();
            std::this_thread::sleep_for(kRetryDelay);
            continue;
        }
        *devnameOut = std::move(selectedDevname);
        *dumpOut = std::move(selectedDump);
        return std::nullopt;
    }

    if (finalError) return finalError;
    return error(ErrorCode::IoFailure, "스캐너 옵션 조회에 실패했습니다.");
}

sane::ValidationResult Backend::scanSpecificOptionsDump(
    const std::string& sourceDump,
    const std::string& devname,
    const std::string& targetDevice,
    const std::string& backend,
    const std::optional<wire::DeviceIdentity>& expectedIdentity,
    const sane::ScanOptions& options,
    std::string* outDevname,
    std::string* outDump) {
    const sane::MediaSelection preliminary =
        sane::resolveMedia(sane::OptionDump{sourceDump}, options, "");

    const auto argumentsFor = [&](const std::string& device) {
        std::vector<std::string> args{"-A", "-d", device};
        if (preliminary.source) {
            args.emplace_back("--source");
            args.push_back(*preliminary.source);
        }
        if (preliminary.mode) {
            args.emplace_back("--mode");
            args.push_back(*preliminary.mode);
        }
        if (preliminary.resolvedDPI) {
            args.emplace_back("--resolution");
            args.push_back(std::to_string(*preliminary.resolvedDPI));
        }
        if (preliminary.depthArgument) {
            args.emplace_back("--depth");
            args.push_back(std::to_string(*preliminary.depthArgument));
        }
        if (options.resolutionDPI <= 0 && preliminary.hasPreviewOption) {
            args.emplace_back("--preview=yes");
        }
        return args;
    };

    std::string currentDevname = devname;
    std::optional<ScannerError> lastError;
    for (int attempt = 0; attempt < 2; ++attempt) {
        if (attempt > 0) {
            const auto identity =
                expectedIdentity ? expectedIdentity : cachedDeviceIdentity(currentDevname);
            const auto reopened = reopenSelector(currentDevname, targetDevice, backend, identity,
                                                 /*ownedByScanSession=*/true);
            if (!reopened) break;
            currentDevname = *reopened;
        }
        std::string dump;
        auto runError = runScanimage(argumentsFor(currentDevname), /*ownedByScanSession=*/true, &dump);
        if (!runError) {
            if (sane::OptionDump{dump}.empty()) {
                return error(ErrorCode::IoFailure,
                             "최종 스캔 옵션 적용 뒤 scanimage -A가 옵션을 반환하지 않았습니다.");
            }
            *outDevname = currentDevname;
            *outDump = std::move(dump);
            return std::nullopt;
        }
        lastError = runError;
        if (attempt != 0 || !process::isStaleDeviceError(runError->message)) return runError;
    }
    if (lastError) return lastError;
    return error(ErrorCode::IoFailure, "최종 스캔 옵션 조회에 실패했습니다.");
}

// --- capabilities ----------------------------------------------------------

sane::ValidationResult Backend::capabilities(
    const std::string& scannerID,
    const std::optional<wire::DeviceIdentity>& expectedIdentity,
    CapabilityReport* out) {
    beginCommand(process::Command::Capabilities);

    const std::string raw = stripSanePrefix(scannerID);
    if (!process::isSafeDeviceName(raw)) {
        return error(ErrorCode::UnsupportedOption, "deviceID가 유효한 SANE 장치명이 아닙니다.");
    }

    std::string devname;
    std::string dump;
    if (auto dumpError = capabilityOptionsDump(scannerID, expectedIdentity,
                                               /*ownedByScanSession=*/false, &devname, &dump)) {
        return dumpError;
    }

    const std::string backend = sane::backendName(raw);
    // 토큰에 제조사·모델을 반드시 싣는다. 이후 스캔은 주소가 바뀌어도 이
    // 정보로 "같은 모델"임을 확인하고 재연결한다.
    std::optional<wire::DeviceIdentity> identity = cachedDeviceIdentity(devname);
    if (!identity) identity = expectedIdentity;
    if (!identity) {
        std::vector<sane::ListedDevice> listed;
        if (!listDevices(/*ownedByScanSession=*/false, &listed)) {
            for (const auto& device : listed) {
                if (device.devname == devname) {
                    identity = wire::DeviceIdentity{device.vendor, device.model};
                    break;
                }
            }
            if (!identity) {
                std::vector<const sane::ListedDevice*> backendMatches;
                for (const auto& device : listed) {
                    if (sane::backendName(device.devname) == backend) backendMatches.push_back(&device);
                }
                if (backendMatches.size() == 1) {
                    identity = wire::DeviceIdentity{backendMatches.front()->vendor,
                                                    backendMatches.front()->model};
                }
            }
        }
    }

    const sane::OptionDump options{dump};
    const std::string deviceType = cachedDeviceType(devname).value_or("");

    wire::CapabilitySnapshot snapshot;
    snapshot.deviceID = scannerID;
    snapshot.backend = backend;
    snapshot.acquisitionDevice = devname;
    snapshot.deviceIdentity = identity;
    if (!deviceType.empty()) snapshot.deviceType = deviceType;
    snapshot.optionDump = dump;
    if (const auto mode = sane::validatedColorMode(options, backend, deviceType)) {
        snapshot.validatedMode = std::string(sane::colorModeRawValue(*mode));
    }

    const auto token = wire::encodeCapabilityToken(snapshot);
    if (!token) return error(ErrorCode::IoFailure, "capability 스냅샷 인코딩 실패");

    out->capabilities = sane::parseCapabilities(options, deviceType, backend);
    out->capabilityToken = *token;
    return std::nullopt;
}

// --- 미디어 해석 -----------------------------------------------------------

sane::ValidationResult Backend::resolveValidatedMedia(
    const sane::ScanOptions& options,
    const std::optional<std::string>& capabilityToken,
    ResolvedMedia* out) {
    const std::string raw = stripSanePrefix(options.scannerID);
    if (!process::isSafeDeviceName(raw)) {
        return error(ErrorCode::UnsupportedOption, "deviceID가 유효한 SANE 장치명이 아닙니다.");
    }
    const std::string backend = sane::backendName(raw);

    std::string devname;
    std::string dump;
    std::string deviceTypeHint;
    std::optional<wire::DeviceIdentity> identity;

    if (capabilityToken) {
        const auto snapshot = wire::decodeCapabilityToken(*capabilityToken);
        if (!snapshot) {
            return error(ErrorCode::UnsupportedOption,
                         "capabilityToken을 해석할 수 없습니다. 장치 능력을 다시 조회하십시오.");
        }
        if (snapshot->deviceID != options.scannerID || snapshot->backend != backend ||
            snapshot->acquisitionDevice.empty() ||
            sane::OptionDump{snapshot->optionDump}.empty()) {
            return error(ErrorCode::UnsupportedOption,
                         "capabilityToken이 현재 장치와 일치하지 않습니다. 장치 능력을 다시 "
                         "조회하십시오.");
        }
        // 토큰의 `acquisitionDevice` 는 호스트를 거쳐 돌아온 값이라 그대로
        // `-d` 인자가 된다. **여기서 막지 않으면 인자 주입 경로가 된다**
        // (child-process §4.3). macOS 에는 이 검사가 없다 — `Process.arguments`
        // 가 배열이라 구조적으로 불가능하기 때문이다.
        if (!process::isSafeDeviceName(snapshot->acquisitionDevice)) {
            return error(ErrorCode::UnsupportedOption, "capabilityToken이 손상되었습니다.");
        }

        const std::string requestedMode = std::string(sane::colorModeRawValue(options.colorMode));
        if (snapshot->validatedMode && *snapshot->validatedMode == requestedMode) {
            devname = snapshot->acquisitionDevice;
            dump = snapshot->optionDump;
        } else {
            // Color 에서 읽은 depth/geometry 활성 상태를 Gray 요청에 재사용하지
            // 않는다. 실제로 다른 모드를 요청할 때만 그 모드를 적용한 -A 를 읽는다.
            if (auto dumpError = scanSpecificOptionsDump(
                    snapshot->optionDump, snapshot->acquisitionDevice, raw, snapshot->backend,
                    snapshot->deviceIdentity, options, &devname, &dump)) {
                return dumpError;
            }
        }
        deviceTypeHint = snapshot->deviceType.value_or("");
        identity = snapshot->deviceIdentity;
    } else {
        std::string sourceDevname;
        std::string sourceDump;
        if (auto dumpError = capabilityOptionsDump(options.scannerID, std::nullopt,
                                                   /*ownedByScanSession=*/true, &sourceDevname,
                                                   &sourceDump)) {
            return dumpError;
        }
        if (sane::canReuseSinglePassOptionsDump(sane::OptionDump{sourceDump},
                                                sane::backendName(sourceDevname))) {
            devname = sourceDevname;
            dump = sourceDump;
        } else {
            if (auto dumpError = scanSpecificOptionsDump(sourceDump, sourceDevname, raw, backend,
                                                         cachedDeviceIdentity(sourceDevname),
                                                         options, &devname, &dump)) {
                return dumpError;
            }
        }
        deviceTypeHint = cachedDeviceType(sourceDevname).value_or("");
        identity = cachedDeviceIdentity(devname);
        if (!identity) identity = cachedDeviceIdentity(sourceDevname);
    }

    const sane::OptionDump parsed{dump};
    if (parsed.empty()) {
        return error(ErrorCode::IoFailure, "scanimage -A가 적용 가능한 옵션을 반환하지 않았습니다.");
    }

    out->media = sane::resolveMedia(parsed, options, deviceTypeHint);
    out->acquisitionDevice = devname;
    out->expectedIdentity = identity;

    if (auto validation = sane::validateExactOptions(options, out->media)) return validation;
    return std::nullopt;
}

// --- 획득 ------------------------------------------------------------------

sane::ValidationResult Backend::resolveDeviceAddress(const sane::ScanOptions& options,
                                                     const ResolvedMedia& resolved,
                                                     bool forceRefresh,
                                                     std::string* out) {
    const std::string raw = stripSanePrefix(options.scannerID);
    const std::string backend = sane::backendName(raw);

    if (!forceRefresh) {
        // 이 세션에서 이미 열어본 선택자를 최우선으로 재사용한다. 토큰에 적힌
        // 주소는 그 토큰을 만들 때의 open 으로 이미 만료됐을 수 있다.
        if (const auto live = liveCachedSelector(raw, backend, resolved.expectedIdentity)) {
            *out = *live;
            return std::nullopt;
        }
        if (resolved.acquisitionDevice &&
            !sane::isVolatileUSBSelector(*resolved.acquisitionDevice)) {
            *out = *resolved.acquisitionDevice;
            return std::nullopt;
        }
    }

    std::optional<ScannerError> lastError;
    for (int attempt = 0; attempt < 3; ++attempt) {
        std::string address;
        auto addressError = currentDeviceAddress(raw, backend, resolved.expectedIdentity,
                                                 /*allowSingleBackendSelector=*/true,
                                                 /*ownedByScanSession=*/true, &address);
        if (!addressError) {
            *out = std::move(address);
            return std::nullopt;
        }
        if (!isRetryableAddressError(*addressError)) return addressError;
        lastError = addressError;
        if (attempt < 2) std::this_thread::sleep_for(kRetryDelay);
    }
    if (lastError) return lastError;
    return error(ErrorCode::NotConnected, "scanimage 장치 목록에서 장치를 찾지 못함");
}

sane::ValidationResult Backend::runSingleAcquisition(const sane::ScanOptions& options,
                                                     const ResolvedMedia& resolved,
                                                     sane::AcquisitionPass pass,
                                                     const std::filesystem::path& outputPath,
                                                     std::optional<int> brightnessOverride,
                                                     double staleRetryProgress,
                                                     double progressLow,
                                                     double progressHigh,
                                                     const ProgressCallback& progress) {
    const std::string raw = stripSanePrefix(options.scannerID);
    const std::string backend = sane::backendName(raw);
    const int attempts = process::attemptCount(backend);
    const std::string phase =
        pass == sane::AcquisitionPass::Infrared ? "scanningIR" : "scanningRGB";
    std::string lastStderr;

    for (int attempt = 0; attempt < attempts; ++attempt) {
        if (attempt > 0) invalidateAddressCache();

        std::string devname;
        if (auto addressError = resolveDeviceAddress(options, resolved, attempt > 0, &devname)) {
            removeQuietly(outputPath);
            return addressError;
        }
        if (!process::isSafeDeviceName(devname)) {
            removeQuietly(outputPath);
            return error(ErrorCode::UnsupportedOption, "capabilityToken이 손상되었습니다.");
        }

        const std::vector<std::string> args =
            sane::makeScanimageArgs(devname, options, resolved.media, pass, brightnessOverride);

        refreshEnvironment();
        process::ProgressTracker tracker;
        const auto onProgress = [&](double fraction) {
            if (!progress) return;
            ProgressEvent event;
            event.phase = phase;
            event.fraction = mapProgress(progressLow, progressHigh, fraction);
            event.message = "Scanning";
            progress(event);
        };

        const process::AcquisitionRun run = process::runAcquisition(
            location_.path, args, environmentBlock_, outputPath,
            process::kPerCallCeiling, process::kPerCallCeiling,
            sane::usesAutomaticAcquisitionWatchdog(backend), tracker, onProgress, ownership_);

        // 스캔은 언제나 장치를 연다 → 종료 시 libusb 주소가 바뀐 것으로 본다.
        noteDeviceOpened();

        if (run.status != process::LaunchStatus::Ok) {
            removeQuietly(outputPath);
            switch (run.status) {
                case process::LaunchStatus::Busy:
                    return error(ErrorCode::Busy,
                                 "소유한 scanimage process slot을 사용할 수 없습니다.");
                case process::LaunchStatus::Cancelled:
                    return error(ErrorCode::Cancelled, "스캔이 취소되었습니다.");
                case process::LaunchStatus::LaunchFailed:
                    return error(ErrorCode::IoFailure, run.launchError);
                case process::LaunchStatus::Ok:
                    break;
            }
        }

        process::AcquisitionOutcome outcome;
        outcome.exitCode = run.exitCode;
        outcome.madeProgress = run.madeProgress;
        outcome.stderrText = tracker.takeStderr();
        outcome.timeoutKind = run.timeoutKind;
        outcome.cancelled = run.cancelled;
        lastStderr_ = outcome.stderrText;
        lastStderr = outcome.stderrText;

        switch (process::decideRetry(backend, attempt, attempts, outcome)) {
            case process::RetryDecision::Succeed:
                return std::nullopt;
            case process::RetryDecision::Retry:
                removeQuietly(outputPath);
                if (progress) {
                    ProgressEvent event;
                    event.phase = "warmingLamp";
                    event.fraction = staleRetryProgress;
                    event.message = "Re-detecting scanner";
                    progress(event);
                }
                continue;
            case process::RetryDecision::Fail:
                break;
        }

        removeQuietly(outputPath);
        if (outcome.cancelled) return error(ErrorCode::Cancelled, "스캔이 취소되었습니다.");
        if (outcome.exitCode == 0 && process::containsInexactOptionWarning(outcome.stderrText)) {
            return error(ErrorCode::UnsupportedOption,
                         "SANE가 요청 옵션을 다른 값으로 반올림했습니다: " + outcome.stderrText);
        }
        if (outcome.timeoutKind == process::TimeoutKind::FirstProgress) {
            return error(ErrorCode::Timeout,
                         "scanimage가 " + std::to_string(process::kPerCallCeiling.count() / 1000) +
                             "초 안에 첫 이미지 데이터를 반환하지 않았습니다.");
        }
        if (outcome.timeoutKind == process::TimeoutKind::Stalled) {
            return error(ErrorCode::Timeout,
                         "scanimage 진행률이 " +
                             std::to_string(process::kPerCallCeiling.count() / 1000) +
                             "초 동안 갱신되지 않았습니다.");
        }
        return error(ErrorCode::IoFailure,
                     process::acquisitionFailureDetail(outcome.exitCode, outcome.stderrText));
    }

    removeQuietly(outputPath);
    return error(ErrorCode::IoFailure, process::retriesExhaustedDetail(lastStderr));
}

void Backend::acquireInfraredPass(const sane::ScanOptions& options,
                                  const ResolvedMedia& resolved,
                                  const std::filesystem::path& mainOutputPath,
                                  const ProgressCallback& progress,
                                  std::optional<std::filesystem::path>* outPath,
                                  std::vector<std::string>* warnings) {
    const std::filesystem::path irPath = infraredPath(mainOutputPath);
    if (progress) {
        ProgressEvent event;
        event.phase = "scanningIR";
        event.fraction = 0.86;
        event.message = "Scanning infrared";
        progress(event);
    }
    // **IR 실패는 본 스캔을 무효화하지 않는다**(I-10). 경고로 보고한다.
    if (auto irError = runSingleAcquisition(options, resolved, sane::AcquisitionPass::Infrared,
                                            irPath, std::nullopt, 0.86, 0.80, 0.96, progress)) {
        removeQuietly(irPath);
        warnings->push_back("Infrared pass failed: " + irError->description());
        return;
    }
    const auto [width, height] = imaging::tiffio::imageSize(irPath);
    if (width <= 0 || height <= 0) {
        removeQuietly(irPath);
        warnings->push_back("Infrared pass produced an unreadable image; IR channel dropped.");
        return;
    }
    *outPath = irPath;
}

sane::ValidationResult Backend::validateScanArtifacts(
    const sane::ScanOptions& options,
    const ResolvedMedia& resolved,
    const std::filesystem::path& outputPath,
    const std::optional<std::filesystem::path>& infraredFile,
    std::vector<std::string> warnings,
    ScanOutcome* out) {
    const auto fail = [&](std::string message) {
        removeQuietly(outputPath);
        if (infraredFile) removeQuietly(*infraredFile);
        return error(ErrorCode::IoFailure, std::move(message));
    };

    imaging::tiffio::ScannedTiffMetadata metadata;
    if (auto message = imaging::tiffio::validatedScannedTIFF(outputPath, options.bitDepth,
                                                             options.colorMode, &metadata)) {
        return fail(*message);
    }
    if (options.infraredEnabled) {
        if (!infraredFile) return fail("요청한 별도 IR 채널 결과가 없습니다.");
        imaging::tiffio::ScannedTiffMetadata infrared;
        if (auto message = imaging::tiffio::validatedScannedTIFF(
                *infraredFile, options.bitDepth, sane::ColorMode::Gray, &infrared)) {
            return fail(*message);
        }
        if (infrared.width != metadata.width || infrared.height != metadata.height) {
            return fail("RGB/IR TIFF 픽셀 크기가 일치하지 않습니다.");
        }
    } else if (infraredFile) {
        return fail("요청하지 않은 IR 채널 결과가 생성됐습니다.");
    }

    out->outputPath = outputPath;
    out->width = metadata.width;
    out->height = metadata.height;
    out->bitDepth = metadata.bitDepth;
    out->colorMode = metadata.colorMode;
    out->hasInfrared = infraredFile.has_value();
    out->infraredPath = infraredFile;
    out->warnings = std::move(warnings);
    out->appliedScanArea = sane::ScanArea{
        resolved.media.originXMM.value_or(options.scanArea.originXMM),
        resolved.media.originYMM.value_or(options.scanArea.originYMM),
        resolved.media.widthMM.value_or(options.scanArea.widthMM),
        resolved.media.heightMM.value_or(options.scanArea.heightMM),
    };
    return std::nullopt;
}

sane::ValidationResult Backend::singlePassScan(const sane::ScanOptions& options,
                                               const ResolvedMedia& resolved,
                                               const std::filesystem::path& outputPath,
                                               const ProgressCallback& progress,
                                               ScanOutcome* out) {
    std::vector<std::string> warnings = location_.warnings;
    std::optional<std::filesystem::path> infraredFile;

    const bool separateIR =
        resolved.media.irStrategy.usesInfrared() && resolved.media.irStrategy.needsSeparatePass();
    if (auto scanError = runSingleAcquisition(options, resolved, sane::AcquisitionPass::Main,
                                              outputPath, std::nullopt, 0.05, 0.08,
                                              separateIR ? 0.78 : 0.92, progress)) {
        return scanError;
    }
    if (separateIR) {
        acquireInfraredPass(options, resolved, outputPath, progress, &infraredFile, &warnings);
    }
    if (resolved.media.irStrategy.kind == sane::IRStrategy::Kind::CleanImage) {
        warnings.push_back(
            "IR dust removal applied inside the SANE backend (--clean-image); no separate IR "
            "channel file.");
    }
    return validateScanArtifacts(options, resolved, outputPath, infraredFile, std::move(warnings),
                                 out);
}

sane::ValidationResult Backend::multiPassScan(const sane::ScanOptions& options,
                                              const ResolvedMedia& resolved,
                                              const std::filesystem::path& outputPath,
                                              const ProgressCallback& progress,
                                              ScanOutcome* out) {
    const std::vector<int> plan = hardwareExposurePlan();
    const int passCount = static_cast<int>(plan.size());
    std::vector<std::filesystem::path> samples;
    samples.reserve(plan.size());
    for (int index = 0; index < passCount; ++index) {
        samples.push_back(multipassSamplePath(outputPath, index));
    }
    const bool keepSamples = keepMultipassArtifacts();
    struct SampleCleanup {
        const std::vector<std::filesystem::path>* files;
        bool keep;
        ~SampleCleanup() {
            if (keep) return;
            for (const auto& file : *files) removeQuietly(file);
        }
    } cleanup{&samples, keepSamples};

    for (int index = 0; index < passCount; ++index) {
        const double base = 0.08 + index * (0.70 / passCount);
        sane::ScanOptions passOptions = options;
        passOptions.hardwareExposureTime = plan[static_cast<std::size_t>(index)];
        if (progress) {
            ProgressEvent event;
            event.phase = "scanningRGB";
            event.fraction = base;
            event.message = "Exposure bracket " + std::to_string(index + 1) + "/" +
                            std::to_string(passCount) + " @ " +
                            std::to_string(plan[static_cast<std::size_t>(index)]);
            progress(event);
        }
        if (auto passError = runSingleAcquisition(
                passOptions, resolved, sane::AcquisitionPass::Main,
                samples[static_cast<std::size_t>(index)], std::nullopt, base, base,
                base + 0.70 / passCount, progress)) {
            return passError;
        }
    }

    if (progress) {
        ProgressEvent event;
        event.phase = "processingNegative";
        event.fraction = 0.82;
        event.message = "Merging exposure brackets";
        progress(event);
    }

    // 병합은 **비트 동일 대상이다**(D-11). 픽셀을 직접 다루는 것은
    // imaging_logic 이고 여기서는 로드와 저장만 한다.
    std::vector<imaging::FloatBitmap> loaded;
    loaded.reserve(samples.size());
    int width = 0;
    int height = 0;
    for (const auto& sample : samples) {
        auto bitmap = imaging::tiffio::loadScannerTIFF(sample);
        if (!bitmap) {
            return error(ErrorCode::IoFailure,
                         "multi-sample merge failed: " +
                             std::string(imaging::failureMessage(
                                 imaging::Failure::MultiSampleLoadFailed)));
        }
        if (width == 0) {
            width = bitmap->width;
            height = bitmap->height;
        } else if (bitmap->width != width || bitmap->height != height) {
            return error(ErrorCode::IoFailure,
                         "multi-sample merge failed: " +
                             std::string(imaging::failureMessage(
                                 imaging::Failure::ExposureInputMismatch)));
        }
        loaded.push_back(std::move(*bitmap));
    }

    imaging::ImageList images;
    images.reserve(loaded.size());
    for (const auto& bitmap : loaded) images.emplace_back(bitmap.pixels);

    const imaging::Bitmap16Outcome merged =
        imaging::mergeHardwareExposureBitmap(images, plan, width, height);
    if (merged.failure) {
        return error(ErrorCode::IoFailure, "multi-sample merge failed: " +
                                               std::string(imaging::failureMessage(*merged.failure)));
    }
    loaded.clear();
    if (!imaging::tiffio::writeRGB16TIFF(merged.bitmap.pixels, merged.bitmap.width,
                                         merged.bitmap.height, outputPath)) {
        return error(ErrorCode::IoFailure, "multi-sample merge failed: 병합 결과를 저장하지 "
                                           "못했습니다.");
    }

    std::vector<std::string> warnings = location_.warnings;
    warnings.push_back(
        "Hardware scan-exposure-time bracket used with " +
        std::to_string(hardwareExposureSamplesPerStop()) +
        " sample(s) per exposure; same-exposure samples reduce random/color noise before "
        "clipped/low-signal regions are filled from alternate exposures.");
    if (keepSamples) {
        std::string paths;
        for (std::size_t i = 0; i < samples.size(); ++i) {
            if (i != 0) paths += ", ";
            paths += samples[i].string();
        }
        warnings.push_back("Multi-pass intermediate TIFFs kept: " + paths);
    }

    std::optional<std::filesystem::path> infraredFile;
    if (resolved.media.irStrategy.usesInfrared()) {
        if (resolved.media.irStrategy.needsSeparatePass()) {
            acquireInfraredPass(options, resolved, outputPath, progress, &infraredFile, &warnings);
        } else {
            warnings.push_back(
                "Infrared skipped: this device's IR method cannot be combined with multi-exposure "
                "passes.");
        }
    }

    return validateScanArtifacts(options, resolved, outputPath, infraredFile, std::move(warnings),
                                 out);
}

sane::ValidationResult Backend::scan(const sane::ScanOptions& options,
                                     const std::optional<std::string>& capabilityToken,
                                     const std::filesystem::path& outputPath,
                                     const ProgressCallback& progress,
                                     ScanOutcome* out) {
    beginCommand(process::Command::Scan);

    std::uint64_t sessionID = 0;
    switch (ownership_.beginScanSession(&sessionID, options.scannerID)) {
        case process::ProcessOwnership::SessionError::None:
            break;
        case process::ProcessOwnership::SessionError::Busy:
            // 이 프로세스 안일 수도, 같은 스캐너를 쥔 다른 어댑터일 수도 있다.
            // `usbscan.sys` 가 배타 접근을 강제하지 않아 우리가 막는다.
            return error(ErrorCode::Busy, "이 스캐너를 이미 다른 스캔이 쓰고 있습니다.");
        case process::ProcessOwnership::SessionError::Cancelled:
            return error(ErrorCode::Cancelled, "스캔이 취소되었습니다.");
    }
    struct SessionGuard {
        process::ProcessOwnership& ownership;
        std::uint64_t id;
        ~SessionGuard() { ownership.endScanSession(id); }
    } guard{ownership_, sessionID};

    ResolvedMedia resolved;
    if (auto mediaError = resolveValidatedMedia(options, capabilityToken, &resolved)) {
        return mediaError;
    }
    if (progress) {
        ProgressEvent event;
        event.phase = "warmingLamp";
        event.fraction = 0.02;
        event.message = "Warming lamp";
        progress(event);
    }

    const bool multiPass = options.multiExposureEnabled && options.resolutionDPI > 0;
    auto scanError = multiPass ? multiPassScan(options, resolved, outputPath, progress, out)
                               : singlePassScan(options, resolved, outputPath, progress, out);
    if (scanError) return scanError;

    if (progress) {
        ProgressEvent event;
        event.phase = "complete";
        event.fraction = 1.0;
        event.message = multiPass ? "Multi-Exposure scan complete" : "Scan complete";
        progress(event);
    }
    return std::nullopt;
}

}  // namespace negaflow::app
