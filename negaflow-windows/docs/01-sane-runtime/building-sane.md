# SANE 런타임 빌드와 패치

기준일: 2026-08-25
상태: x64 downstream SANE 1.4.0-5와 001~011 패치를 빌드하고 실기 검증했습니다. 빌드 진입점은
`../../scripts/build-sane-runtime.ps1` 이며, 손으로 패치를 복사하면 011 이 빠지는 사고가
실제로 있었으므로 그 스크립트를 씁니다. 현재 recipe와
패치별 출처·실측은 `../../../negaflow-mac/sane-runtime/PKGBUILD`와
`../../../negaflow-mac/sane-runtime/SOURCES.md`가 정본이며, 실제 설치 절차는
`../07-distribution/windows-build-and-install.md`가 우선입니다.
목적: Windows용 SANE 런타임을 우리가 어떻게 만들고 무엇을 책임지는지 정한다

관련 문서:

- [availability](availability.md)
- [runtime-route-decision](runtime-route-decision.md)
- [gpl-compliance](../07-distribution/gpl-compliance.md)
- [backend-quirks](../02-frontend-contract/backend-quirks.md)
- [packaging-and-install](../07-distribution/packaging-and-install.md)

## 0. 현재 구현

- upstream `sane-backends` 1.4.0 고정 tarball 위에 11개 패치를 순서대로 적용한다.
- 빌드 백엔드는 `genesys epson2 epsonds coolscan2 coolscan3 test`이며, 설치
  payload에는 test를 제외한 다섯 백엔드를 넣는다.
- 009는 epson2 IR 프레임, 010은 설치 번들의 backend 검색 경로, 011은
  OpticFilm 7400-v2/8100 host-side Gray(색 필터 `None` 노출 포함)와 GL845/GL846 종료
  길이를 담당한다. 종료 길이를 `gl843.cpp` 에 넣으면 8100 은 `AsicType::GL845` 라
  `CommandSetGl846` 을 쓰므로 아무 효과가 없다.
- 2026-08-25 clean 작업 디렉터리 빌드, UCRT64
  build, adapter Release CTest 5/5, 설치본 OpticFilm Gray 16-bit 연속 2회와 Color 회귀,
  Negaflow host 종단 4조합을 통과했다. macOS formula 의 같은 수정은 맥 실장 검증이 남았다.
- 아래 §1~§4는 macOS 패치와 초기 Windows 설계 판단의 역사적 근거다. 현재
  Windows 파일 목록·번호·상태로 사용하지 않는다.

## 1. macOS에서 우리가 하고 있는 일

현재 이 저장소는 이미 SANE 배포자다.

- 표준 설치 프로그램: Homebrew에게 stock `sane-backends`를 설치하게 한다.
  **우리는 SANE 바이너리를 배포하지 않는다.**
- Coolscan 설치 프로그램: `Formula/sane-backends-negaflow.rb`로 SANE 1.4.0
  소스를 내려받아 사용자 Mac에서 빌드한다. 패치 3개를 적용한다.
  **여전히 바이너리를 배포하지 않는다.** 소스와 formula만 배포한다.

이 구분이 GPL 준수 설계의 핵심이다. 소스와 빌드 레시피를 배포하면
"완전한 대응 소스"가 자동으로 충족된다.

**Windows에는 Homebrew가 없다.** 사용자 머신에서 MSYS2 툴체인으로 SANE를
빌드하게 하는 것은 현실적이지 않다. 따라서 Windows에서는 거의 확실히
**바이너리를 배포하게 되고, 그 순간 GPL 소스 제공 의무가 우리에게 온다.**

## 2. macOS 패치 기준 기록

### 2.0 무엇에 패치하는가 — 고정된 upstream 소스

D-07이 "upstream tarball SHA-256과 툴체인 버전을 고정한다"를 요구한다.
**macOS가 이미 고정하고 있는 값이 이것이다.** Windows 빌드는 같은 소스에서
출발해야 백엔드 동작이 같다.

```text
upstream 버전   1.4.0
tarball SHA-256 f99205c903dfe2fb8990f0c531232c9a00ec9c2c66ac7cb0ce50b4af9f407a72
formula 버전    1.4.0-negaflow.2
upstream 수정   sane-project/backends 커밋 9bea1ee256c744098576acee98053e094b4a14a2
```

