// negaflow-scanner-sane — Windows adapter
// wire/writer — 한 줄을 **끝까지** 내보내는 루프. Win32 호출은 주입받는다.
//
// 정본 문서: docs/05-protocol/wire-contract.md §7
//            docs/05-protocol/encoding-and-json.md §9 체크리스트 3항목
//              - 한 번의 write 로 JSON + LF
//              - 부분 쓰기 처리
//              - ERROR_BROKEN_PIPE 를 EOF 로 처리
//
// ## 이 모듈에도 **파리티가 없다** — 다만 이유가 다르다
//
// `wire/emitter` 는 Swift 짝이 `main.swift` 안에 있어서 못 닿았다(닿을 수는
// 있는데 접근이 막힌 경우다). **여기는 Swift 짝이 아예 없다.**
//
// macOS 는 `FileHandle.standardOutput.write(_:)` 한 줄이고, 부분 쓰기 재개는
// Foundation 안에서 일어난다. 대조할 우리 쪽 코드가 저쪽에는 존재하지 않는다.
//
// ```text
// wire/emitter   Swift 짝이 private 이라 못 닿는다        → 언젠가 닿을 수 있다
// wire/writer    Swift 짝이 없다 (Foundation 이 한다)     → 원리상 못 닿는다
// ```
//
// 그래서 **여기서 틀리면 아무도 못 잡는다.** 단위 테스트가 유일한 그물이고,
// 그 사실을 알고 테스트를 짰다 — 부분 쓰기·0바이트·파이프 끊김·중간 끊김.
//
// ## 왜 루프를 따로 떼어 놓는가
//
// `WriteFile` 은 **요청한 바이트를 다 쓰지 않고 돌아올 수 있다.** 파이프가
// 가득 차면 흔하다. 그 경우 남은 것을 이어서 써야 하는데, **오프셋을 잘못
// 잡으면 줄이 조용히 망가진다** — 앞부분이 두 번 나가거나 뒷부분이 사라진다.
// 호스트는 그것을 "JSON 파싱 실패"로 볼 뿐 원인을 알 수 없다.
//
// 이 루프는 순수하다. `WriteFile` 을 `ByteSink` 뒤로 밀어내면 부분 쓰기를
// **의도적으로 재현**해 검증할 수 있다. 실기에서는 재현이 어렵다.
//
// ## 한 줄은 한 번의 쓰기로 나간다 — 그래도 루프가 필요하다
//
// `wire/emitter` 가 JSON 과 `\n` 을 한 문자열로 돌려주는 것은 **다른 스레드가
// 사이에 끼어들지 못하게** 하기 위해서다(emitter.h). 그것과 "OS 가 한 번에
// 다 받아주느냐"는 별개다. 후자는 보장되지 않으므로 여기서 처리한다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstddef>
#include <string_view>

namespace negaflow::wire {

/// `WriteFile` 한 번의 결과.
struct WriteAttempt {
    enum class Status {
        /// 썼다. `written` 이 요청보다 적을 수 있다(부분 쓰기).
        Ok,
        /// 읽는 쪽이 사라졌다. `ERROR_BROKEN_PIPE` / `ERROR_NO_DATA`.
        /// **오류가 아니라 EOF 로 다룬다** — 호스트가 먼저 끝낸 것이다.
        BrokenPipe,
        /// 일시적이다. 다시 시도해 볼 수 있다.
        Retryable,
        /// 회복 불가.
        Fatal,
    };

    std::size_t written = 0;
    Status status = Status::Ok;
};

/// 바이트를 한 번 쓰려 시도하는 것. Win32 에서 `WriteFile` 하나에 대응한다.
///
/// **구현이 루프를 돌면 안 된다.** 루프는 `writeAll` 이 갖는다 — 그래야
/// 부분 쓰기 재개가 한 곳에서 검증된다.
class ByteSink {
public:
    ByteSink() = default;
    virtual ~ByteSink() = default;
    ByteSink(const ByteSink&) = delete;
    ByteSink& operator=(const ByteSink&) = delete;
    ByteSink(ByteSink&&) = delete;
    ByteSink& operator=(ByteSink&&) = delete;

    [[nodiscard]] virtual WriteAttempt writeSome(const char* data, std::size_t size) = 0;
};

/// `writeAll` 의 결과.
enum class WriteOutcome {
    /// 요청한 바이트를 전부 썼다.
    Ok,
    /// 호스트가 먼저 끝냈다. **오류로 보고하지 않는다** — 보고할 곳이 없다.
    /// 남은 이벤트를 계속 만들 이유도 없으므로 호출자는 조용히 멈춘다.
    HostGone,
    /// 실패했다. 줄이 잘렸을 수 있다.
    Failed,
};

/// 진행이 없는 시도를 몇 번까지 참을 것인가.
///
/// `Retryable` 이 계속 오거나 `Ok` 인데 `written == 0` 이 계속 오면 무한
/// 루프가 된다. **상한이 없으면 스캔이 멈춘 채 워치독만 기다리게 된다.**
/// 그 편이 조용히 도는 것보다 낫지만, 실패로 끝내는 것이 더 낫다.
inline constexpr int kDefaultMaxStalledAttempts = 64;

/// `bytes` 를 전부 쓴다. 부분 쓰기를 이어서 처리한다.
///
/// ```text
/// 빈 입력              sink 를 호출하지 않고 Ok
/// 부분 쓰기            남은 만큼 다시 쓴다. **오프셋은 누적이다**
/// written == 0 반복    maxStalledAttempts 회 뒤 Failed
/// BrokenPipe           **즉시** HostGone. 재시도하지 않는다
/// Retryable            진행 없는 시도로 센다
/// Fatal                즉시 Failed
/// ```
///
/// 일부를 쓴 뒤 파이프가 끊기면 `HostGone` 이고, **줄은 잘린 채로 나갔다.**
/// 그 상황에서 할 수 있는 것이 없다 — 호스트가 이미 읽기를 끝냈다.
[[nodiscard]] WriteOutcome writeAll(std::string_view bytes, ByteSink& sink,
                                    int maxStalledAttempts = kDefaultMaxStalledAttempts);

}  // namespace negaflow::wire
