# negaflow-scanner-sane — Windows 어댑터

기준일: 2026-08-05
상태: **실행 파일이 돈다.** MSVC(Debug/Release)에서 빌드되고,
      detect / capabilities / scan 이 가상 `scanimage` 상대로 끝까지 통과한다.
      실기 검증 장치는 아직 0대다.
언어: C++20 / MSVC (D-13)

**이 작업을 이어받는다면 [handoff](docs/00-overview/handoff.md)를
먼저 읽는다.** 현재 상태, 다음 작업, 밟으면 안 되는 함정이 정리돼 있다.

설계 문서는 [`docs/`](docs/README.md)에 있다.
**코드를 쓰기 전에 그쪽을 읽는다.** 특히
[field-lessons](docs/10-lessons/field-lessons.md) — 이미 실패한
시도가 정리돼 있다.

## 지금 무엇이 되어 있나

```text
sane_logic (순수 로직, 의존 0) — **완성**
  util/numeric        ✅ containsExactly, saneNumber,
                         epson2AlignedHeightMM, pixelGeometry*
  sane/option_dump    ✅ scanimage -A 파서 전체
  sane/device_list    ✅ -f/-L 파싱, 백엔드·연결 판정, identity, dedupe
  sane/capabilities   ✅ parseCapabilities 전체, fixedDepth, 소스 선택
  sane/media          ✅ resolveMedia 전체 (mm/pel/코너 지오메트리, 극성, IR)
  sane/validate       ✅ validateExactOptions 전체 (거부 조건 24종)
  sane/args           ✅ makeScanimageArgs (인자 순서 계약)

process/*             ✅ 순수 + Win32 완료
  process/progress    ✅ 진행률 파싱, stderr 분류
  process/budget      ✅ D-32 명령별 예산 (신규 설계)
  process/command_line ✅ CreateProcessW 인용, 인자 주입 방어
  process/acquisition ✅ 재시도 정책 (백엔드 분기 2곳)
  process/child       ✅ CreateProcessW, 파이프 동시 drain, Job Object,
                         PROC_THREAD_ATTRIBUTE_HANDLE_LIST, 출력 파일 핸들 검증
  process/watchdog    ✅ 첫 진행률 / 유휴 상한. 진행률 누적도 여기
  process/cancel      ✅ 소유권 상태 기계 + 콘솔 제어 이벤트 + 3단계 종료
imaging_logic         ✅ 순수 부분 완료
  imaging/align       ✅ estimateIntegerOffset, boxBlur3, 신뢰 가중치,
                         mix/smoothstep, accumulateAligned
  imaging/merge       ✅ 병합 코어 전량 + 평균 경로(테스트 전용)
                         정규화 배열을 만들지 않는다 — 아래 참조
  imaging/tiff_contract ✅ 태그 → 통과/거부 판정. D-10 추가 검사 포함
imaging_tiff          🔨 libtiff 부분 완료
  imaging/tiff_io     ✅ 읽기/쓰기/크기조회/검증
  파일 계층 §3.1      ⬜ 읽기 경로의 핸들 기반 검증 (**쓰기 경로는 되어 있다** —
                         process/child 가 GetFinalPathNameByHandleW 로 확인한다)
wire_logic            ✅ 완성
  wire/request        ✅ 1단계 검증(가드 11개). 경로 정책 주입식
  wire/json           ✅ 방출. 이스케이프·수 표기·키 순서
  wire/event          ✅ 이벤트/적용옵션. 생략 vs null 경계
  wire/protocol       ✅ detect/capabilities 응답 DTO
  wire/emitter        ✅ 줄 생성(sequence·프레이밍)
  wire/writer         ✅ 부분 쓰기 루프 (Win32 짝은 wire/win_sink)
  wire/cli            ✅ 서브커맨드 디스패치 판정
  wire/win_sink       ✅ WriteFile ByteSink + stdout 바이너리 고정
wire_parse            ✅ 완성
  wire/parse          ✅ 요청 JSON 디코딩. **이 타깃만 RapidJSON 을 안다**
  wire/snapshot       ✅ capabilityToken (base64 + JSON)
app                   ✅ 조율 계층
  app/environment     ✅ scanimage 탐색(PE machine 확인), 자식 환경 블록
  app/backend         ✅ detect / capabilities / scan 순서와 재시도
  main.cpp            ✅ wire/cli 의 판정을 받아 실행만 한다
```

