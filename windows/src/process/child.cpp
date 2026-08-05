// SPDX-License-Identifier: GPL-2.0-or-later

#include "process/child.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <algorithm>
#include <cstring>
#include <memory>
#include <thread>
#include <utility>

#include "process/command_line.h"

namespace negaflow::process {

namespace {

/// 유틸리티 타임아웃 뒤 강제 종료까지의 유예. macOS 의 0.5 s 와 같다(§11).
constexpr DWORD kTimeoutGraceMs = 500;

/// 파이프 읽기 단위. 진행률 레코드는 짧고 옵션 덤프는 수십 KB 다.
constexpr DWORD kReadChunk = 8192;

// --- RAII -----------------------------------------------------------------

class Handle {
public:
    Handle() = default;
    explicit Handle(HANDLE h) : h_(h) {}
    ~Handle() { reset(); }

    Handle(const Handle&) = delete;
    Handle& operator=(const Handle&) = delete;
    Handle(Handle&& other) noexcept : h_(other.release()) {}
    Handle& operator=(Handle&& other) noexcept {
        if (this != &other) {
            reset();
            h_ = other.release();
        }
        return *this;
    }

    [[nodiscard]] HANDLE get() const noexcept { return h_; }
    [[nodiscard]] bool valid() const noexcept {
        return h_ != nullptr && h_ != INVALID_HANDLE_VALUE;
    }

    HANDLE release() noexcept {
        HANDLE h = h_;
        h_ = nullptr;
        return h;
    }

    void reset(HANDLE h = nullptr) noexcept {
        if (valid()) CloseHandle(h_);
        h_ = h;
    }

private:
    HANDLE h_ = nullptr;
};

[[nodiscard]] std::wstring widen(std::string_view utf8) {
    if (utf8.empty()) return {};
    const int needed = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                           static_cast<int>(utf8.size()), nullptr, 0);
    if (needed <= 0) return {};
    std::wstring out(static_cast<std::size_t>(needed), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), out.data(),
                        needed);
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

[[nodiscard]] std::string formatLastError(DWORD code) {
    LPWSTR buffer = nullptr;
    const DWORD length = FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr, code, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), reinterpret_cast<LPWSTR>(&buffer),
        0, nullptr);
    std::string text = "Win32 error " + std::to_string(code);
    if (length != 0 && buffer != nullptr) {
        std::wstring_view view{buffer, length};
        while (!view.empty() && (view.back() == L'\r' || view.back() == L'\n' || view.back() == L' ')) {
            view.remove_suffix(1);
        }
        text += ": " + narrow(view);
    }
    if (buffer != nullptr) LocalFree(buffer);
    return text;
}

/// 상속 가능한 파이프 한 쌍. `childEnd` 만 자식이 물려받는다.
struct AnonymousPipe {
    Handle parentEnd;
    Handle childEnd;
};

[[nodiscard]] bool makeOutputPipe(AnonymousPipe& pipe) {
    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;
    HANDLE readEnd = nullptr;
    HANDLE writeEnd = nullptr;
    if (CreatePipe(&readEnd, &writeEnd, &sa, 0) == 0) return false;
    // **읽기 끝은 상속시키지 않는다.** 자식이 들고 있으면 EOF 가 오지 않는다.
    if (SetHandleInformation(readEnd, HANDLE_FLAG_INHERIT, 0) == 0) {
        CloseHandle(readEnd);
        CloseHandle(writeEnd);
        return false;
    }
    pipe.parentEnd.reset(readEnd);
    pipe.childEnd.reset(writeEnd);
    return true;
}

[[nodiscard]] Handle openNulForReading() {
    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;
    return Handle{CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa,
                              OPEN_EXISTING, 0, nullptr)};
}

