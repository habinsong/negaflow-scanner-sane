# 開発

[ドキュメントホーム](README.md)

## negaflowスキャナープロトコル

実行ファイルはサブコマンドで呼び出され、標準出力へ JSON を書き込みます。

| コマンド | 入力 | 出力 |
|---|---|---|
| `detect` | なし | デバイス一覧JSON |
| `capabilities <deviceId>` | 任意の検出デバイス識別JSON | 解像度、モード、ビット深度、領域、露出、IR機能のJSON |
| `scan` | stdinのprotocol v2要求JSON | NDJSONの進行状況と最終結果またはエラー |
| `repair-sane-config` | なし | 旧版negaflowプラグインが無効化したバックエンドだけを再有効化 |
| `tune-sane` | なし | `repair-sane-config`の互換エイリアス |
| `restore-sane` | なし | 最終手段として旧版の全体バックアップを復元 |

protocol v2 の全イベントには `protocolVersion`、`requestID`、増加し続ける `sequence` が入ります。
成功結果の `appliedOptions` は、出力 TIFF と実際の適用値を確認した後にだけ返します。negaflow は
`capabilities` が返した不透明な `capabilityToken` を次のスキャン要求へ自動で戻します。CLI から
直接呼び出す場合も同じ値を渡してください。省略すると、より遅い互換用の事前確認が実行されます。

capability は実際にスキャンする状態で読み取ります。SANE のオプションは互いの有効・無効を変えるから
です。`epson2` は Lineart で深度を、リニアガンマを選ぶと明るさを非アクティブにします。そのため装置の
既定状態のダンプはスキャン時の状態を表しません。透過ソースとスキャンモード、中立の色・ガンマを
適用した状態でオプションを読み、その状態をトークンに含めます。異なるモードを要求した場合はその
モードで読み直します。

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

## 要求値とエラー処理

- 要求 DPI がデバイスの一覧または範囲に正確に含まれている必要があります。近い解像度には変更しません。
- 16-bit 要求は、SANE の depth が 8 より大きく、結果も実際に 16-bit TIFF の場合だけ成功します。
- 物理スキャン領域には mm 単位の `-x/-y` 範囲が必要です。位置指定には `-l/-t` も必要です。
- source、mode、depth、resolution、preview、geometry を適用した後、依存する項目を再確認します。
- プレビューに IR や多重露光を暗黙に追加しません。
- brightness、contrast、gamma をハードウェア多重露光の代わりには使いません。
- 結果が要求と違う場合や検証に失敗した場合は、ファイルを破棄してエラーを返します。

## リポジトリ構成

| パス | 役割 |
|---|---|
| `Sources/SANEPluginCore` | SANE検出、機能解析、取得、TIFF検証、IR、露出マージ |
| `Sources/negaflow-scanner-sane` | negaflowスキャナープロトコル v2用の薄いJSON/CLIアダプター |
| `Tests/SANEPluginCoreTests` | プロトコル、プロセス、オプション解析、TIFF、仮想スキャナーの回帰テスト |
| `Installer` | 一括PKG配布構成、インストールスクリプト、Installer.app用リソース |
| `scripts` | Universalビルド、署名、パッケージ、インストール、公証、リリース確認 |

## 開発時の確認

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

機種別の仮想スキャナーテストでは、実際の subprocess と TIFF 契約を使い、プレビュー、本スキャン、
領域、IR 経路を確認します。モーター、光学系、USB 転送、最終画質は再現しないので、実機検証では
ありません。

## Releaseビルド

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
```

スクリプトは `arm64` と `x86_64` をビルドして Universal 実行ファイルに結合し、dSYM 作成、署名、
パッケージ、SHA-256 記録、アーカイブ検証まで行います。出力先は `.build/release-artifacts/` です。

配布署名と公証には、`NEGAFLOW_CODESIGN_IDENTITY`、`NEGAFLOW_NOTARY_KEYCHAIN_PROFILE`、
`NEGAFLOW_RELEASE_MODE=distribution` が別途必要です。

一括 PKG と DMG は次のコマンドで作成します。

```bash
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

このビルドは、固定した公式 Homebrew パッケージを検証してからインストーラーコンポーネントを
取り込み、Apple Silicon 専用版と Universal 版の両方を作成し、実際にはインストールせずにそれぞれの
PKG と DMG を検査します。`NEGAFLOW_INSTALLER_ARCHITECTURE` に `arm64` または `universal` を指定
すると片方だけを、既定値の `all` は両方をビルドします。`NEGAFLOW_INSTALLER_VARIANT=all` を指定
すると標準版と Coolscan 版の両方を作成し、既定値では標準版だけを作成します。配布用の署名と公証には、
`NEGAFLOW_INSTALLER_MODE=distribution`、PKG 用の `NEGAFLOW_INSTALLER_IDENTITY`、既存のアプリ署名 ID
と公証プロファイルも必要です。
