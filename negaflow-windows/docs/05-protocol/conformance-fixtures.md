# 적합성 픽스처 corpus

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 구현 계획
목적: macOS 구현과 Windows 구현이 같은 입력에 같은 결정을 내는 것을 기계로 증명한다

관련 문서:

- [wire-contract](wire-contract.md)
- [encoding-and-json](encoding-and-json.md)
- [numerical-parity](../04-imaging/numerical-parity.md)
- [option-dump-parser](../02-frontend-contract/option-dump-parser.md)
- [test-plan](../99-plan/test-plan.md)

## 1. 왜 필요한가

이식 프로젝트에서 "옮겼다"를 증명하는 방법은 두 가지다.

1. 코드를 읽고 같은지 확인한다 — 사람이 하며, 3,000행에서 반드시 놓친다.
2. 같은 입력에 같은 출력이 나오는지 기계로 확인한다.

이 저장소는 2번을 할 수 있는 좋은 위치에 있다. **핵심 로직이 거의 전부
순수 함수**이기 때문이다.

```text
SaneOptionDump(dump)                    문자열 → 구조
resolveMedia(dump, options, hint)       문자열 + 구조 → 구조
parseCapabilities(dump, hint, backend)  문자열 → 구조
validateExactOptions(options, media)    구조 → 통과/오류
makeScanimageArgs(dev, options, media)  구조 → 문자열 배열
epson2AlignedHeightMM(...)              수 → 수
containsExactly(...)                    수 → 불리언
mergeHardwareExposureBitmap(...)        픽셀 → 픽셀
estimateIntegerOffset(...)              픽셀 → 정수 쌍
```

이 아홉 개에 대한 골든 파일이 있으면 이식의 대부분이 검증된다.

## 2. 디렉터리 구조

```text
fixtures/
    README.md                    생성·갱신 방법
    VERSION                      corpus 스키마 버전
    manifest.json                전체 케이스 목록과 태그

    dumps/                       실제 scanimage -A 출력 원문
        genesys-opticfilm-8200i-color-16bit.txt
        genesys-opticfilm-8100-color-16bit.txt
        epson2-gtx980-transparency-color.txt
        epson2-gtx980-default-lineart.txt
        epson2-gtx900-tpu8x10.txt
        coolscan3-ls50-default.txt
        coolscan2-ls2000-default.txt
        pieusb-proscan10t-default.txt
        pie-scsi-default.txt
        empty.txt
        malformed-crlf.txt
        malformed-truncated.txt
        synthetic-corner-pel.txt
        synthetic-inactive-depth-single.txt
        synthetic-inactive-depth-multi.txt

    optiondump/                  SaneOptionDump 단위
        <case>/
            input.txt            → dumps/ 의 파일명 또는 인라인
            expected.json        optionNames, inactiveOptionNames,
                                 각 접근자의 결과

    media/                       resolveMedia
        <case>/
            dump.txt
            options.json
            device-type.txt
            expected-media.json

    capabilities/                parseCapabilities
        <case>/
            dump.txt
            device-type.txt
            backend.txt
            expected-capabilities.json

    validate/                    validateExactOptions
        <case>/
            options.json
            media.json
            expected.json        {"result":"ok"} | {"error":{"code":…,"message":…}}

    args/                        makeScanimageArgs
        <case>/
            devname.txt
            options.json
            media.json
            pass.txt             "main" | "infrared"
            brightness.txt       정수 또는 "null"
            expected-args.json   문자열 배열

    numeric/                     순수 수치 함수
        contains-exactly.json    [{range, value, expected}, …]
        epson2-aligned-height.json
        pixel-geometry.json
        sane-number-format.json
        exposure-trust-weight.json
        smoothstep.json

    wire/                        실제 stdout 바이트
        detect-*.stdout
        capabilities-*.stdout
        scan-*.ndjson

    request/                     PluginScanRequestV2 검증
        <case>/
            input.json
            expected.json        {"result":"ok","options":{…}} | {"error":…}

    merge/                       다중 노출 병합
        <case>/
            sample*.tiff
            exposures.json
            expected.tiff
            expected-pixels.json  (작은 케이스만)

    align/                       정렬
        <case>/
            reference.tiff
            sample.tiff
            expected-offset.json
```

