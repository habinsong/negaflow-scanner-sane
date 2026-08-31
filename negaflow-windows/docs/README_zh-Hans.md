<h1 align="center">negaflow-scanner-sane for Windows</h1>

<p align="center">把 SANE 胶片扫描仪接到 Windows 上 negaflow 的插件</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.1-EF8B26" alt="1.1.1"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
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
  <a href="../../negaflow-mac/docs/README_zh-Hans.md">macOS</a>
</p>

---

## 需要什么

- Windows 11，64 位
- 先装好 negaflow 1.1.1 或更高
- SANE 支持的胶片扫描仪

SANE 的可执行文件已经在安装包里，不需要另外下载。

## 安装

在 [Releases](https://github.com/habinsong/negaflow-scanner-sane/releases) 下载
`negaflow-sane-1.1.1-win-x64.exe` 并运行。

1. 选语言，按提示操作。
2. 快结束时会问要不要打开扫描仪通路。只有这一步需要管理员确认。
3. 重开 negaflow，扫描仪的操作就出现了。

## 和 VueScan 或 SilverFast 一起用

可以一起用。

这个插件通过 Windows 本身提供的扫描仪驱动通路（`usbscan.sys`）和设备通信，不替换也不覆盖
驱动，所以其他扫描软件原来用的东西都还在。

只有一条要注意：同一时间只能有一个程序占用扫描仪。在 negaflow 里扫描时先关掉 VueScan，
反过来也一样。

## 卸载

用开始菜单的`卸载 negaflow 扫描仪插件`，或者设置里的应用列表。

卸载时会问一次要不要把安装时打开的扫描仪通路还原。还原了 Windows 就回到原来的驱动，
跳过则通路保留。无论选哪个，negaflow 本体和照片都不动。

## 找不到扫描仪时

按顺序排查。

1. **重开过 negaflow 吗。** 应用在启动时读插件，装完要重开一次。
2. **电源和 USB。** 看设备管理器里有没有作为映像设备出现。
3. **有没有别的程序占着。** 关掉 VueScan、SilverFast 或厂商的工具。
4. **安装时跳过了打开扫描仪通路吗。** 跳过了就再运行一次安装程序，这次选是。

还是不出现的话，可以自己看插件是怎么找的。

```powershell
& "$env:LOCALAPPDATA\Negaflow\Plugins\sane\negaflow-scanner-sane.exe" detect
```

找到设备会返回 JSON。空列表说明 SANE 那一层就没找到。报错的话，错误信息就是原因。

## 扫描扫到一半停住

- 如果接在 USB 集线器上，直接插到电脑上试试。胶片扫描数据量大，集线器有时会掉。
- 检查省电设置有没有把 USB 端口断电。
- 把分辨率降一档看看。降了能过说明是传输速度的问题。

## 验证过的设备

| 扫描仪 | 验证内容 |
|---|---|
| Plustek OpticFilm 8100 | 预览与正式扫描、多档分辨率、彩色与灰度、8 位与 16 位 |
| Epson Perfection V700 | 预览与正式扫描、多档分辨率、红外通道、彩色与灰度 |

这里写的是实际跑过的组合。不在表里的扫描仪也可能能用，只是没验证过。

## 构建

```powershell
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane\negaflow-windows

cmake --preset x64-release
cmake --build --preset x64-release
ctest --preset x64-release --output-on-failure
```

需要 Visual Studio 2022 和 CMake 3.28 或更高。

制作安装程序：

```powershell
.\scripts\build-installer.ps1 -Overwrite
```

## 相关文档

- [共用文档](../../README_zh-Hans.md)
- [macOS 文档](../../negaflow-mac/docs/README_zh-Hans.md)
- [来源说明](../../PROVENANCE.md)
- [第三方声明](../../THIRD_PARTY_NOTICES.md)