**`imaging_logic`은 libtiff를 링크하지 않는다.** 정렬·병합·태그 판정은
순수 산술과 순수 판정이라 libtiff 없이 서 있고, 그래서 macOS에서 Swift
원본과 직접 대조된다. libtiff를 아는 것은 `imaging_tiff` 하나뿐이다 —
`process/`가 순수/Win32로 갈린 것과 같은 이유다.

**실행 파일은 `negaflow-scanner-sane.exe` 하나다.** libtiff 와 RapidJSON 이
둘 다 있을 때만 만든다 — 없이 만들면 결과 TIFF 를 검증하지 못하거나 요청을
파싱하지 못하는 실행 파일이 나오고, 그것은 빌드가 통과했다는 신호를 주면서
제품으로는 쓸 수 없다.

## 빌드와 테스트

Windows(정식 대상). vcpkg 툴체인을 주고, **정적 CRT 트리플릿을 명시한다** —
빼면 vcpkg 기본이 동적 CRT 라 LNK2038 로 링크가 깨진다.

```bash
cmake -S windows -B build -A x64 \
  -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
  -DVCPKG_TARGET_TRIPLET=x64-windows-static
cmake --build build --config Release --parallel
ctest --test-dir build -C Release --output-on-failure
```

포트 버전은 `vcpkg.json` 의 `builtin-baseline` 이 고정한다. **아주 최신
커밋으로 고정하면 안 된다** — 그 커밋이 없는 vcpkg 체크아웃은 자동으로
fetch 하지 않고 그냥 실패한다(실측). 러너 이미지가 확실히 지나온 릴리스
태그를 쓴다.

`ctest` 는 셋을 돈다.

```text
sane_logic_tests   단위 테스트
plugin_smoke       **실행 파일을 실제로 돌린다** — 가상 scanimage 상대로
                   detect → capabilities → scan(단일/IR/다중 노출)
parity_golden      parity_dump 출력이 골든과 같은가. **WIN32 로 묶여 있지
                   않다** — macOS 에서도 돌아야 삼각형이 닫힌다(아래)
```

### parity_golden 이 무엇을 증명하는가

```text
Swift  ==  clang C++     tools/parity-check.sh (macOS 에서 실시간 대조)
clang C++ == MSVC C++    parity_golden (양쪽이 같은 골든과 대조)
──────────────────────────────────────────────
Swift  ==  MSVC C++
```

골든은 MSVC 로 만들었다. macOS 에서 `ctest` 가 통과하면 두 툴체인의 수치가
같다는 뜻이고, 그것이 `parity-check.sh` 와 합쳐져야 "MSVC 산출물이 Swift 와
같다"가 된다. **한쪽만 돌면 삼각형이 열려 있다.**

골든을 다시 만들기 전에 macOS 파리티를 먼저 돌린다 — 골든만 고치면 Swift 와의
차이가 그대로 굳는다.

macOS/Linux에서도 그대로 빌드된다. **순수 계층이 플랫폼 의존이 0이기
때문이다** — 그것이 이 계층의 계약이다(`<windows.h>`도 libtiff도 링크하지
않는다). 덕분에 Windows 장비 없이 M2 전체와 M4의 대부분을 검증할 수 있다.

### 의존성

Windows 에서는 `vcpkg.json` 이 전부 처리한다. 손으로 받을 것이 없다.

