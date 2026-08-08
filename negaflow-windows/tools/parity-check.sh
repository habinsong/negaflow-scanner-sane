#!/usr/bin/env bash
# Swift 구현과 C++ 구현이 같은 입력에 같은 판정을 내는지 확인한다.
#
# **저장소의 실제 Swift 코드를 링크한다.** 소스를 복사하지 않는다 —
# 복사본을 두면 원본이 바뀌어도 파리티가 통과해버린다.
#
# macOS 에서 돌린다(Swift 툴체인 필요). Windows 장비는 필요 없다.
# 골든 픽스처 corpus(M1)가 생기면 이 스크립트는 러너로 대체된다.
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

command -v swiftc >/dev/null || { echo "swiftc 가 필요하다(macOS 에서 실행)"; exit 2; }
command -v c++    >/dev/null || { echo "C++ 컴파일러가 필요하다"; exit 2; }

# --- Swift 쪽 --------------------------------------------------------------
# internal 심볼(SaneOptionDump, SANEBackend.parseDeviceList …)에 접근하려면
# -enable-testing 으로 빌드된 모듈이 필요하다.
echo "swift build (-enable-testing) …" >&2
( cd "$ROOT" && swift build -Xswiftc -enable-testing >/dev/null )

BUILD_DIR="$(find "$ROOT/.build" -maxdepth 2 -type d -name debug -path '*apple-macos*' | head -1)"
[ -n "$BUILD_DIR" ] || { echo "빌드 산출물을 찾지 못했다"; exit 2; }

MODULES="$BUILD_DIR/Modules"
OBJ_DIR="$BUILD_DIR/SANEPluginCore.build"
[ -d "$OBJ_DIR" ] || { echo "SANEPluginCore 오브젝트를 찾지 못했다: $OBJ_DIR"; exit 2; }

# WireProtocol.swift 는 SANEPluginCore 가 아니라 **실행 파일 타깃**에 있어
# @testable import 로 닿지 않는다. 그래서 그 파일을 여기 함께 컴파일한다 —
# **저장소의 실제 파일이다.** 복사본을 두면 원본이 바뀌어도 파리티가 통과한다.
#
# 파일이 둘 이상이면 Swift 는 최상위 코드를 `main.swift` 에서만 허용한다.
# 그래서 **하네스 쪽만** main.swift 로 복사한다 — 하네스는 검증 대상이 아니고
# 매 실행마다 저장소에서 새로 복사되므로 낡을 수 없다.
cp "$ROOT/windows/tools/parity_reference.swift" "$WORK/main.swift"
swiftc -enable-testing -I "$MODULES" \
    -o "$WORK/swift_dump" \
    "$WORK/main.swift" \
    "$ROOT/Sources/negaflow-scanner-sane/WireProtocol.swift" \
    $(find "$OBJ_DIR" -name '*.o') \
    -framework CoreImage -framework CoreGraphics -framework ImageIO

# --- C++ 쪽 ----------------------------------------------------------------
# src/ 아래 .cpp 를 전부 넣는다. 모듈을 추가할 때 이 스크립트를 고치는 것을
# 잊어서 링크 오류가 나는 일을 막는다.
#
# **-ffp-contract=off 가 필수다.** clang 은 C++ 에서 기본이 -ffp-contract=on
# 이라 `a + b * c` 를 FMA 한 명령으로 축약한다. 중간 반올림이 사라져 정확도는
# 올라가지만 **결과가 달라진다.** CMakeLists 는 이미 이 플래그를 걸고 있으므로,
# 여기서 빠지면 파리티가 실제 빌드와 다른 산술을 검증하게 된다.
# 실제로 imaging/align 을 붙이자마자 mix()/휘도 가중합에서 1 ULP 차이로 터졌다.
# 근거: docs/04-imaging/numerical-parity.md §2.2 "컴파일러 최적화"
#
# MSVC 쪽 짝은 `/fp:precise` **가 아니라** `#pragma fp_contract(off)` 다.
# `/fp:precise` 의 기본 축약이 VS 2019 에서는 켜져 있다(2026-08-05 조사).
# CMakeLists 가 `/FI src/util/msvc_fp_contract.h` 로 모든 TU 에 강제 포함한다.
#
# libtiff 가 있으면 imaging/tiff_io 까지 대조한다. 없으면 그 블록을 양쪽 다
# 건너뛴다 — 한쪽만 건너뛰면 diff 가 줄 수 불일치로 터진다.
TIFF_FLAGS=()
TIFF_EXCLUDE=()
if pkg-config --exists libtiff-4 2>/dev/null; then
    TIFF_FLAGS=(-DNEGAFLOW_HAVE_LIBTIFF=1 $(pkg-config --cflags --libs libtiff-4))
    export PARITY_TIFF=1
    echo "libtiff 감지 — TIFF 입출력도 대조한다" >&2
