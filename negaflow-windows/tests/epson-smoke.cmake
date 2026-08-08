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

string(FIND "${detect_out}" "\"id\":\"sane-epson2:usbscan:091\"" found_id)
expect("Windows 장치 이름 epson2:usbscan:NNN 을 그대로 낸다" found_id GREATER -1)

# still-image 클래스 드라이버로 열린 장치도 USB 다. `:libusb:` 만 보면
# 내부 버스로 잘못 분류한다.
string(FIND "${detect_out}" "\"connectionType\":\"usb\"" found_usb)
expect("usbscan 장치를 USB 로 분류한다" found_usb GREATER -1)

string(FIND "${detect_out}" "\"driverVersion\":\"epson2 (SANE)\"" found_driver)
expect("백엔드를 epson2 로 보고한다" found_driver GREATER -1)

# 기기가 스스로 말하는 이름은 판매명이 아니다. epson2 는
# `esci_request_extended_identity` 가 준 문자열을 그대로 쓰고, 그것이 일본
# 내수 모델명이다(V800/V850 = GT-X980, V700/V750 = GT-X900).
#
# 지어낸 값이 아니다 — epson2-ops.c 의 TPU2 분기가 바로 그 문자열로 검사한다.
#
# **사용자는 "Epson GT-X980" 을 보게 된다.** 자기가 산 V800 이 아니다. 맥도
# 같으므로 여기서는 그 사실만 고정한다.
string(FIND "${detect_out}" "\"displayName\":\"Epson GT-X980\"" found_display)
expect("기기가 말하는 이름을 그대로 낸다 (판매명이 아니다)" found_display GREATER -1)

# --- ② capabilities ---------------------------------------------------------

execute_process(
    COMMAND "${PLUGIN}" capabilities "sane-epson2:usbscan:091"
    OUTPUT_VARIABLE caps_out
    ERROR_VARIABLE caps_err
    RESULT_VARIABLE caps_code)

if(NOT caps_code EQUAL 0)
    message(FATAL_ERROR "capabilities 가 ${caps_code} 로 끝났다.\nstderr: ${caps_err}")
endif()

string(FIND "${caps_out}" "\"transparencyModes\":[\"Transparency Unit\",\"TPU8x10\"]" found_tpu)
expect("투과 소스 둘을 모두 인식한다" found_tpu GREATER -1)

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

# 이 계열은 기본 모드가 Lineart 이고 **그 상태에서 --depth 가 비활성이다**
# (실측: GT-X980 = V850). 모드를 적용하지 않은 첫 덤프만 읽으면 지원 심도가
# 통째로 빈다. 어댑터가 모드를 적용해 다시 읽어야 이 값이 나온다.
string(FIND "${caps_out}" "\"bitDepths\":[8,16]" found_depths)
expect("Lineart 기본이라 비활성인 심도를 다시 읽어 복구한다" found_depths GREATER -1)

# 기기 범위를 그대로 호스트에 알린다. genesys 의 -100..100 과 다르다.
string(FIND "${caps_out}" "\"brightnessRange\":{\"minimum\":-4,\"maximum\":3,\"step\":1}" found_bright)
expect("밝기 범위를 기기 값 그대로 보고한다" found_bright GREATER -1)

if(NOT caps_out MATCHES "\"capabilityToken\":\"([^\"]+)\"")
    message(FATAL_ERROR "capabilityToken 을 찾지 못했다.\n${caps_out}")
endif()
set(token "${CMAKE_MATCH_1}")

# --- ③ scan -----------------------------------------------------------------

file(TO_NATIVE_PATH "${WORKDIR}/out.tiff" output_path)
string(REPLACE "\\" "\\\\" output_path_json "${output_path}")