```json
tiff[zip]    imaging/tiff_io
rapidjson    wire/parse       헤더 온리, MIT
```

macOS 개발 환경에서는 직접 깐다.

```bash
brew install libtiff rapidjson pkgconf
```

**`pkgconf` 를 빠뜨리지 않는다.** `pkg-config` 가 없으면 파리티 스크립트가
libtiff 를 못 찾고 TIFF 대조를 **조용히 건너뛴 채 통과한다.**
(2026-08-05 에 `brew install` 의 자동 정리가 실제로 `pkgconf` 를 지웠다.)

둘 다 **선택 의존**이다. 없으면 해당 타깃만 빠지고 나머지는 그대로
빌드·검증된다.

```text
전부 있음              1,063 checks + plugin_smoke
libtiff 없음           imaging_tiff 만 빠진다. **실행 파일도 안 만든다**
rapidjson 없음         wire_parse 만 빠진다.   **실행 파일도 안 만든다**
```

확인하려면:

```bash
cmake -S windows -B build-notiff -DCMAKE_DISABLE_FIND_PACKAGE_TIFF=ON
```

**이 분리를 유지한다.** 순수 부분이 libtiff 나 RapidJSON 에 묶이는 순간
"의존 없이 검증된다"는 성질을 잃는다. 그래서 `wire_logic`(방출)은
`wire_parse`(디코딩)에 의존하지 않는다 — 방향이 반대다.

## 파리티 검사 — 이 저장소의 핵심 도구

C++ 구현이 Swift 원본과 **같은 입력에 같은 판정**을 내는지 확인한다.

```bash
./tools/parity-check.sh
```

저장소의 실제 `SaneOptionDump.swift`를 컴파일해 돌리고, C++ 덤퍼 출력과
diff 한다. macOS에서만 돌아간다(Swift 툴체인 필요).

현재 결과: **574줄 중 573줄 일치, 1줄은 문서화된 의도적 divergence.**

단 파리티는 **corpus 에 있는 입력만** 본다. 일부러 넣지 않은 차이 둘이
있다 — [handoff](docs/00-overview/handoff.md) §4.2a.

`@testable import SANEPluginCore` 로 **실제 구현을 링크한다.** 소스를 복사하지
않는 것이 중요하다 — 복사본을 두면 원본이 바뀌어도 파리티가 통과해버린다.

`WireProtocol.swift` 만 예외적으로 파일을 직접 컴파일 줄에 넣는다. 그것은
`SANEPluginCore` 가 아니라 실행 파일 타깃에 있어 `@testable import` 로
닿지 않기 때문이며, **넣는 것은 저장소의 실제 파일**이다.

### 그 1줄 — CRLF

Swift는 `"\r\n"`을 **한 Character**(확장 자소 클러스터)로 취급한다.
그래서 `dump.split(separator: "\n")`이 **CRLF에서 줄을 나누지 못하고**,
덤프 전체가 옵션 하나로 뭉개진다. 첫 옵션만 남고 나머지는 전부 사라진다.

```text
입력   "--mode Color|Gray [Color]\r\n--depth 8|16 [16]\r\n"
Swift  optionNames == ["mode"]        ← depth 가 없다
C++    optionNames == ["mode","depth"] ← 정상
```

**C++가 맞다.** MinGW `scanimage`가 CRLF를 낼 가능성이 있으므로 이 동작을
그대로 베끼면 Windows에서 능력 판정이 통째로 무너진다.

이것은 macOS 쪽 결함이며 I-20(양 플랫폼 동시 적용) 후보다.
→ [option-dump-parser](docs/02-frontend-contract/option-dump-parser.md) §2.2

### 파리티가 실제로 잡은 것

**① `capitalized` 의 단어 경계.** `isalnum` 기준으로 짰더니 `"a1b2"` 가
`"A1b2"` 로 나왔다. Swift 는 `"A1B2"` 다 — **숫자가 단어 구분자**이고
단어는 letter 의 연속이다.

