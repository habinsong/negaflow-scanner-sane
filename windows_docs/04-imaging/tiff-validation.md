# TIFF 검증과 입출력

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 이식 정본
코드 근거: `SANEBackend+ScanExecution.swift`(`validatedScannedTIFF`),
`SANEBackend+Environment.swift`(`imageSize`), `TIFFLoader.swift`,
`SANEBackend+TIFFWriting.swift`

관련 문서:

- [exact-option-contract](../02-frontend-contract/exact-option-contract.md)
- [numerical-parity](numerical-parity.md)
- [exposure-merge](exposure-merge.md)

## 1. 네 가지 연산

| 연산 | 현재 API | 용도 |
|---|---|---|
| 검증 | `CGImageSource*` | 결과 TIFF가 계약에 맞는지 |
| 크기 조회 | `CGImageSourceCopyPropertiesAtIndex` | IR 패스 결과 확인 |
| 로드 | `CGImageSourceCreateImageAtIndex` + `CIImage` | 다중 노출 병합 입력 |
| 쓰기 | `CGImageDestination*` | 다중 노출 병합 결과 |

Windows 대체: **libtiff를 1차로 쓰고, WIC로 교차 검증한다.**

## 2. 왜 libtiff인가

| 후보 | 장점 | 단점 |
|---|---|---|
| WIC | OS 내장, 의존 없음 | 태그 수준 제어가 약함. sample format, planar config, photometric 해석이 불투명 |
| libtiff | 태그 단위 완전 제어, 크로스 플랫폼, macOS와 같은 결과를 검증하기 쉬움 | 의존 추가, CVE 추적 필요 |

**결정: libtiff 1차.** 이유:

1. 검증 항목이 태그 수준이다(bits per sample, samples per pixel,
   photometric interpretation, planar configuration, page 개수).
   WIC의 `IWICBitmapDecoder`는 이것을 픽셀 포맷 GUID로 추상화해버려
   "16-bit gray"와 "16-bit 단일 채널 RGB의 첫 평면"을 구분하기 어렵다.
2. 우리는 이미 libtiff를 SANE 런타임 의존으로 배포한다
   ([building-sane](../01-sane-runtime/building-sane.md) §8,
   [gpl-compliance](../07-distribution/gpl-compliance.md) §3). 새 의존이 아니다.
3. macOS의 ImageIO와 동작을 비교할 때 libtiff가 기준선 역할을 한다.

WIC는 **교차 검증용**으로 쓴다. libtiff가 통과시킨 파일을 WIC도 열 수 있는지
확인하면, Windows 생태계의 다른 소비자(호스트 포함)가 그 파일을 읽을 수
있음을 보장할 수 있다.

negaflow 본체 windows_docs의 `05-image-io/libtiff.md`와
`10-scanner/protocol-contract.md` §10.2가 호스트 쪽 같은 결정을 다룬다.
어댑터와 호스트가 같은 판정을 내려야 한다.

### 2.1 vcpkg 포트와 기능 (2026-08-05 확인)

포트 이름은 **`libtiff` 가 아니라 `tiff`** 다. 기본 기능은
`[jpeg, lzma, zip]` 인데 우리는 **`zip` 만** 켠다.

```json
{ "name": "tiff", "default-features": false, "features": ["zip"] }
```

| 코덱 | 어떻게 얻는가 |
|---|---|
| 무압축 | 코어. 우리가 쓰는 형식이다 |
| LZW | **코어에 내장.** 기능이 필요 없다 |
| PackBits / CCITT | 코어에 내장 |
| Deflate | `zip` (zlib) |
| JPEG-in-TIFF | `jpeg` — **켜지 않는다** |
| LZMA / WebP / LERC | 켜지 않는다 |

`libdeflate` 는 Deflate 의 **대안이 아니라 가속기**다. upstream 이
`libdeflate AND ZIP_SUPPORT` 일 때만 켜고, vcpkg 쪽 기능도 `tiff[zip]` 를
요구한다. 단독으로 켜면 아무 일도 하지 않는다.

