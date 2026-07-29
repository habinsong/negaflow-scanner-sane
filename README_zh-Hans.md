<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">适用于 macOS 版 negaflow 的 SANE 胶片扫描仪插件</p>

<p align="center">
  <a href="#系统要求"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 或更高版本"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift 5.9 或更高版本"></a>
  <a href="manifest.json"><img src="https://img.shields.io/badge/protocol-v2-4B5563" alt="negaflow 扫描仪协议 v2"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0--or--later-6E7781" alt="GPL 2.0 或更高版本"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_ko.md">한국어</a> ·
  <a href="README_ja.md">日本語</a> ·
  <strong>简体中文</strong> ·
  <a href="README_fr.md">Français</a> ·
  <a href="README_de.md">Deutsch</a>
</p>

---

**negaflow-scanner-sane** 将 SANE 可用的胶片扫描仪连接到 [negaflow](https://github.com/habinsong/negaflow)。<br>
它运行 `scanimage`，读取扫描仪实际提供的选项，并通过 negaflow 扫描仪协议 v2 返回设备信息、功能、进度和 TIFF 路径。

它不是另一套扫描界面，而是可安装的命令行插件。<br>
安装并批准插件后，扫描操作仍在 negaflow 中完成。

插件与主程序是两个独立程序。<br>
所有 SANE 专用代码都保留在这个采用 GPL-2.0-or-later 的仓库中；采用 Apache-2.0 的 negaflow 主程序只通过独立进程、命令行参数、管道和 JSON 与插件通信。

## 功能

- 通过 `scanimage -L` 查找扫描仪
- 根据设备当前返回的 `scanimage -A` 内容生成扫描控件
- 支持预览和完整扫描，不把请求值替换为相近的默认值
- 返回结果前检查分辨率、色彩模式、位深、尺寸和 TIFF 格式
- 仅在后端报告所需范围时使用毫米扫描区域
- 仅在后端确实能提供时获取独立红外通道
- 仅在 `--scan-exposure-time` 覆盖所需曝光计划时启用硬件多重曝光
- 只停止当前插件实例启动的 `scanimage` 进程

插件不会只凭扫描仪型号判断功能。<br>
negaflow 只显示当前设备及其 SANE 后端实际报告的选项。

## 系统要求

- 按当前 negaflow 与 Homebrew 安装方式，需要 macOS 14.0 或更高版本
- negaflow
- 普通扫描仪使用 Homebrew 标准 `sane-backends`
- Nikon Coolscan 专用修补路径仅支持 macOS 26 或更高版本
- 仅从源码构建时需要 Swift 5.9 或更高版本

独立可执行文件在 `Package.swift` 中仍以 macOS 13 为 deployment target。<br>
但本指南所述的 negaflow 与 Homebrew 完整安装方式，按当前支持范围从 macOS 14 开始。

## 安装

### 1. 一键安装程序

如果尚未安装 Xcode Command Line Tools，请先安装：

```bash
xcode-select --install
```

安装包有四种。普通 SANE 扫描仪使用标准版；macOS 26 或更高版本上的 Nikon Coolscan
使用单独的 Coolscan 版。

| 安装包 | SANE 路径 | 插件二进制 |
|---|---|---|
| `negaflow-scanner-sane-1.0.3-macos-arm64-installer.dmg` | 标准版，macOS 14+ | 仅 `arm64` |
| `negaflow-scanner-sane-1.0.3-macos-universal-installer.dmg` | 标准版，macOS 14+ | `arm64` + `x86_64` |
| `negaflow-scanner-sane-1.0.3-coolscan-macos26-arm64-installer.dmg` | Coolscan 修补版，macOS 26+ | 仅 `arm64` |
| `negaflow-scanner-sane-1.0.3-coolscan-macos26-universal-installer.dmg` | Coolscan 修补版，macOS 26+ | `arm64` + `x86_64` |

标准 DMG 内运行 `Install negaflow Scanner.pkg`；Coolscan DMG 内运行
`Install negaflow Scanner for Coolscan.pkg`。

标准版安装 Homebrew 的 `sane-backends`。Coolscan 版从官方 SANE 1.4.0 源码构建
`sane-backends-negaflow`，应用 upstream 的 `coolscan2`/`coolscan3` 分配修复与 `epson2` 扫描高度修复。<br>
安装需要互联网连接和管理员密码；若已安装 Homebrew，则直接复用现有安装。

标准版和 macOS 26 以下系统不会主动阻止 Coolscan。stock SANE 可能适用于某些设备，
但不含该分配修复；受支持的修补路径是 macOS 26 以上 Coolscan 版。

后续 upstream 还加入了至少 LS-5000 firmware 1.03 所需的 Coolscan3
load/eject/reset 参数块初始化。该修改有意不包含在这组最小补丁中，因此即使使用 Coolscan
版，LS-5000 的装片、退片和复位仍未经过验证，并可能失败。

完成后重新启动 negaflow，在“加载扫描仪”中检查插件信息并批准它。

### 2. 手动安装 Homebrew 和 SANE

如果尚未安装 Homebrew，请运行当前官方安装命令：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

该命令会下载并运行 Homebrew 安装程序。<br>
执行前请确认地址正是 `raw.githubusercontent.com/Homebrew/install/HEAD/install.sh`。<br>
也可以使用 [Homebrew 官方网站](https://brew.sh/)提供的已签名 `.pkg` 安装程序。

安装完成后，按屏幕显示的 **Next steps** 将 `brew` 加入 shell 环境，再重新打开终端并检查命令是否可用：

```bash
brew --version
```

macOS 14 以上标准路径：

```bash
brew install sane-backends
```

macOS 26 以上 Coolscan 修补路径：

```bash
bash scripts/install-patched-sane.sh
export PATH="$(brew --prefix sane-backends-negaflow)/bin:$PATH"
```

检查已安装的命令和版本：

```bash
command -v scanimage
scanimage --version
brew list --versions sane-backends sane-backends-negaflow
```

若修补后的 keg 存在，插件会使用其绝对路径以及同一 keg 的 `etc/sane.d` 和 `lib/sane`。

### 3. 连接并检查扫描仪

打开扫描仪电源，尽量直接连接 USB 而不经过集线器，然后运行：

```bash
scanimage -L
```

复制输出中包含后端名和 USB 地址的完整 device ID，再查看该设备实际提供的选项：

```bash
scanimage -d '<device-id>' -A
```

device ID 可能类似 `genesys:libusb:001:002`。<br>
不要照抄这个示例，请使用当前 Mac 上 `scanimage -L` 返回的值。

`sane-find-scanner` 只能证明发现了 USB 或 SCSI 设备，也可能列出没有可用 SANE 后端的扫描仪。<br>
如果设备没有出现在 `scanimage -L` 中，本插件就无法使用它。<br>
请先检查 USB 连接、 [SANE 支持列表](https://www.sane-project.org/sane-supported-devices.html)以及相应后端的说明。

### 4A. 从源码构建并安装插件

```bash
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
./install.sh
```

脚本会创建 Release 构建，并安装以下两个文件：

```text
~/Library/Application Support/negaflow/Plugins/sane/
  ├── negaflow-scanner-sane
  └── manifest.json
```

### 4B. 从发布 ZIP 安装

解压发布 ZIP，并运行其中的安装程序：

```bash
./install.sh
```

安装已打包版本不需要 Swift 工具链。`install.sh` 只安装插件，因此请先安装标准 SANE
或 macOS 26 Coolscan 修补版。

### 5. 在 negaflow 中批准并验证

重新启动 negaflow 并打开“加载扫描仪”。<br>
检查插件路径、版本、许可证和 hash 后批准它。<br>
如果更新后可执行文件或 manifest 发生变化，negaflow 会要求重新批准。

也可以直接检查已安装的可执行文件：

```bash
"$HOME/Library/Application Support/negaflow/Plugins/sane/negaflow-scanner-sane" detect
```

返回 `{"devices":[...]}` 表示插件已经运行。<br>
若 `devices` 为空数组，则插件已启动，但 SANE 没有返回可用扫描仪。<br>
此时重新安装插件不会补上缺失的 SANE 后端支持，应从 `scanimage -L` 这一步开始检查。

## 扫描仪支持

下表列出了已知的 SANE 1.4 目标，以及本插件对应的处理路径。<br>
它不代表所有同名设备都一定可用。<br>
请先查看 [SANE 最新设备列表](https://www.sane-project.org/sane-supported-devices.html)，再用 `scanimage -L` 和 `scanimage -A` 检查实际连接的设备。

| 扫描仪系列 | SANE 后端 | SANE 1.4 状态 | 插件处理路径 |
|---|---|---|---|
| Plustek OpticFilm 7200、7200 v2、7200i、7300、7400 v2、7500i、7600i | `genesys` | Complete | 专用胶片扫描仪路径 |
| Plustek OpticFilm 7400 v1 | `genesys` | 支持表标为 Complete，但机型专用修正在 SANE 1.4.0 之后才合入 | capability 驱动路径；stock 1.4.0 实机结果未验证 |
| Plustek OpticFilm 8100，USB `07b3:130c` | `genesys` | Complete | 专用胶片扫描仪路径 |
| Plustek OpticFilm 8100，USB `07b3:1824` | 无 | Unsupported | 不作为可用设备处理 |
| Plustek OpticFilm 8200i，USB `07b3:130d` | `genesys` | Complete | 专用胶片扫描仪路径 |
| Plustek OpticFilm 8200i，USB `07b3:1825`（GL128） | 无 | Unsupported | 不作为可用设备处理 |
| Plustek OpticFilm 120、120 Pro、135、135i、9000i Ai | 无 | Unsupported | 不作为可用设备处理 |
| Epson Perfection V700/V750（GT-X900）、V800/V850（GT-X980） | `epson2` | Good | 在设备报告时使用透射源和定位式平板区域 |
| Nikon Coolscan LS-2000、LS-40 ED、LS-50 ED、LS-4000 ED、LS-8000 ED | `coolscan3` | 视型号为 Complete 至 Minimal | 专用胶片扫描仪路径 |
| Nikon Coolscan LS-5000 ED | `coolscan3` | SANE 1.4 中未经测试，可能与 LS-50 类似 | 专用胶片扫描仪路径 |
| Nikon Coolscan LS-20、LS-30、LS-1000 | `coolscan` | 视型号而定 | 仅 SCSI |
| Nikon Coolscan LS-9000 ED | 无 | Unsupported | 不作为可用设备处理 |
| Reflecta ProScan/CrystalScan/DigitDia、PIE PowerSlide | `pieusb`，旧 SCSI 型号使用 `pie` | 视型号与型号编号而定 | 仅使用设备报告的选项 |
| Pacific Image PrimeFilm XA、XAs、XA Plus | 无 | Unsupported | 不作为可用设备处理 |
| 其他支持透射稿的平板或胶片扫描仪 | 视后端而定 | 视型号而定 | 按功能报告处理，不按型号名回退 |

### 产品名并不能说明硬件

OpticFilm 8100 和 8200i 各自在相同产品名下至少有两种 USB 版本。<br>
`07b3:130c` 和 `07b3:130d` 由 `genesys` 驱动，而 `07b3:1824` 和 `07b3:1825` 使用的是另一颗
Genesys 芯片，目前没有任何后端能驱动。<br>
沿用旧名称销售的新版本无法从 SANE 一侧解决，因此请检查实际 USB product ID，而不是只看外壳上的型号。

还有两个容易混淆的识别陷阱。

- `pieusb` 同时匹配 USB ID 和**型号编号**。Reflecta 与 PIE 设备共用 `05e3:0145` 这类 ID，
  只有型号编号列在 `pieusb.conf` 中的设备才可用。
- `epson2` 按爱普生的日本型号识别设备。`scanimage -L` 会把 Perfection V800/V850 显示为
  `GT-X980`，把 V700/V750 显示为 `GT-X900`。那是同一台扫描仪，并非识别错误。

## 红外通道

在本插件中，“IR 可用”表示可以把独立红外图像作为 `irPath` 返回给 negaflow。<br>
只在后端内部生效的除尘开关不会被报告为 IR 通道。

| 扫描仪或后端路径 | IR 状态 | 获取方式 | 独立 IR TIFF |
|---|---|---|---|
| OpticFilm 7200、7200 v2、7300、7400、8100 | 不可用 | 这些型号不提供 IR 源 | 无 |
| OpticFilm 7200i、7500i、7600i、8200i `07b3:130d` | `scanimage -A` 报告 IR 源时可用 | 单独执行 `Transparency Adapter Infrared` 扫描 | 有 |
| OpticFilm 8200i `07b3:1825` | 不可用 | 该硬件版本不受 SANE 1.4 支持 | 无 |
| 使用标准 `epson2` 的 Epson V700/V750/V800/V850 | 不可用 | 标准构建不提供独立 IR 模式 | 无 |
| 启用 `SANE_FRAME_IR` 的自定义 Epson 路径 | 有条件 | 仅在实际报告时单独执行 `Infrared` 模式 | 有 |
| 提供 `--infrared` 的 Nikon `coolscan3` | 标准 `scanimage` 路径不可用 | `coolscan3` 返回单个 `SANE_FRAME_RGBI`，但 `scanimage` 1.4 无法将其拆分为 RGB 与 IR TIFF | 无 |
| 只提供 `--clean-image` 的 Reflecta/PIE | 不作为 IR 通道使用 | 除尘在后端内部完成 | 无 |
| 其他扫描仪 | 有条件 | 仅当 `scanimage -A` 报告处于活动状态的独立 IR source 或 mode 时 | 通过尺寸和格式检查后提供 |

IR 扫描使用与 RGB 相同的请求分辨率和扫描区域。<br>
返回前还会检查两张图像的像素尺寸是否一致。<br>
negaflow 随后可将 IR 图像用于 GrainMend IR。

## 故障排查：找不到扫描仪

negaflow 中的**已批准**表示允许运行插件可执行文件。<br>
它不表示已经找到扫描仪。设备发现完全来自 `scanimage -L` 的返回结果，所以那里没有的扫描仪在
negaflow 中同样没有，重新安装应用或插件也不会改变。

macOS 没有需要逐个应用开启的 USB 权限。negaflow 和本插件都不使用 App Sandbox，因此
“隐私与安全性”设置也不会阻止访问扫描仪。

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
| `scanimage: command not found` | 未安装 SANE，或其 `bin` 不在当前 shell 的 `PATH` 中 | 普通扫描仪安装 `sane-backends`；Coolscan 使用上面的修补助手与 `export` |
| USB 列表中没有扫描仪 | 集线器、扩展坞、转接头、线缆或供电 | 去掉集线器直连 Mac，并换一个端口。USB 2.0 胶片扫描仪经过 USB-C 转接常常失败 |
| `sane-find-scanner` 能看到，但提示 `no SANE devices found` | 没有已启用的后端支持该型号 | 查看 [SANE 支持设备列表](https://www.sane-project.org/sane-supported-devices.html)，再阅读第 3 步的日志 |
| USB 列表中有，`scanimage -L` 为空，且 `repair-sane-config` 返回 `notNeeded` | SANE 不认识的硬件版本 | 将 USB product ID 与[扫描仪支持](#扫描仪支持)表对照。沿用旧产品名销售的新版本无法从这一侧解决 |
| Coolscan LS-50 或 LS-5000 从 USB 列表中消失 | 这些机型上已知的 USB 端口故障 | 换线缆和端口确认。如果 Mac 完全无法枚举，则是硬件故障而非驱动问题 |
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

它会显示加载了哪些后端以及在哪里失败。<br>
要缩小到单个后端，请使用该后端自己的变量，例如 `SANE_DEBUG_GENESYS=128` 或
`SANE_DEBUG_EPSON2=128`。

反馈问题时需要一并提供 macOS 版本、Mac 机型、`scanimage --version`、
`brew list --versions sane-backends sane-backends-negaflow`、扫描仪型号以及上述三步的输出。

## 请求值与失败处理

- 请求的 DPI 必须准确存在于设备列表或范围中，不会自动改为相近分辨率。
- 16-bit 请求只在 SANE depth 大于 8 且解码结果确实为 16-bit TIFF 时成功。
- 只有存在毫米单位的 `-x/-y` 范围时才报告物理扫描区域；定位扫描还需要 `-l/-t`。
- 应用 source、mode、depth、resolution、preview 和 geometry 后，会重新检查相关选项。
- 预览不会暗中加入 IR 或多重曝光。
- 不会用 brightness、contrast 或 gamma 模拟硬件多重曝光。
- 如果结果与请求不符或验证失败，插件会丢弃文件并返回错误，而不是使用未经检查的结果。

## negaflow 扫描仪协议

可执行文件通过子命令调用，并向标准输出写入 JSON。

| 命令 | 输入 | 输出 |
|---|---|---|
| `detect` | 无 | JSON 设备列表 |
| `capabilities <deviceId>` | 可选的探测设备身份 JSON | JSON 格式的分辨率、模式、位深、区域、曝光和 IR 功能 |
| `scan` | stdin 中的 protocol v2 请求 JSON | NDJSON 进度，以及最终结果或错误事件 |
| `repair-sane-config` | 无 | 只重新启用旧版 negaflow 插件禁用的后端 |
| `tune-sane` | 无 | `repair-sane-config` 的兼容别名 |
| `restore-sane` | 无 | 仅在最后手段下恢复旧版完整备份 |

每个 protocol v2 事件都包含 `protocolVersion`、`requestID` 和持续递增的 `sequence`。<br>
只有在检查输出 TIFF 与实际应用的扫描设置后，成功结果才会包含 `appliedOptions`。
negaflow 会把 `capabilities` 返回的不透明 `capabilityToken` 自动带入下一次扫描请求。
直接使用 CLI 时也应传回同一个值；省略后会继续执行较慢的兼容性预检。

能力信息在实际扫描所处的状态下读取。SANE 选项会互相改变激活状态：`epson2` 在 Lineart 下关闭位深，在选择线性伽马后关闭亮度。因此设备默认状态的 dump 无法描述扫描时的状态。插件会先应用透射光源、扫描模式与中性色彩和伽马设置，在该状态下读取选项并把该状态写入令牌；请求其他模式时会在该模式下重新读取。

完整扫描请求示例：

```json
{
  "protocolVersion": 2,
  "requestID": "7A91B43D-90F8-41E2-B71D-04D17CD9E03B",
  "deviceID": "sane-genesys:libusb:001:002",
  "capabilityToken": "<capabilities 返回的不透明令牌>",
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

## SANE 配置

修补后的 keg 使用自己的 `etc/sane.d`，不会修改普通 Homebrew 安装的 `dll.conf`。<br>
`detect` 会自动修复旧版 negaflow 插件禁用的行，同时保留发行版和用户原有的注释。也可以手动执行相同修复：

```bash
.build/release/negaflow-scanner-sane repair-sane-config
```

如果仍有旧版 `dll.conf.negaflow-backup`，下面的命令会用该备份替换整个当前文件。备份后的更改也会被撤销，因此仅在局部修复无效时使用：

```bash
.build/release/negaflow-scanner-sane restore-sane
```

## 仓库结构

| 路径 | 作用 |
|---|---|
| `Sources/SANEPluginCore` | SANE 发现、功能解析、采集、TIFF 验证、IR 与曝光合并 |
| `Sources/negaflow-scanner-sane` | negaflow 扫描仪协议 v2 的轻量 JSON/CLI 适配层 |
| `Tests/SANEPluginCoreTests` | 协议、进程、选项解析、TIFF 和虚拟扫描仪回归测试 |
| `Installer` | 一键 PKG 分发配置、安装脚本和 Installer.app 界面资源 |
| `scripts` | Universal 构建、签名、打包、安装、公证和发布检查 |

## 开发检查

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

按型号设计的虚拟扫描仪测试会运行真实子进程并验证 TIFF 协议，包括预览、完整扫描、扫描区域和 IR 路径。<br>
它们不模拟扫描仪电机、光学系统、USB 传输或最终画质，也不会被当作真实硬件验证。

## 发布构建

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
```

脚本会构建 `arm64` 和 `x86_64`，合并为 Universal 可执行文件，创建 dSYM，完成签名和打包，写入 SHA-256 校验值并验证归档。<br>
输出位于 `.build/release-artifacts/`。

发行签名与公证还需要 `NEGAFLOW_CODESIGN_IDENTITY`、`NEGAFLOW_NOTARY_KEYCHAIN_PROFILE` 和 `NEGAFLOW_RELEASE_MODE=distribution`。

用以下命令生成独立的一键 PKG 和 DMG：

```bash
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

该构建会先验证固定版本的官方 Homebrew 安装包，再纳入其安装组件，随后同时生成 Apple Silicon 专用版和 Universal 版，并在不实际安装的情况下分别检查各自的 PKG 和 DMG。<br>
将 `NEGAFLOW_INSTALLER_ARCHITECTURE` 设为 `arm64` 或 `universal` 只构建其中一种；默认值 `all` 会构建两种。<br>
设置 `NEGAFLOW_INSTALLER_VARIANT=all` 会同时构建标准版和 Coolscan 版；默认只构建标准版。<br>
用于正式分发时，还需要 `NEGAFLOW_INSTALLER_MODE=distribution`、PKG 使用的 `NEGAFLOW_INSTALLER_IDENTITY`，以及现有的应用签名身份和公证配置。

## 许可证

本项目采用 [GPL-2.0-or-later](LICENSE) 发布。<br>
发布归档同时包含许可证说明和 GNU GPL v2 全文 [COPYING](COPYING)。

安装程序还包含所附 Homebrew 组件，以及 Coolscan 版在用户 Mac 上构建的修补版 SANE
源码的[第三方声明](THIRD_PARTY_NOTICES.md)。<br>
同版本插件的完整源代码归档会在发布 ZIP 内及同一发布位置提供，<br>
同时也包含在 PKG 安装内容和 DMG 中。

negaflow 主程序是独立的 Apache-2.0 项目。<br>
产品名和扫描仪名称仅用于标识兼容或测量目标，相关权利归各自所有者。
