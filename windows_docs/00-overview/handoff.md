# 인수인계 — 여기까지 왔고, 다음은 이것이다

기준일: 2026-08-05 (11차 갱신 — **실행 파일이 돈다.** Win32 계층 + main 완료)
기준 커밋: 6b3b347 (`windows/`, `windows_docs/` 커밋됨)
상태: 사실 기록 — 이어받는 사람이 가장 먼저 읽는 문서
목적: 다른 사람이 이 작업을 중단 없이 이어가게 한다

## 0. 5분 안에 상태 확인하기

Windows(정식 대상):

```bash
python windows_docs/check-docs.py           # 문서 정합성
cmake -S windows -B build -A x64 \
  -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
  -DVCPKG_TARGET_TRIPLET=x64-windows-static
cmake --build build --config Release --parallel
ctest --test-dir build -C Release --output-on-failure
```

macOS(파리티 전용):

```bash
./windows/tools/parity-check.sh             # C++ ↔ Swift 동등성
```

**개발 도구가 없으면 그 블록을 조용히 건너뛴다** — 그러면 검증이 줄어든
채로 통과한다. 스크립트가 무엇을 감지했는지 stderr 를 읽는다.

```bash
brew install libtiff rapidjson pkgconf      # macOS 개발 환경
```

`pkgconf` 가 빠지면 `pkg-config` 가 사라져 libtiff 대조가 통째로 빠진다.
(2026-08-05 에 `brew install` 의 자동 정리가 실제로 그것을 지웠다.)

`VCPKG_TARGET_TRIPLET` 을 빼면 vcpkg 기본이 동적 CRT 라 LNK2038 로 링크가
깨진다. **가장 자주 틀리는 한 줄이다.**

전부 통과하면 이 문서가 기술한 상태 그대로다. **하나라도 실패하면
그 원인을 먼저 파악한다.** 특히 파리티 실패는 "누군가 Swift 원본을
고쳤다"는 신호일 수 있다.

## 1. 이 프로젝트가 무엇인가

macOS에서 동작 중인 SANE 스캐너 플러그인(Swift, 4,922행)을 Windows로
옮긴다. 플러그인은 `scanimage`를 자식 프로세스로 띄우는 어댑터이며,
negaflow 본체(Apache-2.0)와 **프로세스로 분리**돼 GPL 경계를 유지한다.

산출물 셋:

```text
windows_docs/                     44개 문서 — 설계 정본
windows/                          C++20 소스 — 구현
.github/workflows/windows.yml     MSVC 빌드 CI (아직 한 번도 돌지 않았다)
```

정확한 규모는 세어서 확인한다. 여기 숫자를 박아두면 조용히 낡는다.

```bash
find windows/src windows/tests windows/tools -type f | wc -l
find windows/src -name '*.cpp' -o -name '*.h' | xargs wc -l | tail -1
```

**둘 다 아직 git에 커밋되지 않았다**(`git status`에 `??`로 뜬다).
커밋 여부는 사용자 결정 사항이라 손대지 않았다.

## 2. 지금 어디까지 왔나

### 코드

```text
sane_logic (순수 로직, 의존 0)              ✅ 완성
    util/numeric          containsExactly, saneNumber, epson2AlignedHeightMM
    sane/option_dump      scanimage -A 파서
    sane/device_list      -f/-L 파싱, 백엔드 판정, identity, dedupe
    sane/capabilities     parseCapabilities, fixedDepth, 소스 선택
    sane/media            resolveMedia (최대 함수), 재덤프 인자
    sane/validate         validateExactOptions (거부 24종)
    sane/args             makeScanimageArgs

process_logic (순수 로직)                   ✅ 완성
    process/progress      진행률 파싱, stderr 분류
    process/budget        D-32 명령별 예산 (신규 설계)
    process/command_line  CreateProcessW 인용, 인자 주입 방어
    process/acquisition   재시도 정책

process_win32                               ✅ 완성 (Windows 에서만 빌드)
    process/child         CreateProcessW, 파이프 동시 drain, Job Object,
                          PROC_THREAD_ATTRIBUTE_HANDLE_LIST, stdin=NUL,
                          출력 파일 핸들 검증(GetFinalPathNameByHandleW)
    process/watchdog      첫 진행률/유휴 상한 + 진행률 누적. **Win32 없음**
    process/cancel        소유권 상태 기계, 콘솔 제어 핸들러, 3단계 종료

imaging_logic (순수 로직, 의존 0)           ✅ 완성
    imaging/align         estimateIntegerOffset, boxBlur3, 신뢰 가중치,
                          mix/smoothstep, accumulateAligned
    imaging/merge         병합 코어 전량 + 평균 경로(테스트 전용)
    imaging/tiff_contract 태그 → 통과/거부 판정. D-10 추가 검사 포함

imaging_tiff (libtiff)                      ✅ 순수 부분 외 완성
    imaging/tiff_io       읽기/쓰기/크기조회/검증. **libtiff 를 아는 유일한 타깃**
    ⬜ 파일 계층 §3.4     핸들 기반 검증, reparse point 거부 (Win32)

wire_logic (순수 로직)                      ✅ 완성
    wire/request          ✅ 1단계 검증. 가드 11개, 경로 정책 주입식
    wire/json             ✅ 방출. 이스케이프·수 표기·키 순서
    wire/event            ✅ 이벤트/적용옵션. 생략 vs null 경계
    wire/protocol         ✅ detect/capabilities 응답 DTO 인코딩
    wire/emitter          ✅ sequence 규율 + 줄 프레이밍 (**파리티 없음**)
    wire/writer           ✅ 부분 쓰기 루프 (**파리티 원리상 불가**)
    wire/cli              ✅ 서브커맨드 디스패치 판정 (**파리티 없음**)

wire_win32                                  ✅ 완성
    wire/win_sink         WriteFile ByteSink + stdout 바이너리 고정.
                          **루프는 없다** — 재개는 wire/writer 가 갖는다

wire_parse (RapidJSON)                      ✅ 완성
    wire/parse            요청 디코딩. **RapidJSON 을 아는 유일한 타깃**
                          토큰화만 쓰고 수 변환은 std::from_chars 로 직접 한다
    wire/snapshot         capabilityToken. base64 + JSON. SAX 만 쓴다

app (조율 계층)                             ✅ 완성
    app/environment       scanimage 탐색(PE machine 확인), 자식 환경 블록,
                          IR/중간 파일 경로 규칙
    app/backend           detect / capabilities / scan 의 순서와 재시도.
                          **판정은 하지 않는다** — 전부 아래 계층이 갖는다
    main.cpp              wire/cli 의 판정을 받아 실행만 한다
```

