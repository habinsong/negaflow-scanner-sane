# 対応スキャナー

[ドキュメントホーム](README.md)

次の表は、既知の SANE 1.4 対象と、このプラグインが扱う経路をまとめたものです。同じ製品名の
すべての個体が動くことを保証する表ではありません。
[SANE の最新対応一覧](https://www.sane-project.org/sane-supported-devices.html)を確認し、接続した
実機も `scanimage -L` と `scanimage -A` で確かめてください。

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

## 製品名はハードウェアを示しません

OpticFilm 8100 と 8200i には、それぞれ同じ製品名で少なくとも 2 種類の USB 仕様があります。
`07b3:130c` と `07b3:130d` は `genesys` が扱いますが、`07b3:1824` と `07b3:1825` はどのバックエンドも
扱えない別の Genesys チップを使っています。旧来の名前のまま売られる新しいリビジョンは SANE 側で
解決できないため、筐体の製品名ではなく実際の USB product ID を確認してください。

見分けを難しくする落とし穴がもう 2 つあります。

- `pieusb` は USB ID と**モデル番号**の両方を見ます。Reflecta と PIE の機器は `05e3:0145` のように
  ID を共有するため、モデル番号が `pieusb.conf` にある機器だけが使えます。
- `epson2` は Epson スキャナーを日本国内の型番で認識します。`scanimage -L` は Perfection V800/V850 を
  `GT-X980`、V700/V750 を `GT-X900` と表示します。同じスキャナーです。

## 赤外線チャンネル

ここでの「IR 使用可」は、独立した赤外線画像を `irPath` として negaflow へ返せる場合を指します。
バックエンド内部だけで動くゴミ取り機能は、IR チャンネルとして扱いません。

| スキャナー・バックエンド経路 | IRの状態 | 取得方法 | 独立したIR TIFF |
|---|---|---|---|
| OpticFilm 7200、7200 v2、7300、7400、8100 | 使用不可 | IRソースを公開しない機種 | なし |
| OpticFilm 7200i、7500i、7600i、8200i `07b3:130d` | `scanimage -A`にIRソースが出る場合に使用可 | `Transparency Adapter Infrared`の別パス | あり |
| OpticFilm 8200i `07b3:1825` | 使用不可 | SANE 1.4非対応の仕様 | なし |
| `mac26`版のEpson V700/V750/V800/V850 | `scanimage -A`が赤外線モードを報告すれば使用可 | パッチ済み`epson2`の`Infrared`モードで別パス | あり |
| 標準`epson2`のEpson V700/V750/V800/V850 | 使用不可 | 標準ビルドは`SANE_FRAME_IR`が外れたままコンパイルされる | なし |
| `--infrared`を公開するNikon `coolscan3` | 標準`scanimage`経路では使用不可 | `coolscan3`は1つの`SANE_FRAME_RGBI`を返すが、`scanimage` 1.4はRGBとIRのTIFFへ分離できない | なし |
| `--clean-image`だけを公開するReflecta/PIE | IRチャンネルとしては使用不可 | ゴミ取りはバックエンド内で完結 | なし |
| その他のスキャナー | 条件付き | `scanimage -A`が有効な独立IR sourceまたはmodeを返す場合だけ | 寸法・形式確認後にあり |

IR パスには RGB と同じ要求解像度とスキャン領域を使い、両方の画像のピクセル寸法が一致しているかを
確認してから返します。negaflow はこの IR 画像を GrainMend IR で利用できます。
