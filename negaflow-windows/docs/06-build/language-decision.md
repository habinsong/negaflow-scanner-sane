# 구현 언어 결정

기준일: 2026-08-04
상태: 결정
대상: `negaflow-scanner-sane.exe` (어댑터 실행 파일)

관련 문서:

- [toolchain-and-layout](toolchain-and-layout.md)
- [numerical-parity](../04-imaging/numerical-parity.md)
- [child-process](../03-process-and-io/child-process.md)
- [packaging-and-install](../07-distribution/packaging-and-install.md)

## 1. 무엇을 정하는가

이 플러그인은 단일 CLI 실행 파일이다. 하는 일:

```text
JSON 파싱/직렬화       (경량)
텍스트 파싱            (정규식, 문자열)
자식 프로세스 관리     (Win32)
파이프 I/O             (Win32)
TIFF 읽기/쓰기         (libtiff)
부동소수점 픽셀 연산   (수백 MB ~ 수 GB)
```

**GUI 없음. 네트워크 없음. 데이터베이스 없음. 백그라운드 서비스 없음.**

## 2. 후보

| 언어 | 런타임 | 배포 크기 | 시작 시간 | FP 제어 | Win32 접근 |
|---|---|---|---|---|---|
| C++20 | 없음 | 작음 | 즉시 | 완전 | 직접 |
| Rust | 없음 | 작음 | 즉시 | 완전 | `windows-rs` |
| C# / .NET 10 | AOT 또는 런타임 | AOT 중간 | AOT 즉시 | 제한적 | P/Invoke |
| Swift on Windows | Swift 런타임 | 큼 | 보통 | 완전 | 직접 |

## 3. Swift on Windows를 먼저 검토한다

**가장 매력적으로 보인다.** 기존 코드를 거의 그대로 옮길 수 있기 때문이다.

### 3.1 가능한 부분

- `Foundation`의 `String`, `Data`, `JSONEncoder`/`JSONDecoder`,
  `NSRegularExpression`은 swift-corelibs-foundation에 있다.
- 순수 로직(파싱, 검증, 산술)은 수정 없이 컴파일될 가능성이 높다.
- `Package.swift`가 그대로 쓰인다.

### 3.2 불가능하거나 위험한 부분

| 항목 | 문제 |
|---|---|
| `CoreImage`, `CoreGraphics`, `ImageIO` | **없다.** 4장 전체를 새로 써야 한다 |
| `Foundation.Process` | corelibs에 있지만 Windows 구현의 성숙도와 Job Object 미지원 |
| `DispatchSource.makeSignalSource` | Windows에 신호가 없다 |
| `FileHandle.readabilityHandler` | corelibs Windows 지원 불확실 |
| `NSLock` | 있다 |
| 배포 | Swift 런타임 DLL을 함께 배포해야 한다. 재배포 조건과 크기 확인 필요 |
| 툴체인 | Windows Swift 툴체인의 안정성과 CI 지원 |
| 코드 서명 | Swift 런타임 DLL의 서명 상태 |

`Process`와 `Job Object`가 결정적이다. 3장 전체가 Win32 직접 호출을
요구하는데, Swift에서 Win32를 부르는 것은 가능하지만
(`import WinSDK`) 그 순간 "기존 코드를 그대로 쓴다"는 이점이
크게 줄어든다.

### 3.3 결론

```text
Swift on Windows를 채택하지 않는다.
```

이유:

1. 이식해야 할 코드의 **가장 어려운 두 부분(3장 프로세스, 4장 이미징)이
   어차피 전면 재작성**이다. 언어를 유지해도 이득이 없다.
2. 남는 것(파싱·검증)은 순수 로직이라 어느 언어로든 옮기기 쉽다.
3. Swift 런타임 재배포가 배포·서명·크기·지원 부담을 추가한다.
4. negaflow 본체 Windows판이 C#/C++ 조합을 택했다. 도구 체인을
   맞추는 편이 유지에 유리하다.

## 4. C# / .NET 10 Native AOT

