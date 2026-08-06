# 결정 등록부

기준일: 2026-08-04
상태: 정본 — 결정의 단일 출처. 상세 근거는 소유 문서에 있다
목적: 문서 전체에 흩어진 `D-nn` 결정을 한 곳에서 조회한다

충돌 해결 순서(product-invariants §22):

```text
1. product-invariants
2. decision-register        ← 이 문서
3. 주제별 상세 문서
4. open-questions
```

## 0. 사용법

**이 문서는 요약이고, 근거는 소유 문서에 있다.** 결정의 이유가 필요하면
소유 문서를 읽는다. 결정이 무엇인지만 필요하면 여기서 끝난다.

상태 표기:

| 상태 | 뜻 |
|---|---|
| **확정** | 지금 이대로 구현한다 |
| **조건부** | 명시된 spike 결과에 따라 확정 또는 폐기 |
| **미결** | 아직 결정하지 않았다. 소유자가 정해질 때까지 구현하지 않는다 |
| **폐기** | 한때 결정이었으나 뒤집혔다. 기록으로 남긴다 |

**결정을 바꾸려면 이 표의 행을 고치고 소유 문서를 함께 고친다.**
한쪽만 고치면 다음 사람이 두 문서를 보고 어느 쪽이 최신인지 모른다.

## 1. 전체 목록

| ID | 결정 | 상태 | 소유 문서 |
|---|---|---|---|
| D-01 | 1차 경로는 A(MSYS2 기반 재배포) | 조건부 (S-1, S-2) | [runtime-route-decision](../01-sane-runtime/runtime-route-decision.md) §4 |
| D-02 | B(WSL2)는 명시적 대체 경로로만 문서화 | 확정 | [runtime-route-decision](../01-sane-runtime/runtime-route-decision.md) §4 |
| D-03 | C(원격 saned)는 지원 대상 밖, 코드로 막지는 않음 | 확정 | [remote-saned](../01-sane-runtime/remote-saned.md) §4 |
| D-04 | D(SANEWinDS/TWAIN)는 이 저장소 범위 밖 | 확정 | [runtime-route-decision](../01-sane-runtime/runtime-route-decision.md) §4 |
| D-05 | Windows 빌드는 `dll.conf`를 수정하지 않는다 | 확정 | [environment-and-paths](../03-process-and-io/environment-and-paths.md) §8 |
| D-06 | 자체 재빌드한 SANE 런타임을 포함한다 | 확정 | [building-sane](../01-sane-runtime/building-sane.md) §10 |
| D-07 | 빌드는 CI에서, tarball SHA-256과 툴체인 고정 | 확정 | [building-sane](../01-sane-runtime/building-sane.md) §10 |
| D-08 | `NEGAFLOW_SCANIMAGE_PATH` 재정의를 유지한다 | 확정 | [building-sane](../01-sane-runtime/building-sane.md) §10 |
| D-09 | 드라이버 바인딩 도구 — Zadig 안내로 시작, libwdi로 전환 | **폐기** (드라이버를 바꾸지 않는다) | 이 문서 §2 |
| D-10 | Windows TIFF 검사는 macOS보다 엄격하다 | 확정 | [tiff-validation](../04-imaging/tiff-validation.md) §3.4 |
| D-11 | 1차 구현은 스칼라. SIMD는 동등성 증명 이후 | 확정 | [exposure-merge](../04-imaging/exposure-merge.md) §7 |
| D-12 | `requestID`는 파싱 후 재직렬화하지 않고 원문 반사 | 확정 | [wire-contract](../05-protocol/wire-contract.md) §5.4 |
| D-13 | 1차 구현 언어는 C++20 | 확정 (재검토 조건 있음) | [language-decision](../06-build/language-decision.md) §7 |
| D-14 | 단일 저장소 유지. `windows/` 하위 + 루트 `fixtures/` | 확정 | [toolchain-and-layout](../06-build/toolchain-and-layout.md) §5.3 |
| D-15 | poppler·libieee1284 의존을 제거 시도, 불가 시 소스 배포 | 확정 | [gpl-compliance](../07-distribution/gpl-compliance.md) §3 |
| D-16 | 소스 아카이브를 설치물 안에 포함 + 릴리스 페이지 병치 | 확정 | [gpl-compliance](../07-distribution/gpl-compliance.md) §4.2 |
| D-17 | 어댑터는 `libsane`을 링크하지 않는다 | 확정 | [gpl-compliance](../07-distribution/gpl-compliance.md) §5 |
| D-18 | `--all-options-json` 패치를 v2에 도입하지 않는다 | 확정 | [gpl-compliance](../07-distribution/gpl-compliance.md) §5 |
| D-19 | 1차 릴리스는 사용자 범위 설치만 | 확정 | [packaging-and-install](../07-distribution/packaging-and-install.md) §5 |
| D-20 | 설치 프로그램은 NSIS 로 만든 단일 exe | **확정** (2026-08-06) | [packaging-and-install](../07-distribution/packaging-and-install.md) §5.1 |
| D-21 | 드라이버 바인딩을 설치와 분리 | 확정 | [packaging-and-install](../07-distribution/packaging-and-install.md) §7.1 |
| D-22 | 1차 릴리스에 자동 업데이트 없음 | 확정 | [packaging-and-install](../07-distribution/packaging-and-install.md) §11 |
| D-23 | SANE 런타임 바이너리 전체를 서명 | 확정 | [signing-and-trust](../07-distribution/signing-and-trust.md) §5 |
| D-24 | 번들 `scanimage.exe`는 서명 검증, 사용자 지정은 경고만 | 확정 | [signing-and-trust](../07-distribution/signing-and-trust.md) §9 |
| D-25 | 오류 메시지의 절대 경로를 마스킹 | 확정 | [diagnostics](../08-operations/diagnostics-and-troubleshooting.md) §5.2 |
| D-26 | 스캔 중 시스템 절전 방지 | 확정 | [diagnostics](../08-operations/diagnostics-and-troubleshooting.md) §8.3 |
| D-27 | 거부 오류에 "무엇이 가능한가"를 포함 | 확정 | [diagnostics](../08-operations/diagnostics-and-troubleshooting.md) §9 |
| D-28 | Epson Perfection 사용자에게 권하지 않고 경고 | 확정 | [driver-conflicts](../09-hardware/driver-conflicts.md) §5 |
| D-29 | 드라이버 변경 전 현재 드라이버 정보를 기록 | 확정 | [driver-conflicts](../09-hardware/driver-conflicts.md) §8 |
| D-30 | 빌드 시 `.desc`에서 USB ID를 추출해 내장 | 확정 | [driver-conflicts](../09-hardware/driver-conflicts.md) §11 |
| D-31 | SCSI 스캐너를 Windows 지원 범위에서 제외 | 확정 | [validation-matrix](../09-hardware/validation-matrix.md) §6 |
| D-32 | 명령별 총 예산을 호스트 ceiling에서 역산 | 조건부 (T-1~T-3) | [host-requirements](../05-protocol/host-requirements.md) §2.5 |

