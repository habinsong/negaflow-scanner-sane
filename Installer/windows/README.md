# Windows 설치 프로그램

사용자는 **하나만 실행한다.** 플러그인과 SANE 런타임이 함께 설치되고, 따로
받아야 하는 것은 없다. 관리자 권한도 필요 없다 — 드라이버를 바꾸지 않기
때문이다.

```powershell
.\install.ps1              # 설치 또는 갱신
.\install.ps1 -Uninstall   # 제거
.\install.ps1 -Quiet       # 무인
```

설치 위치는 `%LOCALAPPDATA%\Negaflow\ScannerPlugins\sane` 다.

## 배포물 만들기

`payload/` 는 저장소에 두지 않는다. 빌드 산출물이고 15 MB 다.

```bash
# MSYS2 UCRT64 셸에서. sane-runtime/ 의 레시피로 SANE 을 먼저 빌드해 둔다.
bash Installer/windows/make-payload.sh <출력>/payload <플러그인 exe 경로>
cp Installer/windows/install.ps1 <출력>/
```

그러면 `<출력>` 을 통째로 압축해 배포한다.

## 담기는 것

```text
negaflow-scanner-sane.exe   어댑터
manifest.json               호스트가 읽는 것
sane/bin/                   scanimage.exe, 백엔드, 의존 DLL **전부 한 곳에**
sane/etc/sane.d/            dll.conf 와 백엔드 설정
LICENSES/                   COPYING, LICENSE, 고지, provenance
source/                     GPL 대응 소스
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

## 어댑터가 런타임을 찾는 법

설치 레이아웃이 `<플러그인 디렉터리>\sane\bin\scanimage.exe` 라서
`app::findScanimage()` 의 2번 후보가 그대로 걸린다. 환경 변수를 설정할 필요가
없다. `NEGAFLOW_SCANIMAGE_PATH` 로 덮어쓸 수는 있다.

## 검증한 것 (2026-08-06, OpticFilm 8100 실기)

```text
설치            14.5 MB, 48개 파일
detect          Plustek OpticFilm 8100, connectionType usb
실제 스캔        17초, 856x590, TIFF 3,030,480 바이트
갱신            기존 위에 다시 설치 — 성공
제거            디렉터리가 사라진다
재설치          다시 성공
```

MSYS2 를 `PATH` 에서 완전히 뺀 상태에서 확인했다. 설치본만으로 돈다.

## 아직 없는 것

```text
서명            Authenticode 인증서가 없다 (D-1). SmartScreen 경고가 뜬다
단일 .exe       지금은 폴더를 압축해 배포한다. NSIS 나 Inno Setup 으로
                감싸는 것은 D-20 이 정해진 뒤다
ARM64           x64 전용이다. 설치 프로그램이 확인하고 거절한다
```

기술 요건표는
[packaging-and-install](../../windows_docs/07-distribution/packaging-and-install.md)
§5.2 에 있다. 1·4·5·7·8 은 만족한다. 2(아키텍처별 패키지)는 x64 만,
6(서명)과 9(설치 로그)는 아직이다.
