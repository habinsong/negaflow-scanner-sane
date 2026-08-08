// negaflow-scanner-sane — Windows adapter
// process/cancel — 취소 상태 기계와 프로세스 소유권.
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend+Process.swift
//            (beginScanSession, launchOwnedScanProcess, cancelScan …)
//            Sources/negaflow-scanner-sane/main.swift
//            (installScanCancellationForwarders)
// 정본 문서: docs/03-process-and-io/cancellation.md §5, §7
//            docs/03-process-and-io/child-process.md §8
//
// ## 두 개의 취소가 있다
//
// ```text
// A. 호스트 → 플러그인    macOS: SIGTERM/SIGINT   Windows: 콘솔 제어 이벤트
// B. 플러그인 → scanimage macOS: SIGTERM          Windows: §5 의 3단계
// ```
//
// B 는 Windows 에 직접 대응이 없다. `TerminateProcess` 는 `sane_cancel()` 을
// 부르지 않으므로 스캐너가 전송 중간 상태로 남는다. 그래서 순서를 지킨다:
//
// ```text
// 1. CTRL_BREAK_EVENT      (새 프로세스 그룹으로 띄웠으므로 자식만 받는다)
// 2. 유예 대기              kCancelGracePeriod
// 3. Job 전체 종료          손자까지 남기지 않는다
// ```
//
// 3번으로 끝났으면 **강제 종료였다**(`lastCancellationWasForced`). 호출자가
// 주소 캐시를 버리고 다음 open 전에 여유를 둔다(cancellation §5.2).
//
// ## `HANDLE` 대신 `void*` 를 쓰는 이유
//
// 이 헤더가 <windows.h> 를 끌어오면 그것을 포함하는 모든 번역 단위가
// `min`/`max` 매크로와 함께 오염된다. `HANDLE` 은 원래 `void*` 이므로
// 손해가 없다. 실제 Win32 호출은 전부 .cpp 안에 있다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstdint>
#include <mutex>
#include <string_view>

#include "process/budget.h"