/// 최종 경로에서 `\\?\` 접두를 뗀다. 요청 경로와 비교하기 위한 것이다.
[[nodiscard]] std::wstring stripExtendedPrefix(std::wstring path) {
    if (path.rfind(LR"(\\?\UNC\)", 0) == 0) {
        return LR"(\\)" + path.substr(8);
    }
    if (path.rfind(LR"(\\?\)", 0) == 0) {
        return path.substr(4);
    }
    return path;
}

[[nodiscard]] bool sameWindowsPath(std::wstring_view a, std::wstring_view b) {
    if (a.size() != b.size()) return false;
    return CompareStringOrdinal(a.data(), static_cast<int>(a.size()), b.data(),
                                static_cast<int>(b.size()), TRUE) == CSTR_EQUAL;
}

/// 획득 출력 파일을 열고 핸들로 검증한다(§5.1, §7).
///
/// 경로로 검증하고 경로로 다시 열면 TOCTOU 다. 열어 둔 핸들에서 최종 경로를
/// 읽고 reparse point 여부를 보는 것이 그것을 없앤다.
[[nodiscard]] Handle openValidatedOutputFile(const std::filesystem::path& path,
                                             std::string& error) {
    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;

    const std::wstring requested = path.wstring();
    Handle file{CreateFileW(requested.c_str(), GENERIC_WRITE, 0, &sa, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, nullptr)};
    if (!file.valid()) {
        error = "출력 파일을 만들 수 없습니다: " + formatLastError(GetLastError());
        return Handle{};
    }

    BY_HANDLE_FILE_INFORMATION info{};
    if (GetFileInformationByHandle(file.get(), &info) == 0) {
        error = "출력 파일 정보를 읽을 수 없습니다: " + formatLastError(GetLastError());
        return Handle{};
    }
    if ((info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
        error = "출력 경로가 reparse point 입니다.";
        return Handle{};
    }

    std::wstring finalPath(MAX_PATH, L'\0');
    DWORD length = GetFinalPathNameByHandleW(file.get(), finalPath.data(),
                                             static_cast<DWORD>(finalPath.size()),
                                             FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    if (length > finalPath.size()) {
        finalPath.resize(length);
        length = GetFinalPathNameByHandleW(file.get(), finalPath.data(),
                                           static_cast<DWORD>(finalPath.size()),
                                           FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    }
    if (length == 0) {
        error = "출력 파일의 최종 경로를 확인할 수 없습니다: " + formatLastError(GetLastError());
        return Handle{};
    }
    finalPath.resize(length);
    if (!sameWindowsPath(stripExtendedPrefix(std::move(finalPath)), requested)) {
        error = "출력 경로가 다른 위치로 연결됩니다.";
        return Handle{};
    }
    return file;
}

struct LaunchedChild {
    Handle process;
    Handle job;
    DWORD pid = 0;
    bool ownProcessGroup = false;
};

/// 자식을 만들고 Job 에 넣은 뒤 재개한다.
///
/// **`CREATE_SUSPENDED` → Job 할당 → `ResumeThread` 순서가 중요하다**(§6).
/// 그러지 않으면 자식이 Job 에 들어가기 전에 손자를 만들 수 있다.
[[nodiscard]] bool launchChild(const std::filesystem::path& executable,
                               const std::vector<std::string>& args,
                               const std::wstring& environmentBlock,
                               HANDLE stdoutHandle,
                               HANDLE stderrHandle,
                               HANDLE stdinHandle,
                               LaunchedChild& out,
                               std::string& error) {
    const std::string commandLineUtf8 =
        buildCommandLine(executable.string(), args);
    std::wstring commandLine = widen(commandLineUtf8);
    if (commandLine.empty()) {
        error = "명령줄을 만들 수 없습니다.";
        return false;
    }
    commandLine.push_back(L'\0');  // CreateProcessW 는 쓰기 가능한 버퍼를 요구한다

    HANDLE inherited[3] = {stdoutHandle, stderrHandle, stdinHandle};
    DWORD inheritedCount = 0;
    for (HANDLE h : inherited) {
        if (h != nullptr && h != INVALID_HANDLE_VALUE) ++inheritedCount;
    }
    HANDLE compact[3]{};
    DWORD compactCount = 0;
    for (HANDLE h : inherited) {
        if (h != nullptr && h != INVALID_HANDLE_VALUE) compact[compactCount++] = h;
    }

    SIZE_T attributeSize = 0;
    InitializeProcThreadAttributeList(nullptr, 1, 0, &attributeSize);
    std::vector<unsigned char> attributeStorage(attributeSize);
    auto* attributes = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(attributeStorage.data());
    bool attributesReady = InitializeProcThreadAttributeList(attributes, 1, 0, &attributeSize) != 0;
    if (attributesReady && compactCount > 0) {
        // **`bInheritHandles: TRUE` 만 쓰면 상속 가능한 핸들이 전부 넘어간다.**
        // 넘길 것을 명시적으로 셋으로 제한한다(§5.2).
        attributesReady = UpdateProcThreadAttribute(attributes, 0,
                                                    PROC_THREAD_ATTRIBUTE_HANDLE_LIST, compact,
                                                    compactCount * sizeof(HANDLE), nullptr,
                                                    nullptr) != 0;
    }

    STARTUPINFOEXW startup{};
    startup.StartupInfo.cb = sizeof(startup);
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdOutput = stdoutHandle;
    startup.StartupInfo.hStdError = stderrHandle;
    startup.StartupInfo.hStdInput = stdinHandle;
    if (attributesReady) startup.lpAttributeList = attributes;

    // 콘솔이 있으면 자식을 **자기 프로세스 그룹**으로 띄운다 — 그래야
    // `GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, pid)` 가 우리 자신을 때리지
    // 않고 자식에게만 간다(cancellation §4.1). 콘솔이 없으면(GUI 호스트의
    // 자식) 제어 이벤트를 보낼 방법이 애초에 없으므로, 검은 창이 깜빡이지
    // 않도록 `CREATE_NO_WINDOW` 를 준다. 그 경우 취소는 강제 종료 경로다.
    const bool hasConsole = GetConsoleWindow() != nullptr;
    DWORD flags = CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT;
    flags |= attributesReady ? EXTENDED_STARTUPINFO_PRESENT : 0;
    flags |= hasConsole ? CREATE_NEW_PROCESS_GROUP : CREATE_NO_WINDOW;

    const std::wstring applicationName = executable.wstring();
    PROCESS_INFORMATION info{};
    const BOOL created = CreateProcessW(
        applicationName.empty() ? nullptr : applicationName.c_str(), commandLine.data(), nullptr,
        nullptr, TRUE, flags,
        environmentBlock.empty() ? nullptr : const_cast<wchar_t*>(environmentBlock.data()), nullptr,
        &startup.StartupInfo, &info);
    const DWORD createError = GetLastError();
    if (attributesReady) DeleteProcThreadAttributeList(attributes);
    if (created == 0) {
        error = "scanimage 를 실행할 수 없습니다: " + formatLastError(createError);
        return false;
    }

    out.process.reset(info.hProcess);
    out.pid = info.dwProcessId;
    out.ownProcessGroup = hasConsole;
    Handle thread{info.hThread};

    // Job Object — 타임아웃/취소로 죽일 때 손자까지 남기지 않는다(§6).
    // **실패를 치명적으로 다루지 않는다.** 이미 다른 Job 에 속한 환경(일부 CI,
    // 컨테이너, 디버거)이 있고, 그 경우 Job 없이 계속하는 편이 낫다.
    Handle job{CreateJobObjectW(nullptr, nullptr)};
    if (job.valid()) {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        if (SetInformationJobObject(job.get(), JobObjectExtendedLimitInformation, &limits,
                                    sizeof(limits)) == 0 ||
            AssignProcessToJobObject(job.get(), out.process.get()) == 0) {
            job.reset();
        }
    }
    out.job = std::move(job);

    if (ResumeThread(thread.get()) == static_cast<DWORD>(-1)) {
        error = "자식 프로세스를 재개할 수 없습니다: " + formatLastError(GetLastError());
        TerminateProcess(out.process.get(), 1);
        return false;
    }
    return true;
}

/// EOF 까지 읽는다. 파이프가 끊기면 정상 종료다.
void drainPipe(HANDLE pipe, const std::function<void(std::string_view)>& sink) {
    std::vector<char> buffer(kReadChunk);
    for (;;) {
        DWORD read = 0;
        if (ReadFile(pipe, buffer.data(), kReadChunk, &read, nullptr) == 0) return;
        if (read == 0) return;
        sink(std::string_view{buffer.data(), read});
    }
}

/// 유예를 준 뒤 강제로 끝낸다. 유틸리티 타임아웃과 워치독이 공유한다.
void terminateChild(LaunchedChild& child, DWORD graceMs) {
    if (!child.process.valid()) return;
    if (WaitForSingleObject(child.process.get(), 0) == WAIT_OBJECT_0) return;
    if (child.ownProcessGroup) {
        (void)GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, child.pid);
        if (WaitForSingleObject(child.process.get(), graceMs) == WAIT_OBJECT_0) return;
    }
    if (child.job.valid()) {
        (void)TerminateJobObject(child.job.get(), 1);
    } else {
        (void)TerminateProcess(child.process.get(), 1);
    }
}

[[nodiscard]] int exitCodeOf(HANDLE process) {
    DWORD code = 0;
    // **`WAIT_OBJECT_0` 뒤에만 읽는다** — 그러지 않으면 STILL_ACTIVE(259)를
    // 정상 종료 코드로 오인한다(§9.1).
    if (WaitForSingleObject(process, 0) != WAIT_OBJECT_0) return 259;
    if (GetExitCodeProcess(process, &code) == 0) return -1;
    return static_cast<int>(code);
}

[[nodiscard]] ChildHandles toOwnershipView(const LaunchedChild& child) {
    ChildHandles view;
    view.process = child.process.get();
    view.job = child.job.get();
    view.pid = child.pid;
    view.ownProcessGroup = child.ownProcessGroup;
    return view;
}

[[nodiscard]] LaunchStatus toLaunchStatus(ProcessOwnership::SessionError error) {
    switch (error) {
        case ProcessOwnership::SessionError::None:
            return LaunchStatus::Ok;
        case ProcessOwnership::SessionError::Busy:
            return LaunchStatus::Busy;
        case ProcessOwnership::SessionError::Cancelled:
            return LaunchStatus::Cancelled;
    }
    return LaunchStatus::Busy;
}

}  // namespace

std::wstring buildEnvironmentBlock(
    const std::vector<std::pair<std::wstring, std::wstring>>& overrides) {
    std::vector<std::pair<std::wstring, std::wstring>> entries;

    LPWCH parent = GetEnvironmentStringsW();
    if (parent != nullptr) {
        for (LPWCH cursor = parent; *cursor != L'\0';) {
            const std::wstring_view entry{cursor};
            cursor += entry.size() + 1;
            // `=C:=C:\...` 형태의 드라이브별 현재 디렉터리는 이름이 '=' 로
            // 시작한다. 그대로 넘긴다 — CRT 가 쓴다.
            const std::size_t split = entry.find(L'=', 1);
            if (split == std::wstring_view::npos) continue;
            entries.emplace_back(std::wstring{entry.substr(0, split)},
                                 std::wstring{entry.substr(split + 1)});
        }
        FreeEnvironmentStringsW(parent);
    }

    for (const auto& [name, value] : overrides) {
        const auto match = std::find_if(entries.begin(), entries.end(), [&](const auto& existing) {
            return sameWindowsPath(existing.first, name);
        });
        if (match != entries.end()) {
            match->second = value;
        } else {
            entries.emplace_back(name, value);
        }
    }

    std::wstring block;
    for (const auto& [name, value] : entries) {
        block.append(name);
        block.push_back(L'=');
        block.append(value);
        block.push_back(L'\0');
    }
    block.push_back(L'\0');
    return block;
}

std::string sanitizeUtf8(std::string_view raw) {
    std::string out;
    out.reserve(raw.size());
    std::size_t i = 0;
    const auto isContinuation = [&](std::size_t index) {
        return index < raw.size() && (static_cast<unsigned char>(raw[index]) & 0xC0u) == 0x80u;
    };
    while (i < raw.size()) {
        const unsigned char lead = static_cast<unsigned char>(raw[i]);
        std::size_t length = 0;
        unsigned int codepoint = 0;
        if (lead < 0x80u) {
            length = 1;
            codepoint = lead;
        } else if ((lead & 0xE0u) == 0xC0u) {
            length = 2;
            codepoint = lead & 0x1Fu;
        } else if ((lead & 0xF0u) == 0xE0u) {
            length = 3;
            codepoint = lead & 0x0Fu;
        } else if ((lead & 0xF8u) == 0xF0u) {
            length = 4;
            codepoint = lead & 0x07u;
        }
        bool valid = length != 0 && i + length <= raw.size();
        for (std::size_t k = 1; valid && k < length; ++k) {
            if (!isContinuation(i + k)) {
                valid = false;
                break;
            }
            codepoint = (codepoint << 6) | (static_cast<unsigned char>(raw[i + k]) & 0x3Fu);
        }
        if (valid && length > 1) {
            // 과장 인코딩과 서로게이트, 범위 밖을 거른다.
            const bool overlong = (length == 2 && codepoint < 0x80u) ||
                                  (length == 3 && codepoint < 0x800u) ||
                                  (length == 4 && codepoint < 0x10000u);
            const bool surrogate = codepoint >= 0xD800u && codepoint <= 0xDFFFu;
            if (overlong || surrogate || codepoint > 0x10FFFFu) valid = false;
        }
        if (!valid) {
            out += "\xEF\xBF\xBD";  // U+FFFD
            ++i;
            continue;
        }
        out.append(raw.substr(i, length));
        i += length;
    }
    return out;
}

UtilityOutcome runUtility(const std::filesystem::path& executable,
                          const std::vector<std::string>& args,
                          const std::wstring& environmentBlock,
                          Duration timeout,
                          ProcessOwnership& ownership,
                          bool ownedByScanSession) {
    UtilityOutcome outcome;

    AnonymousPipe outPipe;
    AnonymousPipe errPipe;
    if (!makeOutputPipe(outPipe) || !makeOutputPipe(errPipe)) {
        outcome.status = LaunchStatus::LaunchFailed;
        outcome.launchError = "파이프를 만들 수 없습니다: " + formatLastError(GetLastError());
        return outcome;
    }
    Handle nul = openNulForReading();

    LaunchedChild child;
    if (!launchChild(executable, args, environmentBlock, outPipe.childEnd.get(),
                     errPipe.childEnd.get(), nul.get(), child, outcome.launchError)) {
        outcome.status = LaunchStatus::LaunchFailed;
        return outcome;
    }

    const LaunchStatus adopted = toLaunchStatus(ownership.adoptChild(toOwnershipView(child),
                                                                     ownedByScanSession));
    if (adopted != LaunchStatus::Ok) {
        terminateChild(child, 0);
        outcome.status = adopted;
        return outcome;
    }

    // **자식용 쓰기 끝을 지금 닫는다.** 붙들고 있으면 EOF 가 오지 않는다(§3).
    outPipe.childEnd.reset();
    errPipe.childEnd.reset();
    nul.reset();

    std::string stdoutRaw;
    std::string stderrRaw;
    // stdout 과 stderr 를 **동시에** 읽는다. 순차로 읽으면 한쪽 버퍼가 차서
    // 자식이 블록하고 다른 쪽 EOF 가 영원히 오지 않는다(§3.1).
    std::thread stdoutThread([&] {
        drainPipe(outPipe.parentEnd.get(), [&](std::string_view chunk) { stdoutRaw.append(chunk); });
    });
    std::thread stderrThread([&] {
        drainPipe(errPipe.parentEnd.get(), [&](std::string_view chunk) { stderrRaw.append(chunk); });
    });

    const auto milliseconds = timeout.count() <= 0
                                  ? 0
                                  : static_cast<DWORD>(std::min<long long>(timeout.count(), INFINITE - 1));
    if (WaitForSingleObject(child.process.get(), milliseconds) == WAIT_TIMEOUT) {
        outcome.timedOut = true;
        terminateChild(child, kTimeoutGraceMs);
        WaitForSingleObject(child.process.get(), INFINITE);
    }

    stdoutThread.join();
    stderrThread.join();

    outcome.exitCode = exitCodeOf(child.process.get());
    outcome.stdoutText = sanitizeUtf8(stdoutRaw);
    outcome.stderrText = sanitizeUtf8(stderrRaw);
    outcome.cancelled = ownership.cancellationRequested();

    ownership.releaseChild(child.process.get());
    if (!ownedByScanSession) ownership.clearUtilityCancellation();
    return outcome;
}

AcquisitionRun runAcquisition(const std::filesystem::path& executable,
                              const std::vector<std::string>& args,
                              const std::wstring& environmentBlock,
                              const std::filesystem::path& outputPath,
                              Duration firstProgressTimeout,
                              Duration stallTimeout,
                              bool useWatchdog,
                              ProgressTracker& tracker,
                              const ProgressSink& onProgress,
                              ProcessOwnership& ownership) {
    AcquisitionRun run;

    Handle outputFile = openValidatedOutputFile(outputPath, run.launchError);
    if (!outputFile.valid()) {
        run.status = LaunchStatus::LaunchFailed;
        return run;
    }

    AnonymousPipe errPipe;
    if (!makeOutputPipe(errPipe)) {
        run.status = LaunchStatus::LaunchFailed;
        run.launchError = "파이프를 만들 수 없습니다: " + formatLastError(GetLastError());
        return run;
    }
    Handle nul = openNulForReading();

    LaunchedChild child;
    if (!launchChild(executable, args, environmentBlock, outputFile.get(), errPipe.childEnd.get(),
                     nul.get(), child, run.launchError)) {
        run.status = LaunchStatus::LaunchFailed;
        return run;
    }

    const LaunchStatus adopted =
        toLaunchStatus(ownership.adoptChild(toOwnershipView(child), /*requiresScanSession=*/true));
    if (adopted != LaunchStatus::Ok) {
        terminateChild(child, 0);
        run.status = adopted;
        return run;
    }

    // 부모 쪽 복사본을 닫는다. 출력 파일은 자식이 쓴다.
    errPipe.childEnd.reset();
    outputFile.reset();
    nul.reset();

    AcquisitionWatchdog watchdog;
    if (useWatchdog) {
        watchdog.start(firstProgressTimeout, stallTimeout,
                       [&child] { terminateChild(child, kTimeoutGraceMs); });
    }

    drainPipe(errPipe.parentEnd.get(), [&](std::string_view chunk) {
        const ProgressTracker::Update update = tracker.append(chunk);
        if (update.fraction && onProgress) onProgress(*update.fraction);
        if (update.madeProgress) watchdog.markProgress();
    });

    WaitForSingleObject(child.process.get(), INFINITE);
    const AcquisitionWatchdog::Result watchdogResult = watchdog.finish();

    run.exitCode = exitCodeOf(child.process.get());
    run.madeProgress = watchdogResult.observedProgress;
    run.timeoutKind = watchdogResult.kind;
    run.cancelled = ownership.cancellationRequested();

    ownership.releaseChild(child.process.get());
    return run;
}

}  // namespace negaflow::process
