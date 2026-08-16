# Windows 빌드와 설치 파일

기준일: 2026-08-16
상태: x64 로컬 CI에서 Release build, CTest, setup 설치 payload, 설치본 `detect`, 제거 통과. 실제 장치 scan과 GitHub 실행 결과는 별도입니다.

## 1. 사용자 설치

이 설치 파일은 Negaflow 본체가 아닙니다. GPL-2.0-or-later인 SANE 어댑터와
SANE 런타임을 별도 프로세스 플러그인으로 설치합니다. Apache-2.0 Negaflow 설치
파일과 결합하거나 그 payload에 넣지 않습니다.

```text
negaflow-scanner-sane-<version>-x64-setup.exe
%LOCALAPPDATA%\Negaflow\Plugins\sane\
```

설치본 `manifest.json`은 Windows 실행 파일명
`negaflow-scanner-sane.exe`를 명시합니다. Negaflow Windows의
`ScannerPluginDiscovery.DefaultPluginDirectory`가 이 디렉터리를 읽으므로,
설치 뒤 본체를 다시 열면 승인된 플러그인에서 스캐너 탐색을 시작합니다.

처음 설치한 플러그인은 본체에서 한 번 신뢰 승인해야 합니다. 그 뒤에는 파일
해시가 승인 당시와 같은 경우에만 실행됩니다. 설치 프로그램은 관리자 권한을
요구하지 않으며 SANE runtime, GPL license notices, 대응 소스 archive를 함께
넣습니다.

일부 실제 장치에는 제조사 또는 usbscan 드라이버 바인딩이 별도로 필요합니다.
서명된 INF가 없는 장치의 드라이버 설치에는 관리자 권한이 필요할 수 있습니다.
이 설치 파일은 드라이버를 바꾸지 않습니다.

```powershell
.\negaflow-scanner-sane-<version>-x64-setup.exe /S
```

`/D=<절대경로>`는 NSIS 규칙에 따라 마지막 인자로만 둡니다. 제거는 Windows
"설치된 앱" 또는 설치 폴더의 `uninstall.exe /S`입니다.

## 2. 개발 환경

다음은 최종 사용자에게 필요하지 않고 설치 파일을 만드는 개발 PC에만 필요합니다.

```text
Visual Studio 2026 C++ x64 toolchain
CMake 3.25 이상
vcpkg (x64-windows-static)
MSYS2 UCRT64 + 빌드한 SANE runtime (scanimage.exe)
NSIS 3
```

Visual Studio 설치에 포함된 vcpkg는 자동으로 찾습니다. 다른 위치라면
`-VcpkgRoot`를 명시합니다. NSIS는 다음처럼 설치할 수 있습니다.

```powershell
winget install --id NSIS.NSIS --exact
```

## 3. x64 설치 파일 생성

macOS `ci-gate.sh`와 같은 Windows 로컬 단일 진입점은 다음 명령입니다. Release build,
CTest, setup 생성, 임시 설치 payload 확인, 설치본 `detect`, 제거를 순서대로 실행하고
`out\logs\local-ci-*.log`에 전체 로그를 남깁니다. QA에는 이 게이트를 통과한 산출물만 사용합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\local-ci.ps1
```

`build-installer.ps1`은 adapter Release build, CTest, MSYS2 runtime payload 조립,
NSIS 컴파일, SHA-256 생성을 한 번에 수행합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-installer.ps1
```

산출물은 `out\release\x64\`에 생성됩니다. 같은 버전을 다시 만들 때는
기존 release artifact를 의도적으로 덮도록 `-Overwrite`를 명시해야 합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-installer.ps1 `
  -InstallerPath .\out\release\x64\negaflow-scanner-sane-<version>-x64-setup.exe
```

smoke는 임시 경로에 무인 설치한 뒤 Windows manifest, adapter, bundled
`scanimage.exe`, GPL source/license payload을 확인하고 `detect`, 무인 제거를
실행합니다. 실제 장치 detect/scan의 성공은 하드웨어·드라이버 검증이 필요하므로
이 smoke의 범위 밖입니다.

## 4. CI와 GitHub Release

`.github/workflows/windows.yml`은 Debug/Release adapter build와 CTest를 계속
실행합니다. `installer-contract` job은 NSIS 문법과 Windows payload manifest
형식을 확인합니다. 실제 SANE runtime을 포함한 release installer는 UCRT64 runtime
recipe까지 재현된 Windows release PC에서 위 스크립트로 만들고, setup.exe와 같은
이름의 `.sha256`을 GitHub Release에 첨부합니다.

릴리스 전에는 다음을 분리해서 기록합니다.

- adapter CTest와 installer smoke
- 실제 장치/driver binding에서 detect·capabilities·scan
- SHA-256 파일과 GPL source payload 존재
- x64 외 아키텍처는 별도 runtime 검증 전까지 배포하지 않음

## 5. 2026-08-16 로컬 검증

- adapter Release CTest 5/5를 통과했습니다.
- 실제 UCRT64 SANE runtime을 포함한 x64 NSIS 설치 파일을 생성했습니다.
- installer smoke가 Windows manifest, adapter, bundled `scanimage.exe`, GPL source/license payload,
  `detect`, 무인 제거를 확인했습니다. 실제 장치 scan은 포함하지 않습니다.

## 6. 2026-08-17 로컬 CI 검증

- `scripts/local-ci.ps1`에서 Release CTest 5/5, setup 생성, 임시 설치 payload,
  설치본 `detect` 종료 코드 0, 제거를 통과했습니다.
- 로그: `out\logs\local-ci-20260817-000901.log`
- 설치 파일 SHA-256: `85b1928ec01a8729af4de27d09805ed2bf336deaf41680b55f9ad39f2066fe09`
- 실제 8100/V700 scan, IR, 취소, 재연결, 반복 스캔은 이 로컬 CI의 범위가 아닙니다.
