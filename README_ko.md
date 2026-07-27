<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">macOS용 negaflow SANE 필름 스캐너 플러그인</p>

<p align="center">
  <a href="#요구-사항"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 이상"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift 5.9 이상"></a>
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
- `--scan-exposure-time`이 필요한 노출 계획을 모두 지원할 때만 하드웨어 다중 노출 사용
- 현재 플러그인 인스턴스가 실행한 `scanimage` 프로세스만 취소



## 요구 사항

- 현재 negaflow와 Homebrew 설치 경로 기준 macOS 14.0 이상
- negaflow
- 실행 시 [SANE backends](https://formulae.brew.sh/formula/sane-backends)
- 소스에서 빌드할 때만 Swift 5.9 이상

설치 안내는 현재 negaflow와 Homebrew가 함께 지원되는 macOS 14 이상을 기준으로 합니다.

## 설치

### 1. 손쉬운 설치

Xcode Command Line Tools가 없다면 먼저 설치합니다.

```bash
xcode-select --install
```

설치 파일은 두 가지입니다. [Releases](https://github.com/habinsong/negaflow-scanner-sane/releases)에서
하나를 내려받아 열고 <br>
**`Install negaflow Scanner.pkg`를 실행합니다.**

| 설치 파일 | 대상 | 플러그인 바이너리 |
|---|---|---|
| `negaflow-scanner-sane-1.0.0-macos-arm64-installer.dmg` | Apple Silicon Mac(M1 이상) | `arm64` 전용 |
| `negaflow-scanner-sane-1.0.0-macos-universal-installer.dmg` | Apple Silicon과 Intel Mac | `arm64` + `x86_64` |

기능은 두 파일이 같습니다.<br>
Apple Silicon 전용 파일은 용량이 작고 Intel Mac에서는 설치되지 않으며, 유니버설 파일은 모든 Mac에서 실행됩니다.

Homebrew가 없으면 공식 Homebrew 설치 구성 요소를 먼저 설치하고, <br>로그인한 사용자 계정에
`sane-backends`와 negaflow 플러그인을 차례대로 설치합니다.<br>
설치에는 인터넷 연결과 관리자 암호가 필요하며, 기존 Homebrew가 있으면 그대로 사용합니다.

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

SANE backends를 설치합니다. 이미 설치되어 있다면 같은 명령에서 설치 상태를 확인할 수 있습니다.

```bash
brew install sane-backends
```

설치된 명령과 버전을 확인합니다.

```bash
command -v scanimage
scanimage --version
brew list --versions sane-backends
```

`scanimage`의 일반적인 위치는 Silicon Mac에서 `/opt/homebrew/bin/scanimage`, IntelMac에서 `/usr/local/bin/scanimage`입니다. <br>
GUI 앱은 터미널보다 `PATH`가 짧지만 이 플러그인은 두 위치를 모두 확인합니다.<br>
SANE 설정은 보통 `/opt/homebrew/etc/sane.d` 또는 `/usr/local/etc/sane.d`에 있습니다.<br><br>

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

배포용 설치 파일에는 Swift 도구체인이 필요하지 않습니다. SANE은 따로 설치해야 합니다.

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
| Plustek OpticFilm 7200, 7200 v2, 7200i, 7300, 7400, 7500i, 7600i, 8100 | `genesys` | Complete | 필름 전용 스캐너 경로 |
| Plustek OpticFilm 8200i, USB `07b3:130d` | `genesys` | Complete | 필름 전용 스캐너 경로 |
| Plustek OpticFilm 8200i, USB `07b3:1825` (GL128) | `genesys` | Unsupported | 사용 가능한 장치로 처리하지 않음 |
| Epson Perfection V700/V750, V800/V850 | `epson2` | Good | 보고된 경우 투과 소스와 위치 지정 플랫베드 영역 사용 |
| Nikon Coolscan/LS 계열 | `coolscan3`, 구형 SCSI는 `coolscan` | 기종에 따라 Complete~Minimal | 필름 전용 스캐너 경로 |
| Reflecta ProScan/CrystalScan/DigitDia, PIE PowerSlide | `pieusb`, 구형 SCSI는 `pie` | 기종별로 다름 | 보고된 옵션만 사용 |
| 그 밖의 투과 원고용 플랫베드·필름 스캐너 | 백엔드별로 다름 | 기종별로 다름 | 기능 보고 기준, 모델명 fallback 없음 |

OpticFilm 8200i는 같은 제품명 아래 USB 변형이 적어도 두 가지 있습니다.<br> `07b3:130d`와
`07b3:1825`는 SANE 지원 상태가 다릅니다.<br> 본체에 적힌 이름이 아니라 실제 USB product ID를 확인해야 합니다.<br>
(랜덤 뽑기라는게... 참 이해가 안되긴 합니다. )

## 적외선 채널

이 플러그인에서 “IR 사용 가능”은 별도 적외선 이미지를 `irPath`로 negaflow에 넘길 수 있다는 뜻입니다. <br>백엔드 내부에서만 작동하는 먼지 제거 옵션은 IR 채널로 보고하지 않습니다.

| 스캐너·백엔드 경로 | IR 상태 | 획득 방법 | 별도 IR TIFF |
|---|---|---|---|
| OpticFilm 7200, 7200 v2, 7300, 7400, 8100 | 사용 불가 | IR 소스를 제공하지 않는 기종 | 없음 |
| OpticFilm 7200i, 7500i, 7600i, 8200i `07b3:130d` | `scanimage -A`에 IR 소스가 나오면 사용 가능 | `Transparency Adapter Infrared` 별도 패스 | 있음 |
| OpticFilm 8200i `07b3:1825` | 사용 불가 | SANE 1.4 미지원 변형 | 없음 |
| 기본 `epson2`의 Epson V700/V750/V800/V850 | 사용 불가 | 기본 빌드는 별도 IR 모드를 제공하지 않음 | 없음 |
| `SANE_FRAME_IR`을 적용한 커스텀 Epson 경로 | 조건부 | 실제로 보고될 때만 `Infrared` 모드 별도 패스 | 있음 |
| `--infrared`를 제공하는 Nikon `coolscan3` | 기본 `scanimage` 경로에서는 사용 불가 | `coolscan3`는 `SANE_FRAME_RGBI` 한 프레임을 반환하지만 `scanimage` 1.4는 이를 RGB와 IR TIFF로 분리하지 못함 | 없음 |
| `--clean-image`만 제공하는 Reflecta/PIE | IR 채널로는 사용 불가 | 먼지 제거가 백엔드 내부에서 끝남 | 없음 |
| 그 밖의 스캐너 | 조건부 | `scanimage -A`에 활성 상태의 별도 IR source 또는 mode가 있을 때만 | 크기·형식 확인 후 있음 |

IR 패스에는 RGB와 같은 요청 해상도와 스캔 영역을 사용합니다. <br>두 파일의 실제 픽셀 크기가 같은지도 확인한 뒤 반환합니다. <br>negaflow는 이 IR 이미지를 GrainMend IR에 사용할 수 있습니다.

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
| `scanimage: command not found` | `sane-backends` 미설치 또는 다른 Homebrew 경로에 설치 | `command -v scanimage` 확인. Apple Silicon은 `/opt/homebrew/bin`, Intel은 `/usr/local/bin` |
| USB 목록에 스캐너가 없음 | 허브, 도크, 젠더, 케이블, 전원 | 허브를 빼고 Mac에 직접 연결하고 다른 포트도 시도. USB 2.0 필름 스캐너는 USB-C 젠더에서 자주 실패 |
| `sane-find-scanner`에는 보이는데 `no SANE devices found` | 이 모델을 맡는 활성 백엔드가 없음 | [SANE 지원 목록](https://www.sane-project.org/sane-supported-devices.html)을 확인한 뒤 3번 로그 확인 |
| `another process has device opened for exclusive access`, `device busy`, `is not configured` | 다른 프로그램이 USB 인터페이스를 이미 점유 | VueScan, SilverFast, 이미지 캡처와 제조사 유틸리티를 종료하고 스캐너를 다시 연결한 뒤 재시도 |
| `sudo scanimage -L`로만 찾음 | 인터페이스가 점유됐거나 해제되지 않음 | 위 점유 문제를 해결. negaflow는 플러그인을 root로 실행하지 않으므로 `sudo`는 해결책이 아님 |
| 터미널에서는 찾는데 negaflow에서는 안 보임 | 표준 경로 밖에 설치된 SANE | 플러그인은 `/opt/homebrew`, `/usr/local`, `/usr` 아래만 확인합니다. MacPorts(`/opt/local`)나 직접 빌드한 경로는 쓰지 않으므로 `sane-backends`를 Homebrew로 설치 |
| `open of device ... failed: Invalid argument` | 처음 연 뒤 USB 주소가 바뀌었거나 SANE 설정 디렉토리가 없음 | `detect`를 다시 실행하고 `/opt/homebrew/etc/sane.d` 또는 `/usr/local/etc/sane.d`가 있는지 확인 |
| `brew upgrade` 전에는 됐음 | 새 `sane-backends`의 백엔드 회귀 | `brew list --versions sane-backends`를 되던 버전과 비교 |
| 구버전 negaflow 플러그인 설치 후 목록이 빔 | 구버전이 `dll.conf`에서 백엔드를 꺼 둠 | [SANE 설정](#sane-설정)의 `repair-sane-config` 실행 |

### 3. 백엔드 로그 확인

```bash
SANE_DEBUG_DLL=3 scanimage -L 2>&1 | tail -40
```

어떤 백엔드가 로드되고 어디서 실패하는지 보여 줍니다.<br>
백엔드 하나로 좁히려면 `SANE_DEBUG_GENESYS=128`, `SANE_DEBUG_EPSON2=128`처럼 해당 백엔드의
변수를 사용합니다.

문제를 알리려면 macOS 버전, Mac 기종, `scanimage --version`,
`brew list --versions sane-backends`, 스캐너 모델과 위 세 단계의 출력이 함께 필요합니다.

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

현재 버전은 Homebrew의 공용 `dll.conf`를 필터링하지 않습니다.<br>
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
기본값 `all`은 둘 다 만듭니다. 배포용 서명·공증에는
`NEGAFLOW_INSTALLER_MODE=distribution`, PKG용 `NEGAFLOW_INSTALLER_IDENTITY`, 기존 앱 서명
신원과 공증 프로필이 추가로 필요합니다.

## 라이선스

이 프로젝트는 [GPL-2.0-or-later](LICENSE)로 배포됩니다. 릴리스 압축 파일에는 라이선스 안내와
GNU GPL v2 전문인 [COPYING](COPYING)이 함께 들어갑니다.

원샷 설치 파일에는 함께 넣은 Homebrew 설치 구성 요소와 네트워크로 설치하는 SANE backends의
[서드파티 고지](THIRD_PARTY_NOTICES.md)도 포함됩니다.
동일 버전의 완전한 플러그인 소스 압축 파일은 릴리스 ZIP 안과 같은 릴리스 경로에 제공하고,<br>
PKG 페이로드와 DMG에도 포함합니다.

negaflow 본체는 별도의 Apache-2.0 프로젝트입니다. 제품명과 스캐너명은 호환 대상이나 측정 대상을
식별할 때만 사용하며, 각 이름의 권리는 해당 소유자에게 있습니다.
