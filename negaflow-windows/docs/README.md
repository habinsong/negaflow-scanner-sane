# negaflow-scanner-sane — Windows 이식 문서

기준일: 2026-08-04
기준 커밋: c554aaf
대상 독자: 이 플러그인을 Windows로 옮기는 사람

## 0. 이 문서 묶음이 무엇인가

macOS에서 동작 중인 SANE 스캐너 플러그인을 Windows로 옮기기 위한 설계
문서다. **구현 전에 답해야 하는 것**과 **구현 중에 지켜야 하는 것**을 나눠
적었다.

지금 상태 (2026-08-05):

```text
macOS 구현   완성. 실사용 중. 이 문서의 사실 기준.
Windows 구현 순수 로직 이식 진행 중. 실행 파일은 아직 없다.
```

정확한 현황은 [handoff](00-overview/handoff.md) §2가 소유한다.
**이 README의 숫자를 믿지 말고 거기를 본다** — 두 곳에 같은 숫자를 두면
한쪽이 조용히 낡는다.

**코드와 문서가 어긋나면 코드가 옳고 문서를 고친다.**
단 코드가 [product-invariants](99-plan/product-invariants.md)를 위반하고
있다면 코드가 결함이다.

## 1. 처음 읽는 순서

**이어받는 사람은 [handoff](00-overview/handoff.md)부터 읽는다.**
지금 어디까지 왔고 다음이 무엇인지, 그리고 밟으면 안 되는 함정이 거기 있다.

```text
0. 00-overview/handoff.md              ← 이어받는다면 여기부터
1. 00-overview/macos-inventory.md      지금 코드가 무엇을 하는가
2. 99-plan/product-invariants.md       절대 깨면 안 되는 것 20개
3. 10-lessons/field-lessons.md         이미 실패한 시도들
4. 99-plan/roadmap.md                  무엇을 어떤 순서로
5. 99-plan/spike-checklist.md          지금 당장 할 수 있는 실험
```

**3번을 건너뛰지 않기를 권한다.** 이식 중에 "이건 명백히 개선할 수 있는데"로
보이는 다섯 가지가 이미 시도돼 실패한 것들이다.

## 2. 전체 목록

### 00-overview — 사실과 결정

| 문서 | 내용 |
|---|---|
| [macos-inventory](00-overview/macos-inventory.md) | 현재 구현이 무엇을 하는지 파일 단위로. 다른 문서가 "현재 macOS는 X한다"고 할 때의 근거 |
| [handoff](00-overview/handoff.md) | **인수인계.** 현재 상태·다음 작업·함정 |
| [decision-register](00-overview/decision-register.md) | D-01…D-32 결정 단일 출처 |
| [glossary](00-overview/glossary.md) | SANE·필름·Windows 세 어휘가 겹친다. 막히면 여기 |

### 01-sane-runtime — SANE를 어떻게 전달하는가

| 문서 | 내용 |
|---|---|
| [runtime-route-decision](01-sane-runtime/runtime-route-decision.md) | A(MSYS2) / B(WSL2) / C(원격) / D(TWAIN) 중 무엇으로 갈 것인가 |
| [availability](01-sane-runtime/availability.md) | Windows에서 SANE가 실제로 존재하는가. `-A` 파싱의 취약성 |
| [building-sane](01-sane-runtime/building-sane.md) | 우리가 빌드해야 하는 이유와 패치 세트 |
| [usb-transport](01-sane-runtime/usb-transport.md) | libusb, WinUSB, 드라이버 교체의 대가 |
| [remote-saned](01-sane-runtime/remote-saned.md) | 원격 경로를 지원하지 않되 깨뜨리지도 않는 법 |

### 02-frontend-contract — `scanimage`와 어떻게 대화하는가

**이식 코드의 60%가 이 장이다.** 그리고 거의 전부가 순수 함수다.

| 문서 | 내용 |
|---|---|
| [scanimage-invocation](02-frontend-contract/scanimage-invocation.md) | 호출 형태, stdout/stderr 비대칭 |
| [option-dump-parser](02-frontend-contract/option-dump-parser.md) | `-A` 텍스트 파서 |
| [capability-model](02-frontend-contract/capability-model.md) | 덤프 → 능력 판정 |
| [exact-option-contract](02-frontend-contract/exact-option-contract.md) | 정확한 옵션만 적용한다 (I-1의 정본) |
| [backend-quirks](02-frontend-contract/backend-quirks.md) | 백엔드별 분기 16곳 |
| [device-identity](02-frontend-contract/device-identity.md) | 주소가 바뀌어도 같은 장치를 연다 |

### 03-process-and-io — 전면 재작성이 필요한 부분

