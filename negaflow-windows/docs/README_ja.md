<h1 align="center">negaflow-scanner-sane for Windows</h1>

<p align="center">SANE フィルムスキャナーを Windows の negaflow につなぐプラグイン</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.1-EF8B26" alt="1.1.1"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0--or--later-6E7781" alt="GPL 2.0+"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_ko.md">한국어</a> ·
  <strong>日本語</strong> ·
  <a href="README_zh-Hans.md">简体中文</a> ·
  <a href="README_fr.md">Français</a> ·
  <a href="README_de.md">Deutsch</a>
</p>

<p align="center">
  <a href="../../README_ja.md">共通ドキュメント</a> ·
  <a href="../../negaflow-mac/docs/README_ja.md">macOS</a>
</p>

---

## 必要なもの

- Windows 11、64ビット
- negaflow 1.1.1 以降が先に入っていること
- SANE が対応するフィルムスキャナー

SANE の実行ファイルはインストーラに入っています。ほかに用意するものはありません。

## インストール

[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases) から
`negaflow-sane-1.1.1-win-x64.exe` を取って実行します。

1. 言語を選び、案内に従います。
2. 終わりごろにスキャナーの通り道を開くか聞かれます。管理者確認が要るのはここだけです。
3. negaflow を開き直すとスキャナーの操作が現れます。

## VueScan や SilverFast と一緒に使うとき

一緒に使えます。

このプラグインは Windows がもともと用意しているスキャナードライバーの経路
(`usbscan.sys`) で装置とやり取りします。ドライバーを差し替えたり上書きしたりしないので、
ほかのスキャンソフトが使っていたものはそのまま残ります。

守ることは一つだけで、スキャナーを同時に握れるのは一つのソフトだけです。negaflow で
スキャンしているあいだは VueScan を閉じておいてください。逆も同じです。

## 削除

スタートメニューの `negaflow スキャナープラグインのアンインストール` か、設定のアプリ一覧から
行います。

削除のとき、インストール時に開いた通り道を戻すか一度聞かれます。戻せば Windows は元の
ドライバーに帰り、飛ばせば通り道は残ります。どちらを選んでも negaflow 本体と写真はそのままです。

## スキャナーが見つからないとき

上から順に確かめてください。

1. **negaflow を開き直しましたか。** 起動時にプラグインを読むので、入れた直後は一度開き直します。
2. **電源と USB。** デバイスマネージャーにイメージング装置として出ているか見ます。
3. **ほかのソフトが握っていないか。** VueScan、SilverFast、メーカーのユーティリティを閉じます。
4. **インストール時に通り道を開くのを飛ばしませんでしたか。** 飛ばしたなら、もう一度
   インストーラを実行して今度は「はい」を選びます。

それでも出ないときは、プラグインが探す様子を直接見られます。

```powershell
& "$env:LOCALAPPDATA\Negaflow\Plugins\sane\negaflow-scanner-sane.exe" detect
```

見つかれば JSON で一覧が返ります。空のときは SANE の段階で見つかっていません。
エラーが出たときは、その文面が原因です。

## スキャンが途中で止まるとき

- USB ハブ越しなら、パソコンに直接つないでみてください。フィルムスキャンはデータ量が多く、
  ハブで落ちることがあります。
- 省電力で USB の電源が切れない設定になっているか確かめます。
- 解像度を一段下げて通るか見ます。通るなら転送速度の問題です。

## 確かめた装置

| スキャナー | 確かめた内容 |
|---|---|
| Plustek OpticFilm 8100 | プレビューと本スキャン、複数の解像度、カラーとグレー、8bit と 16bit |
| Epson Perfection V700 | プレビューと本スキャン、複数の解像度、赤外線チャンネル、カラーとグレー |

ここに書いたのは実際に動かした組み合わせです。一覧にないスキャナーも動くかもしれません。
確かめていないだけです。

## ビルド

```powershell
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane\negaflow-windows

cmake --preset x64-release
cmake --build --preset x64-release
ctest --preset x64-release --output-on-failure
```

Visual Studio 2022 と CMake 3.28 以降が要ります。

インストーラを作るとき:

```powershell
.\scripts\build-installer.ps1 -Overwrite
```

## 関連ドキュメント

- [共通ドキュメント](../../README_ja.md)
- [macOS のドキュメント](../../negaflow-mac/docs/README_ja.md)
- [出所の記録](../../PROVENANCE.md)
- [サードパーティ表示](../../THIRD_PARTY_NOTICES.md)