**④ 문서가 `/` 이스케이프를 반대로 서술했다.** "Swift `JSONEncoder`는 `/`를
이스케이프하지 않는다"를 믿고 짰더니 파리티가 잡았다. 기본이 이스케이프하는
쪽이고, 제품 코드가 그 옵션을 끄지 않으므로 **실제 wire 가 `\/` 다.**

이것으로 파리티가 잡은 문서 오류가 셋이다. 셋 다 "라이브러리가 이렇게 할
것이다"였고 셋 다 코드 한 줄 실행하면 30초에 확인되는 것이었다.
**지금까지 파리티가 잡은 것 중 절반이 코드 버그가 아니라 문서 오류다.**

**③ 문서가 서술한 경로 검사가 실제와 달랐다.** macOS 의 `outputPath` 가드를
"정규화된 절대 경로"로 읽고 `..` 을 거부하도록 짰더니 파리티가 세 줄을 뱉었다.
실행해 보니 `URL(fileURLWithPath:).path` 는 **후행 슬래시만** 없앤다 —
`/tmp/a/../../../etc/passwd` 가 통과한다. **macOS 가 경로 탈출을 막지 못한다.**

Windows 정책은 이것을 베끼지 않고 처음부터 막는다. 두 정책을 모두 구현하되
POSIX 쪽은 **파리티 전용**이다 — 그래야 나머지 10개 가드를 끝까지 대조할 수
있다. 틀린 추론이 실제보다 **안전한 동작**을 서술하면 아무도 의심하지 않는다.

**②′ 파리티 스크립트 자신의 컴파일 플래그.** `imaging/align` 을 붙이자마자
1 ULP 차이로 터졌다. 원인은 이식 코드가 아니라 `parity-check.sh` 가
`-ffp-contract=off` 없이 컴파일한 것이었다 — clang 은 C++ 에서 축약이
기본이라 `a + b*c` 가 FMA 한 명령이 된다. CMakeLists 에는 있고 검증
도구에는 없었다. **느슨한 쪽이 검사를 하고 있으면 통과가 아무것도
증명하지 않는다.**

**② `resolveMedia` 의 지오메트리 분기 구조.** Swift 는 mm / pel / 코너 pel 을
`if / else if / else if` 사슬로 쓴다. 이것을 "앞 갈래가 값을 못 채웠으면
다음을 시도"로 옮기면 **동작이 달라진다** — mm 장치에서 `containsExactly` 가
실패했을 때 엉뚱하게 코너 지오메트리를 시도하게 된다. 조건 탈락과 결과 부재는
다르다.

둘 다 단위 테스트만 있었으면 내 가정을 그대로 검증했을 것이다.
실제로 지금까지 **내가 쓴 기대값이 두 번 틀렸고**(`widthPixels`, 그리고
`area.originNoLT` 에서 잘못된 덤프 상수), 두 번 다 코드가 아니라 테스트를
고쳤다.

`validate` 는 오류 **메시지 문자열까지** 바이트 단위로 일치한다. 한국어
메시지가 그대로 호스트를 거쳐 사용자에게 보이므로, 문구가 갈리면 같은 실패가
OS 마다 다르게 보인다(I-5).

## M2 게이트 — 백엔드 분기 16곳

[backend-quirks](docs/02-frontend-contract/backend-quirks.md) §0 이
이름으로 분기하는 지점 16곳을 나열한다. 그중 **순수 로직 12곳이 전부 이식됐다.**