## 2. D-09 — 드라이버 바인딩 도구 (이 문서가 소유)

> **폐기됨 (2026-08-06, 실기 검증).** 드라이버를 바꾸지 않는다. 이 절의 나머지는
> 왜 그 길을 걸었는지 남겨두는 기록이다.
>
> 스캐너 제조사 패키지가 붙이는 마이크로소프트 still-image 클래스
> 드라이버(`usbscan.sys`)가 사용자 모드에 raw USB 를 열어준다. `sanei_usb` 에
> 백엔드를 하나 더 붙여 그것을 쓰면 **드라이버 교체·관리자 권한·재부팅이
> 전부 필요 없고**, SilverFast 와 VueScan 도 계속 동작한다. OpticFilm 8100
> 실기로 확인했다 — 장치 열거, 옵션 덤프, 캘리브레이션, 600~7200 dpi 스캔.
>
> 그래서 이 결정이 다루던 위험(사용자가 Zadig 에서 잘못된 장치를 고르는 사고,
> libwdi 의 서명·권한·롤백)이 통째로 사라졌다. D-29(드라이버 정보 기록)의
> 실질 비용도 함께 사라졌다 — 바인딩하는 시점이 없다.
>
> **덤으로 확인된 것**: WinUSB 로 바꿨어도 이 길이 더 나았을 것이다. libusb 의
> Windows 백엔드는 `WinUsb_ResetPipe` 뿐이라 장치 리셋이 없고, genesys 가
> `sane_close` 에서 기대는 USB 리셋을 제공하지 못한다.
>
> 근거와 실측: [runtime-route-decision](../01-sane-runtime/runtime-route-decision.md)
> §4.4b, [sane-runtime/SOURCES.md](../../sane-runtime/SOURCES.md)

다른 결정과 달리 D-09는 소유 문서가 없어 여기서 정의한다.
[runtime-route-decision](../01-sane-runtime/runtime-route-decision.md) §8이
근거를 소유하고, 결정 자체는 이 문서에 있다.

```text
D-09  1차 릴리스는 Zadig 안내 방식으로 시작한다.
      다음 중 하나가 참이 되면 libwdi 내장으로 전환한다.

      - 사용자가 잘못된 장치를 바인딩한 사고가 보고된다
      - DC-2(되돌리기 재현성)에서 안내 방식으로는 복구가 불가능한
        장치가 다수 확인된다

      전환 시점과 무관하게 D-29(드라이버 정보 기록)는 만족해야 한다.
```

### 2.1 두 안의 대조

| 방식 | 장점 | 단점 |
|---|---|---|
| Zadig 안내 | 우리가 드라이버를 건드리지 않는다. 책임 경계가 명확 | 사용자가 GUI에서 잘못된 장치를 고를 수 있다. USB 허브나 입력 장치를 고르는 사고가 실제로 보고된다 |
| libwdi 내장 | 대상 VID/PID를 우리가 지정. 사고 위험 낮음 | LGPLv3 준수, 드라이버 설치 권한, 서명, 롤백 UX를 전부 우리가 진다 |

### 2.2 왜 안전한 쪽(libwdi)으로 바로 가지 않는가

