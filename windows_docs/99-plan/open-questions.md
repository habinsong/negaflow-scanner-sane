# 열린 질문

기준일: 2026-08-04
상태: 미해결 — 답이 나오면 결정으로 승격하고 여기서 지운다
목적: 아직 답이 없는 것을 한 곳에 모아 **누가 답할 수 있는지**를 명시한다

관련 문서:

- [spike-checklist](spike-checklist.md) — 실험으로 닫는 것
- [decision-register](../00-overview/decision-register.md) — 이미 닫힌 것
- [roadmap](roadmap.md) — 언제 닫아야 하는지

## 0. spike와 무엇이 다른가

```text
spike           우리가 실험하면 답이 나온다        → spike-checklist
open question   실험만으로는 안 되거나
                판단·협의·정책이 필요하다          → 이 문서
```

경계가 흐린 항목은 양쪽에 다 적고 서로 참조한다.

각 질문에 **"답이 무엇을 바꾸는가"** 를 적었다. 그것이 우선순위다.
아무것도 바꾸지 않는 질문은 답할 필요가 없다.

## 1. 답할 주체별 요약

| 주체 | 질문 |
|---|---|
| negaflow 호스트 팀 | Q-1, Q-2, Q-3, Q-4 |
| 우리 (설계 판단) | Q-5, Q-6, Q-7, Q-11, Q-12 |
| upstream / 커뮤니티 | Q-9, Q-10, Q-15, Q-16 |
| 조사 후 우리 판단 | Q-8, Q-13, Q-14 |

**Q-1과 Q-3은 M0에서 물어본다.** 답을 기다리는 데 시간이 들고, 늦게 알수록
비싸다.

---

## Q-1. 호스트가 Authenticode 서명을 요구하는가

**질문**: negaflow 본체가 플러그인 실행 파일의 서명을 검증하는가?
필수인가 선택인가?

**왜 열려 있나**: macOS는 Developer ID + notarization이 사실상 필수였다.
Windows 호스트가 같은 정책을 가질지는 본체 구현에 달렸고, 이 저장소에서는
알 수 없다.

**답이 바꾸는 것**:

```text
필수  → 인증서 확보가 M0의 차단 항목이다. 확보 못 하면 배포 불가.
선택  → 서명 없이 베타를 낼 수 있다. SmartScreen 경고만 감수한다.
```

**닫는 방법**: 호스트 팀에 직접 질의. spike D-1과 한 세트다.

**관련**: [signing-and-trust](../07-distribution/signing-and-trust.md) §12,
[roadmap](roadmap.md) M0

---

## Q-2. 호스트가 매니페스트와 실행 파일 이름에 거는 제약

**질문**: `manifest.json`의 `executable` 필드가 확장자 있는 이름
(`negaflow-scanner-sane.exe`)을 그대로 받아들이는가? 호스트가 플랫폼별로
이름을 유추하는가?

**왜 열려 있나**: macOS 매니페스트는 확장자 없는 이름을 쓴다. 호스트가
그 문자열을 그대로 실행하는지, 아니면 가공하는지 이 저장소에서 확인할 수 없다.

**답이 바꾸는 것**: 매니페스트 생성 로직과 설치 레이아웃.
[wire-contract](../05-protocol/wire-contract.md)는 "매니페스트에서
`executable`만 바뀐다"를 전제하는데, 그 전제 자체가 미확인이다.

**닫는 방법**: 호스트 팀 질의 또는 본체 `ScannerPluginManifest` 확인.

---

## Q-3. 중간 파일을 어디에 만드는가

**질문**: 다중 패스 스캔의 중간 TIFF와 IR 파일을 호스트가 준 staging
디렉터리 안에 만들어도 되는가?

**왜 열려 있나**: 호스트가 staging 디렉터리에 **정확히 두 파일만** 있을 것을
검증한다면, 중간 파일이 그 검증을 깨뜨린다.

**선택지**:

