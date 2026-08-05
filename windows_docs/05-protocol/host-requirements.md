# 본체 Windows판이 플러그인에 거는 요구사항 — 대조표

기준일: 2026-08-04
상태: 이식 정본 — 미충족 항목이 하나 있다
목적: negaflow 본체 Windows 문서의 요구사항을 이 플러그인 계획과 **한 줄씩 대조**한다

대조 대상(본체 저장소, `../Negaflow/windows_docs`):

- `10-scanner/plugin-architecture.md` (769행)
- `10-scanner/protocol-contract.md` (1,078행)
- `10-scanner/plugin-security-and-lifecycle.md` (1,028행)

관련 문서:

- [wire-contract](wire-contract.md) — 우리가 내는 것
- [timeouts-and-watchdog](../03-process-and-io/timeouts-and-watchdog.md) — §2의 충돌 지점
- [product-invariants](../99-plan/product-invariants.md)

## 0. 왜 이 문서가 필요한가

이 플러그인은 **본체 Windows판과 짝이 되어야만** 의미가 있다. 그런데 두
문서 묶음이 서로 다른 저장소에서 따로 자랐다.

`check-docs.py`는 다른 저장소를 열지 못한다. 즉 **본체 요구사항과의
불일치는 자동으로 잡히지 않는다.** 이 문서가 그 대조를 사람이 한 결과다.

**대조 결과: 26개 요구사항 중 25개 충족, 1개 미충족.**
미충족 항목이 §2이며, 설계 변경이 필요하다.

---

## 1. 충족 — 그대로 가면 되는 것

### 1.1 프로세스 경계

| 본체 요구 | 우리 상태 |
|---|---|
| scanner 구현을 `Negaflow.exe`에 link/load 하지 않음 | I-11. `libsane` 미링크(D-17). `dumpbin /imports`로 검증 가능 |
| JSON/NDJSON + staging file로만 통신 | wire-contract 전체 |
| result image를 file로 전달, stdout에 pixel payload 금지 | 획득 stdout은 파일 핸들 직결. 이미지가 파이프로 안 감 |
| vendor crash/hang을 본체에서 격리 | 별도 프로세스. 백엔드 크래시가 어댑터만 죽인다 |

본체 문서가 `negaflow-scanner-sane.exe`를 **"별도 GPL 배포물"** 로 명시한다.
우리 GPL 경계 설계와 일치한다.

### 1.2 매니페스트와 라우팅

| 본체 요구 | 우리 상태 |
|---|---|
| manifest schema는 **정확히 1** | `manifest.json` `schemaVersion: 1` |
| 모르는 schema는 추측하지 말고 거부 | 호스트 쪽 동작 |
| external ID = `plugin:<pluginId>:<deviceId>` | `id`가 `sane`. 접두사는 호스트가 붙이고 벗김 |
| adapter는 다른 plugin ID가 붙은 routed ID를 받지 않음 | `capabilities <내부 ID>`로 받는다 |
| 실행 파일 PE machine type을 호스트가 확인 | 매니페스트에 아키텍처 필드 불필요 |

### 1.3 프로토콜

| 본체 요구 | 우리 상태 |
|---|---|
| v2는 request ID와 **엄격 증가** sequence | `sequence` 0부터 1씩, `NSLock` 직렬화 |
| UUID format/case 차이가 비교를 깨지 않아야 함 | D-12(원문 반사)로 더 강하게 만족 |
| **v1 omitted-vs-null serialization 일치** | wire-contract §4.2.1 실측 반영 |
| `appliedOptions` 12키 필수, 미적용은 `null` | 커스텀 인코더가 보장 |
| capability token을 호스트가 해석하지 않음 | 불투명 base64. 다음 scan에 그대로 반환 |
| v2 result가 applied options를 **증명** | 요청 ≠ 적용일 수 있음(epson2 높이 정렬) |
| 요청값을 적용 증거로 복사하지 않음 | `appliedScanArea`가 실제 전송값 |

### 1.4 산출물 검증 (본체 `plugin-architecture.md` §14)

| 본체 요구 | 우리 상태 |
|---|---|
| 호스트가 지정한 exact staged path | I-16 |
| regular file, reparse point 아님 | 핸들 기반 검증 |
| non-empty, decodable TIFF, 양수 크기 | 검증 13단계 |
| result width/height와 일치 | 3단계 검증 |
| applied bit depth ↔ decoded bits per component | 검증 |
| color mode ↔ decoded color model | 검증 |
| IR: requested·applied가 true일 때 **필수** | I-10 |
| IR: requested가 false면 존재/flag를 **거부** | 3단계 |
| IR: RGB와 dimensions 일치 | 검증 |
| WIC decode 성공만으로 pixel semantics 증명 안 됨 | D-10(SAMPLEFORMAT/PLANARCONFIG 추가) |

