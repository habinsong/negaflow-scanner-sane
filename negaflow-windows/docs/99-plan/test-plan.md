# 테스트 계획

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 구현 계획
목적: 무엇을 어떤 층에서 검증하고, **각 층이 무엇을 증명하지 못하는지** 정한다

관련 문서:

- [conformance-fixtures](../05-protocol/conformance-fixtures.md) — 순수 함수 골든 (L2)
- [validation-matrix](../09-hardware/validation-matrix.md) — 실기 E 등급 (L6)
- [numerical-parity](../04-imaging/numerical-parity.md) — 수치 동등성
- [roadmap](roadmap.md) — 각 층이 어느 마일스톤에 붙는지

## 0. 층 구조

```text
L0  빌드 검사        컴파일러·링커·플래그가 계약을 만족하는가
L1  단위             함수 하나
L2  적합성 골든      macOS와 같은 입력에 같은 출력      ← conformance-fixtures
L3  프로세스 통합    가상 scanimage.exe로 end-to-end
L4  견고성           퍼징, 자원 누수, 동시성
L5  수치 동등성      macOS와 비트 단위 일치
L6  실기             실제 스캐너                        ← validation-matrix
L7  호스트 통합      negaflow 본체와
```

**각 층은 아래 층이 증명하지 못하는 것만 다룬다.** 중복 테스트는 유지비만
늘리고 실패 시 원인을 흐린다.

### 0.1 각 층이 증명하지 **못하는** 것

| 층 | 증명하지 못하는 것 |
|---|---|
| L2 | 실제 스캐너가 그 덤프를 내는지 |
| L3 | 실제 `scanimage`가 가상본과 같이 행동하는지 |
| L4 | 정상 경로의 정확성 |
| L5 | 이미지가 "좋은지" (품질은 본체 영역) |
| L6 | 우리가 확보하지 못한 장치 |
| L7 | 호스트의 다음 버전 |

**L2가 통과했는데 L6이 실패하는 것은 정상이다.** 반대는 결함이다 —
L6이 통과하는데 L2가 실패하면 골든이 틀린 것이다.

---

## L0 — 빌드 검사

**"코드가 아니라 빌드가 계약을 깬다"** 는 종류의 실패를 잡는다.

| 검사 | 방법 | 근거 |
|---|---|---|
| `libsane` 미링크 | `dumpbin /imports`에 sane 없음 | I-11, D-17 |
| FP 축약 금지 | `/fp:precise`, `-ffp-contract=off` 확인 | D-11, I-4 |
| SIMD 자동 벡터화 확인 | 누적 합 함수의 디스어셈블 검사 | D-11 |
| `asInvoker` 매니페스트 | 리소스 확인 | I-14 |
| 아키텍처 | x64 / ARM64 산출물이 각각 맞는 machine type | — |
| 경고 = 오류 | `/W4 /WX` | — |
| ASan/UBSan 빌드 성립 | 별도 CI job | D-13 |

**FP 플래그 검사가 특히 중요하다.** 로컬 debug에서 수치 동등성이 통과하고
릴리스에서 깨지면 원인을 찾는 데 며칠이 든다
([field-lessons](../10-lessons/field-lessons.md) §7).

`sane_logic` 타깃은 **Win32도 libtiff도 링크하지 않아야 한다**(M2 통과 조건).
순수 로직이 플랫폼에 오염되지 않았음을 링커가 증명한다.

---

## L1 — 단위

L2 골든이 대부분을 덮으므로, 여기서는 **골든으로 표현하기 어려운 것**만 다룬다.

```text
Win32 핸들 RAII 래퍼        이중 해제, 이동 시맨틱
문자열 변환 (UTF-8 ↔ UTF-16) 경계 문자, 서로게이트 쌍, 잘못된 시퀀스
경로 정규화                  UNC, 긴 경로, reparse point 판정
base64 인코더/디코더         패딩, 잘못된 알파벳, 길이 경계
saneNumber 형식             로케일 독립성 (한국어 로케일에서 실행)
```

**로케일 테스트를 실제로 로케일을 바꿔서 한다.** `LC_ALL=C`를 설정하는
코드가 있다는 사실은 그 코드가 동작한다는 증거가 아니다.

---

## L2 — 적합성 골든

