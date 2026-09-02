# 문제 해결

[문서 홈](README.md)

## 설치가 실패할 때

실패 화면에는 "설치에 실패했습니다"만 뜹니다. macOS 설치 관리자는 패키지 스크립트를 종료 코드로만
판정해서, 스크립트가 남긴 내용은 로그에 있습니다. 설치 창이 열려 있는 동안 ⌘L을 누르거나, 나중에
로그를 읽습니다.

```bash
sudo grep -iE "negaflow|Error:" /var/log/install.log | tail -60
```

| 로그 | 원인 |
|---|---|
| `Your Command Line Tools are too outdated` | `mac26` 판은 SANE을 컴파일하는데, 실행 중인 macOS보다 낡은 Command Line Tools는 Homebrew가 거부함 |
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

낡은 설치본에도 `git`은 남아 있어서 파일 확인만으로는 설치된 것으로 잡힙니다. 설치 관리자는 대신
실행 중인 macOS의 SDK를 찾고, 없으면 아무것도 설치하기 전에 멈춥니다.

Homebrew는 미리 깔아둘 필요가 없습니다. 패키지에 공식 서명된 Homebrew 설치본이 들어 있고 `brew`가
없을 때만 실행합니다. 이미 설치된 Homebrew는 그대로 씁니다.

`mac26` 판은 SANE 1.4.0을 소스에서 빌드하므로 몇 분이 걸리고, 진행 막대는 빌드 진행 상황을
보여주지 못합니다. `mac14` 판은 미리 빌드된 bottle을 설치하므로 금방 끝납니다.

## 스캐너가 보이지 않을 때

negaflow의 **승인됨**은 플러그인을 실행해도 된다는 뜻이지, 스캐너를 찾았다는 뜻은 아닙니다. 장치
발견은 `scanimage -L`이 돌려준 결과 그대로이므로, 거기에 없는 스캐너는 negaflow에도 없고 앱이나
플러그인을 다시 설치해도 달라지지 않습니다.

macOS에는 앱별로 켜야 하는 USB 권한이 없습니다. negaflow와 이 플러그인은 App Sandbox를 쓰지 않으니
**개인정보 보호 및 보안** 설정이 스캐너 접근을 막지도 않습니다.

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
| USB 목록에는 있고 `scanimage -L`은 비었으며 `repair-sane-config`가 `notNeeded` | SANE이 모르는 하드웨어 리비전 | USB product ID를 [지원 스캐너](SCANNERS.md)와 대조. 옛 제품명으로 판매되는 새 리비전은 이쪽에서 해결 불가 |
| Coolscan LS-50 또는 LS-5000이 USB 목록에서 사라짐 | 이 기종에서 알려진 USB 포트 고장 | 다른 케이블과 포트로 확인. Mac이 아예 열거하지 못하면 하드웨어 고장 |
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

어떤 백엔드가 로드되고 어디서 실패하는지 보여 줍니다. 백엔드 하나로 좁히려면
`SANE_DEBUG_GENESYS=128`, `SANE_DEBUG_EPSON2=128`처럼 해당 백엔드의 변수를 사용합니다.

문제를 알릴 때는 macOS 버전, Mac 기종, `scanimage --version`,
`brew list --versions sane-backends sane-backends-negaflow`, 스캐너 모델과 위 세 단계의 출력이 함께
필요합니다.

## SANE 설정

패치된 keg는 자체 `etc/sane.d`를 사용하며 일반 Homebrew 설치의 `dll.conf`를 수정하지 않습니다.
`detect`를 실행하면 구버전 negaflow 플러그인이 꺼 둔 백엔드만 자동으로 복구하고, 배포판과 사용자가
원래 주석 처리한 줄은 그대로 둡니다. 같은 복구를 수동으로 실행할 수도 있습니다.

```bash
.build/release/negaflow-scanner-sane repair-sane-config
```

구버전의 `dll.conf.negaflow-backup`이 남아 있다면 아래 명령으로 현재 파일 전체를 백업 시점으로
되돌릴 수 있습니다. 백업 뒤의 사용자 변경도 사라지므로 위의 부분 복구로 해결되지 않을 때만
사용하십시오.

```bash
.build/release/negaflow-scanner-sane restore-sane
```