| 안 | 내용 |
|---|---|
| A | 호스트가 추가 파일을 허용함을 확인하고 그대로 쓴다 |
| B | staging 아래 하위 디렉터리 `\.negaflow-sane-work\` |
| C | `%TEMP%`를 쓴다(현재 macOS와 같음). 공간·성능 문제 감수 |

**권장: B.** 호스트가 두 파일을 검증하더라도 하위 디렉터리는 방해하지 않고,
정리도 staging 삭제로 함께 된다.

**답이 바꾸는 것**: 다중 노출·IR 경로의 파일 배치 전부. 12패스 7200 dpi에서는
중간 파일이 수십 GB가 될 수 있어 **디스크 위치가 성능에도 영향을 준다**(spike E-4).

**닫는 방법**: 호스트 팀 질의. 답이 없으면 B로 진행한다(가장 방어적).

**관련**: [wire-contract](../05-protocol/wire-contract.md) §10,
[environment-and-paths](../03-process-and-io/environment-and-paths.md) §7

---

## Q-4. 알 수 없는 서브커맨드의 종료 코드를 바꿔도 되는가

**질문**: 현재 알 수 없는 서브커맨드는 usage를 stderr에 내고 특정 코드로
끝난다. `exit 2`로 바꾸는 것이 호스트에 영향을 주는가?

**왜 열려 있나**: 호스트가 종료 코드를 어떻게 해석하는지 모른다.
wire 계약의 일부인지 아닌지가 불분명하다.

**답이 바꾸는 것**: 작다. 다만 I-5(wire를 바꾸지 않는다) 적용 대상인지가
갈린다. 대상이면 양 플랫폼에 함께 적용해야 한다.

**닫는 방법**: 호스트 팀 질의.

**관련**: [wire-contract](../05-protocol/wire-contract.md) §8

---

## Q-5. 원격 saned를 정식 지원하기로 하면 백엔드 이름을 어떻게 뽑는가

**질문**: `net:host:genesys:libusb:001:002` 같은 중첩 장치명에서 실제
백엔드 이름을 뽑을 것인가?

**현재 상태**: 뽑지 않는다. 첫 `:` 앞을 백엔드로 보므로 원격 장치는
`net`으로 판정되고 **백엔드별 처리를 전혀 받지 못한다.** 결과적으로 원격
epson2 스캐너는 내부 감마가 켜진 채 스캔될 수 있다.

**이것을 코드로 막지 않는 이유**: 막으려면 중첩 장치명을 파싱해야 하고,
그 파싱이 틀리면 **로컬 경로까지 영향을 준다.** 지원 대상 밖 경로 때문에
지원 대상 경로를 위험에 빠뜨리지 않는다.

**답이 바꾸는 것**: D-03을 뒤집는 일이며 새 결정 항목이 된다.

```text
effectiveBackendName(deviceString):
    "net:"로 시작하면 → 호스트 부분을 건너뛴 다음 토큰
    아니면            → 첫 ":" 앞