**대가**: JPEG-in-TIFF 를 만나면 런타임에 읽기가 실패한다. `scanimage` 는
만들지 않지만 확신할 수 없으므로, `imaging/tiff_io` 가 libtiff 메시지를
삼키지 않고 `lastTiffMessage()` 로 남긴다. 원인 없이 실패하지 않게 하는 것이
`jpeg` 를 켜는 것보다 낫다고 봤다 — 켜면 libjpeg-turbo 가 CVE 추적 대상에
들어온다.

**주의**: 다른 포트가 `tiff` 를 기본 기능으로 끌어오면(opencv, gdal 등)
`jpeg`/`lzma` 가 되돌아온다. 의존을 늘릴 때 확인한다.

## 3. 검증 계약 (`validatedScannedTIFF`)

입력: 파일 경로, 기대 심도, 기대 색 모드. 출력: `(width, height, bitDepth, colorMode)`.

### 3.1 파일 계층

```text
1. 파일 속성 읽기 성공                          실패 → ioFailure
2. regular file                                 아니면 → ioFailure
3. symbolic link 아님                           링크면 → ioFailure
4. 크기 > 0                                     0이면 → ioFailure
```

Windows 대응:

```text
CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, ...,
            FILE_FLAG_BACKUP_SEMANTICS 없이, ...)
GetFileInformationByHandle:
    dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY      → 거부
    dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT  → 거부
    nFileSizeHigh/Low == 0                           → 거부
GetFinalPathNameByHandleW → 기대 경로와 일치 확인
```

**핸들로 검증한 뒤 같은 핸들로 읽는다.** 경로로 검증하고 경로로 다시 열면
TOCTOU가 생긴다.

### 3.2 컨테이너 계층

```text
5. 이미지 소스 생성 성공                        실패 → ioFailure
6. CGImageSourceGetCount == 1                   아니면 → ioFailure
7. 타입 == "public.tiff"                        아니면 → ioFailure
```

libtiff 대응:

```text
TIFFClientOpen (핸들 기반 I/O 콜백 사용)        실패 → ioFailure
디렉터리 개수 세기:
    do { count++ } while (TIFFReadDirectory(tif));
count == 1                                      아니면 → ioFailure
```

**6번(단일 이미지)은 반드시 유지한다.** 멀티페이지 TIFF를 통과시키면
호스트가 첫 페이지만 보고 나머지를 무시하게 되고, 그것은 조용한
데이터 손실이다.

7번(TIFF 타입 확인)은 libtiff가 열었다는 사실 자체로 충족된다.
다만 매직 넘버(`II*\0` 또는 `MM\0*`)를 직접 확인하는 것이 더 명시적이다.
BigTIFF(`II+\0`)를 받아들일지 결정해야 한다 — `scanimage`는 만들지 않으므로
**거부한다.**

### 3.3 이미지 계층

```text
8. 첫 이미지 디코드 성공                        실패 → ioFailure
9. width > 0, height > 0                        아니면 → ioFailure
10. bitsPerComponent ∈ {8, 16}                  아니면 → ioFailure
11. colorSpace.model이 rgb 또는 monochrome      아니면 → ioFailure
12. 실제 심도 == 기대 심도                      아니면 → ioFailure
13. 실제 색 모드 == 기대 색 모드                아니면 → ioFailure
```

libtiff 대응:

```text
TIFFGetField(tif, TIFFTAG_IMAGEWIDTH, &w)          필수, w > 0
TIFFGetField(tif, TIFFTAG_IMAGELENGTH, &h)         필수, h > 0
TIFFGetField(tif, TIFFTAG_BITSPERSAMPLE, &bps)     필수, bps ∈ {8, 16}
TIFFGetField(tif, TIFFTAG_SAMPLESPERPIXEL, &spp)   필수
TIFFGetField(tif, TIFFTAG_PHOTOMETRIC, &photo)     필수

색 모드 판정:
    photo == PHOTOMETRIC_RGB       && spp >= 3   → color
    photo == PHOTOMETRIC_MINISBLACK && spp == 1  → gray
    photo == PHOTOMETRIC_MINISWHITE && spp == 1  → gray (반전 주의, §3.5)
    그 외                                        → ioFailure
```