```text
✅ supportsStableBackendSelector     genesys, epson2
✅ isDedicatedFilmBackend            coolscan*, pie*
✅ canReuseSinglePassOptionsDump     genesys
✅ capabilityDumpMode / Redump       genesys, epson2
✅ resolveMedia (색/감마)            epson2
✅ resolveMedia (높이 정렬)          epson2
✅ resolveMedia (필름 극성)          coolscan, coolscan2, coolscan3
✅ resolveMedia (톤 억제)            genesys + 16-bit
✅ fixedDepth                        epson2, pie
✅ parseCapabilities (IR 사유)       coolscan3
✅ validateExactOptions              pieusb, epson2
✅ makeScanimageArgs                 pieusb, epson2
✅ usesAutomaticAcquisitionWatchdog  pieusb
✅ attemptCount                      pieusb (재시도 금지)
✅ decideRetry                       genesys (첫 진행률 재시도)

⬜ capabilityOptionsDump             Win32 계층 (장치를 연다)
```

**순수 분기 13/13 이식 완료.** 남은 하나는 실제로 장치를 여는 코드라
Win32 계층에 속한다.

**새 분기를 추가하지 않았다.** 추가하려면 upstream 소스 또는 실기 관측이
근거로 있어야 한다(I-2).

## spike 결과 — M4 착수 조건이 열렸다

`spike-checklist` 가 **"M4 를 시작하기 전에 반드시"** 라고 못박은 N-1 을
2026-08-05 에 실행했다. macOS 만 있으면 되는 실험이다.

### N-1 — 통과 (9/9 비트 동일)

16-bit TIFF 를 `loadScannerTIFF` + `renderRGBAf` 로 읽은 결과가
`Float(v) / 65535.0` 과 **비트 패턴까지 같았다.**

```text
value       loaded         v/65535.0      bits
    0    0.000000000    0.000000000    00000000
32767    0.499992371    0.499992371    3effff00
65535    1.000000000    1.000000000    3f800000
```

즉 Core Image 로드 경로는 **감마도 색 변환도 하지 않는다.** Windows 는
이렇게 쓰면 된다:

```cpp
float toLinear(uint16_t v) { return static_cast<float>(v) / 65535.0f; }
```

`numerical-parity` §7 의 선택지(macOS 변경 / Core Image 모사 / 허용오차)
**어느 것도 발동하지 않는다.** roadmap 위험 등록의 "N-1 실패 → M4 대폭 증가"가
해소됐다.

### I-2 — 통과 (덤으로)

같은 파일로 확인했다. 헤더가 `4d4d 002a` = `MM\0*` 이므로 **big-endian 이
맞다** — §6 이 걱정한 "값이 뒤집힌 채 저장"은 일어나지 않는다.

그리고 태그 14개 전수 확인에서:

```text
ICCProfile(34675)      없음 ✓
TransferFunction(301)  없음 ✓
Photometric            RGB
SampleFormat           unsigned integer
```

[host-pipeline-contract](docs/10-lessons/host-pipeline-contract.md) §2 의
"태그 없는 16-bit linear" 계약을 **macOS 가 실제로 지키고 있다.** 그 절의
"미검증" 표기를 해제했다.

### N-3 / N-4 — 통과 (2026-08-05)

`imaging/align` 과 `imaging/merge` 를 옮긴 뒤 파리티로 대조했다.

```text
N-4  정렬 9 케이스     시프트 복원 (-3,5)→(3,-5), factor 2 포함
                       조기 종료 경로(동일/평탄/좁은 이미지) 포함
N-3  병합 6 케이스     float 비트 패턴과 UInt16 을 **둘 다** 비교
                       신뢰 가중치 5분기를 전부 지나는 합성 입력
```

**둘 다 비교하는 이유**: 양자화가 절삭이라 1 ULP 차이는 대개 같은
`UInt16` 으로 떨어진다. UInt16 만 보면 놓친다.

합성 입력은 두 언어에서 **비트 단위로 같아야** 하므로 부동소수점 난수
대신 32비트 정수 해시로 만든다. unsigned 모듈러 연산은 Swift `&*`/`&+` 와
C++ 가 동일하게 정의돼 있다.

