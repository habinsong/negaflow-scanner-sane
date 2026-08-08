// negaflow-scanner-sane — Windows adapter
// app/environment — `scanimage` 를 찾고 자식 환경을 만든다.
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend+Environment.swift
// 정본 문서: windows_docs/03-process-and-io/environment-and-paths.md
//
// ## macOS 의 절반이 여기서 사라진다
//
// ```text
// Homebrew keg 경로   Windows 에 없다
// /usr/bin, /etc      없다
// LD_LIBRARY_PATH     **동작하지 않는다.** 설정하면 조용히 무시된다 → §5.2
// isExecutableFile    실행 권한 비트가 없다 → PE 헤더를 본다 → §3.1
// ```
//
// `LD_LIBRARY_PATH` 를 그대로 옮기는 것이 가장 위험하다 — 아무 일도 일어나지
// 않고, 개발자는 왜 백엔드가 로드되지 않는지 알 수 없다. **설정하지 않는다.**
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace negaflow::app {

/// `scanimage` 탐색 결과.
struct ScanimageLocation {
    bool found = false;
    std::filesystem::path path;
    /// 어디서 찾았는지. 진단에 남긴다.
    std::string source;
    /// 사용자에게 보고할 것. 번들 밖 실행 파일 경고 등(D-24).
    std::vector<std::string> warnings;
    /// 못 찾았을 때의 이유.
    std::string failure;
};

/// §3 의 탐색 순서.
///
/// ```text
/// 1. NEGAFLOW_SCANIMAGE_PATH        환경 변수. **여기서도 검증한다**
/// 2. <플러그인 디렉터리>\sane\bin\scanimage.exe
/// 3. PATH 검색                      마지막 수단
/// ```
///
/// **하드코딩된 시스템 경로가 없다.** macOS 의 Homebrew 경로에 해당하는 것이
/// Windows 에 없고, MSYS2 기본 경로를 넣으면 우리가 검증하지 않은 버전을
/// 조용히 쓰게 된다. 그쪽을 쓰려는 사용자는 1번으로 명시한다.
///
/// 1번을 검증하는 것은 macOS 와 **의도적으로 다르다**(§3.1). macOS 는 환경
/// 변수 값을 검사 없이 쓰므로 오타가 있으면 exec 실패라는 모호한 오류만
/// 나온다. I-20 후보다.
[[nodiscard]] ScanimageLocation findScanimage();

/// 자식에게 줄 환경 블록. **부모 환경을 복사해 덮어쓴다.**
///
/// ```text
/// LC_ALL = C, LANG = C           옵션 이름과 '.' 소수점이 계약이다
/// PATH   = <scanimage 디렉터리>;<기존>   **앞에 붙인다**(§4.3)
/// SANE_CONFIG_DIR                같은 트리의 etc\sane.d 가 있을 때만
/// SANE_DEFAULT_DEVICE            캐시된 선택자가 있을 때만
/// LD_LIBRARY_PATH                **설정하지 않는다**
/// ```
[[nodiscard]] std::wstring buildScanEnvironment(const std::filesystem::path& scanimage,
                                                const std::optional<std::string>& defaultDevice);

/// IR 결과 경로. `frame.tiff` → `frame.ir.tiff`.
///
/// **호스트가 이 경로를 예측할 수 있어야 검증할 수 있다. 규칙을 바꾸지 않는다**
/// (child-process §7).
[[nodiscard]] std::filesystem::path infraredPath(const std::filesystem::path& outputPath);

/// 다중 노출 중간 파일 경로. **`%TEMP%` 가 아니라 출력과 같은 디렉터리다**(§7.1).
///
/// 7200 dpi 12 패스면 중간 파일만 4.8 GB 다. 호스트는 이미 공간이 있는 볼륨을
/// 골랐고, staging 디렉터리를 정리하므로 우리가 실패해도 남지 않는다.
[[nodiscard]] std::filesystem::path multipassSamplePath(const std::filesystem::path& outputPath,
                                                        int index);

/// `NEGAFLOW_KEEP_MULTIPASS` 가 `1` 또는 `true` 인가.
[[nodiscard]] bool keepMultipassArtifacts();

/// `NEGAFLOW_HWEXP_SAMPLES`. 1…4 로 잘라낸다. 기본 1.
[[nodiscard]] int hardwareExposureSamplesPerStop();

/// 노출 브래킷 계획. `kHardwareExposureTimes` 각각을 표본 수만큼 반복한다.
[[nodiscard]] std::vector<int> hardwareExposurePlan();

/// 환경 변수 하나. 없으면 nullopt.
[[nodiscard]] std::optional<std::string> environmentValue(std::string_view name);

}  // namespace negaflow::app
