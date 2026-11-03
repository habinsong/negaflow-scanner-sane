# 扫描仪支持

[文档首页](README.md)

下表列出了已知的 SANE 目标，以及本插件对应的处理路径。它不代表所有同名设备都一定可用。请先查看
[SANE 最新设备列表](https://www.sane-project.org/sane-supported-devices.html)，再用 `scanimage -L`
和 `scanimage -A` 检查实际连接的设备。

“打过补丁的 SANE”指 `mac26` 安装包构建的 SANE，以及 Windows 安装程序自带的 SANE 运行时，即在
SANE 1.4.0 上加上 [`sane-runtime/SOURCES.md`](../../negaflow-mac/sane-runtime/SOURCES.md) 所列补丁。
`mac14` 安装包使用不含这些补丁的 Homebrew 标准 SANE 1.4.0。

| 扫描仪系列 | SANE 后端 | 状态 | 插件处理路径 |
|---|---|---|---|
| Plustek OpticFilm 7200、7200 v2、7200i、7300、7400 v2、7500i、7600i v2 | `genesys` | SANE 1.4 中为 Complete | 专用胶片扫描仪路径 |
| Plustek OpticFilm 7400 v1、7600i v1 | `genesys` | 1.4.0 之后上游已修正，已包含在打过补丁的 SANE 中 | 专用胶片扫描仪路径，未经实机验证 |
| Plustek OpticFilm 8100，USB `07b3:130c`（GL845） | `genesys` | SANE 1.4 中为 Complete | 专用胶片扫描仪路径，已实机验证 |
| Plustek OpticFilm 8200i，USB `07b3:130d`（GL845） | `genesys` | SANE 1.4 中为 Complete | 专用胶片扫描仪路径 |
| Plustek OpticFilm 8200i 新版，USB `07b3:1825`（GL128，SANE 中显示为“8200i SE”） | `genesys`，仅限打过补丁的 SANE | 上游为 Basic：16-bit、150–7200 dpi、无红外 | 专用胶片扫描仪路径，未经实机验证 |
| Plustek OpticFilm 8100 V2，USB `07b3:1824`（GL128） | 无 | Unsupported | 不作为可用设备处理 |
| Plustek OpticFilm 8300i，USB `07b3:181f`（GL128，在 SE 上测得） | 无 | Unsupported | 不作为可用设备处理 |
| Plustek OpticFilm 9000i Ai，USB `07b3:182f` | 无 | Unsupported | 不作为可用设备处理 |
| Plustek OpticFilm 120、120 Pro、135、135i | 无 | Unsupported | 不作为可用设备处理 |
| Epson Perfection V700/V750（GT-X900）、V800/V850（GT-X980） | `epson2` | Good | 若设备报告则使用透射源和可定位平板区域 |
| Nikon Coolscan LS-40 ED、LS-50 ED、LS-5000 ED（USB） | `coolscan3`、`coolscan2` | Complete（LS-40）、Minimal（LS-50）、Untested（LS-5000） | 带有下述限制的专用胶片扫描仪路径，未经实机验证 |
| Nikon Coolscan LS-4000 ED、LS-8000 ED（IEEE 1394 / FireWire） | 经 SBP-2 的 `coolscan3`、`coolscan2` | 在 Linux 上为 Good | macOS 26 上不可用，Windows 与 macOS 14/15 未验证（见下文） |
| Nikon Coolscan LS-30、LS-2000（SCSI） | `coolscan3` | Complete（LS-30）、Good（LS-2000） | 需要 SCSI 主机适配器 |
| Nikon Coolscan LS-20、LS-1000 | `coolscan` | 因型号而异 | 仅 SCSI |
| Nikon Coolscan LS-9000 ED | 无 | Unsupported | 不作为可用设备处理 |
| Reflecta ProScan/CrystalScan/DigitDia、PIE PowerSlide | `pieusb`，旧 SCSI 型号使用 `pie` | 因型号和型号编号而异 | 只使用设备报告的选项 |
| Pacific Image PrimeFilm XA、XAs、XA Plus | 无 | Unsupported | 不作为可用设备处理 |
| 其他支持透射稿的平板与胶片扫描仪 | 因后端而异 | 因型号而异 | 按能力报告处理，不按型号名回退 |

## 产品名并不能说明硬件

Plustek 会沿用旧产品名销售新硬件。能区分两者的是 USB product ID，而不是机身上的型号。

| 机身标注 | USB ID | 控制芯片 | SANE |
|---|---|---|---|
| OpticFilm 8100 旧版 | `07b3:130c` | GL845 | SANE 1.4.0 的 `genesys` |
| OpticFilm 8100 新版（V2） | `07b3:1824` | GL128 | 无 |
| OpticFilm 8200i 旧版 | `07b3:130d` | GL845 | SANE 1.4.0 的 `genesys` |
| OpticFilm 8200i 新版 | `07b3:1825` | GL128 | 自 2026-09 起在上游 master 的 `genesys` 中，仅限打过补丁的 SANE |
| OpticFilm 8300i SE（Ai 未确认） | `07b3:181f` | GL128 | 无 |
| OpticFilm 9000i Ai | `07b3:182f` | 未公开 | 无 |

SE 和 Ai 是随机附带的 SilverFast 版本名称，并不代表硬件。旧版 8200i SE/Ai 是 `130d`，新版是
`1825`。

这三款 GL128 机型的寄存器布局相同，但取值并不完全相同。SANE 的 GL128 代码在很大程度上基于开源驱动
[pyopticfilm](https://github.com/jboneng/pyopticfilm) 解读的 USB 抓包，该项目也记录了差异：8100 V2
启动时的 ASIC 时钟和寄存器 `0x0B` 不同，8300i SE 的曝光、传感器时序和电机表都是自己的一套。直接套用
8200i SE 的表，等于凭猜测控制电机和灯管。pyopticfilm 记录过在 8100 V2 上置位一个寄存器位后电机随即
卡住的情况。因此，在 SANE 构建能真正驱动某款 GL128 机型、并且有人用它实际扫描过之前，本插件不会启用它。

在 Mac 上可用 `system_profiler SPUSBDataType`，在 Windows 上可在设备管理器中查看 ID。

还有两个容易混淆的识别陷阱。

- `pieusb` 同时匹配 USB ID 和**型号编号**。Reflecta 与 PIE 设备共用 `05e3:0145` 这类 ID，
  只有型号编号列在 `pieusb.conf` 中的设备才可用。
- `epson2` 按爱普生的日本型号识别设备。`scanimage -L` 会把 Perfection V800/V850 显示为
  `GT-X980`，把 V700/V750 显示为 `GT-X900`。那是同一台扫描仪。

## Nikon Coolscan

目前还没有任何 Coolscan 用本插件做过实机验证。以下内容来自阅读 `coolscan3` 源码和插件代码。

### 连接方式

LS-4000 ED 和 LS-8000 ED 只有 IEEE 1394（FireWire）接口。SANE 通过 SBP-2 把它们当作 SCSI 设备处理，
所以设备名是 `coolscan3:scsi:...`，而不是 USB。

- **macOS 26 完全没有 FireWire**，用转接器也无法恢复。`mac26` 是唯一使用打过补丁的 SANE 的安装包，
  因此无法连接这两款机型。
- macOS 14 和 15 仍有 FireWire，SANE 也有 macOS 的 SCSI 接口，但从未用 `mac14` 安装包试过这条路径。
- 在 Windows 上，SANE 需要经由 SCSI pass-through 路径才能连接 SBP-2 扫描仪。这条路径也没有试过。

现实可用的 Coolscan 目标是使用 USB 的 LS-40 ED、LS-50 ED、LS-5000 ED。

### 插件路径的行为

| 项目 | 行为 | 结果 |
|---|---|---|
| 颜色模式 | `coolscan2`/`coolscan3` 没有 `--mode`，总是返回 RGB | 只报告 `color`。黑白胶片也以彩色扫描，由 negaflow 冲洗；除胶片类型外，请求与彩色负片相同 |
| 扫描区域 | 区域选项不是 mm，而是以扫描仪最高分辨率计的像素 | negaflow 无法选择区域，插件把默认的 36 x 24 mm 换算成像素。LS-8000 的中画幅画格只会留下左上角 36 x 24 mm |
| 画格 | 不发送 `--frame` | 使用片条夹时只扫描第一格 |
| 对焦 | `coolscan3` 只在被要求时才自动对焦，而 negaflow 没有要求 | 以扫描仪当前的对焦位置扫描 |
| 红外 | `--infrared` 返回单个 RGBI 帧 | 不作为 IR 通道提供 |
| 胶片类型 | `--negative` 会让扫描仪反转颜色 | 始终发送 `--negative=no`，negaflow 拿到的是原始负片 |

表中最后两行是有意为之。前四行是尚未完成的工作，每一项都需要用实机确认。

## 红外通道

这里说的“IR 可用”，指可以把独立红外图像作为 `irPath` 返回给 negaflow。只在后端内部生效的除尘开关
不会被报告为 IR 通道。

| 扫描仪或后端路径 | IR 状态 | 获取方式 | 独立 IR TIFF |
|---|---|---|---|
| OpticFilm 7200、7200 v2、7300、7400、8100 | 不可用 | 这些型号不提供 IR 源 | 无 |
| OpticFilm 7200i、7500i、7600i、8200i `07b3:130d` | `scanimage -A` 报告 IR 源时可用 | 单独执行 `Transparency Adapter Infrared` 扫描 | 有 |
| OpticFilm 8200i 新版 `07b3:1825` | 不可用 | SANE 的 GL128 代码尚无红外扫描 | 无 |
| OpticFilm 8100 V2、8300i、9000i | 不可用 | 没有 SANE 后端 | 无 |
| 使用 `mac26` 安装包的 Epson V700/V750/V800/V850 | `scanimage -A` 报告红外模式时可用 | 打过补丁的 `epson2` 以 `Infrared` 模式单独扫描一遍 | 有 |
| 使用标准 `epson2` 的 Epson V700/V750/V800/V850 | 不可用 | 标准构建把 `SANE_FRAME_IR` 编译在外 | 无 |
| 提供 `--infrared` 的 Nikon `coolscan3` | `scanimage` 路径不可用 | `coolscan3` 返回单个 `SANE_FRAME_RGBI`，但 `scanimage` 1.4 无法将其拆分为 RGB 与 IR TIFF | 无 |
| 只提供 `--clean-image` 的 Reflecta/PIE | 不作为 IR 通道使用 | 除尘在后端内部完成 | 无 |
| 其他扫描仪 | 有条件 | 仅当 `scanimage -A` 报告处于活动状态的独立 IR source 或 mode 时 | 通过尺寸和格式检查后提供 |

IR 扫描使用与 RGB 相同的请求分辨率和扫描区域，返回前还会检查两张图像的像素尺寸是否一致。negaflow
随后可将 IR 图像用于 GrainMend IR。