**실행 파일이 있다: `negaflow-scanner-sane.exe`.** libtiff 와 RapidJSON 이
둘 다 있을 때만 만든다.

### 검증 상태

| 항목 | 상태 |
|---|---|
| MSVC 빌드 | Debug/Release 둘 다 통과 (`/W4 /WX`, 경고 0) |
| 단위 테스트 | 1,063 checks 통과 (Debug/Release 동일) |
| 실행 파일 스모크 | `plugin_smoke` 통과 — 가상 scanimage 상대 end-to-end |
| 파리티 (C++ ↔ Swift) | 574줄 중 573줄 일치 (1건은 문서화된 CRLF) |
| 문서 정합성 | 44개 통과 |
| 백엔드 분기 (순수) | **13/13 이식 완료** |
| spike | **5개 통과** (N-1, N-2, N-3, N-4, I-2) |
| 실기 검증 | **0대.** 아래 §8 |

**§0의 명령이 이 표를 재생성한다.** 숫자가 다르면 표가 낡았거나
누군가 코드를 고쳤다는 뜻이다.

`plugin_smoke` 가 무엇을 지나는지는 `windows/tests/plugin-smoke.cmake` 가
소유한다. 요약하면:

```text
detect → capabilities → scan(단일 / IR 별도 패스 / 다중 노출 3패스 병합)
깨진 요청·봉투만 있는 요청의 오류 경로
stderr 1 MiB 폭주에도 교착하지 않는가
반올림 경고가 있으면 결과를 버리는가 (I-1)
**첫 open 이 죽은 주소로 실패하면 재열거 후 다시 시도하는가**
scanimage 가 없을 때 원인을 말하는가
```

마지막에서 두 번째가 실기에서 가장 흔한 실패다 — 장치를 열 때마다 libusb
주소가 바뀌므로 토큰에 적힌 주소는 이미 죽어 있을 수 있다.

**가상 scanimage 는 우리 코드를 링크하지 않는다.** TIFF 를 손으로 쓴다 —
우리 writer 로 만들면 "우리가 쓴 것을 우리가 읽는다"가 되어 검증이 자기
자신을 확인하는 꼴이 된다.

### 닫힌 결정

- D-32 신설 (명령별 타임아웃 예산) — `process/budget`에 구현됨
- Q-18 종결 (`serialNumber` 부재가 ID 불안정 신호 — wire 변경 불필요)
- 본체 요구사항 26개 중 25개 충족 확인
  ([host-requirements](../05-protocol/host-requirements.md))

## 3. 다음에 할 일

**소프트웨어로 검증할 수 있는 것은 다 했다.** 남은 것은 **전부 실기와
협의**를 요구한다.

```text
A. 병합 입력 스트리밍       7200 dpi 12 패스면 입력만 13.2 GB   §3.3
B. imaging/tiff 읽기 경로   핸들 기반 검증 (쓰기 경로는 되어 있다)  §3.4
C. 실기 검증                장치 0대. spike S-1/S-2/D-1/C-1~C-4    §8
D. SANE 런타임 배포          scanimage.exe 를 어떻게 담을 것인가    §3.6
```

### 3.0 이미 지난 관문 — **Windows 에서 빌드되고 돈다**

2026-08-05 에 로컬 Windows(VS 2026, MSVC 19.51, CMake 4.3, vcpkg)에서
설정·빌드·테스트를 전부 통과시켰다. `.github/workflows/windows.yml` 이
같은 것을 `windows-latest` 에서 Debug/Release 양쪽으로 돈다.

Debug 를 같이 도는 이유가 있다. `_ITERATOR_DEBUG_LEVEL` 불일치는 Debug 에서만
드러나고, `CMAKE_MSVC_RUNTIME_LIBRARY` 의 제네레이터 식이 정확히 그 경우를
다룬다 — 안 돌리면 그 식이 검증되지 않는다.