tarball URL은 표준 릴리스 경로가 아니라 **GitLab uploads 경로**다.

```text
https://gitlab.com/-/project/429008/uploads/
    843c156420e211859e974f78f64c3ea3/sane-backends-1.4.0.tar.gz
```

**추측으로 찾을 수 없는 주소다.** 정본은 저장소 루트의
`THIRD_PARTY_NOTICES.md`이며, `Formula/sane-backends-negaflow.rb`의
`url`/`sha256`/`version`과 일치해야 한다. gpl-compliance 체크리스트의
"upstream tarball SHA-256이 고정되고 THIRD_PARTY_NOTICES.md와 일치"가
이 일치를 요구한다.

버전을 올릴 때는 세 곳(Formula, THIRD_PARTY_NOTICES.md, 이 문서)을 함께
고치고, `-A` 덤프를 재수집한다
([availability](availability.md) §7.2 — `-A` 출력은 버전 간 안정적이지 않다).

패치 내용은 `Formula/sane-backends-negaflow.rb`의 `__END__` 이후에 있다.

### 2.1 coolscan2 word-list 할당

```diff
--- a/backend/coolscan2.c    (546행)
-	  word_list = (SANE_Word *) cs2_xmalloc (2 * sizeof (SANE_Word));
+	  word_list = (SANE_Word *) cs2_xmalloc (3 * sizeof (SANE_Word));
```

### 2.2 coolscan3 word-list 할당

```diff
--- a/backend/coolscan3.c    (506행)
-				(SANE_Word *) cs3_xmalloc(2 *
+				(SANE_Word *) cs3_xmalloc(3 *
```

두 패치의 upstream 커밋: `9bea1ee256c744098576acee98053e094b4a14a2`.
힙 오버플로우이며 macOS 26의 강화된 할당자에서 즉시 크래시한다.

### 2.3 epson2 스캔 높이 절삭

```diff
--- a/backend/epson2-ops.c   (1423행)
-			((int) SANE_UNFIX(s->val[OPT_BR_Y].w) / MM_PER_INCH *
+			(SANE_UNFIX(s->val[OPT_BR_Y].w) / MM_PER_INCH *
```

`(int)` 캐스트가 나눗셈보다 먼저 걸려 `br_y`를 정수 mm로 잘라낸다.
자세한 내용은 [backend-quirks](../02-frontend-contract/backend-quirks.md) §2.3.

### 2.4 Windows에서의 필요성

| 패치 | Windows에서 필요한가 |
|---|---|
| coolscan2/3 word-list | **예.** OS 무관한 힙 오버플로우다. Windows 힙이 조용히 넘어갈 수도 있지만 그것은 "동작한다"가 아니라 "아직 안 터졌다"이다 |
| epson2 높이 | **선택.** 플러그인 쪽 `epson2AlignedHeightMM` 보정으로도 대응된다. 백엔드를 고치면 보정이 no-op가 되고, 고치지 않아도 계약이 지켜진다 |

## 3. 초기 MSYS2 재빌드 판단

**확인** — MSYS2 `mingw-w64-sane` 1.4.0-4의 `BACKENDS=` 허용 목록에
다음이 없다.

| 백엔드 | 필요성 |
|---|---|
| `pieusb` | Reflecta ProScan/CrystalScan/DigitDia, PIE PowerSlide 지원 |
| `pie` | 구형 PIE SCSI (Windows에서는 사실상 불가능하므로 우선순위 낮음) |
| `net` | 원격 saned (지원 대상 밖이므로 선택) |

그리고 다음 패치가 적용돼 있지 않다.

- coolscan2/coolscan3 word-list (§2.1, §2.2)
- epson2 높이 (§2.3)

또한 빌드 플래그에 `--disable-locking`이 있어 SANE 계층의 장치 잠금이 없다.

**결론: 재빌드 없이 MSYS2 패키지를 그대로 재배포하면 Nikon Coolscan에서
힙 오버플로우를 안은 채 출하하게 된다.** Coolscan은 이 플러그인의 가장 강한
Windows 존재 이유이므로 이것은 받아들일 수 없다.

