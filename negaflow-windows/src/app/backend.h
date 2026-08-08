// negaflow-scanner-sane — Windows adapter
// app/backend — `scanimage` 를 지휘한다. **비순수 계층이다.**
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend.swift
//            Sources/SANEPluginCore/SANEBackend+Discovery.swift
//            Sources/SANEPluginCore/SANEBackend+ScanExecution.swift
// 정본 문서: docs/02-frontend-contract/*
//            docs/03-process-and-io/*
//
// ## 여기에는 판정이 거의 없다
//
// 파싱·능력 판정·미디어 해석·검증·인자 조립은 전부 `sane_logic` 과
// `process_logic` 이 갖고 있고 파리티로 대조된다. 이 파일이 하는 것은
// **순서와 재시도**다 — 언제 목록을 다시 읽고, 언제 주소를 버리고,
// 몇 번까지 다시 여는가.
//
// 새 판정을 여기에 쓰지 않는다. 쓰게 되면 그것은 검증되지 않은 분기다.
//
// ## 주소는 열 때마다 바뀐다
//
// 실측(Plustek OpticFilm 8100 + sane-backends 1.4.0): 장치를 **열 때마다**
// libusb 주소가 바뀐다. 목록 조회(-L/-f)만으로는 바뀌지 않는다. 그래서
// "목록은 싸고 안전하고, open 은 방금 얻은 주소를 태운다"로 다룬다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <filesystem>
#include <functional>
#include <map>
#include <optional>
#include <string>
#include <vector>

#include "app/environment.h"
#include "process/budget.h"
#include "process/cancel.h"
#include "sane/args.h"
#include "sane/capabilities.h"
#include "sane/device_list.h"
#include "sane/media.h"
#include "sane/validate.h"
#include "wire/protocol.h"
#include "wire/snapshot.h"

namespace negaflow::app {

/// 진행률 한 건. `wire/event` 의 progress 이벤트로 그대로 나간다.
struct ProgressEvent {
    std::string phase;
    double fraction = 0.0;
    std::string message;
};

using ProgressCallback = std::function<void(const ProgressEvent&)>;

/// 스캔 결과. `wire/event` 의 result 이벤트를 만드는 재료다.
struct ScanOutcome {
    std::filesystem::path outputPath;
    int width = 0;
    int height = 0;
    sane::BitDepth bitDepth = sane::BitDepth::Sixteen;
    sane::ColorMode colorMode = sane::ColorMode::Color;
    bool hasInfrared = false;
    std::optional<std::filesystem::path> infraredPath;
    std::vector<std::string> warnings;
    sane::ScanArea appliedScanArea{};
};

/// capability 조회 결과.
struct CapabilityReport {
    sane::ScannerCapabilities capabilities;
    std::string capabilityToken;
};

/// 한 요청을 처리하는 동안만 산다. **재사용하지 않는다.**
class Backend {
public:
    Backend(ScanimageLocation location, process::ProcessOwnership& ownership);

    /// 실행 파일을 찾지 못했으면 그 이유. 모든 명령이 이것을 먼저 본다.
    [[nodiscard]] const ScanimageLocation& location() const noexcept { return location_; }

    /// 탐색 과정에서 붙은 경고. result 이벤트의 `warnings` 에 실린다.
    [[nodiscard]] const std::vector<std::string>& startupWarnings() const noexcept {
        return location_.warnings;
    }

    [[nodiscard]] sane::ValidationResult detect(std::vector<wire::PluginDevice>* out);

    [[nodiscard]] sane::ValidationResult capabilities(
        const std::string& scannerID,
        const std::optional<wire::DeviceIdentity>& expectedIdentity,
        CapabilityReport* out);

    /// 본 스캔. `preview` 는 `resolutionDPI == 0` 으로 표현된다(요청 계약).
    [[nodiscard]] sane::ValidationResult scan(const sane::ScanOptions& options,
                                              const std::optional<std::string>& capabilityToken,
                                              const std::filesystem::path& outputPath,
                                              const ProgressCallback& progress,
                                              ScanOutcome* out);

private:
    struct ProcessOutput {
        std::string stdoutText;
    };

    // --- scanimage 실행 -----------------------------------------------------

    [[nodiscard]] sane::ValidationResult runScanimage(const std::vector<std::string>& args,
                                                      bool ownedByScanSession,
                                                      std::string* stdoutText);

    // --- 장치 목록과 주소 ---------------------------------------------------

    [[nodiscard]] sane::ValidationResult listDevices(bool ownedByScanSession,
                                                     std::vector<sane::ListedDevice>* out);

    [[nodiscard]] sane::ValidationResult currentDeviceAddress(
        const std::optional<std::string>& targetDevice,
        const std::optional<std::string>& targetBackend,
        const std::optional<wire::DeviceIdentity>& expectedIdentity,
        bool allowSingleBackendSelector,
        bool ownedByScanSession,
        std::string* out);

    [[nodiscard]] std::optional<std::string> liveCachedSelector(
        const std::optional<std::string>& targetDevice,
        const std::optional<std::string>& targetBackend,
        const std::optional<wire::DeviceIdentity>& expectedIdentity) const;

