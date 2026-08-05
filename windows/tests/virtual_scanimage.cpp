// negaflow-scanner-sane — Windows adapter
// virtual_scanimage — 실기 없이 어댑터 전체를 돌리기 위한 가짜 `scanimage`.
//
// 정본 문서: windows_docs/03-process-and-io/child-process.md §13.1
//
// **libtiff 도 우리 코드도 링크하지 않는다.** TIFF 를 손으로 쓴다 — 우리
// writer 로 만들면 "우리가 쓴 것을 우리가 읽는다"가 되어 검증이 자기 자신을
// 확인하는 꼴이 된다. 여기서 확인하려는 것은 **어댑터가 남이 만든 TIFF 를
// 받아 계약대로 처리하는가**다.
//
// 시나리오는 `NEGAFLOW_VSCAN_SCENARIO` 로 준다.
//
// ```text
// (없음)      정상. 진행률을 내고 유효한 TIFF 를 쓴다
// stall       진행률을 한 번 내고 멈춘다 → 워치독의 Stalled 경로
// silent      아무것도 내지 않고 멈춘다  → 워치독의 FirstProgress 경로
// fail        exit 1 + stderr 오류
// stale       exit 1 + "open of device failed: Invalid argument" → 재시도 경로
// stale-once  **첫 획득만** 위와 같이 실패하고 그 뒤로는 정상.
//             실기에서 가장 흔한 실패다 — 장치를 열 때마다 libusb 주소가
//             바뀌므로 첫 open 이 죽은 주소를 태운다.
//             `NEGAFLOW_VSCAN_MARKER` 가 가리키는 파일로 상태를 남긴다
//             (프로세스가 매번 새로 뜨므로 메모리로는 셀 수 없다).
// rounded     exit 0 인데 "rounded value of" 경고 → I-1 로 결과를 버려야 한다
// bigout      1 MiB 넘는 stdout+stderr → 파이프 교착 재현
// ```
//
// SPDX-License-Identifier: GPL-2.0-or-later

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <fcntl.h>
#include <io.h>
#include <stdio.h>

#include <chrono>
#include <cstdint>
#include <string>
#include <thread>
#include <vector>

