<h1 align="center">negaflow-scanner-sane for macOS</h1>

<p align="center">SANE フィルムスキャナーを macOS の negaflow につなぐプラグイン</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.2-EF8B26" alt="1.1.2"></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 以降"></a>
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
  <a href="../../negaflow-windows/docs/README_ja.md">Windows</a>
</p>

---

## 必要なもの

- macOS 14.0 以降
- negaflow 1.1.1 以降が先に入っていること
- SANE が対応するフィルムスキャナー
- インストール時にインターネット接続と管理者パスワード

Xcode Command Line Tools がなければ先に入れます。

```bash
xcode-select --install
```

## インストール

[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases) から DMG を取ります。
四つありますが、macOS 26 が使えないとき以外は `mac26` のほうを選んでください。

| DMG | SANE | プラグイン |
|---|---|---|
| `negaflow-sane-1.1.2-mac26-arm64.dmg` | パッチ版、macOS 26 以降 | `arm64` |
| `negaflow-sane-1.1.2-mac26-universal.dmg` | パッチ版、macOS 26 以降 | `arm64` + `x86_64` |
| `negaflow-sane-1.1.2-mac14-arm64.dmg` | OpticFilm 用、macOS 14 以降 | `arm64` |
| `negaflow-sane-1.1.2-mac14-universal.dmg` | OpticFilm 用、macOS 14 以降 | `arm64` + `x86_64` |

`mac26` の DMG では `Install negaflow Scanner.pkg`、`mac14` の DMG では
`Install negaflow Scanner for OpticFilm.pkg` を実行します。

終わったら negaflow を開き直し、**スキャナー読み込み**でプラグインを確認して承認します。

### 二つの違い

`mac26` 版は公式 SANE 1.4.0 のソースを `sane-backends-negaflow` としてビルドします。
Nikon Coolscan、Epson の赤外線チャンネル、OpticFilm の白黒スキャンと OpticFilm 8200i SE を
使えるようにするのがこのビルドです。当てているパッチは次のとおりです。

| パッチ | 変わるところ |
|---|---|
| Coolscan の深度一覧 | upstream の `coolscan2`/`coolscan3` の確保を直します |
| `epson2` のスキャン高さ | Epson フラットベッドが報告する高さを直します |
| `epson2` の赤外線 | `SANE_FRAME_IR` の遮断を外し、赤外線パスを出せるようにします |
| OpticFilm Gray | OpticFilm 8100 と 7400 v2 が Gray スキャンを最後まで終えられるようにします |
| OpticFilm upstream バックポート | 1.4.0 以降の SANE の `genesys` の作業を取り込みます。OpticFilm 8200i SE（`07b3:1825`、GL128）と 7400 v1、7600i v1 の修正です |

`mac14` 版は Homebrew 標準の `sane-backends` を入れ、上のパッチは入りません。
macOS 14 と 15 でパッチ版を入れられないときに使います。OpticFilm Gray の修正も 8200i SE の
対応もありません。

どちらの版も macOS 14 と 15 で Coolscan を止めはしません。標準 SANE で動く可能性もありますが、
確保の修正がないため、USB 機種で対応する経路は `mac26` 版です。LS-4000 ED と LS-8000 ED は
FireWire でしか接続できず、macOS 26 には FireWire がありません。Mac では macOS 14 か 15 で
`mac14` 版を使って試すしかなく、まだ誰も確認していません。
[対応スキャナー](../../docs/ja/SCANNERS.md#nikon-coolscan)を参照してください。

LS-5000 のファームウェア 1.03 で要る Coolscan3 の load/eject/reset 初期化は、パッチの範囲に
入れていません。パッチ版でも LS-5000 のフィルム装填と排出、リセットは未確認で、失敗する
可能性があります。

## 手作業で入れる

```bash
# Homebrew がなければ
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install sane-backends
scanimage -L
```

そのあとプラグインをソースからビルドするか、リリース ZIP から入れます。

```bash
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
swift build -c release
```

## スキャナーが見つからないとき

1. **negaflow を開き直しましたか。** 起動時にプラグインを読みます。
2. **承認しましたか。** スキャナー読み込みの画面で承認しないと動きません。
3. **SANE が見えていますか。** ターミナルで `scanimage -L` を試します。ここで出ないなら
   プラグインではなく SANE の段階です。
4. **ほかのソフトが握っていませんか。** VueScan やメーカーのユーティリティを閉じます。

```bash
/usr/local/bin/negaflow-scanner-sane detect
```

## 確かめた装置

| スキャナー | 確かめた内容 |
|---|---|
| Plustek OpticFilm 8100 | プレビューと本スキャン、複数の解像度、カラーとグレー |
| Epson Perfection V700 | プレビューと本スキャン、複数の解像度、赤外線チャンネル |

一覧にないスキャナーも動くかもしれません。確かめていないだけです。

## ビルドと点検

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

仮想スキャナーのテストは実際のプロセス実行と TIFF の取り決めで、プレビュー、本スキャン、
スキャン範囲、赤外線の経路を確かめます。モーターや光学系、USB 転送、最終画質は再現しません。

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

## 関連ドキュメント

- [共通ドキュメント](../../README_ja.md)
- [Windows のドキュメント](../../negaflow-windows/docs/README_ja.md)
- [出所の記録](../../PROVENANCE.md)
- [サードパーティ表示](../../THIRD_PARTY_NOTICES.md)
