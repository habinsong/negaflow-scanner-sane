# 인코딩과 JSON

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 이식 정본
코드 근거: `main.swift`(`emitLine`, `ProtocolV2Emitter`), `PluginProtocolV2.swift`

관련 문서:

- [wire-contract](wire-contract.md)
- [conformance-fixtures](conformance-fixtures.md)
- [child-process](../03-process-and-io/child-process.md)

## 1. 인코딩 계약

```text
JSON 텍스트: UTF-8
이벤트 구분: LF (0x0A) 하나
stdout:      바이너리, BOM 없음
stderr:      UTF-8 권장, 검증 없음
```

Swift `JSONEncoder`는 UTF-8 `Data`를 낸다. `FileHandle.write`가 그대로
쓴다. 중간 변환이 없다.

## 2. Windows에서 UTF-8을 보장하는 방법

세 계층에서 깨질 수 있다.

### 2.1 stdout 모드

CRT가 stdout을 텍스트 모드로 열면 `\n` → `\r\n` 변환이 일어난다.

```c
_setmode(_fileno(stdout), _O_BINARY);
```

프로세스 시작 직후, 어떤 출력보다 먼저 호출한다.

또는 CRT를 우회한다.

```c
HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
WriteFile(h, data, len, &written, nullptr);
```

**후자를 권장한다.** macOS 구현이 `FileHandle`로 직접 쓰는 것과 같은 계층이며,
CRT 버퍼링과 모드 문제를 모두 우회한다.

C#이면:

```csharp
using var stdout = Console.OpenStandardOutput();
stdout.Write(utf8Bytes, 0, utf8Bytes.Length);
stdout.Flush();
```

`Console.Out`(TextWriter)을 쓰지 않는다. 인코딩과 개행 변환이 개입한다.

### 2.2 문자열 → 바이트

