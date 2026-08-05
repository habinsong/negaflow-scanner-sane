# 인수인계 — 여기까지 왔고, 다음은 이것이다

기준일: 2026-08-05 (10차 갱신 — wire 순수 부분 완료 + MSVC 조사 반영)
기준 커밋: c554aaf (`windows/`, `windows_docs/` 는 아직 **커밋되지 않음**)
상태: 사실 기록 — 이어받는 사람이 가장 먼저 읽는 문서
목적: 다른 사람이 이 작업을 중단 없이 이어가게 한다

## 0. 5분 안에 상태 확인하기

```bash
python3 windows_docs/check-docs.py          # 문서 정합성
./windows/tools/parity-check.sh             # C++ ↔ Swift 동등성
cmake -S windows -B build && cmake --build build && ctest --test-dir build
./build/sane_logic_tests                    # 체크 수를 보려면 직접 돌린다
```

셋 다 개발 도구를 요구한다. **없으면 그 블록을 조용히 건너뛴다** — 그러면
검증이 줄어든 채로 통과한다. 스크립트가 무엇을 감지했는지 stderr 를 읽는다.

```bash
brew install libtiff rapidjson pkgconf
```

`pkgconf` 가 빠지면 `pkg-config` 가 사라져 libtiff 대조가 통째로 빠진다.
(2026-08-05 에 `brew install` 의 자동 정리가 실제로 그것을 지웠다.)

셋 다 통과하면 이 문서가 기술한 상태 그대로다. **하나라도 실패하면
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

process_logic (순수 부분만)                 🔨 4/7
    process/progress      진행률 파싱, stderr 분류
    process/budget        D-32 명령별 예산 (신규 설계)
    process/command_line  CreateProcessW 인용, 인자 주입 방어
    process/acquisition   재시도 정책
    ⬜ child / watchdog / cancel            ← Win32. macOS에서 컴파일 불가

imaging_logic (순수 로직, 의존 0)           ✅ 완성
    imaging/align         estimateIntegerOffset, boxBlur3, 신뢰 가중치,
                          mix/smoothstep, accumulateAligned
    imaging/merge         병합 코어 전량 + 평균 경로(테스트 전용)
    imaging/tiff_contract 태그 → 통과/거부 판정. D-10 추가 검사 포함

imaging_tiff (libtiff)                      ✅ 순수 부분 외 완성
    imaging/tiff_io       읽기/쓰기/크기조회/검증. **libtiff 를 아는 유일한 타깃**
    ⬜ 파일 계층 §3.4     핸들 기반 검증, reparse point 거부 (Win32)

wire_logic (순수 로직)                      🔨 8/10
    wire/request          ✅ 1단계 검증. 가드 11개, 경로 정책 주입식
    wire/json             ✅ 방출. 이스케이프·수 표기·키 순서
    wire/event            ✅ 이벤트/적용옵션. 생략 vs null 경계
    wire/protocol         ✅ detect/capabilities 응답 DTO 인코딩
    wire/emitter          ✅ sequence 규율 + 줄 프레이밍 (**파리티 없음**)
    wire/writer           ✅ 부분 쓰기 루프 (**파리티 원리상 불가**)
    wire/cli              ✅ 서브커맨드 디스패치 판정 (**파리티 없음**)
    ⬜ main.cpp / 응답 조립(비순수) / WriteFile 어댑터(Win32)

wire_parse (RapidJSON)                      ✅ 완성
    wire/parse            요청 디코딩. **RapidJSON 을 아는 유일한 타깃**
                          토큰화만 쓰고 수 변환은 std::from_chars 로 직접 한다
