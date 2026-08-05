# negaflow-scanner-sane — Windows adapter
# plugin-smoke — 실행 파일을 **실제로 돌려** 계약을 확인한다.
#
# 정본 문서: windows_docs/03-process-and-io/child-process.md §13
#            windows_docs/05-protocol/wire-contract.md §3, §4, §5
#
# 단위 테스트는 순수 판정을 고정한다. 여기서 보는 것은 그 밖의 것이다 —
# 프로세스가 뜨는가, 파이프가 교착하지 않는가, stdout 에 프로토콜만 나오는가,
# detect → capabilities → scan 이 토큰으로 이어지는가.
#
# CMake 스크립트 모드로 도는 이유: ctest 에 이미 있고, PowerShell 실행 정책
# 같은 변수가 끼어들지 않는다.
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

set(ENV{NEGAFLOW_SCANIMAGE_PATH} "${VSCAN}")
set(ENV{NEGAFLOW_VSCAN_SCENARIO} "")

# 조건은 **개별 인자로** 받는다. `expect(name "a EQUAL 1")` 처럼 한 문자열로
# 넘기면 `if()` 가 그것을 변수 이름 하나로 보고 언제나 거짓이 된다 —
# 그러면 모든 검사가 조용히 실패한다.
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

string(FIND "${detect_out}" "\"id\":\"sane-genesys:libusb:001:002\"" found_id)
expect("detect 가 라우팅 ID 를 낸다" found_id GREATER -1)

string(FIND "${detect_out}" "\"displayName\":\"Plustek OpticFilm 8100\"" found_name)
expect("detect 의 displayName 이 capitalized 규칙을 따른다" found_name GREATER -1)

string(FIND "${detect_out}" "\"driverVersion\":\"genesys (SANE)\"" found_driver)
expect("detect 가 백엔드를 driverVersion 으로 보고한다" found_driver GREATER -1)

# stdout 은 프로토콜 전용이다. 한 줄이어야 한다.
string(REGEX MATCHALL "\n" detect_newlines "${detect_out}")
list(LENGTH detect_newlines detect_line_count)
expect("detect stdout 이 정확히 한 줄이다" detect_line_count EQUAL 1)

# --- ② capabilities ---------------------------------------------------------

execute_process(
    COMMAND "${PLUGIN}" capabilities "sane-genesys:libusb:001:002"
    OUTPUT_VARIABLE caps_out
    ERROR_VARIABLE caps_err
    RESULT_VARIABLE caps_code)

if(NOT caps_code EQUAL 0)
    message(FATAL_ERROR "capabilities 가 ${caps_code} 로 끝났다.\nstderr: ${caps_err}")
endif()

string(FIND "${caps_out}" "\"resolutionsDPI\":[600,1200,2400,3600,7200]" found_res)
expect("capabilities 가 해상도를 오름차순으로 낸다" found_res GREATER -1)

string(FIND "${caps_out}" "\"supportsTransparency\":true" found_transparency)
expect("투과 소스를 인식한다" found_transparency GREATER -1)

string(FIND "${caps_out}" "\"supportsInfrared\":true" found_ir)
expect("IR 소스를 인식한다" found_ir GREATER -1)

string(FIND "${caps_out}" "\"scanAreaUnit\":\"millimeter\"" found_unit)
expect("mm 단위 지오메트리를 보고한다" found_unit GREATER -1)

string(REGEX MATCH "\"capabilityToken\":\"([^\"]+)\"" _match "${caps_out}")
set(token "${CMAKE_MATCH_1}")
string(LENGTH "${token}" token_length)
expect("capabilityToken 이 비어 있지 않다" token_length GREATER 0)

# --- ③ scan -----------------------------------------------------------------

file(TO_NATIVE_PATH "${WORKDIR}/frame.tiff" output_path)
string(REPLACE "\\" "\\\\" output_path_json "${output_path}")