| 문서 | 내용 |
|---|---|
| [child-process](03-process-and-io/child-process.md) | CreateProcessW, 파이프, Job Object |
| [cancellation](03-process-and-io/cancellation.md) | POSIX 신호가 없는 곳에서 취소하기 |
| [timeouts-and-watchdog](03-process-and-io/timeouts-and-watchdog.md) | 진행률 기반 watchdog |
| [environment-and-paths](03-process-and-io/environment-and-paths.md) | `scanimage` 탐색, 환경 블록, 임시 파일 |

### 04-imaging — 수치가 어긋나면 안 되는 부분

| 문서 | 내용 |
|---|---|
| [numerical-parity](04-imaging/numerical-parity.md) | macOS와 비트 단위로 같아야 한다 (I-4) |
| [tiff-validation](04-imaging/tiff-validation.md) | 산출물 검증 13단계 |
| [exposure-merge](04-imaging/exposure-merge.md) | 다중 노출 병합과 정렬 |

### 05-protocol — 호스트와의 계약

| 문서 | 내용 |
|---|---|
| [wire-contract](05-protocol/wire-contract.md) | 응답 형태 정본. 플랫폼에 따라 바뀌지 않는다 (I-5) |
| [encoding-and-json](05-protocol/encoding-and-json.md) | UTF-8, 개행, base64 |
| [conformance-fixtures](05-protocol/conformance-fixtures.md) | 골든 corpus 설계 |
| [host-requirements](05-protocol/host-requirements.md) | **본체 Windows 문서 요구사항 대조표.** 미충족 1건 |

### 06-build — 언어와 저장소 구조

| 문서 | 내용 |
|---|---|
| [language-decision](06-build/language-decision.md) | C++20 (D-13)과 그 조건 |
| [toolchain-and-layout](06-build/toolchain-and-layout.md) | CMake, vcpkg, 단일 저장소 |
| [porting-map](06-build/porting-map.md) | Swift 함수 하나하나가 어느 C++ 모듈로 가는가 |

### 07-distribution — 배포

| 문서 | 내용 |
|---|---|
| [gpl-compliance](07-distribution/gpl-compliance.md) | GPL 경계와 소스 배포 의무 |
| [packaging-and-install](07-distribution/packaging-and-install.md) | 설치 위치, 도구, 업데이트 |
| [signing-and-trust](07-distribution/signing-and-trust.md) | Authenticode, SmartScreen |

### 08-operations — 운영

| 문서 | 내용 |
|---|---|
| [diagnostics-and-troubleshooting](08-operations/diagnostics-and-troubleshooting.md) | `diagnose` 서브커맨드, 로그 위생 |

### 09-hardware — 실제 장치

| 문서 | 내용 |
|---|---|
| [driver-conflicts](09-hardware/driver-conflicts.md) | WinUSB로 바꾸면 무엇을 잃는가 |
| [validation-matrix](09-hardware/validation-matrix.md) | E1~E7 실기 검증 절차와 릴리스 gate |

### 10-lessons — 경험

**다른 장이 "무엇을 할 것인가"라면, 이 장은 "왜 그렇게 하기로 했는가"다.**

| 문서 | 내용 |
|---|---|
| [driver-option-reference](10-lessons/driver-option-reference.md) | 우리가 보내는 모든 옵션과 그 근거. 안 보내는 것도 |
| [field-lessons](10-lessons/field-lessons.md) | 터진 것 10개, 통한 것 8개 |
| [host-pipeline-contract](10-lessons/host-pipeline-contract.md) | 본체가 우리 출력에 거는 계약 |

### 99-plan — 계획

| 문서 | 내용 |
|---|---|
| [product-invariants](99-plan/product-invariants.md) | **충돌 시 이 문서가 이긴다** |
| [roadmap](99-plan/roadmap.md) | M0~M9와 중단 조건 |
| [test-plan](99-plan/test-plan.md) | L0~L7 테스트 층 |
| [spike-checklist](99-plan/spike-checklist.md) | 미확인 항목 41개와 실행 순서 |
| [open-questions](99-plan/open-questions.md) | Q-1…Q-17 (Q-18 종결), 누가 답할 수 있는지 |

## 3. 목적별 진입점

| 하려는 일 | 읽을 것 |
|---|---|
| 이 작업을 이어받았다 | [handoff](00-overview/handoff.md) |
| 용어를 모르겠다 | [glossary](00-overview/glossary.md) |
| 본체와 호환되는지 알고 싶다 | [host-requirements](05-protocol/host-requirements.md) |
| 이 Swift 파일을 어디로 옮기나 | [porting-map](06-build/porting-map.md) |
| 이 프로젝트가 가능한지 알고 싶다 | [roadmap](99-plan/roadmap.md) §M0, [spike-checklist](99-plan/spike-checklist.md) Gate 0 |
| 지금 당장 뭘 할 수 있나 | [spike-checklist](99-plan/spike-checklist.md) "실행 순서" |
| 옵션 값을 바꾸려 한다 | [driver-option-reference](10-lessons/driver-option-reference.md) |
| 코드가 이상해 보여 고치려 한다 | [field-lessons](10-lessons/field-lessons.md) §18 |
| 결정의 이유를 찾는다 | [decision-register](00-overview/decision-register.md) |
| 왜 색이 이럴까 | [host-pipeline-contract](10-lessons/host-pipeline-contract.md) |
| 테스트를 어떻게 짜나 | [test-plan](99-plan/test-plan.md), [conformance-fixtures](05-protocol/conformance-fixtures.md) |
| 장비가 생겼다 | [validation-matrix](09-hardware/validation-matrix.md) |