else
    # **소스 목록에서도 빼야 한다.** tiff_io.cpp 는 <tiffio.h> 를 무조건
    # 포함하므로, 플래그만 빼면 컴파일이나 링크에서 터진다.
    # (2026-08-05: brew 가 pkgconf 를 자동 정리해 pkg-config 가 사라지자
    #  실제로 이 경로로 들어와 링크가 깨졌다.)
    TIFF_EXCLUDE=(-not -name 'tiff_io.cpp')
    echo "libtiff 없음 — TIFF 블록을 건너뛴다 (brew install libtiff pkgconf)" >&2
fi

# RapidJSON 은 헤더 온리라 pkg-config 가 없다. 헤더를 직접 찾는다.
# **-isystem 이다** — 1.1.0 헤더가 clang 경고를 내는데 여기는 -Werror 가 없어도
# CMake 쪽과 같은 취급을 해야 양쪽 빌드가 같은 것을 컴파일한다.
RJ_FLAGS=()
RJ_EXCLUDE=()
RJ_DIR=""
for candidate in /opt/homebrew/include /usr/local/include /usr/include; do
    if [ -f "$candidate/rapidjson/reader.h" ]; then RJ_DIR="$candidate"; break; fi
done
if [ -n "$RJ_DIR" ]; then
    RJ_FLAGS=(-DNEGAFLOW_HAVE_RAPIDJSON=1 -isystem "$RJ_DIR")
    export PARITY_RAPIDJSON=1
    echo "RapidJSON 감지 — 요청 JSON 디코딩도 대조한다" >&2
else
    # 헤더가 없으면 parse.cpp 를 목록에서 뺀다. 양쪽 덤프가 같은 블록을
    # 건너뛰어야 diff 가 줄 수 불일치로 터지지 않는다.
    RJ_EXCLUDE=(-not -name 'parse.cpp')
    echo "RapidJSON 없음 — wire/parse 블록을 건너뛴다 (brew install rapidjson)" >&2
fi

c++ -std=c++20 -O2 -ffp-contract=off -I"$ROOT/windows/src" -o "$WORK/cpp_dump" \
    $(find "$ROOT/windows/src" -name '*.cpp' \
        "${TIFF_EXCLUDE[@]+"${TIFF_EXCLUDE[@]}"}" \
        "${RJ_EXCLUDE[@]+"${RJ_EXCLUDE[@]}"}") \
    "$ROOT/windows/tests/parity_dump.cpp" \
    "${TIFF_FLAGS[@]+"${TIFF_FLAGS[@]}"}" \
    "${RJ_FLAGS[@]+"${RJ_FLAGS[@]}"}"

# TIFF 상호운용은 **양방향**으로 본다. 한쪽이 쓴 파일을 다른 쪽이 읽어야 한다.
#
#   1회차 C++   cpp_write.tiff 를 만든다 (출력은 버린다)
#   Swift       swift_write.tiff 를 만들고 cpp_write.tiff 를 읽는다
#   2회차 C++   swift_write.tiff 를 읽는다
#
# C++ 은 결정적이고 부작용이 파일 쓰기뿐이라 두 번 돌려도 같은 출력을 낸다.
export PARITY_TMP="$WORK"
[ -n "${PARITY_TIFF:-}" ] && "$WORK/cpp_dump" > /dev/null

"$WORK/swift_dump" > "$WORK/swift.txt"
"$WORK/cpp_dump"   > "$WORK/cpp.txt"

LINES="$(wc -l < "$WORK/cpp.txt" | tr -d ' ')"

# --- 비교 ------------------------------------------------------------------
#
# crlf.depth 는 **의도적으로 다르다.** Swift 는 "\r\n" 을 한 Character 로
# 보아 줄 분리를 하지 못하고 첫 옵션만 남긴다. C++ 는 바이트 단위로 나눠
# 정상 파싱한다. 이 divergence 는 문서화돼 있다.
# 근거: docs/02-frontend-contract/option-dump-parser.md §2.2.1
KNOWN_DIVERGENCE="crlf.depth"

if diff -q "$WORK/swift.txt" "$WORK/cpp.txt" >/dev/null; then
    echo "parity: 완전 일치 ($LINES 줄)"
    echo "경고: 알려진 CRLF divergence 가 사라졌다."
    echo "      Swift 가 고쳐졌다면 이 스크립트와 §2.2.1 을 갱신한다."
    exit 0
fi

UNEXPECTED="$(diff "$WORK/swift.txt" "$WORK/cpp.txt" | grep -E '^[<>]' | grep -v "$KNOWN_DIVERGENCE" || true)"
if [ -z "$UNEXPECTED" ]; then
    echo "parity: 통과 — $LINES 줄 중 문서화된 divergence 1건 외에 차이 없음"
    diff "$WORK/swift.txt" "$WORK/cpp.txt" || true
    exit 0
fi

echo "parity: 실패 — 문서화되지 않은 차이가 있다"
diff "$WORK/swift.txt" "$WORK/cpp.txt" || true
exit 1