    void cacheListedDevices(const std::vector<sane::ListedDevice>& devices);
    void invalidateAddressCache();
    void noteDeviceOpened();

    [[nodiscard]] std::optional<std::string> cachedDeviceType(const std::string& devname) const;
    [[nodiscard]] std::optional<wire::DeviceIdentity> cachedDeviceIdentity(
        const std::string& devname) const;

    // --- 옵션 덤프 ----------------------------------------------------------

    [[nodiscard]] sane::ValidationResult capabilityOptionsDump(
        const std::string& scannerID,
        const std::optional<wire::DeviceIdentity>& expectedIdentity,
        bool ownedByScanSession,
        std::string* devname,
        std::string* dump);

    [[nodiscard]] sane::ValidationResult sourceSpecificOptionsDump(
        const std::string& baseDump,
        const std::string& devname,
        const std::string& targetDevice,
        const std::string& backend,
        const std::optional<wire::DeviceIdentity>& expectedIdentity,
        bool ownedByScanSession,
        std::string* outDevname,
        std::string* outDump);

    [[nodiscard]] sane::ValidationResult scanSpecificOptionsDump(
        const std::string& sourceDump,
        const std::string& devname,
        const std::string& targetDevice,
        const std::string& backend,
        const std::optional<wire::DeviceIdentity>& expectedIdentity,
        const sane::ScanOptions& options,
        std::string* outDevname,
        std::string* outDump);

    [[nodiscard]] std::optional<std::string> reopenSelector(
        const std::string& previous,
        const std::string& targetDevice,
        const std::string& backend,
        const std::optional<wire::DeviceIdentity>& expectedIdentity,
        bool ownedByScanSession);

    // --- 스캔 ---------------------------------------------------------------

    struct ResolvedMedia {
        sane::MediaSelection media;
        std::optional<std::string> acquisitionDevice;
        std::optional<wire::DeviceIdentity> expectedIdentity;
    };

    [[nodiscard]] sane::ValidationResult resolveValidatedMedia(
        const sane::ScanOptions& options,
        const std::optional<std::string>& capabilityToken,
        ResolvedMedia* out);

    [[nodiscard]] sane::ValidationResult runSingleAcquisition(
        const sane::ScanOptions& options,
        const ResolvedMedia& resolved,
        sane::AcquisitionPass pass,
        const std::filesystem::path& outputPath,
        std::optional<int> brightnessOverride,
        double staleRetryProgress,
        double progressLow,
        double progressHigh,
        const ProgressCallback& progress);

    [[nodiscard]] sane::ValidationResult resolveDeviceAddress(const sane::ScanOptions& options,
                                                              const ResolvedMedia& resolved,
                                                              bool forceRefresh,
                                                              std::string* out);

    [[nodiscard]] sane::ValidationResult singlePassScan(const sane::ScanOptions& options,
                                                        const ResolvedMedia& resolved,
                                                        const std::filesystem::path& outputPath,
                                                        const ProgressCallback& progress,
                                                        ScanOutcome* out);

    [[nodiscard]] sane::ValidationResult multiPassScan(const sane::ScanOptions& options,
                                                       const ResolvedMedia& resolved,
                                                       const std::filesystem::path& outputPath,
                                                       const ProgressCallback& progress,
                                                       ScanOutcome* out);

    void acquireInfraredPass(const sane::ScanOptions& options,
                             const ResolvedMedia& resolved,
                             const std::filesystem::path& mainOutputPath,
                             const ProgressCallback& progress,
                             std::optional<std::filesystem::path>* outPath,
                             std::vector<std::string>* warnings);

    [[nodiscard]] sane::ValidationResult validateScanArtifacts(
        const sane::ScanOptions& options,
        const ResolvedMedia& resolved,
        const std::filesystem::path& outputPath,
        const std::optional<std::filesystem::path>& infraredFile,
        std::vector<std::string> warnings,
        ScanOutcome* out);

    // --- 상태 ---------------------------------------------------------------

    ScanimageLocation location_;
    process::ProcessOwnership& ownership_;
    std::wstring environmentBlock_;

    process::Command command_ = process::Command::Other;
    process::TimePoint commandStart_{};

    std::optional<std::string> cachedAddress_;
    std::optional<std::string> cachedAddressBackend_;
    std::optional<std::string> cachedAddressTarget_;
    std::optional<wire::DeviceIdentity> cachedAddressIdentity_;
    bool cachedAddressIsStableSelector_ = false;
    process::TimePoint cachedAddressAt_{};

    std::map<std::string, std::string> cachedDeviceTypes_;
    std::map<std::string, wire::DeviceIdentity> cachedDeviceIdentities_;

    /// 마지막 실행의 stderr. 오류 문구를 만들 때 쓴다.
    std::string lastStderr_;

    /// 이 명령의 예산을 시작한다. `detect`/`capabilities`/`scan` 이 각각 부른다.
    void beginCommand(process::Command command);
    /// 다음 호출에 걸 타임아웃. nullopt 이면 **호출하지 않는다**(D-32).
    [[nodiscard]] std::optional<process::Duration> nextCallTimeout() const;
    /// 환경 블록을 현재 캐시 상태로 다시 만든다.
    void refreshEnvironment();
};

}  // namespace negaflow::app
