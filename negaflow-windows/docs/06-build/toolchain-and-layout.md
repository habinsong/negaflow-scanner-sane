# 툴체인·의존성·저장소 구조

기준일: 2026-08-04
상태: 설계
관련 문서:

- [language-decision](language-decision.md)
- [building-sane](../01-sane-runtime/building-sane.md)
- [packaging-and-install](../07-distribution/packaging-and-install.md)
- [gpl-compliance](../07-distribution/gpl-compliance.md)

## 1. 현재 macOS 툴체인

```text
Swift 5.9+ / SwiftPM
Xcode (DEVELOPER_DIR)
빌드: swift build -c release --triple {arm64,x86_64}-apple-macosx13.0
결합: lipo -create → universal
심볼: dsymutil
서명: codesign --options runtime --entitlements Config/Plugin.entitlements
공증: xcrun notarytool submit --wait
검증: codesign --verify --strict, spctl --assess, lipo -archs,
      dwarfdump --uuid
패키징: ditto -c -k, tar + gzip -n, shasum -a 256
provenance: python3 scripts/verify-provenance.py
CI: GitHub Actions, macos-26
```

## 2. Windows 툴체인

| 항목 | 선택 |
|---|---|
| 컴파일러 | MSVC (Visual Studio 2022 또는 후속) |
| 빌드 시스템 | CMake |
| 의존성 | vcpkg (매니페스트 모드) |
| 아키텍처 | x64, ARM64 (**별도 산출물**, universal 없음) |
| 심볼 | PDB |
| 서명 | `signtool` + Authenticode |
| 타임스탬프 | RFC 3161 |
| 패키징 | ZIP + MSI |
| CI | GitHub Actions, `windows-latest` + ARM64 |

### 2.1 왜 MSVC인가

- Windows SDK와 가장 잘 통합된다.
- Authenticode 서명 도구 체인이 표준이다.
- `/analyze` 정적 분석.
- **단 SANE 런타임은 MSVC로 빌드할 수 없다**(autotools 전용).
  런타임은 MSYS2/MinGW 툴체인으로 별도 빌드한다
  ([building-sane](../01-sane-runtime/building-sane.md)).

즉 **두 개의 툴체인이 공존한다.**

```text
어댑터 (negaflow-scanner-sane.exe)  ← MSVC / CMake / vcpkg
SANE 런타임 (scanimage.exe 등)       ← MSYS2 / MinGW / autotools
```

두 산출물이 프로세스 경계로 분리돼 있으므로 ABI 호환이 필요 없다.
**이것이 이 아키텍처의 이점 중 하나다.**

libtiff만 예외다. 어댑터도 libtiff를 쓴다.
어댑터용 libtiff는 vcpkg의 MSVC 빌드를 쓰고, SANE 런타임의 libtiff는
MinGW 빌드다. **두 개가 각자 링크된다.** 버전이 달라도 무방하지만
같게 유지하는 편이 진단에 유리하다.

### 2.2 ARM64

`clangarm64` MSYS2 환경에 sane 패키지가 있으므로 런타임은 가능하다.
어댑터는 MSVC ARM64로 빌드한다.

**universal binary가 없다.** macOS의 `lipo` 대응이 없으므로
x64와 ARM64를 별도 설치물로 배포한다.

x64 어댑터를 ARM64 Windows에서 에뮬레이션으로 돌릴 수는 있지만:

- 성능이 나쁘다(픽셀 연산이 무겁다)
- x64 `scanimage.exe`가 필요하고, libusb/WinUSB 계층이 에뮬레이션에서
  동작하는지 불확실하다

**ARM64 네이티브 설치물을 별도로 만든다.**

## 3. 의존성

### 3.1 어댑터

| 라이브러리 | 용도 | 라이선스 | 출처 |
|---|---|---|---|
| libtiff | TIFF 읽기/쓰기 | BSD-like | vcpkg |
| RapidJSON | JSON | MIT | vcpkg 또는 vendoring |
| zlib | libtiff 의존 | zlib | vcpkg |
| libjpeg-turbo | libtiff 의존(선택) | BSD-like | vcpkg |