namespace {

void writeHandle(DWORD stream, const void* data, std::size_t size) {
    HANDLE handle = GetStdHandle(stream);
    if (handle == nullptr || handle == INVALID_HANDLE_VALUE) return;
    const auto* bytes = static_cast<const unsigned char*>(data);
    std::size_t offset = 0;
    while (offset < size) {
        const DWORD request = static_cast<DWORD>(
            (size - offset) > (1u << 20) ? (1u << 20) : (size - offset));
        DWORD written = 0;
        if (WriteFile(handle, bytes + offset, request, &written, nullptr) == 0) return;
        if (written == 0) return;
        offset += written;
    }
}

void out(const std::string& text) { writeHandle(STD_OUTPUT_HANDLE, text.data(), text.size()); }
void err(const std::string& text) { writeHandle(STD_ERROR_HANDLE, text.data(), text.size()); }

[[nodiscard]] std::string environmentValue(const char* name) {
    char buffer[4096];
    const DWORD length = GetEnvironmentVariableA(name, buffer, sizeof(buffer));
    if (length == 0 || length >= sizeof(buffer)) return {};
    return std::string(buffer, length);
}

void put16(std::vector<unsigned char>& v, std::uint16_t value) {
    v.push_back(static_cast<unsigned char>(value & 0xFFu));
    v.push_back(static_cast<unsigned char>((value >> 8) & 0xFFu));
}

void put32(std::vector<unsigned char>& v, std::uint32_t value) {
    v.push_back(static_cast<unsigned char>(value & 0xFFu));
    v.push_back(static_cast<unsigned char>((value >> 8) & 0xFFu));
    v.push_back(static_cast<unsigned char>((value >> 16) & 0xFFu));
    v.push_back(static_cast<unsigned char>((value >> 24) & 0xFFu));
}

void entry(std::vector<unsigned char>& v, std::uint16_t tag, std::uint16_t type,
           std::uint32_t count, std::uint32_t value) {
    put16(v, tag);
    put16(v, type);
    put32(v, count);
    // SHORT 하나는 4바이트 칸의 **앞쪽 2바이트**에 들어간다(little-endian).
    put32(v, value);
}

/// 무압축 단일 스트립 TIFF 를 손으로 만든다.
///
/// 태그는 오름차순이어야 한다(TIFF 6.0). 순서가 틀리면 libtiff 가 경고를
/// 내면서도 읽어 주기 때문에, 여기서 어겨도 테스트는 통과해 버린다 —
/// 그래서 규격대로 쓴다.
[[nodiscard]] std::vector<unsigned char> makeTiff(int width, int height, int samples,
                                                  int bitsPerSample) {
    const std::size_t sampleBytes = static_cast<std::size_t>(bitsPerSample / 8);
    const std::size_t dataSize = static_cast<std::size_t>(width) * height * samples * sampleBytes;

    std::vector<unsigned char> file;
    file.reserve(dataSize + 512);
    file.push_back('I');
    file.push_back('I');
    put16(file, 42);
    put32(file, static_cast<std::uint32_t>(8 + dataSize));  // IFD 위치

    // 픽셀. 가로·세로로 값이 변하는 패턴이라 상하 반전이나 stride 오류가
    // 그대로 드러난다.
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            for (int c = 0; c < samples; ++c) {
                const unsigned value =
                    static_cast<unsigned>((x * 7 + y * 13 + c * 29) % 251) * 257u;
                if (sampleBytes == 2) {
                    put16(file, static_cast<std::uint16_t>(value));
                } else {
                    file.push_back(static_cast<unsigned char>(value >> 8));
                }
            }
        }
    }

    const std::uint32_t ifdOffset = static_cast<std::uint32_t>(8 + dataSize);
    const std::uint16_t entryCount = 12;
    const std::uint32_t ifdSize = 2u + entryCount * 12u + 4u;
    const std::uint32_t bitsOffset = ifdOffset + ifdSize;
    const std::uint32_t formatOffset = bitsOffset + static_cast<std::uint32_t>(samples * 2);

    put16(file, entryCount);
    entry(file, 256, 4, 1, static_cast<std::uint32_t>(width));   // ImageWidth (LONG)
    entry(file, 257, 4, 1, static_cast<std::uint32_t>(height));  // ImageLength
    if (samples == 1) {
        entry(file, 258, 3, 1, static_cast<std::uint32_t>(bitsPerSample));  // 인라인
    } else {
        entry(file, 258, 3, static_cast<std::uint32_t>(samples), bitsOffset);
    }
    entry(file, 259, 3, 1, 1);  // Compression = none
    entry(file, 262, 3, 1, samples == 1 ? 1u : 2u);  // MinIsBlack / RGB
    entry(file, 273, 4, 1, 8);                       // StripOffsets
    entry(file, 274, 3, 1, 1);                       // Orientation = TopLeft
    entry(file, 277, 3, 1, static_cast<std::uint32_t>(samples));
    entry(file, 278, 4, 1, static_cast<std::uint32_t>(height));  // RowsPerStrip
    entry(file, 279, 4, 1, static_cast<std::uint32_t>(dataSize));
    entry(file, 284, 3, 1, 1);  // PlanarConfig = contig
    if (samples == 1) {
        entry(file, 339, 3, 1, 1);  // SampleFormat = UINT
    } else {
        entry(file, 339, 3, static_cast<std::uint32_t>(samples), formatOffset);
    }
    put32(file, 0);  // 다음 IFD 없음

    if (samples > 1) {
        for (int i = 0; i < samples; ++i) put16(file, static_cast<std::uint16_t>(bitsPerSample));
        for (int i = 0; i < samples; ++i) put16(file, 1);
    }
    return file;
}

constexpr const char* kDeviceName = "genesys:libusb:001:002";

/// 필름 스캐너 하나를 흉내낸 `-A` 덤프. 실제 genesys 출력 형태를 따른다.
[[nodiscard]] std::string optionDump(bool grayMode) {
    std::string dump;
    dump += "Options specific to device `";
    dump += kDeviceName;
    dump += "':\n";
    dump += "  Scan Mode:\n";
    dump += std::string("    --mode Color|Gray [") + (grayMode ? "Gray" : "Color") + "]\n";
    dump += "    --source Transparency Adapter|Transparency Adapter Infrared "
            "[Transparency Adapter]\n";
    dump += "    --resolution 7200|3600|2400|1200|600dpi [1200]\n";
    dump += "    --depth 8|16 [16]\n";
    dump += "    --preview[=(yes|no)] [no]\n";
    dump += "  Enhancement:\n";
    dump += "    --brightness -100..100 (in steps of 1) [0]\n";
    dump += "    --contrast -100..100 (in steps of 1) [0]\n";
    // 다중 노출 계획(11000/14000/30000)이 **전부** 범위에 정확히 있어야
    // `supportsMultiExposure` 가 켜진다. 하나라도 빠지면 그 경로가 통째로
    // 검증되지 않는다.
    dump += "    --scan-exposure-time 1000..60000 (in steps of 1) [11000]\n";
    // **step 을 일부러 넣지 않는다.** 실제 genesys 는 step 을 내지만, 그러면
    // 최대값조차 `containsExactly` 를 통과하지 못해(36.33 / 0.0211639 가
    // 정수가 아니다) 시나리오가 옵션 계약이 아니라 산술에서 걸린다.
    // 연속 범위를 내는 백엔드도 실제로 있다.
    dump += "  Geometry:\n";
    dump += "    -l 0..36.33mm [0]\n";
    dump += "    -t 0..24.5mm [0]\n";
    dump += "    -x 0..36.33mm [36.33]\n";
    dump += "    -y 0..24.5mm [24.5]\n";
    return dump;
}

}  // namespace

