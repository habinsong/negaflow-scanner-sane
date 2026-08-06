# upstream 에 낼 패치

여기 있는 것은 **sane-backends upstream 에 제출할 수 있는 형태**로 다듬은
패치다. `sane-runtime/patches/` 의 것들과 내용은 같지만 다음이 다르다.

- upstream `master` 기준으로 다시 만들어 fuzz 없이 적용된다
- 커밋 메시지가 영어이고, 재현 절차와 실측값이 들어 있다
- 한 커밋에 한 파일만 건드린다

기준: `f498f59` (2026-08-06 시점의 `master`)

## 무엇을 내는가

| 파일 | 고치는 것 | 크기 |
| --- | --- | --- |
| `0001-scanimage-write-image-data-to-stdout-in-binary-mode-.patch` | Windows 에서 이미지가 stdout 을 지나며 깨진다 | 14줄 |
| `0001-sanei_init_debug-do-not-pass-a-non-time_t-to-localti.patch` | `SANE_DEBUG_*` 를 켜면 프론트엔드가 죽는다 | 16줄 |
| `0001-scanimage-make-cancellation-work-on-Windows.patch` | 취소가 스캐너를 망가뜨린다 | 31줄 |

셋 다 **Windows 에서 명백히 깨진 것**이고 재현 절차가 한 줄이다. 다른
플랫폼의 동작은 바뀌지 않는다 — 전부 `#ifdef _WIN32` 또는 `#ifdef SIGBREAK`
안에 있다.

## 내지 않는 것

| 패치 | 왜 |
| --- | --- |
| `001-fix-build-on-mingw` | MSYS2 것을 그대로 쓴다. 이미 upstream 밖에서 유지된다 |
| `003-test-backend-on-mingw` | 낼 만하지만 위 셋보다 급하지 않다 |
| `004-usbdk-on-windows` | 우리 사정이다. upstream 은 UsbDk 를 권하지 않는다 |
| `005-usbscan-backend` | 아래 참조 |

`005` 는 `sanei_usb` 에 세 번째 백엔드를 더하는 일이라 규모가 다르다.
Windows 에서 SANE 을 쓰는 모든 사람에게 의미가 있지만 — 지금은 Zadig 로
드라이버를 바꿔야 하고, 바꾸면 제조사 소프트웨어를 잃는다 — 유지 약속이
따라온다. **먼저 sane-devel 에 의도를 알리고 반응을 보는 것이 순서다.**
새 백엔드는 그렇게 하라고 upstream 이 안내한다.

## 어떻게 내는가

GitLab merge request 가 주 경로다. `sane-devel` 메일링 리스트는 논의 채널이고,
보내려면 구독해야 한다.

```bash
# 1. https://gitlab.com/sane-project/backends 를 fork
# 2. 패치 하나마다 브랜치 하나
git clone https://gitlab.com/<계정>/backends.git
cd backends
git checkout -b windows-debug-segfault
git am ../0001-sanei_init_debug-do-not-pass-a-non-time_t-to-localti.patch
git push -u origin windows-debug-segfault
# 3. GitLab 웹에서 merge request 를 연다
```

**셋을 한 MR 에 묶지 않는다.** 고치는 것이 서로 다르고, 하나가 논의에
걸리면 나머지가 함께 멈춘다.

## 검증 상태

세 패치가 얹힌 상태로 OpticFilm 8100 실기에서 확인한 것:

```text
스캔          600~7200 dpi 전부. 600 dpi 전면적이 3,030,277 바이트
연속 스캔     8/8
취소          6,890 ms 에 곱게 끝나고 다음 스캔이 바로 된다
디버그 출력   SANE_DEBUG_GENESYS=5 로 8만 줄을 받아도 죽지 않는다
```

단 그 확인은 1.4.0 트리에서 했다. `master` 에는 **fuzz 없이 적용되는 것까지만**
확인했다 — `master` 는 이 autoconf(2.73)로 `configure.ac:824` 에서 자체
오류가 나 mingw 빌드가 되지 않는다. MSYS2 의 `001` 패치가 따로 필요하다.
MR 을 열면 upstream CI 가 그 부분을 대신 봐 줄 것이다.
