# Windows 설치 프로그램

사용자는 **실행 파일 하나만 받아 실행한다.** 플러그인과 SANE 런타임이 함께
설치되고, 따로 받아야 하는 것은 없다. 관리자 권한도 필요 없다 — 드라이버를
바꾸지 않기 때문이다.

```text
negaflow-scanner-sane-<버전>-x64-setup.exe        실행하면 마법사가 뜬다
negaflow-scanner-sane-<버전>-x64-setup.exe /S     무인
```

설치 위치는 `%LOCALAPPDATA%\Negaflow\ScannerPlugins\sane` 이고, 마법사에서
바꿀 수 있다(무인일 때는 `/D=<경로>` 를 **맨 뒤에 따옴표 없이**).

제거는 Windows 의 "설치된 앱"에서 하거나, 설치 폴더의 `uninstall.exe` 를
실행한다(`/S` 로 무인).

## 만들기

```bash
# MSYS2 UCRT64 셸에서. sane-runtime/ 의 레시피로 SANE 을 먼저 빌드해 둔다.
bash Installer/windows/make-installer.sh [<플러그인 exe 경로>]
```

`make-payload.sh` 가 배포물을 모으고 `makensis` 가 그것을 실행 파일 하나로
감싼다. 버전은 `manifest.json` 의 `pluginVersion` 을 읽는다 — 두 곳에 적으면
언젠가 갈라진다. 15 MB 배포물이 LZMA solid 로 **5.1 MB** 가 된다.

`payload/` 와 `*-setup.exe` 는 저장소에 두지 않는다. 빌드 산출물이다.

`makensis` 가 없으면:

```bash
pacman -S mingw-w64-ucrt-x86_64-nsis
```

## 담기는 것

```text
negaflow-scanner-sane.exe   어댑터
manifest.json               호스트가 읽는 것
sane/bin/                   scanimage.exe, 백엔드, 의존 DLL **전부 한 곳에**
sane/etc/sane.d/            dll.conf 와 백엔드 설정
LICENSES/                   COPYING, LICENSE, 고지, provenance
source/                     GPL 대응 소스
install.log                 설치가 무엇을 했는지
uninstall.exe               제거 프로그램
```

담을 DLL 목록을 **손으로 적지 않는다.** `ldd` 가 계산한다. 손으로 적으면
반드시 빠지고, 빠진 것은 사용자 기계에서만 드러난다. 지금 19개다.

### 왜 한 디렉터리인가

백엔드를 `lib/sane/` 에 따로 두면 **로드되지 않는다.** dlfcn 의 `dlopen` 이
`LOAD_WITH_ALTERED_SEARCH_PATH` 로 여는 탓에 의존 DLL 검색이 실행 파일
디렉터리가 아니라 그 백엔드 DLL 의 디렉터리에서 시작한다. genesys 는 libtiff
압축 스택까지 16개를 끌고 오므로 반드시 걸린다.

실측: 나눠 두면 `dlopen() failed ... 지정된 모듈을 찾을 수 없습니다`,
합쳐 두면 장치가 나온다.

이름은 `cygsane-<backend>-1.dll` 이어야 한다. `dll.c` 가 Windows 에서 쓰는
접두사·접미사다.

### `test` 백엔드는 담지 않는다

`detect` 에 가짜 장치가 나타나면 I-17 과 충돌한다. 개발 빌드에서만 쓴다.

## 설치가 실패하면 되돌린다

반쯤 설치된 상태로 두지 않는다. staging 에 새것을 완성하고 → 기존을 옆으로
치우고 → 새것을 제자리로 옮긴다. 어디서 실패하든 이전 상태로 돌아간다.

**기존을 치우는 rename 이 곧 "실행 중인가" 검사다.** 파일이 잠겨 있으면
rename 이 실패하므로 프로세스를 따로 뒤질 필요가 없다.

두 가지를 실측으로 배웠다.

- `SetOutPath` 는 프로세스의 현재 디렉터리도 옮긴다. 그대로 두면 staging 을
  제자리로 옮기는 rename 이 "현재 디렉터리는 이름을 못 바꾼다"로 조용히
  실패한다. 첫 시도에서 설치가 0개 파일로 끝났다.
- 무인 모드에서 대화상자를 띄우면 배포 스크립트가 통째로 멎는다. `/S` 일
  때는 종료 코드와 `install.log` 로만 말한다.

## 어댑터가 런타임을 찾는 법

설치 레이아웃이 `<플러그인 디렉터리>\sane\bin\scanimage.exe` 라서
`app::findScanimage()` 의 2번 후보가 그대로 걸린다. 환경 변수를 설정할 필요가
없다. `NEGAFLOW_SCANIMAGE_PATH` 로 덮어쓸 수는 있다.

## 검증한 것 (2026-08-06, OpticFilm 8100 실기)

`PATH` 에서 msys64 를 완전히 뺀 상태에서 확인했다. 설치본만으로 돈다.

```text
설치 프로그램     5.1 MB, 단일 exe, 무인 설치 2초, 종료 코드 0
설치 결과         50개 파일 14.7 MB, install.log, "설치된 앱" 항목 등록
detect            Plustek OpticFilm 8100, connectionType usb
실제 스캔          20초, 848x566, 16-bit, TIFF 2,880,048 바이트
갱신              기존 위에 다시 설치 — 성공, 이전 버전의 잔여 파일이 사라진다
파일이 잠겼을 때   종료 코드 2, 기존 설치 그대로, staging/backup 찌꺼기 0개
제거              폴더·레지스트리 항목 모두 사라지고 상위 폴더도 정리된다
재설치            다시 성공
```

## 알려진 제약

```text
서명            Authenticode 인증서가 없다 (D-1, 영구 제외).
                SmartScreen 경고가 뜬다. 사용자는 "추가 정보 → 실행"을
                눌러야 한다
ARM64           x64 전용이다. 설치 프로그램이 확인하고 거절한다
_?= 제거        UninstallString 을 `_?=` 와 함께 부르면 uninstall.exe 가
                제자리에서 돌아 폴더 rename 이 막힌다. 우리는 그렇게 부르지
                않고, Windows 의 "설치된 앱"도 그렇게 부르지 않는다
```

기술 요건표는
[packaging-and-install](../../../negaflow-windows/docs/07-distribution/packaging-and-install.md)
§5.2 에 있다. 서명(6)과 아키텍처별 패키지(2, x64 만)를 뺀 나머지를 만족한다.