int main(int argc, char** argv) {
    (void)_setmode(_fileno(stdout), _O_BINARY);
    (void)_setmode(_fileno(stderr), _O_BINARY);

    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);

    const std::string scenario = environmentValue("NEGAFLOW_VSCAN_SCENARIO");
    const auto has = [&](const std::string& flag) {
        for (const auto& a : args) {
            if (a == flag) return true;
        }
        return false;
    };
    const auto valueOf = [&](const std::string& flag) -> std::string {
        for (std::size_t i = 0; i + 1 < args.size(); ++i) {
            if (args[i] == flag) return args[i + 1];
        }
        return {};
    };

    // --- 장치 목록 ---------------------------------------------------------
    if (has("-f") || has("--formatted-device-list")) {
        const std::string format = valueOf("-f");
        // 우리 어댑터는 `%d\t%v\t%m\t%t%n` 만 쓴다. 다른 형식이 오면 흉내내지
        // 않고 실패시킨다 — 조용히 다른 것을 주면 파서 버그를 못 잡는다.
        if (format.find("%d") == std::string::npos) {
            err("scanimage: unsupported format\n");
            return 1;
        }
        out(std::string(kDeviceName) + "\tPlustek\tOpticFilm 8100\tfilm scanner\n");
        return 0;
    }
    if (has("-L") || has("--list-devices")) {
        out(std::string("device `") + kDeviceName + "' is a Plustek OpticFilm 8100 film scanner\n");
        return 0;
    }

    // --- 옵션 덤프 ---------------------------------------------------------
    if (has("-A") || has("--all-options")) {
        if (scenario == "stale") {
            err("scanimage: open of device " + valueOf("-d") +
                " failed: Invalid argument\n");
            return 1;
        }
        const std::string mode = valueOf("--mode");
        out(optionDump(mode == "Gray"));
        return 0;
    }

    // --- 획득 ---------------------------------------------------------------
    if (scenario == "fail") {
        err("scanimage: sane_start: Device busy\n");
        return 1;
    }
    if (scenario == "stale") {
        err("scanimage: open of device " + valueOf("-d") + " failed: Invalid argument\n");
        return 1;
    }
    if (scenario == "stale-once") {
        const std::string marker = environmentValue("NEGAFLOW_VSCAN_MARKER");
        if (!marker.empty() && GetFileAttributesA(marker.c_str()) == INVALID_FILE_ATTRIBUTES) {
            HANDLE touch = CreateFileA(marker.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                                       FILE_ATTRIBUTE_NORMAL, nullptr);
            if (touch != INVALID_HANDLE_VALUE) CloseHandle(touch);
            err("scanimage: open of device " + valueOf("-d") +
                " failed: Invalid argument\n");
            return 1;
        }
    }
    if (scenario == "silent") {
        std::this_thread::sleep_for(std::chrono::seconds(600));
        return 0;
    }

    const std::string source = valueOf("--source");
    const std::string mode = valueOf("--mode");
    const bool infraredPass =
        source.find("Infrared") != std::string::npos || mode.find("Infrared") != std::string::npos;
    const int samples = (infraredPass || mode == "Gray") ? 1 : 3;
    const std::string depth = valueOf("--depth");
    const int bits = depth == "8" ? 8 : 16;

    if (scenario == "bigout") {
        // 파이프 버퍼(64 KiB)를 확실히 넘긴다. 어댑터가 stdout·stderr 를
        // 동시에 읽지 않으면 여기서 교착한다.
        const std::string filler(1u << 20, 'x');
        err(filler);
    }

    err("scanimage: scanning image of size 700x500 pixels at 48 bits/pixel\n");
    for (int percent = 0; percent <= 100; percent += 20) {
        err("Progress: " + std::to_string(percent) + ".0%\r");
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    err("\n");
    if (scenario == "stall") {
        std::this_thread::sleep_for(std::chrono::seconds(600));
        return 0;
    }
    if (scenario == "rounded") {
        err("scanimage: rounded value of br-y from 24.5 to 24.4788\n");
    }

    const std::vector<unsigned char> tiff = makeTiff(70, 50, samples, bits);
    out(std::string(reinterpret_cast<const char*>(tiff.data()), tiff.size()));
    return 0;
}
