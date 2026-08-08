# 제품 불변식

기준일: 2026-08-04
상태: 정본 — 이 문서와 다른 문서가 충돌하면 이 문서가 이긴다
목적: Windows 이식이 절대 깨뜨리면 안 되는 것을 한 곳에 모은다

## 0. 사용법

구현 중에 "이렇게 하면 더 쉬운데"라는 생각이 들 때 여기를 본다.
여기 있는 것은 편의를 위해 완화하지 않는다. 완화하려면 이 문서를
먼저 고치고, 그 변경이 검토를 통과해야 한다.

각 불변식에는 **깨졌을 때 무슨 일이 일어나는가**를 적었다.
그것이 근거다.

여러 불변식이 실제 사고에서 나왔다. 그 사건들은
[field-lessons](../10-lessons/field-lessons.md)에 있다 — "왜 이렇게까지
엄격한가"가 궁금할 때 읽는다.

## I-1. 정확한 옵션만 적용한다

> 요청한 값을 정확히 적용할 수 없으면 스캔을 시작하지 않는다.
> 시작한 뒤에 알게 되면 결과를 버린다.

가장 가까운 값으로 스냅하지 않는다. 반올림 경고를 무시하지 않는다.
"거의 맞으니까 괜찮다"가 없다.

**깨지면**: 같은 필름을 같은 설정으로 두 OS에서 스캔했을 때 다른
픽셀이 나온다. negaflow의 현상 결과가 플랫폼에 의존하게 된다.

소유: [exact-option-contract](../02-frontend-contract/exact-option-contract.md)

## I-2. 능력은 관측이지 약속이 아니다

> 장치가 실제로 노출한 옵션에서만 능력을 판정한다.
> 모델명으로 능력을 발명하지 않는다.

백엔드 이름으로 분기하는 곳은 문서화된 16곳뿐이며, 각각 upstream 소스나
실기 관측이 근거다.

**깨지면**: 사용자가 켤 수 있는 컨트롤을 켰다가 스캔 시작 시 거부당한다.
또는 지원하지 않는 장치를 지원한다고 표시한다.

소유: [capability-model](../02-frontend-contract/capability-model.md),
[backend-quirks](../02-frontend-contract/backend-quirks.md)

## I-3. 산출물을 검증하기 전에는 성공이 아니다

> 종료 코드 0만으로 성공하지 않는다.
> result 이벤트만으로도 성공하지 않는다.
> TIFF를 열어 크기·심도·색 모델을 확인한 뒤에만 result를 낸다.

**깨지면**: 손상된 파일이나 잘못된 형식의 파일이 negaflow로 들어가
현상 파이프라인에서 알 수 없는 오류가 난다.

소유: [tiff-validation](../04-imaging/tiff-validation.md),
[exact-option-contract](../02-frontend-contract/exact-option-contract.md) §5

## I-4. 이미지 결과는 플랫폼에 의존하지 않는다

> 다중 노출 병합, 정렬, 픽셀 변환의 결과가 macOS와 Windows에서
> 비트 단위로 같아야 한다.

**깨지면**: 같은 스캔이 OS에 따라 다른 결과를 낸다. negaflow가
"이미지 품질·정밀도 계약은 플랫폼에 따라 달라지지 않는다"는 자기
불변식을 지킬 수 없게 된다.

소유: [numerical-parity](../04-imaging/numerical-parity.md)

## I-5. wire를 바꾸지 않는다

> 같은 호스트가 두 플랫폼의 플러그인을 상대한다.
> 응답 형태가 다르면 호스트가 플랫폼별 분기를 갖게 된다.

`id`는 `sane`이다. `verifiedStatus`는 항상 `compatibleTarget`이다.
모든 옵셔널 필드가 `null`로 명시된다. `appliedOptions`는 12키 전부 있다.

**깨지면**: 호스트가 플랫폼을 구분해야 하고, 그 순간 "계약"이라는
개념이 사라진다.

소유: [wire-contract](../05-protocol/wire-contract.md)

## I-6. 자기가 만든 프로세스만 다룬다

> 이름이나 경로로 전역 프로세스를 찾아 죽이지 않는다.
> 백엔드 인스턴스가 직접 생성해 보관한 프로세스만 취소·종료 대상이다.

**깨지면**: 사용자의 다른 SANE 프런트엔드나 무관한 프로세스를 죽인다.

소유: [child-process](../03-process-and-io/child-process.md) §8

## I-7. 총 스캔 시간에 상한을 두지 않는다

> 진행률이 계속 오는 한 몇 시간짜리 스캔도 허용한다.
> 상한은 첫 진행률까지와 진행률 사이 유휴 시간에만 둔다.

**깨지면**: 7200 dpi 대형 포맷 스캔이나 다중 노출이 중간에 죽는다.
그리고 USB 전송 중 프로세스를 죽이면 장치가 반쯤 열린 상태로 남는다.

소유: [timeouts-and-watchdog](../03-process-and-io/timeouts-and-watchdog.md)

## I-8. 장치를 필요 이상으로 열지 않는다

