<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">把胶片扫描仪接入 negaflow 的插件</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/zh/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="网站"></a>
  <a href="negaflow-mac/docs/README_zh-Hans.md"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 或更高版本"></a>
  <a href="negaflow-windows/docs/README_zh-Hans.md"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
  <a href="negaflow-mac/manifest.json"><img src="https://img.shields.io/badge/protocol-v2-4B5563" alt="negaflow 扫描仪协议 v2"></a>
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

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/zh/">网站</a> ·
  <a href="https://habinsong.github.io/negaflow-site/zh/supported-scanners/">扫描仪支持</a> ·
  <a href="https://habinsong.github.io/negaflow-site/zh/faq/">常见问题</a>
</p>

---

**negaflow-scanner-sane** 把 SANE 能驱动的胶片扫描仪接入
[negaflow](https://github.com/habinsong/negaflow)。

扫描仍然在 negaflow 里完成。插件负责控制扫描仪，不单独运行也能工作。装好后在 negaflow 里批准
一次，扫描仪就会出现在“加载扫描仪”中。

插件和主程序是两个独立程序。SANE 代码只在这个采用 GPL-2.0-or-later 的仓库里，采用 Apache-2.0 的
negaflow 只是跨进程和它交换 JSON。

## 运行环境

- 先装好 negaflow
- SANE 支持的胶片扫描仪
- macOS 14.0 或更高，或者 Windows 11

## 安装

在 [Releases](https://github.com/habinsong/negaflow-scanner-sane/releases) 下载对应系统的安装程序并
运行，重开 negaflow，批准插件即可。macOS 上安装程序会通过 Homebrew 一并准备好 SANE。Windows 上
SANE 的可执行文件已经在安装包里。

| 平台 | 页面 |
|---|---|
| macOS | [在 macOS 上安装](negaflow-mac/docs/README_zh-Hans.md) |
| Windows | [在 Windows 上安装](negaflow-windows/docs/README_zh-Hans.md) |

## 扫描仪

SANE 支持的胶片扫描仪基本都能用。麻烦的是同一个产品名下的机器芯片可能不同，只有其中一种有后端。
红外通道也只在设备确实能提供时才使用。哪台机器做到什么程度，写在
[扫描仪支持](docs/zh-Hans/SCANNERS.md)里。

插件不会凭型号名开启功能，只把设备和后端报告的选项交给 negaflow。

## 文档

- [扫描仪支持](docs/zh-Hans/SCANNERS.md) | 逐个机型的状态、产品名陷阱、红外通道
- [故障排查](docs/zh-Hans/TROUBLESHOOTING.md) | 安装失败、找不到扫描仪、SANE 配置
- [开发](docs/zh-Hans/DEVELOPMENT.md) | 扫描仪协议、仓库结构、构建
- 安装页面 | [macOS](negaflow-mac/docs/README_zh-Hans.md) · [Windows](negaflow-windows/docs/README_zh-Hans.md)

## 许可证

本项目采用 [GPL-2.0-or-later](LICENSE) 发布。发布归档同时包含许可证说明和 GNU GPL v2 全文
[COPYING](COPYING)。

安装程序还包含所附 Homebrew 组件，以及 Coolscan 版在用户 Mac 上构建的修补版 SANE 源码的
[第三方声明](THIRD_PARTY_NOTICES.md)。同版本插件的完整源代码归档会在发布 ZIP 内及同一发布位置
提供，同时也包含在 PKG 安装内容和 DMG 中。

negaflow 主程序是独立的 Apache-2.0 项目。产品名和扫描仪名称仅用于标识兼容或测量目标，相关权利归
各自所有者。
