<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">macOS と Windows で使う negaflow SANE フィルムスキャナープラグイン</p>

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

**negaflow-scanner-sane**は、SANEで利用できるフィルムスキャナーを [negaflow](https://github.com/habinsong/negaflow)に接続します。<br>
`scanimage`を実行してスキャナーが公開しているオプションを読み取り、デバイス情報、機能、進行状況、TIFFのパスを negaflowスキャナープロトコル v2で返します。

独自のスキャン画面を備えた別アプリではありません。<br>
インストールして承認した後は、 negaflowの「スキャナーを読み込む」から使用します。

プラグインと本体は別々のプログラムです。<br>
SANE固有のコードはすべてGPL-2.0-or-laterのこのリポジトリに置かれ、Apache-2.0のnegaflow本体とは、別プロセス、コマンドライン引数、パイプ、JSONだけで通信します。

## 機能

- `scanimage -L`によるスキャナー検出
- デバイスが現在返す`scanimage -A`の内容からスキャン項目を構成
- 要求値を近い既定値へ置き換えないプレビューと本スキャン
- 結果を返す前に解像度、カラーモード、ビット深度、寸法、TIFF形式を確認
- バックエンドが必要な範囲を返した場合だけ、mm単位のスキャン領域を使用
- バックエンドが実際に提供できる場合だけ、独立した赤外線チャンネルを取得
- 赤外パスに本スキャンと同じガンマテーブルと焦点を渡し、フィルムベースが切れず両パスの焦点面が揃う
- `--scan-exposure-time`が必要な露出計画を満たす場合だけ、ハードウェア多重露光を使用
- 現在のプラグインインスタンスが起動した`scanimage`プロセスだけを停止

スキャナー名だけで機能を判断しません。<br>
接続中のデバイスとSANEバックエンドが報告した項目だけを negaflowに表示します。

## 動作環境

- negaflow が先に入っていること
- SANE が対応するフィルムスキャナー
- macOS 14.0 以降、または Windows 11

## インストール

二つの環境で手順がかなり違うので、それぞれ別のページにしました。

| 環境 | ページ |
|---|---|
| macOS | [macOS へのインストール](negaflow-mac/docs/README_ja.md) |
| Windows | [Windows へのインストール](negaflow-windows/docs/README_ja.md) |

短くまとめると次のとおりです。[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases)
から自分の環境に合うインストーラを取って実行し、negaflow を開き直してプラグインを承認します。
macOS ではインストーラが Homebrew 経由で SANE まで用意します。Windows では SANE の実行ファイルが
インストーラに入っています。

## 対応スキャナー

次の表は、既知のSANE 1.4対象と、このプラグインが扱う経路をまとめたものです。<br>
同じ製品名のすべての個体が動くことを保証する表ではありません。<br>
[SANEの最新対応一覧](https://www.sane-project.org/sane-supported-devices.html)を確認し、接続した実機を`scanimage -L`と`scanimage -A`でも確認してください。

| スキャナー系統 | SANEバックエンド | SANE 1.4の状態 | プラグインでの処理 |
|---|---|---|---|
| Plustek OpticFilm 7200、7200 v2、7200i、7300、7400 v2、7500i、7600i | `genesys` | Complete | フィルム専用スキャナー経路 |
| Plustek OpticFilm 7400 v1 | `genesys` | 対応表ではCompleteだが、機種固有の修正はSANE 1.4.0以降 | capabilityベース経路、stock 1.4.0実機結果は未検証 |
| Plustek OpticFilm 8100、USB `07b3:130c` | `genesys` | Complete | フィルム専用スキャナー経路 |
| Plustek OpticFilm 8100、USB `07b3:1824` | なし | Unsupported | 利用可能なデバイスとして扱わない |
| Plustek OpticFilm 8200i、USB `07b3:130d` | `genesys` | Complete | フィルム専用スキャナー経路 |
| Plustek OpticFilm 8200i、USB `07b3:1825`（GL128） | なし | Unsupported | 利用可能なデバイスとして扱わない |
| Plustek OpticFilm 120、120 Pro、135、135i、9000i Ai | なし | Unsupported | 利用可能なデバイスとして扱わない |
| Epson Perfection V700/V750（GT-X900）、V800/V850（GT-X980） | `epson2` | Good | 報告された場合に透過原稿ソースと位置指定領域を使用 |
| Nikon Coolscan LS-2000、LS-40 ED、LS-50 ED、LS-4000 ED、LS-8000 ED | `coolscan3` | 機種によりComplete〜Minimal | フィルム専用スキャナー経路 |
| Nikon Coolscan LS-5000 ED | `coolscan3` | SANE 1.4では未検証、LS-50と同様に動作する可能性あり | フィルム専用スキャナー経路 |
| Nikon Coolscan LS-20、LS-30、LS-1000 | `coolscan` | 機種により異なる | SCSI専用 |
| Nikon Coolscan LS-9000 ED | なし | Unsupported | 利用可能なデバイスとして扱わない |
| Reflecta ProScan/CrystalScan/DigitDia、PIE PowerSlide | `pieusb`、旧SCSI機は`pie` | 機種とモデル番号により異なる | 報告されたオプションだけを使用 |
| Pacific Image PrimeFilm XA、XAs、XA Plus | なし | Unsupported | 利用可能なデバイスとして扱わない |
| その他の透過原稿対応フラットベッド・フィルムスキャナー | バックエンドにより異なる | 機種により異なる | 機能報告に従い、機種名によるfallbackは行わない |

### 製品名はハードウェアを示しません

OpticFilm 8100と8200iには、それぞれ同じ製品名で少なくとも2種類のUSB仕様があります。<br>
`07b3:130c`と`07b3:130d`は`genesys`が扱いますが、`07b3:1824`と`07b3:1825`はどのバックエンドも
扱えない別のGenesysチップを使っています。<br>
旧来の名前のまま売られる新しいリビジョンはSANE側で解決できないため、筐体の製品名ではなく実際の
USB product IDを確認してください。

見分けを難しくする落とし穴がもう2つあります。

- `pieusb`はUSB IDと**モデル番号**の両方を見ます。ReflectaとPIEの機器は`05e3:0145`のようにIDを
  共有するため、モデル番号が`pieusb.conf`にある機器だけが使えます。
- `epson2`はEpsonスキャナーを日本国内の型番で認識します。`scanimage -L`はPerfection V800/V850を
  `GT-X980`、V700/V750を`GT-X900`と表示します。別の機器ではなく同じスキャナーです。

## 赤外線チャンネル

このプラグインで「IR使用可」とするのは、独立した赤外線画像を`irPath`としてnegaflowへ返せる場合です。<br>
バックエンド内部だけで動くゴミ取り機能は、IRチャンネルとして扱いません。

| スキャナー・バックエンド経路 | IRの状態 | 取得方法 | 独立したIR TIFF |
|---|---|---|---|
| OpticFilm 7200、7200 v2、7300、7400、8100 | 使用不可 | IRソースを公開しない機種 | なし |
| OpticFilm 7200i、7500i、7600i、8200i `07b3:130d` | `scanimage -A`にIRソースが出る場合に使用可 | `Transparency Adapter Infrared`の別パス | あり |
| OpticFilm 8200i `07b3:1825` | 使用不可 | SANE 1.4非対応の仕様 | なし |
| 標準`epson2`のEpson V700/V750/V800/V850 | 使用不可 | 標準ビルドは`SANE_FRAME_IR`が外れたままコンパイルされる | なし |
| `mac26`版のEpson V700/V750/V800/V850 | `scanimage -A`が赤外線モードを報告すれば利用可能 | パッチ済み`epson2`の`Infrared`モードで別パス | あり |
| `--infrared`を公開するNikon `coolscan3` | 標準`scanimage`経路では使用不可 | `coolscan3`は1つの`SANE_FRAME_RGBI`を返しますが、`scanimage` 1.4はRGBとIRのTIFFへ分離できません | なし |
| `--clean-image`だけを公開するReflecta/PIE | IRチャンネルとしては使用不可 | ゴミ取りはバックエンド内で完結 | なし |
| その他のスキャナー | 条件付き | `scanimage -A`が有効な独立IR sourceまたはmodeを返す場合だけ | 寸法・形式確認後にあり |

IRパスにはRGBと同じ要求解像度とスキャン領域を使います。<br>
返す前に、両方の画像のピクセル寸法も一致しているか確認します。<br>
negaflowはこのIR画像をGrainMend IRで利用できます。

## トラブルシューティング: インストールに失敗する

失敗画面には「インストールに失敗しました」としか出ません。macOSインストーラーはパッケージ
スクリプトを終了コードだけで判定し、スクリプトの出力を画面に出しません。インストーラーが
開いている間に⌘Lを押すか、後からログを読みます。

```bash
sudo grep -iE "negaflow|Error:" /var/log/install.log | tail -60
```

| ログ | 原因 |
|---|---|
| `Your Command Line Tools are too outdated` | `mac26`版はSANEをコンパイルするが、実行中のmacOSより古いCommand Line ToolsはHomebrewが拒否する |
| `Homebrew was not installed at the supported prefix` | `/opt/homebrew`または`/usr/local`に`brew`がない |
| `no supported logged-in user was found` | コンソールユーザーがいない。SSHやログインウインドウから実行した場合 |
| `patched scanimage was not installed` | SANEのビルド失敗。Homebrewのエラーがこの行の上にある |

Command Line Toolsが古い場合:

```bash
sudo rm -rf /Library/Developer/CommandLineTools
```

```bash
xcode-select --install
```

古い環境にも`git`は残るため、ファイルの有無だけでは導入済みと判定されます。インストーラーは
代わりに実行中のmacOSのSDKを探し、無ければ何も入れる前に停止します。

Homebrewは事前に入れておく必要はありません。パッケージに公式署名済みのHomebrewインストーラーが
含まれ、`brew`が無いときだけ実行します。既存のHomebrewはそのまま使い、置き換えもアップグレードも
しません。

`mac26`版はSANE 1.4.0をソースからビルドするため数分かかり、進行バーはビルドの進行を表示
できません。`mac14`版はビルド済みbottleを入れるのですぐ終わります。

## トラブルシューティング: スキャナーが見つからない

negaflowの**承認済み**は、プラグインの実行ファイルを実行してよいという意味です。<br>
スキャナーが見つかったという意味ではありません。デバイスの検出は`scanimage -L`が返した結果その
ものなので、そこに出ないスキャナーはnegaflowにも出ず、アプリやプラグインを再インストールしても
変わりません。

macOSにはアプリごとに有効化するUSB権限はありません。negaflowとこのプラグインはApp Sandboxを
使わないため、「プライバシーとセキュリティ」の設定がスキャナーへのアクセスを止めることもありません。

### 1. どの段階で止まっているかを切り分ける

スキャナーの電源を入れて接続した状態で、順に実行します。

```bash
system_profiler SPUSBDataType
```

```bash
scanimage -L
```

```bash
"$HOME/Library/Application Support/negaflow/Plugins/sane/negaflow-scanner-sane" detect
```

| USB一覧 | `scanimage -L` | `detect` | 問題の場所 |
|---|---|---|---|
| スキャナーなし | なし | `{"devices":[]}` | SANE以前のケーブル、ポート、電源 |
| スキャナーあり | なし | `{"devices":[]}` | SANEバックエンド、またはデバイスを占有している別プロセス |
| スキャナーあり | デバイスあり | `{"devices":[]}` | プラグインが参照しない場所へのSANEインストール |
| スキャナーあり | デバイスあり | デバイスあり | negaflow側: 「スキャナーを読み込む」を開き直して再承認 |

### 2. よくある原因

| 症状 | 原因 | 対処 |
|---|---|---|
| `scanimage: command not found` | SANEが未インストール、またはその`bin`が現在の`PATH`にない | 通常は`brew install sane-backends`を実行し、修正版経路では上記のヘルパーと`export`を使用 |
| USB一覧にスキャナーが出ない | ハブ、ドック、変換アダプタ、ケーブル、電源 | ハブを外してMacへ直結し、別のポートも試します。USB 2.0のフィルムスキャナーはUSB-C変換で失敗しやすいです |
| `sane-find-scanner`では見えるのに`no SANE devices found` | この機種を担当する有効なバックエンドがない | [SANE対応機器一覧](https://www.sane-project.org/sane-supported-devices.html)を確認し、3のログを読みます |
| USB一覧にはあり、`scanimage -L`が空で、`repair-sane-config`が`notNeeded` | SANEが知らないハードウェアリビジョン | USB product IDを[対応スキャナー](#対応スキャナー)の表と照合します。旧来の製品名で売られる新しいリビジョンはこちらでは解決できません |
| Coolscan LS-50やLS-5000がUSB一覧から消える | この機種で知られているUSBポートの故障 | 別のケーブルとポートで確認します。Macが列挙すらしない場合はドライバーではなくハードウェアの故障です |
| `another process has device opened for exclusive access`、`device busy`、`is not configured` | 別のプログラムがUSBインターフェースを占有済み | VueScan、SilverFast、イメージキャプチャ、メーカー製ユーティリティを終了し、スキャナーを接続し直して再試行します |
| `sudo scanimage -L`でだけ見つかる | インターフェースが占有されている、または解放されていない | 上の占有を解消します。negaflowはプラグインをrootで実行しないため`sudo`は回避策になりません |
| ターミナルでは見つかるがnegaflowでは見えない | 対応するHomebrew kegパス以外にSANEがある | 同梱インストーラーを再実行。MacPortsや別の手動ビルドは使用しません |
| `open of device ... failed: Invalid argument` | 一度開いた後にUSBアドレスが変わった、またはSANE設定ディレクトリがない | `detect`をもう一度実行し、`/opt/homebrew/etc/sane.d`か`/usr/local/etc/sane.d`があるか確認します |
| 更新前は動いていた | 選択したSANE kegが削除または置換された | 対応するインストーラーを再実行し、`brew list --versions sane-backends sane-backends-negaflow`を確認 |
| 旧版negaflowプラグインの導入後に一覧が空 | 旧版が`dll.conf`でバックエンドを無効化した | [SANE設定](#sane設定)の`repair-sane-config`を実行します |

### 3. バックエンドのログを読む

```bash
SANE_DEBUG_DLL=3 scanimage -L 2>&1 | tail -40
```

どのバックエンドが読み込まれ、どこで失敗したかがわかります。<br>
バックエンドを1つに絞るときは`SANE_DEBUG_GENESYS=128`や`SANE_DEBUG_EPSON2=128`のように、その
バックエンドの変数を使います。

報告にはmacOSのバージョン、Macの機種、`scanimage --version`、
`brew list --versions sane-backends sane-backends-negaflow`、スキャナーの機種名と、上の3段階の出力が必要です。

## 要求値とエラー処理

- 要求DPIがデバイスの一覧または範囲に正確に含まれている必要があります。近い解像度には変更しません。
- 16-bit要求は、SANEのdepthが8より大きく、結果も実際に16-bit TIFFの場合だけ成功します。
- 物理スキャン領域にはmm単位の`-x/-y`範囲が必要です。位置指定には`-l/-t`も必要です。
- source、mode、depth、resolution、preview、geometryを適用した後、依存する項目を再確認します。
- プレビューにIRや多重露光を暗黙に追加しません。
- brightness、contrast、gammaをハードウェア多重露光の代わりには使いません。
- 結果が要求と違う場合や検証に失敗した場合は、ファイルを破棄してエラーを返します。

## negaflowスキャナープロトコル

実行ファイルはサブコマンドで呼び出され、標準出力へJSONを書き込みます。

| コマンド | 入力 | 出力 |
|---|---|---|
| `detect` | なし | デバイス一覧JSON |
| `capabilities <deviceId>` | 任意の検出デバイス識別JSON | 解像度、モード、ビット深度、領域、露出、IR機能のJSON |
| `scan` | stdinのprotocol v2要求JSON | NDJSONの進行状況と最終結果またはエラー |
| `repair-sane-config` | なし | 旧版negaflowプラグインが無効化したバックエンドだけを再有効化 |
| `tune-sane` | なし | `repair-sane-config`の互換エイリアス |
| `restore-sane` | なし | 最終手段として旧版の全体バックアップを復元 |

protocol v2の全イベントには`protocolVersion`、`requestID`、増加し続ける`sequence`が入ります。<br>
成功結果の`appliedOptions`は、出力TIFFと実際の適用値を確認した後にだけ返します。
negaflowは`capabilities`が返した不透明な`capabilityToken`を次のスキャン要求へ自動で戻します。
CLIから直接呼び出す場合も同じ値を渡してください。省略すると、より遅い互換用の事前確認が
実行されます。

capabilityは実際にスキャンする状態で読み取ります。SANEのオプションは互いの有効・無効を変えます。`epson2`はLineartで深度を、リニアガンマを選ぶと明るさを非アクティブにします。そのため装置の既定状態のダンプはスキャン時の状態を表しません。透過ソースとスキャンモード、中立の色・ガンマを適用した状態でオプションを読み、その状態をトークンに含めます。異なるモードを要求した場合はそのモードで読み直します。

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

修正済みkegは独自の`etc/sane.d`を使い、通常のHomebrew版`dll.conf`を変更しません。<br>
`detect`は旧版negaflowプラグインが無効化した行だけを自動修復し、ディストリビューションとユーザーのコメントを保持します。同じ修復を手動で実行できます。

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

このビルドは、固定した公式Homebrewパッケージを検証してからインストーラーコンポーネントを取り込み、Apple Silicon専用版とUniversal版の両方を作成し、実際にはインストールせずにそれぞれのPKGとDMGを検査します。<br>
`NEGAFLOW_INSTALLER_ARCHITECTURE`に`arm64`または`universal`を指定すると片方だけを、既定値の`all`は両方をビルドします。<br>
`NEGAFLOW_INSTALLER_VARIANT=all`を指定すると標準版とCoolscan版の両方を作成し、既定値では標準版だけを作成します。<br>
配布用の署名と公証には、`NEGAFLOW_INSTALLER_MODE=distribution`、PKG用の `NEGAFLOW_INSTALLER_IDENTITY`、既存のアプリ署名IDと公証プロファイルも必要です。

## ライセンス

このプロジェクトは[GPL-2.0-or-later](LICENSE)で配布されます。<br>
リリースアーカイブにはライセンス表示とGNU GPL v2全文の[COPYING](COPYING)が含まれます。

インストーラーには同梱するHomebrewコンポーネントと、Coolscan版でユーザーのMacに
ビルドする修正済みSANEソースの[サードパーティー通知](THIRD_PARTY_NOTICES.md)も含まれます。<br>
同じバージョンのプラグイン完全ソースアーカイブは、リリースZIP内と同じリリース場所に提供され、<br>
PKGペイロードとDMGの両方にも含まれます。

negaflow本体は別のApache-2.0プロジェクトです。<br>
製品名とスキャナー名は、互換対象または測定対象を示すためにだけ使用し、それぞれの権利は各所有者に帰属します。
