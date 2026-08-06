# negaflow-scanner-sane — Windows adapter
# opticfilm-matrix — OpticFilm 계열 **전 모델**에서 프리뷰와 본스캔이 도는지.
#
# 손에 있는 것은 8100 한 대뿐이다. 그 한 대로는 절대 안 드러나는 것이 있다.
#
#   해상도 목록이 모델마다 다르다. 8100 은 7200/3600/2400/1200/600 이고
#   7200·7300·7500i·7600i·8200i 는 7200/3600/1800/900 이다. 8100 에서 잘 되던
#   600 dpi 요청이 7500i 에는 **아예 없는 값**이다.
#
#   적외선은 7200i/7500i/7600i/8200i 만 낸다. 없는 기기에 IR 을 요청하면
#   보내기 전에 거절해야 한다.
#
#   스캔 영역도 다르다(36x25 / 36x24 / 36.33x25).
#
# 값은 backend/genesys/tables_model.cpp 에서 옮겼고, 덤프의 생김새는 실기
# 8100 이 낸 것을 본떴다.
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

function(expect name)
    if(${ARGN})
        message(STATUS "PASS  ${name}")
    else()
        message(SEND_ERROR "FAIL  ${name}  (${ARGN})")
    endif()
endfunction()

# 스캔 요청 하나를 만들어 보낸다. dpi 가 0 이면 프리뷰 요청으로 만든다.
#
# 프리뷰는 별도 계약이다(wire/request.cpp ⑪). `preview:true` 면 해상도가 0,
# infrared·multiExposure 가 거짓, hardwareExposureTime 없음,
# **outputRawTIFF 가 거짓**이어야 한다. 하나라도 어긋나면 봉투에서 거절된다.
#
#   결과는 호출한 쪽의 ${out_code} / ${out_stdout} 로 돌려준다.
function(run_scan tag token dpi infrared out_code out_stdout)
    file(TO_NATIVE_PATH "${WORKDIR}/${tag}.tiff" output_path)
    string(REPLACE "\\" "\\\\" output_path_json "${output_path}")
    if(dpi EQUAL 0)
        set(preview "true")
        set(raw "false")
    else()
        set(preview "false")
        set(raw "true")
    endif()
    set(request "{\"protocolVersion\":2,\
\"requestID\":\"6f9619ff-8b86-d011-b42d-00cf4fc964ff\",\
\"deviceID\":\"sane-genesys:usbscan:000\",\
\"resolutionDPI\":${dpi},\
\"bitDepth\":16,\
\"colorMode\":\"color\",\
\"filmType\":\"colorNegative\",\
\"preview\":${preview},\
\"multiExposure\":false,\
\"infrared\":${infrared},\
\"scanArea\":{\"originXMM\":0,\"originYMM\":0,\"widthMM\":36,\"heightMM\":24},\
\"outputRawTIFF\":${raw},\
\"capabilityToken\":\"${token}\",\
\"outputPath\":\"${output_path_json}\"}")
    file(WRITE "${WORKDIR}/${tag}.json" "${request}")

    execute_process(
        COMMAND "${PLUGIN}" scan
        INPUT_FILE "${WORKDIR}/${tag}.json"
        OUTPUT_VARIABLE scan_out
        ERROR_VARIABLE scan_err
        RESULT_VARIABLE scan_code)

    set(${out_code} "${scan_code}" PARENT_SCOPE)
    set(${out_stdout} "${scan_out}" PARENT_SCOPE)
endfunction()

# --- 모델표 -----------------------------------------------------------------
#
# 시나리오|모델명|이 기기에 있는 dpi|이 기기에 **없는** dpi|폭|높이|IR

set(models
    "of-7200|OpticFilm 7200|1800|600|36|25|0"
    "of-7300|OpticFilm 7300|900|2400|36|24|0"
    "of-7500i|OpticFilm 7500i|3600|1200|36|24|1"
    "of-8100|OpticFilm 8100|600|1800|36.33|25|0"
    "of-8200i|OpticFilm 8200i|7200|600|36.33|25|1")

