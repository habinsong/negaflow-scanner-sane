# negaflow-scanner-sane — Windows adapter
# epson-smoke — Epson 평판(V700/V750/V800/V850)의 **인자 계약**을 고정한다.
#
# 이 계열은 OpticFilm 과 다르게 어렵다. 소스마다 지오메트리 한계가 다르고,
# 필름 종류·색 보정·감마를 인자로 받고, Windows 에서는 장치 이름이
# `epson2:usbscan:NNN` 이다. 맥에서 그 인자들 때문에 오래 고생했으므로
# Windows 에서는 실제로 나간 인자를 로그로 받아 검사한다.
#
# 실기가 없어도 되는 검사다 — 가상 scanimage 가 epson2 덤프를 흉내낸다.
#
# 필요한 변수: PLUGIN, VSCAN, WORKDIR
#
# SPDX-License-Identifier: GPL-2.0-or-later

cmake_minimum_required(VERSION 3.25)

if(NOT PLUGIN OR NOT VSCAN OR NOT WORKDIR)
    message(FATAL_ERROR "PLUGIN / VSCAN / WORKDIR 이 필요하다.")
endif()

file(REMOVE_RECURSE "${WORKDIR}")
file(MAKE_DIRECTORY "${WORKDIR}")
file(TO_NATIVE_PATH "${WORKDIR}/args.log" ARGLOG)

set(ENV{NEGAFLOW_SCANIMAGE_PATH} "${VSCAN}")
set(ENV{NEGAFLOW_VSCAN_SCENARIO} "epson")
set(ENV{NEGAFLOW_VSCAN_ARGLOG} "${ARGLOG}")

# 조건은 **개별 인자로** 받는다. 한 문자열로 넘기면 `if()` 가 변수 이름
# 하나로 보고 언제나 거짓이 된다 — 그러면 모든 검사가 조용히 통과한다.
function(expect name)
    if(${ARGN})
        message(STATUS "PASS  ${name}")
    else()
        message(SEND_ERROR "FAIL  ${name}  (${ARGN})")
    endif()
endfunction()

# --- ① detect ---------------------------------------------------------------

execute_process(
    COMMAND "${PLUGIN}" detect
    OUTPUT_VARIABLE detect_out
    ERROR_VARIABLE detect_err
    RESULT_VARIABLE detect_code)

if(NOT detect_code EQUAL 0)
    message(FATAL_ERROR "detect 가 ${detect_code} 로 끝났다.\nstderr: ${detect_err}")
endif()

string(FIND "${detect_out}" "\"id\":\"sane-epson2:usbscan:001\"" found_id)
expect("Windows 장치 이름 epson2:usbscan:NNN 을 그대로 낸다" found_id GREATER -1)

# still-image 클래스 드라이버로 열린 장치도 USB 다. `:libusb:` 만 보면
# 내부 버스로 잘못 분류한다.
string(FIND "${detect_out}" "\"connectionType\":\"usb\"" found_usb)
expect("usbscan 장치를 USB 로 분류한다" found_usb GREATER -1)

string(FIND "${detect_out}" "\"driverVersion\":\"epson2 (SANE)\"" found_driver)
expect("백엔드를 epson2 로 보고한다" found_driver GREATER -1)

# --- ② capabilities ---------------------------------------------------------

execute_process(
    COMMAND "${PLUGIN}" capabilities "sane-epson2:usbscan:001"
    OUTPUT_VARIABLE caps_out
    ERROR_VARIABLE caps_err
    RESULT_VARIABLE caps_code)

if(NOT caps_code EQUAL 0)
    message(FATAL_ERROR "capabilities 가 ${caps_code} 로 끝났다.\nstderr: ${caps_err}")
endif()

string(FIND "${caps_out}" "\"transparencyModes\":[\"TPU8x10\"]" found_tpu)
expect("TPU8x10 을 투과 소스로 인식한다" found_tpu GREATER -1)

# 여기가 이 계열의 함정이다. 소스를 적용하지 않은 덤프는 평판 한계
# (215.9 x 297.18mm)를 내고, TPU8x10 을 적용한 덤프가 8x10 인치
# (203.2 x 254mm)를 낸다. 어댑터가 소스를 적용해 다시 읽지 않으면
# 사용자에게 존재하지 않는 스캔 영역을 제시하게 된다.
string(FIND "${caps_out}" "\"scanWidthRange\":{\"minimum\":0,\"maximum\":203.2}" found_w)
expect("소스를 적용한 덤프에서 TPU 폭 한계를 읽는다" found_w GREATER -1)
string(FIND "${caps_out}" "\"scanHeightRange\":{\"minimum\":0,\"maximum\":254}" found_h)
expect("소스를 적용한 덤프에서 TPU 높이 한계를 읽는다" found_h GREATER -1)

