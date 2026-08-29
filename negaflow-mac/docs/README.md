<h1 align="center">negaflow-scanner-sane for macOS</h1>

<p align="center">The plugin that connects SANE film scanners to negaflow on macOS</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="version 1.1.0"></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 or later"></a>
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
  <a href="../../negaflow-windows/docs/README.md">Windows</a>
</p>

---

## What you need

- macOS 14.0 or later
- negaflow 1.1.0 or later, installed first
- A film scanner that SANE supports
- An internet connection and an administrator password during installation

Install the Xcode Command Line Tools first if you do not have them.

```bash
xcode-select --install
```

## Installing

Download a DMG from
[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases). There are four.
Take a `macos26` one unless you cannot run macOS 26.

| Download | SANE | Plugin |
|---|---|---|
| `negaflow-scanner-sane-1.1.0-macos26-arm64-installer.dmg` | Patched, macOS 26 or later | `arm64` only |
| `negaflow-scanner-sane-1.1.0-macos26-universal-installer.dmg` | Patched, macOS 26 or later | `arm64` and `x86_64` |
| `negaflow-scanner-sane-1.1.0-opticfilm-macos14-arm64-installer.dmg` | For OpticFilm, macOS 14 or later | `arm64` only |
| `negaflow-scanner-sane-1.1.0-opticfilm-macos14-universal-installer.dmg` | For OpticFilm, macOS 14 or later | `arm64` and `x86_64` |

In a `macos26` DMG run `Install negaflow Scanner.pkg`. In an `opticfilm-macos14` DMG run
`Install negaflow Scanner for OpticFilm.pkg`.

When it finishes, restart negaflow, look at the plugin details under **Load scanner**, and
approve it.

### How the two builds differ

The `macos26` build compiles the official SANE 1.4.0 source as `sane-backends-negaflow`.
That build is what makes Nikon Coolscan and the Epson infrared channel work. Three patches
go in.

| Patch | What it changes |
|---|---|
| Coolscan depth list | Fixes the upstream `coolscan2` and `coolscan3` allocation |
| `epson2` scan height | Corrects the scan height Epson flatbeds report |
| `epson2` infrared | Lifts the `SANE_FRAME_IR` block so Epson film flatbeds can produce an infrared pass |

The `opticfilm-macos14` build installs the stock Homebrew `sane-backends` without those
patches. It exists for macOS 14 and 15, where the patched build cannot be installed.

Neither build blocks Coolscan on macOS 14 or 15. It may work with stock SANE, but without
the allocation fix, so the supported path is the `macos26` installer.

The Coolscan3 load, eject, and reset parameter setup that LS-5000 firmware 1.03 needs was
deliberately left out of the patch set. Film loading, ejecting, and resetting on an LS-5000
is unverified and may fail even on the patched build.

## Installing by hand

If you would rather manage Homebrew and SANE yourself:

```bash
# If you do not have Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install SANE
brew install sane-backends

# Check that the scanner is seen
scanimage -L
```

Then build the plugin from source, or install it from the release ZIP.

```bash
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
swift build -c release
```

## When no scanner shows up

Work through these in order.

1. **Did you restart negaflow?** The app reads plugins at startup.
2. **Did you approve it?** The plugin only runs after you approve it on the Load scanner
   screen.
3. **Does SANE see the device?** Run `scanimage -L` in Terminal. If nothing appears there,
   the problem is at the SANE level rather than in the plugin.
4. **Is another program holding it?** Close VueScan or the manufacturer's utility.

You can also watch the plugin look for scanners itself.

```bash
/usr/local/bin/negaflow-scanner-sane detect
```

## Devices that have been checked

| Scanner | What was checked |
|---|---|
| Plustek OpticFilm 8100 | Preview and full scan, several resolutions, color and gray |
| Epson Perfection V700 | Preview and full scan, several resolutions, infrared channel |

A scanner missing from the list is not known to fail, it just has not been checked.

## Building and checking

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

The virtual scanner tests use real process execution and the TIFF contract to check
preview, full scan, scan area, and the infrared path. They do not reproduce scanner motors,
optics, USB transfer, or final image quality.

For releases and installers:

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

## Related documents

- [Shared documentation](../../README.md)
- [Windows docs](../../negaflow-windows/docs/README.md)
- [Provenance](../../PROVENANCE.md)
- [Third-party notices](../../THIRD_PARTY_NOTICES.md)