`runtime-route-decision` §8은 **안전을 이유로 libwdi를 권장**한다.
그 권장은 옳지만, libwdi 내장은 **드라이버 설치 프로그램을 만드는 일**이고
서명·권한·롤백·Windows 버전 대응이 전부 따라온다.

1차 릴리스의 목표는 "스캔이 된다"이지 "드라이버 관리 도구를 만든다"가 아니다.
D-21이 이미 드라이버 바인딩을 설치와 분리했으므로, 나중에 바꿔 끼울 수 있다.

**단 D-29(현재 드라이버 정보 기록)는 Zadig 안내 방식에서도 만족해야 한다.**
안내 방식에서는 우리가 기록할 시점이 없으므로, 진단 서브커맨드가 바인딩
**전에** 정보를 덤프하도록 만든다. 이게 D-09를 조건부로 두는 실질 비용이다.

## 3. 서로 얽힌 결정

한 결정을 뒤집으면 함께 흔들리는 것들이다.

### 3.1 D-01(A 경로)이 폐기되면

```text
D-01 폐기 → B(WSL2)로 전환
  ├─ D-06 (자체 SANE 빌드)      배포판 SANE를 쓰게 되어 무의미해진다
  ├─ D-07 (CI 빌드)             함께 무의미
  ├─ D-23 (SANE 서명)           우리가 배포하지 않으므로 무의미
  ├─ D-09 (드라이버 바인딩)      usbipd로 성격이 완전히 바뀐다
  ├─ D-28 (Epson 경고)          여전히 유효
  └─ D-31 (SCSI 제외)           WSL2에서는 재검토 여지가 생긴다
```

### 3.2 D-17(libsane 미링크)이 뒤집히면

```text
D-17 폐기
  ├─ I-11 불변식 위반           → product-invariants를 먼저 고쳐야 한다
  ├─ D-18 (--all-options-json)  무의미해진다
  ├─ GPL 경계 재검토 필수         프로세스 분리 = aggregation 논거가 사라진다
  ├─ macOS 구현도 함께 바꿀지 결정  I-20
  └─ 크래시 격리 대체 수단 필요     백엔드 크래시가 어댑터를 죽인다
```

**이 넷을 전부 답하지 않으면 뒤집지 않는다.** gpl-compliance §5가
이 조건을 명시한다.

### 3.3 D-13(C++20)이 재검토되면

```text
재검토 조건 (셋 중 하나)
  - 팀에 C++ 유지 역량이 없다
  - N-1 실패로 비트 동일을 포기 → FP 제어의 가치가 크게 줄어든다
  - 보안 검토에서 C++ 메모리 안전 위험이 수용 불가

영향
  ├─ D-11 (스칼라/FP 제어)      C#이면 FP 제어 수단이 줄어든다
  ├─ D-14 (단일 저장소)          빌드 체계가 바뀐다
  └─ 라이브러리 선택 전부 (RapidJSON, libtiff 직접 사용)
```

### 3.4 D-20(설치 도구) — 정해졌다

NSIS. MSI 를 만들지 않는다. 사용자 범위 설치라 시스템 설치 관리자에 등록할
이유가 없고, §5.2 의 요건 중 MSI 여야만 되는 것이 없다.

D-16(소스 아카이브 포함)이 설치물을 키운다는 제약은 실측으로 해소됐다.
배포물 15 MB 가 LZMA solid 로 **5.1 MB** 가 된다.

## 4. 결정이 아닌 것 — 자유롭게 바꿔도 되는 것

product-invariants §21과 같은 목록이다. 여기서도 명시한다.

```text
내부 자료구조
로그 형식 (민감 정보 규칙만 지키면)
타임아웃 수치 (측정 근거가 있으면)
백엔드 DLL 배치
임시 파일 위치
진단 서브커맨드 추가
```

**이것들을 바꾸는 데 이 문서의 행이 필요하지 않다.**

## 5. 폐기된 결정

현재 없다.

폐기가 생기면 **행을 지우지 않고** 상태를 `폐기`로 바꾸고 이유를 적는다.
"왜 그 길을 택하지 않았는가"가 다음 사람에게 필요한 정보다.
[field-lessons](../10-lessons/field-lessons.md)가 같은 원칙으로 쓰였다.

## 6. 정정 이력

```text
2026-08-04  availability.md §7.3의 참조를 D-03 → D-17로 정정.
            문맥은 libsane 직접 링크 여부인데 D-03(원격 saned)을
            가리키고 있었다.
```

```text
2026-08-04  §1 표의 "같음" 항목 14개를 명시적 링크로 교체.
            표만 보고는 어느 문서인지 알 수 없었고, 자동 검사도
            불가능했다. 이제 check-docs.py 가 31개 행의 §참조를
            전부 확인한다.
```

**이 종류의 오류를 잡는 것이 `check-docs.py` 3번 검사다** — `D-nn`이
이 표에 없는 채로 다른 문서에서 참조되면 실패한다. 반대로 **여기 있는
결정이 어느 문서에도 안 쓰이는 것은 잡지 못한다.** 결정을 폐기할 때는
`grep -rn "D-nn" windows_docs/`로 참조처를 직접 확인한다.
