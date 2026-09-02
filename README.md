<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">The plugin that connects film scanners to negaflow</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="website"></a>
  <a href="negaflow-mac/docs/README.md"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 or later"></a>
  <a href="negaflow-windows/docs/README.md"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
  <a href="negaflow-mac/manifest.json"><img src="https://img.shields.io/badge/protocol-v2-4B5563" alt="negaflow scanner protocol v2"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0--or--later-6E7781" alt="GPL 2.0 or later"></a>
</p>

<p align="center">
  <strong>English</strong> ·
  <a href="README_ko.md">한국어</a> ·
  <a href="README_ja.md">日本語</a> ·
  <a href="README_zh-Hans.md">简体中文</a> ·
  <a href="README_fr.md">Français</a> ·
  <a href="README_de.md">Deutsch</a>
</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/">Website</a> ·
  <a href="https://habinsong.github.io/negaflow-site/supported-scanners/">Supported scanners</a> ·
  <a href="https://habinsong.github.io/negaflow-site/faq/">FAQ</a>
</p>

---

**negaflow-scanner-sane** connects film scanners that SANE can drive to
[negaflow](https://github.com/habinsong/negaflow).

Scanning still happens in negaflow. The plugin sits behind it and does the talking to the scanner,
so there is nothing here to run yourself. Install it, approve it once in negaflow, and the scanner
shows up under **Load scanner**.

The plugin and the app are separate programs. All the SANE code lives in this GPL-2.0-or-later
repository, and negaflow, which is Apache-2.0, only exchanges JSON with it across a process
boundary.

## Requirements

- negaflow, installed first
- A film scanner that SANE supports
- macOS 14.0 or later, or Windows 11

## Install

Download the installer for your system from
[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases), run it, restart negaflow,
and approve the plugin. On macOS the installer sets up SANE through Homebrew as well. On Windows the
SANE binaries are already inside the installer.

| Platform | Page |
|---|---|
| macOS | [Install on macOS](negaflow-mac/docs/README.md) |
| Windows | [Install on Windows](negaflow-windows/docs/README.md) |

## Scanners

Most film scanners SANE supports will work. The catch is that two units sold under the same product
name can carry different chips, and only one of them has a backend. The infrared channel is used
only when the device really provides one. Which model does what is in
[supported scanners](docs/SCANNERS.md).

A model name never opens a feature by itself. What the connected device and its backend report is
what negaflow gets.

## Documentation

- [Supported scanners](docs/SCANNERS.md) | model by model, product name traps, infrared channel
- [Troubleshooting](docs/TROUBLESHOOTING.md) | failed installs, no scanner found, SANE configuration
- [Development](docs/DEVELOPMENT.md) | scanner protocol, repository layout, builds
- Install pages | [macOS](negaflow-mac/docs/README.md) · [Windows](negaflow-windows/docs/README.md)

## License

This project is distributed under [GPL-2.0-or-later](LICENSE). Release archives include the license
notice and the full GNU GPL v2 text in [COPYING](COPYING).

The installers include [third-party notices](THIRD_PARTY_NOTICES.md) for the bundled Homebrew
component and, in the Coolscan variant, the patched SANE source built on the user's Mac. The
matching complete plugin source archive is published beside the release ZIP and included in it, as
well as in the PKG payload and the DMG.

negaflow is a separate Apache-2.0 project. Product and scanner names are used only to identify
compatible or measured targets; they remain the property of their respective owners.
