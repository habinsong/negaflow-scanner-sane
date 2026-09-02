# 开发

[文档首页](README.md)

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

每个 protocol v2 事件都包含 `protocolVersion`、`requestID` 和持续递增的 `sequence`。只有在检查输出
TIFF 与实际应用的扫描设置后，成功结果才会包含 `appliedOptions`。negaflow 会把 `capabilities` 返回的
不透明 `capabilityToken` 自动带入下一次扫描请求。直接使用 CLI 时也应传回同一个值；省略后会继续执行
较慢的兼容性预检。

能力信息在实际扫描所处的状态下读取，因为 SANE 选项会互相改变激活状态。`epson2` 在 Lineart 下关闭
位深，在选择线性伽马后关闭亮度，所以设备默认状态的 dump 无法描述扫描时的状态。插件会先应用透射
光源、扫描模式与中性色彩和伽马设置，在该状态下读取选项并把该状态写入令牌；请求其他模式时会在该
模式下重新读取。

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

## 请求值与失败处理

- 请求的 DPI 必须准确存在于设备列表或范围中，不会自动改为相近分辨率。
- 16-bit 请求只在 SANE depth 大于 8 且解码结果确实为 16-bit TIFF 时成功。
- 只有存在毫米单位的 `-x/-y` 范围时才报告物理扫描区域；定位扫描还需要 `-l/-t`。
- 应用 source、mode、depth、resolution、preview 和 geometry 后，会重新检查相关选项。
- 预览不会暗中加入 IR 或多重曝光。
- 不会用 brightness、contrast 或 gamma 模拟硬件多重曝光。
- 如果结果与请求不符或验证失败，插件会丢弃文件并返回错误。

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

按型号设计的虚拟扫描仪测试会运行真实子进程并验证 TIFF 协议，包括预览、完整扫描、扫描区域和 IR
路径。它们不模拟扫描仪电机、光学系统、USB 传输或最终画质，因此不算真实硬件验证。

## 发布构建

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
```

脚本会构建 `arm64` 和 `x86_64`，合并为 Universal 可执行文件，创建 dSYM，完成签名和打包，写入
SHA-256 校验值并验证归档。输出位于 `.build/release-artifacts/`。

发行签名与公证还需要 `NEGAFLOW_CODESIGN_IDENTITY`、`NEGAFLOW_NOTARY_KEYCHAIN_PROFILE` 和
`NEGAFLOW_RELEASE_MODE=distribution`。

用以下命令生成独立的一键 PKG 和 DMG：

```bash
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

该构建会先验证固定版本的官方 Homebrew 安装包，再纳入其安装组件，随后同时生成 Apple Silicon 专用版
和 Universal 版，并在不实际安装的情况下分别检查各自的 PKG 和 DMG。将
`NEGAFLOW_INSTALLER_ARCHITECTURE` 设为 `arm64` 或 `universal` 只构建其中一种；默认值 `all` 会构建
两种。设置 `NEGAFLOW_INSTALLER_VARIANT=all` 会同时构建标准版和 Coolscan 版；默认只构建标准版。用于
正式分发时，还需要 `NEGAFLOW_INSTALLER_MODE=distribution`、PKG 使用的
`NEGAFLOW_INSTALLER_IDENTITY`，以及现有的应用签名身份和公证配置。