첫 빌드에서 실제로 걸린 것은 셋이었고, 셋 다 **우리 코드의 문제**였다.

```text
C4996  _wfopen / getenv     `/sdl` 이 막는다. 짝인 _wfopen_s / _dupenv_s 로 고쳤다
C4456  parity_dump 의 `d`   같은 함수 안 바깥 선언을 가린다. clang 은 침묵했다
LNK4075 /INCREMENTAL        Debug 에 /OPT:ICF 를 걸어 증분 링크가 버려졌다
```

**셋 다 macOS 에서는 보이지 않았다.** `/W4 /WX` 가 clang `-Wall -Wextra`
보다 넓은 것이 아니라 **다른 것을 본다**.

### 3.0a 첫 빌드가 실제로 닫은 것

| 항목 | 결과 |
|---|---|
| `testFromCharsOutOfRangeContract` | 통과. MSVC STL 이 libc++ 과 같다 |
| 단위 테스트 수 | macOS 965 = Windows 965 (당시). **블록이 조용히 빠지지 않았다** |
| RapidJSON master 의 `0e999` 거부 | 그대로다. §3.2 ① 종결 |
| `/sdl` 의 `/we4996` 가 외부 헤더를 뚫는가 | **뚫지 않았다.** §3.2 ③ 종결 |

`wire_parse` 의 `/wd4996` 은 켜지 않았다. **켤 필요가 없었으므로 켜지
않는다** — 이유 없이 켜 두면 다음 사람이 지웠다가 같은 곳에서 막힌다.

### 3.1 조사로 **닫힌** 것 (2026-08-05) — 다시 조사하지 말 것

웹 조사로 1차 자료(MSVC STL 소스, MS 문서, CMake 소스, 러너 이미지 README)를
확인해 닫았다. **여기 적힌 것을 "미확인"으로 되돌리지 말 것.**

**① `std::from_chars(double)` 은 MSVC 와 갈리지 않는다.**

MSVC STL 소스와 그 테스트 스위트를 직접 확인했다. 아홉 개 경계 입력 전부
libc++ 과 같다.

```text
1e-324 / 1e-400   out_of_range, 값 0     MSVC STL 에 주석이 있다:
                                         "reports underflow only when the result
                                          is zero after rounding"
4.9e-324          ok, denorm_min          VSO-838635 로 고쳐진 이력이 있다
0e999 / 0e-999    ok, 값 0                가수가 비면 지수 검사 전에 단락한다
1e309             out_of_range, inf
반올림             최근접-짝수. 큰 정수 정확 경로라 구조적으로 정확 반올림
```

**libstdc++(MinGW/Linux)만 하나 다르다.** 실패 시 `value` 를 **쓰지 않는다**
(MSVC 와 libc++ 은 0/inf 를 써 준다). 우리 코드는 모든 호출부가 변수를
초기화하고 `ec` 를 먼저 검사하므로 안전하다 — **그 습관을 깨지 말 것.**

**② `/fp:precise` 만으로는 FMA 축약이 안 꺼진다 — 고쳤다.**

이 문서와 CMakeLists 가 `/fp:precise` 를 충분한 것처럼 서술하고 있었다.
**VS 2022 에서만 맞다.**

```text
                /fp:precise 의 기본 fp_contract
VS 2019 이하     on    ← 축약이 일어난다. ARM64 는 스칼라까지
VS 2022 17.0+    off
```

끄는 수단이 하나뿐이라는 것도 확인됐다 — `/fp:contract-` 는 **존재하지 않고**,
`#pragma float_control(precise,on)` 은 VS 2019 에서 축약에 영향이 없다.
`#pragma fp_contract(off)` 만 전 버전·전 아키텍처에서 통한다.

`windows/src/util/msvc_fp_contract.h` 를 CMake 가 `/FI` 로 **모든 번역 단위에
강제 포함한다.** 어느 파일이 민감한지 사람이 판단하게 두면 언젠가 빠뜨리고,
빠뜨려도 빌드는 통과한다.
→ [field-lessons](../10-lessons/field-lessons.md) §9b.6

**③ `SYSTEM` 인클루드는 CMake 가 `/external:W0` 을 자동으로 붙인다.**

손으로 적을 필요가 없다. 다만 MSVC < 19.29.30036.3 이거나 CMake < 3.24(VS
생성기)면 **조용히 `/I` 로 떨어진다** — 그러면 RapidJSON 경고가 `/WX` 에 걸려
빌드가 깨진다. CMakeLists 가 `FATAL_ERROR` 로 먼저 멈추게 해 두었다.

`TIFF::TIFF` 는 imported target 이라 CMake 3.25+ 가 자동으로 SYSTEM 처리한다.
손으로 `SYSTEM` 을 적는 곳은 RapidJSON 하나뿐이다(포트가 변수만 내보낸다).

**④ 정적 CRT 에는 `x64-windows-static` 트리플릿이 필요하다.**

`CMAKE_MSVC_RUNTIME_LIBRARY` 가 정적인데 vcpkg 기본은 동적이라, 안 주면
LNK2038 로 링크가 깨진다. 워크플로에 이미 들어 있다.

```text
x64-windows-static      CRT 정적 + 라이브러리 정적   ← 이것
x64-windows-static-md   CRT **동적** + 라이브러리 정적   ← 이름이 함정이다
```

