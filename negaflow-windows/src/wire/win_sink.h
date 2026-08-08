// negaflow-scanner-sane — Windows adapter
// wire/win_sink — `ByteSink` 의 Win32 구현. **부분 쓰기 루프는 여기 없다.**
//
// 정본 문서: docs/05-protocol/wire-contract.md §7
//            docs/05-protocol/encoding-and-json.md §9
//
// 재개 루프는 `wire/writer` 의 `writeAll` 이 갖는다. 여기서 루프를 돌면
// 그쪽 테스트가 검증하는 것이 실제로 쓰이지 않게 된다 — `writeSome` 은
// `WriteFile` **한 번**에 대응한다(writer.h).
//
// ## stdout 을 바이너리로 고정한다
//
// `_setmode(_fileno(stdout), _O_BINARY)` 를 하지 않으면 CRT 가 `\n` 을
// `\r\n` 으로 바꾼다. 우리는 CRT 를 거치지 않고 `WriteFile` 을 쓰므로 실제
// 변환은 일어나지 않지만, 같은 프로세스에서 누가 `printf` 를 쓰면 그때
// 섞인다. 입구에서 못을 박아 둔다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstddef>
#include <string_view>

#include "wire/writer.h"

namespace negaflow::wire {

/// stdout 에 쓰는 sink. **프로토콜 전용 스트림이다**(§7).
class StdoutSink final : public ByteSink {
public:
    StdoutSink();

    [[nodiscard]] WriteAttempt writeSome(const char* data, std::size_t size) override;

private:
    void* handle_;  ///< HANDLE
};

/// stderr 진단. 사람이 읽는 것이고 호스트는 로그로만 본다.
///
/// **stdout 으로 절대 나가지 않는다.** 한 바이트라도 섞이면 호스트의 NDJSON
/// 디코딩이 깨진다.
void writeDiagnostic(std::string_view text);

}  // namespace negaflow::wire
