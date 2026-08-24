# Windows 빌드와 설치 파일

기준일: 2026-08-25
상태: x64 Release build와 CTest 5/5를 통과했습니다. V700·OpticFilm 8100 의 Color/Gray 와
V700 IR 실장 결과가 있고 Gray 는 patch 011 로 닫혔습니다. 커밋된 소스에서의 재빌드와
GitHub 실행 결과는 별도입니다.

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

## 7. 2026-08-25 Gray runtime 체크포인트

- SANE 1.4.0에 001~011 패치를 순서대로 적용해 clean 작업 디렉터리에서 빌드했습니다.
  절차는 `scripts\build-sane-runtime.ps1`이 소유하며, PKGBUILD 의 `source=()`·`prepare()`와
  `patches/`를 대조하고 CRLF 를 거부하고 설치 뒤 낡은 `cygsane-*` 그림자를 지웁니다.
- **GL846** host-side Gray 종료 길이를 수정한 UCRT64 패키지 SHA-256:
  `31d00ae1701ea4040ab058a81068aa1a5be43995e924583f751e60f5b08f6703`.
  (이전 기록의 `e1f11ec7…`는 종료 길이 수정을 `gl843.cpp`에 넣은 판으로, OpticFilm 8100은
  `AsicType::GL845`라 그 파일을 타지 않아 실제로는 아무 효과가 없었습니다.)
- 해당 runtime으로 adapter Release build와 CTest 5/5를 통과해 만든 setup SHA-256:
  `ba79f19165cc099105617a83d5b0cc3dd8693330511d8ced0bcf95db23677851`.
- 이 setup을 `%LOCALAPPDATA%\Negaflow\Plugins\sane`에 무인 설치한 뒤 확인했습니다.
  - 번들 `cygsane-genesys-1.dll` SHA-256이 빌드한 `libsane-genesys-1.dll`과 동일 (`37b6df9a…`).
  - OpticFilm 8100 Gray 16-bit **연속 2회 성공**: 16,658/16,781ms, 1,010,302B,
    856×590 Samples/Pixel 1, 예고/실제 바이트 일치, 경고 없음.
  - OpticFilm 8100 Color 16-bit 회귀 성공 (856×590, Samples/Pixel 3).
  - Epson GT-X900 Gray/Color 16-bit 모두 성공.
  - Negaflow host `--scanner-live-end-to-end` 네 조합 모두 published 1/1.
- **dirty tree에서 만든 산출물입니다.** 최종 릴리스는 010·011 패치를 포함해 커밋한 뒤
  같은 소스에서 다시 빌드하고, 그 해시로 이 절을 갱신해야 GPL 대응 소스와 일치합니다.
