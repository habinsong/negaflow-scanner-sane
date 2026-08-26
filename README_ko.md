<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">macOS용 negaflow SANE 필름 스캐너 플러그인</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/ko/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="웹사이트"></a>
  <a href="#요구-사항"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 이상"></a>
  <a href="negaflow-mac/Package.swift"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift 5.9 이상"></a>
  <a href="manifest.json"><img src="https://img.shields.io/badge/protocol-v2-4B5563" alt="negaflow 스캐너 프로토콜 v2"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0--or--later-6E7781" alt="GPL 2.0 이상 라이선스"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <strong>한국어</strong> ·
  <a href="README_ja.md">日本語</a> ·
  <a href="README_zh-Hans.md">简体中文</a> ·
  <a href="README_fr.md">Français</a> ·
  <a href="README_de.md">Deutsch</a>
</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/ko/">웹사이트</a> ·
  <a href="https://habinsong.github.io/negaflow-site/ko/supported-scanners/">지원 스캐너</a> ·
  <a href="https://habinsong.github.io/negaflow-site/ko/faq/">FAQ</a>
</p>

---

**negaflow-scanner-sane**은 SANE에서 사용할 수 있는 필름 스캐너를
[negaflow](https://github.com/habinsong/negaflow)에 연결합니다. <br>
>`scanimage`를 실행해 스캐너가 보고한 옵션을 읽고, 장치 정보와 기능, 진행 상황, <br>
>TIFF 경로를 negaflow 스캐너 프로토콜 v2로 전달합니다.

별도의 스캔 화면을 제공하는 앱은 아닙니다. 설치하고 승인한 뒤 negaflow의 **스캐너불러오기**에 사용하는 플러그인입니다.

플러그인과 본체는 서로 다른 프로그램입니다. SANE 관련 코드는 모두 GPL-2.0-or-later인 이 저장소에 있으며,<br>
Apache-2.0인 **negaflow** 와는 다른 별도 프로세스, CLI 인자, 파이프와 JSON으로만 통신합니다.

## 기능

- `scanimage -L`로 스캐너 찾기
- 장치가 현재 내놓는 `scanimage -A` 결과로 스캔 항목 구성
- 요청한 값을 가까운 기본값으로 바꾸지 않는 프리뷰와 본 스캔
- 결과를 넘기기 전에 해상도, 색상 모드, 비트 심도, 크기와 TIFF 형식 확인
- 백엔드가 필요한 범위를 보고할 때만 mm 단위 스캔 영역 사용
- 백엔드가 실제로 제공할 수 있을 때만 별도 적외선 채널 획득
- 적외선 패스에 본 스캔과 같은 감마 테이블과 초점을 실어, 필름 베이스가 잘리지 않고 두 패스의 초점면이 일치
- `--scan-exposure-time`이 필요한 노출 계획을 모두 지원할 때만 하드웨어 다중 노출 사용
- 현재 플러그인 인스턴스가 실행한 `scanimage` 프로세스만 취소



## 요구 사항

- 현재 negaflow와 Homebrew 설치 경로 기준 macOS 14.0 이상
- negaflow
- 일반 스캐너 경로는 Homebrew 기본 `sane-backends`
- 별도 SANE 패치 경로만 macOS 26 이상
- 소스에서 빌드할 때만 Swift 5.9 이상

설치 안내는 현재 negaflow와 Homebrew가 함께 지원되는 macOS 14 이상을 기준으로 합니다.

## 설치

### 1. 손쉬운 설치

Xcode Command Line Tools가 없다면 먼저 설치합니다.

```bash
xcode-select --install
```

설치 파일은 네 가지입니다. macOS 26을 쓸 수 없는 경우가 아니라면 `macos26` 쪽을 받습니다.
패치판 SANE 빌드가 여기에 들어 있고, Nikon Coolscan과 Epson 적외선 채널을 쓰게 해 주는 것이
그 빌드입니다. `opticfilm-macos14` 쪽은 그 빌드를 설치할 수 없는 macOS 14·15를 위한 것입니다.

| 설치 파일 | SANE 경로 | 플러그인 바이너리 |
|---|---|---|
| `negaflow-scanner-sane-1.1.0-macos26-arm64-installer.dmg` | 패치판 SANE, macOS 26 이상 | `arm64` 전용 |
| `negaflow-scanner-sane-1.1.0-macos26-universal-installer.dmg` | 패치판 SANE, macOS 26 이상 | `arm64` + `x86_64` |
| `negaflow-scanner-sane-1.1.0-opticfilm-macos14-arm64-installer.dmg` | OpticFilm, macOS 14 이상 | `arm64` 전용 |
| `negaflow-scanner-sane-1.1.0-opticfilm-macos14-universal-installer.dmg` | OpticFilm, macOS 14 이상 | `arm64` + `x86_64` |

`macos26` DMG에서는 `Install negaflow Scanner.pkg`, `opticfilm-macos14` DMG에서는
`Install negaflow Scanner for OpticFilm.pkg`를 실행합니다.

`macos26` 판은 공식 SANE 1.4.0 소스를 `sane-backends-negaflow`로 빌드한 뒤 같은 플러그인을
설치합니다. 적용되는 패치는 셋입니다.

| 패치 | 바뀌는 것 |
|---|---|
| Coolscan 깊이 목록 | upstream `coolscan2`/`coolscan3` 할당 수정 |
| `epson2` 스캔 높이 | Epson 평판이 보고하는 스캔 높이를 바로잡습니다 |
| `epson2` 적외선 | `SANE_FRAME_IR` 차단을 풀어, Epson 필름 평판이 별도 적외선 패스를 낼 수 있게 합니다 |

`opticfilm-macos14` 판은 Homebrew 기본 `sane-backends`를 설치하며 위 패치는 들어가지 않습니다.<br>
설치에는 인터넷 연결과 관리자 암호가 필요하며, 기존 Homebrew가 있으면 그대로 사용합니다.

두 설치본 모두 macOS 14·15에서 Coolscan을 강제로 차단하지는 않습니다. stock SANE으로 동작할 수도
있지만 할당 수정이 없으므로, 지원하는 패치 경로는 `macos26` 설치본입니다.

이후 upstream에는 적어도 LS-5000 펌웨어 1.03에서 필요한 Coolscan3
load/eject/reset 매개변수 초기화도 반영됐습니다. 이 변경은 의도적으로 최소 패치 범위에
넣지 않았으므로, 패치판에서도 LS-5000의 필름 로드·배출·리셋은 미검증이며 실패할 수 있습니다.

설치가 끝나면 negaflow를 다시 실행하고 **스캐너 불러오기**에서 플러그인 정보를 확인한 뒤 승인합니다.<br><br>
**그냥 간단하게 윗 손쉬운 방법으로 설치후 negaflow 를 실행하시고, 승인 버튼 한번 누르면 끝납니다.**

---
### 2. Homebrew와 SANE 수동 설치

Homebrew가 없다면 현재 공식 설치 명령을 실행합니다.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

이 명령은 Homebrew 설치 파일을 내려받아 실행합니다. 실행하기 전에 주소가 정확히
`raw.githubusercontent.com/Homebrew/install/HEAD/install.sh`인지 확인합니다. <br>
명령 대신 쓸 수 있는 서명된 `.pkg` 설치 파일도 [Homebrew 공식 홈페이지](https://brew.sh/)에 안내되어 있습니다.

설치가 끝나면 화면에 나온 **Next steps**를 그대로 실행해 `brew`를 셸 환경에 추가하고, 먼저 명령이 잡히는지 확인합니다.


```bash
brew --version
```

일반 macOS 14 이상 경로는 다음과 같습니다.

```bash
brew install sane-backends
```

macOS 26 이상 SANE 패치 경로는 저장소에 포함된 도우미를 실행합니다.

```bash
bash scripts/install-patched-sane.sh
export PATH="$(brew --prefix sane-backends-negaflow)/bin:$PATH"
```

설치된 명령과 버전을 확인합니다.

```bash
command -v scanimage
scanimage --version
brew list --versions sane-backends sane-backends-negaflow
```

패치된 keg가 있으면 플러그인은 `/opt/homebrew/opt/...` 또는 `/usr/local/opt/...`
절대 경로와 같은 keg의 `etc/sane.d`, `lib/sane`을 함께 사용합니다.<br><br>

### 3. 스캐너 연결과 SANE 확인

스캐너 전원을 켜고 가능하면 USB 허브를 거치지 않고 직접 연결한 뒤 실행합니다.

```bash
scanimage -L
```

출력에 적힌 백엔드와 USB 주소를 포함한 device ID 전체를 복사해서 해당 장치가 제공하는 옵션을
확인합니다.

```bash
scanimage -d '<device-id>' -A
```

device ID는 `genesys:libusb:001:002`처럼 보일 수 있습니다.<br> 이 예시를 그대로 쓰지 말고 현재
Mac에서 `scanimage -L`이 반환한 값을 사용해야 합니다.

`sane-find-scanner`는 USB나 SCSI 장치를 찾았다는 뜻일 뿐입니다.<br> 사용할 수 있는 SANE 백엔드가 없는 스캐너도 표시할 수 있습니다.<br> `scanimage -L`에 장치가 나오지 않으면 이 플러그인에서도 사용할 수 없습니다.<br><br> USB 연결,
[SANE 지원 목록](https://www.sane-project.org/sane-supported-devices.html)과 해당 백엔드
설명서를 먼저 확인해야 합니다.

### 4A. 소스에서 플러그인 빌드·설치

```bash
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
./install.sh
```

스크립트가 Release 빌드를 만든 뒤 아래 두 파일을 설치합니다.

```text
~/Library/Application Support/negaflow/Plugins/sane/
  ├── negaflow-scanner-sane
  └── manifest.json
```

### 4B. 배포 ZIP에서 설치

릴리스 ZIP을 풀고 안에 있는 설치 파일을 실행합니다.

```bash
./install.sh
```

배포 ZIP 설치에는 Swift 도구체인이 필요하지 않습니다. `install.sh`는 플러그인만
설치하므로, 위 설명에 따라 일반 SANE 또는 macOS 26 패치판을 먼저 설치합니다.

### 5. negaflow에서 승인하고 확인

negaflow를 다시 실행하고 **스캐너 불러오기**를 엽니다. 플러그인 경로, 버전, 라이선스와 hash를 확인한 뒤 승인합니다. <br>
업데이트로 실행 파일이나 manifest가 바뀌면 다시 승인을 받아야 합니다.

설치된 실행 파일을 직접 확인할 수도 있습니다.

```bash
"$HOME/Library/Application Support/negaflow/Plugins/sane/negaflow-scanner-sane" detect
```

`{"devices":[...]}`가 나오면 플러그인이 실행된 것입니다. `devices`가 빈 배열이면 플러그인은
실행됐지만 SANE이 사용할 수 있는 스캐너를 반환하지 않은 상태입니다. 이때 플러그인을 다시
설치해도 빠진 SANE 백엔드 지원이 생기지는 않으므로 `scanimage -L` 단계부터 확인해야 합니다.

## 지원 스캐너

아래 표는 알려진 SANE 1.4 대상과 이 플러그인이 처리하는 경로를 정리한 것입니다. 같은 제품명을
가진 모든 장치가 작동한다는 보장은 아닙니다.
[SANE 최신 지원 목록](https://www.sane-project.org/sane-supported-devices.html)을 확인한 뒤
실제로 연결한 장치를 `scanimage -L`과 `scanimage -A`로 다시 확인해야 합니다.

| 스캐너 계열 | SANE 백엔드 | SANE 1.4 상태 | 플러그인 처리 |
|---|---|---|---|
| Plustek OpticFilm 7200, 7200 v2, 7200i, 7300, 7400 v2, 7500i, 7600i | `genesys` | Complete | 필름 전용 스캐너 경로 |
| Plustek OpticFilm 7400 v1 | `genesys` | 지원표에는 Complete지만 기종별 보정은 SANE 1.4.0 이후 반영됨 | capability 기반 경로, stock 1.4.0 실기 결과 미검증 |
| Plustek OpticFilm 8100, USB `07b3:130c` | `genesys` | Complete | 필름 전용 스캐너 경로 |
| Plustek OpticFilm 8100, USB `07b3:1824` | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| Plustek OpticFilm 8200i, USB `07b3:130d` | `genesys` | Complete | 필름 전용 스캐너 경로 |
| Plustek OpticFilm 8200i, USB `07b3:1825` (GL128) | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| Plustek OpticFilm 120, 120 Pro, 135, 135i, 9000i Ai | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| Epson Perfection V700/V750(GT-X900), V800/V850(GT-X980) | `epson2` | Good | 보고된 경우 투과 소스와 위치 지정 플랫베드 영역 사용 |
| Nikon Coolscan LS-2000, LS-40 ED, LS-50 ED, LS-4000 ED, LS-8000 ED | `coolscan3` | 기종에 따라 Complete~Minimal | 필름 전용 스캐너 경로 |
| Nikon Coolscan LS-5000 ED | `coolscan3` | SANE 1.4 기준 미검증, LS-50과 비슷하게 동작할 수 있음 | 필름 전용 스캐너 경로 |
| Nikon Coolscan LS-20, LS-30, LS-1000 | `coolscan` | 기종별로 다름 | SCSI 전용 |
| Nikon Coolscan LS-9000 ED | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| Reflecta ProScan/CrystalScan/DigitDia, PIE PowerSlide | `pieusb`, 구형 SCSI는 `pie` | 기종과 모델 번호에 따라 다름 | 보고된 옵션만 사용 |
| Pacific Image PrimeFilm XA, XAs, XA Plus | 없음 | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| 그 밖의 투과 원고용 플랫베드·필름 스캐너 | 백엔드별로 다름 | 기종별로 다름 | 기능 보고 기준, 모델명 fallback 없음 |

### 제품명은 하드웨어를 알려주지 않습니다

OpticFilm 8100과 8200i는 각각 같은 제품명 아래 USB 변형이 적어도 두 가지 있습니다.<br>
`07b3:130c`와 `07b3:130d`는 `genesys`가 다루지만, `07b3:1824`와 `07b3:1825`는 어느 백엔드도
다루지 못하는 다른 Genesys 칩을 씁니다.<br>
옛 이름 그대로 판매되는 새 리비전은 SANE 쪽에서 해결할 수 없으므로, 본체에 적힌 이름이 아니라
실제 USB product ID를 확인해야 합니다.<br>
(랜덤 뽑기라는게... 참 이해가 안되긴 합니다. )

식별을 어렵게 하는 함정이 두 가지 더 있습니다.

- `pieusb`는 USB ID와 **모델 번호**를 함께 봅니다. Reflecta와 PIE 기기는 `05e3:0145`처럼 같은
  ID를 공유하므로, 모델 번호가 `pieusb.conf`에 있어야만 사용할 수 있습니다.
- `epson2`는 Epson 스캐너를 일본 모델명으로 인식합니다. `scanimage -L`은 Perfection V800/V850을
  `GT-X980`, V700/V750을 `GT-X900`으로 표시합니다. 다른 장치가 아니라 같은 스캐너입니다.

## 적외선 채널

이 플러그인에서 “IR 사용 가능”은 별도 적외선 이미지를 `irPath`로 negaflow에 넘길 수 있다는 뜻입니다. <br>백엔드 내부에서만 작동하는 먼지 제거 옵션은 IR 채널로 보고하지 않습니다.

| 스캐너·백엔드 경로 | IR 상태 | 획득 방법 | 별도 IR TIFF |
|---|---|---|---|
| OpticFilm 7200, 7200 v2, 7300, 7400, 8100 | 사용 불가 | IR 소스를 제공하지 않는 기종 | 없음 |
| OpticFilm 7200i, 7500i, 7600i, 8200i `07b3:130d` | `scanimage -A`에 IR 소스가 나오면 사용 가능 | `Transparency Adapter Infrared` 별도 패스 | 있음 |
| OpticFilm 8200i `07b3:1825` | 사용 불가 | SANE 1.4 미지원 변형 | 없음 |
| `macos26` 설치본의 Epson V700/V750/V800/V850 | `scanimage -A`가 적외선 모드를 보고하면 사용 가능 | 패치된 `epson2`의 `Infrared` 모드 별도 패스 | 있음 |
| 기본 `epson2`의 Epson V700/V750/V800/V850 | 사용 불가 | 기본 빌드는 `SANE_FRAME_IR`이 빠진 채 컴파일됨 | 없음 |
| `--infrared`를 제공하는 Nikon `coolscan3` | 기본 `scanimage` 경로에서는 사용 불가 | `coolscan3`는 `SANE_FRAME_RGBI` 한 프레임을 반환하지만 `scanimage` 1.4는 이를 RGB와 IR TIFF로 분리하지 못함 | 없음 |
| `--clean-image`만 제공하는 Reflecta/PIE | IR 채널로는 사용 불가 | 먼지 제거가 백엔드 내부에서 끝남 | 없음 |
| 그 밖의 스캐너 | 조건부 | `scanimage -A`에 활성 상태의 별도 IR source 또는 mode가 있을 때만 | 크기·형식 확인 후 있음 |

IR 패스에는 RGB와 같은 요청 해상도와 스캔 영역을 사용합니다. <br>두 파일의 실제 픽셀 크기가 같은지도 확인한 뒤 반환합니다. <br>negaflow는 이 IR 이미지를 GrainMend IR에 사용할 수 있습니다.

## 문제 해결: 설치가 실패할 때

실패 화면에는 "설치에 실패했습니다"만 뜹니다. macOS 설치 관리자는 패키지 스크립트를 종료
코드로만 판정하고, 스크립트가 출력한 내용은 화면에 띄우지 않습니다. 설치 창이 열려 있는
동안 ⌘L을 누르거나, 나중에 로그를 읽습니다.

```bash
sudo grep -iE "negaflow|Error:" /var/log/install.log | tail -60
```

| 로그 | 원인 |
|---|---|
| `Your Command Line Tools are too outdated` | `macos26` 판은 SANE을 컴파일하는데, 실행 중인 macOS보다 낡은 Command Line Tools는 Homebrew가 거부함 |
| `Homebrew was not installed at the supported prefix` | `/opt/homebrew` 또는 `/usr/local`에 `brew`가 없음 |
| `no supported logged-in user was found` | 콘솔 사용자가 없음. SSH나 로그인 창에서 실행한 경우 |
| `patched scanimage was not installed` | SANE 빌드 실패. Homebrew 오류가 이 줄 위에 있음 |

Command Line Tools가 낡은 경우:

```bash
sudo rm -rf /Library/Developer/CommandLineTools
```

```bash
xcode-select --install
```

낡은 설치본에도 `git`은 남아 있어서 파일 확인만으로는 설치된 것으로 잡힙니다. 설치 관리자는
대신 실행 중인 macOS의 SDK를 찾고, 없으면 아무것도 설치하기 전에 멈춥니다.

Homebrew는 미리 깔아둘 필요가 없습니다. 패키지에 공식 서명된 Homebrew 설치본이 들어 있고
`brew`가 없을 때만 실행합니다. 이미 설치된 Homebrew는 그대로 쓰며 교체하거나 업그레이드하지
않습니다.

`macos26` 판은 SANE 1.4.0을 소스에서 빌드하므로 몇 분이 걸리고, 진행 막대는 빌드 진행 상황을
보여주지 못합니다. `opticfilm-macos14` 판은 미리 빌드된 bottle을 설치하므로 금방 끝납니다.

## 문제 해결: 스캐너가 보이지 않을 때

negaflow의 **승인됨**은 플러그인 실행 파일을 실행해도 된다는 뜻입니다.<br>
스캐너를 찾았다는 뜻이 아닙니다. 장치 발견은 `scanimage -L`이 돌려준 결과 그대로이므로, 거기에
없는 스캐너는 negaflow에도 없고 앱이나 플러그인을 다시 설치해도 달라지지 않습니다.

macOS에는 앱별로 켜야 하는 USB 권한이 없습니다. negaflow와 이 플러그인은 App Sandbox를 쓰지
않으므로 **개인정보 보호 및 보안** 설정이 스캐너 접근을 막지도 않습니다.

### 1. 어느 단계에서 끊기는지 확인

스캐너 전원을 켜고 연결한 상태에서 차례대로 실행합니다.

```bash
system_profiler SPUSBDataType
```

```bash
scanimage -L
```

```bash
"$HOME/Library/Application Support/negaflow/Plugins/sane/negaflow-scanner-sane" detect
```

| USB 목록 | `scanimage -L` | `detect` | 문제 위치 |
|---|---|---|---|
| 스캐너 없음 | 없음 | `{"devices":[]}` | SANE 이전 단계인 케이블, 포트, 전원 |
| 스캐너 있음 | 없음 | `{"devices":[]}` | SANE 백엔드 또는 장치를 점유한 다른 프로세스 |
| 스캐너 있음 | 장치 나옴 | `{"devices":[]}` | 플러그인이 보지 않는 위치에 설치된 SANE |
| 스캐너 있음 | 장치 나옴 | 장치 나옴 | negaflow 쪽: **스캐너 불러오기**를 다시 열고 승인 |

### 2. 흔한 원인

| 증상 | 원인 | 조치 |
|---|---|---|
| `scanimage: command not found` | SANE이 없거나 해당 `bin`이 현재 `PATH` 밖에 있음 | 일반 `sane-backends`를 설치하고, 패치 경로면 위 도우미와 `export` 실행 |
| USB 목록에 스캐너가 없음 | 허브, 도크, 젠더, 케이블, 전원 | 허브를 빼고 Mac에 직접 연결하고 다른 포트도 시도. USB 2.0 필름 스캐너는 USB-C 젠더에서 자주 실패 |
| `sane-find-scanner`에는 보이는데 `no SANE devices found` | 이 모델을 맡는 활성 백엔드가 없음 | [SANE 지원 목록](https://www.sane-project.org/sane-supported-devices.html)을 확인한 뒤 3번 로그 확인 |
| USB 목록에는 있고 `scanimage -L`은 비었으며 `repair-sane-config`가 `notNeeded` | SANE이 모르는 하드웨어 리비전 | USB product ID를 [지원 스캐너](#지원-스캐너) 표와 대조. 옛 제품명으로 판매되는 새 리비전은 이쪽에서 해결 불가 |
| Coolscan LS-50 또는 LS-5000이 USB 목록에서 사라짐 | 이 기종에서 알려진 USB 포트 고장 | 다른 케이블과 포트로 확인. Mac이 아예 열거하지 못하면 드라이버가 아니라 하드웨어 고장 |
| `another process has device opened for exclusive access`, `device busy`, `is not configured` | 다른 프로그램이 USB 인터페이스를 이미 점유 | VueScan, SilverFast, 이미지 캡처와 제조사 유틸리티를 종료하고 스캐너를 다시 연결한 뒤 재시도 |
| `sudo scanimage -L`로만 찾음 | 인터페이스가 점유됐거나 해제되지 않음 | 위 점유 문제를 해결. negaflow는 플러그인을 root로 실행하지 않으므로 `sudo`는 해결책이 아님 |
| 터미널에서는 찾는데 negaflow에서는 안 보임 | 지원하는 Homebrew keg 경로 밖에 SANE이 있음 | 포함된 설치 파일을 다시 실행. MacPorts(`/opt/local`)나 별도 수동 빌드 경로는 사용하지 않음 |
| `open of device ... failed: Invalid argument` | 처음 연 뒤 USB 주소가 바뀌었거나 SANE 설정 디렉토리가 없음 | `detect`를 다시 실행하고 `/opt/homebrew/etc/sane.d` 또는 `/usr/local/etc/sane.d`가 있는지 확인 |
| 업데이트 전에는 됐음 | 선택한 SANE keg가 제거되었거나 다른 설치로 교체됨 | 해당 설치 파일을 다시 실행하고 `brew list --versions sane-backends sane-backends-negaflow` 확인 |
| 구버전 negaflow 플러그인 설치 후 목록이 빔 | 구버전이 `dll.conf`에서 백엔드를 꺼 둠 | [SANE 설정](#sane-설정)의 `repair-sane-config` 실행 |

### 3. 백엔드 로그 확인

```bash
SANE_DEBUG_DLL=3 scanimage -L 2>&1 | tail -40
```

어떤 백엔드가 로드되고 어디서 실패하는지 보여 줍니다.<br>
백엔드 하나로 좁히려면 `SANE_DEBUG_GENESYS=128`, `SANE_DEBUG_EPSON2=128`처럼 해당 백엔드의
변수를 사용합니다.

문제를 알리려면 macOS 버전, Mac 기종, `scanimage --version`,
`brew list --versions sane-backends sane-backends-negaflow`, 스캐너 모델과 위 세 단계의 출력이 함께 필요합니다.

## 요청값과 실패 처리

- 요청한 DPI가 장치의 목록이나 범위에 정확히 있어야 합니다. 가까운 해상도로 바꾸지 않습니다.
- 16-bit 요청은 SANE depth가 8보다 크고 결과 파일도 실제 16-bit TIFF일 때만 성공합니다.
- mm 단위 `-x/-y` 범위가 있어야 물리 스캔 영역을 표시합니다. 위치 지정에는 `-l/-t`도 필요합니다.
- source, mode, depth, resolution, preview와 geometry를 적용한 뒤 의존 옵션을 다시 확인합니다.
- 프리뷰에 IR이나 다중 노출을 몰래 덧붙이지 않습니다.
- 밝기, 대비나 gamma를 하드웨어 다중 노출처럼 사용하지 않습니다.
- 결과가 요청과 다르거나 검증에 실패하면 해당 파일을 버리고 오류를 반환합니다.

## negaflow 스캐너 프로토콜

실행 파일은 서브커맨드로 호출되며 표준 출력에 JSON을 기록합니다.

| 명령 | 입력 | 출력 |
|---|---|---|
| `detect` | 없음 | 장치 목록 JSON |
| `capabilities <deviceId>` | 선택적 탐지 장치 식별 JSON | 해상도, 모드, 비트 심도, 영역, 노출과 IR 기능 JSON |
| `scan` | stdin의 protocol v2 요청 JSON | NDJSON 진행 상황과 최종 결과 또는 오류 이벤트 |
| `repair-sane-config` | 없음 | 구버전 negaflow 플러그인이 꺼 둔 백엔드만 다시 활성화 |
| `tune-sane` | 없음 | `repair-sane-config` 호환 별칭 |
| `restore-sane` | 없음 | 최후 수단으로 구버전 전체 백업 복구 |

protocol v2의 모든 이벤트에는 `protocolVersion`, `requestID`와 계속 증가하는 `sequence`가
들어갑니다. 성공 결과의 `appliedOptions`는 출력 TIFF와 실제 적용값을 확인한 뒤에만 기록합니다.
negaflow는 `capabilities`가 돌려준 불투명 `capabilityToken`을 다음 스캔 요청에 자동으로
되돌려줍니다. CLI를 직접 호출할 때도 같은 값을 넣어야 하며, 생략하면 호환용 사전 검사가 더
실행됩니다.

capability는 실제로 스캔할 상태에서 읽습니다. SANE 옵션은 서로의 활성 여부를 바꿉니다. `epson2`는 Lineart에서 심도를, 선형 감마를 고르면 밝기를 비활성으로 내립니다. 그래서 장치 기본 상태의 덤프는 스캔 상태를 설명하지 못합니다. 투과 소스와 스캔 모드, 중립 색·감마를 적용한 상태에서 옵션을 읽고 그 상태를 토큰에 담으며, 다른 모드를 요청하면 그 모드에서 옵션을 다시 읽습니다.

본 스캔 요청 예시:

```json
{
  "protocolVersion": 2,
  "requestID": "7A91B43D-90F8-41E2-B71D-04D17CD9E03B",
  "deviceID": "sane-genesys:libusb:001:002",
  "capabilityToken": "<capabilities가 반환한 불투명 토큰>",
  "resolutionDPI": 3600,
  "bitDepth": 16,
  "colorMode": "color",
  "filmType": "colorNegative",
  "preview": false,
  "multiExposure": false,
  "infrared": false,
  "scanArea": {
    "originXMM": 0,
    "originYMM": 0,
    "widthMM": 36,
    "heightMM": 24
  },
  "outputRawTIFF": true,
  "outputPath": "/tmp/scan.tiff"
}
```

## SANE 설정

패치된 keg는 자체 `etc/sane.d`를 사용하며 일반 Homebrew 설치의 `dll.conf`를 수정하지 않습니다.<br>
`detect`를 실행하면 구버전 negaflow 플러그인이 꺼 둔 백엔드만 자동으로 복구하며, 배포판과
사용자가 원래 주석 처리한 줄은 보존합니다. 같은 복구를 수동으로 실행할 수도 있습니다.

```bash
.build/release/negaflow-scanner-sane repair-sane-config
```

구버전의 `dll.conf.negaflow-backup`이 남아 있다면 아래 명령으로 현재 파일 전체를 백업 시점으로
되돌릴 수 있습니다. 백업 뒤의 사용자 변경도 사라지므로 위의 부분 복구로 해결되지 않을 때만
사용하십시오.

```bash
.build/release/negaflow-scanner-sane restore-sane
```

## 저장소 구성

| 경로 | 역할 |
|---|---|
| `Sources/SANEPluginCore` | SANE 장치 찾기, 기능 해석, 스캔, TIFF 검증, IR과 노출 병합 |
| `Sources/negaflow-scanner-sane` | negaflow 스캐너 프로토콜 v2용 JSON/CLI 어댑터 |
| `Tests/SANEPluginCoreTests` | 프로토콜, 프로세스, 옵션 파서, TIFF와 가상 스캐너 회귀 테스트 |
| `Installer` | 원샷 PKG 배포 구성, 설치 스크립트와 Installer.app 화면 자료 |
| `scripts` | 유니버설 빌드, 서명, 패키징, 설치, 공증과 릴리스 확인 |

## 개발 확인

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

모델별 가상 스캐너 테스트는 실제 subprocess와 TIFF 계약으로 프리뷰, 본 스캔, 스캔 영역과 IR 경로를 확인합니다. <br>
스캐너 모터, 광학계, USB 전송이나 최종 화질을 재현하지 않으며 실기기 검증으로 표시하지 않습니다.

## 릴리스 빌드

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
```

스크립트는 `arm64`와 `x86_64`를 빌드해 유니버설 실행 파일로 합치고, dSYM 생성, 서명, 패키징,
SHA-256 기록과 압축 파일 검증까지 수행합니다. <br>산출물은 `.build/release-artifacts/`에 저장됩니다.

배포 서명과 공증에는 `NEGAFLOW_CODESIGN_IDENTITY`, `NEGAFLOW_NOTARY_KEYCHAIN_PROFILE`,
`NEGAFLOW_RELEASE_MODE=distribution`이 추가로 필요합니다.

원샷 PKG와 DMG는 아래 명령으로 만듭니다.

```bash
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

이 빌드는 고정된 공식 Homebrew 패키지를 검증한 뒤 설치 구성 요소를 포함하고, Apple Silicon 전용과
유니버설 두 가지를 만든 다음 실제 설치 없이 각 PKG와 DMG 구조를 확인합니다.
`NEGAFLOW_INSTALLER_ARCHITECTURE`를 `arm64` 또는 `universal`로 지정하면 한 가지만 만들고,
기본값 `all`은 둘 다 만듭니다. `NEGAFLOW_INSTALLER_VARIANT=all`을 지정하면 일반판과
Coolscan판을 모두 만들며 기본값은 일반판입니다. 배포용 서명·공증에는
`NEGAFLOW_INSTALLER_MODE=distribution`, PKG용 `NEGAFLOW_INSTALLER_IDENTITY`, 기존 앱 서명
신원과 공증 프로필이 추가로 필요합니다.

## 라이선스

이 프로젝트는 [GPL-2.0-or-later](LICENSE)로 배포됩니다. 릴리스 압축 파일에는 라이선스 안내와
GNU GPL v2 전문인 [COPYING](COPYING)이 함께 들어갑니다.

설치 파일에는 함께 넣은 Homebrew 설치 구성 요소와, Coolscan판에서 사용자 Mac에 빌드하는
패치된 SANE 소스의 [서드파티 고지](THIRD_PARTY_NOTICES.md)도 포함됩니다.
동일 버전의 완전한 플러그인 소스 압축 파일은 릴리스 ZIP 안과 같은 릴리스 경로에 제공하고,<br>
PKG 페이로드와 DMG에도 포함합니다.

negaflow 본체는 별도의 Apache-2.0 프로젝트입니다. 제품명과 스캐너명은 호환 대상이나 측정 대상을
식별할 때만 사용하며, 각 이름의 권리는 해당 소유자에게 있습니다.