```

**실행 파일은 아직 없다.** 정적 라이브러리 다섯과 테스트뿐이다.

### 검증 상태

| 항목 | 상태 |
|---|---|
| 단위 테스트 | 965 checks 통과 |
| 파리티 (C++ ↔ Swift) | 574줄 중 573줄 일치 (1건은 문서화된 CRLF) |
| 문서 정합성 | 44개 통과 |
| 백엔드 분기 (순수) | **13/13 이식 완료** |
| spike | **5개 통과** (N-1, N-2, N-3, N-4, I-2) |

**§0의 세 명령이 이 표를 재생성한다.** 숫자가 다르면 표가 낡았거나
누군가 코드를 고쳤다는 뜻이다.

### 닫힌 결정

- D-32 신설 (명령별 타임아웃 예산) — `process/budget`에 구현됨
- Q-18 종결 (`serialNumber` 부재가 ID 불안정 신호 — wire 변경 불필요)
- 본체 요구사항 26개 중 25개 충족 확인
  ([host-requirements](../05-protocol/host-requirements.md))

## 3. 다음에 할 일

**macOS 에서 검증할 수 있는 것은 다 했다.** 남은 것은 **전부** Windows 환경이나
M5 조율 계층을 요구한다.

```text
A. 병합 입력 스트리밍       M5 조율 계층과 함께 설계해야 한다   §3.3
B. imaging/tiff 파일 계층   Win32 필요                        §3.4
C. process/ 의 Win32 3개    Win32 필요                        §3.5
D. wire/ 의 나머지 3개      Win32 + 프로세스 실행 필요         §3.6
```

### 3.0 가장 먼저 — **Windows 에서 한 번 빌드한다**

**장비는 없어도 된다.** `.github/workflows/windows.yml` 을 넣어 두었다.
`windows/` 를 커밋하면 GitHub Actions 의 `windows-latest` 에서 MSVC 빌드와
ctest 가 Debug/Release 양쪽으로 돈다(`paths:` 필터가 있어 커밋 전에는 안 돈다).

Debug 를 같이 도는 이유가 있다. `_ITERATOR_DEBUG_LEVEL` 불일치는 Debug 에서만
드러나고, `CMAKE_MSVC_RUNTIME_LIBRARY` 의 제네레이터 식이 정확히 그 경우를
다룬다 — 안 돌리면 그 식이 검증되지 않는다.

순서:

```text
1. 설정이 통과하는가        vcpkg 매니페스트가 tiff/rapidjson 을 끌어온다
2. 단위 테스트가 다 통과하는가   여기가 첫 관문이다
3. imaging 파리티 수치       갈리면 D-11 과 §3.1 의 fp_contract 를 다시 본다
4. §3.2 의 열린 항목 셋을 닫는다
5. C(process Win32) → B(tiff 파일 계층) → D(WriteFile 어댑터·응답 조립·main)
```

**2번이 갈리면 그 뒤가 전부 흔들린다.** 특히 아래 둘을 먼저 본다.

```text
testFromCharsOutOfRangeContract   **우리 코드가 아니라 툴체인을 잰다**
                                  빨간불이면 파서 버그가 아니라 stdlib 이 다른 것이다
imaging/merge 파리티 6 케이스      1 ULP 차이면 FMA 축약을 의심한다
```

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

### 3.2 아직 **열려 있는** 것 셋

**① RapidJSON 버전이 개발 환경과 Windows 에서 다르다.**

```text
macOS 개발   Homebrew 1.1.0       (2016-08-25. 유일한 태그다)
Windows      vcpkg master 스냅샷   (version-date 2025-02-26)
```

`wire/parse` 의 실측은 전부 1.1.0 에서 했다. 우리가 쓰는 것이 토큰화뿐이라
표면은 작지만, **`0e999` 거부가 바로 그 토큰화의 지수 검사에서 나왔다.**
Windows 빌드가 서면 `testParseZeroMantissaHugeExponentDivergence` 부터 본다.

방향은 유리하다. master 는 1.1.0 이 MSVC `/W4 /WX` + C++20 에서 내는 경고
넷(C4996/STL4015, C5054, C5232, C4127)을 전부 고쳐 뒀다. 그리고 `wire/parse`
는 그 넷이 사는 `document.h` / `schema.h` / `pointer.h` 를 **애초에 끌어오지
않는다**(`c++ -H` 로 전이 포함까지 확인). SAX 만 쓴 것이 수 변환 때문이었는데
경고 표면까지 같이 비껴갔다.

**② `vcpkg.json` 에 `builtin-baseline` 이 없다.**

포트 버전이 러너 이미지에 따라 떠다닌다. ①을 걱정하면서 버전을 고정하지 않는
것은 앞뒤가 안 맞는다. **여기서 SHA 를 지어내지 않았다** — 실제 vcpkg 커밋을
골라야 하고, 틀린 SHA 는 빌드를 깬다.

**③ `/sdl` 이 주입하는 `/we4996` 이 `/external:W0` 을 뚫을 수 있다.**

`/we` 는 경고 레벨과 무관하므로 외부 헤더에서도 오류가 될 수 있다. 문서로는
확인되지 않았고 **첫 Windows 빌드에서 판명된다.** 터지면 CMakeLists 의
`wire_parse` 블록에 준비해 둔 `/wd4996` 한 줄을 켜고 **이유를 그 자리에 적는다.**

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

### 3.5 C — `process/` 의 Win32 3개

```text
process/child      CreateProcessW, 익명 파이프, Job Object
process/watchdog   타이머. **process/progress 위에 서 있다**(이미 이식됨)
process/cancel     콘솔 제어 이벤트
```

순수 부분 넷(`progress`·`budget`·`command_line`·`acquisition`)은 이미 있다.
남은 셋은 전부 시스템 호출이라 macOS 에서 컴파일조차 되지 않는다.
`SANEBackend+Process.swift`(489행)는 **이식하지 않고 다시 쓴다** —
Foundation `Process`/`Pipe`/`DispatchSource`/POSIX 신호에 완전히 묶여 있다.
→ [porting-map](../06-build/porting-map.md) §2.3

**stderr drain 에서 교착이 나기 쉽다.** 전용 스레드나 겹친 I/O 가 필요하다.

### 3.6 D — `wire/` 의 나머지 3개

wire 계층은 순수한 부분을 전부 옮겼다. 무엇이 언제 갔는지는 이 파일의 §2
표가 소유한다. 남은 것만 적는다.

```text
WriteFile 어댑터  _setmode(_O_BINARY) + WriteFile. **ByteSink 구현 하나**다 —
                  부분 쓰기 재개 루프는 wire/writer 에 이미 있고 테스트도 있다