```

**닫는 방법**: 원격 지원 요구가 실제로 생길 때까지 열어 둔다.
**지금 답할 필요가 없는 질문이다.**

**관련**: [remote-saned](../01-sane-runtime/remote-saned.md) §5

---

## Q-6. genesys 16-bit 톤 억제의 근거는 무엇인가

**질문**: `supportsHardwareToneAdjustments = !(genesys && 16-bit)`의
근거가 upstream 어디에 있는가?

**왜 열려 있나**: 코드에 이유가 적혀 있지 않다. 실기 관측으로 추정된다.

**정황 증거는 있다**: `--brightness`/`--contrast`는 sane-backends 1.0.32에서
제거됐고(릴리스 노트 genesys: "Removes lineart and image enhancement
emulation support"), 애초에 하드웨어가 아니라 소프트웨어 후처리였다.
16-bit raw에서는 걸렸더라도 이득이 0이다.

**그러나 이 정황이 "왜 하필 16-bit에서만"을 설명하지 못한다.**

**답이 바꾸는 것**: 분기를 유지할지 정리할지. 그리고 Q-7의 답.

**닫는 방법**: `backend/genesys/` 소스 조사. 못 찾으면 **"실기 관측 기반,
근거 미문서화"로 명시하고 유지한다.** 근거 없이 제거하지 않는다.

**관련**: [backend-quirks](../02-frontend-contract/backend-quirks.md) §1.3,
[driver-option-reference](../10-lessons/driver-option-reference.md) §10

---

## Q-7. 능력 응답과 검증의 유일한 불일치를 어떻게 처리하는가

**질문**: `parseCapabilities`는 genesys 16-bit 예외를 적용하지 않고
`resolveMedia`만 적용한다. 결과적으로 능력 응답에는 brightness 범위가
나타나지만, 16-bit 스캔에서 그 값을 보내면 2단계에서 거부된다.

**선택지**:

| 안 | 내용 | 대가 |
|---|---|---|
| 1 | 현재 동작 그대로 이식 | 사용자가 컨트롤을 조정하려다 거부당한다 |
| 2 | `parseCapabilities`에도 예외를 넣고 `disabledReasons["brightness"]`에 이유를 적는다 | 동작이 개선되지만 macOS와 능력 응답이 달라진다 |

**권장: 2번을 macOS와 Windows 양쪽에 동시에 적용한다.** 한쪽만 바꾸면
같은 스캐너가 OS에 따라 다른 컨트롤을 보여준다(I-20 위반).

**답이 바꾸는 것**: macOS 코드 변경이 이 이식 프로젝트에 포함되는지.
포함되면 별도 PR과 회귀 테스트가 필요하다.

**닫는 방법**: Q-6의 답을 먼저 얻고, macOS 변경 승인을 받는다.

**관련**: [capability-model](../02-frontend-contract/capability-model.md) §3.10

---

## Q-8. MSYS2 패키지를 재배포할 때 "필요한 파일"의 경계는 어디인가

**질문**: `scanimage.exe`가 끌고 오는 의존 중 실제로 필요한 것은 무엇인가?
poppler, curl, libxml2가 정말 필요한가?

**왜 중요한가**: poppler와 libieee1284가 **GPL이다.** 재배포하면 그 소스도
제공해야 한다(D-15). poppler는 PDF 출력용이고 우리는 PDF를 만들지 않는다.
libieee1284는 병렬 포트 스캐너용이고 그 백엔드를 포함하지 않는다.
**둘 다 제거 가능성이 높다.**

**답이 바꾸는 것**: 배포물 크기, GPL 소스 제공 범위, 재빌드 configure 플래그.

**닫는 방법**: D-06 재빌드에서 `--without-*` 조합을 시험한다.
M6에서 확인한다.

**관련**: [gpl-compliance](../07-distribution/gpl-compliance.md) §3,
[building-sane](../01-sane-runtime/building-sane.md) §11

---

## Q-9. MSYS2가 `--disable-locking`을 쓴 이유는 무엇인가

**질문**: MSYS2 SANE 패키지가 왜 장치 잠금을 껐는가? 그 빌드에서 두
프로세스가 같은 장치를 열면 무슨 일이 일어나는가 — 무해한 실패인가,
하드웨어 상태 손상인가?

**왜 열려 있나**: 잠금 디렉터리 경로가 POSIX 전제라 Windows에서 안 되기
때문일 가능성이 높지만 **미확인**이다.

**답이 바꾸는 것**: 동시 실행 방어를 우리가 얼마나 해야 하는지.
macOS는 자기 세션만 관리하면 됐다(I-6). 잠금이 없으면 사용자가 다른 SANE
프런트엔드를 동시에 돌릴 때 우리가 막을 수단이 없다.

**"무해한 실패"면 오류 메시지 분류만 추가하면 된다. "상태 손상"이면
설치 문서에 경고가 필요하다.**

**닫는 방법**: MSYS2 PKGBUILD 확인 + spike U-5(동시 열기 실패 문구).

### 답 — **상태 손상이다** (2026-08-06, 실기)

`--disable-locking` 을 쓴 이유는 여전히 모르지만, 그것이 무엇을 뜻하는지는
확인했다. 잠금이 있든 없든 **`usbscan.sys` 는 배타 접근을 강제하지 않는다.**
`FILE_SHARE` 를 0 으로 줘도 두 번째 열기가 성공한다 — 같은 프로세스에서도,
교차 프로세스에서도.

그래서 "무해한 실패"가 아니다. 두 스캔이 같은 파이프에 전송을 섞어 넣고,
그렇게 망가진 스캐너는 **전원을 껐다 켜기 전까지 돌아오지 않는다**
(cancellation §10 의 C-2).

**우리가 막는다.** `ProcessOwnership::beginScanSession` 이 장치별 이름 붙은
뮤텍스를 쥐고, 이미 쥐고 있으면 `busy` 로 거절한다. 우리 어댑터끼리는 그것으로
충분하다. 사용자가 **다른 SANE 프런트엔드**를 동시에 돌리는 것까지는 막을 수
없으므로, 그건 설치 문서에 경고로 남긴다.

**관련**: [building-sane](../01-sane-runtime/building-sane.md) §11,
[usb-transport](../01-sane-runtime/usb-transport.md) §8

---

## Q-10. upstream에 패치를 제출할 것인가, 제출한다면 누가

**질문**: MinGW 패치와 (필요하다면) binary stdout 수정을 sane-backends
upstream에 제출할 것인가?

**왜 열려 있나**: 기술적 판단이 아니라 시간·유지보수 약속의 문제다.
제출하면 리뷰 대응과 후속 유지가 따라온다.

**답이 바꾸는 것**:

```text
제출하고 병합됨  → 장기적으로 우리 패치 세트가 줄어든다
                   D-18(--all-options-json)의 전제도 바뀐다
