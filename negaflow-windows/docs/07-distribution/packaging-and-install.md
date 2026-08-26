# Windows 패키지와 설치

기준일: 2026-08-25

현재 배포 형식은 x64 NSIS 설치 파일입니다.

```text
negaflow-scanner-sane-<version>-x64-setup.exe
%LOCALAPPDATA%\Negaflow\Plugins\sane\
```

설치 파일은 adapter, bundled SANE runtime, manifest, license·notice, 대응 소스 archive를 함께 넣습니다.

설치 마지막에 **스캐너 통로를 여는 단계**가 있습니다. 플러그인은 Windows 자신의
`usbscan.sys` 로 장치를 열고, 그 드라이버가 스캐너에 묶여 있어야 합니다
(runtime-route-decision §4.4b). 그런데 §4.4b 의 실측은 "Plustek 드라이버 그대로" 인
기계에서 잰 것이고, OpticFilm 8100 이 열렸던 것도 SilverFast 가 깔아 둔 INF 덕이었습니다 —
**벤더 소프트웨어가 없는 깨끗한 PC 에는 묶어 주는 것이 없습니다.** 그래서 설치본이
`usbscan-bind\` 에 INF 와 그 설치 스크립트를 함께 싣고, 설치 마지막에 그 통로를 엽니다.

- 설치 자체는 사용자 영역에만 쓰고 관리자를 요구하지 않습니다. **그 한 단계만** 권한을 올립니다.
- 거절해도 설치는 그대로 남습니다. 벤더 드라이버로 이미 열리는 기계는 이 단계 없이도 동작합니다.
- 통로를 연 뒤 `detect` 를 다시 돌려 장치 목록을 `install.log` 에 남깁니다.
- 무인(`/S`) 설치에서는 관리자 확인을 띄울 수 없으므로 건너뛰고 그 사실을 기록합니다.
- 제거할 때 통로와 자체 서명 인증서를 함께 되돌릴지 묻습니다.

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