### 4.1 장점

- negaflow 본체 shell이 C# / WinUI 3다. 팀 역량이 공유된다.
- JSON, 정규식, 문자열 처리가 표준 라이브러리로 충분하다.
- `System.Text.Json`이 빠르고 로케일 독립이다.
- Native AOT로 런타임 없는 단일 exe를 만들 수 있다.
- P/Invoke로 Win32 전체에 접근 가능하다.
- 메모리 안전.

### 4.2 단점

- **부동소수점 제어가 약하다.** `Math.Round`의 기본이 banker's rounding이고,
  JIT의 FP 최적화를 완전히 제어할 수 없다. AOT는 상황이 낫지만
  `-ffp-contract=off` 같은 직접적 제어가 없다.
- 대용량 float 배열 처리에서 GC 압력. `ArrayPool`과 `Span`으로 완화할 수
  있지만 신경 써야 한다.
- libtiff 사용에 P/Invoke 래퍼가 필요하다(`LibTiff.Net`은 관리 포팅이라
  성능과 동등성이 다를 수 있다).
- Native AOT 산출물 크기가 C++보다 크다(수 MB).

### 4.3 FP 문제의 실제 무게

[numerical-parity](../04-imaging/numerical-parity.md)가 **비트 동일**을
요구한다. C#에서 이것을 달성할 수 있는가?

- `float`/`double` 연산 자체는 IEEE 754를 따른다. 명시적으로 쓴 순서대로
  계산된다.
- .NET은 x86 32-bit의 x87 80-bit 중간 정밀도 문제를 오래전에 해결했다.
  x64/ARM64는 SSE/NEON을 쓰므로 문제없다.
- **FMA 축약**: JIT/AOT가 `a*b+c`를 FMA로 바꾸는가? .NET은 이것을
  자동으로 하지 않는다(명시적 `Math.FusedMultiplyAdd`가 별도로 있다).
  즉 **안전하다.**
- `Math.Round`는 명시적으로 `MidpointRounding.AwayFromZero`를 쓰면 된다.

**결론: C#으로도 비트 동일이 달성 가능하다.** 단 주의 항목을
코딩 규칙으로 강제해야 한다.

## 5. C++20

### 5.1 장점

- FP 제어가 완전하다(`/fp:precise`, `-ffp-contract=off`).
- libtiff를 직접 링크한다.
- Win32를 직접 호출한다. 래퍼 계층이 없다.
- 산출물이 작고 시작이 즉시다.
- SANE 런타임과 같은 계층(C/C++)이라 디버깅이 일관된다.

### 5.2 단점

- 메모리 안전이 언어로 보장되지 않는다. 이 프로그램은
  **신뢰할 수 없는 입력을 파싱한다**(JSON, base64 토큰, `scanimage` 출력).
- JSON 라이브러리를 골라야 한다(nlohmann/json, RapidJSON, simdjson).
- 정규식이 약하다. `std::regex`는 느리고 구현마다 다르다. PCRE2나
  RE2를 쓰면 의존이 하나 더 는다.
- 문자열 처리가 번거롭다(UTF-8 ↔ UTF-16).

### 5.3 메모리 안전 위험의 실제 무게

공격 표면:

```text
호스트가 준 JSON        — 호스트를 신뢰한다면 낮음
capabilityToken         — 호스트를 거쳐 오지만 원래 우리가 만든 것.
                          변조 가능성 있음
scanimage stdout/stderr — 우리가 설치한 프로그램. 낮음
TIFF 파일               — scanimage가 만든 것. libtiff로 파싱
```

**가장 위험한 것은 TIFF와 base64 토큰이다.** 둘 다 라이브러리가
처리하므로 우리 코드의 위험은 상대적으로 낮다.

그러나 3,000행의 문자열 파싱 코드를 C++로 쓰면 버퍼 오버런과
반복자 무효화 기회가 실제로 생긴다.

## 6. Rust

