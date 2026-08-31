<h1 align="center">negaflow-scanner-sane for Windows</h1>

<p align="center">SANE 필름 스캐너를 Windows의 negaflow에 연결하는 플러그인</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.1-EF8B26" alt="버전 1.1.1"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
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
  <a href="../../negaflow-mac/docs/README_ko.md">macOS</a>
</p>

---

## 필요한 것

- Windows 11, 64비트
- negaflow 1.1.1 이상이 먼저 설치돼 있어야 합니다
- SANE이 지원하는 필름 스캐너

SANE 실행 파일은 설치 파일 안에 들어 있습니다. 따로 받으실 것은 없습니다.

## 설치

[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases)에서
`negaflow-sane-1.1.1-win-x64.exe`를 내려받아 실행합니다.

1. 언어를 고르고 안내를 따릅니다.
2. 설치가 끝날 무렵 스캐너 통로를 열지 물어봅니다. 여기서만 관리자 확인이 한 번 필요합니다.
3. negaflow를 다시 켜면 스캐너 조작이 나타납니다.

## VueScan이나 SilverFast를 같이 쓸 때

같이 쓸 수 있습니다.

이 플러그인은 Windows가 이미 제공하는 스캐너 드라이버 경로(`usbscan.sys`)로 장치와
통신합니다. 드라이버를 바꿔치거나 다른 것으로 덮어쓰지 않기 때문에, 다른 스캔 프로그램이
쓰던 방식이 그대로 남습니다.

한 번에 한 프로그램만 스캐너를 잡을 수 있다는 점만 지키시면 됩니다. negaflow에서 스캔하는
동안에는 VueScan을 닫아 두시고, 그 반대도 마찬가지입니다.

## 제거

시작 메뉴의 `negaflow 스캐너 플러그인 제거`나 설정의 앱 목록에서 제거합니다.

제거할 때 설치하면서 열었던 스캐너 통로를 되돌릴지 한 번 물어봅니다. 되돌리면 Windows가
원래 쓰던 드라이버로 돌아가고, 건너뛰면 통로는 그대로 남습니다. 어느 쪽을 고르든 negaflow
본체와 사진은 그대로입니다.

## 스캐너가 안 보일 때

순서대로 확인해 보십시오.

1. **negaflow를 다시 켰는지.** 설치 직후에는 앱을 한 번 다시 켜야 플러그인을 읽습니다.
2. **스캐너 전원과 USB 연결.** 장치 관리자에 이미징 장치로 잡히는지 봅니다.
3. **다른 프로그램이 잡고 있는지.** VueScan, SilverFast, 제조사 스캔 유틸리티를 닫습니다.
4. **설치할 때 스캐너 통로 열기를 건너뛰지 않았는지.** 건너뛰었다면 설치 파일을 다시
   실행해서 이번에는 예를 고르시면 됩니다.

여기까지 해도 안 보이면 플러그인이 스캐너를 찾는 과정을 직접 볼 수 있습니다.

```powershell
& "$env:LOCALAPPDATA\Negaflow\Plugins\sane\negaflow-scanner-sane.exe" detect
```

장치가 잡히면 JSON으로 목록이 나옵니다. 빈 목록이 나오면 SANE 단계에서 못 찾은 것이고,
오류가 나오면 그 메시지가 원인입니다.

## 스캔이 중간에 멈출 때

- USB 허브를 거치고 있다면 컴퓨터에 직접 꽂아 보십시오. 필름 스캔은 데이터 양이 많아서
  허브에서 끊기는 경우가 있습니다.
- 절전으로 USB 전원이 꺼지지 않도록 설정을 확인하십시오.
- 해상도를 한 단계 낮춰서 되는지 봅니다. 됐다면 전송 속도 문제입니다.

## 확인된 장치

| 스캐너 | 확인한 내용 |
|---|---|
| Plustek OpticFilm 8100 | 프리뷰와 본스캔, 여러 해상도, 컬러와 흑백, 8비트와 16비트 |
| Epson Perfection V700 | 프리뷰와 본스캔, 여러 해상도, 적외선 채널, 컬러와 흑백 |

여기 적은 것은 실제로 돌려 본 조합입니다. 목록에 없는 스캐너도 동작할 수 있습니다.
확인해 보지 못했을 뿐입니다.

## 빌드

```powershell
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane\negaflow-windows

cmake --preset x64-release
cmake --build --preset x64-release
ctest --preset x64-release --output-on-failure
```

Visual Studio 2022와 CMake 3.28 이상이 필요합니다.

설치 파일을 만들 때:

```powershell
.\scripts\build-installer.ps1 -Overwrite
```

## 관련 문서

- [공통 문서](../../README_ko.md)
- [macOS 문서](../../negaflow-mac/docs/README_ko.md)
- [출처 고지](../../PROVENANCE.md)
- [서드파티 고지](../../THIRD_PARTY_NOTICES.md)
