<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">macOS版Negaflow用 SANEフィルムスキャナープラグイン</p>

<p align="center">
  <a href="#動作環境"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14以降"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift 5.9以降"></a>
  <a href="manifest.json"><img src="https://img.shields.io/badge/protocol-v2-4B5563" alt="Negaflowスキャナープロトコル v2"></a>
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

---

**negaflow-scanner-sane**は、SANEで利用できるフィルムスキャナーを [Negaflow](https://github.com/habinsong/negaflow)に接続します。<br>
`scanimage`を実行してスキャナーが公開しているオプションを読み取り、デバイス情報、機能、進行状況、TIFFのパスを Negaflowスキャナープロトコル v2で返します。

独自のスキャン画面を備えた別アプリではありません。<br>
インストールして承認した後は、 Negaflowの「スキャナーを読み込む」から使用します。

プラグインと本体は別々のプログラムです。<br>
SANE固有のコードはすべてGPL-2.0-or-laterのこのリポジトリに置かれ、Apache-2.0のNegaflow本体とは、別プロセス、コマンドライン引数、パイプ、JSONだけで通信します。

## 機能

- `scanimage -L`によるスキャナー検出
- デバイスが現在返す`scanimage -A`の内容からスキャン項目を構成
- 要求値を近い既定値へ置き換えないプレビューと本スキャン
- 結果を返す前に解像度、カラーモード、ビット深度、寸法、TIFF形式を確認
- バックエンドが必要な範囲を返した場合だけ、mm単位のスキャン領域を使用
- バックエンドが実際に提供できる場合だけ、独立した赤外線チャンネルを取得
- `--scan-exposure-time`が必要な露出計画を満たす場合だけ、ハードウェア多重露光を使用
- 現在のプラグインインスタンスが起動した`scanimage`プロセスだけを停止

スキャナー名だけで機能を判断しません。<br>
接続中のデバイスとSANEバックエンドが報告した項目だけを Negaflowに表示します。

## 動作環境

- 現行NegaflowとHomebrewによるインストールではmacOS 14.0以降
- Negaflow
- 実行時に[SANE backends](https://formulae.brew.sh/formula/sane-backends)
- ソースからビルドする場合のみSwift 5.9以降

単体実行ファイルのdeployment targetは`Package.swift`でmacOS 13のままです。<br>
ただし、この手順で案内するNegaflowとHomebrewを含む構成は、現在の対応範囲であるmacOS 14以降を基準にしています。

## インストール

### 1. 一括インストーラー

Xcode Command Line Toolsが入っていない場合は、先にインストールします。

```bash
xcode-select --install
```

[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases)から `negaflow-scanner-sane-1.0.0-macos-universal-installer.dmg`をダウンロードして開き、 `Install Negaflow Scanner.pkg`を実行します。

Homebrewがなければ公式Homebrewインストーラーコンポーネントを先にインストールし、ログイン中のユーザーに`sane-backends`とUniversal版Negaflowプラグインを順番にインストールします。<br>
Apple Silicon MacとIntel Macの両方に対応します。<br>
インターネット接続と管理者パスワードが必要です。<br>
既存のHomebrewがある場合はそのまま使用します。

完了後にNegaflowを再起動し、「スキャナーを読み込む」でプラグイン情報を確認して承認します。

### 2. HomebrewとSANEを手動でインストール

Homebrewがない場合は、現在の公式インストールコマンドを実行します。

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

このコマンドはHomebrewのインストーラーを取得して実行します。<br>
実行前にURLが正確に `raw.githubusercontent.com/Homebrew/install/HEAD/install.sh`であることを確認してください。<br>
署名済み`.pkg`を使う方法も[Homebrew公式サイト](https://brew.sh/)に案内されています。

インストール後に表示される**Next steps**を実行して`brew`をシェル環境へ追加し、新しいターミナルを開きます。<br>
まずコマンドを確認します。

```bash
brew --version
```

SANE backendsをインストールします。<br>
すでに入っている場合は、同じコマンドでその状態が表示されます。

```bash
brew install sane-backends
```

インストールされたコマンドとバージョンを確認します。

```bash
command -v scanimage
scanimage --version
brew list --versions sane-backends
```

通常の`scanimage`の場所は、Apple Silicon Macでは`/opt/homebrew/bin/scanimage`、Intel Macでは`/usr/local/bin/scanimage`です。<br>
GUIアプリの`PATH`が短い場合でも、このプラグインは両方を確認します。<br>
SANE設定は通常`/opt/homebrew/etc/sane.d`または `/usr/local/etc/sane.d`にあります。

### 3. スキャナーを接続してSANEを確認

スキャナーの電源を入れ、できればUSBハブを介さず直接接続して実行します。

```bash
scanimage -L
```

出力されたバックエンド名とUSBアドレスを含むdevice ID全体をコピーし、そのデバイスが公開するオプションを調べます。

```bash
scanimage -d '<device-id>' -A
```

device IDは`genesys:libusb:001:002`のような形式です。<br>
この例をそのまま使わず、現在の Macで`scanimage -L`が返した値を使ってください。

`sane-find-scanner`で分かるのは、USBまたはSCSIデバイスを検出したことだけです。<br>
利用できる SANEバックエンドがないスキャナーも表示されます。<br>
`scanimage -L`に出ないデバイスは、このプラグインでも使用できません。<br>
USB接続、 [SANE対応一覧](https://www.sane-project.org/sane-supported-devices.html)、対象バックエンドのマニュアルを確認してから進んでください。

### 4A. ソースからプラグインをビルドしてインストール

```bash
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
./install.sh
```

スクリプトはReleaseビルドを作成し、次の2ファイルをインストールします。

```text
~/Library/Application Support/negaflow/Plugins/sane/
  ├── negaflow-scanner-sane
  └── manifest.json
```

### 4B. 配布ZIPからインストール

リリースZIPを展開し、同梱のインストーラーを実行します。

```bash
./install.sh
```

配布版のインストールにSwiftツールチェーンは不要です。<br>
SANEは別途インストールしてください。

### 5. Negaflowで承認して確認

Negaflowを再起動して「スキャナーを読み込む」を開きます。<br>
プラグインのパス、バージョン、ライセンス、hashを確認して承認します。<br>
更新後に実行ファイルまたはmanifestが変わった場合は、再承認が必要です。

インストール済みの実行ファイルは直接確認することもできます。

```bash
"$HOME/Library/Application Support/negaflow/Plugins/sane/negaflow-scanner-sane" detect
```

`{"devices":[...]}`が返ればプラグインは動いています。<br>
`devices`が空なら、プラグインは起動したもののSANEが利用可能なスキャナーを返していません。<br>
プラグインを入れ直しても不足した SANEバックエンドの対応は増えないため、`scanimage -L`から確認してください。

## 対応スキャナー

次の表は、既知のSANE 1.4対象と、このプラグインが扱う経路をまとめたものです。<br>
同じ製品名のすべての個体が動くことを保証する表ではありません。<br>
[SANEの最新対応一覧](https://www.sane-project.org/sane-supported-devices.html)を確認し、接続した実機を`scanimage -L`と`scanimage -A`でも確認してください。

| スキャナー系統 | SANEバックエンド | SANE 1.4の状態 | プラグインでの処理 |
|---|---|---|---|
| Plustek OpticFilm 7200、7200 v2、7200i、7300、7400、7500i、7600i、8100 | `genesys` | Complete | フィルム専用スキャナー経路 |
| Plustek OpticFilm 8200i、USB `07b3:130d` | `genesys` | Complete | フィルム専用スキャナー経路 |
| Plustek OpticFilm 8200i、USB `07b3:1825`（GL128） | `genesys` | Unsupported | 利用可能なデバイスとして扱わない |
| Epson Perfection V700/V750、V800/V850 | `epson2` | Good | 報告された場合に透過原稿ソースと位置指定領域を使用 |
| Nikon Coolscan/LS系 | `coolscan3`、旧SCSI機は`coolscan` | 機種によりComplete〜Minimal | フィルム専用スキャナー経路 |
| Reflecta ProScan/CrystalScan/DigitDia、PIE PowerSlide | `pieusb`、旧SCSI機は`pie` | 機種により異なる | 報告されたオプションだけを使用 |
| その他の透過原稿対応フラットベッド・フィルムスキャナー | バックエンドにより異なる | 機種により異なる | 機能報告に従い、機種名によるfallbackは行わない |

OpticFilm 8200iには、同じ製品名で少なくとも2種類のUSB仕様があります。<br>
`07b3:130d`と `07b3:1825`ではSANEの対応状況が異なります。<br>
筐体の製品名ではなく、実際のUSB product IDを確認してください。

## 赤外線チャンネル

このプラグインで「IR使用可」とするのは、独立した赤外線画像を`irPath`としてNegaflowへ返せる場合です。<br>
バックエンド内部だけで動くゴミ取り機能は、IRチャンネルとして扱いません。

| スキャナー・バックエンド経路 | IRの状態 | 取得方法 | 独立したIR TIFF |
|---|---|---|---|
| OpticFilm 7200、7200 v2、7300、7400、8100 | 使用不可 | IRソースを公開しない機種 | なし |
| OpticFilm 7200i、7500i、7600i、8200i `07b3:130d` | `scanimage -A`にIRソースが出る場合に使用可 | `Transparency Adapter Infrared`の別パス | あり |
| OpticFilm 8200i `07b3:1825` | 使用不可 | SANE 1.4非対応の仕様 | なし |
| 標準`epson2`のEpson V700/V750/V800/V850 | 使用不可 | 標準ビルドは独立したIRモードを公開しない | なし |
| `SANE_FRAME_IR`を有効にしたカスタムEpson経路 | 条件付き | 実際に報告された場合だけ`Infrared`モードで別パス | あり |
| `--infrared`を公開するNikon `coolscan3` | 標準`scanimage`経路では使用不可 | `coolscan3`は1つの`SANE_FRAME_RGBI`を返しますが、`scanimage` 1.4はRGBとIRのTIFFへ分離できません | なし |
| `--clean-image`だけを公開するReflecta/PIE | IRチャンネルとしては使用不可 | ゴミ取りはバックエンド内で完結 | なし |
| その他のスキャナー | 条件付き | `scanimage -A`が有効な独立IR sourceまたはmodeを返す場合だけ | 寸法・形式確認後にあり |

IRパスにはRGBと同じ要求解像度とスキャン領域を使います。<br>
返す前に、両方の画像のピクセル寸法も一致しているか確認します。<br>
NegaflowはこのIR画像をGrainMend IRで利用できます。

## 要求値とエラー処理

- 要求DPIがデバイスの一覧または範囲に正確に含まれている必要があります。近い解像度には変更しません。
- 16-bit要求は、SANEのdepthが8より大きく、結果も実際に16-bit TIFFの場合だけ成功します。
- 物理スキャン領域にはmm単位の`-x/-y`範囲が必要です。位置指定には`-l/-t`も必要です。
- source、mode、depth、resolution、preview、geometryを適用した後、依存する項目を再確認します。
- プレビューにIRや多重露光を暗黙に追加しません。
- brightness、contrast、gammaをハードウェア多重露光の代わりには使いません。
- 結果が要求と違う場合や検証に失敗した場合は、ファイルを破棄してエラーを返します。

## Negaflowスキャナープロトコル

実行ファイルはサブコマンドで呼び出され、標準出力へJSONを書き込みます。

| コマンド | 入力 | 出力 |
|---|---|---|
| `detect` | なし | デバイス一覧JSON |
| `capabilities <deviceId>` | 任意の検出デバイス識別JSON | 解像度、モード、ビット深度、領域、露出、IR機能のJSON |
| `scan` | stdinのprotocol v2要求JSON | NDJSONの進行状況と最終結果またはエラー |
| `repair-sane-config` | なし | 旧版Negaflowプラグインが無効化したバックエンドだけを再有効化 |
| `tune-sane` | なし | `repair-sane-config`の互換エイリアス |
| `restore-sane` | なし | 最終手段として旧版の全体バックアップを復元 |

protocol v2の全イベントには`protocolVersion`、`requestID`、増加し続ける`sequence`が入ります。<br>
成功結果の`appliedOptions`は、出力TIFFと実際の適用値を確認した後にだけ返します。
Negaflowは`capabilities`が返した不透明な`capabilityToken`を次のスキャン要求へ自動で戻します。
CLIから直接呼び出す場合も同じ値を渡してください。省略すると、より遅い互換用の事前確認が
実行されます。

本スキャン要求の例:

```json
{
  "protocolVersion": 2,
  "requestID": "7A91B43D-90F8-41E2-B71D-04D17CD9E03B",
  "deviceID": "sane-genesys:libusb:001:002",
  "capabilityToken": "<capabilitiesが返した不透明なトークン>",
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

## SANE設定

現在のリリースは、Homebrewの共有`dll.conf`をフィルタリングしません。<br>
`detect`は旧版Negaflowプラグインが無効化した行だけを自動修復し、ディストリビューションとユーザーのコメントを保持します。同じ修復を手動で実行できます。

```bash
.build/release/negaflow-scanner-sane repair-sane-config
```

旧版の`dll.conf.negaflow-backup`が残っている場合、次のコマンドは現在のファイル全体をそのバックアップで置き換えます。バックアップ後の変更も戻るため、部分修復で解決しない場合にだけ使用してください。

```bash
.build/release/negaflow-scanner-sane restore-sane
```

## リポジトリ構成

| パス | 役割 |
|---|---|
| `Sources/SANEPluginCore` | SANE検出、機能解析、取得、TIFF検証、IR、露出マージ |
| `Sources/negaflow-scanner-sane` | Negaflowスキャナープロトコル v2用の薄いJSON/CLIアダプター |
| `Tests/SANEPluginCoreTests` | プロトコル、プロセス、オプション解析、TIFF、仮想スキャナーの回帰テスト |
| `Installer` | 一括PKG配布構成、インストールスクリプト、Installer.app用リソース |
| `scripts` | Universalビルド、署名、パッケージ、インストール、公証、リリース確認 |

## 開発時の確認

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

機種別の仮想スキャナーテストでは、実際のsubprocessとTIFF契約を使い、プレビュー、本スキャン、領域、IR経路を確認します。<br>
モーター、光学系、USB転送、最終画質は再現せず、実機検証としては扱いません。

## Releaseビルド

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
```

スクリプトは`arm64`と`x86_64`をビルドしてUniversal実行ファイルに結合し、dSYM作成、署名、パッケージ、SHA-256記録、アーカイブ検証まで行います。<br>
出力先は`.build/release-artifacts/`です。

配布署名と公証には、`NEGAFLOW_CODESIGN_IDENTITY`、`NEGAFLOW_NOTARY_KEYCHAIN_PROFILE`、 `NEGAFLOW_RELEASE_MODE=distribution`が別途必要です。

一括PKGとDMGは次のコマンドで作成します。

```bash
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

このビルドは、固定した公式Homebrewパッケージを検証してからインストーラーコンポーネントを取り込み、Universalプラグインをビルドし、実際にはインストールせずにPKGとDMGを検査します。<br>
配布用の署名と公証には、`NEGAFLOW_INSTALLER_MODE=distribution`、PKG用の `NEGAFLOW_INSTALLER_IDENTITY`、既存のアプリ署名IDと公証プロファイルも必要です。

## ライセンス

このプロジェクトは[GPL-2.0-or-later](LICENSE)で配布されます。<br>
リリースアーカイブにはライセンス表示とGNU GPL v2全文の[COPYING](COPYING)が含まれます。

一括インストーラーには、同梱するHomebrewインストーラーコンポーネントとネットワーク経由で導入するSANE backendsの[サードパーティー通知](THIRD_PARTY_NOTICES.md)も含まれます。<br>
同じバージョンのプラグイン完全ソースアーカイブは、リリースZIP内と同じリリース場所に提供され、<br>
PKGペイロードとDMGの両方にも含まれます。

Negaflow本体は別のApache-2.0プロジェクトです。<br>
製品名とスキャナー名は、互換対象または測定対象を示すためにだけ使用し、それぞれの権利は各所有者に帰属します。