## 4. 초기 재빌드 계획 — 현재 구현 아님

### 4.1 무엇을 만드는가

```text
negaflow-sane-runtime/
  win-x64/
    bin/scanimage.exe
    bin/libsane-1.dll
    bin/libusb-1.0.dll
    bin/<필요한 런타임 DLL>
    lib/sane/libsane-genesys-1.dll
    lib/sane/libsane-epson2-1.dll
    lib/sane/libsane-epsonds-1.dll
    lib/sane/libsane-coolscan2-1.dll
    lib/sane/libsane-coolscan3-1.dll
    lib/sane/libsane-pieusb-1.dll
    lib/sane/libsane-dll-1.dll
    etc/sane.d/*.conf
  win-arm64/
    (동일 구조)
```

**백엔드를 최소로 좁힌다.** 58개 전부가 아니라 이 플러그인이 실제로 지원하는
것만 넣는다. 이유:

- 배포 크기
- 공격 표면
- `dll.conf`에서 사용하지 않는 백엔드를 로드하며 발생하는 지연과 오류
  (macOS의 `SaneConfigTuner`가 과거에 해결하려던 바로 그 문제)
- GPL 소스 제공 범위는 어차피 sane-backends 전체이므로 줄여도 의무는 같다

포함 후보:

```text
genesys      Plustek OpticFilm 7200~8200i
epson2       Epson Perfection V700~V850
epsonds      신형 Epson
coolscan2    Nikon Coolscan 구형
coolscan3    Nikon Coolscan LS-40/50/4000/5000/8000
pieusb       Reflecta / PIE
dll          백엔드 로더 (필수)
```

`test` 백엔드를 포함할지는 결정 사항이다. 가상 스캐너 테스트에 유용하지만
production 배포에 테스트 장치가 열거되면 사용자를 혼란시킨다.
**개발 빌드에만 포함한다.**

### 4.2 어떻게 만드는가

MSYS2 PKGBUILD를 fork한다.

```text
negaflow-scanner-sane/
  sane-runtime/
    PKGBUILD                        MSYS2 PKGBUILD 기반, BACKENDS 조정
    patches/
      001-fix-build-on-mingw.patch  MSYS2 원본 (442행)
      002-coolscan2-word-list.patch upstream 9bea1ee
      003-coolscan3-word-list.patch upstream 9bea1ee
      004-epson2-scan-height.patch  (선택)
      005-binary-stdout.patch       spike S-2 결과에 따라
    build.sh                        컨테이너/CI에서 재현 가능한 빌드
    SOURCES.md                      각 패치의 출처와 라이선스
```

빌드는 CI에서 수행한다. 로컬 MSYS2 설치에 의존하지 않는다.

### 4.3 재현 가능성

GPL 준수와 공급망 신뢰 양쪽에 필요하다.

- upstream tarball의 SHA-256을 고정한다:
  `f99205c903dfe2fb8990f0c531232c9a00ec9c2c66ac7cb0ce50b4af9f407a72`
  (sane-backends-1.4.0.tar.gz, 현재 formula에 이미 있는 값)
- MSYS2 툴체인 버전을 고정한다(패키지 스냅샷 또는 컨테이너 이미지 다이제스트).
- 빌드 산출물의 SHA-256을 릴리스에 기록한다.
- 완전한 대응 소스 아카이브를 릴리스마다 함께 배포한다
  ([gpl-compliance](../07-distribution/gpl-compliance.md)).

### 4.4 `--disable-locking`을 되돌릴 것인가

MSYS2가 끈 이유는 SANE의 잠금이 POSIX 파일 잠금과 `/var/lock/sane`
디렉터리에 의존하기 때문일 가능성이 높다(**미확인**).

되돌리려면 Windows용 잠금 구현이 필요하고, 그것은 upstream에 없는 기능을
우리가 만드는 일이다. **되돌리지 않는다.** 대신:

- 플러그인이 자체 세션 소유권으로 자기 프로세스 간 경합을 막는다
- WinUSB가 동시 열기를 애초에 거부하므로 실질적 보호가 있다
- 동시 열기 실패의 오류 문구를 `busy`로 정확히 분류한다(spike U-5)

## 5. `_setmode(_O_BINARY)` 문제 (spike S-2)