> 전용 필름 스캐너는 연속해서 여러 번 열면 다음 획득이 실패할 수 있다.
> capability 토큰이 있는 정상 Color 경로에서는 scan 전 장치 open이 0회다.

**깨지면**: OpticFilm 같은 장치에서 스캔이 간헐적으로 실패한다.
재현이 어렵고 원인을 찾기 어렵다.

소유: [scanimage-invocation](../02-frontend-contract/scanimage-invocation.md) §3

## I-9. 주소가 바뀌어도 같은 장치를 연다

> USB 주소는 장치를 열 때마다 바뀔 수 있다.
> 다중 패스 스캔은 패스마다 현재 주소를 다시 확인한다.
> 제조사·모델이 일치하지 않으면 열지 않는다.

같은 모델 두 대가 붙어 있으면 **거부한다.** 엉뚱한 스캐너를 여는 것보다
실패가 낫다.

**깨지면**: 두 번째 패스부터 실패하거나, 더 나쁘게는 다른 스캐너를 연다.

소유: [device-identity](../02-frontend-contract/device-identity.md)

## I-10. IR 실패가 본 스캔을 무효화하지 않는다

> IR 패스가 실패하면 경고를 남기고 RGB 결과를 반환한다.
> 단 요청했는데 IR 파일이 없으면 3단계 검증이 실패시킨다.

이 두 문장이 모순처럼 보이지만 아니다. `acquireInfraredPass`가
실패를 warnings로 삼키고 `nil`을 돌려주며, `validatedScanResult`가
`options.infraredEnabled && infraredURL == nil`을 오류로 만든다.

즉 **최종적으로는 실패한다.** 중간 단계에서 예외를 던지지 않을 뿐이다.

**깨지면**: IR을 요청했는데 IR 없는 결과가 성공으로 반환되거나,
IR 실패 때문에 정상 RGB 데이터가 버려진다.

소유: [exact-option-contract](../02-frontend-contract/exact-option-contract.md) §5.2

## I-11. libsane을 링크하지 않는다

> 어댑터는 `scanimage` 실행 파일을 자식 프로세스로 부른다.
> SANE 헤더나 라이브러리를 링크하지 않는다.

**깨지면**:

- 프로세스 격리 상실. SANE 백엔드 크래시가 어댑터를 죽인다.
- SANE 교체 가능성 상실.
- GPL 경계의 성격이 바뀐다.

소유: [gpl-compliance](../07-distribution/gpl-compliance.md) §5

**검증 가능하다**: `dumpbin /imports`에 sane이 없어야 한다.

## I-12. GPL 소스를 함께 배포한다

> SANE 바이너리를 배포하면 완전한 대응 소스(패치와 빌드 스크립트 포함)를
> 같은 배포물 안에, 그리고 같은 다운로드 위치에 둔다.

**깨지면**: 라이선스 위반이다.

소유: [gpl-compliance](../07-distribution/gpl-compliance.md)

## I-13. 사용자 동의 없이 시스템을 바꾸지 않는다

> 드라이버 바인딩은 명시적 동의와 사전 경고 뒤에만 한다.
> 무엇을 잃는지 설치 전에 말한다.
> 되돌리는 방법을 함께 안내한다.

**깨지면**: 사용자가 Epson Scan 2를 잃고, 왜 그런지 모르고,
되돌리는 방법도 모른다.

소유: [driver-conflicts](../09-hardware/driver-conflicts.md),
[packaging-and-install](../07-distribution/packaging-and-install.md)

## I-14. 권한을 요구하지 않는다

> `negaflow-scanner-sane.exe`는 `asInvoker`로 실행한다.
> 관리자 권한을 요구하지 않는다.
> 호스트가 사용자 권한으로 실행하고 그것으로 충분해야 한다.

드라이버 바인딩 도구만 예외이며, 그것은 별도 실행 파일이다.

**깨지면**: 호스트가 플러그인을 실행할 수 없거나, 사용자가 매 스캔마다
UAC 프롬프트를 본다.

소유: [signing-and-trust](../07-distribution/signing-and-trust.md) §9

## I-15. 신뢰할 수 없는 입력을 신뢰하지 않는다

> `capabilityToken`은 호스트를 거쳐 돌아온다.
> `scanimage` 출력은 파싱 대상이다.
> TIFF는 외부 파일이다.
>
> 전부 크기 상한, 형식 검증, 안전한 파서를 거친다.

특히 `acquisitionDevice`가 명령줄로 나가므로 인자 주입을 막는 검증이
필요하다(Windows에서 신규).

**깨지면**: 임의 명령 실행 또는 크래시.

소유: [child-process](../03-process-and-io/child-process.md) §4,
[capability-model](../02-frontend-contract/capability-model.md) §5.3

## I-16. 호스트가 준 경로에만 쓴다

> `outputPath`와 그것에서 파생된 IR 경로에만 결과를 쓴다.
> 경로를 정규화하거나 확장자를 바꾸지 않는다.
> 기존 파일을 예상 밖으로 덮어쓰지 않는다.

파일을 연 뒤 `GetFinalPathNameByHandleW`로 최종 경로를 확인한다.
reparse point를 거부한다.

