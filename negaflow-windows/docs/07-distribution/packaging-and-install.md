# 패키징과 설치

기준일: 2026-08-04
상태: 설계
관련 문서:

- [signing-and-trust](signing-and-trust.md)
- [gpl-compliance](gpl-compliance.md)
- [runtime-route-decision](../01-sane-runtime/runtime-route-decision.md)
- [environment-and-paths](../03-process-and-io/environment-and-paths.md)

## 1. 현재 macOS 배포물

| 산출물 | 내용 |
|---|---|
| `...-macos-universal.zip` | 플러그인 + 매니페스트 + 라이선스 + README 6종 + 소스 아카이브 + `install.sh` |
| `...-macos-universal.dSYM.zip` | 디버그 심볼 |
| `...-source.tar.gz` | GPL 소스 |
| `...-SHA256SUMS.txt` | 체크섬 |
| `...-macos-arm64-installer.pkg/.dmg` | 표준, arm64 |
| `...-macos-universal-installer.pkg/.dmg` | 표준, universal |
| `...-coolscan-macos26-arm64-installer.pkg/.dmg` | Coolscan, arm64 |
| `...-coolscan-macos26-universal-installer.pkg/.dmg` | Coolscan, universal |

**8개의 설치물**이 있다. standard/coolscan × arm64/universal × pkg/dmg.

## 2. Windows 배포물

```text
negaflow-scanner-sane-<ver>-win-x64.msi
negaflow-scanner-sane-<ver>-win-arm64.msi
negaflow-scanner-sane-<ver>-win-x64.zip           수동 설치용
negaflow-scanner-sane-<ver>-win-arm64.zip
negaflow-scanner-sane-<ver>-win-x64-pdb.zip
negaflow-scanner-sane-<ver>-win-arm64-pdb.zip
negaflow-scanner-sane-<ver>-source.tar.gz         플러그인 소스
sane-backends-1.4.0-negaflow-source.tar.gz        SANE 소스 + 패치
negaflow-scanner-sane-<ver>-win-SHA256SUMS.txt
```

**Coolscan 변종이 없다.** macOS에서 두 변종이 있는 이유는 stock Homebrew
`sane-backends`와 패치된 keg를 구분하기 때문이다. Windows에서는
**우리가 항상 패치된 런타임을 배포**하므로 변종이 하나다.

이것은 실질적 단순화다. macOS의 8개가 Windows에서 2개(아키텍처별)가 된다.

## 3. 설치 레이아웃

```text
%LOCALAPPDATA%\Negaflow\ScannerPlugins\sane\
    negaflow-scanner-sane.exe
    manifest.json
    sane\
        bin\
            scanimage.exe
            libsane-1.dll
            libsane-genesys-1.dll
            libsane-epson2-1.dll
            libsane-epsonds-1.dll
            libsane-coolscan2-1.dll
            libsane-coolscan3-1.dll
            libsane-pieusb-1.dll
            libsane-dll-1.dll
            libusb-1.0.dll
            <MinGW 런타임 DLL>
        etc\sane.d\
            dll.conf
            genesys.conf
            epson2.conf
            coolscan2.conf
            coolscan3.conf
            pieusb.conf
    LICENSES\
        LICENSE
        COPYING
        THIRD_PARTY_NOTICES.md
        PROVENANCE.md
    negaflow-scanner-sane-<ver>-source.tar.gz
    sane-backends-1.4.0-negaflow-source.tar.gz
```

백엔드 DLL 위치는 [environment-and-paths](../03-process-and-io/environment-and-paths.md) §4의
spike E-1 결과에 따라 `bin\`이 될 수도 `lib\sane\`이 될 수도 있다.

## 4. 사용자 범위 vs 머신 범위

macOS는 **사용자 범위 전용**이다(`~/Library/Application Support`).
설치 프로그램이 root로 시작해 콘솔 사용자로 강등한 뒤 설치한다.

negaflow 본체 windows_docs `10-scanner/plugin-architecture.md` §6(설치와 발견)이
두 root를 정의한다:

```text
%LOCALAPPDATA%\Negaflow\ScannerPlugins\<plugin-id>\      user scope (1차)
%ProgramFiles%\Negaflow Scanner Plugins\<plugin-id>\     machine scope (선택)
```

```text
D-19  1차 릴리스는 사용자 범위만 지원한다.
      macOS와 같은 모델을 유지한다.
