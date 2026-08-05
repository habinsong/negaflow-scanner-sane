# 환경과 경로

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 이식 정본 — 전면 재설계 대상
코드 근거: `SANEBackend+Environment.swift`, `SaneConfigTuner.swift`,
`Tests/SANEPluginCoreTests/SANEBackendEnvironmentTests.swift`(801행)

관련 문서:

- [building-sane](../01-sane-runtime/building-sane.md)
- [child-process](child-process.md)
- [packaging-and-install](../07-distribution/packaging-and-install.md)

## 1. 현재 macOS가 하는 일

### 1.1 `scanimage` 탐색

```text
1. NEGAFLOW_SCANIMAGE_PATH               (환경 변수)
2. /opt/homebrew/opt/sane-backends-negaflow/bin/scanimage
3. /usr/local/opt/sane-backends-negaflow/bin/scanimage
4. /opt/homebrew/bin/scanimage
5. /usr/local/bin/scanimage
6. /usr/bin/scanimage
7. "scanimage"                            (PATH에 위임)
```

2~6은 `isExecutableFile`로 확인한다. **패치된 keg가 stock보다 우선한다.**

### 1.2 환경 구성

```text
LC_ALL = "C"
LANG   = "C"
PATH   = <scanimage 디렉터리>:/opt/homebrew/bin:/opt/homebrew/sbin:
         /usr/local/bin:/usr/local/sbin:<기존 PATH 또는 /usr/bin:/bin>
SANE_CONFIG_DIR = <findSaneConfigDir 결과>
LD_LIBRARY_PATH = <선택한 keg>/lib/sane:<기존>   (그 디렉터리가 존재할 때만)
SANE_DEFAULT_DEVICE = <캐시된 선택자>            (유효할 때만)
```

### 1.3 설정 디렉터리 탐색

```text
1. <scanimage의 상위상위>/etc/sane.d          ← 같은 keg 우선
2. SANE_CONFIG_DIR 환경 변수 (존재할 때만)
3. /opt/homebrew/etc/sane.d
4. /usr/local/etc/sane.d
5. /etc/sane.d
```

**1번이 2번보다 우선한다.** 코드 주석: patched scanimage에 stock
`SANE_CONFIG_DIR`가 섞이면 Coolscan backend 패치가 우회될 수 있다.

## 2. Windows에서 무엇이 무의미해지는가

| 항목 | Windows |
|---|---|
| Homebrew keg 경로 | 존재하지 않음 |
| `/usr/bin`, `/etc` | 존재하지 않음 |
| `LD_LIBRARY_PATH` | **동작하지 않음.** Windows DLL 검색과 무관 |
| `PATH` 앞에 붙이기 | 동작하지만 권장하지 않음 |
| `isExecutableFile` | 실행 권한 비트가 없음 |

`LD_LIBRARY_PATH`를 그대로 옮기면 **아무 일도 일어나지 않는다.** 조용히
무시되고, 개발자는 왜 백엔드가 로드되지 않는지 알 수 없다.

## 3. Windows 탐색 순서

```text
1. NEGAFLOW_SCANIMAGE_PATH                       (환경 변수, 절대 경로)
2. <플러그인 디렉터리>\sane\bin\scanimage.exe     ← 우리가 배포한 런타임
3. 설정 파일에 기록된 경로                        (사용자 지정, 있다면)
4. PATH 검색                                     (마지막 수단)
```

**하드코딩된 시스템 경로가 없다.** macOS의 Homebrew 경로에 해당하는 것이
Windows에는 없기 때문이다. MSYS2 기본 설치 경로(`C:\msys64\ucrt64\bin`)를
후보에 넣을 수도 있지만 권장하지 않는다.

- 사용자마다 설치 위치가 다르다
- 우리가 검증하지 않은 버전을 조용히 쓰게 된다
- `-A` 출력 형식이 다를 수 있다

MSYS2를 쓰려는 사용자는 1번이나 3번으로 명시적으로 지정한다.

### 3.1 실행 파일 검증

`isExecutableFile` 대응이 없으므로 다음을 확인한다.