Swift 쪽 병합 진입점이 `[CIImage]` 를 받아서, 합성 float 를 CIImage 로
감싸 넣는다. 그 왕복이 **비트 단위 항등**임을 먼저 실측했다 — Y 뒤집힘
없음, 1 초과·음수 값도 보존. `normalizeExposure` 가 값을 1 이상으로 밀어
올리므로 이것이 성립하지 않으면 비교가 무의미했다.

### 파리티가 닿지 못하는 곳 — 셋이고, 이유가 둘이다

```text
wire/emitter   Swift 짝이 main.swift 안 private 이라 못 닿는다   → 언젠가 닿을 수 있다
wire/cli       Swift 짝이 main.swift 의 최상위 switch 다         → 같은 이유
wire/writer    Swift 짝이 **없다**. Foundation 이 대신 한다      → 원리상 못 닿는다
```

`wire/writer` 는 부분 쓰기 재개 루프다. macOS 는
`FileHandle.standardOutput.write(_:)` 한 줄이고 재개는 Foundation 안에서
일어나므로 **대조할 코드가 저쪽에 존재하지 않는다.** 단위 테스트가 유일한
그물이라 그 전제로 짰다 — 1바이트씩만 받는 파이프, 중간 끊김, 과다 보고까지.

아래는 `wire/emitter` 이야기다.

**`wire/emitter` 만 예외였다.**
Swift 짝(`ProtocolV2Emitter`)이 `main.swift` 안의 `private` 클래스이고,
그 파일은 최상위 코드를 갖고 있어 파리티 바이너리에 넣을 수 없다.

그 클래스가 하는 일 넷 중 셋은 다른 경로로 대조된다 — 이벤트 구성은
`wire/event`, JSON 인코딩은 `wire/json` 이다. 남은 것은 `sequence` 규율과
줄 프레이밍 둘이고, 규칙이 한 줄씩이라 단위 테스트로 고정했다.

**그래도 적어 둔다.** "여기도 대조되고 있겠지"라고 가정하면 그때부터
이 모듈은 검증되지 않은 채 자란다.
→ [handoff](docs/00-overview/handoff.md) §4.2b

### 병합 메모리 — 오버헤드 5.6배 감소 (2026-08-05)

정규화는 스칼라 곱 하나다. 배열로 들고 있을 이유가 없어서 없앴다.

```text
NormalizedView { raw, scale }  →  raw[i] * scale   (알파는 1)
```

`normalizeExposure` 도 `out[i] *= scale` 을 한 번 할 뿐이므로 **반올림까지
같다.** 그 항등식을 단위 테스트가 고정한다 — 식이 갈리면 메모리는 줄고
결과가 조용히 달라진다.

정렬만은 정규화된 전체 배열을 요구하므로(`fullResLumaError` 가 풀해상도
임의 접근을 한다) 거기서만 **기준 1장 + 표본 1장**을 만든다.
16비트 양자화도 중간 float 비트맵을 거치지 않는다.

실측 (12 패스 700×500, 같은 출력 체크값):

```text
옛 구조   입력 64 MB → 피크 143 MB    오버헤드 79 MB
현재      입력 64 MB → 피크  78 MB    오버헤드 14 MB
```

파리티 6 케이스가 전부 그대로 통과했다. **비트 동일이 유지된다.**

다시 재볼 수 있다. 두 실행의 **체크값이 같아야 한다** — 다르면 메모리를
줄이면서 결과를 바꾼 것이다.

```bash
c++ -std=c++20 -O2 -ffp-contract=off -Isrc -o /tmp/bench tools/merge-memory-bench.cpp src/imaging/merge.cpp src/imaging/align.cpp src/util/numeric.cpp
```

남은 것은 호출자가 넘기는 입력 N장이다. 없애려면 TIFF 스트리밍이 필요하고
그것은 M5 조율 계층과 함께 설계해야 한다 —
[exposure-merge](docs/04-imaging/exposure-merge.md) §7.2.2.

