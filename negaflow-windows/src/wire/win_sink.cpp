// SPDX-License-Identifier: GPL-2.0-or-later

#include "wire/win_sink.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <fcntl.h>
#include <io.h>
#include <stdio.h>

#include <algorithm>

namespace negaflow::wire {

namespace {

void makeStandardStreamsBinaryOnce() {
    static const bool done = [] {
        (void)_setmode(_fileno(stdout), _O_BINARY);
        (void)_setmode(_fileno(stderr), _O_BINARY);
        return true;
    }();
    (void)done;
}

}  // namespace

StdoutSink::StdoutSink() : handle_(nullptr) {
    makeStandardStreamsBinaryOnce();
    handle_ = GetStdHandle(STD_OUTPUT_HANDLE);
}

WriteAttempt StdoutSink::writeSome(const char* data, std::size_t size) {
    WriteAttempt attempt;
    if (handle_ == nullptr || handle_ == INVALID_HANDLE_VALUE) {
        attempt.status = WriteAttempt::Status::Fatal;
        return attempt;
    }
    // `WriteFile` 은 DWORD 를 받는다. 한 이벤트 줄이 4 GiB 를 넘을 일은 없지만
    // 잘라서 넘기는 편이 값 자르기보다 안전하다 — 남은 것은 writeAll 이 잇는다.
    const DWORD request = static_cast<DWORD>(std::min<std::size_t>(size, 1u << 20));
    DWORD written = 0;
    if (WriteFile(static_cast<HANDLE>(handle_), data, request, &written, nullptr) == 0) {
        const DWORD error = GetLastError();
        // 읽는 쪽이 사라진 것은 **오류가 아니라 EOF 다.** 호스트가 먼저 끝냈다.
        if (error == ERROR_BROKEN_PIPE || error == ERROR_NO_DATA) {
            attempt.status = WriteAttempt::Status::BrokenPipe;
        } else if (error == ERROR_NOT_ENOUGH_MEMORY || error == ERROR_IO_PENDING) {
            attempt.status = WriteAttempt::Status::Retryable;
        } else {
            attempt.status = WriteAttempt::Status::Fatal;
        }
        return attempt;
    }
    attempt.written = written;
    attempt.status = WriteAttempt::Status::Ok;
    return attempt;
}

void writeDiagnostic(std::string_view text) {
    makeStandardStreamsBinaryOnce();
    HANDLE handle = GetStdHandle(STD_ERROR_HANDLE);
    if (handle == nullptr || handle == INVALID_HANDLE_VALUE) return;
    std::size_t offset = 0;
    while (offset < text.size()) {
        const DWORD request =
            static_cast<DWORD>(std::min<std::size_t>(text.size() - offset, 1u << 20));
        DWORD written = 0;
        if (WriteFile(handle, text.data() + offset, request, &written, nullptr) == 0) return;
        if (written == 0) return;
        offset += written;
    }
}

}  // namespace negaflow::wire