## 3. 생성

### 3.1 원칙

**골든 파일은 macOS 구현이 만든다.** 손으로 쓰지 않는다.
손으로 쓰면 "우리가 생각하는 동작"을 검증하게 되고,
"실제 동작"을 놓친다.

```bash
swift test --filter GoldenFixtureGeneration -- --write
```

이 모드는 CI에서 기본으로 꺼져 있다. 실행하면 `fixtures/`가 갱신되고,
Git diff가 나면 리뷰 대상이 된다.

### 3.2 덤프 수집

`dumps/`의 실제 덤프는 **실기에서 수집한다.** 현재
`VirtualScanimageFixture.swift`(405행)가 합성 덤프를 가지고 있으므로
출발점이 있지만, 합성 덤프는 실제 백엔드가 내는 모든 형태를 담지 못한다.

수집 절차:

```text
1. 장치 연결
2. scanimage -f "%d\t%v\t%m\t%t%n" > device-list.txt
3. scanimage -A -d <dev> > dump-default.txt
4. scanimage -A -d <dev> --source <투과> --mode Color > dump-color.txt
5. scanimage --version >> metadata.txt
6. 각 파일에 수집 환경(OS, SANE 버전, 장치 펌웨어)을 메타데이터로 첨부
```

**개인정보 확인**: 덤프에 시리얼 번호나 사용자 경로가 포함될 수 있다.
커밋 전에 확인하고 필요하면 마스킹한다.

### 3.3 직렬화 규칙

`MediaSelection`과 `ScannerCapabilities`는 현재 `Codable`이 아니거나
wire 형태와 다르다. 픽스처용 직렬화를 별도로 만든다.

```text
- 모든 필드를 명시한다. nil은 null로 쓴다.
- 키 순서는 선언 순서.
- Double은 왕복 최단 표현.
- 열거형은 rawValue.
- IRStrategy는 { "kind": "separateSource", "value": "…" } 형태.
```

**이 직렬화는 wire가 아니다.** 테스트 전용이며 프로토콜을 바꾸지 않는다.

## 4. 케이스 목록

### 4.1 `optiondump`

| 케이스 | 검증 |
|---|---|
| `section-headers-ignored` | `-`로 시작하지 않는 줄 무시 |
| `bool-suffix-stripped` | `--preview[=(yes|no)]` → `preview` |
| `short-option` | `-x`, `-l` → `x`, `l` |
| `duplicate-first-wins` | 같은 옵션 두 번 |
| `inactive-detected` | `[inactive]` |
| `inactive-case-variant` | `[INACTIVE]` |
| `crlf-line-endings` | `\r\n` 처리 |
| `enum-with-spaces` | `Transparency Adapter Infrared` 보존 |
| `enum-selected-value` | `[Color]` 추출 |
| `int-tokens-dpi-suffix` | `600dpi` → 600 |
| `range-mm` | `0..36.33mm` |
| `range-pel` | `0..3600pel` |
| `range-no-unit` | `0..65535` → 단위 nil |
| `range-with-step` | `(in steps of 1)` |
| `range-fractional-step` | `(in steps of 0.5)` |
| `negative-range` | `-100..100` |
| `resolution-list` | `7200|3600|600dpi` |
| `resolution-range` | `50..6400dpi` |
| `inactive-enum-empty` | 비활성이면 `enumValues`가 빈 배열 |
| `inactive-constraint-visible` | `constraintEnumValues`는 값 있음 |
| `empty-dump` | `isEmpty == true` |
| `invalid-utf8` | 오류 |

### 4.2 `media`

각 백엔드 덤프 × 대표 요청 조합.

