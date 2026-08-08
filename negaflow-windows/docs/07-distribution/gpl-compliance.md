# GPL 준수

기준일: 2026-08-04
상태: 설계 — **법률 자문이 아니다**
목적: Windows 배포에서 GPL 의무가 어떻게 달라지는지 정확히 기록한다

관련 문서:

- [building-sane](../01-sane-runtime/building-sane.md)
- [packaging-and-install](packaging-and-install.md)
- [availability](../01-sane-runtime/availability.md)

이 문서는 프로젝트의 감사 가능한 기록이며 법적 의견이 아니다.
새 코드·자산·의존이 도입될 때 권리 검토를 대체하지 않는다.

## 1. 현재 상태 (macOS)

`PROVENANCE.md`와 `THIRD_PARTY_NOTICES.md`가 기록하는 사실:

| 항목 | 상태 |
|---|---|
| 이 저장소의 Swift/셸/테스트 코드 | GPL-2.0-or-later |
| SANE 헤더·라이브러리 링크 | **없음** |
| vendored SANE 트리 | **없음** |
| 배포물의 SANE 바이너리 | **없음** |
| 표준 설치 프로그램 | Homebrew에게 stock `sane-backends` 설치 요청 |
| Coolscan 설치 프로그램 | SANE 1.4.0 소스를 사용자 Mac에서 빌드 |
| Homebrew 컴포넌트 | 검증 후 원본 그대로 포함 (BSD 2-Clause) |
| 소스 아카이브 | 릴리스 ZIP 옆·안, PKG 페이로드, DMG 최상위 |
| 자동 검사 | `scripts/verify-provenance.py` |

**핵심 설계**: SANE 바이너리를 배포하지 않으므로 SANE에 대한 소스 제공
의무가 발생하지 않는다. 플러그인 자체는 GPL-2.0-or-later이고 소스를
함께 배포하므로 그 의무는 충족된다.

## 2. Windows에서 무엇이 달라지는가

```text
Homebrew가 없다
   ↓
사용자가 SANE를 직접 설치할 수단이 사실상 없다
   ↓
우리가 SANE 바이너리를 배포한다
   ↓
SANE에 대한 완전한 대응 소스 제공 의무가 발생한다
```

이것이 이 문서가 존재하는 이유다. **의무가 늘어난다.**

### 2.1 회피할 수 있는가

세 가지 회피 경로가 있고 전부 대가가 있다.

| 경로 | 의무 | 대가 |
|---|---|---|
| 사용자가 MSYS2를 설치 | 없음 | 사용자 부담 큼, 패치 미적용, 버전 불일치 |
| 설치 프로그램이 MSYS2 pacman을 호출 | 애매 | MSYS2 설치가 선행돼야 함, 자동화 어려움 |
| WSL2 경로 | 없음 | 사용자 부담이 가장 큼 |

macOS의 Homebrew 방식(설치 프로그램이 패키지 관리자에게 설치를 요청)을
Windows에서 재현하려면 winget이나 Chocolatey가 SANE를 가지고 있어야
하는데 **없다.**

**결론: 재배포를 피하기 어렵다. 의무를 받아들이고 정확히 이행한다.**

## 3. GPL-2.0-or-later의 소스 제공 요건

sane-backends는 GPL-2.0-or-later다. 바이너리를 배포하면 GPLv2 §3에 따라
다음 중 하나를 해야 한다.

```text
(a) 바이너리와 함께 완전한 대응 소스를 배포한다
(b) 3년간 유효한 서면 제안(written offer)을 동봉한다
(c) (비상업적 배포에 한해) 받은 제안을 전달한다
```

**(a)를 선택한다.** 이유:

- (b)는 3년간 소스 제공 인프라를 유지해야 하고, 그 의무를 추적하기 어렵다.
- (a)는 릴리스 시점에 한 번 하면 끝난다.
- 이미 macOS에서 플러그인 소스 아카이브를 배포하는 구조가 있다.