**미확인**: MSYS2 `scanimage.exe`가 stdout으로 바이너리 TIFF를 쓸 때
CRLF 변환이 개입하는지.

MinGW/MSVCRT에서 stdout의 기본 모드는 텍스트다. `_setmode(_fileno(stdout),
_O_BINARY)`를 호출하지 않으면 `0x0A`가 `0x0D 0x0A`로 확장된다.
16-bit TIFF에서 이것은 **파일 전체를 파괴한다.**

가능한 결과와 대응:

| S-2 결과 | 대응 |
|---|---|
| 이미 처리돼 있다 | 아무것도 안 한다. 가장 좋은 시나리오 |
| `--output-file` 같은 대안이 있다 | 그것을 쓴다. `makeScanimageArgs`에 인자 추가. **stdout 리다이렉트 계약이 바뀌므로 3장 문서 수정 필요** |
| 대안이 없다 | `005-binary-stdout.patch`를 만들어 유지한다. upstream에 제출한다 |

세 번째가 되면 우리는 SANE의 다운스트림 패치 유지자가 된다. 그 부담을
받아들이되, **패치를 upstream에 제출하는 것을 릴리스 조건에 넣는다.**
영구 fork는 유지 비용이 계속 늘어난다.

### 5.1 소스 감사 방법

```bash
grep -n "_setmode\|_O_BINARY\|setmode" frontend/scanimage.c
grep -rn "_setmode\|_O_BINARY" frontend/ sanei/ include/
```

`--format=tiff` 출력 경로(`scanimage.c` 2182~2194행 근처)에서 stdout 핸들을
어떻게 얻는지 확인한다.

## 6. `dll.conf` 처리

macOS의 `SaneConfigTuner`는 과거 버전이 공용 `dll.conf`에서 꺼둔 백엔드를
복구한다. 이 코드가 존재하는 이유는 Homebrew의 `dll.conf`가 **시스템의 모든
SANE 프런트엔드가 공유하는 파일**이기 때문이다.

Windows에서 우리가 SANE를 자체 디렉터리에 배치하면 이 문제가 사라진다.

```text
%LOCALAPPDATA%\Negaflow\Plugins\sane\sane\etc\sane.d\dll.conf
```

이 파일은 **우리만 쓴다.** 다른 프로그램이 공유하지 않는다. 따라서:

```text
D-05  Windows 어댑터는 dll.conf를 수정하지 않는다.
      repair-sane-config / tune-sane / restore-sane 서브커맨드는
      Windows 빌드에서 제거하거나, "이 플랫폼에서는 할 일이 없습니다"를
      출력하고 exit 0 하는 no-op로 남긴다.
```

**제거보다 no-op를 권장한다.** 서브커맨드가 사라지면 호스트나 사용자
스크립트가 호출했을 때 usage가 출력되고 exit 0이 되어(현재 default 분기)
성공으로 오인될 수 있다. 명시적 no-op가 낫다.

`dll.conf`는 우리가 배포하는 내용 그대로 쓴다. 포함한 백엔드만 활성화된
상태로 만들어 배포한다.

## 7. 설정 파일 경로

SANE는 컴파일 시점의 `--sysconfdir`에서 설정을 찾고, `SANE_CONFIG_DIR`
환경 변수로 재정의할 수 있다.

MSYS2 빌드는 `/ucrt64/etc/sane.d`를 컴파일 시점 경로로 갖는다. 우리가
재배치하면 그 경로가 존재하지 않으므로 **`SANE_CONFIG_DIR`을 반드시
설정해야 한다.**

```text
SANE_CONFIG_DIR = <플러그인 디렉터리>\sane\etc\sane.d
```

`dll` 백엔드가 다른 백엔드 DLL을 찾는 경로도 컴파일 시점에 정해진다
(`/ucrt64/lib/sane`). Windows에서는 `LD_LIBRARY_PATH`가 의미 없고,
DLL 검색은 다르게 동작한다 →
[environment-and-paths](../03-process-and-io/environment-and-paths.md) §4.

이것이 재빌드가 필요한 또 하나의 이유일 수 있다. `--libdir`와
`--sysconfdir`을 우리 레이아웃에 맞춰 설정하고 빌드하면 환경 변수 의존이
줄어든다. 상대 경로 기반 재배치 가능성은 spike로 확인한다.