```

이유:

- 관리자 권한이 필요 없다(드라이버 설치는 별도).
- 호스트의 승인 모델이 사용자별이다.
- 머신 범위는 여러 사용자가 같은 스캐너를 쓰는 시나리오인데, 스캐너를 한
  번에 한 프로세스만 열 수 있어 이득이 적다.

**관리자 권한은 어디에서도 필요 없다 (2026-08-06 갱신).** 드라이버를
바꾸지 않기 때문이다 —
[runtime-route-decision](../01-sane-runtime/runtime-route-decision.md)
§4.4b. 예전 초안의 "드라이버는 관리자" 분리는 폐기됐다.

## 5. MSI 구조

### 5.1 도구 선택

| 도구 | 라이선스 | 상태 |
|---|---|---|
| WiX Toolset v4/v5 | MS-RL | upstream이 수익 창출 사용에 Open Source Maintenance Fee 명시 |
| WiX v3 | MS-RL | 유지보수 모드 |
| Inno Setup | 자체(무료, 상업적 사용 허용) | EXE 설치 프로그램, MSI 아님 |
| NSIS | zlib-like | EXE 설치 프로그램 |
| MSIX | — | 패키지 identity, 제약 많음 |

negaflow 본체 windows_docs README §3.7이 WiX에 대해 같은 우려를 기록한다:

> WiX Toolset는 구현상 후보일 뿐 비용·사용 조건 승인이 끝난 무료 전제로
> 취급하지 않는다.

```text
D-20  결정: NSIS.  (2026-08-06)
```

MSI 를 만들지 않는다. §5.2 의 요건은 도구와 무관하고, MSI 여야만 되는 것이
하나도 없다 — 사용자 범위 설치라 시스템 설치 관리자에 등록할 이유가 없다.

NSIS 를 고른 이유는 셋이다.

- 라이선스가 zlib 계열이라 조건이 없다. WiX 의 Open Source Maintenance Fee
  같은 문제가 없다.
- **SANE 을 빌드하는 그 MSYS2 안에 이미 있다**
  (`mingw-w64-ucrt-x86_64-nsis`). 도구 하나를 위해 별도 Windows 설치를
  늘리지 않는다. Inno Setup 은 MSYS2 에 없다.
- 무인 설치(`/S`), 롤백, 설치 로그, 제거를 스크립트로 직접 쓴다. MSI 의
  트랜잭션을 커스텀 액션으로 흉내내는 것보다 읽기 쉽다.

생성된 exe 안에는 NSIS 스텁 코드가 들어간다. 그것을 배포하므로 고지를
`THIRD_PARTY_NOTICES.md` 에 적었다. GPL 바이너리는 그 안에 **자료로** 들어
있다가 그대로 풀린다 — 결합 저작물이 아니라 단순 취합이다.

구현은 [`Installer/windows/negaflow-scanner-sane.nsi`](../../Installer/windows/negaflow-scanner-sane.nsi),
사용법은 [`Installer/windows/README.md`](../../Installer/windows/README.md).

### 5.2 기술 요건

도구와 무관하게 만족해야 하는 것:

도구와 무관하게 만족해야 하는 것, 그리고 현재 상태(2026-08-06 실측):

```text
 1. 사용자 범위 설치 (관리자 권한 불필요)      됨   RequestExecutionLevel user
 2. 아키텍처별 별도 패키지 (x64 / ARM64)       일부 x64 만. ARM64 는 거절한다
 3. 대상 OS 최소 버전 확인                     됨   AtLeastWin10
 4. 기존 설치 감지 및 업그레이드                됨   덮어쓰기 실측
 5. 깨끗한 제거                                됨   폴더·레지스트리·상위 폴더
 6. Authenticode 서명                          안 함 D-1, 인증서 없음(영구)
 7. 롤백 (설치 실패 시 이전 상태 복원)          됨   파일 잠금으로 실측
 8. 무인 설치 지원                              됨   `/S`, 창을 띄우지 않는다
 9. 설치 로그                                   됨   설치 폴더의 install.log
10. 드라이버 바인딩 단계를 설치와 분리           해당 없음 — 드라이버를 안 바꾼다
```

10번은 사라졌다. usbscan.sys 경로를 택해 드라이버를 바꾸지 않으므로
바인딩 단계 자체가 없다(runtime-route-decision §4.4b).

7번이 중요하다. macOS의 `install-plugin-user.sh`가 이미
staging → 기존 이동 → 새것 이동 → 실패 시 복원 패턴을 구현한다. NSIS 판도
같은 순서다. 기존을 옆으로 옮기는 rename 이 실패하는 것이 곧 "실행 중인가"
검사여서, 프로세스 목록을 뒤지지 않는다.

### 5.3 업그레이드

```text
같은 UpgradeCode, 새 ProductCode
MajorUpgrade로 이전 버전 제거 후 설치
```

**설치 후 호스트가 재승인을 요구한다.** 실행 파일 해시가 바뀌기 때문이다.
설치 완료 화면에 이를 안내한다.

```text
설치가 완료되었습니다.

negaflow를 다시 시작하고 "스캐너 불러오기"에서 플러그인을 다시
승인하십시오. 업데이트 후에는 승인이 초기화됩니다.
```

## 6. 설치 흐름

```text
1. 사전 확인
     OS 버전
     아키텍처 일치
     기존 설치