**의존을 최소로 유지한다.** libtiff의 JPEG/LZW 지원을 끄면 의존이 줄지만,
`scanimage`가 만든 파일이 압축돼 있을 수 있으므로 읽기는 지원해야 한다.

`scanimage`의 TIFF writer가 무엇을 쓰는지 확인해 필요한 압축만 켠다.
→ spike B-1.

### 3.2 vcpkg 매니페스트

```json
{
  "name": "negaflow-scanner-sane",
  "version-string": "1.0.3",
  "dependencies": [
    { "name": "tiff", "default-features": false, "features": ["zip"] },
    "rapidjson"
  ],
  "builtin-baseline": "<고정 커밋>"
}
```

`builtin-baseline`을 고정한다. 재현 가능한 빌드의 전제다.

### 3.3 정적 링크

```text
어댑터는 모든 의존을 정적 링크한다.
MSVC 런타임도 /MT로 정적 링크한다.
```

이유:

- 플러그인 디렉터리에 DLL이 늘어나면 DLL 하이재킹 표면이 커진다.
- 사용자가 VC++ 재배포 패키지를 설치할 필요가 없다.
- 산출물이 하나의 exe다. 서명·해시·승인이 단순해진다.

**단 `negaflow-scanner-sane.exe`만 정적이다.** SANE 런타임 DLL들은
어차피 별도 프로세스가 로드한다.

`/MT`의 단점: 보안 업데이트가 나오면 재빌드해야 한다.
libtiff CVE도 마찬가지다. **SBOM에 정확한 버전을 기록하고 추적한다.**

## 4. CMake 구성

```cmake
cmake_minimum_required(VERSION 3.25)
project(negaflow-scanner-sane CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_compile_options(
    /W4 /WX
    /permissive-
    /fp:precise          # 기본이지만 명시
    /Zc:__cplusplus
    /Zc:preprocessor
    /guard:cf            # Control Flow Guard
    /GS                  # 버퍼 보안 검사
    /sdl                 # 추가 보안 검사
)
add_link_options(
    /DYNAMICBASE /NXCOMPAT /HIGHENTROPYVA
    /CETCOMPAT           # ARM64에서는 무시됨
    /DEBUG /OPT:REF /OPT:ICF
)
```

`/fp:fast`를 **절대 쓰지 않는다.** parity가 깨진다.

`/GL`(전체 프로그램 최적화)과 `/LTCG`는 부동소수점 결과를 바꾸지 않지만,
확인 없이 켜지 않는다. parity 픽스처를 두 설정 모두에서 돌려본다.

### 4.1 순수 함수 계층 격리

```cmake
add_library(sane_logic STATIC
    src/sane/option_dump.cpp
    src/sane/device_list.cpp
    src/sane/media.cpp
    src/sane/capabilities.cpp
    src/sane/validate.cpp
    src/sane/args.cpp
    src/util/numeric.cpp
)
target_link_libraries(sane_logic PRIVATE)   # 의존 없음
```

이 타깃이 Win32도 libtiff도 링크하지 않는다는 것이 계약이다.
`#include <windows.h>`가 들어가면 빌드가 깨지도록 강제한다.

## 5. 저장소 구조

두 가지 선택이 있다.

### 5.1 단일 저장소 (권장)

```text
negaflow-scanner-sane/
    Package.swift              macOS
    Sources/                   macOS Swift
    Tests/                     macOS Swift 테스트
    scripts/                   macOS 릴리스
    Installer/                 macOS PKG/DMG
    Formula/                   macOS Homebrew

    windows/
        CMakeLists.txt
        vcpkg.json
        src/
        tests/
        installer/             WiX 또는 대안
        scripts/               Windows 릴리스

    sane-runtime/              Windows SANE 재빌드
        PKGBUILD
        patches/
        build.sh

    fixtures/                  두 구현이 공유하는 골든 파일
    manifest.json              공유
    LICENSE, COPYING           공유
    THIRD_PARTY_NOTICES.md     플랫폼별 섹션 추가
    PROVENANCE.md              플랫폼별 섹션 추가
    README*.md                 플랫폼별 섹션 추가
    docs/              이 문서들
```

