# 용어집

기준일: 2026-08-04
상태: 참고
목적: 이 문서 묶음이 설명 없이 쓰는 용어를 한 곳에 모은다

이 프로젝트는 **세 개의 서로 다른 어휘**가 겹치는 지점에 있다.

```text
SANE / 유닉스 스캐너      backend, dll.conf, saned, SANE_CAP_INACTIVE
필름 스캔 / 사진          Dmin, TPU, IR, flat master, Lineart
Windows 시스템            WinUSB, Job Object, reparse point, Authenticode
```

**어느 한 배경만 가진 사람은 나머지 두 어휘에서 막힌다.**

여기 있는 것은 이 문서 묶음이 **설명 없이 그냥 쓰는** 용어다. 일반적인
용어 사전이 아니므로, 이 프로젝트에서 특별한 뜻을 갖거나 오해를 부르는
것만 담았다.

## 1. SANE

**SANE** (Scanner Access Now Easy)
: 유닉스 계열의 스캐너 API 표준. 표준 자체는 public domain이지만,
  **개별 백엔드 구현은 대부분 GPL**이다. 이 구분이 이 프로젝트의 라이선스
  설계 전체를 결정한다 → [gpl-compliance](../07-distribution/gpl-compliance.md)

**backend** (백엔드)
: 특정 스캐너 제품군을 구동하는 SANE 드라이버. 이 프로젝트가 다루는 것:

  | 이름 | 대상 |
  |---|---|
  | `genesys` | Plustek OpticFilm 등 Genesys 칩 기반 |
  | `epson2` | Epson Perfection / GT 계열 |
  | `epkowa` | Epson 비공식(Image Scan!) 백엔드. 우리는 포함하지 않음 |
  | `coolscan2` / `coolscan3` | Nikon Coolscan LS 계열 |
  | `coolscan` | 구형 Nikon SCSI |
  | `pieusb` / `pie` | Reflecta / PIE PowerSlide |
  | `dll` | 다른 백엔드를 동적 로드하는 메타 백엔드 |
  | `net` | 원격 `saned`에 접속하는 백엔드 |

**frontend** (프런트엔드)
: 백엔드를 호출하는 프로그램. `scanimage`가 그것이고, **이 플러그인은
  프런트엔드를 링크하지 않고 실행 파일로 부른다.**

**`scanimage`**
: SANE 공식 CLI 프런트엔드. 이 플러그인이 자식 프로세스로 띄우는 대상.
  우리 코드의 거의 모든 것이 "이 프로그램에 무엇을 주고 무엇을 받는가"다.

**`-A` (옵션 덤프)**
: `scanimage -A -d <장치>`가 내는 사람용 옵션 목록. **능력 판정 전체가
  이 텍스트 파싱 위에 서 있다.** `--help`와 같은 렌더러를 쓰는 도움말
  덤프이지 인터페이스가 아니라서 **버전 간 형식이 바뀔 수 있다**
  → [availability](../01-sane-runtime/availability.md) §7.2

**`SANE_CAP_INACTIVE`**
: 옵션이 "비활성"이라는 플래그. **"지금 꺼져 있다"가 아니라 대개 "이
  하드웨어에 그 기능 자체가 없다"** 는 뜻이다. 비활성 옵션을 설정하려 하면
  `attempted to set inactive option`으로 스캔이 실패한다.
  → [driver-option-reference](../10-lessons/driver-option-reference.md) §8.2

**`dll.conf`**
: `dll` 백엔드가 어느 백엔드를 로드할지 적은 설정 파일. 백엔드 이름을
  주석 처리하면 그 백엔드가 비활성화된다. macOS에서는 **공용 파일**이라
  플러그인이 조심스럽게 다루지만, Windows에서는 우리 전용이므로 건드리지
  않는다(D-05).

**`saned`**
: SANE 네트워크 데몬. 다른 기계의 스캐너를 `net:` 장치명으로 쓰게 해준다.
  **지원 대상 밖이지만 코드가 깨지지도 않게 한다**(D-03)
  → [remote-saned](../01-sane-runtime/remote-saned.md)

**`.desc` 파일**
: SANE 소스의 `doc/descriptions/`에 있는 장치 목록. `:usbid "0x07b3" "0x130c"`
  형태로 USB ID가 적혀 있고, `status` 필드(Complete/Good/Basic/Minimal/
  Untested)도 있다. D-30이 여기서 USB ID를 추출한다.
  **"SANE가 안다"이지 "동작한다"가 아니다.**

**`pel`**
: SANE 지오메트리 옵션의 픽셀 단위. `mm`와 **섞이지 않는다** —
  coolscan 계열은 `-x`/`-y`가 pel이라 mm 값을 넘기면 36 mm가 36픽셀이 된다.
  변환: `mm * dpi / 25.4`