**8번(실제 디코드)이 중요하다.** 헤더만 읽고 통과시키면 손상된 스트립을
가진 파일이 통과한다. 현재 macOS 코드는 `CGImageSourceCreateImageAtIndex`로
실제 이미지를 만든다.

libtiff에서 최소 비용으로 같은 보장을 얻는 방법:

```text
첫 스트립/타일 하나를 실제로 읽는다
TIFFReadEncodedStrip(tif, 0, buf, (tsize_t)-1) >= 0
```

전체를 읽을 필요는 없다. 마지막 스트립도 읽으면 더 강하지만 비용이 든다.
**첫 스트립과 마지막 스트립을 읽는 것을 권장한다.** 잘린 파일이
가장 흔한 손상 형태이기 때문이다.

negaflow 본체 문서는 호스트가 "small thumbnail decode도 성공"을 요구한다.
어댑터는 그보다 약한 검사로 충분하다 — 호스트가 다시 볼 것이므로.

### 3.4 반드시 추가할 검사 (macOS에 없는 것)

Windows 구현에서 태그 수준 접근이 가능해지므로 강화한다.

```text
TIFFTAG_SAMPLEFORMAT:
    없거나 SAMPLEFORMAT_UINT이어야 함
    SAMPLEFORMAT_IEEEFP(float TIFF)를 16-bit로 오인하지 않도록

TIFFTAG_PLANARCONFIG:
    PLANARCONFIG_CONTIG여야 함
    PLANARCONFIG_SEPARATE는 픽셀 레이아웃이 달라 병합 코드가 깨진다

TIFFTAG_COMPRESSION:
    읽을 수만 있으면 무엇이든 허용 (scanimage는 보통 무압축)
    진단에 기록

TIFFTAG_EXTRASAMPLES:
    RGB에서 spp > 3이면 extrasamples가 명시돼 있어야 함
```

이 검사들은 **macOS 동작을 더 엄격하게 만든다.** 즉 macOS에서 통과하던
파일이 Windows에서 거부될 수 있다. 실무적으로 `scanimage`가 그런 파일을
만들지 않으므로 위험이 낮지만, **결정으로 기록한다.**

```text
D-10  Windows 어댑터는 macOS보다 엄격한 TIFF 검사를 수행한다.
      SAMPLEFORMAT, PLANARCONFIG를 추가로 확인한다.
      같은 검사를 macOS에도 추가하는 것을 권장하되 이 문서의 범위는 아니다.
```

### 3.5 `PHOTOMETRIC_MINISWHITE`

`MINISWHITE`는 0이 흰색이다. `MINISBLACK`과 픽셀 의미가 반대다.

현재 macOS 코드는 `colorSpace.model == .monochrome`만 보므로 둘을 구분하지
않는다. ImageIO가 내부에서 어떻게 처리하는지 불투명하다.

**Windows에서는 명시적으로 결정한다.**

```text
권장: MINISWHITE를 거부한다.
```

이유: IR 채널의 밀도 의미가 반전되면 negaflow의 GrainMend IR이 정확히
반대로 동작한다. `scanimage`가 gray를 `MINISWHITE`로 내는 백엔드가 있는지
확인하고(spike I-1), 있다면 그때 변환 규칙을 정한다.

## 4. 크기 조회 (`imageSize`)

```text
imageSize(at url) -> (Int, Int):
    소스 생성 실패 → (0, 0)
    속성 읽기 실패 → (0, 0)
    PixelWidth/PixelHeight 없음 → (0, 0)
    → (w, h)
```

IR 패스 후 결과가 읽히는지만 본다. 실패해도 예외가 아니라 `(0,0)`이고,
호출자가 그것을 보고 IR을 버린다.

```text
let (w, h) = Self.imageSize(at: irURL)
guard w > 0, h > 0 else {
    IR 파일 삭제
    return (nil, ["Infrared pass produced an unreadable image; IR channel dropped."])
}
```

libtiff 대응은 헤더만 읽으면 된다. **실패를 예외로 바꾸지 않는다.**
IR 실패는 본 스캔을 무효화하지 않는다는 것이 계약이다.

## 5. 로드 (`TIFFLoader.loadScannerTIFF`)