**장점**:

- `fixtures/`를 한 곳에서 관리한다. parity 검증의 전제다.
- `manifest.json`이 하나다. 버전 동기화가 자동이다.
- GPL 소스 아카이브가 하나다.
- 프로토콜 변경이 한 커밋에서 양쪽에 반영된다.

**단점**:

- CI가 복잡해진다(macOS job + Windows job + MSYS2 job).
- macOS 개발자가 Windows 코드를 보게 된다(그 반대도).

### 5.2 분리 저장소

`negaflow-scanner-sane-windows`를 따로 둔다.

**장점**: 독립적 릴리스 주기, 단순한 CI.

**단점**: `fixtures/`를 서브모듈이나 패키지로 공유해야 한다.
프로토콜 변경이 두 저장소에 걸친다. 버전 동기화가 수동이다.
GPL 소스 제공 범위가 애매해진다.

### 5.3 결정

```text
D-14  단일 저장소를 유지한다.
      windows/ 하위에 Windows 구현을 둔다.
      fixtures/를 루트에 두고 양쪽이 공유한다.
```

## 6. CI

```yaml
jobs:
  docs:
    runs-on: ubuntu-latest      # 파이썬만 필요하다
    steps:
      - python3 docs/check-docs.py

  macos:
    runs-on: macos-26
    steps:
      - verify-provenance.py
      - swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
      - conformance fixtures 검증
      - git diff --exit-code fixtures/

  windows-x64:
    runs-on: windows-latest
    steps:
      - vcpkg install
      - cmake --preset x64-release
      - cmake --build
      - ctest (unit + conformance)
      - 정적 분석 (/analyze)

  windows-arm64:
    runs-on: windows-11-arm     # 가용성 확인 필요
    steps: (동일)

  windows-asan:
    runs-on: windows-latest
    steps:
      - cmake --preset x64-asan
      - ctest
      - 퍼징 시드 코퍼스 실행

  sane-runtime:
    runs-on: windows-latest
    steps:
      - MSYS2 설정
      - sane-runtime/build.sh
      - 산출물 SHA-256 기록
      - 아티팩트 업로드
```

`sane-runtime` job은 매 커밋마다 돌 필요가 없다. 태그나 수동 실행에서만.

`docs` job은 몇 초면 끝난다. 문서가 서로 어긋난 채 머지되는 것을 막는다
→ [README](../README.md) §5.1

### 6.1 ARM64 러너

GitHub Actions의 Windows ARM64 러너 가용성을 확인해야 한다.
없으면:

- x64 러너에서 크로스 컴파일(MSVC는 ARM64 크로스 지원)
- 테스트는 실행할 수 없다 → 별도 하드웨어 필요

**크로스 컴파일 + 수동 실기 테스트**가 현실적 시작점이다.

## 7. 릴리스 스크립트

macOS의 스크립트 구조를 대응시킨다.

| macOS | Windows |
|---|---|
| `build-release.sh` | `build-release.ps1` |
| `package-release.sh` | `package-release.ps1` |
| `sign-plugin.sh` | `sign-plugin.ps1` (`signtool`) |
| `notarize-plugin.sh` | **없음** (Windows에 공증 개념 없음) |
| `create-source-archive.sh` | 공유 또는 `.ps1` 대응 |
| `verify-release.sh` | `verify-release.ps1` |
| `build-installer.sh` | `build-installer.ps1` |
| `verify-installer.sh` | `verify-installer.ps1` |
| `install-release.sh` | `install-release.ps1` |
| `verify-provenance.py` | **공유** (Python) |

### 7.1 `verify-provenance.py` 확장

현재 이 스크립트는:

- 추적된 파일과 릴리스 후보 파일을 인벤토리한다
- vendored 네이티브 코드와 SANE 링크를 거부한다
- 고정된 Homebrew·SANE notice와 설치 정책을 확인한다
- 릴리스 스크립트가 `scanimage`나 SANE 라이브러리를 복사하지 않는지 확인한다

**Windows에서는 마지막 규칙이 뒤집힌다.** 우리가 SANE 바이너리를
재배포하기 때문이다([building-sane](../01-sane-runtime/building-sane.md)).

스크립트를 수정한다.

```text
플랫폼별 정책:
  macOS:   SANE 바이너리 재배포 금지 (현행 유지)
  Windows: SANE 바이너리 재배포 허용, 단
           - sane-runtime/patches/의 모든 패치가 SOURCES.md에 기록됨
           - upstream tarball SHA-256이 고정됨
           - GPL 소스 아카이브에 sane-runtime/ 전체가 포함됨
           - THIRD_PARTY_NOTICES.md에 모든 런타임 의존이 기록됨

공통:
  - 어댑터 소스에 SANE 헤더/라이브러리 링크 없음
  - vendored SANE 소스 트리 없음 (다운로드만)
  - 어댑터가 libsane을 링크하지 않음
```

**마지막 항목이 가장 중요하다.** 어댑터가 여전히 `scanimage`를
프로세스로 부르고 libsane을 링크하지 않는다는 것이 이 프로젝트의
아키텍처 불변식이다.

## 8. 재현 가능한 빌드

macOS는 이미 `gzip -n`과 `COPYFILE_DISABLE`로 소스 아카이브를
결정론적으로 만든다. Windows도 같은 수준을 목표로 한다.

| 항목 | 대응 |
|---|---|
| 타임스탬프 | `/Brepro` 링커 플래그(PE 헤더 타임스탬프 제거) |
| 경로 | `/pathmap` 또는 상대 경로 빌드 |
| PDB | 서명 대상이 아니므로 별도 |
| ZIP | 타임스탬프 고정, 정렬된 항목 순서 |
| vcpkg | baseline 고정 |
| MSVC 버전 | CI에서 고정 |

완전한 비트 재현은 어렵지만, **같은 입력에 같은 해시**를 목표로 노력하고
달성 여부를 릴리스 노트에 기록한다.

## 9. `manifest.json` 공유

한 파일을 두 플랫폼이 쓴다. `executable` 필드가 다르다.

선택지:

**(a) 빌드 시 생성**

```text
manifest.template.json → 플랫폼별 manifest.json
```

**(b) 두 파일 유지**

```text
manifest.json          macOS
windows/manifest.json  Windows
```

**(a)를 권장한다.** `pluginVersion`이 한 곳에 있어야 동기화 실수가 없다.
릴리스 스크립트가 이미 `plutil -extract pluginVersion`으로 읽고 있으므로
Windows도 같은 값을 읽게 한다.

버전 소스는 `manifest.template.json` 또는 별도 `VERSION` 파일.

## 10. spike

### B-1 — `scanimage` TIFF writer의 압축

```text
scanimage -d <dev> --format=tiff > out.tif
tiffinfo out.tif | grep Compression
```

압축을 쓰지 않으면 libtiff의 압축 코덱을 뺄 수 있다.

### B-2 — MSVC `std::to_chars(double)` 지원

대상 툴체인 버전에서 컴파일되는지 확인한다.

### B-3 — ARM64 CI

GitHub Actions ARM64 Windows 러너 가용성.

### B-4 — 정적 링크 크기

`/MT` + libtiff 정적 링크 시 산출물 크기.
2~3 MB 예상. 허용 범위인지 확인.

## 11. 열린 질문

- `/GL`+`/LTCG`가 parity에 영향을 주는가
- ARM64 러너를 어디서 얻는가
- MSVC 재배포 정적 링크의 보안 업데이트 정책
- MSYS2 빌드를 컨테이너로 재현 가능하게 만들 수 있는가