**shading / calibration**
: 스캔 전 센서 보정 단계. `pieusb`는 이것을 `sane_start` 안에서 동기
  실행해 **첫 진행률이 장시간 없을 수 있고**, 그래서 watchdog을 끈다.

## 2. 필름 스캔

**TPU / Transparency Unit / Transparency Adapter**
: 투과 원고(필름) 스캔용 광원 유닛. 평판 스캐너에서는 뚜껑에 들어 있다.
  `--source` 값으로 노출되며, 이 플러그인은 **투과 소스를 자동 선택**한다.
  `TPU8x10`은 영역이 더 넓지만 초점면이 유리면이라, 필름 홀더용인
  `Transparency Unit`을 우선한다.

**Lineart**
: 1비트 흑백 모드. 우리는 쓰지 않지만 **일부 epson2 기기의 기본 모드**이고,
  그 상태에서는 `--depth`가 비활성이라 능력 판정이 통째로 빈다.
  → [capability-model](../02-frontend-contract/capability-model.md) §2

**IR / 적외선 채널**
: 필름의 은염·색소는 적외선을 통과시키지만 **먼지와 스크래치는 막는다.**
  그래서 IR 패스가 곧 결함 지도가 된다. 흑백 은염 필름에서는 은이 IR을
  막아 무효다.

**RGBI**
: R·G·B·적외선을 **한 프레임**에 담은 SANE 프레임 형식(`SANE_FRAME_RGBI`).
  coolscan3의 `--infrared`가 이것을 내는데, **stock `scanimage`가 이를
  RGB TIFF와 IR TIFF로 분리하지 못한다.** 그래서 coolscan3 IR을 지원
  기능으로 보고하지 않는다.

**Dmin**
: 필름의 최소 밀도 = 노광되지 않은 필름 베이스의 값. 컬러 네거티브의
  주황색 베이스가 그것이다. **negaflow의 색 정확도가 이 값의 실측에
  걸려 있고**, 그래서 플러그인은 장치가 색을 미리 만지지 못하게 한다.
  → [host-pipeline-contract](../10-lessons/host-pipeline-contract.md) §4

**flat master**
: 룩(색감)을 굽지 않은 정직한 중간 결과물. negaflow 본체의 개념이며,
  **플러그인 출력이 그 입력**이다. 플러그인이 "보기 좋게" 만들면 안 되는 이유.

**Digital ICE**
: Kodak(Applied Science Fiction)의 적외선 먼지 제거 기술 상표.
  **상표이므로 우리 기능명으로 쓰지 않는다.** 문서에서는 장치 벤더 기능을
  가리킬 때만 인용한다.

**VueScan / SilverFast**
: 상용 스캔 소프트웨어. **드라이버 충돌의 상대**이자 사용자가 잃을 수 있는
  것이다. 둘 다 자체 드라이버를 쓴다고 알려져 있으나, WinUSB 바인딩 후에도
  동작하는지는 **미확인**(spike U-1) → [driver-conflicts](../09-hardware/driver-conflicts.md)

## 3. Windows

**WinUSB**
: Microsoft 제공 범용 USB 드라이버. libusb가 장치를 열려면 대상 장치가
  이 드라이버(또는 libusbK)에 바인딩돼 있어야 한다. **바인딩하면 벤더
  소프트웨어가 그 장치를 못 쓴다** — 이 프로젝트 UX의 핵심 대가.

**Zadig**
: WinUSB 바인딩을 해주는 GPLv3 GUI 도구. 사용자가 **목록에서 잘못된 장치를
  고르는 사고**가 실제로 보고된다(USB 허브나 키보드를 고르면 그것이 죽는다).

**libwdi**
: Zadig의 기반 라이브러리(LGPLv3). 우리가 내장하면 VID/PID를 지정할 수 있어
  안전하지만, **드라이버 설치 프로그램을 만드는 일**이 된다 → D-09

**usbipd**
: USB 장치를 네트워크로 WSL2에 넘겨주는 도구. B 경로(WSL2)의 전제.
  genesys 장치가 스캔 후 연결이 끊기는 알려진 이슈가 있다(spike U-2).

**MSYS2**
: Windows용 유닉스 도구 배포판. **SANE 패키지를 제공하는 유일한 현실적
  경로**이고 A 경로(D-01)의 기반이다.

**Job Object**
: 프로세스 그룹을 묶어 한꺼번에 관리하는 Windows 커널 객체.
  `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`를 걸면 **어댑터가 강제 종료돼도
  자식 `scanimage`가 남지 않는다.** POSIX 프로세스 그룹의 대응물.