string(FIND "${caps_out}" "\"supportsPositionedScanArea\":true" found_pos)
expect("평판이므로 위치 지정 스캔을 지원한다" found_pos GREATER -1)

string(FIND "${caps_out}" "\"supportsInfrared\":true" found_ir)
expect("Infrared 모드를 적외선 채널로 인식한다" found_ir GREATER -1)

if(NOT caps_out MATCHES "\"capabilityToken\":\"([^\"]+)\"")
    message(FATAL_ERROR "capabilityToken 을 찾지 못했다.\n${caps_out}")
endif()
set(token "${CMAKE_MATCH_1}")

# --- ③ scan -----------------------------------------------------------------

file(TO_NATIVE_PATH "${WORKDIR}/out.tiff" output_path)
string(REPLACE "\\" "\\\\" output_path_json "${output_path}")

set(request "{\"protocolVersion\":2,\
\"requestID\":\"6f9619ff-8b86-d011-b42d-00cf4fc964ff\",\
\"deviceID\":\"sane-epson2:usbscan:001\",\
\"resolutionDPI\":2400,\
\"bitDepth\":16,\
\"colorMode\":\"color\",\
\"filmType\":\"colorNegative\",\
\"preview\":false,\
\"multiExposure\":false,\
\"infrared\":false,\
\"brightnessAdjustment\":0,\
\"contrastAdjustment\":0,\
\"scanArea\":{\"originXMM\":10,\"originYMM\":20,\"widthMM\":36,\"heightMM\":24},\
\"outputRawTIFF\":true,\
\"capabilityToken\":\"${token}\",\
\"outputPath\":\"${output_path_json}\"}")

file(WRITE "${WORKDIR}/request.json" "${request}")

execute_process(
    COMMAND "${PLUGIN}" scan
    INPUT_FILE "${WORKDIR}/request.json"
    OUTPUT_VARIABLE scan_out
    ERROR_VARIABLE scan_err
    RESULT_VARIABLE scan_code)

if(NOT scan_code EQUAL 0)
    message(FATAL_ERROR "scan 이 ${scan_code} 로 끝났다.\nstdout: ${scan_out}\nstderr: ${scan_err}")
endif()

string(FIND "${scan_out}" "\"type\":\"result\"" found_result)
expect("result 이벤트가 나온다" found_result GREATER -1)

# --- ④ 인자 계약 -------------------------------------------------------------
#
# 여기가 이 파일의 목적이다. 위 세 단계가 통과해도 인자 순서가 틀리면
# 실기에서 조용히 다른 그림이 나온다.

if(NOT EXISTS "${WORKDIR}/args.log")
    message(FATAL_ERROR "가상 scanimage 가 인자 로그를 남기지 않았다.")
endif()
file(READ "${WORKDIR}/args.log" args)

string(FIND "${args}" "-A -d epson2:usbscan:001 --source TPU8x10" found_a_source)
expect("옵션 조회를 소스를 적용해 다시 한다" found_a_source GREATER -1)

string(FIND "${args}" "--film-type Negative Film" found_film)
expect("컬러 네거티브를 --film-type Negative Film 으로 보낸다" found_film GREATER -1)

string(FIND "${args}" "--color-correction None --gamma-correction User defined" found_corr)
expect("색 보정을 끄고 감마를 사용자 정의로 보낸다 (이 순서로)" found_corr GREATER -1)

string(FIND "${args}" "-l 10 -t 20 -x 36 -y 24" found_geom)
expect("지오메트리를 -l -t -x -y 순서로 보낸다" found_geom GREATER -1)

string(FIND "${args}" "--resolution 2400" found_res)
expect("요청한 해상도를 그대로 보낸다" found_res GREATER -1)

string(FIND "${args}" "--depth 16" found_depth)
expect("요청한 비트 깊이를 그대로 보낸다" found_depth GREATER -1)

# 옵션 조회는 두 번이면 충분하다 — 기본 덤프와 소스를 적용한 덤프. 스캔마다
# 다시 읽으면 Epson 은 그때마다 램프를 다시 켜 느려진다.
string(REGEX MATCHALL "\n-A |^-A " option_reads "${args}")
list(LENGTH option_reads option_read_count)
expect("옵션 조회는 두 번뿐이다" option_read_count EQUAL 2)

message(STATUS "epson-smoke 통과")