### 3.1 "완전한 대응 소스"의 범위

GPLv2 §3의 정의:

> the complete source code means all the source code for all modules it
> contains, plus any associated interface definition files, plus the
> scripts used to control compilation and installation of the executable.

우리가 배포해야 하는 것:

```text
1. sane-backends 1.4.0 전체 소스
2. 우리가 적용한 모든 패치
     001-fix-build-on-mingw.patch     (MSYS2에서 가져옴, 442행)
     002-coolscan2-word-list.patch    (upstream 9bea1ee)
     003-coolscan3-word-list.patch    (upstream 9bea1ee)
     004-epson2-scan-height.patch     (선택)
     005-binary-stdout.patch          (spike S-2 결과에 따라)
3. 빌드 스크립트와 설정
     PKGBUILD 또는 build.sh
     configure 플래그 전체
     툴체인 버전 명세
4. 플러그인 자체 소스 (이미 하고 있음)
5. GPL-2.0-or-later 라이선스 전문 (COPYING)
```

**3번이 중요하다.** "빌드에 사용한 스크립트"가 명시적으로 포함된다.
`--disable-locking`이나 `BACKENDS=` 목록 같은 configure 인자도
빌드 설정의 일부다.

### 3.2 의존 라이브러리

SANE 런타임이 링크하는 것:

| 라이브러리 | 라이선스 | 의무 |
|---|---|---|
| libusb-1.0 | LGPL-2.1-or-later | notice + 재링크 가능성 |
| libtiff | BSD-like | notice |
| libjpeg-turbo | BSD-like / IJG | notice |
| libpng | libpng | notice |
| libxml2 | MIT | notice |
| curl | curl (MIT-like) | notice |
| poppler | **GPL-2.0-or-later** | 소스 제공 |
| net-snmp | BSD-like | notice |
| libieee1284 | GPL-2.0-or-later | 소스 제공 |
| MinGW-w64 런타임 | 다양(대부분 관대) | notice |

**poppler와 libieee1284가 GPL이다.** 이들도 재배포하면 소스를
제공해야 한다.

```text
D-15  재빌드 시 poppler와 libieee1284 의존을 제거할 수 있는지 확인하고,
      가능하면 제거한다.
      제거할 수 없으면 그 소스도 함께 배포한다.
```

poppler는 PDF 출력용이고 이 플러그인은 PDF를 만들지 않는다.
libieee1284는 병렬 포트 스캐너용이고 우리는 그 백엔드를 포함하지 않는다.
**둘 다 제거 가능성이 높다.** 재빌드에서 확인한다.

libusb는 LGPL이므로 **동적 링크를 유지하고** 사용자가 자기 빌드로
교체할 수 있게 한다. 정적 링크하면 재링크 가능성 제공이 필요해진다.
MSYS2 빌드가 이미 동적 링크다.

## 4. 배포물 구성

### 4.1 설치 프로그램 페이로드

```text
negaflow-scanner-sane-<version>-win-x64.msi
    %LOCALAPPDATA%\Negaflow\ScannerPlugins\sane\
        negaflow-scanner-sane.exe
        manifest.json
        sane\bin\...
        sane\etc\sane.d\...
        LICENSES\
            LICENSE                       플러그인 GPL notice
            COPYING                       GPL v2 전문
            THIRD_PARTY_NOTICES.md
            PROVENANCE.md
        negaflow-scanner-sane-<version>-source.tar.gz    플러그인 소스
        sane-backends-1.4.0-negaflow-source.tar.gz       SANE 소스 + 패치 + 빌드
```

**두 개의 소스 아카이브를 설치물 안에 넣는다.**

크기: 플러그인 소스는 수백 KB, SANE 소스는 약 30 MB(압축).
MSI가 커지지만 준수의 가장 확실한 방법이다.

### 4.2 대안 — 병치 배포

