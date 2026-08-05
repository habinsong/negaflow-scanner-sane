// SPDX-License-Identifier: GPL-2.0-or-later

#include "wire/emitter.h"

#include "wire/json.h"

namespace negaflow::wire {

std::optional<std::string> EventEmitter::emit(ScanEventV2 event) {
    event.requestID = requestID_;
    event.sequence = nextSequence_;

    // **인코딩이 먼저다.** 실패하면 번호를 소비하지 않는다 — 나가지 않은
    // 이벤트가 번호를 가져가면 호스트가 보는 sequence 에 구멍이 생기고,
    // 호스트는 그것을 이벤트 유실로 읽는다.
    //
    // 키 순서는 **선언 순서**다. 정렬은 파리티/골든 전용이다.
    auto json = writeJson(encodeScanEvent(event), KeyOrder::Declaration);
    if (!json) return std::nullopt;

    ++nextSequence_;

    // JSON 과 개행을 **한 문자열로** 돌려준다. 호출자가 한 번에 쓴다.
    json->push_back('\n');
    return json;
}

ScanEventV2 makeErrorEvent(std::string message) {
    ScanEventV2 event;
    event.type = "error";
    event.message = std::move(message);
    // 나머지는 전부 비운다. 채우면 키가 늘어나 macOS 와 형태가 갈린다.
    return event;
}

}  // namespace negaflow::wire