### 1.5 실패 처리

| 본체 요구 | 우리 상태 |
|---|---|
| exit code 0만으로 성공 아님 | I-3 |
| result event만으로도 성공 아님 | I-3 |
| error event가 와도 exit code·trailing event·staged file 확인 | 호스트 쪽. 우리는 error + exit 1 |
| **production discovery 실패 시 Mock fallback 금지** | I-17. Mock 자체가 없다 |

### 1.6 자원 예산

| 본체 요구 | 우리 상태 |
|---|---|
| stdout 4 MiB | 진행률 이벤트 ~160 B. 수백 개 수준 |
| stderr 1 MiB | 옵션 덤프 로깅을 기본으로 끈다 |
| adapter가 event 빈도를 제한 | wire-contract §5.2에 제한 방침 기재 |
| stdout/stderr 동시 drain (pipe deadlock 방지) | child-process §13.2 교착 테스트 |

---

## 2. 미충족 — 명령별 wall-time 상한 (설계 변경 필요)

**이것이 이 대조에서 나온 유일한 실질 충돌이다.**

### 2.1 본체가 정한 상한

`plugin-architecture.md` §11:

| command | 호스트 ceiling |
|---|---:|
| `detect` | **90 s** |
| `capabilities` | **180 s** |
| `scan` | 7,200 s |
| 그 외 | 60 s |

### 2.2 우리 예산이 그것을 넘는다

플러그인의 `utilityProcessTimeout`은 **`scanimage` 호출 하나당** 180 s다.
그리고 한 명령이 `scanimage`를 여러 번 부른다.

```text
detect
  listDevices: -f 시도 (180 s)
             → 실패하면 -L 폴백 (180 s)
  최악 360 s  vs  호스트 90 s          ← 4배 초과

capabilities
  capabilityOptionsDump: for attempt in 0..<3
      각 시도마다
        currentDeviceAddress → listDevices (1~2회)
        base -A            (1회)
        sourceSpecificOptionsDump → 재덤프 -A (1회, 자체 재시도 있음)
      + 시도 사이 0.8 s sleep
  + resolveIdentity → listDevices (1회)
  최악 10회 이상 × 180 s  vs  호스트 180 s   ← 10배 이상 초과
```

**`scanimage` 한 번만 매달려도 detect는 호스트 상한의 2배를 쓴다.**

### 2.3 무슨 일이 일어나는가

호스트가 상한에서 프로세스를 죽인다. 우리 쪽 관점에서는:

- 플러그인이 자기 타임아웃에 도달하기 **전에** 강제 종료된다
- 우리가 준비한 오류 이벤트가 나가지 못한다 → 호스트는 `plugin crashed`로 분류
- 정리 코드가 실행되지 않는다 → `scanimage`가 남을 수 있다
  (Job Object가 최소 안전망이지만, 장치는 반쯤 열린 상태로 남는다)

**즉 진단 품질이 무너지고, 사용자는 "왜 실패했는지" 알 수 없다.**

### 2.4 필요한 변경

명령별 **전체 예산**을 먼저 정하고, 개별 `scanimage` 호출 타임아웃을
거기서 역산한다. 지금은 반대로 되어 있다.

```text
현재: 호출당 180 s 고정, 총합 무제한
필요: 명령 총 예산 → 남은 시간에서 호출당 타임아웃 산출

detect        총 예산 75 s  (호스트 90 s - 여유 15 s)
              -f 에 45 s, 폴백 -L 에 남은 시간
capabilities  총 예산 150 s (호스트 180 s - 여유 30 s)
              시도 3회를 포함한 전체가 이 안에 들어와야 한다
              → 재시도 횟수를 시간 기준으로 줄인다
scan          현행 유지 (진행률 기반 watchdog, 총 상한 없음)
              호스트 7,200 s 가 최종 안전망 — I-7과 정합
```

**남은 예산을 호출마다 계산해 넘기는 구조**가 필요하다. 고정 상수로는
불가능하다.

`scan`만 예외인 것이 중요하다. I-7("총 스캔 시간에 상한을 두지 않는다")은
호스트 7,200 s 안에서 성립하므로 **바꾸지 않는다.**

### 2.5 이 결정의 소유

```text
D-32  명령별 총 예산을 호스트 ceiling에서 역산한다.
      detect 75 s, capabilities 150 s 를 출발점으로 하고
      T-1~T-3 실측 후 확정한다.
      scan 은 현행 유지(진행률 watchdog + 호스트 7,200 s).

      개별 scanimage 호출은 "남은 예산"을 인자로 받는다.
      utilityProcessTimeout 고정 상수는 상한으로만 쓴다.
```

