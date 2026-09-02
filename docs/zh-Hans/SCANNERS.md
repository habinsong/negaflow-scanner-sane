# 扫描仪支持

[文档首页](README.md)

下表列出了已知的 SANE 1.4 目标，以及本插件对应的处理路径。它不代表所有同名设备都一定可用。请先查看
[SANE 最新设备列表](https://www.sane-project.org/sane-supported-devices.html)，再用 `scanimage -L`
和 `scanimage -A` 检查实际连接的设备。

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

## 产品名并不能说明硬件

OpticFilm 8100 和 8200i 各自在相同产品名下至少有两种 USB 版本。`07b3:130c` 和 `07b3:130d` 由
`genesys` 驱动，而 `07b3:1824` 和 `07b3:1825` 使用的是另一颗 Genesys 芯片，目前没有任何后端能驱动。
沿用旧名称销售的新版本无法从 SANE 一侧解决，因此请检查实际的 USB product ID，而不是只看外壳上的
型号。

还有两个容易混淆的识别陷阱。

- `pieusb` 同时匹配 USB ID 和**型号编号**。Reflecta 与 PIE 设备共用 `05e3:0145` 这类 ID，
  只有型号编号列在 `pieusb.conf` 中的设备才可用。
- `epson2` 按爱普生的日本型号识别设备。`scanimage -L` 会把 Perfection V800/V850 显示为
  `GT-X980`，把 V700/V750 显示为 `GT-X900`。那是同一台扫描仪。

## 红外通道

这里说的“IR 可用”，指可以把独立红外图像作为 `irPath` 返回给 negaflow。只在后端内部生效的除尘开关
不会被报告为 IR 通道。

| 扫描仪或后端路径 | IR 状态 | 获取方式 | 独立 IR TIFF |
|---|---|---|---|
| OpticFilm 7200、7200 v2、7300、7400、8100 | 不可用 | 这些型号不提供 IR 源 | 无 |
| OpticFilm 7200i、7500i、7600i、8200i `07b3:130d` | `scanimage -A` 报告 IR 源时可用 | 单独执行 `Transparency Adapter Infrared` 扫描 | 有 |
| OpticFilm 8200i `07b3:1825` | 不可用 | 该硬件版本不受 SANE 1.4 支持 | 无 |
| 使用 `mac26` 安装包的 Epson V700/V750/V800/V850 | `scanimage -A` 报告红外模式时可用 | 打过补丁的 `epson2` 以 `Infrared` 模式单独扫描一遍 | 有 |
| 使用标准 `epson2` 的 Epson V700/V750/V800/V850 | 不可用 | 标准构建把 `SANE_FRAME_IR` 编译在外 | 无 |
| 提供 `--infrared` 的 Nikon `coolscan3` | 标准 `scanimage` 路径不可用 | `coolscan3` 返回单个 `SANE_FRAME_RGBI`，但 `scanimage` 1.4 无法将其拆分为 RGB 与 IR TIFF | 无 |
| 只提供 `--clean-image` 的 Reflecta/PIE | 不作为 IR 通道使用 | 除尘在后端内部完成 | 无 |
| 其他扫描仪 | 有条件 | 仅当 `scanimage -A` 报告处于活动状态的独立 IR source 或 mode 时 | 通过尺寸和格式检查后提供 |

IR 扫描使用与 RGB 相同的请求分辨率和扫描区域，返回前还会检查两张图像的像素尺寸是否一致。negaflow
随后可将 IR 图像用于 GrainMend IR。
