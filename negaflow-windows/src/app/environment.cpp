// SPDX-License-Identifier: GPL-2.0-or-later

#include "app/environment.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <system_error>

#include "process/child.h"
#include "sane/capabilities.h"

namespace negaflow::app {

namespace {

[[nodiscard]] std::wstring widen(std::string_view utf8) {
    if (utf8.empty()) return {};
    const int needed = MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                                           nullptr, 0);
    if (needed <= 0) return {};
    std::wstring out(static_cast<std::size_t>(needed), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), out.data(), needed);
    return out;
}

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

[[nodiscard]] std::optional<std::wstring> environmentValueW(const wchar_t* name) {
    DWORD needed = GetEnvironmentVariableW(name, nullptr, 0);
    if (needed == 0) return std::nullopt;
    std::wstring value(needed, L'\0');
    const DWORD written = GetEnvironmentVariableW(name, value.data(), needed);
    if (written == 0 || written >= needed) return std::nullopt;
    value.resize(written);
    return value;
}

/// 우리 실행 파일이 있는 디렉터리.
[[nodiscard]] std::filesystem::path pluginDirectory() {
    std::wstring buffer(MAX_PATH, L'\0');
    for (;;) {
        const DWORD written =
            GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
        if (written == 0) return {};
        if (written < buffer.size()) {
            buffer.resize(written);
            break;
        }
        buffer.resize(buffer.size() * 2);
    }
    return std::filesystem::path{buffer}.parent_path();
}

/// PE 헤더의 machine type. 읽지 못하면 nullopt.
[[nodiscard]] std::optional<std::uint16_t> peMachineType(const std::filesystem::path& path) {
    std::FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"rb") != 0 || file == nullptr) return std::nullopt;
    struct Closer {
        std::FILE* f;
        ~Closer() { std::fclose(f); }
    } closer{file};

    unsigned char dos[64]{};
    if (std::fread(dos, 1, sizeof(dos), file) != sizeof(dos)) return std::nullopt;
    if (dos[0] != 'M' || dos[1] != 'Z') return std::nullopt;
    const long headerOffset = static_cast<long>(dos[60]) | (static_cast<long>(dos[61]) << 8) |
                              (static_cast<long>(dos[62]) << 16) |
                              (static_cast<long>(dos[63]) << 24);
    if (headerOffset < 64 || std::fseek(file, headerOffset, SEEK_SET) != 0) return std::nullopt;
    unsigned char header[6]{};
    if (std::fread(header, 1, sizeof(header), file) != sizeof(header)) return std::nullopt;
    if (header[0] != 'P' || header[1] != 'E' || header[2] != 0 || header[3] != 0) {
        return std::nullopt;
    }
    return static_cast<std::uint16_t>(header[4] | (header[5] << 8));
}

/// `isExecutableFile` 의 Windows 대응(§3.1).
///
/// 실행 권한 비트가 없으므로 **파일이 무엇인지**를 본다: 일반 파일이고,
/// reparse point 가 아니고, `.exe` 이고, PE machine type 이 우리와 맞는가.
[[nodiscard]] bool isUsableScanimage(const std::filesystem::path& path,
                                     std::vector<std::string>& warnings,
                                     std::string& reason) {
    std::error_code ec;
    if (!std::filesystem::is_regular_file(path, ec) || ec) {
        reason = "일반 파일이 아닙니다";
        return false;
    }
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) {
        reason = "파일 속성을 읽을 수 없습니다";
        return false;
    }
    if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
        reason = "reparse point 입니다";
        return false;
    }
    std::wstring extension = path.extension().wstring();
    std::transform(extension.begin(), extension.end(), extension.begin(),
                   [](wchar_t c) { return static_cast<wchar_t>(::towlower(c)); });
    if (extension != L".exe") {
        reason = "확장자가 .exe 가 아닙니다";
        return false;
    }
    const std::optional<std::uint16_t> machine = peMachineType(path);
    if (!machine) {
        reason = "PE 헤더가 유효하지 않습니다";
        return false;
    }

    USHORT processMachine = 0;
    USHORT nativeMachine = 0;
    if (IsWow64Process2(GetCurrentProcess(), &processMachine, &nativeMachine) == 0) {
        nativeMachine = IMAGE_FILE_MACHINE_AMD64;
    }
    if (*machine != nativeMachine) {
        // **거부하지 않는다.** 에뮬레이션으로 동작하기는 한다. 다만 libusb/
        // WinUSB 계층에서 문제가 생길 수 있으므로 기록은 남긴다(§3.1).
        warnings.push_back("scanimage.exe architecture differs from this process; USB transport "
                           "issues are possible.");
    }
    return true;
}