**macOS에도 같은 문제가 있는가?** macOS 호스트가 같은 ceiling을 쓰는지는
이 저장소에서 알 수 없다. 쓴다면 macOS도 이미 같은 위험을 안고 있고,
그렇다면 I-20에 따라 양 플랫폼에 함께 적용한다.
→ [open-questions](../99-plan/open-questions.md) Q-17

---

## 3. 확인한 항목 — 세 건 모두 종결 (2026-08-04)

### 3.1 detect 응답의 장치 ID 중복 → **중복 제거 필수**

본체 `protocol-contract.md` §5.3이 답을 준다.

> 같은 detect response 안의 중복 routed ID는 **첫 항목만 남기는 현재 동작**이 있습니다.
> Windows 구현 목표는 duplicate를 diagnostics에 기록하고 **plugin defect로 취급**하는 것입니다.

즉 호스트는 중복을 조용히 넘기지 않고 **우리 결함으로 기록**한다.
현재 macOS 코드는 `-f`/`-L` 파싱 결과를 중복 제거 없이 반환한다.

```text
결정: detect 응답을 내기 전에 id 기준으로 중복을 제거한다.
      호스트와 같은 의미론을 쓴다 — 첫 항목이 이긴다.
      제거한 항목이 있으면 stderr 진단에 남긴다(개수만, 경로 없이).

이유: 호스트가 어차피 첫 항목만 남긴다. 우리가 먼저 정리하면
      결과는 같고 "plugin defect" 기록만 사라진다.
```

거부하지 않는 이유: 중복이 나오는 상황(백엔드가 같은 하드웨어를 여러
경로로 노출)에서 **스캔은 정상 동작한다.** 사용자를 막을 이유가 없다.

픽스처: 같은 devname이 두 번 나오는 `-L`/`-f` 출력.

### 3.2 ID 불안정성 고지 → **이미 충족. 조치 불필요**

본체 `plugin-architecture.md` §7:

> serial이 없으면 reconnect 뒤 ID가 달라질 수 있음을 명시

**`serialNumber`의 부재가 곧 그 명시다.** 본체 `protocol-contract.md`
§5.3이 `serialNumber`를 `string/null`로 정의하고, §5.4가 detect가
증명하지 않는 것을 따로 나열한다. 호스트는 serial 없는 장치의 ID를
영구 identity로 쓰지 않도록 이미 설계돼 있다.

```text
결정: v2 wire를 바꾸지 않는다. idStability 같은 필드를 추가하지 않는다.
      우리는 serialNumber 를 계속 null 로 낸다 — 그것이 신호다.
```

**추가로 확인된 것**: 본체가 `usbVendorID`/`usbProductID`도
`string/null`로 정의한다. 우리가 셋 다 null인 것은 스키마 위반이 아니다.

### 3.3 오류 범주 매핑 → **현행 8개 유지. v3까지 격차 수용**

본체 `protocol-contract.md` §8.5:

> adapter는 가능하면 stable code를 전달해야 하지만 **현재 event schema에는
> error code field가 없습니다. v3 후보입니다.**

우리는 이미 `errorDescription`이 `"<code>: <message>"` 형태라 **stable
code를 메시지 접두사로 전달하고 있다.** 호스트 요구("가능하면 전달")를
현재 스키마 안에서 만족하는 유일한 방법이다.

```text
결정: 코드 8개를 그대로 유지한다. Windows에서 늘리지 않는다.

이유: 코드 문자열은 message 안에 있고, 호스트가 그 문자열을 사용자에게
      보여준다. Windows만 코드를 늘리면 같은 실패가 OS에 따라 다른
      문구로 보인다 — I-5 위반이다.
```

**격차는 인정하고 기록한다.** `permission denied`, `invalid artifact`,
`protocol violation`, `capability stale`이 `ioFailure`/`unsupportedOption`에
뭉쳐 있다. 이것을 푸는 것은 **양 플랫폼 동시 변경 + v3 code 필드**이며
이 이식의 범위가 아니다.

그때까지 지킬 것:

```text
같은 코드 안에서는 메시지가 원인을 구분할 수 있게 쓴다.
D-27(가능한 값을 오류에 포함)이 그 방향이다.
```

### 3.4 본체 `protocol-contract.md` §8.5가 우리 감사 결과를 확증한다

부수적으로 얻은 것. 본체가 적어 둔 terminal error 예시가 **정확히 5개 키**다.

```json
{"type":"error","protocolVersion":2,"requestID":"…","sequence":8,"message":"Scanner disconnected"}
```

`phase`/`fraction`/`width`/… 가 없다. 이것은
[wire-contract](wire-contract.md) §4.2.1의 실측(합성 인코더는 nil 키를
생략한다)과 **완전히 일치한다.** 두 저장소가 독립적으로 같은 형태를
기록하고 있다.