## 4. 이 이식의 실제 위험

문서 43개가 다루는 것 중 이 다섯 개가 프로젝트를 죽일 수 있다.

| 위험 | 소유 문서 | 언제 답이 나오나 |
|---|---|---|
| Windows `scanimage`가 바이너리 stdout을 깨뜨린다 | [runtime-route-decision](01-sane-runtime/runtime-route-decision.md) | M0 (30분) |
| SANE가 실제 장치를 열지 못한다 | [usb-transport](01-sane-runtime/usb-transport.md) | M0 (장비 필요) |
| Core Image 로드 결과를 재현할 수 없다 | [numerical-parity](04-imaging/numerical-parity.md) | 지금 (macOS만 필요) |
| 코드 서명을 확보할 수 없다 | [signing-and-trust](07-distribution/signing-and-trust.md) | M0 (조사) |
| 드라이버 되돌리기가 불가능하다 | [driver-conflicts](09-hardware/driver-conflicts.md) | 장비 확보 후 |

**세 번째는 오늘 시작할 수 있다.** Windows 장비도 스캐너도 필요 없다
(spike N-1).

## 5. 문서 규약

```text
기준일 / 기준 커밋   문서 첫머리에 명시
상태                 사실 기록 | 이식 정본 | 구현 계획 | 계획 | 정본
확인 / 미확인        원문을 직접 읽은 것과 그렇지 않은 것을 구분
D-nn                 결정. decision-register가 목록을 소유
Q-nn                 열린 질문. open-questions가 소유
I-nn                 불변식. product-invariants가 소유
S/E/N/I/C/T/U/DC/B/D-n  spike. spike-checklist가 소유
```

문서 사이 충돌 해결 순서:

```text
1. product-invariants
2. decision-register
3. 주제별 상세 문서
4. open-questions
```

### 5.1 정합성 검사

```bash
python3 docs/check-docs.py
```

깨진 링크, 없는 섹션 참조(`§N.M`), 등록되지 않은 `D-nn`/`Q-nn`/`I-nn`,
본문과 결과 표가 어긋난 spike ID, 고아 문서, 빠진 머리말,
파일명 없는 본체 저장소 인용, **낡은 소스 행수**를 잡는다.
의존성 없음. 실패하면 exit 1이라 CI에 붙일 수 있다.

마지막 항목이 특히 중요하다. [macos-inventory](00-overview/macos-inventory.md)의
파일별 행수는 이식 규모 산정의 근거인데, 코드가 바뀌면 **조용히 낡는다.**
실제로 2026-08-04 감사에서 헤더 합계 두 개가 낡아 있었다
(백엔드 4,336→4,581, 테스트 3,220→4,460).

**본체 저장소(`../negaflow/negaflow-windows/docs`) 인용은 링크 검사가 불가능하다.**
그래서 최소한 파일명을 적도록 강제한다 — 본체 README에도 §6이 있고
`10-scanner/plugin-architecture.md`에도 §6이 있어서, 파일을 안 적으면
독자가 엉뚱한 곳으로 간다.

**이 검사가 잡지 못하는 것은 "내용이 코드와 맞는가"다.** 그건 사람이
소스를 읽어야 하고, 실제로 그렇게 해서
[field-lessons](10-lessons/field-lessons.md) §9b의 오류를 찾았다.
문서가 런타임 동작을 주장하면 **실행해서 확인한다.**

## 6. 아직 없는 것

정직하게 적는다. 진행 중인 항목의 숫자는
[handoff](00-overview/handoff.md) §2·§8이 소유한다.

- **Windows에서 한 번도 빌드해본 적이 없다.** MSVC 플래그는 문서 기반이다
- 실행 파일이 없다. `main.cpp`도 없다
- `fixtures/` 디렉터리가 아직 없다 (M1에서 만든다).
  파리티 하네스가 그 자리를 임시로 메운다
- spike 대부분이 미실행이다 — 통과한 것은 이미징 동등성 계열뿐이다
- 실기 검증 장치가 **0대**다
- IR 경로는 macOS에서도 실기 검증되지 않았다

**이 문서들과 코드는 계획과 기반이지 완성품이 아니다.**
