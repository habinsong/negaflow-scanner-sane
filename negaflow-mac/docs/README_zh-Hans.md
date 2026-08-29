<h1 align="center">negaflow-scanner-sane for macOS</h1>

<p align="center">把 SANE 胶片扫描仪接到 macOS 上 negaflow 的插件</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="1.1.0"></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 及以上"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0--or--later-6E7781" alt="GPL 2.0+"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_ko.md">한국어</a> ·
  <a href="README_ja.md">日本語</a> ·
  <strong>简体中文</strong> ·
  <a href="README_fr.md">Français</a> ·
  <a href="README_de.md">Deutsch</a>
</p>

<p align="center">
  <a href="../../README_zh-Hans.md">共用文档</a> ·
  <a href="../../negaflow-windows/docs/README_zh-Hans.md">Windows</a>
</p>

---

## 需要什么

- macOS 14.0 或更高
- 先装好 negaflow 1.1.0 或更高
- SANE 支持的胶片扫描仪
- 安装时需要联网和管理员密码

没有 Xcode Command Line Tools 的话先装。

```bash
xcode-select --install
```

## 安装

在 [Releases](https://github.com/habinsong/negaflow-scanner-sane/releases) 下载 DMG。
一共四个，除非用不了 macOS 26，都选 `macos26` 那两个。

| DMG | SANE | 插件 |
|---|---|---|
| `negaflow-scanner-sane-1.1.0-macos26-arm64-installer.dmg` | 打过补丁，macOS 26 及以上 | `arm64` |
| `negaflow-scanner-sane-1.1.0-macos26-universal-installer.dmg` | 打过补丁，macOS 26 及以上 | `arm64` + `x86_64` |
| `negaflow-scanner-sane-1.1.0-opticfilm-macos14-arm64-installer.dmg` | 给 OpticFilm 用，macOS 14 及以上 | `arm64` |
| `negaflow-scanner-sane-1.1.0-opticfilm-macos14-universal-installer.dmg` | 给 OpticFilm 用，macOS 14 及以上 | `arm64` + `x86_64` |

`macos26` 的 DMG 里运行 `Install negaflow Scanner.pkg`，`opticfilm-macos14` 的运行
`Install negaflow Scanner for OpticFilm.pkg`。

装完重开 negaflow，在**加载扫描仪**里看一下插件信息，点批准。

### 两个版本的区别

`macos26` 版把官方 SANE 1.4.0 源码编成 `sane-backends-negaflow`。让 Nikon Coolscan 和
Epson 红外通道能用的就是这个版本。一共打三个补丁。

| 补丁 | 改了什么 |
|---|---|
| Coolscan 深度列表 | 修正上游 `coolscan2`/`coolscan3` 的分配 |
| `epson2` 扫描高度 | 修正 Epson 平板报告的扫描高度 |
| `epson2` 红外 | 解除 `SANE_FRAME_IR` 限制，让 Epson 胶片平板能出红外通道 |

`opticfilm-macos14` 版装的是 Homebrew 自带的 `sane-backends`，不含上面的补丁。给
macOS 14 和 15 上装不了补丁版的情况用。

LS-5000 固件 1.03 需要的 Coolscan3 load/eject/reset 初始化没有放进补丁范围。补丁版上
LS-5000 的进片、退片和复位也未经验证，可能失败。

## 手动安装

```bash
# 没有 Homebrew 的话
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install sane-backends
scanimage -L
```

然后从源码构建插件，或者用发布 ZIP 安装。

```bash
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
swift build -c release
```

## 找不到扫描仪时

1. **重开过 negaflow 吗。** 应用在启动时读插件。
2. **点了批准吗。** 要在加载扫描仪的界面批准插件才会工作。
3. **SANE 看得到设备吗。** 终端里跑 `scanimage -L`。这里就没有的话，问题在 SANE 那一层。
4. **有没有别的程序占着。** 关掉 VueScan 或厂商的工具。

```bash
/usr/local/bin/negaflow-scanner-sane detect
```

## 验证过的设备

| 扫描仪 | 验证内容 |
|---|---|
| Plustek OpticFilm 8100 | 预览与正式扫描、多档分辨率、彩色与灰度 |
| Epson Perfection V700 | 预览与正式扫描、多档分辨率、红外通道 |

不在表里的扫描仪也可能能用，只是没验证过。

## 构建与检查

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

虚拟扫描仪测试用真实的进程调用和 TIFF 约定，检查预览、正式扫描、扫描区域和红外通路。
不复现扫描仪马达、光学系统、USB 传输和最终画质。

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

## 相关文档

- [共用文档](../../README_zh-Hans.md)
- [Windows 文档](../../negaflow-windows/docs/README_zh-Hans.md)
- [来源说明](../../PROVENANCE.md)
- [第三方声明](../../THIRD_PARTY_NOTICES.md)