set(request "{\"protocolVersion\":2,\
\"requestID\":\"6f9619ff-8b86-d011-b42d-00cf4fc964ff\",\
\"deviceID\":\"sane-genesys:libusb:001:002\",\
\"resolutionDPI\":1200,\
\"bitDepth\":16,\
\"colorMode\":\"color\",\
\"filmType\":\"colorNegative\",\
\"preview\":false,\
\"multiExposure\":false,\
\"infrared\":false,\
\"brightnessAdjustment\":0,\
\"contrastAdjustment\":0,\
\"scanArea\":{\"originXMM\":0,\"originYMM\":0,\"widthMM\":36.33,\"heightMM\":24.5},\
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

string(FIND "${scan_out}" "\"type\":\"progress\"" found_progress)
expect("진행률 이벤트가 나온다" found_progress GREATER -1)

string(FIND "${scan_out}" "\"sequence\":0" found_seq0)
expect("sequence 가 0 부터 시작한다" found_seq0 GREATER -1)

string(FIND "${scan_out}" "\"type\":\"result\"" found_result)
expect("result 이벤트가 나온다" found_result GREATER -1)

string(FIND "${scan_out}" "\"width\":70" found_width)
string(FIND "${scan_out}" "\"height\":50" found_height)
expect("result 가 실제 TIFF 픽셀 크기를 낸다" found_width GREATER -1 AND found_height GREATER -1)

string(FIND "${scan_out}" "\"hasInfrared\":false" found_hasir)
expect("IR 을 요청하지 않았으므로 hasInfrared 가 false 다" found_hasir GREATER -1)

# appliedOptions 는 **12키가 항상 나온다.** nil 은 null 이다(wire/event).
string(FIND "${scan_out}" "\"hardwareExposureTime\":null" found_null_exposure)
expect("appliedOptions 가 없는 값을 null 로 명시한다" found_null_exposure GREATER -1)

string(FIND "${scan_out}" "\"scanArea\":{\"originXMM\":0,\"originYMM\":0,\"widthMM\":36.33,\"heightMM\":24.5}" found_area)
expect("appliedOptions 가 실제로 보낸 영역을 담는다" found_area GREATER -1)

if(NOT EXISTS "${WORKDIR}/frame.tiff")
    message(SEND_ERROR "FAIL  스캔 결과 파일이 없다")
else()
    file(SIZE "${WORKDIR}/frame.tiff" tiff_size)
    # 70 × 50 × 3 × 2 = 21,000 바이트 + 헤더/IFD
    expect("결과 TIFF 크기가 픽셀 수와 맞는다" tiff_size GREATER 21000)
endif()

# --- ③a IR 별도 패스 ---------------------------------------------------------
#
# genesys 계열의 IR 은 **소스를 바꿔 한 번 더 스캔한다.** 본 스캔과 같은
# 지오메트리·해상도여야 먼지 맵이 RGB 에 정렬된다.

file(TO_NATIVE_PATH "${WORKDIR}/ir/frame.tiff" ir_output_path)
file(MAKE_DIRECTORY "${WORKDIR}/ir")
string(REPLACE "\\" "\\\\" ir_output_json "${ir_output_path}")
string(REPLACE "\"infrared\":false" "\"infrared\":true" ir_request "${request}")
string(REPLACE "${output_path_json}" "${ir_output_json}" ir_request "${ir_request}")
file(WRITE "${WORKDIR}/ir-request.json" "${ir_request}")

execute_process(
    COMMAND "${PLUGIN}" scan
    INPUT_FILE "${WORKDIR}/ir-request.json"
    OUTPUT_VARIABLE ir_out
    ERROR_VARIABLE ir_err
    RESULT_VARIABLE ir_code)

expect("IR 스캔이 성공한다" ir_code EQUAL 0)
string(FIND "${ir_out}" "\"hasInfrared\":true" found_ir_flag)
expect("IR 채널을 보고한다" found_ir_flag GREATER -1)
string(FIND "${ir_out}" "\"phase\":\"scanningIR\"" found_ir_phase)
expect("IR 패스가 별도 phase 로 보고된다" found_ir_phase GREATER -1)
expect("IR 파일 이름이 <base>.ir.<ext> 규칙을 따른다"
       EXISTS "${WORKDIR}/ir/frame.ir.tiff")

# --- ③b 다중 노출 병합 -------------------------------------------------------
#
# 세 노출을 각각 스캔해 병합하고 16비트로 양자화해 쓴다. **비트 동일 대상**인
# 경로가 실제로 끝까지 도는지 여기서 확인한다.

file(TO_NATIVE_PATH "${WORKDIR}/mx/frame.tiff" mx_output_path)
file(MAKE_DIRECTORY "${WORKDIR}/mx")
string(REPLACE "\\" "\\\\" mx_output_json "${mx_output_path}")
string(REPLACE "\"multiExposure\":false" "\"multiExposure\":true" mx_request "${request}")
string(REPLACE "${output_path_json}" "${mx_output_json}" mx_request "${mx_request}")
file(WRITE "${WORKDIR}/mx-request.json" "${mx_request}")

execute_process(
    COMMAND "${PLUGIN}" scan
    INPUT_FILE "${WORKDIR}/mx-request.json"
    OUTPUT_VARIABLE mx_out
    ERROR_VARIABLE mx_err
    RESULT_VARIABLE mx_code)

expect("다중 노출 스캔이 성공한다" mx_code EQUAL 0)
# `/` 가 `\/` 로 이스케이프된 채 나온다. Swift `JSONEncoder` 의 기본이 그렇고
# 제품 코드가 그 옵션을 끄지 않으므로 **실제 wire 가 그 형태다**(wire/json.h).
# 이스케이프 없는 형태를 찾으면 이 검사는 조용히 실패한다.
string(FIND "${mx_out}" "Exposure bracket 1\\/3 @ 11000" found_bracket)
expect("노출 브래킷 진행률을 보고한다" found_bracket GREATER -1)
string(FIND "${mx_out}" "\"phase\":\"processingNegative\"" found_merge_phase)
expect("병합 단계를 보고한다" found_merge_phase GREATER -1)
string(FIND "${mx_out}" "\"width\":70" found_mx_width)
expect("병합 결과가 입력과 같은 픽셀 크기다" found_mx_width GREATER -1)
expect("병합 결과 파일이 있다" EXISTS "${WORKDIR}/mx/frame.tiff")
# 중간 표본은 기본적으로 지운다(NEGAFLOW_KEEP_MULTIPASS 가 없을 때).
expect("중간 표본 TIFF 가 남지 않는다" NOT EXISTS "${WORKDIR}/mx/frame.negaflow-sample1.tiff")

# --- ④ 잘못된 요청은 wire 로 오류를 낸다 -------------------------------------

file(WRITE "${WORKDIR}/bad.json"
     "{\"protocolVersion\":2,\"requestID\":\"6f9619ff-8b86-d011-b42d-00cf4fc964ff\",\"x\":")

execute_process(
    COMMAND "${PLUGIN}" scan
    INPUT_FILE "${WORKDIR}/bad.json"
    OUTPUT_VARIABLE bad_out
    ERROR_VARIABLE bad_err
    RESULT_VARIABLE bad_code)

expect("깨진 요청은 exit 1 이다" bad_code EQUAL 1)
string(FIND "${bad_err}" "scan 옵션 JSON 파싱 실패" found_parse_fail)
expect("봉투도 못 읽으면 stderr 로 보고한다" found_parse_fail GREATER -1)

# 봉투가 읽히면 **wire 로** 오류가 나가야 한다(requestID 가 있으므로).
file(WRITE "${WORKDIR}/envelope.json"
     "{\"protocolVersion\":2,\"requestID\":\"6f9619ff-8b86-d011-b42d-00cf4fc964ff\"}")

execute_process(
    COMMAND "${PLUGIN}" scan
    INPUT_FILE "${WORKDIR}/envelope.json"
    OUTPUT_VARIABLE env_out
    ERROR_VARIABLE env_err
    RESULT_VARIABLE env_code)

expect("봉투만 있는 요청은 exit 1 이다" env_code EQUAL 1)
string(FIND "${env_out}" "\"type\":\"error\"" found_error_event)
expect("requestID 를 건지면 오류를 wire 로 낸다" found_error_event GREATER -1)

# --- ⑤ 파이프 교착 — stderr 를 1 MiB 쏟아붓는다 ------------------------------

set(ENV{NEGAFLOW_VSCAN_SCENARIO} "bigout")
execute_process(
    COMMAND "${PLUGIN}" scan
    INPUT_FILE "${WORKDIR}/request.json"
    OUTPUT_VARIABLE big_out
    ERROR_VARIABLE big_err
    RESULT_VARIABLE big_code
    TIMEOUT 120)
set(ENV{NEGAFLOW_VSCAN_SCENARIO} "")

expect("stderr 폭주에도 교착하지 않는다" big_code EQUAL 0)

# --- ⑥ 반올림 경고는 결과를 버린다 (I-1) --------------------------------------

set(ENV{NEGAFLOW_VSCAN_SCENARIO} "rounded")
execute_process(
    COMMAND "${PLUGIN}" scan
    INPUT_FILE "${WORKDIR}/request.json"
    OUTPUT_VARIABLE rounded_out
    ERROR_VARIABLE rounded_err
    RESULT_VARIABLE rounded_code)
set(ENV{NEGAFLOW_VSCAN_SCENARIO} "")

expect("반올림 경고가 있으면 실패한다" rounded_code EQUAL 1)
string(FIND "${rounded_out}" "unsupportedOption: SANE가 요청 옵션을" found_rounded)
expect("반올림 실패 문구가 macOS 와 같다" found_rounded GREATER -1)

# --- ⑦ 주소가 만료된 첫 open 은 재열거 후 다시 시도한다 ----------------------
#
# **실기에서 가장 흔한 실패다.** 장치를 열 때마다 libusb 주소가 바뀌므로
# 토큰에 적힌 주소는 이미 죽어 있을 수 있다. 이 갈래가 없으면 스캔이
# 첫 시도에서 그냥 실패한다.

file(TO_NATIVE_PATH "${WORKDIR}/stale/frame.tiff" stale_output_path)
file(MAKE_DIRECTORY "${WORKDIR}/stale")
string(REPLACE "\\" "\\\\" stale_output_json "${stale_output_path}")
string(REPLACE "${output_path_json}" "${stale_output_json}" stale_request "${request}")
file(WRITE "${WORKDIR}/stale-request.json" "${stale_request}")

set(ENV{NEGAFLOW_VSCAN_SCENARIO} "stale-once")
set(ENV{NEGAFLOW_VSCAN_MARKER} "${WORKDIR}/stale/opened-once")
execute_process(
    COMMAND "${PLUGIN}" scan
    INPUT_FILE "${WORKDIR}/stale-request.json"
    OUTPUT_VARIABLE stale_out
    ERROR_VARIABLE stale_err
    RESULT_VARIABLE stale_code)
set(ENV{NEGAFLOW_VSCAN_SCENARIO} "")
set(ENV{NEGAFLOW_VSCAN_MARKER} "")

expect("죽은 주소로 시작해도 스캔이 성공한다" stale_code EQUAL 0)
string(FIND "${stale_out}" "Re-detecting scanner" found_redetect)
expect("재열거를 진행률로 알린다" found_redetect GREATER -1)
expect("재시도한 스캔의 결과 파일이 있다" EXISTS "${WORKDIR}/stale/frame.tiff")

# --- ⑧ scanimage 가 없으면 원인을 말한다 --------------------------------------

set(ENV{NEGAFLOW_SCANIMAGE_PATH} "${WORKDIR}/does-not-exist.exe")
execute_process(
    COMMAND "${PLUGIN}" detect
    OUTPUT_VARIABLE missing_out
    ERROR_VARIABLE missing_err
    RESULT_VARIABLE missing_code)
set(ENV{NEGAFLOW_SCANIMAGE_PATH} "${VSCAN}")

expect("scanimage 가 없으면 exit 1 이다" missing_code EQUAL 1)
string(FIND "${missing_err}" "NEGAFLOW_SCANIMAGE_PATH" found_reason)
expect("무엇이 잘못됐는지 말한다" found_reason GREATER -1)

message(STATUS "plugin smoke: 전 항목 통과")
