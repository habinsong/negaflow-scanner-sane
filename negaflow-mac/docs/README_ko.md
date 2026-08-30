<h1 align="center">negaflow-scanner-sane for macOS</h1>

<p align="center">SANE 필름 스캐너를 macOS의 negaflow에 연결하는 플러그인</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="버전 1.1.0"></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 이상"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0--or--later-6E7781" alt="GPL 2.0 이상"></a>
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
  <a href="../../README_ko.md">공통 문서</a> ·
  <a href="../../negaflow-windows/docs/README_ko.md">Windows</a>
</p>

---

## 필요한 것

- macOS 14.0 이상
- negaflow 1.1.0 이상이 먼저 설치돼 있어야 합니다
- SANE이 지원하는 필름 스캐너
- 설치할 때 인터넷 연결과 관리자 암호

Xcode Command Line Tools가 없다면 먼저 설치합니다.

```bash
xcode-select --install
```

## 설치

[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases)에서 DMG를
내려받습니다. 네 가지가 있는데, macOS 26을 쓸 수 없는 경우가 아니라면 `mac26` 쪽을
받으시면 됩니다.

| 설치 파일 | SANE | 플러그인 |
|---|---|---|
| `negaflow-sane-1.1.0-mac26-arm64.dmg` | 패치판, macOS 26 이상 | `arm64` 전용 |
| `negaflow-sane-1.1.0-mac26-universal.dmg` | 패치판, macOS 26 이상 | `arm64` + `x86_64` |
| `negaflow-sane-1.1.0-mac14-arm64.dmg` | OpticFilm용, macOS 14 이상 | `arm64` 전용 |
| `negaflow-sane-1.1.0-mac14-universal.dmg` | OpticFilm용, macOS 14 이상 | `arm64` + `x86_64` |

`mac26` DMG에서는 `Install negaflow Scanner.pkg`를,
`mac14` DMG에서는 `Install negaflow Scanner for OpticFilm.pkg`를 실행합니다.

설치가 끝나면 negaflow를 다시 켜고 **스캐너 불러오기**에서 플러그인 정보를 확인한 뒤
승인 버튼을 누르면 됩니다.

### 두 설치본의 차이

`mac26` 판은 공식 SANE 1.4.0 소스를 `sane-backends-negaflow`로 빌드합니다.
Nikon Coolscan과 Epson 적외선 채널을 쓰게 해 주는 것이 이 빌드입니다. 들어가는 패치는 셋입니다.

| 패치 | 바뀌는 것 |
|---|---|
| Coolscan 깊이 목록 | upstream `coolscan2`/`coolscan3` 할당 수정 |
| `epson2` 스캔 높이 | Epson 평판이 보고하는 스캔 높이를 바로잡습니다 |
| `epson2` 적외선 | `SANE_FRAME_IR` 차단을 풀어 Epson 필름 평판이 적외선 패스를 낼 수 있게 합니다 |

`mac14` 판은 Homebrew 기본 `sane-backends`를 설치하고 위 패치는 들어가지
않습니다. macOS 14와 15에서 패치판 빌드를 설치할 수 없을 때 쓰는 쪽입니다.

두 설치본 모두 macOS 14와 15에서 Coolscan을 막지는 않습니다. 기본 SANE으로 동작할 수도
있지만 할당 수정이 없으므로, 지원하는 경로는 `mac26` 설치본입니다.

LS-5000 펌웨어 1.03에서 필요한 Coolscan3 load/eject/reset 매개변수 초기화는 패치 범위에
넣지 않았습니다. 패치판에서도 LS-5000의 필름 로드와 배출, 리셋은 확인하지 못했고 실패할 수
있습니다.

## 직접 설치

Homebrew와 SANE을 직접 다루고 싶다면 이 순서로 하시면 됩니다.

```bash
# Homebrew 가 없다면
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# SANE 설치
brew install sane-backends

# 스캐너가 잡히는지 확인
scanimage -L
```

그다음 플러그인을 소스에서 빌드하거나 릴리스 ZIP에서 설치합니다.

```bash
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
swift build -c release
```

## 스캐너가 안 보일 때

순서대로 확인해 보십시오.

1. **negaflow를 다시 켰는지.** 설치 직후에는 앱을 한 번 다시 켜야 플러그인을 읽습니다.
2. **승인을 눌렀는지.** 스캐너 불러오기 화면에서 플러그인을 승인해야 동작합니다.
3. **SANE이 장치를 보는지.** 터미널에서 `scanimage -L`을 실행해 봅니다. 여기서 안 나오면
   플러그인 문제가 아니라 SANE 단계입니다.
4. **다른 프로그램이 잡고 있는지.** VueScan이나 제조사 유틸리티를 닫습니다.

플러그인이 직접 찾는 과정을 볼 수도 있습니다.

```bash
/usr/local/bin/negaflow-scanner-sane detect
```

## 확인된 장치

| 스캐너 | 확인한 내용 |
|---|---|
| Plustek OpticFilm 8100 | 프리뷰와 본스캔, 여러 해상도, 컬러와 흑백 |
| Epson Perfection V700 | 프리뷰와 본스캔, 여러 해상도, 적외선 채널 |

목록에 없는 스캐너도 동작할 수 있습니다. 확인해 보지 못했을 뿐입니다.

## 빌드와 점검

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

가상 스캐너 테스트는 실제 프로세스 실행과 TIFF 계약으로 프리뷰, 본 스캔, 스캔 영역과
적외선 경로를 확인합니다. 스캐너 모터나 광학계, USB 전송, 최종 화질은 재현하지 않습니다.

릴리스와 설치 파일:

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

## 관련 문서

- [공통 문서](../../README_ko.md)
- [Windows 문서](../../negaflow-windows/docs/README_ko.md)
- [출처 고지](../../PROVENANCE.md)
- [서드파티 고지](../../THIRD_PARTY_NOTICES.md)