### N-2 — 양방향 상호운용 (2026-08-05)

`imaging/tiff_io` 를 붙이면서 macOS ImageIO 와의 상호운용을 대조했다.

```text
libtiff 로 쓴 파일   → macOS ImageIO 로 읽기   픽셀 비트 동일
ImageIO 로 쓴 파일   → libtiff 로 읽기         픽셀 비트 동일
```

**파일 바이트는 다르다.** libtiff 는 `II`(little-endian) 314 B, ImageIO 는
`MM`(big-endian) 338 B 를 낸다. 그래도 디코드된 픽셀이 같으면 통과다 —
호스트가 libtiff/WIC 로 읽으므로 바이트 순서는 투명하다.

처음에는 **모든 행이 같은 값**인 픽스처를 썼다. 그러면 위아래 뒤집힘도
행 stride 오류도 통과시킨다는 것을 깨닫고 행마다 패턴을 밀었다.
지금은 행 순서까지 검증된다.

그리고 매번 우리 산출물의 태그를 확인한다:

```text
bps=16 spp=3 photo=RGB planar=CONTIG pages=1
ICCProfile(34675)      없음
TransferFunction(301)  없음
```

**프로파일이 박히면 본체가 감마 도메인으로 읽어 색이 무너진다.** 스캔은
성공하고 검증도 통과하므로 가장 늦게 발견되는 실패다. 그래서 파리티가
지킨다.

## process/ 는 왜 둘로 나뉘어 있나

`process/` 전체가 Win32 라고 생각하기 쉽지만 **판정 로직은 그렇지 않다.**

```text
process_logic (macOS 에서 테스트·파리티 가능)
    progress      진행률 레코드 개수, 마지막 값, stderr 분류
    budget        명령별 예산 산술 (시간을 주입받는다)
    command_line  따옴표 규칙, 장치명 안전성
    acquisition   재시도 판정

process_win32
    child         CreateProcessW, 파이프 drain, Job Object
    watchdog      타이머 + 진행률 누적. **Win32 를 포함하지 않는다**
    cancel        소유권 상태 기계 + 콘솔 제어 이벤트
```

순수 쪽을 먼저 끝내면 **watchdog 전체가 서 있는 바닥**이 골든으로 검증된다.
`progress` 는 Swift 짝이 있어 파리티 대상이고, `budget`/`command_line` 은
Windows 전용이라 단위 테스트만 있다.

`watchdog` 이 `process_win32` 에 있는 것은 편의다 — `child` 와 함께 쓰이고
따로 두면 타깃만 늘어난다. 타이머는 `std::condition_variable` 의 시한
대기이고 죽이는 행위는 콜백으로 밀어냈으므로, **판정은 실기 없이
단위 테스트로 고정된다**(`testWatchdogClassifiesTimeouts`).

### 취소가 3단계인 이유

Windows 에는 `SIGTERM` 을 남에게 보낼 방법이 없다. `TerminateProcess` 는
`sane_cancel()` 을 부르지 않으므로 스캐너가 전송 중간 상태로 남는다.

```text
1. CTRL_BREAK_EVENT      자기 프로세스 그룹으로 띄운 자식에게만 간다
2. 유예 2초               sane_cancel() 이 현재 전송 블록을 끝낼 시간
3. Job 전체 종료          손자까지 남기지 않는다
```

1번은 **콘솔이 있을 때만** 쓸 수 있다. GUI 호스트의 자식으로 뜨면 콘솔이
없고, 그때는 `CREATE_NO_WINDOW` 로 검은 창을 막는 대신 취소가 강제 종료
경로가 된다. 그 경우의 안전망이 Job Object 다 — 어댑터가 죽어도
`scanimage` 가 남지 않는다.

### acquisition 이 문자열 대신 구조를 쓰는 이유

macOS 는 genesys 재시도를 오류 메시지에 `"첫 이미지 데이터"` 가 들어 있는지로
판정한다. **그 문구를 영어로 바꾸면 재시도가 조용히 사라진다.**

