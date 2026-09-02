# 故障排查

[文档首页](README.md)

## 安装失败

失败界面只显示“安装失败”。macOS 安装器仅按包脚本的退出码判定，脚本的输出留在日志里。安装器打开时按
⌘L，或事后读取日志：

```bash
sudo grep -iE "negaflow|Error:" /var/log/install.log | tail -60
```

| 日志 | 原因 |
|---|---|
| `Your Command Line Tools are too outdated` | `mac26` 版编译 SANE，而 Homebrew 拒绝比当前 macOS 更旧的 Command Line Tools |
| `Homebrew was not installed at the supported prefix` | `/opt/homebrew` 或 `/usr/local` 下没有 `brew` |
| `no supported logged-in user was found` | 没有控制台用户，例如通过 SSH 或在登录窗口执行 |
| `patched scanimage was not installed` | SANE 构建失败，Homebrew 的报错在该行上方 |

Command Line Tools 过旧时：

```bash
sudo rm -rf /Library/Developer/CommandLineTools
```

```bash
xcode-select --install
```

过旧的安装仍保留 `git`，因此只查文件会判定为已安装。安装器改为查找当前 macOS 的 SDK，若不存在则在
安装任何内容之前停止。

Homebrew 无需预先安装。安装包内含官方签名的 Homebrew 安装器，仅在没有 `brew` 时运行。已有的
Homebrew 按原样使用。

`mac26` 版从源码构建 SANE 1.4.0，需要数分钟，进度条无法显示构建进度。`mac14` 版安装预编译 bottle，
很快完成。

## 找不到扫描仪

negaflow 中的**已批准**表示允许运行插件，并不表示已经找到扫描仪。设备发现完全来自 `scanimage -L`
的返回结果，所以那里没有的扫描仪在 negaflow 中同样没有，重新安装应用或插件也不会改变。

macOS 没有需要逐个应用开启的 USB 权限。negaflow 和本插件都不使用 App Sandbox，因此“隐私与安全性”
设置也不会阻止访问扫描仪。

### 1. 判断在哪一层失败

打开扫描仪电源并连接后，按顺序执行：

```bash
system_profiler SPUSBDataType
```

```bash
scanimage -L
```

```bash
"$HOME/Library/Application Support/negaflow/Plugins/sane/negaflow-scanner-sane" detect
```

| USB 列表 | `scanimage -L` | `detect` | 问题所在 |
|---|---|---|---|
| 没有扫描仪 | 没有 | `{"devices":[]}` | SANE 之前的线缆、端口或供电 |
| 有扫描仪 | 没有 | `{"devices":[]}` | SANE 后端，或占用该设备的其他进程 |
| 有扫描仪 | 列出设备 | `{"devices":[]}` | SANE 装在插件不会查找的位置 |
| 有扫描仪 | 列出设备 | 列出设备 | negaflow 一侧：重新打开“加载扫描仪”并再次批准 |

### 2. 常见原因

| 现象 | 原因 | 处理 |
|---|---|---|
| `scanimage: command not found` | 未安装 SANE，或其 `bin` 不在当前 shell 的 `PATH` 中 | 普通扫描仪安装 `sane-backends`；修补路径使用上面的助手与 `export` |
| USB 列表中没有扫描仪 | 集线器、扩展坞、转接头、线缆或供电 | 去掉集线器直连 Mac，并换一个端口。USB 2.0 胶片扫描仪经过 USB-C 转接常常失败 |
| `sane-find-scanner` 能看到，但提示 `no SANE devices found` | 没有已启用的后端支持该型号 | 查看 [SANE 支持设备列表](https://www.sane-project.org/sane-supported-devices.html)，再阅读第 3 步的日志 |
| USB 列表中有，`scanimage -L` 为空，且 `repair-sane-config` 返回 `notNeeded` | SANE 不认识的硬件版本 | 将 USB product ID 与[扫描仪支持](SCANNERS.md)对照。沿用旧产品名销售的新版本无法从这一侧解决 |
| Coolscan LS-50 或 LS-5000 从 USB 列表中消失 | 这些机型上已知的 USB 端口故障 | 换线缆和端口确认。如果 Mac 完全无法枚举，则是硬件故障 |
| `another process has device opened for exclusive access`、`device busy`、`is not configured` | 其他程序已占用 USB 接口 | 退出 VueScan、SilverFast、图像捕捉和厂商工具，重新连接扫描仪后再试 |
| 只有 `sudo scanimage -L` 能找到 | 接口被占用或未释放 | 先解决上面的占用问题。negaflow 不会以 root 运行插件，所以 `sudo` 不是解决办法 |
| 终端能找到，negaflow 找不到 | SANE 不在支持的 Homebrew keg 路径 | 重新运行随附安装程序；不会使用 MacPorts 或其他手动编译路径 |
| `open of device ... failed: Invalid argument` | 首次打开后 USB 地址发生变化，或缺少 SANE 配置目录 | 重新执行 `detect`，并确认存在 `/opt/homebrew/etc/sane.d` 或 `/usr/local/etc/sane.d` |
| 更新前可用 | 当前选择的 SANE keg 被删除或替换 | 重新运行对应的安装程序，并检查 `brew list --versions sane-backends sane-backends-negaflow` |
| 安装旧版 negaflow 插件后列表为空 | 旧版本在 `dll.conf` 中禁用了后端 | 执行 [SANE 配置](#sane-配置)中的 `repair-sane-config` |

### 3. 阅读后端日志

```bash
SANE_DEBUG_DLL=3 scanimage -L 2>&1 | tail -40
```

它会显示加载了哪些后端以及在哪里失败。要缩小到单个后端，请使用该后端自己的变量，例如
`SANE_DEBUG_GENESYS=128` 或 `SANE_DEBUG_EPSON2=128`。

反馈问题时需要一并提供 macOS 版本、Mac 机型、`scanimage --version`、
`brew list --versions sane-backends sane-backends-negaflow`、扫描仪型号以及上述三步的输出。

## SANE 配置

修补后的 keg 使用自己的 `etc/sane.d`，不会修改普通 Homebrew 安装的 `dll.conf`。`detect` 会自动修复
旧版 negaflow 插件禁用的行，同时保留发行版和用户原有的注释。也可以手动执行相同修复：

```bash
.build/release/negaflow-scanner-sane repair-sane-config
```

如果仍有旧版 `dll.conf.negaflow-backup`，下面的命令会用该备份替换整个当前文件。备份后的更改也会被
撤销，因此仅在局部修复无效时使用：

```bash
.build/release/negaflow-scanner-sane restore-sane
```