namespace negaflow::process {

/// 취소 신호를 보낸 뒤 강제 종료까지 기다리는 시간.
///
/// **넉넉해야 한다.** 이 시간이 지나 `TerminateProcess` 로 넘어가면 스캐너가
/// 전송 도중에 죽고, 전원을 다시 넣기 전까지 어떤 요청에도 답하지 않는다.
/// 취소가 느린 것보다 그쪽이 훨씬 나쁘다.
///
/// 실측(OpticFilm 8100): 스캔 6초 지점에서 CTRL_BREAK 를 보내면 `scanimage`
/// 가 **6,890 ms** 만에 끝난다. 신호를 받은 뒤 진행 중인 `sane_read` 가
/// 끝나기를 기다리고, `sane_cancel` 이 헤드를 홈으로 돌리는 시간이 그 안에
/// 있다. 예전 값 2,000 ms 로는 그 한가운데에서 죽였을 것이다.
inline constexpr Duration kCancelGracePeriod = std::chrono::milliseconds{15'000};

/// 자식 프로세스 하나. 전부 Win32 핸들이지만 여기서는 불투명하다.
struct ChildHandles {
    void* process = nullptr;  ///< HANDLE
    void* job = nullptr;      ///< HANDLE (없을 수 있다 — 중첩 Job 실패)
    unsigned long pid = 0;
    /// `CREATE_NEW_PROCESS_GROUP` 으로 띄웠는가. 아니면 CTRL_BREAK 를 건너뛴다.
    bool ownProcessGroup = false;
};

/// 한 백엔드 인스턴스의 프로세스 소유권과 취소 플래그.
///
/// **불변식 넷**(child-process §8):
///   1. 동시 프로세스는 하나
///   2. 스캔 세션 중에는 유틸리티 실행 불가
///   3. 스캔 세션 밖에서는 스캔 프로세스 불가
///   4. **이름이나 경로로 전역 프로세스를 찾아 죽이지 않는다**
///
/// 4번은 보안 요건이다. `scanimage.exe` 를 이름으로 열거해 죽이면 사용자의
/// 다른 SANE 프런트엔드를 죽인다.
class ProcessOwnership {
public:
    enum class SessionError { None, Busy, Cancelled };

    /// 스캔 세션을 연다. 성공하면 `*outSessionID` 가 채워진다.
    ///
    /// `deviceKey` 는 이름 붙은 뮤텍스의 키다. **어댑터 프로세스 하나만으로는
    /// 부족하다** — `usbscan.sys` 는 배타 접근을 강제하지 않는다. 실측:
    /// 한 프로세스가 `FILE_SHARE` 를 0 으로 주고 잡고 있어도 다른 프로세스가
    /// 그대로 연다. 그러면 두 스캔이 같은 파이프에 전송을 섞어 넣고, 그렇게
    /// 망가진 스캐너는 전원을 다시 넣기 전까지 돌아오지 않는다. libusb 가
    /// `EBUSY` 를 주는 macOS 와 달리 여기서는 아무도 막아주지 않으므로
    /// 우리가 막는다.
    ///
    /// 비어 있으면 기계 범위 잠금을 건너뛴다(장치를 아직 모르는 호출).
    [[nodiscard]] SessionError beginScanSession(std::uint64_t* outSessionID,
                                                std::string_view deviceKey = {});

    /// 세션을 닫는다. **취소 플래그도 지운다.**
    void endScanSession(std::uint64_t sessionID);

    /// 프로세스를 등록해도 되는가. 등록까지 한 번에 한다.
    ///
    /// 호출자는 `CreateProcessW` 성공 **직후**, 자식을 재개하기 전에 부른다.
    /// 거절되면(`Busy`/`Cancelled`) 호출자가 자식을 정리한다.
    [[nodiscard]] SessionError adoptChild(const ChildHandles& child, bool requiresScanSession);

    /// 등록을 해제한다. 같은 프로세스일 때만 지운다.
    void releaseChild(void* processHandle);

    [[nodiscard]] bool cancellationRequested() const;

    /// 호스트 취소(A). 플래그를 세우고 현재 자식에게 §5 의 3단계를 적용한다.
    ///
    /// 자식이 없으면 플래그만 세운다 — 다음 `adoptChild` 가 거절된다.
    void requestCancellation();

    /// 유틸리티 실행이 끝났고 세션이 없을 때만 플래그를 지운다.
    void clearUtilityCancellation();

    /// 마지막 취소가 강제 종료로 끝났는가. 복구 절차 판단용(§5.2).
    [[nodiscard]] bool lastCancellationWasForced() const;

private:
    mutable std::mutex mutex_;
    ChildHandles current_{};
    std::uint64_t activeSessionID_ = 0;
    std::uint64_t nextSessionID_ = 1;
    /// 기계 범위 잠금. 세션 동안만 쥔다. 다른 핸들과 같은 이유로 불투명하다.
    void* machineLock_ = nullptr;  ///< HANDLE (뮤텍스)
    bool cancellationRequested_ = false;
    bool forcedTermination_ = false;
};

/// 콘솔 제어 핸들러를 설치한다. **한 번만 유효하다.**
///
/// `CTRL_C_EVENT` / `CTRL_BREAK_EVENT` / `CTRL_CLOSE_EVENT` 를 받아
/// `owner->requestCancellation()` 을 부른다. macOS 가 `[SIGTERM, SIGINT]` 를
/// 모두 받는 것과 같은 범위다(cancellation §3).
///
/// 콘솔이 없으면(GUI 호스트의 자식) 설치는 성공하지만 이벤트가 오지 않는다.
/// 그 경우 안전망은 Job Object 다 — 어댑터가 강제 종료돼도 `scanimage` 가
/// 남지 않는다(§6).
void installConsoleCancellation(ProcessOwnership* owner);

/// 취소를 위한 콘솔을 확보한다. 이미 있으면 아무것도 하지 않는다.
///
/// `GenerateConsoleCtrlEvent` 는 **부르는 쪽의 콘솔을 공유하는** 프로세스
/// 그룹에만 신호를 보낸다(MS 문서). GUI 호스트의 자식으로 뜨면 콘솔이 없어
/// 그 경로가 통째로 죽고, 취소는 `TerminateProcess` 로만 끝난다 — 전송
/// 도중에 죽은 스캐너는 전원을 다시 넣기 전까지 돌아오지 않는다.
///
/// 그래서 콘솔이 없으면 하나 만들어 창을 숨긴다. `AllocConsole` 은 표준
/// 핸들을 새 콘솔로 **덮어쓰므로**(MS 문서) 부르기 전에 세 개를 저장했다가
/// 되돌린다. 그러지 않으면 stdout 이 wire 프로토콜에서 콘솔로 옮겨간다.
/// 제어 핸들러 표도 초기화되므로 호출자는 그 뒤에
/// `installConsoleCancellation` 을 부른다.
///
/// @return 이 프로세스에 콘솔이 있는가. 없으면 취소는 강제 종료뿐이다.
bool ensureConsoleForCancellation();

}  // namespace negaflow::process
