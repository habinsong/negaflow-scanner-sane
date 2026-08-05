// SPDX-License-Identifier: GPL-2.0-or-later

#include "process/cancel.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <atomic>

namespace negaflow::process {

namespace {

/// 콘솔 핸들러는 C 함수 포인터라 상태를 실어 보낼 수 없다.
/// **하나뿐인 프로세스 전역이다** — 어댑터는 요청 하나를 처리하고 끝난다.
std::atomic<ProcessOwnership*> g_consoleOwner{nullptr};

BOOL WINAPI consoleHandler(DWORD type) {
    switch (type) {
        case CTRL_C_EVENT:
        case CTRL_BREAK_EVENT:
        case CTRL_CLOSE_EVENT:
        case CTRL_LOGOFF_EVENT:
        case CTRL_SHUTDOWN_EVENT:
            break;
        default:
            return FALSE;
    }
    ProcessOwnership* owner = g_consoleOwner.load(std::memory_order_acquire);
    if (owner == nullptr) return FALSE;
    owner->requestCancellation();
    // TRUE 를 돌려주면 기본 종료가 일어나지 않는다. 취소 오류 이벤트를 내보내고
    // 우리가 exit 하는 것이 계약이다(cancellation §8).
    return TRUE;
}

[[nodiscard]] bool stillRunning(HANDLE process) {
    if (process == nullptr) return false;
    return WaitForSingleObject(process, 0) == WAIT_TIMEOUT;
}

}  // namespace

ProcessOwnership::SessionError ProcessOwnership::beginScanSession(std::uint64_t* outSessionID) {
    std::lock_guard lock(mutex_);
    if (current_.process != nullptr && !stillRunning(current_.process)) {
        current_ = ChildHandles{};
    }
    if (cancellationRequested_) return SessionError::Cancelled;
    if (activeSessionID_ != 0 || current_.process != nullptr) return SessionError::Busy;
    activeSessionID_ = nextSessionID_++;
    if (outSessionID != nullptr) *outSessionID = activeSessionID_;
    return SessionError::None;
}

void ProcessOwnership::endScanSession(std::uint64_t sessionID) {
    std::lock_guard lock(mutex_);
    if (activeSessionID_ != sessionID) return;
    if (current_.process != nullptr && !stillRunning(current_.process)) {
        current_ = ChildHandles{};
    }
    activeSessionID_ = 0;
    cancellationRequested_ = false;
}

ProcessOwnership::SessionError ProcessOwnership::adoptChild(const ChildHandles& child,
                                                           bool requiresScanSession) {
    std::lock_guard lock(mutex_);
    if (current_.process != nullptr) return SessionError::Busy;
    const bool sessionOk = requiresScanSession ? activeSessionID_ != 0 : activeSessionID_ == 0;
    if (!sessionOk) return SessionError::Busy;
    if (cancellationRequested_) return SessionError::Cancelled;
    current_ = child;
    return SessionError::None;
}

void ProcessOwnership::releaseChild(void* processHandle) {
    std::lock_guard lock(mutex_);
    if (current_.process == processHandle) current_ = ChildHandles{};
}

bool ProcessOwnership::cancellationRequested() const {
    std::lock_guard lock(mutex_);
    return cancellationRequested_;
}

bool ProcessOwnership::lastCancellationWasForced() const {
    std::lock_guard lock(mutex_);
    return forcedTermination_;
}

void ProcessOwnership::clearUtilityCancellation() {
    std::lock_guard lock(mutex_);
    if (activeSessionID_ != 0 || current_.process != nullptr) return;
    cancellationRequested_ = false;
}

void ProcessOwnership::requestCancellation() {
    ChildHandles child{};
    {
        std::lock_guard lock(mutex_);
        cancellationRequested_ = true;
        child = current_;
    }
    if (child.process == nullptr) return;

    HANDLE process = static_cast<HANDLE>(child.process);
    if (!stillRunning(process)) return;

    // ① graceful — 새 프로세스 그룹으로 띄운 자식에게만 보낼 수 있다.
    //    CTRL_C_EVENT 는 그룹 0(자기 그룹 전체)에만 갈 수 있어 우리 자신도
    //    맞으므로 쓰지 않는다(cancellation §4.1).
    if (child.ownProcessGroup) {
        (void)GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, child.pid);
    }

    // ② 유예. `sane_cancel()` 이 현재 전송 블록을 끝낼 시간을 준다.
    const DWORD grace = static_cast<DWORD>(kCancelGracePeriod.count());
    if (WaitForSingleObject(process, grace) == WAIT_OBJECT_0) return;

    // ③ 강제. Job 이 있으면 트리 전체, 없으면 프로세스만.
    {
        std::lock_guard lock(mutex_);
        forcedTermination_ = true;
    }
    if (child.job != nullptr) {
        (void)TerminateJobObject(static_cast<HANDLE>(child.job), 1);
    } else {
        (void)TerminateProcess(process, 1);
    }
}

bool ensureConsoleForCancellation() {
    if (GetConsoleWindow() != nullptr) return true;

    // AllocConsole 은 표준 핸들 셋을 새 콘솔로 덮어쓴다. 우리 stdout 은 wire
    // 프로토콜이므로 저장했다가 되돌린다.
    HANDLE saved[3] = {GetStdHandle(STD_INPUT_HANDLE), GetStdHandle(STD_OUTPUT_HANDLE),
                       GetStdHandle(STD_ERROR_HANDLE)};

    if (AllocConsole() == FALSE) return GetConsoleWindow() != nullptr;

    SetStdHandle(STD_INPUT_HANDLE, saved[0]);
    SetStdHandle(STD_OUTPUT_HANDLE, saved[1]);
    SetStdHandle(STD_ERROR_HANDLE, saved[2]);

    // 창은 보여줄 것이 없다. 취소 신호를 나를 통로로만 쓴다.
    HWND window = GetConsoleWindow();
    if (window != nullptr) (void)ShowWindow(window, SW_HIDE);
    return window != nullptr;
}

void installConsoleCancellation(ProcessOwnership* owner) {
    g_consoleOwner.store(owner, std::memory_order_release);
    (void)SetConsoleCtrlHandler(consoleHandler, TRUE);
}

}  // namespace negaflow::process
