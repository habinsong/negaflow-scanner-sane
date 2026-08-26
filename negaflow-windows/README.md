# negaflow-scanner-sane Windows 어댑터

기준일: 2026-08-25

SANE `scanimage.exe`를 별도 프로세스로 실행하는 Negaflow Windows 스캐너 플러그인입니다. GPL-2.0-or-later 플러그인과 Negaflow 본체는 같은 설치 파일에 섞지 않습니다.

## 실기 확인

- Plustek OpticFilm 8100: 프리뷰와 본스캔을 여러 DPI에서 성공
- Epson Perfection V700: 프리뷰와 본스캔을 여러 DPI에서 성공
- Epson Perfection V700: IR 스캔 성공
- Epson Perfection V700: Color/Gray × 8/16-bit와 Negaflow host RGB/IR 게시·재열기 성공
- Plustek OpticFilm 8100: 원본 Gray 정지 재현 후 patch 011(`HOST_SIDE_GRAY` + 색 필터
  `None` + GL846 출력 길이)로 해결. 설치본 Gray 16-bit 연속 2회와 Color 회귀 성공
- 두 장치 × Color/Gray 네 조합 모두 Negaflow host 저장→catalog 게시→재열기 성공

위 결과는 장치·드라이버·Windows 조합에서 확인한 범위입니다. 취소, USB 재연결,
장시간 반복, 다른 장치와 ARM64 실행, macOS formula 의 같은 Gray 수정은 별도 확인이 필요합니다.

## 코드와 자동 검사

- C++20 / MSVC
- `scanimage` 옵션 해석, capability 확인, 정확한 옵션 검증, 자식 프로세스 실행, TIFF 결과 검사, JSON 프로토콜
- Release 구성의 CTest: `plugin_smoke`, `epson_smoke`, `opticfilm_matrix`, `sane_logic_tests`, `parity_golden`

## 빌드와 테스트

`negaflow-windows`에서 실행합니다.

```powershell
cmake -S . -B out\build -A x64 `
  -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_ROOT\scripts\buildsystems\vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static
cmake --build out\build --config Release --parallel
ctest --test-dir out\build -C Release --output-on-failure
```

`vcpkg.json`의 TIFF와 RapidJSON이 모두 잡혀야 플러그인 실행 파일이 만들어집니다.

## 설치 파일

현재 플러그인 버전은 `1.1.0`입니다. x64 설치 파일 생성과 무인 설치 검사는 [Windows 빌드와 설치 파일](docs/07-distribution/windows-build-and-install.md)을 따릅니다.

## 문서

- [현재 상태와 다음 확인](docs/00-overview/handoff.md)
- [실기 검증 범위](docs/09-hardware/validation-matrix.md)
