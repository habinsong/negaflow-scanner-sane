<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">negaflow にフィルムスキャナーをつなぐプラグイン</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/ja/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="ウェブサイト"></a>
  <a href="negaflow-mac/docs/README_ja.md"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14以降"></a>
  <a href="negaflow-windows/docs/README_ja.md"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
  <a href="negaflow-mac/manifest.json"><img src="https://img.shields.io/badge/protocol-v2-4B5563" alt="negaflowスキャナープロトコル v2"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0--or--later-6E7781" alt="GPL 2.0以降"></a>
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
  <a href="https://habinsong.github.io/negaflow-site/ja/">ウェブサイト</a> ·
  <a href="https://habinsong.github.io/negaflow-site/ja/supported-scanners/">対応スキャナー</a> ·
  <a href="https://habinsong.github.io/negaflow-site/ja/faq/">FAQ</a>
</p>

---

**negaflow-scanner-sane** は、SANE で扱えるフィルムスキャナーを
[negaflow](https://github.com/habinsong/negaflow) につなぐプラグインです。

スキャンは negaflow で行います。このプラグインはスキャナーを制御し、別に起動しなくても動きます。
インストールして negaflow で一度承認すると、「スキャナーを読み込む」に機器が出てきます。

プラグインと本体は別々のプログラムです。SANE のコードは GPL-2.0-or-later のこのリポジトリだけに
あり、Apache-2.0 の negaflow とは別プロセスで JSON をやり取りするだけです。

## 動作環境

- negaflow が先に入っていること
- SANE が対応するフィルムスキャナー
- macOS 14.0 以降、または Windows 11

## インストール

[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases) から自分の環境に合う
インストーラを取って実行し、negaflow を開き直してプラグインを承認します。macOS では
インストーラが Homebrew 経由で SANE まで用意します。Windows では SANE の実行ファイルが
インストーラに入っています。

| 環境 | ページ |
|---|---|
| macOS | [macOS へのインストール](negaflow-mac/docs/README_ja.md) |
| Windows | [Windows へのインストール](negaflow-windows/docs/README_ja.md) |

## スキャナー

SANE が対応するフィルムスキャナーならおおむね動きます。やっかいなのは、同じ製品名で売られていても
中のチップが違うことがあり、片方にしかバックエンドがない点です。赤外線チャンネルも、機器が実際に
出せるときだけ使います。機種ごとの状況は[対応スキャナー](docs/ja/SCANNERS.md)にまとめました。

モデル名だけで機能を開くことはありません。接続した機器とバックエンドが報告した項目だけを
negaflow に渡します。

## ドキュメント

- [対応スキャナー](docs/ja/SCANNERS.md) | 機種ごとの状態、製品名の落とし穴、赤外線チャンネル
- [トラブルシューティング](docs/ja/TROUBLESHOOTING.md) | インストール失敗、スキャナーが見つからないとき、SANE 設定
- [開発](docs/ja/DEVELOPMENT.md) | スキャナープロトコル、リポジトリ構成、ビルド
- インストール手順 | [macOS](negaflow-mac/docs/README_ja.md) · [Windows](negaflow-windows/docs/README_ja.md)

## ライセンス

このプロジェクトは [GPL-2.0-or-later](LICENSE) で配布されます。リリースアーカイブにはライセンス
表示と GNU GPL v2 全文の [COPYING](COPYING) が含まれます。

インストーラーには同梱する Homebrew コンポーネントと、Coolscan 版でユーザーの Mac にビルドする
修正済み SANE ソースの[サードパーティー通知](THIRD_PARTY_NOTICES.md)も含まれます。同じバージョンの
プラグイン完全ソースアーカイブは、リリース ZIP 内と同じリリース場所に提供され、PKG ペイロードと
DMG にも含まれます。

negaflow 本体は別の Apache-2.0 プロジェクトです。製品名とスキャナー名は、互換対象または測定対象を
示すためにだけ使用し、それぞれの権利は各所有者に帰属します。
