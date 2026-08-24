# 현재 상태와 다음 확인

기준일: 2026-08-25

## 현재 상태

- Windows x64 어댑터는 `scanimage.exe`를 자식 프로세스로 실행합니다.
- Release CTest에는 플러그인 통합 검사, Epson·OpticFilm 인자 검사, 단위 검사, golden 검사가 있습니다.
- OpticFilm 8100과 Epson V700에서 프리뷰·본스캔을 여러 DPI로 성공했습니다.
- Epson V700에서 IR 스캔도 성공했습니다.
- Epson V700은 600 DPI 10×10mm에서 Color/Gray × 8/16-bit 네 조합을 모두
  완료했고, Color 16-bit RGB/IR 쌍은 Negaflow host의 저장·catalog 게시·재열기까지 통과했습니다.
- OpticFilm 8100의 원본 SANE Gray 16-bit는 장치 버퍼가 끝까지 비어 멎는 것을
  직접 재현했습니다. patch 011(`HOST_SIDE_GRAY` + color-filter `None` 노출 +
  **GL846** 종료 길이)로 **닫혔습니다**. 설치본에서 Gray 16-bit 연속 2회가
  16,658/16,781ms, 1,010,302B, Samples/Pixel 1, 예고=실제로 통과했고 Color 16-bit
  회귀도 통과했습니다. 종료 길이 수정을 처음에 `gl843.cpp`에 넣었던 것은 오진입니다 —
  8100은 `AsicType::GL845`라 `CommandSetGl846`을 씁니다. 자세한 내용은
  `../../negaflow-mac/sane-runtime/SOURCES.md` §011.
- Negaflow host 종단(`--scanner-live-end-to-end`)도 설치 플러그인 경로에서 두 장치 ×
  gray/color 네 조합 모두 `status ok`, published 1/1로 통과했습니다.
- 현재 Windows SANE recipe는 1.4.0에 11개 패치를 적용하며, clean source
  `scripts/build-sane-runtime.ps1` 빌드와 Release CTest 5/5를 통과했습니다.
- 설치 파일은 x64 전용입니다. 현재 manifest 버전은 `1.0.4`입니다.

## 바로 실행할 명령

```powershell
cmake -S . -B out\build -A x64 `
  -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_ROOT\scripts\buildsystems\vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static
cmake --build out\build --config Release --parallel
ctest --test-dir out\build -C Release --output-on-failure
```

설치 파일은 [windows-build-and-install](../07-distribution/windows-build-and-install.md)의 `build-installer.ps1`과 `verify-installer.ps1`로 확인합니다.

## 다음 확인

1. **패치 010·011을 커밋합니다.** 지금 git 미추적이라 GitHub에는 Gray 수정도
   bundled-backend-dir 수정도 없습니다. `.gitattributes` 경로 수정, PKGBUILD 해시 복원,
   `scripts/build-sane-runtime.ps1`을 같이 올리고, **커밋된 소스에서 다시 빌드한** setup의
   SHA-256으로 배포 문서를 갱신합니다. dirty tree 로컬 setup은 GPL 대응 소스 증거가 아닙니다.
2. macOS에서 `negaflow-mac/docs/opticfilm-gray.md` §5의 합격 기준을 실행합니다.
   formula에 genesys hunk 3개를 넣고 version을 `1.4.0-negaflow.4`로 올렸지만 맥에서
   빌드·실행한 적이 없습니다. 맥 Gray가 실패하면 `tables_model` hunk를 되돌리고
   RGB 획득→흑백 네거/포지티브 현상 경로로 전환합니다.
3. 두 장치에서 취소 뒤 다음 스캔, USB 분리·재연결, 다른 프로그램 점유 오류를 확인합니다.
4. ARM64 Windows 장치에서 빌드와 실스캔을 따로 확인합니다.
5. OpticFilm 계열 중 `HOST_SIDE_GRAY`를 켜지 않은 행(7200·7200i·7200-v2·7300·7400-v1·
   7500i·7600i-v1·8200i·7600i-v2)은 그 장치를 손에 넣기 전에는 켜지 않습니다.
   근거는 `../09-hardware/validation-matrix.md`에 있습니다.
