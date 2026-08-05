// negaflow-scanner-sane — 병합 피크 메모리 측정.
//
// exposure-merge.md §7.2.1 이 적어 둔 수치를 **다시 확인할 수 있게** 하는 도구다.
// 검증 불가능한 숫자는 문서에 적지 않는다는 것이 이 저장소의 원칙이라
// (field-lessons §9b.1), 측정값을 적었으면 재현 수단도 함께 둔다.
//
// 테스트가 아니다 — 단언하지 않고 숫자만 낸다. RSS 는 할당자와 OS 에 따라
// 흔들리므로 CI 게이트로 쓰기에 적합하지 않다. **비율을 본다.**
//
// macOS / Linux 전용(getrusage). Windows 에서는 GetProcessMemoryInfo 가 필요하다.
//
//   c++ -std=c++20 -O2 -ffp-contract=off -Iwindows/src \
//       -o /tmp/bench windows/tools/merge-memory-bench.cpp \
//       windows/src/imaging/merge.cpp windows/src/imaging/align.cpp \
//       windows/src/util/numeric.cpp
//   /tmp/bench old      정규화 N장을 병합 내내 살려 둔 옛 구조
//   /tmp/bench          현재 구조
//
// 두 실행의 **체크값이 같아야 한다.** 다르면 메모리를 줄이면서 결과를 바꾼 것이다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#include <sys/resource.h>

#include <cstdio>
#include <string>
#include <vector>

#include "imaging/merge.h"

using namespace negaflow::imaging;

namespace {

/// macOS 는 ru_maxrss 가 바이트, Linux 는 KB 다.
long peakMegabytes() {
    rusage usage{};
    getrusage(RUSAGE_SELF, &usage);
#ifdef __APPLE__
    return usage.ru_maxrss / (1024 * 1024);
#else
    return usage.ru_maxrss / 1024;
#endif
}

}  // namespace

int main(int argc, char** argv) {
    // "old" 를 주면 정규화 N장을 병합 내내 살려 둔다 — 지연 계산 이전의 구조다.
    const bool holdNormalized = argc > 1 && std::string(argv[1]) == "old";

    // 12 패스는 NEGAFLOW_HWEXP_SAMPLES=4 의 최대 계획이다(§2).
    const int passes = 12;
    const int width = 700;
    const int height = 500;
    const int referenceExposure = 14000;

    std::vector<std::vector<float>> storage;
    std::vector<int> exposureTimes;
    storage.reserve(static_cast<std::size_t>(passes));
    for (int p = 0; p < passes; ++p) {
        std::vector<float> image(static_cast<std::size_t>(width) * height * 4, 0.0f);
        for (std::size_t i = 0; i < image.size(); ++i) {
            image[i] = (i % 4 == 3)
                           ? 1.0f
                           : static_cast<float>((i * 7919 + static_cast<std::size_t>(p) * 104729) %
                                                65536) /
                                 65535.0f;
        }
        storage.push_back(std::move(image));
        exposureTimes.push_back(p < 4 ? 11000 : (p < 8 ? 14000 : 30000));
    }

    ImageList rendered;
    rendered.reserve(storage.size());
    for (const auto& s : storage) rendered.emplace_back(s);

    const long inputMB =
        static_cast<long>(passes) * width * height * 4 * 4 / (1024 * 1024);

    std::vector<std::vector<float>> oldNormalized;
    if (holdNormalized) {
        for (int p = 0; p < passes; ++p) {
            const auto i = static_cast<std::size_t>(p);
            oldNormalized.push_back(
                normalizeExposure(rendered[i], exposureTimes[i], referenceExposure));
        }
    }

    const auto out = mergeHardwareExposureBitmap(rendered, exposureTimes, width, height);
    if (out.failure) {
        std::printf("병합 실패: %s\n", std::string(failureMessage(*out.failure)).c_str());
        return 1;
    }

    // 체크값은 결과가 바뀌지 않았음을 보는 용도다. 두 실행에서 같아야 한다.
    unsigned long long checksum = 0;
    for (std::uint16_t v : out.bitmap.pixels) checksum += v;

    std::printf("%s  패스 %d  %dx%d  입력 %ld MB  피크 %ld MB  체크 %llu\n",
                holdNormalized ? "옛구조" : "현재  ", passes, width, height, inputMB,
                peakMegabytes(), checksum);
    return 0;
}