foreach(row IN LISTS models)
    string(REPLACE "|" ";" f "${row}")
    list(GET f 0 scenario)
    list(GET f 1 model)
    list(GET f 2 dpi_ok)
    list(GET f 3 dpi_absent)
    list(GET f 4 width)
    list(GET f 5 height)
    list(GET f 6 has_ir)

    message(STATUS "--- ${model} ---")
    set(ENV{NEGAFLOW_VSCAN_SCENARIO} "${scenario}")

    # ① detect
    execute_process(
        COMMAND "${PLUGIN}" detect
        OUTPUT_VARIABLE detect_out
        RESULT_VARIABLE detect_code)
    if(NOT detect_code EQUAL 0)
        message(FATAL_ERROR "${model}: detect 가 ${detect_code} 로 끝났다.")
    endif()
    string(FIND "${detect_out}" "\"model\":\"${model}\"" found_model)
    expect("${model}: 모델명을 그대로 낸다" found_model GREATER -1)

    # ② capabilities
    execute_process(
        COMMAND "${PLUGIN}" capabilities "sane-genesys:usbscan:000"
        OUTPUT_VARIABLE caps_out
        ERROR_VARIABLE caps_err
        RESULT_VARIABLE caps_code)
    if(NOT caps_code EQUAL 0)
        message(FATAL_ERROR "${model}: capabilities 가 ${caps_code} 로 끝났다.\n${caps_err}")
    endif()

    # 이 기기에 있는 해상도는 보고하고, 없는 것은 보고하지 않는다.
    string(FIND "${caps_out}" "\"resolutionsDPI\":[" found_res_list)
    expect("${model}: 해상도 목록을 낸다" found_res_list GREATER -1)
    if(NOT caps_out MATCHES "\"resolutionsDPI\":\\[([^]]*)\\]")
        message(FATAL_ERROR "${model}: 해상도 목록을 못 읽었다.")
    endif()
    set(res_list ";${CMAKE_MATCH_1};")
    string(REPLACE "," ";" res_list "${res_list}")
    if(${dpi_ok} IN_LIST res_list)
        set(has_ok 1)
    else()
        set(has_ok 0)
    endif()
    if(${dpi_absent} IN_LIST res_list)
        set(has_absent 1)
    else()
        set(has_absent 0)
    endif()
    expect("${model}: ${dpi_ok} dpi 를 보고한다" has_ok EQUAL 1)
    expect("${model}: 이 기기에 없는 ${dpi_absent} dpi 는 보고하지 않는다" has_absent EQUAL 0)

    string(FIND "${caps_out}" "\"scanWidthRange\":{\"minimum\":0,\"maximum\":${width}}" found_w)
    string(FIND "${caps_out}" "\"scanHeightRange\":{\"minimum\":0,\"maximum\":${height}}" found_h)
    expect("${model}: 스캔 영역이 ${width}x${height}mm 다" found_w GREATER -1 AND found_h GREATER -1)

    if(has_ir)
        string(FIND "${caps_out}" "\"supportsInfrared\":true" found_ir)
    else()
        string(FIND "${caps_out}" "\"supportsInfrared\":false" found_ir)
    endif()
    expect("${model}: 적외선 지원 여부를 맞게 낸다" found_ir GREATER -1)

    # 전 모델이 16-bit 고정이다(bpp_color_values = { 16 }).
    string(FIND "${caps_out}" "\"bitDepths\":[16]" found_depth)
    expect("${model}: 16-bit 하나만 낸다" found_depth GREATER -1)

    if(NOT caps_out MATCHES "\"capabilityToken\":\"([^\"]+)\"")
        message(FATAL_ERROR "${model}: capabilityToken 을 못 찾았다.")
    endif()
    set(token "${CMAKE_MATCH_1}")

    # ③ 프리뷰 (resolutionDPI 0)
    #
    # 여기가 지금까지 어느 시험도 안 돌던 경로다. 프리뷰는 해상도를 보내지
    # 않고 `--preview=yes` 만 보낸다 — 기기가 자기 기본 해상도로 훑는다.
    file(TO_NATIVE_PATH "${WORKDIR}/${scenario}-preview.log" ARGLOG)
    set(ENV{NEGAFLOW_VSCAN_ARGLOG} "${ARGLOG}")
    run_scan("${scenario}-preview" "${token}" 0 "false" pv_code pv_out)
    expect("${model}: 프리뷰 스캔이 성공한다" pv_code EQUAL 0)
    string(FIND "${pv_out}" "\"type\":\"result\"" found_pv_result)
    expect("${model}: 프리뷰가 result 를 낸다" found_pv_result GREATER -1)

    file(READ "${ARGLOG}" pv_args)
    string(FIND "${pv_args}" "--preview=yes" found_pv_flag)
    expect("${model}: 프리뷰에 --preview=yes 를 보낸다" found_pv_flag GREATER -1)
    # 해상도를 함께 보내면 기기의 프리뷰 해상도를 덮어써 느려진다.
    string(FIND "${pv_args}" "--resolution" found_pv_res)
    expect("${model}: 프리뷰에 --resolution 을 보내지 않는다" found_pv_res EQUAL -1)

    # ④ 본스캔 — 이 기기에 있는 해상도
    file(TO_NATIVE_PATH "${WORKDIR}/${scenario}-main.log" ARGLOG)
    set(ENV{NEGAFLOW_VSCAN_ARGLOG} "${ARGLOG}")
    run_scan("${scenario}-main" "${token}" "${dpi_ok}" "false" main_code main_out)
    expect("${model}: ${dpi_ok} dpi 본스캔이 성공한다" main_code EQUAL 0)
    string(FIND "${main_out}" "\"type\":\"result\"" found_main_result)
    expect("${model}: 본스캔이 result 를 낸다" found_main_result GREATER -1)

    file(READ "${ARGLOG}" main_args)
    string(FIND "${main_args}" "--resolution ${dpi_ok}" found_main_res)
    expect("${model}: 요청한 ${dpi_ok} dpi 를 그대로 보낸다" found_main_res GREATER -1)
    string(FIND "${main_args}" "--preview=yes" found_main_pv)
    expect("${model}: 본스캔에 --preview 를 보내지 않는다" found_main_pv EQUAL -1)

    # ⑤ 본스캔 — 이 기기에 **없는** 해상도
    #
    # 스냅하지 않는다(I-1). 가까운 값으로 몰래 바꾸면 사용자가 요청한 것과
    # 다른 그림이 나오고, 그것을 알 방법이 없다.
    run_scan("${scenario}-bad" "${token}" "${dpi_absent}" "false" bad_code bad_out)
    expect("${model}: 없는 ${dpi_absent} dpi 는 exit 1 이다" bad_code EQUAL 1)
    string(FIND "${bad_out}" "\"type\":\"error\"" found_bad_error)
    expect("${model}: 없는 해상도를 오류로 보고한다" found_bad_error GREATER -1)

    # ⑥ 적외선
    file(TO_NATIVE_PATH "${WORKDIR}/${scenario}-ir.log" ARGLOG)
    set(ENV{NEGAFLOW_VSCAN_ARGLOG} "${ARGLOG}")
    run_scan("${scenario}-ir" "${token}" "${dpi_ok}" "true" ir_code ir_out)
    if(has_ir)
        expect("${model}: 적외선 스캔이 성공한다" ir_code EQUAL 0)
        string(FIND "${ir_out}" "\"hasInfrared\":true" found_ir_flag)
        expect("${model}: IR 채널을 보고한다" found_ir_flag GREATER -1)
        file(READ "${ARGLOG}" ir_args)
        string(FIND "${ir_args}" "--source Transparency Adapter Infrared" found_ir_source)
        expect("${model}: IR 패스에 IR 소스를 쓴다" found_ir_source GREATER -1)
    else()
        # 없는 기기에 요청하면 스캐너까지 가기 전에 거절해야 한다.
        expect("${model}: IR 이 없으면 exit 1 이다" ir_code EQUAL 1)
        string(FIND "${ir_out}" "\"type\":\"error\"" found_no_ir)
        expect("${model}: IR 없음을 오류로 보고한다" found_no_ir GREATER -1)
    endif()
endforeach()

message(STATUS "opticfilm-matrix 통과")