FP 제어가 완전하고 메모리 안전하며 산출물이 작다.
`windows-rs`로 Win32에 접근하고, `tiff` crate 또는 libtiff 바인딩을 쓴다.

**기술적으로 가장 좋은 선택일 수 있다.** 그러나:

- negaflow 본체 팀에 Rust 역량이 있는지 불명확하다.
- 본체가 C#/C++이므로 세 번째 언어가 추가된다.
- 빌드·서명·CI 파이프라인을 별도로 만들어야 한다.

**기술적 이점이 조직적 비용을 넘지 못한다면 채택하지 않는다.**
이 판단은 이 문서가 할 수 없다.

## 7. 결정

```text
D-13  1차 구현 언어는 C++20으로 한다.
      단 다음 조건을 코딩 규칙으로 강제한다.

      - 신뢰할 수 없는 입력 파싱에 raw 포인터 산술을 쓰지 않는다
      - 문자열은 std::string_view / std::string, 인덱싱은 .at() 또는
        명시적 범위 검사
      - JSON은 RapidJSON 반복 파서, 상한 설정
      - 정규식은 미리 컴파일, 입력 크기 제한
      - 모든 Win32 핸들은 RAII 래퍼
      - AddressSanitizer / UBSan 빌드를 CI에 포함
      - 퍼징 대상: JSON 디코더, 옵션 덤프 파서, base64 디코더
```

### 7.1 근거

1. **부동소수점 동등성이 최우선 제약**이고, C++가 가장 직접적인 제어를 준다.
2. libtiff를 직접 쓴다. 관리 래퍼의 동작 차이를 걱정하지 않는다.
3. Win32 호출이 코드의 상당 부분이다. P/Invoke 서명 30개를 쓰는 것보다
   직접 부르는 것이 낫다.
4. SANE 런타임과 같은 계층이라 크래시 덤프와 디버깅이 일관된다.
5. 배포물이 작고 런타임 의존이 적다(MSVC 재배포 가능 런타임 또는 정적 링크).

### 7.2 C#을 택했어야 할 조건

다음 중 하나라도 참이면 D-13을 재검토한다.

- 팀에 C++ 유지 역량이 없다
- parity spike N-1이 실패해 비트 동일을 포기하게 된다(그러면 FP 제어의
  가치가 크게 줄어든다)
- 보안 검토에서 C++ 메모리 안전 위험이 수용 불가로 판정된다

### 7.3 하이브리드를 택하지 않는 이유

"파싱은 C#, 이미징은 C++" 같은 분리는 이 크기의 프로그램에서
비용만 늘린다. 총 코드가 5,000행 미만이다.

## 8. 라이브러리 결정

| 용도 | 선택 | 근거 |
|---|---|---|
| JSON | RapidJSON | 반복 파서(스택 오버플로 방지), 상한 설정 가능, 헤더 온리, MIT |
| TIFF | libtiff | 이미 SANE 의존. 태그 수준 제어 |
| 정규식 | `std::regex` 또는 수동 파서 | §8.1 |
| base64 | 직접 구현 또는 소형 라이브러리 | 엄격한 검증이 필요하므로 직접이 낫다 |
| UUID | 직접 검증(정규식) | 파싱하지 않고 반사만 하므로 |
| 로깅 | 직접 | stderr에 줄 단위 출력이 전부 |

### 8.1 정규식

쓰이는 곳은 여섯 개뿐이다.