[[nodiscard]] bool tryCandidate(const std::filesystem::path& candidate,
                                std::string source,
                                ScanimageLocation& out) {
    if (candidate.empty()) return false;
    std::string reason;
    std::vector<std::string> warnings;
    if (!isUsableScanimage(candidate, warnings, reason)) return false;
    out.found = true;
    out.path = candidate;
    out.source = std::move(source);
    out.warnings.insert(out.warnings.end(), warnings.begin(), warnings.end());
    return true;
}

/// `PATH` 에서 `scanimage.exe` 를 찾는다.
[[nodiscard]] std::filesystem::path searchPath() {
    std::wstring buffer(MAX_PATH, L'\0');
    for (;;) {
        const DWORD written = SearchPathW(nullptr, L"scanimage.exe", nullptr,
                                          static_cast<DWORD>(buffer.size()), buffer.data(), nullptr);
        if (written == 0) return {};
        if (written < buffer.size()) {
            buffer.resize(written);
            return std::filesystem::path{buffer};
        }
        buffer.resize(written + 1);
    }
}

}  // namespace

std::optional<std::string> environmentValue(std::string_view name) {
    const std::optional<std::wstring> value = environmentValueW(widen(name).c_str());
    if (!value) return std::nullopt;
    return narrow(*value);
}

ScanimageLocation findScanimage() {
    ScanimageLocation location;

    // ① 환경 변수. **여기서도 검증한다** — macOS 와 의도적으로 다르다(§3.1).
    if (const std::optional<std::wstring> override = environmentValueW(L"NEGAFLOW_SCANIMAGE_PATH")) {
        const std::filesystem::path candidate{*override};
        std::string reason;
        std::vector<std::string> warnings;
        if (isUsableScanimage(candidate, warnings, reason)) {
            location.found = true;
            location.path = candidate;
            location.source = "NEGAFLOW_SCANIMAGE_PATH";
            location.warnings = std::move(warnings);
            location.warnings.push_back(
                "scanimage was taken from NEGAFLOW_SCANIMAGE_PATH; its signature is not verified.");
            return location;
        }
        location.failure = "NEGAFLOW_SCANIMAGE_PATH 가 가리키는 파일을 쓸 수 없습니다(" + reason +
                           "): " + narrow(*override);
        return location;
    }

    // ② 우리가 배포한 런타임.
    const std::filesystem::path bundled = pluginDirectory() / "sane" / "bin" / "scanimage.exe";
    if (tryCandidate(bundled, "bundled runtime", location)) return location;

    // ③ PATH. 마지막 수단이며 검증되지 않은 버전일 수 있다(D-24).
    if (tryCandidate(searchPath(), "PATH", location)) {
        location.warnings.push_back(
            "scanimage was found on PATH rather than in the plug-in bundle; its version is not "
            "verified.");
        return location;
    }

    location.failure =
        "scanimage.exe 를 찾을 수 없습니다. NEGAFLOW_SCANIMAGE_PATH 로 경로를 지정하거나 "
        "플러그인의 sane\\bin 에 설치하십시오.";
    return location;
}