MSI 크기가 문제라면 릴리스 페이지에 소스 아카이브를 **바이너리와
같은 위치에** 올린다.

GPLv2 §3의 각주:

> If distribution of executable or object code is made by offering access
> to copy from a designated place, then offering equivalent access to copy
> the source code from the same place counts as distribution of the source
> code

즉 같은 다운로드 페이지에서 소스를 받을 수 있으면 (a)를 만족한다.

**그러나 설치 프로그램이 사용자 손에 들어간 뒤 재배포될 수 있다.**
그 경우 재배포자가 소스를 함께 전달해야 하는데, 설치물 안에 없으면
어렵다.

```text
D-16  소스 아카이브를 설치물 안에 포함한다.
      릴리스 페이지에도 병치한다.
      두 사본의 SHA-256이 같은지 릴리스 검증에서 확인한다.
      (macOS의 verify-release.sh가 이미 하는 일)
```

### 4.3 설치 후 위치

소스 아카이브를 설치 디렉터리에 남길 것인가, 설치 중에만 쓰고 지울 것인가.

macOS는 남긴다(`verify-release.sh`가 설치 후 존재를 확인한다).
**Windows도 남긴다.** 30 MB는 감수한다.

사용자가 지울 수 있게 하려면 설치 옵션으로 분리할 수 있지만,
기본값은 설치다.

## 5. 어댑터가 libsane을 링크하지 않는다

이것이 이 프로젝트의 **아키텍처 불변식**이며 라이선스 결론과 별개로
지켜진다.

```text
negaflow-scanner-sane.exe
   ├─ libtiff (BSD)
   ├─ RapidJSON (MIT)
   └─ Win32
      ※ libsane, SANE 헤더, SANE 코드 없음

scanimage.exe (별도 프로세스)
   └─ libsane-1.dll → 백엔드 DLL
```

### 5.1 왜 유지하는가

라이선스 때문만이 아니다.

1. **프로세스 격리**: SANE 백엔드가 크래시하거나 매달려도 어댑터가 산다.
   coolscan 힙 오버플로우 같은 버그가 우리 프로세스를 죽이지 않는다.
2. **교체 가능성**: 사용자가 자기 SANE 빌드를 쓸 수 있다.
3. **버전 독립**: SANE를 업데이트해도 어댑터를 다시 빌드하지 않는다.
4. **비트니스 독립**: x64 어댑터가 x64 `scanimage`를 부른다. 필요하면
   다른 조합도 가능하다.

### 5.2 libsane 직접 링크의 유혹

[availability](../01-sane-runtime/availability.md) §7.3이 지적하듯
`sane_get_option_descriptor()`를 직접 호출하는 것이 `-A` 텍스트 파싱보다
**훨씬 안정적**이다. `-A`는 도움말 렌더러이고 버전 간 보장이 없다.

그럼에도 링크하지 않는 이유:

```text
D-17  어댑터는 libsane을 링크하지 않는다.
      -A 파싱의 취약성은 버전 고정과 conformance 픽스처로 관리한다.

      이 결정을 뒤집으려면:
      - 프로세스 격리 상실을 감수할 근거
      - GPL 경계 재검토
      - macOS 구현도 함께 바꿀지 결정
      - 크래시 격리 대체 수단
      가 모두 필요하다.
```

**중간안이 있다**: `scanimage`를 우리가 재빌드하므로, JSON 옵션 덤프
기능을 추가하는 패치를 만들 수 있다.

```text
scanimage --all-options-json
```

이것은:

- 프로세스 경계를 유지한다
- `-A` 파싱 취약성을 없앤다
- upstream에 제출할 가치가 있다(다른 프런트엔드에도 유용)
- GPL 패치이므로 소스 배포에 포함된다

**매력적이지만 macOS는 stock SANE를 쓰므로 양쪽 동작이 갈린다.**
macOS도 패치된 SANE를 쓰게 하면(Coolscan 경로처럼) 통일되지만
표준 경로 사용자는 여전히 stock이다.