```text
device `([^']+)' is a (.+)$                         -L 파싱
(-?\d+(?:\.\d+)?)\.\.(-?\d+(?:\.\d+)?)              범위
steps? of (-?\d+(?:\.\d+)?)                          step
-?\d+(?:\.\d+)?\.\.-?\d+(?:\.\d+)?\s*(mm|pel)        단위
(?i)progress\s*:?\s*(?:\([^)]*\)|[0-9]{1,3}(?:[.,][0-9]+)?\s*%)   진행률 개수
(?i)progress\s*:?\s*([0-9]{1,3}(?:[.,][0-9]+)?)\s*%              진행률 값
```

전부 단순하다. **수동 파서로 대체하는 것이 실용적이다.**

- 성능이 예측 가능하다(진행률 파서는 stderr chunk마다 호출된다).
- `std::regex`의 구현 차이와 느린 성능을 피한다.
- 의존이 줄어든다.

단 **수동 파서가 정규식과 정확히 같은 동작을 해야 한다.**
`fixtures/optiondump/`가 이를 검증한다.

`-L` 파싱만 정규식이 편할 수 있다. 그것은 후퇴 경로이고 호출 빈도가
낮으므로 `std::regex`를 써도 무방하다.

## 9. 표준 라이브러리 주의

| 항목 | 주의 |
|---|---|
| `std::stod` | **로케일 의존.** 쓰지 않는다 |
| `std::to_string(double)` | **로케일 의존, 6자리 고정.** 쓰지 않는다 |
| `std::from_chars` / `std::to_chars` | 로케일 독립, 왕복 최단. **이것을 쓴다** |
| `std::round` | half-away-from-zero. Swift와 같다 |
| `std::filesystem` | Windows에서 경로 처리가 편하지만 예외 동작에 주의 |
| `std::regex` | 느리고 스택을 많이 쓴다 |
| `std::locale` | 전역 로케일을 바꾸지 않는다 |

`std::to_chars(double)`의 C++17 지원은 컴파일러마다 시기가 다르다.
MSVC 19.24+에서 지원한다. 확인하고, 없으면 Ryu/Grisu 구현을 가져온다.

## 10. 프로젝트 구성

```text
NegaflowScannerSane/
    src/
        main.cpp                 서브커맨드 디스패치
        wire/
            protocol.h/.cpp      요청·응답·이벤트 타입
            json.h/.cpp          RapidJSON 래퍼, 상한 설정
            emitter.h/.cpp       ProtocolV2Emitter
        sane/
            option_dump.h/.cpp   SaneOptionDump
            device_list.h/.cpp   -f / -L 파싱
            media.h/.cpp         resolveMedia
            capabilities.h/.cpp  parseCapabilities
            validate.h/.cpp      validateExactOptions
            args.h/.cpp          makeScanimageArgs
            backend_quirks.h     백엔드 이름 상수와 판정
        process/
            child.h/.cpp         CreateProcessW, 파이프, Job
            watchdog.h/.cpp      진행률 watchdog
            cancel.h/.cpp        취소
            environment.h/.cpp   환경 블록, 경로 탐색
        imaging/
            tiff.h/.cpp          libtiff 읽기/쓰기/검증
            merge.h/.cpp         노출 병합
            align.h/.cpp         정렬
        util/
            numeric.h/.cpp       containsExactly, saneNumber, 파싱
            handle.h             RAII 래퍼
            utf8.h/.cpp          인코딩 변환
    tests/
        conformance/             fixtures/ 러너
        unit/
        virtual_scanimage/       가짜 scanimage.exe
    fixtures/                    골든 파일 (Swift와 공유)
    cmake/
    CMakeLists.txt
```

**`sane/` 아래가 전부 순수 함수다.** Win32도 libtiff도 참조하지 않는다.
이 경계를 빌드 수준에서 강제한다(별도 static library, 링크 의존 없음).

## 11. 코딩 규칙 (요약)

```text
- 순수 함수 계층은 I/O를 하지 않는다
- 모든 Win32 핸들은 RAII
- 부동소수점 연산 순서를 소스 그대로 유지
- Math 함수는 std:: 명시
- 문자열 인덱싱은 범위 검사
- 신뢰할 수 없는 입력은 크기 상한 후 파싱
- 예외는 경계에서 잡아 오류 이벤트로 변환
- 전역 상태 금지 (테스트 가능성)
```

## 12. 열린 질문

- 팀의 C++ 유지 역량
- `std::to_chars(double)`의 대상 툴체인 지원
- 정적 링크 vs MSVC 재배포 가능 런타임
- ARM64 빌드의 CI 지원