## 8. 라이선스 결과

MSYS2 패키지는 GPL-2.0-or-later다. 재빌드해도 마찬가지다.
배포하면 우리에게 다음 의무가 온다.

- 완전한 대응 소스 제공(sane-backends 1.4.0 + 우리 패치 전부)
- 빌드 스크립트와 설정 제공
- 라이선스 사본 동봉
- 수정 사실 명시

플러그인 자체가 이미 GPL-2.0-or-later이므로 라이선스 호환성 문제는 없다.
**의무의 범위가 커질 뿐이다.**

의존 라이브러리(libusb LGPL-2.1+, libtiff BSD-like, libjpeg-turbo,
libpng, libxml2, curl, poppler GPL)에 대해서도 각각의 notice와,
LGPL 컴포넌트의 경우 재링크 가능성을 제공해야 한다.

**poppler는 GPL-2.0-or-later이며, 이 플러그인은 PDF를 만들지 않는다.**
재빌드로 poppler 의존을 제거할 수 있다면 제거한다. 의존을 줄이는 것이
배포 크기와 준수 부담 양쪽에 이롭다.

자세한 내용은 [gpl-compliance](../07-distribution/gpl-compliance.md).

## 9. 대안 — 빌드하지 않는 길

### 9.1 MSYS2 패키지를 그대로 재배포

빠르지만 Coolscan 힙 오버플로우가 남는다. Coolscan을 지원 대상에서 빼면
성립한다. 그러나 Coolscan이 Windows에서 SANE가 필요한 가장 강한 이유이므로
자기모순이다.

### 9.2 사용자에게 MSYS2 설치를 요구

```text
1. MSYS2 설치
2. pacman -S mingw-w64-ucrt-x86_64-sane
3. 플러그인 설정에서 scanimage.exe 경로 지정
```

배포 의무가 사라지고 GPL 부담이 없다. 그러나:

- 사용자 부담이 WSL2와 비슷한 수준으로 올라간다
- 패치가 적용되지 않는다
- `pieusb`가 없다
- 버전이 사용자마다 다르다 → `-A` 파싱 안정성 위험 증가

**개발자·고급 사용자용 경로로는 반드시 지원한다.**
`NEGAFLOW_SCANIMAGE_PATH` 환경 변수와 설정 파일로 임의 경로를 지정할 수
있게 유지한다(macOS에 이미 있는 기능).

### 9.3 WSL2 경로 우선

빌드 부담이 없다. 배포판이 SANE를 제공한다. 그러나 사용자 설치 부담이
가장 크다 → [runtime-route-decision](runtime-route-decision.md) §3.2.

## 10. 결정 요약

```text
D-06  Windows 배포는 자체 재빌드한 SANE 런타임을 포함한다.
      백엔드는 genesys, epson2, epsonds, coolscan2, coolscan3, pieusb, dll로 좁힌다.
      coolscan2/3 word-list 패치를 반드시 적용한다.

D-07  빌드는 CI에서 수행하고 upstream tarball SHA-256과 툴체인 버전을 고정한다.

D-08  NEGAFLOW_SCANIMAGE_PATH로 사용자가 자기 SANE를 지정할 수 있게 유지한다.
      그 경우 버전과 백엔드 구성이 우리 것과 다를 수 있음을 진단에 기록한다.

D-05  dll.conf를 수정하지 않는다. 관련 서브커맨드는 no-op로 남긴다.
```

## 11. 열린 질문

- MSYS2가 `--disable-locking`을 쓴 정확한 이유
- `--libdir`/`--sysconfdir`을 상대 경로 기반으로 만들어 재배치 가능하게
  할 수 있는가
- poppler·curl·libxml2 의존을 제거하고 빌드할 수 있는가
- `test` 백엔드를 개발 빌드에만 넣는 방법(별도 패키지 vs 빌드 플래그)
- upstream에 MinGW 패치와 binary stdout 수정을 제출할 것인가, 제출한다면 누가
- ARM64 빌드를 CI에서 어떻게 만드는가(clangarm64 크로스 빌드 가능 여부)