**[conformance-fixtures](../05-protocol/conformance-fixtures.md)가 소유한다.**
여기서는 그 문서가 다루지 않는 **운영 규칙**만 정한다.

### 2.1 골든의 권위

```text
골든 파일은 macOS 구현이 만든다. 손으로 쓰지 않는다.
```

손으로 쓰면 "우리가 생각하는 동작"을 검증하게 되고 "실제 동작"을 놓친다.

### 2.2 골든이 바뀔 때

```text
macOS job:  swift test --filter ConformanceFixtures
            git diff --exit-code fixtures/     ← 골든이 바뀌면 실패
Windows job: conformance-runner fixtures/
```

**두 job이 같은 커밋의 `fixtures/`를 쓴다.** 골든 갱신은 **별도 PR**로 하고
그 PR에서 두 job이 모두 통과해야 한다.

골든이 바뀌는 PR은 리뷰에서 **"이 변경이 의도적인가"** 만 확인하면 된다.
이것이 골든 방식의 전부다.

### 2.3 커버리지 목표

M2 통과 조건이다.

| 대상 | 목표 |
|---|---|
| `validateExactOptions` 거부 케이스 | **전부** ([exact-option-contract](../02-frontend-contract/exact-option-contract.md) §8.2) |
| `PluginScanRequestV2` 검증 조건 | 11개 전부 + Windows 경로 8종 |
| `epson2AlignedHeightMM` | 4갈래 전부 |
| `fixedDepth` | 5갈래 전부 |
| 백엔드 분기 | 문서화된 16곳 전부 |
| `makeScanimageArgs` | 각 백엔드 × {main, IR} × {preview, full} |

**"백엔드 분기 16곳 전부"가 이 표에서 가장 중요하다.** 분기 하나가 이식에서
누락되면 그 백엔드만 조용히 오동작한다
([backend-quirks](../02-frontend-contract/backend-quirks.md) §0).

### 2.4 플랫폼 태그

```json
{"case": "windows-unc-path", "platforms": ["windows"], ...}
```

`C:\Users\x\frame.tiff`는 macOS에서 상대 경로로 보여 거부되고,
`/tmp/frame.tiff`는 Windows에서 거부된다. **양쪽이 다르게 판정하는 것이
정상인 케이스**를 태그로 분리한다.

---

## L3 — 프로세스 통합 (가상 `scanimage.exe`)

macOS의 `VirtualScanimageFixture`(405행)에 대응하는 것을 만든다.
**mock 객체가 아니라 실제 실행되는 프로그램이어야 한다.**

### 3.1 가상 `scanimage.exe`가 해야 하는 것

```text
-f / -L        고정 장치 목록 텍스트를 stdout에
-A -d <dev>    지정된 덤프 텍스트를 stdout에
-p --format=tiff
               stderr에 Progress: n% 를 지정된 간격으로
               stdout에 유효한 TIFF 바이트를
```

주입 가능해야 하는 동작:

| 시나리오 | 방법 |
|---|---|
| 첫 진행률 지연 | 인자 또는 환경 변수 |
| 진행률 중단(stall) | 같음 |
| 비정상 종료 코드 | 같음 |
| stderr에 `rounded value of` | 같음 |
| stderr에 `Device busy` | 같음 |
| 손상된 TIFF | 같음 |
| 종료 신호 무시(강제 종료 유도) | 같음 |
| 대용량 출력 (파이프 버퍼 초과) | 같음 |

### 3.2 검증 항목

[child-process](../03-process-and-io/child-process.md) §13.2가 정본이다.
그중 이식에서 **새로 생기는** 것:

```text
□ stdout이 바이너리 모드다 (0x0D 삽입 없음)          ← 가장 중요
□ 획득 stdout이 파일 핸들로 직접 간다 (파이프 아님)
□ stderr 파이프가 가득 차도 교착하지 않는다
□ 핸들 상속이 필요한 것만 상속된다
□ Job Object가 우리 자식만 담는다
□ 부모 크래시 후 자식이 남지 않는다
□ 100회 반복 후 핸들 누수 0
□ 좀비/고아 프로세스 0
□ 취소가 동작한다 (C-1 결과에 따라 경로가 갈림)
□ 강제 종료 후 다음 스캔이 가능하다 (C-2)
□ 동시 scan 세션 거부
□ 이름으로 전역 프로세스를 찾지 않는다 (I-6)
```