```text
genesys-8200i × {color 16bit 3600dpi 36×24mm,
                 color 8bit preview,
                 gray 16bit,
                 IR 요청,
                 지원하지 않는 dpi 2000}
epson2-gtx980 × {color 16bit, 소수 mm 높이(정렬 발생),
                 원점 지정, TPU8x10 선택}
coolscan3     × {color 16bit(depth 14), pel 지오메트리, mode 없음}
coolscan2     × {negative 옵션}
pieusb        × {advance 옵션, clean-image}
빈 덤프       × 아무 요청
```

각각의 `expected-media.json`은 **모든 필드**를 담는다.
필드가 하나라도 다르면 실패한다.

### 4.3 `capabilities`

`media`와 같은 덤프 집합. 요청과 무관하므로 케이스 수가 적다.

특히 확인할 것:

- `disabledReasons`의 각 조합
- `fixedDepth` 5갈래
- 범위형 해상도의 표준 후보 필터링
- `supportsPositionedScanArea` 4조건
- `minimumPositiveScanDimension` 3갈래
- `scanAreaUnit`이 pixel인 경우

### 4.4 `validate`

[exact-option-contract](../02-frontend-contract/exact-option-contract.md) §8.2의
목록 전부. 각 거부 케이스가 **정확한 오류 코드와 메시지**를 내는지 확인한다.

메시지 비교는 완전 일치로 한다. 메시지가 바뀌면 픽스처를 갱신해야 하고,
그것이 의도적 변경임을 리뷰에서 확인하게 된다.

### 4.5 `args`

```text
각 백엔드 × {main, infrared} × {preview, full}
+ 밝기/대비/노출이 있는 경우
+ pel 지오메트리
+ 모서리 pel 지오메트리
+ epson2 색/감마 보정
+ pieusb advance
```

**배열의 순서까지 비교한다.**

### 4.6 `numeric`

표 형태의 순수 입출력.

```json
{
  "cases": [
    {"minimum": 0, "maximum": 36.33, "step": null, "value": 36.33, "expected": true},
    {"minimum": -100, "maximum": 100, "step": 1, "value": 0.5, "expected": false},
    ...
  ]
}
```

부동소수점 입력은 **문자열로** 적고 파싱한다. JSON 숫자로 적으면
파서마다 다르게 읽힐 수 있다.

```json
{"minimum": "0", "maximum": "36.33", "value": "36.33", "expected": true}
```

### 4.7 `request`

`PluginScanRequestV2.validatedOptions()`의 11개 조건 + Windows 경로 8종.

Windows 경로 케이스는 **macOS에서 다르게 판정된다.** 예를 들어
`C:\Users\x\frame.tiff`는 macOS에서 상대 경로로 보여 거부되고,
`/tmp/frame.tiff`는 Windows에서 거부된다.

**플랫폼별 케이스를 태그로 분리한다.**

```json
{
  "case": "windows-unc-path",
  "platforms": ["windows"],
  "input": {...},
  "expected": {"error": {"code": "unsupportedOption"}}
}
```

`manifest.json`의 `platforms` 태그로 각 러너가 자기 케이스만 돌린다.

### 4.8 `merge` / `align`

[numerical-parity](../04-imaging/numerical-parity.md) §3.5 참조.

작은 합성 이미지(64×64 또는 128×128)로 모든 분기를 통과시킨다.
`expected-pixels.json`은 작은 케이스에서만 전체 픽셀을 담고,
큰 케이스는 SHA-256 또는 디코드 후 배열 비교로 한다.

### 4.9 `wire` — 바이트 비교를 하지 않는다

`wire/`만 다른 규칙을 쓴다.

```text
비교 대상   파싱 후 의미
            - 키 집합(생략된 키 포함)
            - 각 값
            - 배열 순서
비교 제외   키 순서
```

이유: Swift `JSONEncoder`의 키 순서가 **해시 기반이라 선언 순서도
알파벳 순도 아니다**(2026-08-04 실측). Windows 구현은 자연히 선언 순서로
낼 것이므로 바이트 비교는 매번 실패한다
→ [wire-contract](wire-contract.md) §4.2.3