제출 안 함        → 매 SANE 릴리스마다 패치를 리베이스한다
```

**닫는 방법**: M6에서 패치 세트가 확정된 뒤 판단한다.

### 결론 — 내지 않는다 (2026-08-06)

**upstream 에 제출하지 않는다.** 패치를 이 저장소에서 유지한다.

이유는 기술이 아니라 범위다. 제출하면 리뷰 대응과 후속 유지가 따라오고,
그것은 이 프로젝트가 하려는 일이 아니다. 매 SANE 릴리스마다 리베이스하는
비용은 받아들인다 — 패치가 일곱 개이고 그중 다섯은 20줄 아래다.

라이선스는 문제가 되지 않는다. 이 저장소가 GPL-2.0-or-later 라 SANE 의
파생물을 그대로 담을 수 있고, `sane-runtime/` 에 원본 해시와 레시피와 패치가
다 있어 같은 바이너리를 재현할 수 있다. Apache-2.0 인 negaflow 본체와는
프로세스로 분리돼 있다 —
[gpl-compliance](../07-distribution/gpl-compliance.md) §6.

아래는 패치 세트의 성격 기록이다. 나중에 마음이 바뀌면 출발점으로 쓴다.

### 패치 세트 (2026-08-06)

전문: [sane-runtime/SOURCES.md](../../sane-runtime/SOURCES.md).
성격이 셋으로 갈린다.

| 패치 | 성격 | 제출 가치 |
| --- | --- | --- |
| 001 | MSYS2 것을 그대로 씀 | 이미 upstream 밖에서 유지된다 |
| 002 binary stdout | Windows 이식 결함 | **높다.** 3줄, `_setmode` 하나 |
| 003 test 백엔드 빌드 | Windows 이식 결함 | 보통. `_pipe`/`fcntl` 가드 |
| 004 UsbDk opt-in | 우리 사정 | 낮다. UsbDk 는 upstream 이 권하지 않는다 |
| 005 usbscan 백엔드 | **새 기능** | **가장 높다.** Windows 에서 드라이버 교체 없이 스캐너를 쓰게 한다 |
| 006 디버그 출력 segfault | Windows 이식 결함 | **높다.** `localtime(&tv.tv_sec)` 한 줄 |
| 007 취소 | Windows 이식 결함 | **높다.** `SIGBREAK` + 스레드 안전성 |

002·006·007 은 "Windows 에서 명백히 깨진 것"이라 리뷰가 짧을 것이다. 006 은
`SANE_DEBUG_*` 를 켜면 어떤 백엔드든 죽는 것이고, 007 은 취소가 스캐너를
망가뜨리는 것이다 — 둘 다 재현 절차가 한 줄이다.

005 는 규모가 다르다. `sanei_usb` 에 세 번째 백엔드를 더하는 일이고, 유지
약속이 따라온다. 다만 **Windows 에서 SANE 을 쓰는 모든 사람에게 의미가 있다** —
지금은 Zadig 로 드라이버를 바꿔야 하고, 바꾸면 제조사 소프트웨어를 잃는다.


**관련**: [building-sane](../01-sane-runtime/building-sane.md) §11,
[gpl-compliance](../07-distribution/gpl-compliance.md) §5

---

## Q-11. 4 GB TIFF 한계에 닿으면 어떻게 하는가

**질문**: 120 포맷(6×9) 고해상도 스캔은 약 25500 × 17000 × 6 ≈ **2.6 GB**다.
표준 TIFF는 4 GB를 넘을 수 없다. 다중 노출 병합 결과가 그 한계에 닿으면?

**현재 상태**: macOS에서 이 조합이 실제로 동작하는지 **확인되지 않았다.**

**책임 경계가 갈린다**:

```text
scanimage가 만드는 파일   → 우리 제어 밖
병합 결과를 우리가 쓸 때   → 우리 책임
```

**선택지**:

| 안 | 대가 |
|---|---|
| BigTIFF로 쓴다 | 호스트가 읽을 수 있어야 한다 → **프로토콜 변경 수준** |
| 그 조합을 능력에서 제외한다 | 대형 포맷 사용자를 잃는다 |
| 압축을 쓴다 | 불확실한 완화. 무손실 압축률이 예측 불가 |

**답이 바꾸는 것**: 능력 보고(해상도 상한)와 TIFF 쓰기 경로.
현재 검증 단계는 **BigTIFF를 거부한다** — 즉 지금은 "제외" 쪽에 서 있다.

**닫는 방법**: macOS에서 해당 크기를 실제로 만들어 본다(장비 불필요, 합성
가능). 그 다음 호스트가 BigTIFF를 읽는지 질의한다.

**관련**: [tiff-validation](../04-imaging/tiff-validation.md) §8

---

## Q-12. gray 출력의 `MINISWHITE`를 어떻게 다루는가

**질문**: `scanimage`가 gray를 `PHOTOMETRIC_MINISWHITE`로 내는 백엔드가
있는가?

**왜 중요한가**: `MINISWHITE`는 0이 흰색이다. `MINISBLACK`과 픽셀 의미가
**반대**다. IR 채널의 밀도 의미가 뒤집히면 본체의 IR 결함 제거가 정확히
반대로 동작한다 — 결함이 아닌 곳을 복원하고 결함을 남긴다.

**현재 macOS 코드는 둘을 구분하지 않는다**(`colorSpace.model == .monochrome`만
본다). ImageIO 내부 처리가 불투명하다.

**권장: Windows에서는 MINISWHITE를 거부한다.**

**답이 바꾸는 것**: 거부로 끝날지, 변환 규칙이 필요할지.

**닫는 방법**: spike I-1. IR을 내는 백엔드가 실기에 있어야 한다 —
현재 개발 환경에서는 IR이 노출되지 않으므로 **장비 확보에 걸려 있다.**

**관련**: [tiff-validation](../04-imaging/tiff-validation.md) §3.5

---

## Q-13. Windows on ARM을 어디까지 지원하는가

**질문 셋**:

```text
① GitHub Actions에 ARM64 Windows 러너가 있는가 (spike B-3)
② clangarm64 크로스 빌드로 SANE를 만들 수 있는가
③ Zadig/libwdi가 ARM64 드라이버를 설치할 수 있는가
```

**왜 열려 있나**: macOS는 universal binary(lipo)로 한 파일이면 끝났다.
Windows는 **x64와 ARM64가 별도 산출물**이고, 세 층(어댑터·SANE·드라이버)이
각각 ARM64를 지원해야 한다.

**③이 실패하면 ①②가 성공해도 소용없다.** 드라이버를 바인딩할 수 없으면
장치를 열 수 없다.

**답이 바꾸는 것**: 지원 아키텍처 선언. ARM64를 빼면 CI·배포·검증 부담이
절반이 된다.

**닫는 방법**: ③을 먼저 조사한다(가장 싸고 가장 결정적).

**관련**: [toolchain-and-layout](../06-build/toolchain-and-layout.md) §10,
[runtime-route-decision](../01-sane-runtime/runtime-route-decision.md) §9

---

## Q-14. 설치 중 GPL 고지를 어떻게 표시하는가

**질문**: 설치 프로그램에서 "동의합니다" 체크박스를 요구할 것인가?

**왜 열려 있나**: GPL은 **사용에 동의를 요구하지 않는다.** 재배포에만
조건이 붙는다. "동의합니다"를 요구하면 GPL을 EULA처럼 제시하는 것이고,
이는 라이선스의 성격을 잘못 전달한다.

**권장**: "동의합니다" 대신 **"라이선스를 확인했습니다"** 또는 단순 표시.

**답이 바꾸는 것**: 설치 UI 문구. 작지만 라이선스 커뮤니티에서 지적받는 지점이다.

**닫는 방법**: D-20(설치 도구)이 정해질 때 함께 정한다.

**관련**: [gpl-compliance](../07-distribution/gpl-compliance.md) §7

---

## Q-15. SANE 설치를 재배치 가능하게 만들 수 있는가

**질문**: `--libdir`/`--sysconfdir`을 상대 경로 기반으로 빌드해, 설치
위치가 바뀌어도 백엔드와 설정을 찾게 할 수 있는가?

**왜 중요한가**: 사용자 범위 설치(D-19)라 경로에 사용자 이름이 들어간다.
빌드 시점에 절대 경로를 박으면 **빌드 머신의 경로가 배포물에 남는다.**

대안은 환경 변수(`SANE_CONFIG_DIR`, 백엔드 검색 경로)로 매번 지정하는
것인데, 그 경로에 **spike E-2의 함정**이 있다 — SANE가
`SANE_CONFIG_DIR`를 `:`로 분리하는 검색 경로로 다루면 `C:\...`의 `C:`가
잘린다.

**답이 바꾸는 것**: 환경 변수 구성 방식과 E-2의 심각도.
재배치 가능하게 만들 수 있으면 E-2를 우회할 수 있다.

**닫는 방법**: M6 재빌드에서 시험. `sanei/sanei_config.c` 확인.

### E-2 의 함정은 없었다. 다른 함정이 있다 (2026-08-06, 실기)

`SANE_CONFIG_DIR` 는 잘리지 않는다. `C:\sane-build\cfg2` 처럼 드라이브 문자가
든 경로를 그대로 읽는다. 같은 디렉터리에서 `dll.conf` 한 줄만 바꿔 장치가
나타나고 사라지는 것으로 확인했다.

**대신 두 가지를 지켜야 한다.**

```text
.conf 를 $SANE_CONFIG_DIR 에 **직접** 둔다     — sane.d 하위에 두면 안 읽는다
없는 디렉터리를 가리키면 내장 경로로 되돌아가지 않는다 — 조용히 장치 0개가 된다
```

그리고 백엔드 DLL 쪽에 별도의 함정이 있다(E-1). `dll.c` 는 Windows 에서
접두사 `cygsane-` 와 접미사 `-%u.dll` 로 찾고, `HAVE_DLOPEN` 이 없으면 DLL 을
열 방법 자체를 갖지 못한다. 둘 다 만족시켜야 백엔드가 로드된다.

**그래서 답은 "환경 변수로 충분하다"이다.** `--libdir` 을 상대 경로로 만드는
작업은 하지 않는다. 빌드 시점 절대 경로가 배포물에 남는 문제는
`SANE_CONFIG_DIR` 로 덮어써서 피하고, 백엔드는 `cygsane-` 이름으로 실행 파일
옆에 둔다. 실기에서 그 구성으로 스캔까지 확인했다.

**관련**: [environment-and-paths](../03-process-and-io/environment-and-paths.md) §9,
[building-sane](../01-sane-runtime/building-sane.md) §11

---

## Q-16. `test` 백엔드를 개발 빌드에만 넣는 방법

**질문**: 별도 패키지로 낼 것인가, 빌드 플래그로 가를 것인가?

**왜 필요한가**: `test` 백엔드가 있으면 **하드웨어 없이 end-to-end
테스트가 가능하다.** 이식 프로젝트에서 이 가치는 크다 — 특히 M0에서
장비를 기다리는 동안.

**왜 릴리스에 넣으면 안 되는가**: `detect`에 가짜 장치가 나타난다.
I-17("Mock이나 fallback 장치가 없다")과 정면으로 충돌한다.

**답이 바꾸는 것**: CI 구성과 M3/M5의 테스트 전략. 가상 `scanimage.exe`로
대체 가능한 부분이 많으므로 **차단 항목은 아니다.**

**닫는 방법**: M6 빌드 구성 시 결정.

### 가상 `scanimage` 로 충분하다 (2026-08-06)

`test` 백엔드를 릴리스에 넣을 이유가 없어졌다. 하드웨어 없이 확인해야 할 것을
전부 `windows/tests/virtual_scanimage.cpp` 가 해냈다.

```text
plugin_smoke   detect → capabilities → scan, 진행률, IR, 교착, stdout 분리
epson_smoke    Epson 인자 계약 17검사 — 소스별 지오메트리, TPU8x10,
               --film-type / --color-correction / --gamma-correction 순서,
               -A 캐싱, 획득 선택자
