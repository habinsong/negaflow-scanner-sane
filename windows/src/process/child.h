// negaflow-scanner-sane — Windows adapter
// process/child — `CreateProcessW` 로 `scanimage` 를 띄운다.
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend+Process.swift
//            (runScanimage, runScanimageTo)
// 정본 문서: windows_docs/03-process-and-io/child-process.md
//
// ## 두 가지 실행 형태를 그대로 유지한다 (§2)
//
// ```text
// 유틸리티(-L/-f/-A)   stdout → 파이프   stderr → 파이프   둘 다 전용 스레드
// 획득(-p --format)     stdout → 파일     stderr → 파이프   스트리밍 파싱
// ```
//
// 이미지 바이트를 파이프로 받아 파일에 다시 쓰면 불필요한 복사와 교착 위험이
// 생긴다. 그래서 비대칭을 유지한다.
//
// ## 교착을 막는 규칙 (§3)
//
// ```text
// 1. 파이프 생성
// 2. 자식이 쓰는 끝만 상속 가능하게
// 3. CreateProcessW
// 4. 부모가 들고 있는 "자식용 쓰기 끝"을 **즉시 닫는다**   ← 빠뜨리면 EOF 가 안 온다
// 5. 그제서야 읽기 시작. stdout·stderr 를 **동시에**
// ```
//
// Foundation 은 4번을 자동으로 한다. 그래서 Swift 원본에는 대응하는 줄이 없다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <filesystem>
#include <functional>
#include <string>
#include <vector>

#include "process/acquisition.h"
#include "process/budget.h"
#include "process/cancel.h"
#include "process/watchdog.h"

namespace negaflow::process {

/// 자식 실행이 어떻게 끝났는가. **종료 코드만 보고 판단하지 않는다** —
/// `TerminateProcess(h, 1)` 로 죽인 프로세스의 종료 코드도 1 이다(§9.1).
enum class LaunchStatus {
    Ok,
    /// 소유권이 거절했다. 동시 실행 또는 세션 규칙 위반.
    Busy,
    /// 시작 전에 이미 취소 요청이 있었다.
    Cancelled,
    /// `CreateProcessW` 자체가 실패했다. `launchError` 에 이유가 있다.
    LaunchFailed,
};

/// 유틸리티 실행 결과.
struct UtilityOutcome {
    LaunchStatus status = LaunchStatus::Ok;
    std::string launchError;
    int exitCode = 0;
    std::string stdoutText;
    std::string stderrText;  ///< 유효한 UTF-8 로 정리된 것
    bool timedOut = false;
    bool cancelled = false;
};

/// 획득 실행 결과.
struct AcquisitionRun {
    LaunchStatus status = LaunchStatus::Ok;
    std::string launchError;
    int exitCode = 0;
    bool madeProgress = false;
    TimeoutKind timeoutKind = TimeoutKind::None;
    bool cancelled = false;
};

/// 진행률 콜백. 0…1 로 정규화된 값이 온다. **스레드에서 불린다.**
using ProgressSink = std::function<void(double fraction)>;

/// 부모 환경을 복사해 덮어쓴 자식용 환경 블록.
///
/// **부모 환경을 통째로 비우지 않는다.** `SystemRoot` / `TEMP` / `USERPROFILE`
/// 가 없으면 CRT 나 libusb 가 실패한다(environment-and-paths §5.4).
///
/// 결과는 `\0` 으로 구분되고 `\0\0` 으로 끝나는 `CREATE_UNICODE_ENVIRONMENT`
/// 블록이다.
[[nodiscard]] std::wstring buildEnvironmentBlock(
    const std::vector<std::pair<std::wstring, std::wstring>>& overrides);

/// UTF-8 로 디코드할 수 없는 바이트를 U+FFFD 로 바꾼다.
///
/// `scanimage` stderr 인코딩은 빌드와 콘솔 코드 페이지에 따라 달라진다.
/// 진행률 파싱은 ASCII 만 쓰므로 실용상 문제가 없지만, **오류 메시지를 그대로
/// wire 에 실을 때는 유효한 UTF-8 이어야 한다**(child-process §10.1).
[[nodiscard]] std::string sanitizeUtf8(std::string_view raw);

/// 유틸리티 실행. stdout 을 돌려주고 stderr 를 모은다.
///
/// `timeout` 이 지나면 자식을 끝내고 `timedOut` 을 세운다. 종료 코드로는
/// 타임아웃을 알 수 없으므로 별도 상태로 유지한다(§9.1).
[[nodiscard]] UtilityOutcome runUtility(const std::filesystem::path& executable,
                                        const std::vector<std::string>& args,
                                        const std::wstring& environmentBlock,
                                        Duration timeout,
                                        ProcessOwnership& ownership,
                                        bool ownedByScanSession);

/// 획득 실행. stdout 을 `outputPath` 에 직접 쓴다.
///
/// **출력 파일은 핸들로 검증한다**(§5.1, §7): 열자마자
/// `GetFinalPathNameByHandleW` 로 최종 경로가 요청과 같은지 보고
/// reparse point 가 아님을 확인한다. 어긋나면 시작하지 않는다.
///
/// `useWatchdog` 이 false 면(pieusb) 타이머를 걸지 않는다. 그 장치는
/// shading/calibration 을 `sane_start` 안에서 동기 실행해 첫 진행률이
/// 장시간 없을 수 있고, 중간 종료가 transport 상태를 망가뜨린다.
[[nodiscard]] AcquisitionRun runAcquisition(const std::filesystem::path& executable,
                                            const std::vector<std::string>& args,
                                            const std::wstring& environmentBlock,
                                            const std::filesystem::path& outputPath,
                                            Duration firstProgressTimeout,
                                            Duration stallTimeout,
                                            bool useWatchdog,
                                            ProgressTracker& tracker,
                                            const ProgressSink& onProgress,
                                            ProcessOwnership& ownership);

}  // namespace negaflow::process