```text
D-18  --all-options-json 패치를 v2에서는 도입하지 않는다.
      upstream 제출을 검토하고, upstream에 들어가면 그때
      두 플랫폼에서 함께 채택한다.
```

## 6. Apache-2.0 negaflow와의 경계

`PROVENANCE.md`가 기록하는 현재 사실:

- negaflow는 Apache-2.0이고 이 플러그인을 링크하지 않는다.
- 플러그인을 negaflow 애플리케이션 번들에 포함하지 않는다.
- 두 프로그램은 별도 프로세스에서 버전 있는 JSON/NDJSON으로 통신한다.

**Windows에서도 동일하다.** 추가로:

```text
금지:
  - SANE 바이너리를 negaflow 본체 MSIX/MSI에 포함
  - 플러그인을 negaflow 설치 프로그램에 자동 포함
  - negaflow가 libsane 또는 이 플러그인의 코드를 링크
```

negaflow 본체 windows_docs의
`13-build-and-deps/third-party-licenses.md` §12.3이 같은 경계를 정의하며,
"macOS보다 약하지 않은 분리를 유지한다"고 적는다.

**이 저장소는 그 분리의 플러그인 쪽 절반을 소유한다.**

### 6.1 설치 프로그램 분리

```text
negaflow 본체 설치 프로그램        ← Apache-2.0, SANE 없음
negaflow-scanner-sane 설치 프로그램 ← GPL-2.0-or-later, SANE 포함
```

**두 설치 프로그램은 별도 다운로드다.** 본체 설치 중에 플러그인을
자동으로 받지 않는다. 사용자가 명시적으로 플러그인을 설치한다.

본체 UI에서 "SANE 스캐너 플러그인 설치"를 안내하고 다운로드 페이지로
보내는 것은 허용된다. 그것은 배포가 아니라 안내다.

## 7. 라이선스 표시

### 7.1 설치 프로그램 UI

MSI의 라이선스 동의 화면에 GPL-2.0-or-later 전문을 표시한다.

**"동의"를 요구하는 것이 GPL의 취지와 맞지 않는다**는 견해가 있다.
GPL은 사용에 동의를 요구하지 않고 배포·수정에만 조건을 건다.

```text
권장: "동의합니다" 대신 "라이선스를 확인했습니다" 또는
      단순히 라이선스 텍스트를 표시하고 계속 진행.
```

macOS의 `Installer/Resources/LICENSE.html`이 현재 어떻게 표현하는지
확인하고 일관되게 한다.

### 7.2 실행 파일 메타데이터

```text
VERSIONINFO 리소스:
  CompanyName      (개인 또는 조직)
  FileDescription  "negaflow SANE scanner plug-in"
  FileVersion      1.0.3.0
  ProductVersion   1.0.3
  LegalCopyright   "Copyright ... Licensed under GPL-2.0-or-later."
  OriginalFilename "negaflow-scanner-sane.exe"
```

`LegalCopyright`에 라이선스를 명시하면 파일 속성에서 바로 보인다.

### 7.3 `--version` / `--license`

CLI에 라이선스 표시를 추가하는 것을 검토한다.

```text
negaflow-scanner-sane --version
  negaflow-scanner-sane 1.0.3
  Copyright ...
  License GPL-2.0-or-later: GNU GPL version 2 or later
  This is free software: you are free to change and redistribute it.
  There is NO WARRANTY, to the extent permitted by law.

  SANE runtime: sane-backends 1.4.0 (patched)
  Source: <설치 디렉터리>\sane-backends-1.4.0-negaflow-source.tar.gz
```

**현재 macOS 구현에 `--version`이 없다.** 추가하면 양쪽에 추가한다.
GNU 관례를 따르는 것이 GPL 프로그램으로서 적절하다.

## 8. `verify-provenance.py` 확장