```text
CGImageSourceCreateWithURL
CGImageSourceCreateImageAtIndex(src, 0, nil)
CIImage(cgImage: cg, options: [.colorSpace: linearSRGB])
```

**핵심**: `.colorSpace: linearSRGB`는 **변환이 아니라 재해석**이다.
파일의 픽셀 값을 그대로 두고 "이 값들은 선형 sRGB 좌표다"라고 선언한다.

Windows 구현은 이것을 훨씬 단순하게 할 수 있다.

```text
libtiff로 픽셀을 읽어 uint16 버퍼에 담는다
색 변환을 하지 않는다
값 / 65535.0 → float
```

즉 **CIImage 계층이 필요 없다.** 병합 코드가 원하는 것은 결국
`[Float]` RGBA 버퍼이고, 그것을 직접 만들면 된다.
자세한 것은 [numerical-parity](numerical-parity.md) §3.

## 6. 쓰기 (`writeRGB16TIFF`)

현재 구현:

```text
pixels: [UInt16] (RGB 인터리브, 알파 없음)
각 값을 bigEndian으로 변환
Data로 만들고 CGDataProvider
CGImage(width, height, bitsPerComponent: 16, bitsPerPixel: 48,
        bytesPerRow: width * 3 * 2,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: alphaInfo.none)
CGImageDestinationCreateWithURL(url, "public.tiff", 1, nil)
AddImage + Finalize
```

**주의**: 픽셀을 bigEndian으로 뒤집는데, `CGImage`의 bitmapInfo에
byte order 플래그가 없다. 기본은 호스트 순서(Apple Silicon = little endian)다.
즉 이 코드는 **의도적으로 바이트를 뒤집은 뒤 host order로 해석하게 하고
있다.**

이것이 실제로 무엇을 만드는지는 검증이 필요하다. 두 가지 가능성:

1. 결과 TIFF가 big-endian(`MM`) 바이트 순서로 저장되고 픽셀 값이 올바르다
2. 픽셀 값이 뒤집힌 채 저장된다(버그)

`SANEBackendMultiSampleTests.swift`(219행)와
`SANEBackendHardwareExposureTests.swift`(151행)가 이 경로를 테스트하고 있으므로
2번은 아닐 가능성이 높지만, **이식 전에 실제 산출물의 바이트를 확인한다**
→ spike I-2.

### 6.1 libtiff 구현

```text
TIFFOpenW(path, "w")
TIFFSetField(tif, TIFFTAG_IMAGEWIDTH, width)
TIFFSetField(tif, TIFFTAG_IMAGELENGTH, height)
TIFFSetField(tif, TIFFTAG_BITSPERSAMPLE, 16)
TIFFSetField(tif, TIFFTAG_SAMPLESPERPIXEL, 3)
TIFFSetField(tif, TIFFTAG_PHOTOMETRIC, PHOTOMETRIC_RGB)
TIFFSetField(tif, TIFFTAG_PLANARCONFIG, PLANARCONFIG_CONTIG)
TIFFSetField(tif, TIFFTAG_SAMPLEFORMAT, SAMPLEFORMAT_UINT)
TIFFSetField(tif, TIFFTAG_ORIENTATION, ORIENTATION_TOPLEFT)
TIFFSetField(tif, TIFFTAG_COMPRESSION, COMPRESSION_NONE)   // 또는 LZW
TIFFSetField(tif, TIFFTAG_ROWSPERSTRIP, TIFFDefaultStripSize(tif, 0))
행 단위로 TIFFWriteScanline
TIFFClose
```

**libtiff가 바이트 순서를 알아서 처리한다.** 호스트 순서로 값을 주면
libtiff가 파일 헤더에 맞춰 쓴다. 수동 endian 변환을 하지 않는다.

압축: `TIFFLoader.saveScannerTIFF`는 LZW(5)를 쓰지만
`writeRGB16TIFF`는 압축을 지정하지 않는다. 두 경로가 다르다.
**Windows에서는 무압축으로 통일한다.** 이유:

- 중간 산출물이며 곧 호스트가 읽어 지운다
- LZW 압축은 랜덤한 스캐너 노이즈에서 효과가 거의 없고 CPU만 쓴다
- 파일 크기가 예측 가능해져 공간 확인이 쉽다