**nil 필드는 키가 생략된다는 사실이 이 비교의 핵심이다.** Windows가
`null`을 명시하면 "키 집합" 비교에서 잡힌다 — 그것이 이 골든의 존재 이유다.

경로·UUID·타임스탬프는 비교 전에 정규화한다.

## 5. 실행

### 5.1 macOS

```bash
swift test --filter ConformanceFixtures
```

### 5.2 Windows

```bash
<빌드 산출물>/conformance-runner fixtures/
```

또는 테스트 프레임워크 통합. 어느 쪽이든 **같은 `fixtures/` 디렉터리를
읽어야 한다.**

### 5.3 결과 형식

```text
PASS  optiondump/enum-with-spaces
PASS  media/genesys-8200i-color-16bit-3600
FAIL  media/epson2-gtx980-fractional-height
      heightAlignmentMM: expected 0.67, got 0.6699999999999999
PASS  numeric/contains-exactly (48 cases)
...
SUMMARY  312 passed, 1 failed, 4 skipped (platform)
```

실패는 **어느 필드가 어떻게 다른지**를 보여야 한다.
"불일치"만 출력하면 디버깅에 쓸 수 없다.

## 6. CI 통합

```yaml
macOS job:
  - swift test --filter ConformanceFixtures
  - git diff --exit-code fixtures/      # 골든이 바뀌면 실패

Windows job:
  - conformance-runner fixtures/
```

**두 job이 같은 커밋의 `fixtures/`를 쓴다.** 골든 갱신은 별도 PR로 하고
그 PR에서 두 job이 모두 통과해야 한다.

## 7. 유지

### 7.1 언제 갱신하는가

| 변경 | 조치 |
|---|---|
| 파싱 로직 개선 | 골든 갱신 + 리뷰에서 diff 확인 |
| 새 백엔드 지원 | 덤프 추가 + 케이스 추가 |
| sane-backends 버전 변경 | **덤프 재수집** + 회귀 확인 |
| 오류 메시지 수정 | 골든 갱신 |
| 새 검증 조건 | 케이스 추가 |

### 7.2 sane-backends 버전

`-A` 출력이 버전 간 안정적이지 않다
([availability](../01-sane-runtime/availability.md) §7.2).

```text
dumps/<case>.txt 의 첫 줄에 주석으로:
# sane-backends 1.4.0, macOS 26.0, Plustek OpticFilm 8200i fw 1.10, 2026-08-04
```

새 SANE 버전을 지원하기로 하면 덤프를 다시 수집하고, 기존 덤프와
diff를 확인한다. 형식이 바뀌었으면 파서를 조정하고 두 버전 모두를
픽스처로 유지한다.

## 8. 이 corpus가 증명하지 않는 것

- 실제 스캐너가 그 덤프를 내는지 (실기 필요)
- 실제 스캔이 성공하는지
- 성능
- 프로세스·파이프·취소 동작 (별도 테스트 필요)
- 호스트와의 통합

**순수 함수의 동등성만 증명한다.** 그것만으로도 이식 위험의 대부분이
사라지지만, 나머지는 [test-plan](../99-plan/test-plan.md)이 소유한다.

## 9. 착수 순서

```text
1. macOS에 골든 생성 모드를 추가하고 numeric/ 부터 만든다 (가장 쉽다)
2. optiondump/ — 기존 테스트에서 추출
3. dumps/ — 합성 덤프를 VirtualScanimageFixture에서 추출
4. media/, capabilities/, validate/, args/ — 기존 테스트를 픽스처로 전환
5. request/ — 플랫폼 태그 도입
6. wire/ — 실제 stdout 캡처
7. 실기 덤프 수집 (장비 확보 후)
8. merge/, align/ — 합성 이미지 제작
```

1~4는 Windows 구현을 시작하기 **전에** 끝낸다. 그래야 구현하면서
바로 검증할 수 있다.