std::wstring buildScanEnvironment(const std::filesystem::path& scanimage,
                                  const std::optional<std::string>& defaultDevice) {
    std::vector<std::pair<std::wstring, std::wstring>> overrides;

    // `scanimage -A/--help` 파싱은 영문 옵션명과 '.' 소수점을 계약으로 쓴다.
    overrides.emplace_back(L"LC_ALL", L"C");
    overrides.emplace_back(L"LANG", L"C");

    const std::filesystem::path toolDirectory = scanimage.parent_path();
    if (!toolDirectory.empty()) {
        // **앞에 붙인다.** 뒤에 붙이면 시스템에 같은 이름의 DLL 이 있을 때
        // 그것이 먼저 로드된다(예: 다른 프로그램이 설치한 libusb-1.0.dll).
        std::wstring path = toolDirectory.wstring();
        if (const std::optional<std::wstring> existing = environmentValueW(L"PATH")) {
            if (!existing->empty()) {
                path.push_back(L';');
                path.append(*existing);
            }
        }
        overrides.emplace_back(L"PATH", std::move(path));

        // MSYS2 빌드의 컴파일 시점 경로(`/ucrt64/etc/sane.d`)는 우리 배포에
        // 존재하지 않는다. 같은 트리의 설정을 명시적으로 준다(§5.1).
        std::error_code ec;
        const std::filesystem::path configDir =
            toolDirectory.parent_path() / "etc" / "sane.d";
        if (std::filesystem::is_directory(configDir, ec) && !ec) {
            overrides.emplace_back(L"SANE_CONFIG_DIR", configDir.wstring());
        }
        // 번들 SANE은 개발 PC의 절대 LIBDIR가 아니라 이 디렉터리에서 백엔드를 연다.
        overrides.emplace_back(L"SANE_BACKEND_DIR", toolDirectory.wstring());
    }

    // `SANE_DEFAULT_DEVICE` 가 있으면 `scanimage -L` 이 probe 없이 그 장치를
    // 바로 연다. 만료된 주소는 캐시에서 이미 지워졌으므로 죽은 주소가
    // 주입되지 않는다.
    if (defaultDevice && !defaultDevice->empty()) {
        overrides.emplace_back(L"SANE_DEFAULT_DEVICE", widen(*defaultDevice));
    }

    // `LD_LIBRARY_PATH` 는 **설정하지 않는다**(§5.2). Windows DLL 검색과 무관해
    // 조용히 무시되고, 있으면 다음 사람이 그것이 동작한다고 오해한다.
    return process::buildEnvironmentBlock(overrides);
}

std::filesystem::path infraredPath(const std::filesystem::path& outputPath) {
    std::filesystem::path result = outputPath;
    std::string extension = outputPath.extension().string();
    if (!extension.empty() && extension.front() == '.') extension.erase(0, 1);
    if (extension.empty()) extension = "tiff";
    result.replace_extension();
    result += ".ir." + extension;
    return result;
}

std::filesystem::path multipassSamplePath(const std::filesystem::path& outputPath, int index) {
    std::filesystem::path result = outputPath;
    result.replace_extension();
    result += ".negaflow-sample" + std::to_string(index + 1) + ".tiff";
    return result;
}

bool keepMultipassArtifacts() {
    const std::optional<std::string> value = environmentValue("NEGAFLOW_KEEP_MULTIPASS");
    if (!value) return false;
    std::string lowered = *value;
    std::transform(lowered.begin(), lowered.end(), lowered.begin(),
                   [](unsigned char c) { return static_cast<char>(::tolower(c)); });
    return lowered == "1" || lowered == "true";
}

int hardwareExposureSamplesPerStop() {
    const std::optional<std::string> raw = environmentValue("NEGAFLOW_HWEXP_SAMPLES");
    int parsed = 1;
    if (raw) {
        try {
            parsed = std::stoi(*raw);
        } catch (...) {
            parsed = 1;
        }
    }
    return std::min(std::max(parsed, 1), 4);
}

std::vector<int> hardwareExposurePlan() {
    const int samples = hardwareExposureSamplesPerStop();
    std::vector<int> plan;
    for (const int exposure : sane::kHardwareExposureTimes) {
        for (int i = 0; i < samples; ++i) plan.push_back(exposure);
    }
    return plan;
}

}  // namespace negaflow::app