압축을 쓰기로 한다면 `COMPRESSION_ADOBE_DEFLATE`가 LZW보다 낫다.

### 6.2 원자적 쓰기

현재 코드는 대상 파일을 지우고 바로 쓴다. 쓰기 도중 크래시하면
불완전한 파일이 남는다.

3단계 검증이 그것을 잡아내므로(§3) 치명적이지 않지만, Windows에서는
같은 디렉터리에 임시 이름으로 쓰고 `MoveFileExW(..., MOVEFILE_REPLACE_EXISTING)`
하는 것이 낫다. 비용이 거의 없다.

**단 최종 출력 경로에는 적용하지 않는다.** 호스트가 그 정확한 경로에
파일이 나타나기를 기대하고, `CREATE_ALWAYS`로 이미 자식이 만들고 있다.
다중 노출 병합 결과처럼 우리가 직접 쓰는 파일에만 적용한다.

## 7. `writeLinearTIFF`

`.RGBAh`(half float) 형식으로 CIImage를 TIFF로 쓴다.
**현재 코드 어디에서도 호출되지 않는다.** 죽은 코드다.

이식 시 옮기지 않는다. 옮긴다면 "미사용" 주석을 명시한다.

## 8. Spike 명세

### I-1 — `scanimage` gray 출력의 photometric

```text
백엔드별로 gray 스캔 후:
tiffinfo out.tif | grep Photometric
MINISWHITE가 나오는 백엔드가 있는가?
```

### I-2 — `writeRGB16TIFF` 산출물 검증

macOS에서:

```text
1. 알려진 픽셀 값 배열로 writeRGB16TIFF 호출
2. tiffinfo, tiffdump으로 헤더 확인 (바이트 순서, 태그)
3. hexdump로 첫 픽셀 바이트 확인
4. 값이 입력과 일치하는가?
5. ICCPROFILE(34675) 태그가 있는가?          ← 색 계약
6. TRANSFERFUNCTION(301) 태그가 있는가?
```

결과가 Windows libtiff 구현의 기준이 된다. **불일치가 발견되면
macOS 버그이며 별도로 수정해야 한다.**

**5·6번이 색 계약을 건다.** 현재 코드는 `CGColorSpaceCreateDeviceRGB()`로
`CGImage`를 만들어 ImageIO에 넘긴다. DeviceRGB는 장치 종속 공간이라 보통
프로파일이 박히지 않지만, **ImageIO가 실제로 무엇을 쓰는지는 확인되지
않았다.**

본체는 이 플러그인의 출력을 **태그 없는 16-bit linear**로 재해석한다
([host-pipeline-contract](../10-lessons/host-pipeline-contract.md) §2).
프로파일이 박혀 있으면 본체가 감마 도메인으로 읽어 **색이 무너진다.**
스캔은 성공하고 검증도 통과하므로 가장 늦게 발견되는 종류의 실패다.

```text
5·6이 "태그 있음"으로 나오면
    → macOS 결함이다. 양 플랫폼에서 함께 고친다(I-20).
    → Windows는 어느 쪽이든 태그를 쓰지 않는다.
```

### I-3 — WIC 교차 검증

```text
libtiff로 만든 파일을 WIC로 연다
IWICBitmapDecoder → IWICBitmapFrameDecode → GetPixelFormat
GUID_WICPixelFormat48bppRGB가 나오는가?
GetSize가 일치하는가?
```

호스트가 WIC를 쓴다면 이 검증이 어댑터-호스트 호환성을 보장한다.

### I-4 — 큰 파일

```text
7200 dpi 35mm 컬러 16-bit ≈ 10200 × 6800 × 6 ≈ 416 MB
1. libtiff로 쓰기 시간
2. 읽기 시간
3. 32-bit 오버플로우 없는가 (libtiff의 tsize_t, toff_t)
4. 120 포맷(6×9)은 더 크다: 약 25500 × 17000 × 6 ≈ 2.6 GB
   → BigTIFF가 필요한 크기다. 4 GB 한계 확인
```

