# トラブルシューティング

[ドキュメントホーム](README.md)

## インストールに失敗する

失敗画面には「インストールに失敗しました」としか出ません。macOS インストーラーはパッケージ
スクリプトを終了コードだけで判定するため、スクリプトの出力はログに残ります。インストーラーが
開いている間に ⌘L を押すか、後からログを読みます。

```bash
sudo grep -iE "negaflow|Error:" /var/log/install.log | tail -60
```

| ログ | 原因 |
|---|---|
| `Your Command Line Tools are too outdated` | `mac26`版はSANEをコンパイルするが、実行中のmacOSより古いCommand Line ToolsはHomebrewが拒否する |
| `Homebrew was not installed at the supported prefix` | `/opt/homebrew`または`/usr/local`に`brew`がない |
| `no supported logged-in user was found` | コンソールユーザーがいない。SSHやログインウインドウから実行した場合 |
| `patched scanimage was not installed` | SANEのビルド失敗。Homebrewのエラーがこの行の上にある |

Command Line Tools が古い場合:

```bash
sudo rm -rf /Library/Developer/CommandLineTools
```

```bash
xcode-select --install
```

古い環境にも `git` は残るため、ファイルの有無だけでは導入済みと判定されます。インストーラーは
代わりに実行中の macOS の SDK を探し、無ければ何も入れる前に停止します。

Homebrew は事前に入れておく必要はありません。パッケージに公式署名済みの Homebrew インストーラーが
含まれ、`brew` が無いときだけ実行します。既存の Homebrew はそのまま使います。

`mac26` 版は SANE 1.4.0 をソースからビルドするため数分かかり、進行バーはビルドの進行を表示
できません。`mac14` 版はビルド済み bottle を入れるのですぐ終わります。

## スキャナーが見つからない

negaflow の**承認済み**は、プラグインを実行してよいという意味で、スキャナーが見つかったという意味
ではありません。デバイスの検出は `scanimage -L` が返した結果そのものなので、そこに出ないスキャナーは
negaflow にも出ず、アプリやプラグインを再インストールしても変わりません。

macOS にはアプリごとに有効化する USB 権限はありません。negaflow とこのプラグインは App Sandbox を
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
| USB一覧にはあり、`scanimage -L`が空で、`repair-sane-config`が`notNeeded` | SANEが知らないハードウェアリビジョン | USB product IDを[対応スキャナー](SCANNERS.md)と照合します。旧来の製品名で売られる新しいリビジョンはこちらでは解決できません |
| Coolscan LS-50やLS-5000がUSB一覧から消える | この機種で知られているUSBポートの故障 | 別のケーブルとポートで確認します。Macが列挙すらしない場合はハードウェアの故障です |
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

どのバックエンドが読み込まれ、どこで失敗したかがわかります。バックエンドを 1 つに絞るときは
`SANE_DEBUG_GENESYS=128` や `SANE_DEBUG_EPSON2=128` のように、そのバックエンドの変数を使います。

報告には macOS のバージョン、Mac の機種、`scanimage --version`、
`brew list --versions sane-backends sane-backends-negaflow`、スキャナーの機種名と、上の 3 段階の
出力が必要です。

## SANE設定

修正済み keg は独自の `etc/sane.d` を使い、通常の Homebrew 版 `dll.conf` を変更しません。`detect` は
旧版 negaflow プラグインが無効化した行だけを自動修復し、ディストリビューションとユーザーの
コメントはそのまま残します。同じ修復を手動で実行できます。

```bash
.build/release/negaflow-scanner-sane repair-sane-config
```

旧版の `dll.conf.negaflow-backup` が残っている場合、次のコマンドは現在のファイル全体をその
バックアップで置き換えます。バックアップ後の変更も戻るため、部分修復で解決しない場合にだけ
使用してください。

```bash
.build/release/negaflow-scanner-sane restore-sane
```
