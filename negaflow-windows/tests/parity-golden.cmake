# negaflow-scanner-sane — Windows adapter
# parity-golden — `parity_dump` 출력이 골든과 같은가.
#
# 정본 문서: docs/04-imaging/numerical-parity.md
#            docs/05-protocol/conformance-fixtures.md
#
# ## 이 검사가 무엇을 증명하고 무엇을 증명하지 않는가
#
# **증명하는 것**: 이 툴체인의 `parity_dump` 출력이 골든과 같다.
# 골든은 MSVC 로 만들었으므로, macOS/clang 에서 이 테스트가 통과하면
# **두 툴체인의 수치가 같다**는 뜻이다.
#
# **증명하지 않는 것**: Swift 와 같다는 것. 그것은 `tools/parity-check.sh`
# 가 macOS 에서 실제 Swift 구현을 링크해 확인한다.
#
# 둘을 합치면 삼각형이 닫힌다.
#
# ```text
# Swift  ==  clang C++     parity-check.sh (macOS 에서 실시간)
# clang C++ == MSVC C++    이 테스트 (양쪽에서 같은 골든과 대조)
# ────────────────────────────────────────────────
# Swift  ==  MSVC C++
# ```
#
# **그래서 이 파일은 `if(WIN32)` 로 묶지 않는다.** macOS 에서도 돌아야
# 삼각형의 두 번째 변이 생긴다.
#
# ## 줄 끝을 정규화한다
#
# `parity_dump` 는 stdout 이 텍스트 모드라 Windows 에서 `\n` 이 `\r\n` 이
# 된다. 골든은 LF 로 보관하고 비교 전에 양쪽을 LF 로 맞춘다 — 그러지
# 않으면 이 테스트는 수치가 아니라 줄 끝을 재게 된다.
#
# 필요한 변수: DUMP, GOLDEN
#
# SPDX-License-Identifier: GPL-2.0-or-later

cmake_minimum_required(VERSION 3.25)

if(NOT DUMP OR NOT GOLDEN)
    message(FATAL_ERROR "DUMP / GOLDEN 이 필요하다.")
endif()

execute_process(
    COMMAND "${DUMP}"
    OUTPUT_VARIABLE actual
    ERROR_VARIABLE dump_err
    RESULT_VARIABLE dump_code)

if(NOT dump_code EQUAL 0)
    message(FATAL_ERROR "parity_dump 가 ${dump_code} 로 끝났다.\nstderr: ${dump_err}")
endif()

file(READ "${GOLDEN}" expected)

string(REPLACE "\r\n" "\n" actual "${actual}")
string(REPLACE "\r\n" "\n" expected "${expected}")

if(actual STREQUAL expected)
    string(REPLACE "\n" ";" lines "${expected}")
    list(LENGTH lines count)
    math(EXPR count "${count} - 1")
    message(STATUS "PASS  parity golden — ${count}줄 일치")
    return()
endif()

# 어디서 갈렸는지 말한다. "다르다"만 보고하면 다음 사람이 파일 두 개를
# 손으로 diff 해야 한다.
string(REPLACE "\n" ";" actual_lines "${actual}")
string(REPLACE "\n" ";" expected_lines "${expected}")
list(LENGTH actual_lines actual_count)
list(LENGTH expected_lines expected_count)

set(reported 0)
math(EXPR last "${expected_count} - 1")
foreach(index RANGE ${last})
    if(index GREATER_EQUAL actual_count)
        break()
    endif()
    list(GET expected_lines ${index} want)
    list(GET actual_lines ${index} got)
    if(NOT want STREQUAL got)
        math(EXPR line "${index} + 1")
        message("  ${line}행")
        message("    골든: ${want}")
        message("    실제: ${got}")
        math(EXPR reported "${reported} + 1")
        if(reported GREATER_EQUAL 10)
            message("  … (이하 생략)")
            break()
        endif()
    endif()
endforeach()

message(FATAL_ERROR
    "parity golden 불일치 (골든 ${expected_count}줄, 실제 ${actual_count}줄).\n"
    "수치가 갈렸으면 D-11(FMA 축약 금지)과 컴파일 플래그를 먼저 본다.\n"
    "의도한 변경이면 골든을 다시 만든다:\n"
    "  ./build/<config>/parity_dump > negaflow-windows/tests/golden/parity_dump.txt\n"
    "**다시 만들기 전에 macOS 파리티를 돌린다** — 골든만 고치면 Swift 와의\n"
    "차이가 그대로 굳는다.")