응답 조립         장치 열거 → DTO. **프로세스 실행이 필요하다**(비순수).
                  DTO 인코딩 자체는 wire/protocol 이 이미 파리티로 대조한다
main.cpp          wire/cli 의 판정을 받아 실행만 한다. 위 둘이 있어야 의미가 있다
```

**결정이 하나 걸려 있다.** 알 수 없는 서브커맨드의 exit 코드가 macOS 는 0 이고
[wire-contract](../05-protocol/wire-contract.md) §6 은 2 를 권한다. 사용자에게
보이는 동작 변경이라 D 번호가 필요하다. 그래서 `wire/cli` 가 **정책을
주입받고 기본값은 macOS 쪽**이다 — 결정이 나면 호출부에서 한 줄 바꾼다.
(`wire/request` 의 `PathPolicy`, `wire/parse` 의 `ParseLimits` 와 같은 방식이다.)

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

- Windows에서 **한 번도 빌드해본 적이 없다.** 다만 MSVC 플래그는 이제
  문서 기반 추정이 아니다 — 2026-08-05 조사로 `/fp:precise` 만으로는 FMA
  축약이 안 꺼진다는 것이 확인돼 `#pragma fp_contract(off)` 를 강제 포함으로
  넣었다(§4.3, [field-lessons](../10-lessons/field-lessons.md) §9b.6)
- 실행 파일이 없다. `main.cpp`도 없다
- `fixtures/` 디렉터리가 없다(M1 미착수). 파리티 하네스가 그 자리를 임시로 메운다
- spike 대부분이 미실행. **차단 항목 S-1/S-2/D-1은 장비와 협의가 필요하다**
- 통과한 spike 5개는 **전부 macOS에서 C++와 Swift를 대조한 것**이다.
  MSVC 가 같은 수치를 내는지는 **실제로 컴파일해 보기 전까지 미확인**이다
  (플래그 자체는 §3.1 에서 확인해 고쳤지만, 그것과 결과가 같다는 것은 다른 말이다)
- `imaging/merge`의 메모리는 절반만 해결됐다 — 병합 오버헤드는 5.6배 줄였지만
  입력 N장 상주가 남았다. 7200 dpi 12패스면 그것만 13.2 GB다 (§3.3)
- 실기 검증 장치 0대
- IR 경로는 **macOS에서도 실기 검증되지 않았다**(이 개발 환경의 genesys
  빌드가 IR을 노출하지 않는다)

**이 문서들과 코드는 계획과 기반이지 완성품이 아니다.**
