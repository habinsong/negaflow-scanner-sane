<h1 align="center">negaflow-scanner-sane for Windows</h1>

<p align="center">The plugin that connects SANE film scanners to negaflow on Windows</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.1-EF8B26" alt="version 1.1.1"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0--or--later-6E7781" alt="GPL 2.0 or later"></a>
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
  <a href="../../README.md">Shared documentation</a> ·
  <a href="../../negaflow-mac/docs/README.md">macOS</a>
</p>

---

## What you need

- Windows 11, 64-bit
- negaflow 1.1.1 or later, installed first
- A film scanner that SANE supports

The SANE binaries ship inside the installer. There is nothing else to download.

## Installing

Download `negaflow-sane-1.1.1-win-x64.exe` from
[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases) and run it.

1. Pick a language and follow the prompts.
2. Near the end it asks whether to open the scanner path. This is the one step that needs
   an administrator confirmation.
3. Restart negaflow and the scanner controls appear.

## Using VueScan or SilverFast alongside it

You can.

This plugin talks to the device through the scanner driver path Windows already provides
(`usbscan.sys`). It does not swap the driver or overwrite it with something else, so
whatever your other scanning software was using stays in place.

The one rule is that only one program can hold the scanner at a time. Close VueScan while
you scan in negaflow, and the other way around.

## Removing it

Use `Uninstall negaflow scanner plug-in` in the Start menu, or the app list in Settings.

The uninstaller asks once whether to undo the scanner path it opened during installation.
Undo it and Windows goes back to the driver it used before. Skip it and the path stays.
Either way negaflow itself and your photos are untouched.

## When no scanner shows up

Work through these in order.

1. **Did you restart negaflow?** The app reads plugins at startup, so it needs one restart
   after installation.
2. **Power and USB.** Check that the scanner appears in Device Manager as an imaging device.
3. **Another program holding it.** Close VueScan, SilverFast, or the manufacturer's utility.
4. **Did you skip opening the scanner path during installation?** If so, run the installer
   again and answer yes this time.

If it still does not appear, you can watch the plugin look for scanners yourself.

```powershell
& "$env:LOCALAPPDATA\Negaflow\Plugins\sane\negaflow-scanner-sane.exe" detect
```

A device that is found comes back as JSON. An empty list means SANE did not find it. An
error message tells you what went wrong.

## When a scan stops partway

- If the scanner is on a USB hub, plug it straight into the computer. Film scans move a lot
  of data and hubs sometimes drop it.
- Check that power saving is not switching off the USB port.
- Try one step down in resolution. If that works, the problem is transfer speed.

## Devices that have been checked

| Scanner | What was checked |
|---|---|
| Plustek OpticFilm 8100 | Preview and full scan, several resolutions, color and gray, 8-bit and 16-bit |
| Epson Perfection V700 | Preview and full scan, several resolutions, infrared channel, color and gray |

These are the combinations that were actually run. A scanner missing from the list is not
known to fail, it just has not been checked.

## Building

```powershell
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane\negaflow-windows

cmake --preset x64-release
cmake --build --preset x64-release
ctest --preset x64-release --output-on-failure
```

You need Visual Studio 2022 and CMake 3.28 or later.

To build the installer:

```powershell
.\scripts\build-installer.ps1 -Overwrite
```

## Related documents

- [Shared documentation](../../README.md)
- [macOS docs](../../negaflow-mac/docs/README.md)
- [Provenance](../../PROVENANCE.md)
- [Third-party notices](../../THIRD_PARTY_NOTICES.md)
