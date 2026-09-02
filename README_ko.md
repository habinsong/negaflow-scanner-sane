<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">negaflow에 필름 스캐너를 연결하는 플러그인</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/ko/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="웹사이트"></a>
  <a href="negaflow-mac/docs/README_ko.md"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 이상"></a>
  <a href="negaflow-windows/docs/README_ko.md"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
  <a href="negaflow-mac/manifest.json"><img src="https://img.shields.io/badge/protocol-v2-4B5563" alt="negaflow 스캐너 프로토콜 v2"></a>
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

**negaflow-scanner-sane**는 SANE으로 다룰 수 있는 필름 스캐너를
[negaflow](https://github.com/habinsong/negaflow)에 연결해 주는 플러그인입니다.

스캔은 negaflow에서 합니다. 이 플러그인은 뒤에서 스캐너와 이야기하는 쪽이라 따로 실행할 일이
없습니다. 설치하고 negaflow에서 한 번 승인하면 **스캐너 불러오기**에 장치가 나옵니다.

플러그인과 본체는 서로 다른 프로그램입니다. SANE 관련 코드는 GPL-2.0-or-later인 이 저장소에만
있고, Apache-2.0인 negaflow와는 별도 프로세스에서 JSON으로만 주고받습니다.

## 요구 사항

- negaflow가 먼저 설치돼 있어야 합니다
- SANE이 지원하는 필름 스캐너
- macOS 14.0 이상 또는 Windows 11

## 설치

[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases)에서 쓰는 시스템에 맞는 설치
파일을 받아 실행하고, negaflow를 다시 켜서 플러그인을 승인하면 됩니다. macOS에서는 설치 파일이
Homebrew로 SANE까지 준비해 주고, Windows에서는 SANE 실행 파일이 설치 파일 안에 들어 있습니다.

| 플랫폼 | 문서 |
|---|---|
| macOS | [macOS에 설치하기](negaflow-mac/docs/README_ko.md) |
| Windows | [Windows에 설치하기](negaflow-windows/docs/README_ko.md) |

## 스캐너

SANE이 지원하는 필름 스캐너면 대체로 됩니다. 문제는 같은 제품명으로 팔린 기기라도 안에 든 칩이
다를 수 있고, 그중 한쪽만 백엔드가 있다는 점입니다. 적외선 채널도 기기가 실제로 내줄 때만 씁니다.
어떤 기종이 어디까지 되는지는 [지원 스캐너](docs/ko/SCANNERS.md)에 정리해 두었습니다.

모델명을 보고 기능을 열지는 않습니다. 연결된 장치와 백엔드가 알려 준 항목만 negaflow로 넘깁니다.

## 문서

- [지원 스캐너](docs/ko/SCANNERS.md) | 기종별 상태, 제품명 함정, 적외선 채널
- [문제 해결](docs/ko/TROUBLESHOOTING.md) | 설치 실패, 스캐너가 보이지 않을 때, SANE 설정
- [개발](docs/ko/DEVELOPMENT.md) | 스캐너 프로토콜, 저장소 구성, 빌드
- 설치 문서 | [macOS](negaflow-mac/docs/README_ko.md) · [Windows](negaflow-windows/docs/README_ko.md)

## 라이선스

이 프로젝트는 [GPL-2.0-or-later](LICENSE)로 배포됩니다. 릴리스 압축 파일에는 라이선스 안내와
GNU GPL v2 전문인 [COPYING](COPYING)이 함께 들어갑니다.

설치 파일에는 함께 넣은 Homebrew 설치 구성 요소와, Coolscan판에서 사용자 Mac에 빌드하는 패치된
SANE 소스의 [서드파티 고지](THIRD_PARTY_NOTICES.md)도 포함됩니다. 동일 버전의 완전한 플러그인 소스
압축 파일은 릴리스 ZIP 안과 같은 릴리스 경로에 제공하고, PKG 페이로드와 DMG에도 포함합니다.

negaflow 본체는 별도의 Apache-2.0 프로젝트입니다. 제품명과 스캐너명은 호환 대상이나 측정 대상을
식별할 때만 사용하며, 각 이름의 권리는 해당 소유자에게 있습니다.