### 3.2 열려 있던 셋 중 둘은 첫 빌드가 닫았다

**① RapidJSON 버전 차이 — 닫혔다 (2026-08-05).**

```text
macOS 개발   Homebrew 1.1.0       (2016-08-25. 유일한 태그다)
Windows      vcpkg master 스냅샷   (version-date 2025-02-26)
```

`wire/parse` 의 실측은 전부 1.1.0 에서 했다. 걱정한 것은 **`0e999` 거부가
그 토큰화의 지수 검사에서 나왔다**는 점이었다.

**master 에서도 같았다.** `testParseZeroMantissaHugeExponentDivergence` 를
포함해 파서 테스트 전부가 MSVC 빌드에서 통과했다. 경고 넷(C4996/STL4015,
C5054, C5232, C4127)도 나오지 않았다 — 그 넷이 사는 `document.h` /
`schema.h` / `pointer.h` 를 애초에 끌어오지 않기 때문이다.

**② `vcpkg.json` 에 `builtin-baseline` 이 없다 — 여전히 열려 있다.**

포트 버전이 러너 이미지에 따라 떠다닌다. **여기서 SHA 를 지어내지 않았다** —
실제 vcpkg 커밋을 골라야 하고, 틀린 SHA 는 빌드를 깬다. 고정하려면
`vcpkg x-update-baseline --add-initial-baseline` 을 실제 클론에서 돌리고,
그 뒤 **CI 가 그 커밋을 fetch 할 수 있는지**까지 확인한다.

지금 실측된 것은 tiff 4.7.2 + zlib 1.3.2 + rapidjson master 다.

**③ `/sdl` 의 `/we4996` 이 외부 헤더를 뚫는가 — 닫혔다. 뚫지 않았다.**

`/we` 는 경고 레벨과 무관하지만, RapidJSON 헤더에서 4996 이 나오지 않아
문제가 되지 않았다. `wire_parse` 의 `/wd4996` 은 **켜지 않은 채로 둔다.**

대신 **우리 코드에서** 두 번 터졌다 — `_wfopen` 과 `getenv` 다. 둘 다
`_CRT_SECURE_NO_WARNINGS` 로 덮지 않고 짝인 `_wfopen_s` / `_dupenv_s` 로
고쳤다. 경고를 지우는 것과 경고가 가리키는 것을 고치는 것은 다르다.

### 3.3 A — 병합 메모리: 절반 했다

**병합이 스스로 만들던 오버헤드는 줄였다**(2026-08-05).
`normalized` 배열 N장을 없애고 지연 계산으로 바꿨으며, 16비트 양자화도
중간 float 비트맵을 거치지 않는다. 정렬만은 전체 배열을 요구하므로
거기서만 **기준 1장 + 표본 1장**을 만든다.

실측(12 패스 700×500, 같은 출력 체크값):

```text
옛 구조   입력 64 MB → 피크 143 MB    오버헤드 79 MB
현재      입력 64 MB → 피크  78 MB    오버헤드 14 MB     5.6배 감소
```

파리티 6 케이스가 전부 그대로 통과했다 — **비트 동일이 유지된다.**
그 근거인 "지연 정규화 == 배열 정규화" 항등식은 단위 테스트가 고정한다.

**남은 것**: 호출자가 넘기는 입력 N장이 그대로 상주한다. 7200 dpi 12 패스면
그것만 13.2 GB다. 없애려면 픽셀을 TIFF에서 필요할 때 읽어야 하고,
그러려면 `ImageList`가 "행 단위 소스" 추상이어야 하며 그것을 지휘할 계층이
필요하다(M5).

**그리고 정렬이 걸린다.** `fullResLumaError`는 후보 오프셋마다 이미지 전체를
훑는다. 스트리밍하면 패스마다 TIFF를 15번쯤 다시 읽게 된다 — 성능 대가가
있는 설계 결정이고, **검증이 끝난 `imaging/align`의 동작 표면을 건드린다.**
그래서 절반에서 멈췄다. 절반만 구현하면 "비트 동일"과 "메모리 안전" 중
어느 것도 확실하지 않은 상태가 된다.
→ [exposure-merge](../04-imaging/exposure-merge.md) §7.2.2

### 3.4 B — TIFF 파일 계층 (Win32)

`validatedScannedTIFF`가 지금은 `std::filesystem`으로 regular file /
symlink / 크기만 본다. 빠진 것 둘:

```text
⬜ reparse point 거부   FILE_ATTRIBUTE_REPARSE_POINT
⬜ 핸들 기반 검증       경로로 검증하고 경로로 다시 열면 TOCTOU
```

핸들을 유지한 채 libtiff에 넘기려면 `TIFFClientOpen`과 Win32 핸들 I/O
콜백이 필요하다. **지금 상태는 macOS와 같은 수준이다**(macOS도 경로 기반) —
뒤처진 것이 아니라 아직 강화하지 않은 것이다.
→ [tiff-validation](../04-imaging/tiff-validation.md) §9.1

### 3.5 C — `process/` 의 Win32 3개: **끝났다**

