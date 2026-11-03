# 対応スキャナー

[ドキュメントホーム](README.md)

次の表は、既知の SANE 対象と、このプラグインが扱う経路をまとめたものです。同じ製品名の
すべての個体が動くことを保証する表ではありません。
[SANE の最新対応一覧](https://www.sane-project.org/sane-supported-devices.html)を確認し、接続した
実機も `scanimage -L` と `scanimage -A` で確かめてください。

「パッチ済み SANE」とは、`mac26` 版がビルドする SANE と Windows インストーラーに同梱された SANE
ランタイムのことです。SANE 1.4.0 に
[`sane-runtime/SOURCES.md`](../../negaflow-mac/sane-runtime/SOURCES.md) のパッチを加えたものです。
`mac14` 版はこれらのパッチを含まない Homebrew 標準の SANE 1.4.0 を使います。

| スキャナー系統 | SANEバックエンド | 状態 | プラグインでの処理 |
|---|---|---|---|
| Plustek OpticFilm 7200、7200 v2、7200i、7300、7400 v2、7500i、7600i v2 | `genesys` | SANE 1.4でComplete | フィルム専用スキャナー経路 |
| Plustek OpticFilm 7400 v1、7600i v1 | `genesys` | 1.4.0以降にupstreamで修正済み、パッチ済みSANEに含む | フィルム専用スキャナー経路、実機未確認 |
| Plustek OpticFilm 8100、USB `07b3:130c`（GL845） | `genesys` | SANE 1.4でComplete | フィルム専用スキャナー経路、実機確認済み |
| Plustek OpticFilm 8200i、USB `07b3:130d`（GL845） | `genesys` | SANE 1.4でComplete | フィルム専用スキャナー経路 |
| Plustek OpticFilm 8200i 新型、USB `07b3:1825`（GL128、SANEでは「8200i SE」と表示） | `genesys`、パッチ済みSANEのみ | upstreamでBasic：16-bit、150〜7200 dpi、赤外線なし | フィルム専用スキャナー経路、実機未確認 |
| Plustek OpticFilm 8100 V2、USB `07b3:1824`（GL128） | なし | Unsupported | 使用可能な機器として扱わない |
| Plustek OpticFilm 8300i、USB `07b3:181f`（GL128、SEで測定） | なし | Unsupported | 使用可能な機器として扱わない |
| Plustek OpticFilm 9000i Ai、USB `07b3:182f` | なし | Unsupported | 使用可能な機器として扱わない |
| Plustek OpticFilm 120、120 Pro、135、135i | なし | Unsupported | 使用可能な機器として扱わない |
| Epson Perfection V700/V750（GT-X900）、V800/V850（GT-X980） | `epson2` | Good | 報告される場合は透過ソースと位置指定のフラットベッド領域を使用 |
| Nikon Coolscan LS-40 ED、LS-50 ED、LS-5000 ED（USB） | `coolscan3`、`coolscan2` | Complete（LS-40）、Minimal（LS-50）、Untested（LS-5000） | 下記の制約付きのフィルム専用スキャナー経路、実機未確認 |
| Nikon Coolscan LS-4000 ED、LS-8000 ED（IEEE 1394 / FireWire） | SBP-2経由の`coolscan3`、`coolscan2` | LinuxでGood | macOS 26では使用不可、WindowsとmacOS 14/15は未確認（下記参照） |
| Nikon Coolscan LS-30、LS-2000（SCSI） | `coolscan3` | Complete（LS-30）、Good（LS-2000） | SCSIホストアダプターが必要 |
| Nikon Coolscan LS-20、LS-1000 | `coolscan` | 機種ごとに異なる | SCSI専用 |
| Nikon Coolscan LS-9000 ED | なし | Unsupported | 使用可能な機器として扱わない |
| Reflecta ProScan/CrystalScan/DigitDia、PIE PowerSlide | `pieusb`、旧SCSI機は`pie` | 機種とモデル番号で異なる | 報告されたオプションのみ使用 |
| Pacific Image PrimeFilm XA、XAs、XA Plus | なし | Unsupported | 使用可能な機器として扱わない |
| その他の透過原稿対応フラットベッド・フィルムスキャナー | バックエンドごとに異なる | 機種ごとに異なる | 機能報告に基づき、モデル名での代替処理なし |

## 製品名はハードウェアを示しません

Plustek は新しいハードウェアを旧来の製品名のまま販売しています。見分けるのは筐体の名前ではなく
USB product ID です。

| 筐体の表記 | USB ID | コントローラー | SANE |
|---|---|---|---|
| OpticFilm 8100 旧型 | `07b3:130c` | GL845 | SANE 1.4.0の`genesys` |
| OpticFilm 8100 新型（V2） | `07b3:1824` | GL128 | なし |
| OpticFilm 8200i 旧型 | `07b3:130d` | GL845 | SANE 1.4.0の`genesys` |
| OpticFilm 8200i 新型 | `07b3:1825` | GL128 | 2026年9月からupstream masterの`genesys`、パッチ済みSANEのみ |
| OpticFilm 8300i SE（Aiは未確認） | `07b3:181f` | GL128 | なし |
| OpticFilm 9000i Ai | `07b3:182f` | 非公開 | なし |

SE と Ai はハードウェアではなく、同梱される SilverFast の版の名前です。旧型の 8200i SE・Ai は
`130d`、新型は `1825` です。

GL128 の 3 機種はレジスター配置こそ同じですが、値まで同じではありません。SANE の GL128 コードが
大部分を拠っている USB キャプチャの解読は、オープンなドライバー
[pyopticfilm](https://github.com/jboneng/pyopticfilm) によるもので、その差分も記録されています。
8100 V2 は起動時の ASIC クロックとレジスター `0x0B` が異なり、8300i SE は露光・センサータイミング・
モーターテーブルがすべて独自です。8200i SE のテーブルをそのまま使うのは、モーターとランプの制御を
推測で行うことになります。pyopticfilm には、8100 V2 でレジスターのビットを 1 つ立てた直後にモーターが
引っかかった記録があります。そのため、このプラグインは SANE のビルドが実際に駆動し、その機器で
スキャンが確認されるまで GL128 機種を有効にしません。

ID は Mac では `system_profiler SPUSBDataType`、Windows ではデバイスマネージャーで確認できます。

見分けを難しくする落とし穴がもう 2 つあります。

- `pieusb` は USB ID と**モデル番号**の両方を見ます。Reflecta と PIE の機器は `05e3:0145` のように
  ID を共有するため、モデル番号が `pieusb.conf` にある機器だけが使えます。
- `epson2` は Epson スキャナーを日本国内の型番で認識します。`scanimage -L` は Perfection V800/V850 を
  `GT-X980`、V700/V750 を `GT-X900` と表示します。同じスキャナーです。

## Nikon Coolscan

このプラグインで実機確認を済ませた Coolscan はまだありません。以下は `coolscan3` のソースと
プラグインのコードを読んでまとめたものです。

### 接続

LS-4000 ED と LS-8000 ED には IEEE 1394（FireWire）ポートしかありません。SANE はこれらを SBP-2
経由の SCSI 機器として扱うため、機器名は USB ではなく `coolscan3:scsi:...` になります。

- **macOS 26 には FireWire がまったくなく**、アダプターを使っても戻りません。パッチ済み SANE を
  使う唯一のインストーラーである `mac26` 版では、この 2 機種に届きません。
- macOS 14 と 15 には FireWire が残っており、SANE にも macOS 用の SCSI インターフェースがありますが、
  `mac14` 版でこの経路を試したことはありません。
- Windows では、SANE が SCSI パススルー経路で SBP-2 スキャナーに届く必要があります。こちらも
  試したことはありません。

現実的な Coolscan の対象は、USB を使う LS-40 ED、LS-50 ED、LS-5000 ED です。

### プラグイン経路の動作

| 項目 | 動作 | 結果 |
|---|---|---|
| カラーモード | `coolscan2`/`coolscan3`には`--mode`がなく、常にRGBを返す | `color`だけを報告します。白黒フィルムもカラーでスキャンして negaflow が現像し、要求はフィルム種別以外カラーネガと同じです |
| スキャン領域 | 領域オプションがmmではなく、スキャナー最大解像度でのピクセル | negaflow が領域を選べないため、プラグインが既定の 36 x 24 mm をピクセルに変換します。LS-8000 の中判フレームは左上の 36 x 24 mm だけになります |
| フレーム | `--frame`を送らない | ストリップホルダーでは最初のフレームだけをスキャンします |
| フォーカス | `coolscan3`は要求されたときだけオートフォーカスするが、negaflow は要求しない | スキャナーの現在のフォーカス位置でスキャンします |
| 赤外線 | `--infrared`はRGBIの1フレームを返す | IRチャンネルとしては提供しません |
| フィルム種別 | `--negative`はスキャナーに色を反転させる | 常に`--negative=no`を送り、negaflow は元のネガを受け取ります |

表の最後の 2 行は意図した動作です。最初の 4 行は残りの作業で、それぞれ実機での確認が必要です。

## 赤外線チャンネル

ここでの「IR 使用可」は、独立した赤外線画像を `irPath` として negaflow へ返せる場合を指します。
バックエンド内部だけで動くゴミ取り機能は、IR チャンネルとして扱いません。

| スキャナー・バックエンド経路 | IRの状態 | 取得方法 | 独立したIR TIFF |
|---|---|---|---|
| OpticFilm 7200、7200 v2、7300、7400、8100 | 使用不可 | IRソースを公開しない機種 | なし |
| OpticFilm 7200i、7500i、7600i、8200i `07b3:130d` | `scanimage -A`にIRソースが出る場合に使用可 | `Transparency Adapter Infrared`の別パス | あり |
| OpticFilm 8200i 新型 `07b3:1825` | 使用不可 | SANEのGL128コードにまだ赤外線パスがない | なし |
| OpticFilm 8100 V2、8300i、9000i | 使用不可 | SANEバックエンドがない | なし |
| `mac26`版のEpson V700/V750/V800/V850 | `scanimage -A`が赤外線モードを報告すれば使用可 | パッチ済み`epson2`の`Infrared`モードで別パス | あり |
| 標準`epson2`のEpson V700/V750/V800/V850 | 使用不可 | 標準ビルドは`SANE_FRAME_IR`が外れたままコンパイルされる | なし |
| `--infrared`を公開するNikon `coolscan3` | `scanimage`経路では使用不可 | `coolscan3`は1つの`SANE_FRAME_RGBI`を返すが、`scanimage` 1.4はRGBとIRのTIFFへ分離できない | なし |
| `--clean-image`だけを公開するReflecta/PIE | IRチャンネルとしては使用不可 | ゴミ取りはバックエンド内で完結 | なし |
| その他のスキャナー | 条件付き | `scanimage -A`が有効な独立IR sourceまたはmodeを返す場合だけ | 寸法・形式確認後にあり |

IR パスには RGB と同じ要求解像度とスキャン領域を使い、両方の画像のピクセル寸法が一致しているかを
確認してから返します。negaflow はこの IR 画像を GrainMend IR で利用できます。