[toolchain-and-layout](../06-build/toolchain-and-layout.md) §7.1에 정리했다.
요약:

```text
Windows 정책:
  ✓ sane-runtime/patches/의 모든 패치가 SOURCES.md에 출처·라이선스와 함께 기록됨
  ✓ upstream tarball SHA-256이 고정되고 THIRD_PARTY_NOTICES.md와 일치
  ✓ GPL 소스 아카이브에 sane-runtime/ 전체가 포함됨
  ✓ 배포물의 모든 DLL이 THIRD_PARTY_NOTICES.md에 기록됨
  ✓ 어댑터 exe가 libsane을 링크하지 않음 (import table 검사)
  ✓ 소스 아카이브 두 사본의 SHA-256 일치
  ✓ poppler/libieee1284 부재 확인 (D-15)
```

**import table 검사**가 새롭고 유용하다.

```python
# 어댑터 exe의 import를 읽어 libsane이 없음을 확인
imports = read_pe_imports("negaflow-scanner-sane.exe")
assert not any("sane" in dll.lower() for dll in imports)
```

## 9. `THIRD_PARTY_NOTICES.md` 확장

현재 구조에 Windows 섹션을 추가한다.

```markdown
## Windows SANE runtime

- Project: https://www.sane-project.org/
- Upstream source: <URL>
- Upstream version: 1.4.0
- Upstream SHA-256: f99205c9...
- License: GPL-2.0-or-later
- Modifications:
  - 001-fix-build-on-mingw.patch (MSYS2, GPL-2.0-or-later)
  - 002-coolscan2-word-list.patch (upstream 9bea1ee)
  - 003-coolscan3-word-list.patch (upstream 9bea1ee)
  - 004-epson2-scan-height.patch
- Build configuration: sane-runtime/PKGBUILD
- Complete corresponding source: included in this distribution as
  sane-backends-1.4.0-negaflow-source.tar.gz

### Runtime dependencies bundled with the SANE runtime

| Library | Version | License | Source |
|---|---|---|---|
| libusb | ... | LGPL-2.1-or-later | ... |
| libtiff | ... | BSD-like | ... |
...
```

**"Modifications"를 명시하는 것이 GPLv2 §2(a)의 요구다.**
수정한 파일에 수정 사실과 날짜를 표시해야 한다. 패치 파일이
그 역할을 하되, 각 패치 헤더에 날짜와 설명을 넣는다.

## 10. 체크리스트

릴리스마다 확인한다.

- [ ] SANE 소스 아카이브가 설치물 안에 있다
- [ ] 릴리스 페이지에 병치돼 있다
- [ ] 두 사본의 SHA-256이 같다
- [ ] 아카이브에 모든 패치가 들어 있다
- [ ] 아카이브에 빌드 스크립트와 configure 인자가 들어 있다
- [ ] upstream tarball SHA-256이 notice와 일치한다
- [ ] 각 패치에 출처·날짜·설명이 있다
- [ ] 모든 번들 DLL이 notice에 기록됐다
- [ ] GPL 의존(poppler, libieee1284)이 없거나 소스가 제공된다
- [ ] LGPL 의존(libusb)이 동적 링크다
- [ ] COPYING(GPL v2 전문)이 설치물에 있다
- [ ] 어댑터 exe의 import table에 sane이 없다
- [ ] negaflow 본체 설치물에 SANE가 없다
- [ ] `verify-provenance.py`가 통과한다

## 11. 열린 질문

- poppler/libieee1284 의존을 제거할 수 있는가
- MSI 크기(약 40 MB)가 수용 가능한가
- `--all-options-json` 패치를 upstream에 제출할 것인가
- 라이선스 화면에서 "동의"를 요구할 것인가
- `--version`/`--license` 출력을 추가할 것인가 (양쪽 플랫폼)
- MinGW-w64 런타임 DLL의 라이선스 의무 정확한 범위