내부 문자열이 UTF-16(C#, Windows API)이면 UTF-8로 변환할 때
**서러게이트 쌍과 비유효 시퀀스**를 처리해야 한다.

```text
비유효 UTF-16(짝 없는 서러게이트)이 들어오면:
  - 대체 문자(U+FFFD)로 바꾼다
  - 또는 오류로 처리한다
```

어디서 비유효 시퀀스가 들어올 수 있나:

- `scanimage` stderr를 디코드한 결과 (오류 메시지에 실린다)
- 장치가 보고한 vendor/model 문자열
- 파일 경로

**stderr 디코드가 가장 위험하다.** `scanimage`의 출력 인코딩이
보장되지 않으므로, 손실 허용 디코드 후 유효한 UTF-8만 wire에 실어야 한다.

```text
scanimage stderr 바이트
  → UTF-8로 디코드 시도, 실패한 바이트는 U+FFFD
  → 결과 문자열은 항상 유효한 UTF-8로 재인코딩 가능
```

`System.Text.Encoding.UTF8` 기본은 대체 폴백을 쓴다(예외를 던지지 않는다).
C++이면 직접 처리하거나 검증된 라이브러리를 쓴다.

### 2.3 JSON 이스케이프

JSON 문자열에서 반드시 이스케이프해야 하는 것:

```text
"  → \"
\  → \\
제어 문자 (U+0000 ~ U+001F) → \u00XX 또는 축약형(\b \f \n \r \t)
```

**Windows 경로가 이 계약을 매번 건드린다.**

```text
C:\Users\name\AppData\Local\Temp\.negaflow-scan-abc\frame.tiff
   ↓
"C:\\Users\\name\\AppData\\Local\\Temp\\.negaflow-scan-abc\\frame.tiff"
```

검증된 JSON 라이브러리를 쓰면 자동이다. **수동 문자열 조립을 하지 않는다.**

### 2.3.1 `/` 이스케이프 — 실측 (2026-08-05)

**이 절의 이전 서술은 틀렸다.** "Swift `JSONEncoder`는 `/`를 이스케이프하지
않는다"고 적혀 있었는데, 반대다.

```text
Swift JSONEncoder 기본            "a/b"  →  "a\/b"
.withoutEscapingSlashes 를 켜면    "a/b"  →  "a/b"
```

그리고 **제품 코드는 옵션을 켜지 않는다.** `main.swift`의 두 인코더가 전부
맨 `JSONEncoder()`다.

```text
main.swift:18   let encoder = JSONEncoder()
main.swift:87   JSONEncoder().encode(event)
```

즉 **호스트에 나가는 실제 바이트가 `\/`다.** Windows 구현도 같아야 한다 —
I-5는 같은 형태를 요구하고, 본체 `10-scanner/protocol-contract.md` §20이
직렬화 일치를 인수 gate로 삼는다.

macOS가 나중에 `.withoutEscapingSlashes`를 켜기로 하면 **양 플랫폼을 함께
바꾼다**(I-20). 한쪽만 바꾸면 골든이 갈린다.

이 오류는 파리티가 잡았다 — `irPath: "/tmp/x.ir.tiff"`가 든 케이스에서
Swift가 `"\/tmp\/x.ir.tiff"`를 냈다.
→ [field-lessons](../10-lessons/field-lessons.md) §9b.4

비ASCII 문자를 `\uXXXX`로 이스케이프하는 인코더도 있다.
Swift는 UTF-8 그대로 낸다. 오류 메시지가 한국어이므로 **이 차이가
바로 드러난다.**

```text
"요청 resolution을 정확히 적용할 수 없습니다."
   Swift:  그대로 UTF-8 바이트
   일부 인코더: "\uc694\uccad ..." 
```

둘 다 유효한 JSON이고 디코드 결과가 같지만 바이트가 다르다.
**골든 파일 비교를 위해 UTF-8 그대로 내는 설정을 쓴다.**

- .NET `JsonSerializer`: `Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping`
  (이름과 달리 HTML 컨텍스트가 아닌 곳에서는 안전하다. 우리는 stdout에
  쓰므로 HTML 인젝션 위험이 없다)
- nlohmann/json: 기본이 UTF-8 그대로
- RapidJSON: `kWriteValidateEncodingFlag` 사용, ASCII 이스케이프 끄기

## 3. 숫자 직렬화

### 3.1 위험

```text
Swift Double 36.33 → "36.33"
printf("%f", 36.33) → "36.330000"
로케일이 독일어면 → "36,330000"     ← JSON 파싱 실패
```

**JSON 인코더가 로케일에 의존하지 않는지 반드시 확인한다.**

- Swift `JSONEncoder`: 로케일 독립
- .NET `JsonSerializer`: 로케일 독립 (인바리언트)
- C++ `std::ostream << double`: **로케일 의존.** `imbue(std::locale::classic())`
  또는 `std::to_chars`를 쓴다
- `sprintf("%g")`: 로케일 의존

### 3.2 정확도

```text
scanArea.widthMM = 36.33
```

이 값이 왕복해야 한다. 요청에서 받은 36.33이 `appliedOptions`에서
36.33으로 나가야 하고, 호스트가 exact match를 검사한다.

**왕복 가능한 최단 표현**을 쓴다.

| 언어 | 방법 |
|---|---|
| Swift | 기본 (`Double`의 `description`) |
| .NET Core 3.0+ | 기본 `ToString()` / `JsonSerializer` |
| C++17 | `std::to_chars(buf, end, value)` |
| C++ 이전 | `printf("%.17g")` — 왕복은 되지만 표현이 길다 |

`%.17g`는 `36.329999999999998`을 낸다. 왕복은 되지만 **바이트가 다르다.**
호스트가 값으로 비교하면 통과하지만 골든 파일 비교는 실패한다.
그리고 사용자에게 로그로 보이면 이상하다.

### 3.3 정수

`sequence`는 `UInt64`다. JSON 숫자로 나간다.

```text
2^53 을 초과하면 IEEE 754 double로 정확히 표현되지 않는다
```

실제로 sequence가 2^53에 도달할 일은 없다(이벤트가 수백 개다).
그러나 **호스트 디코더가 JSON 숫자를 double로 파싱하면** 이론적 위험이 있다.

negaflow 본체 windows_docs `10-scanner/protocol-contract.md` §20이 "`UInt64` sequence overflow를 안전하게 거부"를
gate로 명시한다. 어댑터는 2^53 미만을 유지하면 되므로 신경 쓸 것이 없다.

`resolutionDPI`, `bitDepth`, `width`, `height`는 `Int`다.
JSON에 소수점이 붙지 않아야 한다(`3600` not `3600.0`).

### 3.4 특수 값

```text
NaN, Infinity, -Infinity → JSON에 없다
```

Swift `JSONEncoder`는 기본적으로 **예외를 던진다**
(`.throw` 전략). 즉 NaN이 값에 들어가면 인코딩이 실패한다.

`fraction`이 NaN이 될 수 있는가?

```text
scanimageProgressFraction: Double(number) 후 isFinite 검사
mapped = lower + (upper - lower) * fraction   ← 모두 유한
```

유한성이 보장된다. `brightnessAdjustment` 등은 요청 검증에서
`isFinite`를 확인한다.

**Windows 구현도 NaN/Inf를 JSON에 쓰지 않는다.** 라이브러리 설정에
따라 `NaN`이라는 리터럴을 쓰는 것이 있다(비표준). 끈다.

## 4. NDJSON 출력

```text
한 이벤트 = JSON 객체 하나 + 0x0A
객체 내부에 리터럴 개행이 없어야 한다 (JSON 인코더가 이스케이프)
마지막 이벤트 뒤에도 0x0A를 쓴다
```

현재 구현:

```swift
FileHandle.standardOutput.write(data + Data([0x0A]))
```

한 번의 `write` 호출로 JSON과 개행을 함께 쓴다. **원자성을 위해서다.**
두 번 나눠 쓰면 다른 스레드가 사이에 끼어들 수 있다.

`emitLine`(detect/capabilities용)은 문자열에 `\n`을 붙인 뒤 한 번 쓴다.
같은 의도다.

**Windows에서도 한 번의 `WriteFile`로 쓴다.**

```text
버퍼 = JSON 바이트 + 0x0A
WriteFile(hStdout, 버퍼, 길이, &written, nullptr)
written < 길이면 나머지를 계속 쓴다   ← 파이프에서 부분 쓰기가 가능하다
```

부분 쓰기 처리를 빠뜨리면 드물게 잘린 JSON이 나간다.

### 4.1 플러시

파이프는 CRT 버퍼링을 우회하면 플러시가 필요 없다.
`WriteFile`은 즉시 전달한다.

CRT `fwrite`를 쓴다면 `fflush(stdout)`이 필수다. 진행률이 실시간으로
호스트에 도달해야 하기 때문이다.

### 4.2 직렬화

`ProtocolV2Emitter`가 락으로 직렬화한다.

```text
lock
  이벤트 생성 (sequence 사용 후 증가)
  인코딩
  write
unlock
```

**인코딩과 쓰기가 모두 락 안에 있다.** sequence 순서와 출력 순서가
일치해야 하기 때문이다. 락을 좁히면(sequence만 락 안에서) 순서가
뒤바뀔 수 있다.

Windows에서도 같은 범위를 유지한다.

진행률 콜백이 다른 스레드에서 온다(stderr 읽기 스레드).
결과 이벤트는 주 스레드에서 온다. **두 스레드가 실제로 경합한다.**

## 5. stdin 읽기

```text
readDataToEndOfFile()
```

EOF까지 읽는다. 호스트가 쓰고 파이프를 닫는다.

Windows:

```text
loop:
    ReadFile(hStdin, buf, sizeof(buf), &n, nullptr)
    실패:
        GetLastError() == ERROR_BROKEN_PIPE → EOF로 처리
        그 외 → 오류
    n == 0 → EOF
    누적
```

**`ERROR_BROKEN_PIPE`를 EOF로 다뤄야 한다.** 파이프 쓰기 끝이 닫히면
`ReadFile`이 이 오류를 낸다.

크기 상한을 둔다. `capabilityToken`이 1 MiB이므로 요청 전체가
약 1.1 MiB를 넘지 않는다.

```text
상한 4 MiB. 초과하면 거부.
```

## 6. JSON 파싱

### 6.1 디코딩 규칙

현재 Swift 구현:

```text
JSONDecoder() 기본 설정
알 수 없는 키 → 무시
필수 키 누락 → 실패
타입 불일치 → 실패
```

**알 수 없는 키를 무시하는 것이 계약이다.** 호스트가 새 필드를 추가해도
기존 플러그인이 동작해야 한다.

.NET `JsonSerializer`의 기본도 알 수 없는 키를 무시한다.
`JsonSerializerOptions.UnmappedMemberHandling = Skip`(기본).

### 6.2 옵셔널 vs null

`PluginScanRequestV2`의 필드:

```swift
public var brightnessAdjustment: Double?
```

Swift 합성 디코더는 `decodeIfPresent`를 쓴다. 즉:

```text
키 없음  → nil
"null"   → nil
값 있음  → 값
```

**두 경우가 같다.** Windows 구현도 같아야 한다.

`ScanArea`는 커스텀 디코더를 가진다:

```text
originXMM: decodeIfPresent ?? 0
originYMM: decodeIfPresent ?? 0
widthMM:   decode (필수)
heightMM:  decode (필수)
```

즉 **원점은 생략 가능하고 기본 0, 크기는 필수**다.

#### 6.2.1 인코딩 방향은 대칭이 아니다

위는 **디코딩**(우리가 받는 쪽)이다. **인코딩**(우리가 내는 쪽)은
규칙이 다르고, 타입마다 갈린다(2026-08-04 실측).

```text
합성 Codable        nil → 키 생략          (encodeIfPresent)
명시적 encode(to:)   nil → "null" 명시      (container.encode)
```

| 우리가 내는 타입 | 인코더 | nil |
|---|---|---|
| `PluginDevice` | 합성 | 키 생략 |
| `PluginCapabilities` | 합성 | 키 생략 |
| `PluginScanEventV2` | 합성 | 키 생략 |
| `PluginAppliedScanOptionsV2` | 명시적 | `null` |

**받을 때는 둘을 같게 다루지만, 낼 때는 macOS와 같은 형태를 낸다.**
Windows가 모든 키를 `null`로 채우면 호스트는 아마 견디겠지만 I-5가
요구하는 "같은 형태"가 아니다.

그리고 **키 순서는 보장되지 않는다** — Swift `JSONEncoder`는 해시 순서로
낸다. 이것이 wire 골든을 바이트 비교로 만들 수 없는 이유다
→ [wire-contract](wire-contract.md) §4.2.1, §4.2.3

### 6.3 방어

토큰과 요청이 신뢰할 수 없는 입력이므로:

```text
최대 문서 크기:      4 MiB
최대 중첩 깊이:      32
최대 문자열 길이:    2 MiB (capabilityToken 여유)
최대 배열/객체 항목: 4096
```

.NET: `JsonReaderOptions.MaxDepth`.
nlohmann/json: 깊이 제한 없음 → 재귀 파서라 스택 오버플로 가능.
**RapidJSON의 반복 파서(`kParseIterativeFlag`)를 권장한다.**

### 6.4 중복 키

```text
{"bitDepth": 16, "bitDepth": 8}
```

JSON 표준이 동작을 정의하지 않는다. 구현마다 첫 값 또는 마지막 값을 쓴다.

**macOS 는 첫 값을 쓴다**(2026-08-05 실측). 위 예에서 `16` 이다.

이 문서는 원래 "대체로 마지막 값"이라고 적고 있었다. **추측이었고 틀렸다** —
[field-lessons](../10-lessons/field-lessons.md) §9b.5.

**Windows 구현은 중복 키를 거부한다.** 공격 표면을 줄인다. 그래서 이 항목은
macOS 보다 엄격하며, 파리티는 `KeepFirst` 설정으로 돌려 macOS 동작을 대조한다
(`windows/src/wire/parse.h` 의 `DuplicateKeyPolicy`).

### 6.5 실측표 — 요청 디코딩

2026-08-05, `PluginScanRequestV2` 에 직접 먹여 확인했다. **§6.1~§6.4 의 서술
중 검증된 것과 아닌 것을 구분하기 위해 남긴다.**

```text
알 수 없는 키              무시             중첩 객체 안에서도 무시한다
키 부재 / null (옵셔널)    둘 다 nil
키 부재 (필수)             keyNotFound
null (필수 String/Int)     valueNotFound
null (필수 Bool)           typeMismatch    ← Bool 만 다르다
중복 키                    **첫 값**
Int 필드에 16.0 / 1.6e1    수락 → 16       정수값이면 표기는 무관
Int 필드에 1200.5          **문서 전체가 무효 JSON**  타입 오류가 아니다
Int 필드에 2^63            거부            Int64 범위 밖
Double 에 1e-324 / 1e309   거부            언더/오버플로 둘 다
Double 에 4.9e-324         수락            준정규는 유효하다
Double 에 0e999            수락 → 0.0
문자열 안 생 제어문자       거부            탭·개행
잘못된 이스케이프 \x        거부
짝 없는 서로게이트 \uD800   거부
                      수락            NUL 이 문자열에 들어온다
잘못된 UTF-8 바이트         **수락**        거부하지 않는다
UTF-8 BOM                  수락
앞 공백 / 뒤 개행           수락
뒤에 붙은 값 / 주석         거부
중첩 깊이                  512 근처에서 거부
UUID                       8-4-4-4-12 만. 중괄호·하이픈없음·urn: 전부 거부
```

Windows 구현이 이 표와 갈리는 곳은 **둘뿐이고 둘 다 문서화돼 있다** —
`windows/src/wire/parse.h` 의 "그래도 남는 차이 하나"와 `IntegerTooWide`.

## 7. UUID

```text
Swift UUID 인코딩: 대문자 하이픈 8-4-4-4-12
Swift UUID 디코딩: 대소문자 무시, 하이픈 필수, 중괄호 불허
```

[wire-contract](wire-contract.md) §5.4의 결정에 따라 Windows는
**요청 문자열을 그대로 반사**한다. 그래도 유효성은 검증한다.

```text
정규식: ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$
```

중괄호 형태(`{...}`)나 하이픈 없는 형태를 받지 않는다.
`Guid.Parse`는 여러 형태를 받으므로 `Guid.ParseExact(s, "D")`를 쓴다.

## 8. base64

```text
표준 알파벳 (A-Za-z0-9+/)
패딩 = 포함
줄바꿈 없음
```

디코드 시:

- 줄바꿈이 섞인 입력을 받을 것인가? Swift
  `Data(base64Encoded:)`의 기본은 **거부**한다
  (`.ignoreUnknownCharacters` 옵션이 없으면).
- Windows도 엄격하게 거부한다.
- URL-safe 알파벳(`-_`)을 받지 않는다.

## 9. 이식 체크리스트

- [ ] stdout이 바이너리 모드이거나 CRT를 우회한다
- [ ] JSON이 UTF-8 그대로 나간다(`\uXXXX` 이스케이프 없음)
- [ ] `/`를 이스케이프하지 않는다
- [ ] 백슬래시 이스케이프가 라이브러리로 처리된다
- [ ] 숫자 직렬화가 로케일 독립이고 왕복 최단이다
- [ ] `Int` 필드에 소수점이 붙지 않는다
- [ ] NaN/Inf가 JSON에 나가지 않는다
- [ ] 한 번의 write로 JSON + LF
- [ ] 부분 쓰기 처리
- [ ] emitter 락이 인코딩과 쓰기를 모두 감싼다
- [ ] `ERROR_BROKEN_PIPE`를 EOF로 처리
- [ ] 알 수 없는 키를 무시한다
- [ ] 키 생략과 null이 같게 **디코드**된다
- [ ] **인코딩**은 타입별 규칙을 따른다 — 합성=생략, appliedOptions=null (§6.2.1)
- [ ] `ScanArea` 원점 기본 0, 크기 필수
- [ ] 파싱 상한 4종
- [ ] 반복 파서(스택 오버플로 방지)
- [ ] 중복 키 정책이 정해졌다
- [ ] UUID 형식 검증이 엄격하다
- [ ] base64가 엄격하다
- [ ] stderr 바이트를 손실 허용 디코드 후 유효 UTF-8로 만든다

## 10. 골든 파일 검증

`fixtures/wire/` 아래에 macOS가 실제로 낸 바이트를 저장한다.

```text
detect-one-device.stdout
detect-empty.stdout
capabilities-genesys-8200i.stdout
capabilities-coolscan3.stdout
scan-progress-sequence.ndjson
scan-result-full.ndjson
scan-result-ir.ndjson
scan-result-multiexposure.ndjson
scan-error-unsupported.ndjson
scan-error-parse-failure.ndjson
```

Windows 구현이 같은 입력에 **바이트 동일한** 출력을 내는지 검증한다.

바이트 동일이 불가능한 항목(경로가 다르므로 `path` 필드)은
정규화 후 비교한다. 정규화 규칙을 명시한다.

```text
경로 필드를 "<PATH>"로 치환
requestID를 "<UUID>"로 치환
그 외는 바이트 동일
```