2. 라이선스 표시 (GPL-2.0-or-later)
3. 파일 복사
4. 완료 안내
```

### 6.1 macOS 설치 프로그램과의 차이

| macOS | Windows |
|---|---|
| Homebrew 설치 여부 확인 | 해당 없음 |
| Xcode CLT 확인 | 해당 없음 |
| root → 콘솔 사용자 강등 | 사용자 범위 설치이므로 불필요 |
| `brew install sane-backends` | 런타임을 함께 복사 |
| 소스 빌드 (Coolscan) | 불필요, 미리 빌드됨 |
| — | 없음 — 드라이버를 바꾸지 않는다 |

**Windows 설치가 macOS보다 단순하다.** 인터넷 연결이 필요 없고, 빌드가
없고, 관리자 권한이 필요 없다. 드라이버 바인딩이라는 복잡성도 없다 —
초안에는 있었지만 usbscan.sys 경로가 그것을 지웠다.

## 7. 드라이버 경고

[runtime-route-decision](../01-sane-runtime/runtime-route-decision.md) §7과
[usb-transport](../01-sane-runtime/usb-transport.md) §4.2에서 정한 문구를
설치 프로그램에 넣는다.

**설치 전에 표시한다.** 사용자가 취소할 수 있어야 한다.

```text
┌──────────────────────────────────────────────────────┐
│ 스캐너 드라이버 변경 안내                              │
│                                                      │
│ 이 플러그인이 스캐너를 사용하려면 스캐너의 USB        │
│ 드라이버를 WinUSB로 바꿔야 합니다.                    │
│                                                      │
│ 바꾸면 다음을 사용할 수 없게 됩니다:                  │
│   • 제조사 스캔 소프트웨어 (Epson Scan 2 등)          │
│   • Windows 팩스 및 스캔                              │
│   • 제조사 TWAIN 드라이버를 쓰는 프로그램             │
│                                                      │
│ 되돌리기:                                            │
│   장치 관리자에서 제조사 드라이버로 되돌립니다.       │
│                                                      │
│ 드라이버는 지금 바꾸지 않아도 됩니다. 나중에          │
│ 설치 디렉터리의 도구로 바꿀 수 있습니다.              │
│                                                      │
│    [ 자세히 ]        [ 취소 ]        [ 계속 ]         │
└──────────────────────────────────────────────────────┘
```

### 7.1 드라이버 바인딩 단계 분리

```text
D-21  드라이버 바인딩을 설치와 분리한다.
      설치는 파일만 복사한다.
      드라이버 바인딩은 별도 실행 파일 또는 설치 후 선택 단계다.
```

이유:

- 설치 시점에 스캐너가 연결돼 있지 않을 수 있다.
- 사용자가 여러 스캐너 중 하나만 바꾸고 싶을 수 있다.
- 되돌리기 도구도 필요하다.
- MSI 커스텀 액션에서 드라이버를 설치하면 롤백이 복잡하다.

```text
%LOCALAPPDATA%\Negaflow\ScannerPlugins\sane\
    bind-scanner-driver.exe     (관리자 권한 요구, 매니페스트에 명시)
```

또는 Zadig 안내로 시작한다([runtime-route-decision](../01-sane-runtime/runtime-route-decision.md) §8).

## 8. 제거

```text
파일 삭제
설치 디렉터리 제거
```

**드라이버 바인딩을 자동으로 되돌리지 않는다.** 위험하고, 사용자가
다른 이유로 WinUSB를 원할 수 있다.

제거 완료 화면에 안내:

```text
플러그인이 제거되었습니다.

스캐너 드라이버는 변경된 상태로 남아 있습니다.
제조사 소프트웨어를 다시 쓰려면 장치 관리자에서
드라이버를 되돌리십시오.
```

제거 도구를 함께 제공하는 것이 친절하지만, 제거 후에는 그 도구도
사라진다. **제거 전에 되돌릴 것을 권하는 것이 낫다.**

## 9. ZIP 배포 (수동 설치)

**하지 않는다.** 계획 단계에서는 macOS 의 ZIP + `install.sh` 에 맞춰 ZIP +
`install.ps1` 을 두려 했고 실제로 한 번 만들었지만, 단일 exe 가 그 일을 전부
한다 — 무인 설치도, 대상 폴더 지정도, 롤백도, 제거도. 설치 경로가 둘이면
둘 다 계속 동작하게 유지해야 하고, 언젠가 한쪽만 고치게 된다.

무인·스크립트 설치는 exe 로 한다.

```powershell
.\negaflow-scanner-sane-<ver>-x64-setup.exe /S /D=C:\경로
```

`/D=` 는 **맨 뒤에, 따옴표 없이** 와야 한다. NSIS 의 제약이다.

## 10. 릴리스 검증

`verify-release.ps1`이 확인할 것 (macOS `verify-release.sh` 대응):

```text
아티팩트 존재:  setup.exe, PDB ZIP, 소스 아카이브 2종, SHA256SUMS
체크섬 일치
setup.exe /S /D=<임시 경로> 로 설치한 뒤:
    negaflow-scanner-sane.exe가 실행 가능
    manifest.json 필드 4종
    LICENSES\ 4개 파일
    소스 아카이브 존재, 병치 사본과 SHA-256 일치
