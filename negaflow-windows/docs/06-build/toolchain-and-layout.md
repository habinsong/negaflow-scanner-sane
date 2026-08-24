# Windows 빌드 환경과 구조

기준일: 2026-08-25

## 빌드 환경

| 항목 | 현재 사용 |
| --- | --- |
| 어댑터 | C++20, MSVC, CMake |
| 의존성 | vcpkg manifest, `x64-windows-static` |
| TIFF·JSON | libtiff, RapidJSON |
| SANE runtime | MSYS2 UCRT64에서 001~011 patch로 만든 SANE 1.4.0-5 `scanimage.exe` |
| 설치 파일 | NSIS x64 |
| CI | GitHub Actions `windows-latest` x64 |

어댑터와 SANE runtime은 별도 프로세스입니다. 둘은 같은 C++ ABI를 공유하지 않습니다.

## 현재 배포 범위

현재 설치 파일은 x64만 만듭니다. ARM64용 adapter·SANE runtime·설치 파일은 설계 대상이지만 빌드와 실기 확인이 끝나기 전에는 배포 대상으로 적지 않습니다.

## 디렉터리

```text
src/       옵션 해석, 프로세스, TIFF, JSON, 앱 조율
tests/     단위·golden·가상 scanimage 통합 검사
scripts/   설치 파일 생성과 installer smoke
out/       로컬 CMake·release 산출물
```

## 구성 명령

```powershell
cmake -S . -B out\build -A x64 `
  -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_ROOT\scripts\buildsystems\vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static
```

이후 `cmake --build out\build --config Release`와 `ctest --test-dir out\build -C Release`를 실행합니다.