```text
process/child      CreateProcessW, 익명 파이프 동시 drain, Job Object,
                   PROC_THREAD_ATTRIBUTE_HANDLE_LIST, stdin=NUL,
                   출력 파일을 열자마자 핸들로 검증
process/watchdog   첫 진행률/유휴 상한. **Win32 를 포함하지 않는다** —
                   타이머는 condition_variable 시한 대기이고 죽이는 행위는
                   콜백으로 밀어냈다. 그래서 판정이 단위 테스트로 고정된다
process/cancel     소유권 상태 기계 + SetConsoleCtrlHandler + 3단계 종료
```

`SANEBackend+Process.swift`(489행)는 예고대로 **이식하지 않고 다시 썼다.**
Foundation `Process`/`Pipe`/`DispatchSource`/POSIX 신호에 묶여 있어 옮길
것이 없었다.

**교착은 실제로 재현해서 막았다.** `plugin_smoke` 의 `bigout` 시나리오가
가짜 scanimage 로 stderr 에 1 MiB 를 쏟아붓는다 — stdout·stderr 를 동시에
읽지 않거나 자식용 파이프 끝을 안 닫으면 거기서 멈춘다.

**남은 것**: 강제 종료 뒤 복구 절차(cancellation §5.2)는 구현하지 않았다.
`lastCancellationWasForced()` 가 그 사실을 들고 있지만 아직 호출부가 없다 —
유예 시간과 복구 절차를 정하려면 실기 측정(C-2, C-3)이 필요하다.

### 3.6 D — `wire/` 의 나머지 3개: **끝났다**

```text
WriteFile 어댑터  wire/win_sink. **ByteSink 구현 하나**다 — 재개 루프는
                  wire/writer 에 그대로 있고 여기서 루프를 돌지 않는다
응답 조립         app/backend + main.cpp. DTO 인코딩은 wire/protocol 그대로다
main.cpp          wire/cli 의 판정을 받아 실행만 한다
```

**결정은 아직 그대로 걸려 있다.** 알 수 없는 서브커맨드의 exit 코드가 macOS 는
0 이고 [wire-contract](../05-protocol/wire-contract.md) §6 은 2 를 권한다.
`main.cpp` 는 **기본값(macOS 쪽)을 쓴다** — 바꾸는 것은 사용자에게 보이는
동작 변경이라 D 번호가 필요하고, 결정이 나면 `planCli` 호출에 정책 하나를
더 넘기면 된다.

### 3.7 D — SANE 런타임을 어떻게 담을 것인가

어댑터는 `scanimage.exe` 를 **찾기만 한다**. 탐색 순서는 셋이다.

```text
1. NEGAFLOW_SCANIMAGE_PATH        환경 변수. **여기서도 검증한다**
2. <플러그인 디렉터리>\sane\bin\scanimage.exe
3. PATH                            마지막 수단. 검증되지 않은 버전 경고를 붙인다
```

2번을 실제로 채우는 것이 남은 일이고, **거기에 차단 항목이 하나 확정됐다.**

```text
S-2 실패 (2026-08-05, 장비 없이 확정)

  SANE 1.4.0 frontend/scanimage.c 는 Windows 에서 바이너리 모드를
  설정하지 않는다. MinGW/UCRT 기본이 텍스트 모드라 stdout 으로 나가는
  이미지의 0x0A 마다 0x0D 가 삽입된다.
  `--output-file` 도 fopen(path, "w") 라 똑같이 깨진다.
  배포된 scanimage.exe 의 -L/--help 출력이 전부 CRLF 인 것으로 확인했다.

  → **MSYS2 패키지를 그대로 재배포하면 안 된다.**
     _setmode(_fileno(ofp), _O_BINARY) 3줄을 얹어 직접 빌드해야 한다.
     그 수정으로 바이트가 보존되는 것까지 같은 툴체인에서 측정했다.
```

전문과 근거: [runtime-route-decision](../01-sane-runtime/runtime-route-decision.md) §5.
남은 조건은 S-1(실기 open)과 E-1/E-2 다.
→ [building-sane](../01-sane-runtime/building-sane.md),
  [environment-and-paths](../03-process-and-io/environment-and-paths.md) §9

**우리 어댑터 쪽에 고칠 것은 없다.** 텍스트 모드 변환은 자식의 CRT 안에서
일어나므로 부모가 핸들을 어떻게 만들든 막을 수 없다. 이것은 우리가 배포할
SANE 런타임의 문제다.

## 4. 반드시 알아야 할 것

### 4.1 파리티 하네스가 이 작업의 핵심 도구다

```bash
./windows/tools/parity-check.sh
```

`swift build -Xswiftc -enable-testing` 후 `@testable import SANEPluginCore`로
**저장소의 실제 Swift 구현을 링크**해 같은 입력을 먹이고 diff한다.

**소스를 복사하지 않는 것이 중요하다.** 복사본을 두면 원본이 바뀌어도
파리티가 통과해버린다.

모듈을 추가하면 두 파일에 케이스를 넣는다:

```text
windows/tools/parity_reference.swift   Swift 쪽 (같은 key=value 출력)
windows/tests/parity_dump.cpp          C++ 쪽
```

C++ 소스 목록은 `find`로 자동 수집하므로 스크립트를 고칠 필요 없다.

### 4.2 파리티가 잡아내는 divergence는 **하나뿐**이다

```text
crlf.depth   Swift: (없음)   C++: 8,16
```