Authenticode 서명 검증 (signtool verify /pa) — 서명하면
PE machine type이 기대 아키텍처와 일치
PDB GUID가 exe의 것과 일치
import table에 sane 없음
소스 아카이브에 Package.swift, windows/CMakeLists.txt,
    sane-runtime/PKGBUILD 존재
NEGAFLOW_PLUGINS_DIR로 실제 설치 후 해시 일치 확인
```

**PDB GUID 확인**이 macOS의 dSYM UUID 확인에 대응한다.

```powershell
# exe의 디버그 디렉터리에서 PDB GUID + Age 읽기
# PDB 파일의 GUID + Age와 비교
```

## 11. 업데이트

macOS는 업데이트 메커니즘이 없다. 사용자가 새 설치물을 받아 실행한다.

Windows도 같게 시작한다.

```text
D-22  1차 릴리스에 자동 업데이트를 넣지 않는다.
      negaflow 본체가 플러그인 업데이트 확인을 제공한다면
      그 경로를 쓴다.
```

자동 업데이트를 넣으면:

- 서명된 업데이트 메타데이터
- 버전 단조성
- 롤백 정책
- 승인 승계 정책 (호스트와 협의 필요)

가 전부 필요하다. 초기 릴리스의 범위를 넘는다.

## 12. 파일 시스템 권한

```text
%LOCALAPPDATA%\Negaflow\ScannerPlugins\sane\
    소유자: 설치한 사용자
    권한: 사용자 전체 제어, 다른 사용자 접근 없음
    상속: 명시적으로 설정
```

macOS의 `install-plugin-user.sh`가 `chmod go-w`를 하는 것에 대응한다.

**중요**: 호스트가 이 디렉터리의 ACL을 검사한다
(negaflow 본체 windows_docs `10-scanner/plugin-security-and-lifecycle.md`).
쓰기 권한이 넓으면 플러그인을 거부한다.

MSI가 기본으로 `%LOCALAPPDATA%`의 상속 ACL을 쓰면 적절하지만,
명시적으로 설정하는 편이 안전하다.

## 13. 진단 정보 수집

설치 프로그램이 로그를 남긴다.

```text
%TEMP%\negaflow-scanner-sane-install-<timestamp>.log
```

MSI는 `/l*v` 로그를 지원한다. 기본으로 켤지, 실패 시에만 남길지 결정한다.

**개인정보**: 로그에 사용자 이름과 경로가 들어간다. 사용자가
공유하기 전에 확인할 수 있게 위치를 안내한다.

## 14. 체크리스트

2026-08-06 기준. 실측 결과는 `Installer/windows/README.md` §검증한 것.

- [x] Coolscan 변종 없음(단일 런타임)
- [x] 사용자 범위 설치
- [x] 소스 아카이브가 설치물에 포함됨 (`source/`)
- [x] LICENSES\ 4개 파일
- [x] 업그레이드 시 이전 버전이 사라짐 (폴더 통째 교체)
- [x] 롤백 동작 — 파일을 잠근 채 설치해 확인
- [x] 무인 설치 동작 — `/S`, 창을 띄우지 않는다
- [x] 설치 로그
- [x] 설치 후 실제로 도는지 확인 (`detect` 종료 코드)
- [ ] 아키텍처별 패키지 2종 — x64 만. ARM64 는 거절한다
- [ ] Authenticode 서명 — D-1, 인증서 없음(영구 제외)
- [ ] verify-release.ps1
- [ ] ACL이 좁게 설정됨
- [x] ~~드라이버 경고~~ / ~~드라이버 바인딩 분리~~ / ~~제거 시 드라이버 안내~~
      — 드라이버를 바꾸지 않으므로 해당 없음
- [x] ~~ZIP + install.ps1 경로~~ / ~~`NEGAFLOW_PLUGINS_DIR` 지원~~
      — §9 참조. 단일 exe 의 `/S /D=` 로 대체

## 15. 열린 질문

- 설치 프로그램 도구 (WiX vs Inno Setup vs 기타)
- 드라이버 바인딩 도구 (Zadig 안내 vs libwdi 내장)
- MSI 크기(약 40 MB)가 수용 가능한가
- negaflow 본체가 플러그인 설치를 안내하는 방식
- 제거 시 SANE 설정 파일을 남길 것인가