```

가상 프로그램은 우리가 만든 것이라 시나리오를 원하는 대로 만들 수 있고
(`stall`, `fail`, `stale-once`, `bigout`, `epson`), 무엇보다 **`detect` 에 가짜
장치가 나타나지 않는다** — I-17 과 충돌하지 않는다.

`test` 백엔드는 개발 빌드에서만 쓴다. `003-test-backend-on-mingw.patch` 는
그 백엔드가 mingw 에서 **빌드되게** 하는 것이고, 배포 여부와는 별개다.
배포 패키지의 `dll.conf` 에서 빼면 된다.

**관련**: [building-sane](../01-sane-runtime/building-sane.md) §11,
[test-plan](test-plan.md) §4

---

## Q-17. macOS 호스트도 같은 명령별 ceiling을 쓰는가

**질문**: negaflow macOS판도 `detect` 90초 / `capabilities` 180초 상한을
적용하는가?

**왜 중요한가**: 적용한다면 **macOS도 이미 같은 위험을 안고 있다.**
플러그인의 `utilityProcessTimeout`(호출당 180초)이 호스트 상한을 넘고,
`capabilities`는 `scanimage`를 10회 이상 부를 수 있다
([host-requirements](../05-protocol/host-requirements.md) §2).

지금까지 문제가 보고되지 않은 이유는 **정상 경로가 빠르기 때문**일 것이다
(`-f` 한 번, `-A` 한두 번). 상한에 닿는 것은 장치가 매달릴 때뿐이고,
그때는 어차피 실패한다 — 다만 **실패 방식이 "진단 가능한 오류"가 아니라
"플러그인이 죽음"이 된다.**

**답이 바꾸는 것**: D-32를 양 플랫폼에 적용할지(I-20), Windows에만 적용할지.

**닫는 방법**: 호스트 팀 질의 또는 macOS `ScannerPluginHost` 확인.

**관련**: D-32, [timeouts-and-watchdog](../03-process-and-io/timeouts-and-watchdog.md)

---

---|
| A | 호스트가 SANE 플러그인의 성질을 알고 처리한다(현행 추정) |
| B | v3에 `idStability` 같은 필드를 추가한다 |

**답이 바꾸는 것**: 호스트가 장치 목록을 캐시하거나 "같은 스캐너"로
기억하는 UX를 만들 때 잘못된 전제를 갖는지 여부.

**닫는 방법**: 호스트 팀 질의. v2 wire 변경이 아니므로 급하지 않다.

---

## 2. 질문을 닫는 절차

```text
1. 답을 얻는다
2. 결정이면 → decision-register에 D-nn으로 추가하고 소유 문서에 근거를 쓴다
   사실이면 → 해당 주제 문서에 반영한다
3. 이 문서에서 항목을 지운다
4. 그 항목을 참조하던 문서의 링크를 정정한다
```

**4번을 빠뜨리면 다음 사람이 없는 질문을 찾아간다.**
`grep -rn "Q-nn" windows_docs/`로 확인한다.

## 3. 답이 나와 닫힌 질문

| ID | 결론 | 날짜 |
|---|---|---|
| Q-18 | 불안정 ID 고지는 **이미 충족**. `serialNumber` 부재가 그 신호다. v2 wire 변경 없음 | 2026-08-04 |

근거: 본체 `10-scanner/protocol-contract.md` §5.3·§5.4
→ [host-requirements](../05-protocol/host-requirements.md) §3.2

## 4. 답할 필요가 없다고 판단한 질문

지금은 없다.

"답할 필요 없음"으로 판정하면 **지우지 말고 이 절로 옮긴다.**
왜 답하지 않기로 했는지가 나중에 필요해진다. Q-5가 그 후보다 —
원격 지원 요구가 실제로 생기기 전에는 답할 이유가 없다.