**교착 테스트를 반드시 넣는다.** stderr를 읽지 않고 자식의 종료를 기다리면
파이프 버퍼가 차는 순간 양쪽이 멈춘다. 이건 부하가 걸려야 나타나므로
수동 테스트로는 절대 안 잡힌다.

### 3.3 타임아웃 테스트

가상 `scanimage.exe`에 짧은 타임아웃을 주입해 실시간을 기다리지 않는다.

```text
utilityProcessTimeout                180 s → 테스트에서 0.5 s
acquisitionFirstProgressTimeout      180 s → 0.5 s
acquisitionProgressStallTimeout      180 s → 0.5 s
```

확인할 것:

- 첫 진행률 타임아웃과 stall 타임아웃이 **구분되어** 판정된다
- genesys는 첫 진행률 타임아웃에서 **1회 재시도**한다
- pieusb는 **재시도하지 않고 watchdog도 켜지 않는다**
- **총 스캔 시간에 상한이 없다**(I-7) — 진행률이 계속 오면 계속 기다린다

마지막 항목을 테스트로 고정한다. "안전하게 상한을 두자"는 생각이 이식 중에
반드시 나오고, 그러면 7200 dpi 스캔이 중간에 죽는다.

---

## L4 — 견고성

### 4.1 퍼징

M2 통과 조건: **24시간 크래시 없음.**

| 대상 | 입력 |
|---|---|
| JSON 디코더 | `PluginScanRequestV2` 요청 |
| 옵션 덤프 파서 | `-A` 출력 |
| base64 디코더 | `capabilityToken` |

**셋 다 신뢰할 수 없는 입력이다**(I-15). `capabilityToken`은 호스트를
거쳐 돌아오고, `scanimage` 출력은 외부 프로그램이 만들고, 요청은 호스트가 준다.

시드는 `fixtures/`에서 가져온다. 실제 덤프가 가장 좋은 시드다.

### 4.2 인자 주입

`acquisitionDevice`가 명령줄로 나간다. **Windows에서 새로 생기는 위험이다** —
`CreateProcessW`는 인자를 문자열 하나로 받고 자식이 파싱한다.

```text
장치명에 " 포함
장치명에 공백 포함
장치명에 ^ & | > < 포함
장치명이 - 로 시작 (옵션으로 해석)
장치명이 매우 김
```

전부 **거부**되어야 한다. 이스케이프해서 통과시키지 않는다 —
정상 SANE 장치명에는 이런 문자가 없다.

### 4.3 자원

```text
100회 detect → 핸들 수 변화 0
100회 scan (가상) → 핸들·메모리 변화 0
큰 TIFF 반복 처리 → 피크 메모리가 예측 범위
중간 파일이 실패 경로에서도 정리된다
```

### 4.4 파일 경로

```text
outputPath가 reparse point → 거부 (I-16)
outputPath 디렉터리가 없음 → 명확한 오류
outputPath에 쓰기 권한 없음 → 명확한 오류
디스크 가득 참 → 부분 파일을 남기지 않는다
GetFinalPathNameByHandleW로 최종 경로 확인
```

---

## L5 — 수치 동등성

**[numerical-parity](../04-imaging/numerical-parity.md)가 정본이다.**

### 5.1 순서

```text
N-1  로드 경로 동등성 spike     ← M4 착수 전에 반드시
     macOS에서만 실행. Windows 장비 불필요.
```

N-1이 실패하면 M4의 규모가 크게 늘고 macOS 변경이 필요할 수 있다.
**M4를 시작하기 전에 답을 얻는다.**

### 5.2 비교 대상

| 연산 | 허용 오차 |
|---|---|
| 노출 병합 결과 | **UInt16 단위 완전 일치** |
| 정렬 오프셋 | **정수 완전 일치** |
| 순수 수치 함수 | 비트 패턴 일치 |

**"거의 같다"가 없다.** I-4가 비트 단위 일치를 요구한다.

### 5.3 실패 시 선택지

`numerical-parity` §7이 소유한다. 요약하면:

```text
(a) macOS를 명시적 변환으로 바꾼다      권장. 단 macOS 변경 작업이 추가된다
(b) Windows가 Core Image 동작을 모사한다  재현 위험
(c) 허용 오차를 도입한다                 I-4 포기. product-invariants 수정 필요
```

**(c)를 고르면 다중 노출 기능을 Windows에서 비활성화하는 것도 선택지다**
(roadmap "언제 중단할 것인가").

---

## L6 — 실기

**[validation-matrix](../09-hardware/validation-matrix.md)가 소유한다.**
E1~E7 절차와 릴리스 gate가 거기 있다.

여기서는 **L6과 다른 층의 연결**만 적는다.

### 6.1 L6이 L2에 되먹임된다

```text
E4  scanimage -A 출력 전문 저장 → fixtures/dumps/ 에 추가
```

**실기에서 얻은 덤프가 골든의 입력이 된다.** 합성 덤프는 실제 백엔드가
내는 모든 형태를 담지 못한다.

덤프에 **시리얼 번호나 사용자 경로가 들어갈 수 있다.** 커밋 전에 확인하고
필요하면 마스킹한다.

각 덤프 첫 줄에 수집 환경을 남긴다:

```text
# sane-backends 1.4.0, Windows 11 26xx, Plustek OpticFilm 8200i fw 1.10, 2026-xx-xx
```

### 6.2 L6에서만 나오는 값

이 값들은 실기 없이 정할 수 없다.

| 값 | spike |
|---|---|
| 첫 진행률까지의 시간 분포 | T-1 |
| 진행률 간격 최댓값 | T-2 |
| 유틸리티 실행 시간 | T-3 |
| 취소 지연 | C-3 |
| 장치명 변동 비율 | U-3 |

**현재 타임아웃 180초는 macOS 관측에서 나온 값이다.** Windows에서 그대로
쓸 근거가 없다 — 측정하고 정한다. 다만 **바꿀 때는 측정 근거를 함께
기록한다**(product-invariants §21: 타임아웃 수치는 불변식이 아니지만
근거는 필요하다).

### 6.3 IR 경로는 장비에 걸려 있다

현재 개발 환경(macOS)의 genesys 빌드는 OpticFilm에서 **IR을 노출하지 않는다.**
epson2/epkowa도 미노출. 즉 **IR 경로는 macOS에서도 실기 검증되지 않았다.**

```text
IR 코드는 이식하되, "macOS에서 검증된 동작을 재현했다"고 말할 수 없다.
Windows에서 처음으로 실기 검증될 가능성이 있다.
```

이 사실을 릴리스 노트의 알려진 한계에 넣는다.
릴리스 gate는 "최소 2대 E6 + 그중 하나는 IR E6"을 요구하므로,
**IR을 노출하는 장비 확보가 gate의 실질 병목**이다.

---

## L7 — 호스트 통합

가장 늦게, 가장 적게 자동화되는 층이다.

### 7.1 확인 항목

```text
□ 호스트가 플러그인을 발견한다 (%LOCALAPPDATA% 경로)
□ detect 결과가 UI에 장치로 나타난다
□ capabilities가 UI 컨트롤로 변환된다
□ scan 진행률이 UI에 반영된다
□ 취소가 UI에서 동작한다
□ 결과 TIFF가 현상 파이프라인에 들어간다
□ IR 파일이 결함 제거에 쓰인다
□ 플러그인 크래시가 본체를 죽이지 않는다
□ appliedOptions의 1 mm 높이 차이를 호스트가 허용한다
□ requestID 대소문자 차이를 호스트가 견딘다
```

### 7.2 색 계약 확인 — 자동화 가능하다

[host-pipeline-contract](../10-lessons/host-pipeline-contract.md)가 요구하는 것을
**플러그인 쪽에서 단독으로 검증할 수 있다.**

```text
□ 출력 TIFF에 ICC 프로파일 태그가 없다
□ TRANSFERFUNCTION 태그가 없다
□ 16-bit, 무압축
□ IR 파일의 픽셀 크기가 RGB와 같다
```

**호스트 없이 검증할 수 있으므로 L3에 넣는다.** 여기 적는 이유는 이 검사가
왜 존재하는지가 L7 맥락에서만 이해되기 때문이다.

색이 무너지는 실패는 **스캔 성공, 검증 통과, 색만 틀림**으로 나타난다
([field-lessons](../10-lessons/field-lessons.md) §6). 이 네 줄이 그것을 막는다.