**reparse point**
: 심볼릭 링크·정션 등 경로 재지향 메커니즘. 출력 경로가 이것이면
  **거부한다** — 호스트가 준 경로 밖에 쓰게 될 수 있다(I-16).

**Authenticode / SmartScreen**
: Windows 코드 서명과 평판 기반 경고. macOS의 Developer ID / Gatekeeper에
  대응 → [signing-and-trust](../07-distribution/signing-and-trust.md)

**`asInvoker`**
: 실행 파일 매니페스트의 권한 요청 수준. **관리자 권한을 요구하지 않는다**는
  뜻이고, I-14가 이것을 강제한다.

## 4. macOS (이식 원본 쪽)

**Homebrew keg**
: Homebrew가 패키지를 설치하는 격리된 디렉터리. 이 플러그인은
  **패치된 SANE keg를 최우선**으로 찾고, 같은 keg의 `etc/sane.d`와
  `lib/sane`을 함께 쓴다. **Windows에는 대응 개념이 없어 경로 우선순위를
  다시 설계해야 한다.**

**`lipo` / universal binary**
: 여러 아키텍처를 한 파일에 담는 macOS 도구. **Windows에는 없다** —
  x64와 ARM64가 별도 산출물이다.

**notarize** / **hardened runtime**
: Apple의 배포 전 검사와 런타임 보호 설정. Windows에는 직접 대응물이 없고
  Authenticode + SmartScreen이 그 역할을 나눠 맡는다.

## 5. 이 프로젝트 고유

**호스트 (host)**
: negaflow 본체 앱. 이 플러그인을 자식 프로세스로 실행하는 쪽.
  **Apache-2.0이고 SANE 코드가 0줄이다.**

**어댑터 (adapter)**
: 이 플러그인의 프로토콜 계층. 호스트의 JSON 요청을 `scanimage` 인자로
  바꾸고 결과를 되돌린다.

**`capabilityToken`**
: `capabilities` 응답에 실려 나갔다가 `scan` 요청에 그대로 돌아오는
  불투명 문자열. base64(JSON)이고 **옵션 덤프 원문이 통째로 들어 있어
  수십 KB가 될 수 있다**(상한 1 MiB). 호스트는 해석하지 않는다.
  **신뢰할 수 없는 입력으로 취급한다**(I-15).

**staging**
: 호스트가 결과 파일을 받으려고 지정한 디렉터리. 플러그인은 **거기에만
  쓴다**(I-16). 중간 파일을 그 안에 둬도 되는지가 Q-3다.

**NDJSON**
: 줄 단위 JSON. `scan`의 진행률·결과 이벤트 형식. 한 줄 = 한 이벤트이고
  `\n`으로만 끝난다(`\r\n` 아님).

**정확한 옵션 계약 (exact option contract)**
: "요청한 값을 정확히 적용할 수 없으면 스캔을 시작하지 않는다"는 원칙.
  가장 가까운 값으로 스냅하지 않는다. I-1이자 이 프로젝트의 성격을
  규정하는 규칙 → [exact-option-contract](../02-frontend-contract/exact-option-contract.md)

**골든 픽스처 (golden fixture)**
: macOS 구현이 생성한 기대 출력 파일. Windows 구현이 같은 입력에 같은
  출력을 내는지 기계로 비교한다. **손으로 쓰지 않는다.**
  → [conformance-fixtures](../05-protocol/conformance-fixtures.md)

**spike**
: 답을 모르는 것을 확인하기 위한 짧은 실험. 구현이 아니다.
  → [spike-checklist](../99-plan/spike-checklist.md)

## 6. 혼동하기 쉬운 짝

| A | B | 차이 |
|---|---|---|
| 백엔드 이름 | 모델명 | **모델명은 하드웨어를 식별하지 못한다.** 8200i가 "OpticFilm 8100"으로 보고된다 |
| 비활성(inactive) | 값 없음 | 비활성은 "하드웨어에 그 기능이 없다"에 가깝다 |
| `--negative` | 필름 종류 | coolscan의 `--negative`는 **장치 색 반전 스위치**다. 항상 `no` |
| `--clean-image` | IR 채널 | 백엔드 내부 먼지 제거. **별도 IR 파일이 없다** |
| 미검증 | 미지원 | 시도 안 한 것 vs 시도해도 안 되는 것 |
| `verified` | `compatibleTarget` | 우리는 **항상 후자**를 보고한다(I-19) |
| 능력(capability) | 약속 | 능력은 관측이다. 모델명으로 발명하지 않는다(I-2) |
| 취소 | 타임아웃 | 취소는 사용자 의도, 타임아웃은 watchdog 판정. 오류 분류가 다르다 |
| stall 타임아웃 | 첫 진행률 타임아웃 | 구분해서 판정해야 한다. genesys 재시도가 후자에만 걸린다 |