set(request "{\"protocolVersion\":2,\
\"requestID\":\"6f9619ff-8b86-d011-b42d-00cf4fc964ff\",\
\"deviceID\":\"sane-epson2:usbscan:091\",\
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

string(FIND "${args}" "-A -d epson2:usbscan:091 --source TPU8x10 --mode Color" found_a_source)
expect("옵션 조회를 소스와 모드를 적용해 다시 한다" found_a_source GREATER -1)

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

# 맥과 갈리는 지점이다. 맥은 libusb 주소가 열 때마다 바뀌므로 주소 없는
# `-d epson2` 선택자를 쓴다. Windows 의 `usbscan:NNN` 은 커널 장치 번호라
# 열고 닫아도, 전원을 다시 넣어도 바뀌지 않는 것을 실측했다 — 그래서 전체
# 이름을 그대로 쓴다. 더 정확하고, 같은 백엔드 장치가 둘일 때도 안 헷갈린다.
string(FIND "${args}" "-d epson2:usbscan:091 -p" found_selector)
expect("획득에 전체 장치 이름을 쓴다 (주소가 안 바뀌므로)" found_selector GREATER -1)

# 옵션 조회는 두 번이면 충분하다 — 기본 덤프와 소스를 적용한 덤프. 스캔마다
# 다시 읽으면 Epson 은 그때마다 램프를 다시 켜 느려진다.
string(REGEX MATCHALL "\n-A |^-A " option_reads "${args}")
list(LENGTH option_reads option_read_count)
expect("옵션 조회는 두 번뿐이다" option_read_count EQUAL 2)

# epson2 의 --film-type 은 네 값이다(Positive/Negative × Film/Slide). 부분
# 일치로 고르면 Slide 를 집는다.
string(FIND "${args}" "Negative Slide" found_slide)
expect("Negative Film 대신 Negative Slide 를 집지 않는다" found_slide EQUAL -1)

# 비활성 옵션도 제약 목록을 그대로 출력한다. 목록만 보고 설정하면
# scanimage 가 "attempted to set inactive option" 으로 거절한다.
string(FIND "${args}" "--halftoning" found_halftone)
string(FIND "${args}" "--threshold" found_threshold)
string(FIND "${args}" "--eject" found_eject)
expect("비활성 옵션을 설정하지 않는다"
       found_halftone EQUAL -1 AND found_threshold EQUAL -1 AND found_eject EQUAL -1)

# --- ④a 프리뷰 ---------------------------------------------------------------
#
# 프리뷰는 별도 계약이다(wire/request.cpp ⑪): `preview:true` 면 해상도가 0,
# infrared·multiExposure 가 거짓, **outputRawTIFF 도 거짓**이어야 한다.
#
# epson2 의 `--preview` 는 `esci_set_speed(s, 1)` 로 고속 모드를 켠다
# (epson2-ops.c). 해상도는 안 건드리므로, 해상도를 **보내지 않아서** 기기
# 기본값(목록의 최솟값)으로 훑게 하는 것이 프리뷰가 싼 이유다. 여기서
# `--resolution` 을 함께 보내면 프리뷰가 본스캔 해상도로 돈다.

file(TO_NATIVE_PATH "${WORKDIR}/args-preview.log" ARGLOG_PREVIEW)
set(ENV{NEGAFLOW_VSCAN_ARGLOG} "${ARGLOG_PREVIEW}")

file(TO_NATIVE_PATH "${WORKDIR}/preview.tiff" preview_path)
string(REPLACE "\\" "\\\\" preview_path_json "${preview_path}")
set(preview_request "{\"protocolVersion\":2,\
\"requestID\":\"6f9619ff-8b86-d011-b42d-00cf4fc964ff\",\
\"deviceID\":\"sane-epson2:usbscan:091\",\
\"resolutionDPI\":0,\
\"bitDepth\":16,\
\"colorMode\":\"color\",\
\"filmType\":\"colorNegative\",\
\"preview\":true,\
\"multiExposure\":false,\
\"infrared\":false,\
\"scanArea\":{\"originXMM\":10,\"originYMM\":20,\"widthMM\":36,\"heightMM\":24},\
\"outputRawTIFF\":false,\
\"capabilityToken\":\"${token}\",\
\"outputPath\":\"${preview_path_json}\"}")
file(WRITE "${WORKDIR}/preview.json" "${preview_request}")

execute_process(
    COMMAND "${PLUGIN}" scan
    INPUT_FILE "${WORKDIR}/preview.json"
    OUTPUT_VARIABLE preview_out
    ERROR_VARIABLE preview_err
    RESULT_VARIABLE preview_code)

expect("프리뷰 스캔이 성공한다" preview_code EQUAL 0)
string(FIND "${preview_out}" "\"type\":\"result\"" found_preview_result)
expect("프리뷰가 result 를 낸다" found_preview_result GREATER -1)

file(READ "${ARGLOG_PREVIEW}" preview_args)
string(FIND "${preview_args}" "--preview=yes" found_preview_flag)
expect("프리뷰에 --preview=yes 를 보낸다" found_preview_flag GREATER -1)
string(FIND "${preview_args}" "--resolution" found_preview_res)
expect("프리뷰에 --resolution 을 보내지 않는다" found_preview_res EQUAL -1)

# 프리뷰라도 소스는 투과여야 한다. 평판으로 훑으면 필름이 안 보인다.
string(FIND "${preview_args}" "--source TPU8x10" found_preview_source)
expect("프리뷰도 투과 소스로 한다" found_preview_source GREATER -1)

# 프리뷰는 옵션을 다시 읽지 않는다 — 이미 읽은 것을 쓴다.
string(FIND "${preview_args}" "-A " found_preview_dump)
expect("프리뷰가 옵션을 다시 읽지 않는다" found_preview_dump EQUAL -1)

set(ENV{NEGAFLOW_VSCAN_ARGLOG} "${ARGLOG}")

# --- ⑤ 정수 mm 절삭 보정 -----------------------------------------------------
#
# epson2-ops.c 의 e2_init_parameters 는
#
#   ((int) SANE_UNFIX(s->val[OPT_BR_Y].w) / MM_PER_INCH * dpi + 0.5) - s->top
#
# 로 계산하는데 `(int)` 캐스트가 나눗셈보다 먼저 걸린다. br_y 가 소수 mm 면
# 결과의 세로만 최대 1 mm 어치 짧아진다 — 요청한 종횡비와 어긋나고 필름 컷이
# 조용히 잘린다. 어댑터가 아래(bottom)를 정수로 맞춰 보내야 한다.
#
# originY 20 + height 23.5 => bottom 43.5 이므로 44 로 키운다 => 높이 24.
# 위 ④ 의 요청은 bottom 이 이미 정수(20+24=44)라 이 경로를 안 지난다.

string(REPLACE "\"heightMM\":24" "\"heightMM\":23.5" align_request "${request}")
file(WRITE "${WORKDIR}/align.json" "${align_request}")

# 로그를 새 파일로 돌린다. ④ 의 요청이 이미 높이 24 를 보냈으므로, 같은
# 파일에 이어 쓰면 그 줄에 걸려 보정이 없어도 통과한다.
file(TO_NATIVE_PATH "${WORKDIR}/args-align.log" ARGLOG_ALIGN)
set(ENV{NEGAFLOW_VSCAN_ARGLOG} "${ARGLOG_ALIGN}")

execute_process(
    COMMAND "${PLUGIN}" scan
    INPUT_FILE "${WORKDIR}/align.json"
    OUTPUT_VARIABLE align_out
    ERROR_VARIABLE align_err
    RESULT_VARIABLE align_code)

if(NOT align_code EQUAL 0)
    message(FATAL_ERROR "정렬 스캔이 ${align_code} 로 끝났다.\nstderr: ${align_err}")
endif()

file(READ "${WORKDIR}/args-align.log" args_after_align)
string(FIND "${args_after_align}" "-l 10 -t 20 -x 36 -y 24" found_aligned)
expect("소수 mm 아래를 정수로 키워 보낸다 (23.5 -> 24)" found_aligned GREATER -1)

# 호스트가 요청과 다른 높이를 받았음을 알아야 한다. 조용히 바꾸면 앱이
# 종횡비를 잘못 계산한다.
string(FIND "${align_out}" "\"heightMM\":24" found_applied_height)
expect("실제로 적용한 높이를 appliedOptions 로 알린다" found_applied_height GREATER -1)

# --- ⑤a 적외선 ---------------------------------------------------------------
#
# 이 계열의 적외선은 genesys 와 방식이 다르다. genesys 는 **별도 소스**
# (`Transparency Adapter Infrared`)를 내지만 epson2 는 **모드**로 낸다
# (`--mode Infrared`, epson2.c 의 `mode_list`). 그래서 IR 패스가 소스가 아니라
# 모드를 바꿔야 한다 — `IRStrategy::SeparateMode`.

file(TO_NATIVE_PATH "${WORKDIR}/args-ir.log" ARGLOG_IR)
set(ENV{NEGAFLOW_VSCAN_ARGLOG} "${ARGLOG_IR}")

string(REPLACE "\"infrared\":false" "\"infrared\":true" ir_request "${request}")
string(REPLACE "out.tiff" "ir-out.tiff" ir_request "${ir_request}")
file(WRITE "${WORKDIR}/ir.json" "${ir_request}")

execute_process(
    COMMAND "${PLUGIN}" scan
    INPUT_FILE "${WORKDIR}/ir.json"
    OUTPUT_VARIABLE ir_out
    ERROR_VARIABLE ir_err
    RESULT_VARIABLE ir_code)

expect("적외선 스캔이 성공한다" ir_code EQUAL 0)
string(FIND "${ir_out}" "\"hasInfrared\":true" found_ir_flag)
expect("IR 채널을 보고한다" found_ir_flag GREATER -1)

file(READ "${ARGLOG_IR}" ir_args)
# 두 패스가 나가야 한다. IR 패스는 모드만 Infrared 로 바꾸고 나머지는 같다.
string(FIND "${ir_args}" "--mode Infrared" found_ir_mode)
expect("IR 패스를 --mode Infrared 로 돈다 (소스가 아니라 모드다)" found_ir_mode GREATER -1)
# 소스는 그대로여야 한다. epson2 에는 IR 소스가 없다.
string(FIND "${ir_args}" "--source TPU8x10 --mode Infrared" found_ir_keeps_source)
expect("IR 패스도 같은 투과 소스를 쓴다" found_ir_keeps_source GREATER -1)
string(FIND "${ir_args}" "--resolution 2400" found_ir_res)
expect("IR 패스가 본스캔과 같은 해상도로 돈다" found_ir_res GREATER -1)

set(ENV{NEGAFLOW_VSCAN_ARGLOG} "${ARGLOG}")

# --- ⑥ 기기 범위 밖 밝기 -----------------------------------------------------
#
# epson2 의 밝기는 B7/B8 명령 레벨에서 -4..3 이다. genesys 는 -100..100 이라
# 앱이 같은 값을 두 기기에 보내면 Epson 에서만 터진다. 보내기 전에 거절해야
# 한다 — 스캐너까지 갔다가 실패하면 램프만 켜고 시간을 버린다.

string(REPLACE "\"brightnessAdjustment\":0" "\"brightnessAdjustment\":10"
       bright_request "${request}")
file(WRITE "${WORKDIR}/bright.json" "${bright_request}")

execute_process(
    COMMAND "${PLUGIN}" scan
    INPUT_FILE "${WORKDIR}/bright.json"
    OUTPUT_VARIABLE bright_out
    ERROR_VARIABLE bright_err
    RESULT_VARIABLE bright_code)

expect("범위 밖 밝기 요청은 exit 1 이다" bright_code EQUAL 1)
string(FIND "${bright_out}" "\"type\":\"error\"" found_bright_error)
expect("범위 밖 밝기를 오류로 보고한다" found_bright_error GREATER -1)

# --- ⑦ TPU8x10 이 없는 Epson -------------------------------------------------
#
# TPU8x10 은 epson2-ops.c 의 TPU2 분기가 모델명 GT-X800/GT-X900/GT-X980 일
# 때만 붙인다. 그 밖의 투과 장비는 `Transparency Unit` 하나뿐이므로, 8x10 을
# 전제로 만든 코드는 그런 기기에서 투과 스캔을 아예 못 하게 된다.

file(TO_NATIVE_PATH "${WORKDIR}/args-tpu.log" ARGLOG_TPU)
set(ENV{NEGAFLOW_VSCAN_SCENARIO} "epson-tpu")
set(ENV{NEGAFLOW_VSCAN_ARGLOG} "${ARGLOG_TPU}")

execute_process(
    COMMAND "${PLUGIN}" capabilities "sane-epson2:usbscan:091"
    OUTPUT_VARIABLE tpu_caps_out
    ERROR_VARIABLE tpu_caps_err
    RESULT_VARIABLE tpu_caps_code)

if(NOT tpu_caps_code EQUAL 0)
    message(FATAL_ERROR "capabilities(epson-tpu) 가 ${tpu_caps_code} 로 끝났다.\nstderr: ${tpu_caps_err}")
endif()

string(FIND "${tpu_caps_out}" "\"transparencyModes\":[\"Transparency Unit\"]" found_tpu_only)
expect("8x10 이 없으면 Transparency Unit 하나만 낸다" found_tpu_only GREATER -1)

string(FIND "${tpu_caps_out}" "\"scanWidthRange\":{\"minimum\":0,\"maximum\":101.6}" found_tpu_w)
expect("그 소스를 적용한 지오메트리를 읽는다" found_tpu_w GREATER -1)

if(NOT tpu_caps_out MATCHES "\"capabilityToken\":\"([^\"]+)\"")
    message(FATAL_ERROR "capabilityToken(epson-tpu) 을 찾지 못했다.\n${tpu_caps_out}")
endif()
string(REPLACE "${token}" "${CMAKE_MATCH_1}" tpu_request "${request}")
file(WRITE "${WORKDIR}/request-tpu.json" "${tpu_request}")

execute_process(
    COMMAND "${PLUGIN}" scan
    INPUT_FILE "${WORKDIR}/request-tpu.json"
    OUTPUT_VARIABLE tpu_scan_out
    ERROR_VARIABLE tpu_scan_err
    RESULT_VARIABLE tpu_scan_code)

if(NOT tpu_scan_code EQUAL 0)
    message(FATAL_ERROR "scan(epson-tpu) 이 ${tpu_scan_code} 로 끝났다.\nstderr: ${tpu_scan_err}")
endif()

file(READ "${WORKDIR}/args-tpu.log" tpu_args)
string(FIND "${tpu_args}" "--source Transparency Unit" found_tpu_source)
expect("8x10 이 없으면 Transparency Unit 을 쓴다" found_tpu_source GREATER -1)
string(FIND "${tpu_args}" "TPU8x10" found_tpu_8x10)
expect("없는 소스를 만들어 보내지 않는다" found_tpu_8x10 EQUAL -1)

# --- ⑧ 해상도 전 범위 ---------------------------------------------------------
#
# 이 계열은 목록이 50 dpi 부터 6400 까지 열다섯 단계다. 하나만 돌려보고 되는
# 줄 알면 안 된다 — 낮은 쪽은 프리뷰가 쓰고, 높은 쪽은 필름 스캔이 쓴다.
#
# 목록에 없는 값(9600, 12800 같은 보간 해상도)은 거절해야 한다. 스냅하지
# 않는다(I-1).

if(NOT caps_out MATCHES "\"resolutionsDPI\":\\[([^]]*)\\]")
    message(FATAL_ERROR "해상도 목록을 못 읽었다.")
endif()
string(REPLACE "," ";" epson_resolutions "${CMAKE_MATCH_1}")
list(LENGTH epson_resolutions epson_res_count)
expect("해상도를 열다섯 단계 모두 낸다" epson_res_count EQUAL 15)

file(TO_NATIVE_PATH "${WORKDIR}/args-dpi.log" ARGLOG_DPI)

foreach(dpi IN LISTS epson_resolutions)
    file(REMOVE "${ARGLOG_DPI}")
    set(ENV{NEGAFLOW_VSCAN_ARGLOG} "${ARGLOG_DPI}")

    string(REPLACE "\"resolutionDPI\":2400" "\"resolutionDPI\":${dpi}" dpi_request "${request}")
    string(REPLACE "out.tiff" "dpi-${dpi}.tiff" dpi_request "${dpi_request}")
    file(WRITE "${WORKDIR}/dpi-${dpi}.json" "${dpi_request}")

    execute_process(
        COMMAND "${PLUGIN}" scan
        INPUT_FILE "${WORKDIR}/dpi-${dpi}.json"
        OUTPUT_VARIABLE dpi_out
        ERROR_VARIABLE dpi_err
        RESULT_VARIABLE dpi_code)

    if(NOT dpi_code EQUAL 0)
        message(SEND_ERROR "FAIL  ${dpi} dpi 스캔이 ${dpi_code} 로 끝났다.\n${dpi_out}")
    else()
        file(READ "${ARGLOG_DPI}" dpi_args)
        string(FIND "${dpi_args}" "--resolution ${dpi} " found_dpi_arg)
        if(found_dpi_arg GREATER -1)
            message(STATUS "PASS  ${dpi} dpi 를 그대로 보낸다")
        else()
            message(SEND_ERROR "FAIL  ${dpi} dpi 가 인자에 그대로 안 나갔다.\n${dpi_args}")
        endif()
    endif()
endforeach()

# 보간 해상도. epson2 의 word list 에 없으므로 거절해야 한다.
foreach(dpi 9600 12800 5000)
    string(REPLACE "\"resolutionDPI\":2400" "\"resolutionDPI\":${dpi}" bad_request "${request}")
    file(WRITE "${WORKDIR}/dpi-bad-${dpi}.json" "${bad_request}")
    execute_process(
        COMMAND "${PLUGIN}" scan
        INPUT_FILE "${WORKDIR}/dpi-bad-${dpi}.json"
        OUTPUT_VARIABLE bad_dpi_out
        RESULT_VARIABLE bad_dpi_code)
    expect("목록에 없는 ${dpi} dpi 는 거절한다" bad_dpi_code EQUAL 1)
endforeach()

set(ENV{NEGAFLOW_VSCAN_ARGLOG} "${ARGLOG}")

message(STATUS "epson-smoke 통과")