여기서는 `TimeoutKind` 를 결과에 실어 종류로 판정한다. 동작은 같고 문자열
의존만 없앴다 — timeouts-and-watchdog §3.5 가 승인한 개선이다.

### budget 이 왜 새 설계인가

macOS 에는 이 개념이 **없다.** 호출당 180 s 고정이고 총합 제한이 없어서,
`capabilities` 가 `scanimage` 를 10회 부르면 1,800 s 를 쓸 수 있다 —
호스트 상한 180 s 의 10배다. 호스트가 먼저 죽이면 우리 오류 이벤트가
나가지 못하고 `plugin crashed` 로 분류된다.

그래서 방향을 뒤집었다: **명령 총 예산 → 호출 타임아웃 역산.**
테스트 `testBudgetCapabilitiesMultiCall` 이 "호출을 몇 번 하든 총합이
예산을 넘지 않는다"를 고정한다.

`Scan` 만 총 예산이 없다(I-7). 진행률 watchdog 이 대신 보고, 호스트의
7,200 s 가 최종 안전망이다.

## 이 계층에서 지키는 것

```text
sane_logic 은 <windows.h> 도 <tiffio.h> 도 포함하지 않는다
누적 합에 SIMD 를 넣지 않는다 (D-11)
/fp:fast 를 쓰지 않는다
가장 가까운 값으로 스냅하지 않는다 (I-1)
```

마지막 항목이 이 프로젝트의 성격이다. `containsExactly`가 그 바닥이고,
`snapResolution` 같은 함수는 **일부러 옮기지 않았다**
([porting-map](docs/06-build/porting-map.md) §3.5의 죽은 코드 4개).

## 레이아웃

```text
windows/
    CMakeLists.txt
    vcpkg.json          tiff[zip] + rapidjson
    .clangd             편집기용 include 경로
    src/
        main.cpp               서브커맨드 실행. 판정은 wire/cli 가 한다
        app/environment.*      scanimage 탐색, 자식 환경 블록, 경로 규칙
        app/backend.*          detect / capabilities / scan 의 순서와 재시도
        app/long_path.manifest 260자 초과 staging 대응
        util/numeric.*
        sane/option_dump.*
        sane/device_list.*
        sane/capabilities.*
        sane/media.*
        sane/validate.*
        sane/args.*
        process/progress.*
        process/budget.*
        process/command_line.*
        process/acquisition.*
        process/child.*        ← <windows.h> 를 아는 파일
        process/watchdog.*
        process/cancel.*       ← <windows.h> 를 아는 파일
        imaging/align.*
        imaging/merge.*
        imaging/tiff_contract.*
        imaging/tiff_io.*      ← libtiff 를 아는 유일한 파일
        wire/request.*
        wire/json.*
        wire/event.*
        wire/protocol.*
        wire/emitter.*
        wire/writer.*
        wire/cli.*
        wire/parse.*           ← RapidJSON 을 아는 파일
        wire/snapshot.*        ← RapidJSON 을 아는 파일
        wire/win_sink.*        ← <windows.h> 를 아는 파일
    tests/
        test_main.cpp          단위 테스트 (1,063 checks)
        parity_dump.cpp        Swift 대조용 덤퍼
        golden/parity_dump.txt MSVC 로 만든 골든 (560줄)
        parity-golden.cmake    골든 대조. 툴체인이 갈리면 여기서 잡힌다
        virtual_scanimage.cpp  가짜 scanimage. **우리 코드를 링크하지 않는다**
        plugin-smoke.cmake     실행 파일을 실제로 돌리는 ctest 시나리오
    tools/
        parity-check.sh
        parity_reference.swift
        merge-memory-bench.cpp   병합 피크 메모리 측정(테스트 아님)
```

`installer/`와 `scripts/`는 M7에서 만든다.