Swift는 `"\r\n"`을 **한 Character**로 보아 CRLF 덤프에서 줄을 나누지
못한다. 첫 옵션만 남고 나머지가 전부 사라진다. **C++가 옳다.**
MinGW `scanimage`가 CRLF를 낼 수 있으므로 그대로 베끼면 Windows에서
능력 판정이 무너진다.
→ [option-dump-parser](../02-frontend-contract/option-dump-parser.md) §2.2.1

**이 1건 외의 차이가 나오면 그것은 버그다.** 스크립트가 그렇게 판정한다.

### 4.2a 파리티 corpus 에 **일부러 넣지 않은** 차이 둘

위 문장에는 함정이 있다. 파리티는 **corpus 에 있는 입력만** 본다. 아래 둘은
macOS 와 다르다는 것을 알고 corpus 에서 뺐다 — 넣으면 매번 빨간불이 뜬다.

```text
resolutionDPI: 2147483648   Swift Int 은 64비트, ScanRequestV2 는 int  → 거부
brightnessAdjustment: 0e999 RapidJSON 토큰화가 지수를 검사한다         → 거부
```

**둘 다 거부하는 쪽이라 안전한 방향이고, 단위 테스트가 동작을 고정한다.**
근거와 대안 비교는 `windows/src/wire/parse.h` 에 적혀 있다.

여기 적어 두는 이유는 §4.2b 와 같다 — **"파리티가 통과했으니 전부 같다"고
읽으면 안 된다.** corpus 가 무엇을 담고 있는지가 그 문장의 범위다.

### 4.2b 파리티가 닿지 못하는 곳 — 셋이고, 이유가 둘이다

```text
wire/emitter   Swift 짝이 main.swift 안 private 이라 못 닿는다   → 언젠가 닿을 수 있다
wire/cli       Swift 짝이 main.swift 의 최상위 switch 다         → 같은 이유
wire/writer    Swift 짝이 **없다**. Foundation 이 대신 한다      → 원리상 못 닿는다
```

**셋 다 `main.swift` 때문이거나 Foundation 때문이다.** 우연이 아니다 —
파리티가 닿는 경계는 `SANEPluginCore` 이고, 실행 파일 타깃과 표준 라이브러리는
그 밖이다. 앞으로 `main.cpp` 쪽으로 갈수록 이 목록이 늘어난다.

`wire/writer` 는 부분 쓰기 재개 루프다. macOS 는
`FileHandle.standardOutput.write(_:)` 한 줄이고 재개는 Foundation 안에서
일어나므로, **대조할 코드가 저쪽에 존재하지 않는다.** 언젠가 닿게 만들
방법도 없다. 단위 테스트가 유일한 그물이고 그 전제로 짰다 — 부분 쓰기,
0바이트 반복, 파이프 끊김, 중간 끊김, 과다 보고.

아래는 `wire/emitter` 이야기다.

Swift 짝인 `ProtocolV2Emitter` 가 `main.swift` 안의 `private` 클래스이고,
그 파일은 최상위 코드와 서브커맨드 디스패치를 갖고 있어 파리티 바이너리에
넣을 수 없다. `WireProtocol.swift` 때 쓴 방법(파일을 컴파일 줄에 넣기)이
통하지 않는다.

**잃은 것은 크지 않다.** 그 클래스가 하는 일 넷 중 셋이 다른 경로로 대조된다.

```text
이벤트 객체 구성   wire/event 가 파리티로 대조    ✅
JSON 인코딩        wire/json 이 파리티로 대조     ✅
sequence 규율      단위 테스트만                  ⬜
줄 프레이밍        단위 테스트만                  ⬜
```

남은 둘은 규칙이 한 줄씩이라("0부터 1씩", "객체 + 0x0A 하나") 단위 테스트로
고정된다. **그래도 여기 적어 둔다** — 다음 사람이 "여기도 대조되고 있겠지"라고
가정하면 그때부터 이 모듈은 검증되지 않은 채 자란다.

`main.swift` 를 리팩터해서 emitter 를 별도 파일로 빼면 파리티가 닿는다.
그것은 **macOS 쪽 변경**이므로 I-20(양 플랫폼 동시 적용) 절차를 밟아야 한다.

### 4.3 내가 실제로 저지른 실수 — 같은 걸 반복하지 말 것

파리티가 없었으면 셋 다 "통과"로 넘어갔을 것들이다.

| 실수 | 증상 |
|---|---|
| `capitalized`를 `isalnum` 기준으로 구현 | `"a1b2"` → `"A1b2"` (Swift는 `"A1B2"`). **숫자는 단어 구분자**다 |
| `resolveMedia` 지오메트리를 `if/else-if` 사슬이 아닌 구조로 변형 | **조건 탈락과 결과 부재는 다르다.** mm 장치에서 `containsExactly` 실패 시 엉뚱하게 코너 지오메트리를 시도 |
| 테스트 기대값을 추측으로 작성 (2건) | 코드가 아니라 **테스트가 틀렸다**. Swift 출력을 먼저 보고 고쳤다 |

그리고 문서 감사에서 나온 것:

| 실수 | 교훈 |
|---|---|
| `grep -i tpu`로 센 빈도가 3배 부풀음 | `output`에 `tpu`가 들어 있다. **검증 불가능한 숫자는 적지 않는다** |
| 문서가 JSON 인코딩을 반대로 서술 | 런타임 동작 주장은 **실행해서 확인한다** |

