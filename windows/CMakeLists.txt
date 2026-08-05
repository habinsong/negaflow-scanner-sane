# negaflow-scanner-sane — Windows adapter
# SPDX-License-Identifier: GPL-2.0-or-later
#
# 근거 문서: windows_docs/06-build/toolchain-and-layout.md §4
#            windows_docs/06-build/language-decision.md  (D-13: C++20)

cmake_minimum_required(VERSION 3.25)
project(negaflow-scanner-sane-windows CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# 경고를 오류로 — **타깃 속성으로 건다**(CMake 3.24+).
#
# `add_compile_options(/WX)` / `-Werror` 로 박아 두면 빠져나갈 방법이 없다.
# 이쪽은 `cmake --compile-no-warning-as-error` 라는 탈출구가 있고, 타깃별로
# 끌 수도 있다. **타깃 생성 시점에 읽히므로 add_library 보다 먼저 와야 한다.**
set(CMAKE_COMPILE_WARNING_AS_ERROR ON)

if(MSVC)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    add_compile_options(
        /W4
        /permissive-
        /fp:precise          # /fp:fast 는 절대 금지 — parity 가 깨진다.
                             # **이것만으로는 FMA 축약이 안 꺼진다** — 아래 /FI 를 볼 것.
        /Zc:__cplusplus
        /Zc:preprocessor
        /guard:cf            # Control Flow Guard
        /GS                  # 버퍼 보안 검사
        /sdl                 # 추가 보안 검사. **함정이 있다** — 아래 §외부 헤더
        /utf-8
    )

    # --- 외부 헤더가 정말로 /external 로 취급되는지 확인한다 ----------------
    #
    # `target_include_directories(... SYSTEM ...)` 는 MSVC 에서
    # `/external:I` 로 번역되고, **CMake 가 `/external:W0` 을 자동으로 붙인다**
    # (Modules/Compiler/MSVC.cmake 의 `CMAKE_INCLUDE_SYSTEM_FLAG_CXX_WARNING`).
    # 그러므로 `/external:W0` 을 손으로 적을 필요가 없다.
    #
    # **다만 조건이 맞지 않으면 CMake 는 그냥 `/I` 를 쓴다 — 조용히.**
    # 그러면 RapidJSON 헤더 경고가 그대로 오류가 되어 빌드가 깨진다.
    # 필요 조건은 둘이다.
    #
    #   MSVC   >= 19.29.30036.3   (VS 2019 16.11. /external:I 가 실험 딱지를 뗀 시점)
    #   CMake  >= 3.22 (Ninja/NMake) 또는 >= 3.24 (Visual Studio 생성기)
    #
    # 조용히 나빠지는 것을 막으려고 여기서 멈춘다. **원인 없이 실패하지 않게.**
    if(NOT CMAKE_INCLUDE_SYSTEM_FLAG_CXX)
        message(FATAL_ERROR
            "이 MSVC/CMake 조합은 SYSTEM 인클루드를 /external:I 로 번역하지 못한다.\n"
            "  MSVC   = ${CMAKE_CXX_COMPILER_VERSION} (필요: >= 19.29.30036.3)\n"
            "  CMake  = ${CMAKE_VERSION} (필요: >= 3.24)\n"
            "  생성기 = ${CMAKE_GENERATOR}\n"
            "그대로 두면 RapidJSON 헤더 경고가 /WX 에 걸려 빌드가 깨진다.")
    endif()

    # --- FMA 축약을 끈다 (D-11) --------------------------------------------
    #
    # `/fp:precise` 의 기본 `fp_contract` 는 **VS 버전에 따라 다르다**
    # (2026-08-05 조사, MSVC 문서 + MSVC 팀 블로그):
    #
    #   VS 2019 이하    on   ← 축약이 일어난다. ARM64 는 스칼라까지
    #   VS 2022 17.0+   off
    #
    # `/fp:contract-` 라는 플래그는 **없다**(켜는 형태만 있다). `/fp:strict` 는
    # 축약을 끄지만 예외 처리까지 켜서 대가가 크다. 두 버전과 두 아키텍처에서
    # 모두 통하는 것은 `#pragma fp_contract(off)` 하나뿐이다.
    #
    # **강제 포함(`/FI`)으로 넣는다.** 어느 파일이 부동소수점에 민감한지를
    # 사람이 판단해 헤더를 넣게 하면 언젠가 빠뜨린다 — 그리고 빠뜨려도
    # 빌드는 통과하고 결과만 조용히 달라진다.
    #
    # 근거: windows/src/util/msvc_fp_contract.h (전체 설명)
    #       windows_docs/04-imaging/numerical-parity.md §5
    add_compile_options(/FI"${CMAKE_CURRENT_SOURCE_DIR}/src/util/msvc_fp_contract.h")
    # /OPT:REF 와 /OPT:ICF 는 **Debug 에서 제외한다.** Debug 의 기본
    # /INCREMENTAL 과 양립하지 않아 링커가 LNK4075 로 증분 링크를 조용히
    # 버리고, ICF 는 같은 코드의 함수를 합쳐 스택 추적을 흐린다.
    # 릴리스에서만 켜면 둘 다 없다.
    add_link_options(
        /DYNAMICBASE /NXCOMPAT /HIGHENTROPYVA
        /DEBUG
        $<$<NOT:$<CONFIG:Debug>>:/OPT:REF>
        $<$<NOT:$<CONFIG:Debug>>:/OPT:ICF>
    )
else()
    # macOS/Linux 에서의 개발·검증용. 정식 대상은 MSVC 다.
    # 순수 로직은 플랫폼 독립이므로 여기서 먼저 테스트할 수 있다.
    add_compile_options(
        -Wall -Wextra -Wpedantic
        -ffp-contract=off    # FMA 자동 축약 금지. D-11.
                             # MSVC 짝은 /fp:precise 가 아니라 #pragma fp_contract(off) 다.
    )
endif()

# --- sane_logic: 순수 로직. 의존 0. -----------------------------------------
#
# 이 타깃은 Win32 도 libtiff 도 링크하지 않는다. 그것이 계약이다.
# <windows.h> 가 들어가면 빌드가 깨지도록 유지한다.
# 근거: toolchain-and-layout.md §4.1, porting-map.md §1

add_library(sane_logic STATIC
    src/util/numeric.cpp
    src/sane/option_dump.cpp
    src/sane/device_list.cpp
    src/sane/capabilities.cpp
    src/sane/media.cpp
    src/sane/validate.cpp
    src/sane/args.cpp
)

# --- process_logic: process/ 계층의 **순수** 부분 --------------------------
#
# Win32 를 포함하지 않는다. 진행률 파싱·stderr 분류·타임아웃 예산·명령줄 조립은
# 전부 순수 판정이므로 macOS 에서도 테스트할 수 있다.
# CreateProcessW/Job Object 는 별도 타깃(M3 후반)으로 붙인다.

add_library(process_logic STATIC
    src/process/progress.cpp
    src/process/budget.cpp
    src/process/command_line.cpp
    src/process/acquisition.cpp
)
# --- imaging_logic: imaging/ 계층의 **순수** 부분 --------------------------
#
# libtiff 를 링크하지 않는다. 정렬과 병합은 float 배열 위의 순수 산술이므로
# macOS 에서 Swift 원본과 수치를 직접 대조할 수 있다.
# libtiff 가 필요한 imaging/tiff 는 별도 타깃으로 붙인다.
#
# **/fp:fast 나 -ffast-math 가 들어가면 이 타깃의 결과가 조용히 달라진다.**
# 근거: windows_docs/04-imaging/exposure-merge.md §7.4 (D-11)

add_library(imaging_logic STATIC
    src/imaging/align.cpp
    src/imaging/merge.cpp
    src/imaging/tiff_contract.cpp
)

target_include_directories(process_logic PUBLIC src)
target_link_libraries(process_logic PRIVATE)   # 의존 없음
target_include_directories(sane_logic PUBLIC src)
target_link_libraries(sane_logic PRIVATE)   # 의존 없음
target_include_directories(imaging_logic PUBLIC src)
# util/numeric 의 referenceExposureTime 만 쓴다(porting-map §2.7 배정).
# util/numeric 은 의존이 0 이므로 이 엣지로 Win32 나 libtiff 가 새지 않는다.
target_link_libraries(imaging_logic PUBLIC sane_logic)

# --- wire_logic: 호스트 계약의 **순수** 부분 -------------------------------
#
# 요청 검증(1단계)은 순수 판정이라 macOS 에서 Swift 원본과 대조할 수 있다.
# stdout 바이너리 모드·NDJSON 방출·프로세스 실행은 별도 계층(M5 후반)이다.
# 근거: windows_docs/06-build/porting-map.md §2.12

add_library(wire_logic STATIC
    src/wire/request.cpp
    src/wire/json.cpp
    src/wire/event.cpp
    src/wire/protocol.cpp
    src/wire/emitter.cpp
    src/wire/writer.cpp
    src/wire/cli.cpp
)
target_include_directories(wire_logic PUBLIC src)
target_link_libraries(wire_logic PUBLIC sane_logic)

# --- wire_parse: RapidJSON 을 링크하는 유일한 타깃 --------------------------
#
# `imaging_tiff` 와 같은 구조다. **wire_logic 은 여기 의존하지 않는다.**
# 방출(wire/json)이 파서 없이 서 있어야 그쪽을 macOS 에서 단독으로 대조할 수 있다.
#
# RapidJSON 은 헤더 온리(MIT)다. 수 변환은 쓰지 않고 토큰화만 쓴다 —
# 이유는 src/wire/parse.h 의 실측 표에 있다.
#
# **SYSTEM 으로 넣는 것이 중요하다.** 이 프로젝트는 -Werror 로 빌드하는데
# RapidJSON 1.1.0 헤더가 clang 에서 경고를 낸다(memcpy 캐스트 등).
# 근거: windows_docs/06-build/language-decision.md §215, toolchain-and-layout.md §3.2

find_package(RapidJSON QUIET)

if(RapidJSON_FOUND OR RAPIDJSON_INCLUDE_DIRS)
    add_library(wire_parse STATIC
        src/wire/parse.cpp
    )
    target_include_directories(wire_parse PUBLIC src)
    # SYSTEM → MSVC 에서 /external:I + /external:W0 (CMake 가 W0 을 붙인다).
    # **RapidJSON 포트는 imported target 을 내보내지 않고 변수만 준다** —
    # 그래서 여기만 SYSTEM 을 손으로 적는다.
    # (TIFF::TIFF 는 imported target 이라 CMake 3.25+ 가 자동으로 SYSTEM 처리한다.)
    # wire/snapshot 도 여기 둔다. `capabilityToken` 은 wire 필드이고 디코딩에
    # 파서가 필요하다 — **RapidJSON 을 아는 타깃이 하나라는 계약**을 지키려면
    # 별도 타깃을 만드는 것보다 이쪽이 맞다. `document.h` 는 쓰지 않는다.
    target_sources(wire_parse PRIVATE src/wire/snapshot.cpp)
    target_include_directories(wire_parse SYSTEM PRIVATE ${RAPIDJSON_INCLUDE_DIRS})
    #
    # ⚠ /sdl 이 /we4996 등을 **주입한다**(/we 는 경고 레벨과 무관하다).
    # 그래서 /external:W0 으로 막히지 않을 수 있다 — 문서로는 확인되지 않았고
    # 첫 Windows 빌드에서 판명된다. 터지면 아래 한 줄을 켠다.
    #
    #   target_compile_options(wire_parse PRIVATE /wd4996)
    #
    # 그때 **원인을 여기 적어 둔다.** 켜 놓고 이유를 안 적으면 다음 사람이
    # 지웠다가 같은 곳에서 다시 막힌다.
    target_link_libraries(wire_parse PUBLIC wire_logic sane_logic)
    set(NEGAFLOW_HAVE_RAPIDJSON ON)
else()
    message(WARNING
        "RapidJSON 을 찾지 못했다. wire/parse 를 빼고 빌드한다.\n"
        "  나머지 wire 모듈(방출·검증)은 그대로 검증된다.\n"
        "  macOS: brew install rapidjson   Windows: vcpkg 매니페스트가 처리한다")
endif()

# --- imaging_tiff: libtiff 를 링크하는 유일한 타깃 -------------------------
#
# **imaging_logic 은 여기 의존하지 않는다.** 반대 방향이다. 정렬·병합·태그
# 판정이 libtiff 없이 서 있어야 macOS 에서 Swift 원본과 수치를 대조할 수 있다.
#
# libtiff 는 이미 SANE 런타임 의존으로 배포한다(building-sane §8) — 새 의존이
# 아니다. 단 CVE 추적 대상이므로 SBOM 에 올린다.
# 근거: windows_docs/04-imaging/tiff-validation.md §2

find_package(TIFF)

if(TIFF_FOUND)
    add_library(imaging_tiff STATIC
        src/imaging/tiff_io.cpp
    )
    target_include_directories(imaging_tiff PUBLIC src)
    target_link_libraries(imaging_tiff PUBLIC imaging_logic sane_logic TIFF::TIFF)
else()
    message(WARNING
        "libtiff 를 찾지 못했다. imaging/tiff_io 를 빼고 빌드한다.\n"
        "  순수 부분(align/merge/tiff_contract)은 그대로 검증된다.\n"
        "  macOS: brew install libtiff   Windows: vcpkg 매니페스트가 처리한다")
endif()

# --- process_win32: process/ 계층의 Win32 부분 ------------------------------
#
# `watchdog` 은 Win32 를 포함하지 않지만(std::thread + condition_variable)
# `child` 와 함께 쓰이므로 같은 타깃에 둔다. 순수 판정(progress/budget/
# command_line/acquisition)은 그대로 process_logic 에 남는다 — 그쪽이
# macOS 에서 파리티로 대조되는 부분이다.

if(WIN32)
    add_library(process_win32 STATIC
        src/process/watchdog.cpp
        src/process/cancel.cpp
        src/process/child.cpp
    )
    target_include_directories(process_win32 PUBLIC src)
    target_link_libraries(process_win32 PUBLIC process_logic)

    # --- wire_win32: ByteSink 의 Win32 구현 --------------------------------
    #
    # **부분 쓰기 재개 루프는 여기 없다.** wire/writer 가 갖고 있고 테스트도
    # 그쪽에 있다. 이 타깃은 WriteFile 한 번에 대응하는 얇은 층이다.
    add_library(wire_win32 STATIC
        src/wire/win_sink.cpp
    )
    target_include_directories(wire_win32 PUBLIC src)
    target_link_libraries(wire_win32 PUBLIC wire_logic)
endif()

# --- 실행 파일 ---------------------------------------------------------------
#
# **libtiff 와 RapidJSON 이 둘 다 있어야 만든다.** 없이 만들면 스캔 결과를
# 검증하지 못하거나 요청을 파싱하지 못하는 실행 파일이 나오는데, 그것은
# "빌드가 통과했다"는 신호를 주면서 제품으로는 쓸 수 없다.

if(WIN32 AND TIFF_FOUND AND NEGAFLOW_HAVE_RAPIDJSON)
    add_executable(negaflow-scanner-sane
        src/main.cpp
        src/app/environment.cpp
        src/app/backend.cpp
    )
    target_include_directories(negaflow-scanner-sane PRIVATE src)
    target_link_libraries(negaflow-scanner-sane PRIVATE
        sane_logic
        process_logic
        process_win32
        imaging_logic
        imaging_tiff
        wire_logic
        wire_parse
        wire_win32
    )
    # 긴 경로(260자 초과) staging 을 호스트가 줄 수 있다. 매니페스트의
    # long-path 인식이 없으면 CreateFileW 가 그 경로를 열지 못한다.
    # 근거: windows_docs/03-process-and-io/child-process.md §14
    target_sources(negaflow-scanner-sane PRIVATE src/app/long_path.manifest)

    # --- 실행 파일을 실제로 돌리는 스모크 -----------------------------------
    #
    # 단위 테스트는 순수 판정을 고정한다. 여기서 보는 것은 그 밖의 것이다 —
    # 프로세스 생성, 파이프 교착, stdout 오염, detect → capabilities → scan 의
    # 토큰 연결. **가짜 scanimage 는 우리 코드를 링크하지 않는다**(§13.1).
    add_executable(virtual_scanimage tests/virtual_scanimage.cpp)

    add_test(NAME plugin_smoke
        COMMAND ${CMAKE_COMMAND}
            -DPLUGIN=$<TARGET_FILE:negaflow-scanner-sane>
            -DVSCAN=$<TARGET_FILE:virtual_scanimage>
            -DWORKDIR=${CMAKE_CURRENT_BINARY_DIR}/smoke-$<CONFIG>
            -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/plugin-smoke.cmake)
elseif(WIN32)
    message(WARNING
        "실행 파일을 만들지 않는다 — libtiff 또는 RapidJSON 이 없다.\n"
        "  vcpkg 툴체인 파일을 주고 다시 설정한다.")
endif()

# --- 테스트 -----------------------------------------------------------------

enable_testing()

add_executable(sane_logic_tests tests/test_main.cpp)
target_link_libraries(sane_logic_tests PRIVATE sane_logic process_logic imaging_logic wire_logic)
if(TIFF_FOUND)
    target_link_libraries(sane_logic_tests PRIVATE imaging_tiff)
    target_compile_definitions(sane_logic_tests PRIVATE NEGAFLOW_HAVE_LIBTIFF=1)
endif()
if(NEGAFLOW_HAVE_RAPIDJSON)
    target_link_libraries(sane_logic_tests PRIVATE wire_parse)
    target_compile_definitions(sane_logic_tests PRIVATE NEGAFLOW_HAVE_RAPIDJSON=1)
endif()
if(WIN32)
    # 워치독·진행률 누적·취소 상태 기계는 Win32 타깃에 있지만 판정 자체는
    # 순수하다. 단위 테스트가 닿는 유일한 그물이므로 여기서 링크한다.
    target_link_libraries(sane_logic_tests PRIVATE process_win32)
endif()
add_test(NAME sane_logic_tests COMMAND sane_logic_tests)

# Swift 구현과의 출력 대조용 덤퍼.
# tools/parity-check.sh 가 이것과 Swift 짝의 출력을 diff 한다.
add_executable(parity_dump tests/parity_dump.cpp)
target_link_libraries(parity_dump PRIVATE sane_logic process_logic imaging_logic wire_logic)
if(TIFF_FOUND)
    target_link_libraries(parity_dump PRIVATE imaging_tiff)
    target_compile_definitions(parity_dump PRIVATE NEGAFLOW_HAVE_LIBTIFF=1)
endif()
if(NEGAFLOW_HAVE_RAPIDJSON)
    target_link_libraries(parity_dump PRIVATE wire_parse)
    target_compile_definitions(parity_dump PRIVATE NEGAFLOW_HAVE_RAPIDJSON=1)
endif()

# --- 파리티 골든 -------------------------------------------------------------
#
# **`if(WIN32)` 로 묶지 않는다.** macOS 에서도 돌아야 "clang 과 MSVC 가 같은
# 수치를 낸다"가 성립하고, 그것이 `tools/parity-check.sh`(Swift ↔ clang)와
# 합쳐져야 "Swift 와 MSVC 가 같다"가 된다. 한쪽만 돌면 삼각형이 열려 있다.
#
# 골든에는 `PARITY_TMP` 가 필요한 TIFF 왕복 구간이 없다. 그래서 libtiff /
# RapidJSON 유무와 무관하게 같은 출력이 나온다 — 선택 의존이 빠진 환경에서도
# 이 검사는 의미를 유지한다.
add_test(NAME parity_golden
    COMMAND ${CMAKE_COMMAND}
        -DDUMP=$<TARGET_FILE:parity_dump>
        -DGOLDEN=${CMAKE_CURRENT_SOURCE_DIR}/tests/golden/parity_dump.txt
        -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/parity-golden.cmake)