**깨지면**: 사용자 파일이 덮어써지거나, 결과가 예상 밖의 위치에 생긴다.

소유: [exact-option-contract](../02-frontend-contract/exact-option-contract.md) §3.1,
[child-process](../03-process-and-io/child-process.md) §7

## I-17. 실패를 조용히 넘기지 않는다

> 검증에 실패한 파일은 지운다.
> 오류는 error 이벤트와 exit 1로 보고한다.
> "아마 괜찮을 것"으로 진행하지 않는다.

Mock이나 fallback 장치가 없다. 스캐너를 못 찾으면 못 찾은 것이다.

**깨지면**: 사용자가 문제를 늦게 발견하고, 그때는 원인을 알 수 없다.

## I-18. 진단에 민감 정보를 남기지 않는다

> 이미지 픽셀, 전체 로컬 경로, 시리얼 원문, 토큰 원문,
> 환경 변수 덤프를 로그에 쓰지 않는다.

**깨지면**: 사용자가 GitHub 이슈에 로그를 붙이면서 개인정보를 노출한다.

소유: [diagnostics-and-troubleshooting](../08-operations/diagnostics-and-troubleshooting.md) §5

## I-19. 하드웨어 지원을 증거 없이 표시하지 않는다

> `verifiedStatus`는 항상 `compatibleTarget`이다.
> README의 지원 표는 SANE 문서 상태와 실기 검증을 구분한다.
> "장치가 보인다"와 "지원한다"는 다르다.

**깨지면**: 사용자가 지원한다고 믿고 구매하거나 시간을 쓴다.

소유: [validation-matrix](../09-hardware/validation-matrix.md)

## I-20. macOS 동작을 근거 없이 바꾸지 않는다

> Windows 이식 중에 발견한 macOS 코드의 개선점은 별도 작업으로 분리한다.
> 두 플랫폼의 동작이 갈리는 변경은 양쪽에 함께 적용한다.

이 이식에서 발견된 개선 후보:

- 타임아웃 종류를 문자열이 아니라 구조적으로 판정 — **Windows 구현 완료**
  (`process/acquisition.h` `TimeoutKind`). macOS 는 여전히 문자열 검사
- 주소 재시도 판정을 메시지 문자열이 아니라 구조적 이유로
- `parseCapabilities`의 genesys 16-bit 밝기 불일치 (Q-7)
- TIFF 검증에 SAMPLEFORMAT/PLANARCONFIG 추가 (D-10)
- 오류 메시지에 가능한 값 포함 (D-27)
- `--version` / `--license` 출력
- `diagnose` 서브커맨드
- 경로 마스킹 (D-25)
- 소요 시간 로깅

2026-08-04 문서 감사에서 추가로 발견된 것:

- `NEGAFLOW_SCANIMAGE_PATH`를 실행 가능성 검증 없이 사용
  ([environment-and-paths](../03-process-and-io/environment-and-paths.md) §3.1)
- `preferredTransparencySource`의 마지막 폴백이 IR 소스를 배제하지 않음
  ([driver-option-reference](../10-lessons/driver-option-reference.md) §5)
- 출력 TIFF에 ICC/전송함수 태그가 실제로 없는지 미검증
  (spike I-2 §5·6 — 있으면 macOS 결함이다)
- **`SaneOptionDump`가 CRLF 덤프를 파싱하지 못한다** — Swift가 `"\r\n"`을
  한 Character로 보아 줄 분리가 일어나지 않는다. 첫 옵션만 남는다.
  ([option-dump-parser](../02-frontend-contract/option-dump-parser.md) §2.2.1)

**전부 "Windows에서만 고치면 안 되는 것"이다.** 한쪽만 바꾸면 같은 스캐너가
OS에 따라 다르게 동작한다.

단 CRLF 항목은 성격이 다르다. **Windows 구현은 이미 다르게 동작한다** —
그쪽이 옳고 Swift 가 틀렸기 때문이다. LF 입력에서는 두 구현이 완전히
일치하므로 실사용 divergence 가 아니다
([option-dump-parser](../02-frontend-contract/option-dump-parser.md) §2.2.1).

**깨지면**: 두 플랫폼이 서서히 갈라져 결국 별개 제품이 된다.

## 21. 불변식이 아닌 것

혼동을 막기 위해 명시한다. 다음은 **바꿔도 되는 것**이다.

- 구현 언어
- 내부 자료구조
- 로그 형식(민감 정보 규칙만 지키면)
- 타임아웃 수치(측정 근거가 있으면)
- SANE 런타임 전달 방식
- 설치 프로그램 도구
- 백엔드 DLL 배치
- 임시 파일 위치
- 진단 서브커맨드 추가

## 22. 충돌 해결

문서가 서로 어긋나 보이면:

```text
1. 이 문서 (product-invariants)
2. decision-register
3. 주제별 상세 문서
4. open-questions
```

코드와 문서가 어긋나면 **코드가 옳고 문서를 고친다.**
단 코드가 불변식을 위반하고 있다면 코드가 결함이다.
