// negaflow-scanner-sane — Windows adapter
// wire/emitter — 이벤트 줄을 만든다. **쓰지는 않는다.**
//
// 이식 원본: Sources/negaflow-scanner-sane/main.swift (ProtocolV2Emitter)
// 정본 문서: docs/05-protocol/wire-contract.md §5.3, §5.4
//            docs/05-protocol/encoding-and-json.md §4
//
// ## 이 모듈에는 **파리티가 없다** — 이유를 적어 둔다
//
// 지금까지 모든 모듈은 Swift 원본과 대조했다. 이것만 못 한다.
// `ProtocolV2Emitter` 가 `main.swift` 안의 `private` 클래스이고, 그 파일은
// 최상위 코드와 서브커맨드 디스패치를 갖고 있어 파리티 바이너리에 넣을 수
// 없다. `WireProtocol.swift` 때 쓴 "파일을 컴파일 줄에 넣는다"가 통하지 않는다.
//
// **다만 잃은 것은 크지 않다.** 이 클래스가 하는 일 넷 중 셋이 이미
// 다른 경로로 대조된다.
//
// ```text
// 이벤트 객체 구성   → wire/event 가 파리티로 대조   ✅
// JSON 인코딩        → wire/json 이 파리티로 대조    ✅
// sequence 규율      → 여기. 단위 테스트만           ⬜
// 줄 프레이밍        → 여기. 단위 테스트만           ⬜
// ```
//
// 남은 둘은 규칙이 한 줄씩이라("0부터 1씩", "객체 + 0x0A 하나") 단위 테스트로
// 고정할 수 있다. 그래도 **파리티가 없다는 사실 자체는 기록해 둔다** —
// 다음 사람이 "여기도 대조되고 있겠지"라고 가정하지 않도록.
//
// ## 왜 쓰기(write)를 여기서 하지 않는가
//
// stdout 바이너리 모드 설정과 `WriteFile` 부분 쓰기 처리는 Win32 다.
// 줄을 **만드는** 것과 **내보내는** 것을 나누면 앞쪽이 순수해져 테스트된다.
// `process/` 를 순수/Win32 로 나눈 것과 같은 이유다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstdint>
#include <optional>
#include <string>

#include "wire/event.h"

namespace negaflow::wire {

/// 한 요청 동안의 이벤트 줄을 만든다.
///
/// **`sequence` 를 소유한다.** 0부터 1씩 증가하며, 이 객체 밖에서 값을
/// 정하지 않는다. 여러 곳에서 매기면 건너뛰거나 중복된다.
///
/// **스레드 안전하지 않다.** macOS 는 `NSLock` 으로 직렬화하는데, 그것은
/// 진행률 스레드와 주 스레드가 같은 emitter 를 쓰기 때문이다. Windows 에서
/// 같은 구조가 되면 호출자가 잠근다 — 순수하게 유지하려고 여기에 락을 두지
/// 않았다. **혼자 쓰는 것이 아니면 반드시 감싼다.**
class EventEmitter {
public:
    /// `requestID` 는 요청에서 받은 문자열을 **그대로** 반사한다.
    ///
    /// 파싱해서 재직렬화하지 않는다 — Swift `UUID` 는 대문자로,
    /// Windows `Guid.ToString()` 은 소문자로 쓴다. 받은 것을 그대로 돌려주면
    /// 그 차이가 애초에 생기지 않는다(D-12).
    explicit EventEmitter(std::string requestID) : requestID_(std::move(requestID)) {}

    /// 다음 이벤트 줄. **JSON + `\n` 이 한 문자열이다.**
    ///
    /// 한 번의 쓰기로 내보내기 위해서다 — 두 번 나눠 쓰면 다른 스레드가
    /// 사이에 끼어들어 줄이 섞인다.
    ///
    /// NaN/Inf 가 값에 들어 있으면 nullopt 이고 **sequence 는 소비되지 않는다.**
    /// 인코딩에 실패한 이벤트는 나가지 않았으므로 번호를 쓰면 구멍이 생긴다.
    [[nodiscard]] std::optional<std::string> emit(ScanEventV2 event);

    /// 다음에 쓸 번호. 검사와 진단용.
    [[nodiscard]] std::uint64_t nextSequence() const noexcept { return nextSequence_; }

private:
    std::string requestID_;
    std::uint64_t nextSequence_ = 0;
};

/// `ScannerError.errorDescription` 과 같은 형태의 error 이벤트.
///
/// **error 이벤트는 5개 키가 전부다.** `type` / `protocolVersion` /
/// `requestID` / `sequence` / `message`. 나머지 옵셔널은 전부 nil 이므로
/// 생략된다. 여기에 필드를 더하면 macOS 와 다른 JSON 이 된다.
/// 근거: docs/05-protocol/wire-contract.md §5.7
[[nodiscard]] ScanEventV2 makeErrorEvent(std::string message);

}  // namespace negaflow::wire