→ [field-lessons](../10-lessons/field-lessons.md) §9b, §9b.1

`imaging/`을 붙이면서 나온 것(2026-08-05):

| 실수 | 증상 |
|---|---|
| 파리티 스크립트가 `-ffp-contract=off` 없이 컴파일 | clang은 C++에서 축약이 기본이라 `a + b*c`가 FMA가 됐다. **검증 도구가 실제 빌드보다 느슨했다.** 1 ULP 차이로 터짐 → [field-lessons](../10-lessons/field-lessons.md) §9b.2 |
| float 결과를 double 리터럴과 비교 (2건) | `static_cast<double>(0.02f) != 0.02`. **옳은 코드가 틀린 것으로 나왔다.** float끼리 비교한다 |

두 번째는 §4.3 첫 표의 "테스트 기대값을 추측으로 작성"과 **같은 실수의
다른 형태다.** 기대값을 손으로 적을 때는 타입까지 맞춰야 한다.

`wire/` 를 옮기면서 나온 것(2026-08-05):

| 실수 | 증상 |
|---|---|
| 문서 해설을 믿고 경로 정규화를 구현 | macOS 는 **정규화를 하지 않는다.** 후행 슬래시만 없앤다. `/tmp/../x`가 통과한다 → [field-lessons](../10-lessons/field-lessons.md) §9b.3 |
| 문서를 믿고 `/` 를 이스케이프하지 않음 | Swift `JSONEncoder` 는 **기본으로 이스케이프한다.** 제품 코드가 그 옵션을 끄지 않으므로 실제 wire 가 `\/` 다 → §9b.4 |

**둘 다 문서가 런타임 동작을 추측해 적은 것이었다.** 이제 파리티가 잡은
문서 오류가 셋이다(§9b, §9b.3, §9b.4). 셋 다 코드 한 줄 실행하면 30초에
확인되는 것이었다.

```text
문서에서 읽은 런타임 동작은 가설이다. 구현하기 전에 호출해서 확인한다.
"라이브러리 기본값이 X 다"가 특히 위험하다 — 그럴듯하고 아무도 확인하지 않는다.
```

`wire/parse` 를 옮기면서 나온 것(2026-08-05). **이번에는 구현 전에 잡았다.**

| 실수 | 증상 |
|---|---|
| 문서가 중복 키를 "마지막 값"이라 서술 | 실제로는 **첫 값**이다 → §9b.5 |
| 새 라이브러리의 동작을 재 보지 않을 뻔했다 | RapidJSON 1.1.0 이 `1e-324` 를 **NaN** 으로 만든다 |

둘째가 새로운 형태다. 지금까지 실측 대상은 **이식 원본(Swift)** 이었는데,
이번에 갈린 것은 **새로 붙이는 라이브러리** 쪽이었다.

```text
"검증된 라이브러리니까 표준대로 하겠지"는 §9b 와 같은 형태의 가정이다.
붙이기 전에 같은 입력을 먹여 본다.
```

그리고 도구 환경에서 하나 더 나왔다.

| 실수 | 증상 |
|---|---|
| `brew install` 이 무엇을 지우는지 보지 않았다 | 자동 정리가 `pkgconf` 를 지워 **libtiff 대조가 통째로 빠졌다** |

파리티 스크립트가 "libtiff 없음"을 stderr 로 알리고 **그대로 통과했다.**
§4.3 첫 표의 "검증 도구가 실제 빌드보다 느슨했다"와 같은 계열이다 —
이번에는 도구가 아니라 **환경**이 조용히 줄어들었다. 스크립트를 고쳐
libtiff 가 없으면 `tiff_io.cpp` 를 소스 목록에서도 빼도록 했지만,
**"건너뜀"이 통과로 보이는 구조 자체는 그대로다.** §0 이 그것을 경고한다.

밟지 않은 함정 하나도 적어둔다. `estimateIntegerOffset`의 미세보정 루프는
안쪽 범위가 **바깥 반복마다 현재 `fx`로 다시 평가된다.** 두 범위를 모두
루프 밖으로 끌어내면 결과가 달라진다 —
[exposure-merge](../04-imaging/exposure-merge.md) §6.1.1.

### 4.4 건드리면 안 되는 것

**죽은 코드 4개 — 연결하면 불변식이 깨진다**
([porting-map](../06-build/porting-map.md) §3.5):

```text
IRStrategy.cleanImage         연결하면 IR 파일 없는 결과가 성공으로 나간다
snapResolution                연결하면 I-1 위반 (요청값을 스냅한다)
writeLinearTIFF               호출자 0
saveScannerTIFF               호출자 0 (LZW 경로)
```

**이미 시도돼 실패한 "개선" 5가지**
([field-lessons](../10-lessons/field-lessons.md) §18):

```text
1. epson2 --gamma-correction 활성 검사 제거   → 스캔 전체가 실패한다
2. genesys 노출/밝기 옵션 되살리기            → 원리상 불가 (문헌 확인됨)
3. IRStrategy.cleanImage 연결
4. 노출 병합 SIMD 최적화                      → D-11이 금지
5. 장치를 매번 새로 여는 단순화               → I-8 (간헐적 스캔 실패)
```

다섯 개 전부 **코드만 보면 "정리하면 좋겠다"로 보인다.**