---

## 2. CI 구성

```yaml
macos:
  runs-on: macos-26
  - verify-provenance.py
  - swift test (strict concurrency, warnings-as-errors)
  - conformance fixtures
  - git diff --exit-code fixtures/

windows-x64:
  runs-on: windows-latest
  - L0 빌드 검사
  - 단위 + conformance-runner fixtures/
  - 가상 scanimage 통합 테스트
  - (별도 job) ASan/UBSan 빌드 + 테스트

windows-arm64:
  - 빌드만 (러너 확보 여부는 Q-13)

fuzz:
  - 야간 또는 주간, 24시간
```

**`git diff --exit-code fixtures/`가 macOS job에만 있다.** 골든을 만드는
쪽이 macOS이기 때문이다. Windows job은 읽기만 한다.

---

## 3. 회귀 정책

### 3.1 실패했을 때

```text
L2 실패  → 이식 결함이다. 골든을 고치지 않는다.
           골든이 틀렸다고 판단되면 macOS 동작을 먼저 확인한다.
L5 실패  → numerical-parity §7의 선택지로 간다. 허용 오차를 몰래 넣지 않는다.
L6 실패  → 장치별 등급을 낮춘다. 지원 표를 고친다. 코드를 서두르지 않는다.
```

### 3.2 sane-backends 버전이 바뀌면

`-A` 출력이 버전 간 안정적이지 않다. 1.4.0 릴리스 노트 자체가 이 영역의
출력이 바뀐다고 적고 있다.

```text
1. dumps/ 재수집
2. 기존 덤프와 diff
3. 형식이 바뀌었으면 파서 조정
4. 두 버전 모두를 픽스처로 유지
```

**버전을 고정하고, 런타임에 `scanimage --version`을 기록한다.**
알려지지 않은 버전이면 진단에 경고를 남기되 **차단하지 않는다.**

### 3.3 새 장치가 보고되면

```text
1. -A 덤프를 받는다 (개인정보 확인)
2. fixtures/dumps/ 에 추가
3. media/ capabilities/ 케이스 추가
4. 기존 골든이 깨지지 않는지 확인   ← 여기가 핵심
5. 지원 표에 "사용자 보고" + E 등급으로 기록
```

4번이 새 장치 지원의 진짜 비용이다. 새 백엔드 분기를 추가하려면
upstream 소스 또는 실기 관측이 근거로 있어야 한다.

---

## 4. 하드웨어 없이 어디까지 갈 수 있는가

장비 확보가 M8의 병목이므로, **장비 없이 가능한 범위를 명확히 한다.**

| 층 | 장비 없이 |
|---|---|
| L0 | 전부 가능 |
| L1 | 전부 가능 |
| L2 | 합성 덤프로 대부분 가능. 실기 덤프만 나중 |
| L3 | **전부 가능** (가상 scanimage) |
| L4 | 전부 가능 |
| L5 | **전부 가능** (N-1은 macOS만 필요) |
| L6 | 불가능 |
| L7 | 부분 가능 (호스트만 있으면) |

**L0~L5가 전부 장비 없이 가능하다.** 즉 M1~M5를 장비 확보와 병행할 수 있고,
[roadmap](roadmap.md)의 병행 구조가 여기서 나온다.

`test` 백엔드가 있으면 L6의 일부를 장비 없이 흉내낼 수 있지만,
릴리스 빌드에 넣으면 I-17("Mock이나 fallback 장치가 없다")과 충돌한다
→ Q-16.

## 5. 완료 지표

roadmap과 같은 원칙이다. 다시 적는다.

```text
✗ 테스트 개수
✗ 코드 커버리지 %
✗ "일단 스캔이 됐다"

✓ 통과한 골든 픽스처 수 / 전체
✓ 수치 동등성이 증명된 연산 수
✓ E6 이상을 통과한 장치 수
✓ 불변식 20개 중 검증된 수
```

**코드 커버리지를 지표로 쓰지 않는 이유**: 이 프로젝트의 위험은 "실행되지
않은 줄"이 아니라 "다른 판정을 내리는 줄"이다. 커버리지 100%인 이식본이
모든 백엔드에서 틀릴 수 있다.
