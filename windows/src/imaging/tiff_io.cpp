// SPDX-License-Identifier: GPL-2.0-or-later

#include "imaging/tiff_io.h"

#include <tiffio.h>

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>
#include <memory>
#include <system_error>
#include <vector>

namespace negaflow::imaging::tiffio {

// tiff_contract.h 는 libtiff 를 포함하지 않으려고 상수를 직접 들고 있다.
// 그 값이 libtiff 와 어긋나면 **여기서 빌드가 깨진다.** 그것이 목적이다.
static_assert(tifftag::kPhotometricMinIsWhite == PHOTOMETRIC_MINISWHITE);
static_assert(tifftag::kPhotometricMinIsBlack == PHOTOMETRIC_MINISBLACK);
static_assert(tifftag::kPhotometricRGB == PHOTOMETRIC_RGB);
static_assert(tifftag::kPlanarConfigContig == PLANARCONFIG_CONTIG);
static_assert(tifftag::kPlanarConfigSeparate == PLANARCONFIG_SEPARATE);
static_assert(tifftag::kSampleFormatUInt == SAMPLEFORMAT_UINT);
static_assert(tifftag::kSampleFormatInt == SAMPLEFORMAT_INT);
static_assert(tifftag::kSampleFormatIEEEFP == SAMPLEFORMAT_IEEEFP);
static_assert(tifftag::kCompressionNone == COMPRESSION_NONE);

namespace {

/// libtiff 가 마지막으로 낸 메시지. 스레드마다 따로 둔다.
thread_local std::string g_lastMessage;

void captureMessage(const char* module, const char* format, va_list args) {
    char buffer[512];
    // vsnprintf 는 항상 널을 붙이고, 잘려도 음수를 내지 않는다.
    const int written = std::vsnprintf(buffer, sizeof(buffer), format ? format : "", args);
    g_lastMessage.assign(module ? module : "libtiff");
    g_lastMessage += ": ";
    g_lastMessage += (written > 0) ? buffer : "(형식화 실패)";
}

void onError(const char* module, const char* format, va_list args) {
    captureMessage(module, format, args);
}

void onWarning(const char* module, const char* format, va_list args) {
    captureMessage(module, format, args);
}

/// libtiff 는 기본적으로 stderr 에 직접 뱉는다. **우리 stderr 는 호스트가
/// 진단으로 읽으므로 오염시키면 안 된다.**
///
/// 그렇다고 nullptr 로 끄면 메시지가 통째로 사라진다 — 지원하지 않는 코덱
/// (예: JPEG-in-TIFF)을 만났을 때 "왜 못 읽었는지"가 남지 않는다.
/// **실패를 조용히 넘기지 않는다**(field-lessons §14). 그래서 삼키는 대신
/// 붙잡아 두고 `lastTiffMessage()` 로 꺼내 쓴다.
void installHandlersOnce() {
    static const bool done = [] {
        TIFFSetWarningHandler(onWarning);
        TIFFSetErrorHandler(onError);
        return true;
    }();
    (void)done;
}

struct TiffCloser {
    void operator()(TIFF* t) const noexcept {
        if (t) TIFFClose(t);
    }
};
using TiffHandle = std::unique_ptr<TIFF, TiffCloser>;

[[nodiscard]] TiffHandle openRead(const std::filesystem::path& path) {
    installHandlersOnce();
    g_lastMessage.clear();
#ifdef _WIN32
    // Windows 는 UTF-16 경로를 쓴다. narrow 로 넘기면 비ASCII 경로가 깨진다.
    return TiffHandle{TIFFOpenW(path.c_str(), "r")};
#else
    return TiffHandle{TIFFOpen(path.c_str(), "r")};
#endif
}

[[nodiscard]] TiffHandle openWrite(const std::filesystem::path& path) {
    installHandlersOnce();
    g_lastMessage.clear();
#ifdef _WIN32
    return TiffHandle{TIFFOpenW(path.c_str(), "w")};
#else
    return TiffHandle{TIFFOpen(path.c_str(), "w")};
#endif
}

/// BigTIFF 판정. libtiff 가 태그로 노출하지 않으므로 매직을 직접 본다.
///
/// ```text
/// 4949 2a00  "II*\0"   classic little-endian
/// 4d4d 002a  "MM\0*"   classic big-endian      ← macOS 산출물(I-2 확인)
/// 4949 2b00  "II+\0"   BigTIFF little-endian
/// 4d4d 002b  "MM\0+"   BigTIFF big-endian
/// ```
[[nodiscard]] bool looksLikeBigTiff(const std::filesystem::path& path) {
    std::FILE* fh = nullptr;
#ifdef _WIN32
    fh = _wfopen(path.c_str(), L"rb");
#else
    fh = std::fopen(path.c_str(), "rb");
#endif
    if (!fh) return false;
    unsigned char magic[4] = {0, 0, 0, 0};
    const size_t got = std::fread(magic, 1, sizeof(magic), fh);
    std::fclose(fh);
    if (got != sizeof(magic)) return false;
    if (magic[0] == 'I' && magic[1] == 'I') return magic[2] == 0x2B && magic[3] == 0x00;
    if (magic[0] == 'M' && magic[1] == 'M') return magic[2] == 0x00 && magic[3] == 0x2B;
    return false;
}

/// 태그가 없으면 기본값을 쓴다. libtiff 는 성공 시 0이 아닌 값을 낸다.
template <class T>
[[nodiscard]] T field(TIFF* tif, std::uint32_t tag, T fallback) {
    T value = fallback;
    if (TIFFGetField(tif, tag, &value) != 1) return fallback;
    return value;
}

[[nodiscard]] std::optional<TiffTags> readTagsFrom(TIFF* tif, const std::filesystem::path& path) {
    TiffTags tags;
    tags.width = field<std::uint32_t>(tif, TIFFTAG_IMAGEWIDTH, 0);
    tags.height = field<std::uint32_t>(tif, TIFFTAG_IMAGELENGTH, 0);
    tags.bitsPerSample = field<std::uint16_t>(tif, TIFFTAG_BITSPERSAMPLE, 0);
    tags.samplesPerPixel = field<std::uint16_t>(tif, TIFFTAG_SAMPLESPERPIXEL, 0);
    tags.photometric = field<std::uint16_t>(tif, TIFFTAG_PHOTOMETRIC, 0xFFFF);
    tags.planarConfig = field<std::uint16_t>(tif, TIFFTAG_PLANARCONFIG, PLANARCONFIG_CONTIG);
    tags.compression = field<std::uint16_t>(tif, TIFFTAG_COMPRESSION, COMPRESSION_NONE);

    // SAMPLEFORMAT 은 **없을 수 있다.** 없으면 규격 기본값(UINT)이므로
    // nullopt 로 남겨 계약 쪽이 "명시되지 않음"을 알게 한다.
    std::uint16_t sampleFormat = 0;
    if (TIFFGetField(tif, TIFFTAG_SAMPLEFORMAT, &sampleFormat) == 1) {
        tags.sampleFormat = sampleFormat;
    }

    std::uint16_t extraCount = 0;
    std::uint16_t* extraTypes = nullptr;
    if (TIFFGetField(tif, TIFFTAG_EXTRASAMPLES, &extraCount, &extraTypes) == 1) {
        tags.extraSamples = extraCount;
    }

    // 색 계약 진단용. 검증에 쓰지 않는다 — 우리 writer 가 붙이지 않았음을
    // 확인하는 것이 목적이다.
    std::uint32_t iccLength = 0;
    const void* iccData = nullptr;
    tags.hasIccProfile = TIFFGetField(tif, TIFFTAG_ICCPROFILE, &iccLength, &iccData) == 1;

    const std::uint16_t* transfer = nullptr;
    tags.hasTransferFunction = TIFFGetField(tif, TIFFTAG_TRANSFERFUNCTION, &transfer) == 1;

    // IFD 를 끝까지 훑는다. 첫 디렉터리로 돌아가지 않으므로 이 핸들은
    // 이후 픽셀 읽기에 쓰지 않는다.
    std::uint32_t count = 0;
    do {
        ++count;
    } while (TIFFReadDirectory(tif) == 1);
    tags.directoryCount = count;

    tags.bigTiff = looksLikeBigTiff(path);
    return tags;
}

}  // namespace

std::string_view lastTiffMessage() noexcept { return g_lastMessage; }

std::optional<TiffTags> readTags(const std::filesystem::path& path) {
    const TiffHandle tif = openRead(path);
    if (!tif) return std::nullopt;
    return readTagsFrom(tif.get(), path);
}

bool verifyDecodable(const std::filesystem::path& path) {
    const TiffHandle tif = openRead(path);
    if (!tif) return false;

    const tstrip_t strips = TIFFNumberOfStrips(tif.get());
    if (strips == 0) return false;

    std::vector<unsigned char> buffer(static_cast<size_t>(TIFFStripSize(tif.get())));
    if (buffer.empty()) return false;

    // 첫 스트립과 마지막 스트립만 본다. 잘린 파일이 가장 흔한 손상이고,
    // 전체를 읽으면 416 MB 짜리 스캔에서 검증만으로 수 초가 든다.
    if (TIFFReadEncodedStrip(tif.get(), 0, buffer.data(),
                             static_cast<tmsize_t>(buffer.size())) < 0) {
        return false;
    }
    if (strips > 1) {
        if (TIFFReadEncodedStrip(tif.get(), strips - 1, buffer.data(),
                                 static_cast<tmsize_t>(buffer.size())) < 0) {
            return false;
        }
    }
    return true;
}

TiffValidation validatedScannedTIFF(const std::filesystem::path& path,
                                    sane::BitDepth expectedBitDepth,
                                    sane::ColorMode expectedColorMode,
                                    ScannedTiffMetadata* out) {
    // --- 파일 계층 (§3.1) — Win32 핸들 검증은 아직 없다 -------------------
    std::error_code ec;
    const auto status = std::filesystem::symlink_status(path, ec);
    if (ec) return "scanimage 출력 파일을 읽을 수 없습니다.";
    const bool isSymlink = std::filesystem::is_symlink(status);
    const bool isRegular = std::filesystem::is_regular_file(status);
    std::uintmax_t size = 0;
    if (isRegular && !isSymlink) {
        size = std::filesystem::file_size(path, ec);
        if (ec) return "scanimage 출력 파일을 읽을 수 없습니다.";
    }
    if (auto bad = validateFileAttributes(isRegular, isSymlink, size)) return bad;

    // --- 컨테이너 + 이미지 + 추가 검사 -----------------------------------
    const auto tags = readTags(path);
    if (!tags) return "scanimage 출력 형식이 단일 TIFF가 아닙니다.";
    if (auto bad = validateScannedTiffTags(*tags, expectedBitDepth, expectedColorMode)) return bad;

    // --- 실제 디코드 (§3.3 8번) ------------------------------------------
    if (!verifyDecodable(path)) {
        return "scanimage TIFF를 실제 이미지로 decode할 수 없습니다.";
    }

    if (out) {
        out->width = static_cast<int>(tags->width);
        out->height = static_cast<int>(tags->height);
        out->bitDepth = tags->bitsPerSample == 8 ? sane::BitDepth::Eight : sane::BitDepth::Sixteen;
        out->colorMode = colorModeFromTags(*tags).value_or(sane::ColorMode::Color);
    }
    return std::nullopt;
}

std::optional<FloatBitmap> loadScannerTIFF(const std::filesystem::path& path) {
    const TiffHandle tif = openRead(path);
    if (!tif) return std::nullopt;

    const auto width = field<std::uint32_t>(tif.get(), TIFFTAG_IMAGEWIDTH, 0);
    const auto height = field<std::uint32_t>(tif.get(), TIFFTAG_IMAGELENGTH, 0);
    const auto bitsPerSample = field<std::uint16_t>(tif.get(), TIFFTAG_BITSPERSAMPLE, 0);
    const auto samplesPerPixel = field<std::uint16_t>(tif.get(), TIFFTAG_SAMPLESPERPIXEL, 0);
    const auto planarConfig =
        field<std::uint16_t>(tif.get(), TIFFTAG_PLANARCONFIG, PLANARCONFIG_CONTIG);

    if (width == 0 || height == 0 || samplesPerPixel == 0) return std::nullopt;
    if (bitsPerSample != 8 && bitsPerSample != 16) return std::nullopt;
    // SEPARATE 는 (y*w+x)*spp+c 인덱싱이 성립하지 않는다. 병합이 조용히 깨지는
    // 것보다 읽기를 거부하는 편이 낫다.
    if (planarConfig != PLANARCONFIG_CONTIG) return std::nullopt;

    const std::size_t scanlineBytes = static_cast<std::size_t>(TIFFScanlineSize(tif.get()));
    if (scanlineBytes == 0) return std::nullopt;
    std::vector<unsigned char> row(scanlineBytes);

    FloatBitmap out;
    out.width = static_cast<int>(width);
    out.height = static_cast<int>(height);
    out.pixels.assign(static_cast<std::size_t>(width) * height * 4, 0.0f);

    // 정규화 상수. **16-bit 경로가 N-1 이 증명한 것이다.**
    const float inverse = bitsPerSample == 16 ? (1.0f / 65535.0f) : (1.0f / 255.0f);

    for (std::uint32_t y = 0; y < height; ++y) {
        if (TIFFReadScanline(tif.get(), row.data(), y) < 0) return std::nullopt;
        for (std::uint32_t x = 0; x < width; ++x) {
            const std::size_t destination = (static_cast<std::size_t>(y) * width + x) * 4;
            float channel[3] = {0.0f, 0.0f, 0.0f};
            for (int c = 0; c < 3; ++c) {
                // 채널이 하나뿐이면(gray) 세 채널에 같은 값을 넣는다.
                const std::uint16_t sourceChannel =
                    samplesPerPixel >= 3 ? static_cast<std::uint16_t>(c) : 0;
                const std::size_t sample =
                    static_cast<std::size_t>(x) * samplesPerPixel + sourceChannel;
                std::uint32_t raw = 0;
                if (bitsPerSample == 16) {
                    std::uint16_t v = 0;
                    std::memcpy(&v, row.data() + sample * 2, sizeof(v));
                    raw = v;
                } else {
                    raw = row[sample];
                }
                // Swift 원본과 같은 나눗셈. 곱셈으로 바꾸면 결과가 달라진다.
                channel[c] = static_cast<float>(raw) * inverse;
            }
            out.pixels[destination] = channel[0];
            out.pixels[destination + 1] = channel[1];
            out.pixels[destination + 2] = channel[2];
            out.pixels[destination + 3] = 1.0f;
        }
    }
    return out;
}

bool writeRGB16TIFF(std::span<const std::uint16_t> pixels,
                    int width,
                    int height,
                    const std::filesystem::path& path) {
    if (width <= 0 || height <= 0) return false;
    const std::size_t needed = static_cast<std::size_t>(width) * height * 3;
    if (pixels.size() < needed) return false;

    // 같은 디렉터리에 임시 이름으로 쓴다 — 다른 볼륨이면 rename 이 원자적이지 않다.
    std::filesystem::path temporary = path;
    temporary += ".partial";

    {
        const TiffHandle tif = openWrite(temporary);
        if (!tif) return false;

        TIFFSetField(tif.get(), TIFFTAG_IMAGEWIDTH, static_cast<std::uint32_t>(width));
        TIFFSetField(tif.get(), TIFFTAG_IMAGELENGTH, static_cast<std::uint32_t>(height));
        TIFFSetField(tif.get(), TIFFTAG_BITSPERSAMPLE, static_cast<std::uint16_t>(16));
        TIFFSetField(tif.get(), TIFFTAG_SAMPLESPERPIXEL, static_cast<std::uint16_t>(3));
        TIFFSetField(tif.get(), TIFFTAG_PHOTOMETRIC,
                     static_cast<std::uint16_t>(PHOTOMETRIC_RGB));
        TIFFSetField(tif.get(), TIFFTAG_PLANARCONFIG,
                     static_cast<std::uint16_t>(PLANARCONFIG_CONTIG));
        TIFFSetField(tif.get(), TIFFTAG_SAMPLEFORMAT,
                     static_cast<std::uint16_t>(SAMPLEFORMAT_UINT));
        TIFFSetField(tif.get(), TIFFTAG_ORIENTATION,
                     static_cast<std::uint16_t>(ORIENTATION_TOPLEFT));
        // 무압축으로 통일한다. 중간 산출물이고, LZW 는 스캐너 노이즈에서
        // 효과가 거의 없이 CPU 만 쓴다.
        TIFFSetField(tif.get(), TIFFTAG_COMPRESSION,
                     static_cast<std::uint16_t>(COMPRESSION_NONE));
        TIFFSetField(tif.get(), TIFFTAG_ROWSPERSTRIP,
                     TIFFDefaultStripSize(tif.get(), 0));
        // ICC 프로파일과 TransferFunction 을 **넣지 않는다.**
        // 본체가 태그 없는 16-bit linear 로 재해석한다.

        for (int y = 0; y < height; ++y) {
            // libtiff 가 파일 바이트 순서에 맞춰 변환한다. 우리는 호스트 순서
            // 값을 그대로 넘긴다 — 손으로 뒤집으면 값이 망가진다.
            const auto* scanline = pixels.data() + static_cast<std::size_t>(y) * width * 3;
            // TIFFWriteScanline 은 버퍼를 수정할 수 있어 const 를 받지 않는다.
            // 압축이 없으므로 실제로는 건드리지 않지만 규약을 지켜 복사한다.
            std::vector<std::uint16_t> mutableRow(scanline,
                                                  scanline + static_cast<std::size_t>(width) * 3);
            if (TIFFWriteScanline(tif.get(), mutableRow.data(), static_cast<std::uint32_t>(y), 0) <
                0) {
                return false;
            }
        }
    }  // TIFFClose 가 여기서 불린다. rename 전에 닫혀야 한다.

    std::error_code ec;
    std::filesystem::rename(temporary, path, ec);
    if (ec) {
        std::filesystem::remove(temporary, ec);
        return false;
    }
    return true;
}

std::pair<int, int> imageSize(const std::filesystem::path& path) {
    const TiffHandle tif = openRead(path);
    if (!tif) return {0, 0};
    const auto width = field<std::uint32_t>(tif.get(), TIFFTAG_IMAGEWIDTH, 0);
    const auto height = field<std::uint32_t>(tif.get(), TIFFTAG_IMAGELENGTH, 0);
    // 실패를 예외로 바꾸지 않는다. 호출자가 (0,0) 을 보고 IR 을 버린다.
    return {static_cast<int>(width), static_cast<int>(height)};
}

}  // namespace negaflow::imaging::tiffio