4번이 중요하다. **표준 TIFF는 4 GB를 넘을 수 없다.** 120 포맷 고해상도
스캔이 그 한계에 닿는다. 현재 macOS에서 이 조합이 실제로 동작하는지
확인되지 않았다. `scanimage` 자체가 만드는 파일이므로 우리 제어 밖이지만,
**병합 결과를 우리가 쓸 때는 우리 책임이다.**

한계에 닿으면 선택지:

- BigTIFF로 쓴다(호스트가 읽을 수 있어야 함 → 프로토콜 변경 수준)
- 그 조합을 능력에서 제외한다
- 압축을 쓴다(불확실한 완화)

→ [open-questions](../99-plan/open-questions.md) Q-11

## 9. 이식 체크리스트

`imaging/tiff_contract`(순수) + `imaging/tiff_io`(libtiff) 기준(2026-08-05).

- [x] 검증 13단계가 전부 있다 — 파일 계층은 §3.1 단서 참조
- [x] 단일 이미지 검사(6번)
- [ ] **핸들 기반 검증(TOCTOU 방지)** — Win32 미착수. §9.1
- [x] 실제 스트립 읽기(첫/마지막)
- [x] SAMPLEFORMAT, PLANARCONFIG 추가 검사
- [x] MINISWHITE 결정이 반영됨 — 거부한다
- [x] BigTIFF 거부
- [x] `imageSize` 실패가 예외가 아니다 — (0, 0)
- [x] 쓰기에서 수동 endian 변환을 하지 않는다
- [x] 병합 결과 쓰기가 원자적이다 — `.partial` 로 쓰고 rename
- [x] `writeLinearTIFF`를 옮기지 않았거나 미사용 표시 — 옮기지 않았다
- [ ] 4 GB 한계 동작이 정의됐다 — Q-11. I-4 미실행
- [ ] libtiff CVE 추적이 SBOM에 들어 있다 — M7

### 9.1 파일 계층이 아직 반쪽이다

지금 `validatedScannedTIFF` 는 `std::filesystem` 으로 regular file / symlink /
크기만 본다. §3.1 이 요구하는 것 중 **두 가지가 빠져 있다**:

```text
⬜ reparse point 거부        FILE_ATTRIBUTE_REPARSE_POINT
⬜ 핸들 기반 검증            경로로 검증하고 경로로 다시 열면 TOCTOU 다
```

`std::filesystem` 으로는 둘 다 할 수 없다 — 핸들을 유지한 채 libtiff 에
넘기려면 `TIFFClientOpen` 과 Win32 핸들 I/O 콜백이 필요하다. Win32 계층에서
붙인다.

**지금 상태는 macOS 와 같은 수준이다.** macOS 도 `URLResourceValues` 로
경로 기반 검증을 한다. 즉 이식이 뒤처진 것이 아니라 아직 강화하지 않은
것이다.

### 9.2 실측으로 확인한 것 (2026-08-05)

파리티 하네스가 **양방향 상호운용**을 대조한다.

```text
C++ libtiff 로 쓴 파일   → macOS ImageIO 로 읽기   픽셀 비트 동일
macOS ImageIO 로 쓴 파일 → C++ libtiff 로 읽기     픽셀 비트 동일
```

**파일 바이트는 다르다.** libtiff 는 `II`(little-endian, 314 B), ImageIO 는
`MM`(big-endian, 338 B)로 쓴다. 그런데 디코드된 픽셀은 같다 — §8 N-2 가
"바이트 순서가 달라도 픽셀 값이 같으면 통과"라고 정한 그대로다.

행마다 값을 다르게 준 픽스처라 **행 순서도 함께 검증된다**(위아래 뒤집힘
없음). 모든 행이 같은 픽스처였다면 이 검사는 통과해도 아무것도 증명하지
못했을 것이다.

그리고 우리 산출물의 태그를 직접 확인했다:

```text
bps=16 spp=3 photo=RGB planar=CONTIG pages=1
ICCProfile(34675)      없음 ✓
TransferFunction(301)  없음 ✓
```

**색 계약이 지켜진다.** 프로파일이 박히면 본체가 감마 도메인으로 읽어 색이
무너지는데, 스캔은 성공하고 검증도 통과하므로 가장 늦게 발견되는 실패다.
그래서 파리티가 매번 이 태그를 확인한다.
