# Windows 패키지와 설치

기준일: 2026-08-25

현재 배포 형식은 x64 NSIS 설치 파일입니다.

```text
negaflow-scanner-sane-<version>-x64-setup.exe
%LOCALAPPDATA%\Negaflow\Plugins\sane\
```

설치 파일은 adapter, bundled SANE runtime, manifest, license·notice, 대응 소스 archive를 함께 넣습니다. 드라이버는 설치하거나 교체하지 않습니다.

개발 PC에서 설치 파일을 만들고 확인하는 절차는 [windows-build-and-install.md](windows-build-and-install.md)를 따릅니다.

현재 제외 범위:

- ARM64 설치 파일
- Authenticode 서명
- 실제 장치 스캔을 포함한 자동 installer smoke

현재 1.4.0-5 setup은 빌드됐지만 최신 installer smoke·실제 plugin 경로 재설치와
OpticFilm 최종 Gray 연속 실장은 아직 끝나지 않았습니다. 완료 판정은
[windows-build-and-install.md](windows-build-and-install.md)와
[실기 검증 표](../09-hardware/validation-matrix.md)를 따릅니다.

설치 파일을 릴리스에 올리기 전에는 새 설치·업데이트·제거와 `detect`를 실제 Windows 사용자 계정에서 확인합니다.