## 5. 구조를 이해하는 데 필요한 것

### 5.1 왜 `process/`가 둘로 나뉘어 있나

`process/` 전체가 Win32라고 생각하면 macOS에서 아무것도 검증할 수 없다.
그런데 **판정 로직은 플랫폼과 무관하다.**

```text
순수 (테스트·파리티 가능)        Win32 (실기 필요)
  progress                        child     CreateProcessW, 파이프, Job Object
  budget                          watchdog  타이머
  command_line                    cancel    콘솔 제어 이벤트
  acquisition
```

`progress`를 먼저 끝낸 이유는 **watchdog 전체가 그 위에 서 있기** 때문이다.

### 5.2 `budget`이 왜 신규 설계인가

macOS에는 이 개념이 **없고, 그게 문제다.** 호출당 180초 고정에 총합
제한이 없어서 `capabilities`가 `scanimage`를 10번 부르면 1,800초를 쓸 수
있다 — 호스트 상한 180초의 10배다.

호스트가 먼저 죽이면 **우리 오류 이벤트가 나가지 못하고** `plugin crashed`로
분류된다. 그래서 방향을 뒤집었다: 명령 총 예산 → 호출 타임아웃 역산.
→ [host-requirements](../05-protocol/host-requirements.md) §2

### 5.3 `acquisition`이 문자열 대신 구조를 쓰는 이유

macOS는 genesys 재시도를 오류 메시지에 `"첫 이미지 데이터"`가 들어
있는지로 판정한다. **그 문구를 영어로 바꾸면 재시도가 조용히 사라진다.**

`TimeoutKind`로 구조화했다. 동작은 같고 문자열 의존만 없앴다 —
timeouts-and-watchdog §3.5가 승인한 개선이다.

## 6. 문서에서 먼저 읽을 것

```text
1. windows_docs/README.md                       전체 지도
2. 10-lessons/field-lessons.md                  이미 실패한 시도들
3. 99-plan/product-invariants.md                절대 깨면 안 되는 것 20개
4. 06-build/porting-map.md                      어느 함수가 어느 모듈로
5. 05-protocol/host-requirements.md             본체가 거는 요구사항
```

**2번을 건너뛰지 말 것.** 이식 중에 "명백히 개선할 수 있는데"로 보이는
것들이 이미 시도돼 실패한 기록이다.

## 7. 답을 기다리는 것

이어받는 사람이 정할 수 없고, 물어봐야 하는 것들.

| ID | 질문 | 누구에게 |
|---|---|---|
| Q-1 | 호스트가 Authenticode 서명을 요구하는가 | negaflow 호스트 팀 |
| Q-3 | 중간 파일을 staging 안에 만들어도 되는가 | 호스트 팀 |
| Q-17 | macOS 호스트도 같은 명령별 ceiling을 쓰는가 | 호스트 팀 |
| D-20 | 설치 프로그램 도구 (WiX 사용 조건) | 사용자 |

전체: [open-questions](../99-plan/open-questions.md) (Q-1…Q-17)

## 8. 아직 없는 것 — 정직하게

- **실기 검증 장치 0대.** 어댑터는 진짜 `scanimage.exe`(MSYS2 1.4.0)를
  몰아 `detect`/`capabilities` 까지 확인했지만 **스캔은 못 해 봤다.**
  실제 스캐너에서 처음 드러날 것: 옵션 덤프의 실제 형태, 주소 변동(S-5),
  장치명 형식(S-4), 반올림 경고 문구(S-6 나머지)
- **SANE 런타임을 아직 담지 않았고, 그냥 담아서도 안 된다.** S-2 가
  실패했으므로 `_setmode` 수정을 얹어 직접 빌드한 것만 배포할 수 있다 (§3.7)
- `fixtures/` 디렉터리가 없다(M1 미착수). 파리티 하네스와 `plugin_smoke` 의
  가짜 scanimage 가 그 자리를 임시로 메운다
- 통과한 spike 5개는 **전부 macOS에서 C++와 Swift를 대조한 것**이다.
  MSVC 에서 단위 테스트는 전부 통과했지만, **imaging 파리티 자체는 macOS 에서만
  돈다** — MSVC 산출물이 Swift 와 비트 동일인지는 여전히 직접 대조되지 않았다.
  하려면 파리티 덤퍼를 MSVC 로 빌드해 그 출력을 macOS 쪽 골든과 비교해야 한다
- `imaging/merge`의 메모리는 절반만 해결됐다 — 병합 오버헤드는 5.6배 줄였지만
  입력 N장 상주가 남았다. 7200 dpi 12패스면 그것만 13.2 GB다 (§3.3)
- 취소의 **강제 종료 후 복구 절차**가 없다(§3.5). 유예 2초도 문서 권장값이지
  측정값이 아니다 — C-2/C-3 이 정해야 한다
- IR 경로는 **macOS에서도 실기 검증되지 않았다**(이 개발 환경의 genesys
  빌드가 IR을 노출하지 않는다)
- `imaging/tiff_io` 의 **읽기** 경로는 아직 경로 기반이다. 쓰기 경로는
  `process/child` 가 핸들로 검증한다 (§3.4)

**소프트웨어는 돈다. 스캐너에 닿아 본 적은 없다.** 그 둘을 같은 것으로
읽으면 안 된다.