```text
파일이 존재하고 regular file이며 reparse point가 아님
확장자가 .exe
PE 헤더가 유효하고 machine type이 현재 프로세스와 호환
  (x64 프로세스 → IMAGE_FILE_MACHINE_AMD64
   ARM64 프로세스 → IMAGE_FILE_MACHINE_ARM64 또는 AMD64(에뮬레이션))
```

machine type 확인이 실질적으로 중요하다. x64 `scanimage.exe`를 ARM64
프로세스에서 띄우면 에뮬레이션으로 동작하긴 하지만, libusb/WinUSB 계층에서
문제가 생길 수 있다. 최소한 진단에 기록한다.

**이 검증은 1번(`NEGAFLOW_SCANIMAGE_PATH`)에도 적용한다.** 여기서 macOS와
갈린다 — macOS는 환경 변수 값을 **검사 없이 그대로 쓴다**(§1.1의 "2~6만
`isExecutableFile`"). 오타가 있으면 exec 실패라는 모호한 오류만 나온다.

```text
의도적 개선이며 I-20 후보다.
Windows: 1번도 검증하고, 실패하면 "무엇이 잘못됐는지"를 말한다.
macOS 에도 같은 검증을 추가하는 것을 권장하되 별도 작업으로 분리한다.
```

검증을 통과했다고 신뢰하는 것은 아니다. 번들 밖 경로의 `scanimage.exe`는
서명을 검증하지 않되 그 사실을 진단과 결과 warnings에 남긴다(D-24).

## 4. DLL 검색 — 가장 중요한 차이

`scanimage.exe`가 `libsane-1.dll`을 찾고, `libsane-1.dll`이 백엔드 DLL을
찾아야 한다.

### 4.1 Windows DLL 검색 순서 (기본)

```text
1. 이미 로드된 같은 이름의 DLL
2. API set / known DLLs
3. 실행 파일이 있는 디렉터리
4. 시스템 디렉터리
5. Windows 디렉터리
6. 현재 작업 디렉터리     ← SetDefaultDllDirectories로 제거 가능
7. PATH의 각 디렉터리
```

우리 레이아웃:

```text
<플러그인>\sane\bin\scanimage.exe
<플러그인>\sane\bin\libsane-1.dll        ← 3번으로 찾힌다. 좋다
<플러그인>\sane\bin\libusb-1.0.dll       ← 3번. 좋다
<플러그인>\sane\lib\sane\libsane-genesys-1.dll   ← 3번이 아니다
```

백엔드 DLL은 `dll` 백엔드가 **런타임에 명시적으로 로드**한다
(`LoadLibrary` 계열). 그 경로는 SANE 빌드 시점의 `--libdir`에 의해 정해진다.

### 4.2 세 가지 해결책

**(a) 백엔드 DLL을 `bin`에 함께 둔다**

```text
<플러그인>\sane\bin\
    scanimage.exe
    libsane-1.dll
    libsane-genesys-1.dll
    libsane-epson2-1.dll
    ...
```

`dll` 백엔드가 상대 경로나 이름만으로 로드한다면 3번 규칙으로 찾힌다.
가장 단순하다. **`dll` 백엔드가 실제로 어떻게 로드하는지 확인이 필요하다**
(절대 경로를 구성한다면 동작하지 않는다) → spike E-1.

**(b) 빌드 시 `--libdir`을 우리 레이아웃에 맞춘다**

재빌드할 것이므로 가능하다. 다만 설치 경로가 고정돼야 한다
(`%LOCALAPPDATA%\Negaflow\ScannerPlugins\sane\sane\lib\sane`).
사용자가 옮기면 깨진다.

**(c) `SetDllDirectory` / `AddDllDirectory`**

우리가 `scanimage.exe`를 띄우므로 자식의 DLL 검색 경로를 직접 바꿀 수 없다.
자식 프로세스에 적용하려면 `PATH`에 넣는 방법뿐이다.

**권장: (a)를 우선 시도하고, 안 되면 (b).** `PATH` 오염은 피한다.

### 4.3 `PATH`를 쓸 경우

자식에게만 적용되는 환경 블록을 만들어 전달한다. 부모의 `PATH`를 바꾸지 않는다.

```text
자식 PATH = <플러그인>\sane\bin;<기존 PATH>
```

**앞에 붙인다.** 뒤에 붙이면 시스템에 같은 이름의 DLL이 있을 때 그것이 먼저
로드된다(예: 다른 프로그램이 설치한 `libusb-1.0.dll`).

DLL 하이재킹 위험도 있다. `<플러그인>\sane\bin`이 사용자만 쓸 수 있는
ACL이어야 한다([signing-and-trust](../07-distribution/signing-and-trust.md)).

## 5. 환경 변수

### 5.1 유지하는 것

```text
LC_ALL = "C"
LANG   = "C"
```

MinGW `scanimage`가 이를 존중하는지는 **미확인**(spike S-6).
존중하지 않으면 `LANGUAGE` 추가, gettext 카탈로그 제거, 또는
[exact-option-contract](../02-frontend-contract/exact-option-contract.md) §6의
대체 감지 경로가 필요하다.

```text
SANE_CONFIG_DIR = <플러그인>\sane\etc\sane.d
```

**반드시 설정한다.** MSYS2 빌드의 컴파일 시점 경로(`/ucrt64/etc/sane.d`)는
우리 배포에 존재하지 않는다.

경로 구분자에 주의: SANE는 이 값을 `:`로 분리하는 검색 경로로 다룰 수 있다
(Unix 관례). `C:\...`의 `C:`가 잘릴 위험이 있다.

**확인 필요** → spike E-2. 잘린다면 대안:

- 8.3 단축 경로 사용(`GetShortPathNameW`) — 드라이브 문자 문제는 남는다
- MinGW 빌드가 `;`를 구분자로 쓰도록 패치
- 설정을 실행 파일과 같은 디렉터리에 두고 상대 경로 해석에 의존

이것은 **Windows 이식에서 실제로 발목을 잡을 수 있는 구체적 함정**이다.
빌드 spike 단계에서 반드시 확인한다.

```text
SANE_DEFAULT_DEVICE = <캐시된 선택자>   (유효할 때만)
```

의미가 같다면 유지한다.

### 5.2 제거하는 것

```text
LD_LIBRARY_PATH   → 동작하지 않음. 설정하지 않는다.
```

### 5.3 추가를 검토하는 것

```text
SANE_DEBUG_DLL, SANE_DEBUG_<BACKEND>
```

진단 모드에서만 설정한다. 기본 경로에서는 설정하지 않는다
(stderr가 폭증해 진행률 파싱과 stderr 예산에 영향을 준다).

→ [diagnostics-and-troubleshooting](../08-operations/diagnostics-and-troubleshooting.md)

### 5.4 환경 블록 구성 원칙

```text
부모 환경을 복사한다
위 변수들을 덮어쓴다
자식에게 전달한다
```

**부모 환경을 통째로 비우지 않는다.** `SystemRoot`, `TEMP`, `USERPROFILE`,
`ProgramData`가 없으면 CRT나 libusb가 실패할 수 있다.

민감 정보 필터링: 부모 환경에 토큰·자격 증명이 있을 수 있다.
자식이 그것을 필요로 하지 않으므로 **허용 목록 방식**이 더 안전하다.
그러나 어떤 변수가 필요한지 완전히 알기 어려우므로, 현실적으로는
전달하되 진단 로그에는 환경 덤프를 남기지 않는다.

## 6. 플러그인 설치 경로

```text
%LOCALAPPDATA%\Negaflow\ScannerPlugins\sane\
    negaflow-scanner-sane.exe
    manifest.json
    sane\
        bin\      scanimage.exe, libsane-1.dll, 백엔드 DLL, libusb-1.0.dll
        etc\sane.d\   dll.conf, genesys.conf, epson2.conf, ...
    LICENSES\
        LICENSE, COPYING, THIRD_PARTY_NOTICES.md, PROVENANCE.md
    negaflow-scanner-sane-<version>-source.tar.gz
```

negaflow 본체 windows_docs의 `10-scanner/plugin-architecture.md` §6이
`%LOCALAPPDATA%\Negaflow\ScannerPlugins\<plugin-id>\`를 1차 user-scope
root로 정의한다. 그것을 따른다.

플러그인 ID는 `sane`이다(현재 `manifest.json`). 그 ID의 Windows 규칙
적합성:

- 1~64 바이트, 첫 바이트가 letter/digit, 나머지가 letter/digit/`-`/`.`/`_` — 통과
- DOS 예약 이름(`CON`, `PRN`, `AUX`, `NUL`, `COM1`~`COM9`, `LPT1`~`LPT9`) — `sane`은 해당 없음
- 후행 점/공백 없음 — 통과

**ID를 바꾸지 않는다.** 호스트의 라우팅 ID(`plugin:sane:...`)가 바뀌면
승인·캐시·카탈로그가 전부 영향받는다.

## 7. 임시 파일

현재 macOS:

```text
makeTempURL(prefix:suffix:) = FileManager.temporaryDirectory
                              + "<prefix>_<UUID><suffix>"
```

쓰이는 곳:

- `outputURL`이 없을 때의 기본 스캔 출력 (프로토콜 v2에서는 항상 있으므로
  실질적으로 도달하지 않음)
- 다중 노출의 중간 샘플 TIFF (`negaflow_multipass_sample1` 등)

### 7.1 Windows에서의 문제

중간 샘플 TIFF는 **매우 크다.** 7200 dpi 35 mm 컬러 16-bit 한 장이
약 10,200 × 6,800 × 6 바이트 ≈ 400 MB이고, 노출 계획이 3~12 패스면
1.2~4.8 GB다.

`%TEMP%`가:

- 시스템 드라이브에 있고 공간이 부족할 수 있다
- 백업/동기화 대상일 수 있다
- 안티바이러스가 실시간 검사한다

**권장: 호스트가 준 `outputPath`와 같은 디렉터리에 중간 파일을 만든다.**

```text
outputPath = C:\...\.negaflow-scan-<uuid>\frame.tiff
중간 파일  = C:\...\.negaflow-scan-<uuid>\frame.sample1.tiff
```

이유:

- 호스트가 이미 충분한 공간이 있는 볼륨을 골랐다
- 호스트가 staging 디렉터리를 정리하므로 우리가 실패해도 남지 않는다
- 같은 볼륨이므로 최종 결과를 만들 때 복사가 아니라 rename이 가능하다

**단 호스트 계약을 확인해야 한다.** negaflow 본체 문서는 staging 디렉터리
안에 RGB와 IR만 있을 것을 가정할 수 있다. IR 파일 규칙(`frame.ir.tiff`)이
이미 있으므로 추가 파일이 허용될 가능성이 높지만, 명시적으로 정한다.

→ [wire-contract](../05-protocol/wire-contract.md) §10, open question

`NEGAFLOW_KEEP_MULTIPASS=1`일 때 파일을 남기는 동작은 유지한다.
그 경우 경로를 warnings에 싣는 현재 동작도 유지한다.

### 7.2 파일 이름

```text
negaflow_multipass_sample1_<UUID>.tiff
```

UUID가 들어가 충돌이 없다. Windows에서도 유지한다. UUID 문자열 형식은
중괄호 없는 소문자 하이픈 형태로 통일한다.

## 8. `SaneConfigTuner`의 운명

macOS에서 이 클래스는 공용 `dll.conf`를 다룬다. Windows에서는 `dll.conf`가
우리 전용이므로 존재 이유가 사라진다.

```text
D-05  Windows 빌드는 dll.conf를 수정하지 않는다.
      repair-sane-config / tune-sane / restore-sane는 no-op로 남긴다.
```

no-op 구현:

```text
case "repair-sane-config", "tune-sane":
    print("repair: notNeeded (this platform uses a private SANE configuration)")
    print("active backends: " + <dll.conf에서 읽은 활성 백엔드 목록>)

case "restore-sane":
    print("no backup to restore (this platform uses a private SANE configuration)")
```

`activeBackends` 읽기는 유지한다. 진단에 유용하다.

**`detect` 시작 시의 자동 복구 호출은 제거한다.** `hasLegacyFiltering`이
항상 false이므로 무해하지만, 존재하지 않는 파일을 매번 여는 것은 불필요하다.

## 9. Spike 명세

### E-1 — `dll` 백엔드의 DLL 로드 방식

```text
1. MSYS2 sane 패키지 설치
2. Process Monitor로 scanimage.exe -L 실행 추적
3. libsane-*.dll을 어느 경로에서 찾는지 기록
4. 백엔드 DLL을 bin\으로 옮기고 lib\sane\을 지운 뒤 재실행
5. 동작하는가?
```

동작하면 §4.2(a)를 채택한다.

#### 결과 — **닫힘** (2026-08-06, 실측)

Process Monitor 없이 답이 나왔다. MSYS2 SANE 을 그대로 설치하면
**백엔드가 하나도 로드되지 않는다.** 이유는 두 가지이고 둘 다 소스에서 확인했다.

1. `HAVE_DLOPEN` 이 정의되지 않아 `dll.c` 가 DLL 을 열 방법 자체를 갖지 못했다.
   `mingw-w64-ucrt-x86_64-dlfcn` 을 설치해야 한다.
2. `dll.c` 는 Windows 에서 접두사 `cygsane-` 와 접미사 `-%u.dll` 로 찾는다
   (`runtime-route-decision` §4.4 의 코드 인용). 패키지는 `libsane-*.dll` 로
   깔리므로 이름이 어긋난다.

그래서 §4.2(a)(`bin\` 한 곳에 모으기)는 채택하지 않는다. **`lib\sane\` 배치를
유지하고 백엔드를 `cygsane-<backend>-1.dll` 이름으로도 두면 동작한다** —
OpticFilm 8100 실기에서 `scanimage -L` 부터 전체 스캔까지 확인했다.

배포 시에는 두 이름 중 하나만 두면 되지만, 어느 쪽이 정본인지 헷갈리지 않게
`cygsane-` 쪽을 정본으로 삼고 `libsane-` 는 두지 않는 편이 낫다.

### E-2 — `SANE_CONFIG_DIR`의 Windows 경로 처리

```text
1. SANE_CONFIG_DIR="C:\test\sane.d"로 설정
2. scanimage -L 실행, Process Monitor로 어느 경로를 여는지 확인
3. "C:"가 잘려 "\test\sane.d"만 보이는가?
4. 잘린다면:
   - 8.3 경로로 시도
   - 상대 경로로 시도
   - 소스에서 경로 분리 로직 확인 (sanei/sanei_config.c)
```

**이 spike가 실패하면 재빌드 시 경로 처리 패치가 추가로 필요하다.**

### E-3 — 로케일

[availability](../01-sane-runtime/availability.md) S-6과 동일.

```text
한국어 Windows에서:
1. LC_ALL=C 설정 후 scanimage --help
2. 옵션 설명이 영어인가?
3. 존재하지 않는 장치로 -A → 오류 메시지가 영어인가?
4. step에 안 맞는 해상도 요청 → "rounded value of"가 나오는가?
```

### E-4 — 임시 파일 위치와 처리량

```text
1. %TEMP%에 400 MB TIFF 쓰기 시간 측정
2. staging 디렉터리(같은 볼륨)에 쓰기 시간 측정
3. 안티바이러스 실시간 검사 켜짐/꺼짐 비교
4. WSL2 경로면 /mnt/c 경유 시간도 측정
```

## 10. 이식 체크리스트

- [ ] `scanimage` 탐색 순서 4단계
- [ ] PE machine type 확인
- [ ] `LD_LIBRARY_PATH`를 설정하지 않는다
- [x] `SANE_CONFIG_DIR`이 설정되고 실제로 동작한다 (E-2 — 닫힘, 2026-08-06)
- [x] 백엔드 DLL이 로드된다 (E-1 — 닫힘, `cygsane-` 이름이 필요하다)
- [ ] 자식 환경 블록만 수정하고 부모를 건드리지 않는다
- [ ] `PATH`를 쓴다면 앞에 붙인다
- [ ] 중간 파일이 staging 디렉터리에 만들어진다
- [ ] `NEGAFLOW_KEEP_MULTIPASS` 동작 유지
- [ ] `SaneConfigTuner` 서브커맨드가 no-op로 남았다
- [ ] `detect`의 자동 복구 호출이 제거됐다
- [ ] `NEGAFLOW_SCANIMAGE_PATH`가 동작한다
- [ ] 환경 덤프가 로그에 남지 않는다