### 3.3 오류 범주 매핑

본체 `plugin-architecture.md` §13이 **18개 stable category**를 정의한다. 우리 `ScannerError.Code`는
8개뿐이다.

```text
우리:  notConnected, busy, unsupportedOption, driverConflict,
       ioFailure, cancelled, timeout, unknown

본체:  plugin not installed / approval required / identity changed /
       manifest·protocol unsupported / architecture unavailable /
       device not found·disconnected / device busy / permission denied /
       capability changed·stale token / unsupported requested option /
       warming up·user intervention / transfer failed / timeout /
       cancelled / protocol violation / invalid artifact /
       publication conflict / plugin crashed
```

**대부분은 호스트가 판정하는 범주다**(plugin not installed, approval
required, architecture unavailable 등). 어댑터가 낼 수 있는 것만 대응하면 된다.

| 본체 범주 | 우리 코드 |
|---|---|
| device not found/disconnected | `notConnected` |
| device busy | `busy` |
| unsupported requested option | `unsupportedOption` |
| permission denied | 현재 `ioFailure`에 섞임 |
| transfer failed | `ioFailure` |
| invalid artifact | `ioFailure` |
| timeout | `timeout` |
| cancelled | `cancelled` |
| capability changed/stale token | 현재 `unsupportedOption`에 섞임 |
| protocol violation | 현재 `unsupportedOption`에 섞임 |

**세 개가 뭉쳐 있다.** 호스트가 사용자 재시도 가능성과 data safety를
범주로 판단하므로, `unsupportedOption` 하나로 뭉치면 "옵션을 바꿔보세요"와
"플러그인을 다시 설치하세요"가 같게 보인다.

v2 wire에 코드 필드가 없어(§8 알려진 한계) 지금은 메시지 문자열이 전부다.
**v3 후보**이며, 그 전까지는 메시지를 구분 가능하게 쓴다.

---

## 4. 본체가 아직 정하지 않은 것 (우리에게 영향)

`plugin-architecture.md` §22의 미확정 항목 중 우리와 관련된 것:

| 본체 미확정 | 우리 영향 |
|---|---|
| IR plane의 bit depth/color model을 v2보다 강하게 고정할 v3 필요성 | 우리 IR 출력 형식이 그 결정에 묶인다 |
| user-scope와 machine-scope plugin root 동시 출시 여부 | D-19(사용자 범위만)와 직결 |
| signed official plugin update의 approval 자동 승계 | D-22(자동 업데이트 없음)와 직결 |
| driver-specific recovery 전 graceful cancel 최소 시간 | C-2 spike, 취소 유예 시간 |

**이 넷은 우리가 정할 수 없다.** 본체 결정을 기다리거나, 우리 쪽 기본값을
정하고 본체에 알린다.

## 5. 릴리스 gate 대조

본체 `plugin-architecture.md` §20이 요구하는 것 중 **우리가 증명해야 하는 것**:

- [ ] protocol conformance corpus pass → [conformance-fixtures](conformance-fixtures.md)
- [ ] cancel/timeout/process-tree cleanup pass → [cancellation](../03-process-and-io/cancellation.md)
- [ ] artifact transaction crash tests pass → [tiff-validation](../04-imaging/tiff-validation.md)
- [ ] 해당 adapter architecture package signed → [signing-and-trust](../07-distribution/signing-and-trust.md)
- [ ] license/SBOM/notices 검토 → [gpl-compliance](../07-distribution/gpl-compliance.md)
- [ ] 실제 hardware/driver/OS matrix pass → [validation-matrix](../09-hardware/validation-matrix.md)
- [ ] reported/applied/artifact provenance 일치 → [exact-option-contract](../02-frontend-contract/exact-option-contract.md)
- [ ] production에서 implicit Mock fallback 없음 → I-17

**"main app이 scanner 없이 import/develop/export를 완전히 수행"** 은 본체
책임이며, 우리에게는 **플러그인 실패가 본체를 죽이면 안 된다**는 요구로
돌아온다.

## 6. 이 대조를 유지하는 법

본체 문서가 바뀌면 이 표가 낡는다. 그리고 `check-docs.py`는 그것을 잡지 못한다.

```text
본체 10-scanner/ 가 갱신되면 이 문서를 다시 대조한다.
최소한 릴리스 전에 한 번.
대조한 날짜와 본체 커밋을 여기에 기록한다.
```

대조 이력:

| 날짜 | 본체 기준 | 결과 |
|---|---|---|
| 2026-08-04 | `10-scanner/` 4개 문서 | 26개 중 25개 충족, §2 미충족 발견 |
