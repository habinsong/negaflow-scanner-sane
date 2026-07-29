<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">A SANE film-scanner plug-in for negaflow on macOS</p>

<p align="center">
  <a href="#requirements"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 or later"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift 5.9 or later"></a>
  <a href="manifest.json"><img src="https://img.shields.io/badge/protocol-v2-4B5563" alt="negaflow scanner protocol v2"></a>
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

---

**negaflow-scanner-sane** connects [negaflow](https://github.com/habinsong/negaflow) to film scanners available through SANE.<br>
It runs `scanimage`, reads the options reported by the scanner, and returns device information, capabilities, progress, and TIFF paths through negaflow scanner protocol v2.

This is an installable command-line plug-in, not a second scanning interface.<br>
Once it is installed and approved, scanning is done from negaflow.

The plug-in and the main app are separate programs.<br>
All SANE-specific code stays in this GPL-2.0-or-later repository; negaflow is Apache-2.0 and communicates with the plug-in only through a separate process, command-line arguments, pipes, and JSON.

## What it does

- Finds scanners through `scanimage -L`
- Builds controls from the device's current `scanimage -A` output
- Supports preview and full scans without replacing requested values with nearby defaults
- Checks resolution, color mode, bit depth, dimensions, and TIFF format before returning a result
- Uses a millimetre scan area only when the backend reports the required ranges
- Captures a separate infrared channel when the backend can actually deliver one
- Enables hardware multi-exposure only when `--scan-exposure-time` covers the required exposure plan
- Stops only the `scanimage` process started by the current plug-in instance

It does not decide support from the scanner name alone.<br>
A control appears only when the connected device and its active SANE backend report the option.

## Requirements

- macOS 14.0 or later for the current negaflow and Homebrew installation path
- negaflow
- Stock Homebrew `sane-backends` for the standard scanner path
- macOS 26 or later only for the separate patched Nikon Coolscan path
- Swift 5.9 or later only when building from source

`Package.swift` keeps a macOS 13 deployment target for the standalone executable.<br>
The supported end-to-end setup in this guide starts at macOS 14 because it follows the current negaflow and Homebrew requirements.

## Install

### 1. One-shot installer

Install Xcode Command Line Tools first if they are not already present:

```bash
xcode-select --install
```

Four installers are published. Use the standard variant for ordinary SANE scanners. Nikon
Coolscan users on macOS 26 or later should use the separate Coolscan variant.

| Installer | SANE path | Plug-in binary |
|---|---|---|
| `negaflow-scanner-sane-1.0.3-macos-arm64-installer.dmg` | Standard, macOS 14+ | `arm64` only |
| `negaflow-scanner-sane-1.0.3-macos-universal-installer.dmg` | Standard, macOS 14+ | `arm64` + `x86_64` |
| `negaflow-scanner-sane-1.0.3-coolscan-macos26-arm64-installer.dmg` | Patched Coolscan, macOS 26+ | `arm64` only |
| `negaflow-scanner-sane-1.0.3-coolscan-macos26-universal-installer.dmg` | Patched Coolscan, macOS 26+ | `arm64` + `x86_64` |

The standard DMG contains `Install negaflow Scanner.pkg`; the Coolscan DMG contains
`Install negaflow Scanner for Coolscan.pkg`.

The standard package installs stock Homebrew `sane-backends`. The Coolscan package builds the
pinned official SANE 1.4.0 source as `sane-backends-negaflow` with the upstream
`coolscan2`/`coolscan3` allocation fix and an `epson2` scan-height fix, then installs the same
plug-in.<br>
An internet connection and an administrator password are required.<br>
Existing Homebrew installations are reused.

The standard installer and macOS versions below 26 do not proactively block Coolscan. Stock SANE
may work on a particular unit, but it does not include this allocation fix; the macOS 26 Coolscan
installer is the supported patched path.

A later upstream change also initializes the Coolscan3 load/eject/reset parameter blocks required
by at least LS-5000 firmware 1.03. It is intentionally outside this minimal patch set, so LS-5000
load/eject/reset remains unverified and may fail even with the patched installer.

Restart negaflow when the installer finishes, open **Load Scanner**, review the plug-in details, and approve it.

### 2. Manual Homebrew and SANE installation

If Homebrew is not installed, use its current official installer:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

This command downloads and runs Homebrew's installer.<br>
Before running it, check that the URL is exactly `raw.githubusercontent.com/Homebrew/install/HEAD/install.sh`.<br>
A signed `.pkg` alternative is also linked from the [official Homebrew website](https://brew.sh/).

Follow the **Next steps** printed by the installer so `brew` is added to the shell environment, then open a new Terminal window and check that the command is available:

```bash
brew --version
```

For the standard macOS 14+ path:

```bash
brew install sane-backends
```

For the patched Coolscan path on macOS 26 or later:

```bash
bash scripts/install-patched-sane.sh
export PATH="$(brew --prefix sane-backends-negaflow)/bin:$PATH"
```

Check the installed frontend:

```bash
command -v scanimage
scanimage --version
brew list --versions sane-backends sane-backends-negaflow
```

When the patched keg exists, the plug-in invokes its absolute `/opt/homebrew/opt/...` or
`/usr/local/opt/...` path and uses that same keg's `etc/sane.d` and `lib/sane`.

### 3. Connect and check the scanner

Turn the scanner on, connect it directly by USB when possible, and run:

```bash
scanimage -L
```

Copy the complete device ID printed by that command, including the backend and USB address, then inspect the options exposed by that exact device:

```bash
scanimage -d '<device-id>' -A
```

For example, a device ID can look like `genesys:libusb:001:002`.<br>
Do not copy that example as-is; use the value returned on the current Mac.

`sane-find-scanner` only proves that a USB or SCSI device was found.<br>
It can also list scanners for which no usable SANE backend exists.<br>
If the device does not appear in `scanimage -L`, this plug-in cannot use it.<br>
Check the USB connection, the [SANE device list](https://www.sane-project.org/sane-supported-devices.html), and the backend's own manual before continuing.

### 4A. Build and install the plug-in from source

```bash
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
./install.sh
```

The script makes a Release build and installs these two files:

```text
~/Library/Application Support/negaflow/Plugins/sane/
  ├── negaflow-scanner-sane
  └── manifest.json
```

### 4B. Install a packaged ZIP release

Extract the release ZIP and run the included installer:

```bash
./install.sh
```

The packaged installer does not need a Swift toolchain. `install.sh` installs only the plug-in;
install stock SANE or run the macOS 26 Coolscan helper first as described above.

### 5. Approve and verify it in negaflow

Restart negaflow and open **Load Scanner**.<br>
Review the plug-in path, version, license, and hashes, then approve it.<br>
If the executable or manifest changes after an update, negaflow asks for approval again.

The installed executable can also be checked directly:

```bash
"$HOME/Library/Application Support/negaflow/Plugins/sane/negaflow-scanner-sane" detect
```

A `{"devices":[...]}` response means the plug-in ran.<br>
An empty `devices` array means the plug-in started but SANE did not return a usable scanner.<br>
In that case, return to `scanimage -L`; reinstalling the plug-in does not add support to a missing SANE backend.

## Scanner support

The table below describes known SANE 1.4 targets and the paths handled by this plug-in.<br>
It is not a promise that every unit with the same product name will work.<br>
Check the [current SANE device list](https://www.sane-project.org/sane-supported-devices.html), then confirm the connected unit with `scanimage -L` and `scanimage -A`.

| Scanner family | SANE backend | SANE 1.4 status | Plug-in path |
|---|---|---|---|
| Plustek OpticFilm 7200, 7200 v2, 7200i, 7300, 7400 v2, 7500i, 7600i | `genesys` | Complete | Dedicated film-scanner path |
| Plustek OpticFilm 7400 v1 | `genesys` | Listed as Complete, but its model-specific corrections landed after SANE 1.4.0 | Capability-driven path; stock 1.4.0 hardware result is unverified |
| Plustek OpticFilm 8100, USB `07b3:130c` | `genesys` | Complete | Dedicated film-scanner path |
| Plustek OpticFilm 8100, USB `07b3:1824` | None | Unsupported | Not treated as usable |
| Plustek OpticFilm 8200i, USB `07b3:130d` | `genesys` | Complete | Dedicated film-scanner path |
| Plustek OpticFilm 8200i, USB `07b3:1825` (GL128) | None | Unsupported | Not treated as usable |
| Plustek OpticFilm 120, 120 Pro, 135, 135i, 9000i Ai | None | Unsupported | Not treated as usable |
| Epson Perfection V700/V750 (GT-X900), V800/V850 (GT-X980) | `epson2` | Good | Transparency source and positioned flatbed area when reported |
| Nikon Coolscan LS-2000, LS-40 ED, LS-50 ED, LS-4000 ED, LS-8000 ED | `coolscan3` | Complete to Minimal; varies by model | Dedicated film-scanner path |
| Nikon Coolscan LS-5000 ED | `coolscan3` | Untested; may work similarly to LS-50 according to SANE 1.4 | Dedicated film-scanner path |
| Nikon Coolscan LS-20, LS-30, LS-1000 | `coolscan` | Varies by model | SCSI only |
| Nikon Coolscan LS-9000 ED | None | Unsupported | Not treated as usable |
| Reflecta ProScan/CrystalScan/DigitDia and PIE PowerSlide | `pieusb`; old SCSI models use `pie` | Varies by model and model number | Options are accepted only when reported |
| Pacific Image PrimeFilm XA, XAs, XA Plus | None | Unsupported | Not treated as usable |
| Other transparency-capable flatbeds and film scanners | Varies | Varies by model | Capability-driven; no model-name fallback |

### A product name does not identify the hardware

OpticFilm 8100 and 8200i each ship in at least two USB variants under one product name.<br>
`07b3:130c` and `07b3:130d` are driven by `genesys`; `07b3:1824` and `07b3:1825` are not, because
they use a different Genesys chip that no backend drives.<br>
A newer revision sold under an older name cannot be fixed from the SANE side, so check the USB
product ID rather than the name on the case.

Two more identification traps are worth knowing.

- `pieusb` matches a USB ID **and** a model number. Reflecta and PIE units share IDs such as
  `05e3:0145`, so a unit is usable only when its model number is listed in `pieusb.conf`.
- `epson2` knows Epson scanners by their Japanese model names. `scanimage -L` reports a Perfection
  V800/V850 as `GT-X980` and a V700/V750 as `GT-X900`. That is the same scanner, not a wrong device.

## Infrared channel

In this plug-in, “IR available” means that a separate infrared image can be returned to negaflow as `irPath`.<br>
A backend's private dust-removal switch is not reported as an IR channel.

| Scanner or backend path | IR status | How it is acquired | Separate IR TIFF |
|---|---|---|---|
| OpticFilm 7200, 7200 v2, 7300, 7400, 8100 | Not available | These models do not expose an IR source | No |
| OpticFilm 7200i, 7500i, 7600i, 8200i `07b3:130d` | Available when `scanimage -A` reports the infrared source | Separate `Transparency Adapter Infrared` pass | Yes |
| OpticFilm 8200i `07b3:1825` | Not available | The device variant is unsupported by SANE 1.4 | No |
| Epson V700/V750/V800/V850 with stock `epson2` | Not available | Stock builds do not expose a separate IR mode | No |
| Epson path with a custom `SANE_FRAME_IR` build | Conditional | Separate `Infrared` mode pass, only when reported | Yes |
| Nikon `coolscan3` with `--infrared` | Not available through stock `scanimage` | `coolscan3` returns one `SANE_FRAME_RGBI` frame, which `scanimage` 1.4 does not split into RGB and IR TIFF files | No |
| Reflecta/PIE with `--clean-image` only | Not available as an IR channel | Dust removal happens inside the backend | No |
| Any other scanner | Conditional | Only when `scanimage -A` reports an active, separate IR source or mode | Yes, after size and format checks |

The IR pass uses the same requested resolution and scan area as the RGB pass.<br>
The plug-in also checks that both images have the same pixel dimensions before returning them.<br>
negaflow can then use the IR image for GrainMend IR.

## Troubleshooting: no scanner found

**Approved** in negaflow means the plug-in executable is allowed to run.<br>
It does not mean a scanner was found. Detection is whatever `scanimage -L` returns, so a scanner
missing there is also missing in negaflow, and reinstalling the app or the plug-in changes nothing.

macOS has no per-app USB permission to switch on. Neither negaflow nor this plug-in uses the App
Sandbox, so no **Privacy & Security** setting gates scanner access.

### 1. Find the layer that fails

With the scanner powered on and connected, run these in order.

```bash
system_profiler SPUSBDataType
```

```bash
scanimage -L
```

```bash
"$HOME/Library/Application Support/negaflow/Plugins/sane/negaflow-scanner-sane" detect
```

| USB list | `scanimage -L` | `detect` | Where the problem is |
|---|---|---|---|
| No scanner | Nothing | `{"devices":[]}` | Cable, port, or power, before SANE is involved |
| Scanner listed | Nothing | `{"devices":[]}` | SANE backend, or another process holding the device |
| Scanner listed | Device listed | `{"devices":[]}` | SANE installed where the plug-in does not look |
| Scanner listed | Device listed | Device listed | negaflow side: reopen **Load Scanner** and approve again |

### 2. Common causes

| Symptom | Cause | What to do |
|---|---|---|
| `scanimage: command not found` | SANE is not installed or its `bin` is outside the current `PATH` | Install stock `sane-backends`; for Coolscan use the patched helper and export shown above |
| The scanner is not in the USB list | Hub, dock, adapter, cable, or power | Connect it directly, try another port, and avoid hubs. USB 2.0 film scanners often fail through USB-C adapters |
| `no SANE devices found` while `sane-find-scanner` sees the device | No enabled backend claims this model | Check the [SANE device list](https://www.sane-project.org/sane-supported-devices.html), then read the log in step 3 |
| The scanner is in the USB list, `scanimage -L` is empty, and `repair-sane-config` reports `notNeeded` | The unit is a hardware revision SANE does not know | Compare the USB product ID against [Scanner support](#scanner-support). A newer revision sold under an older product name cannot be fixed from this side |
| A Coolscan LS-50 or LS-5000 vanishes from the USB list | A documented USB port failure on these units | Confirm with another cable and port. If the Mac never enumerates it, this is a hardware fault, not a driver problem |
| `another process has device opened for exclusive access`, `device busy`, `is not configured` | Another program already claimed the USB interface | Quit VueScan, SilverFast, Image Capture, and vendor utilities, reconnect the scanner, then retry |
| Only `sudo scanimage -L` finds it | The interface is claimed or was never released | Solve the claim above. negaflow never runs the plug-in as root, so `sudo` is not a workaround |
| Terminal finds it, negaflow does not | SANE lives outside the supported Homebrew keg paths | Re-run the included installer; MacPorts (`/opt/local`) and unrelated hand-built prefixes are not used |
| `open of device ... failed: Invalid argument` | The USB address changed after the first open, or the SANE config directory is missing | Run `detect` again, and confirm `/opt/homebrew/etc/sane.d` or `/usr/local/etc/sane.d` exists |
| It worked before an update | The selected SANE keg was removed or replaced | Re-run the matching installer and check `brew list --versions sane-backends sane-backends-negaflow` |
| Empty list after an older negaflow plug-in was installed | A legacy build disabled backends in `dll.conf` | Run `repair-sane-config`, described in [SANE configuration](#sane-configuration) |

### 3. Read the backend log

```bash
SANE_DEBUG_DLL=3 scanimage -L 2>&1 | tail -40
```

This shows which backends load and which fail.<br>
To narrow it to one backend, use that backend's own variable, such as `SANE_DEBUG_GENESYS=128` or
`SANE_DEBUG_EPSON2=128`.

A report is only useful with the macOS version, the Mac model, `scanimage --version`,
`brew list --versions sane-backends sane-backends-negaflow`, the scanner model, and the output of the three steps above.

## Exact settings and failure behaviour

- A requested DPI must exist in the device's list or range. The plug-in does not snap it to the
  nearest resolution.
- A 16-bit request succeeds only when SANE uses a depth above 8 and the decoded file is a 16-bit TIFF.
- A physical scan area is advertised only with usable millimetre `-x/-y` ranges. Positioned scanning
  also needs `-l/-t`.
- Source, mode, depth, resolution, preview, and geometry are checked again after dependent options
  are applied.
- Preview does not silently add IR or multi-exposure.
- Hardware multi-exposure is not simulated with brightness, contrast, or gamma.
- A failed or mismatched result is discarded and returned as an error instead of falling back to an
  unchecked file.

## negaflow scanner protocol

The executable is called with subcommands and writes JSON to standard output.

| Command | Input | Output |
|---|---|---|
| `detect` | None | Device list as JSON |
| `capabilities <deviceId>` | Optional detect identity JSON | Resolution, mode, bit depth, area, exposure, and IR capabilities as JSON |
| `scan` | Protocol v2 request JSON on stdin | NDJSON progress and a final result or error event |
| `repair-sane-config` | None | Re-enables only backends disabled by an older negaflow plugin |
| `tune-sane` | None | Compatibility alias for `repair-sane-config` |
| `restore-sane` | None | Restores the full legacy backup as a last resort |

Every protocol v2 event carries `protocolVersion`, `requestID`, and an increasing `sequence`.<br>
A successful result contains `appliedOptions` only after the output TIFF and applied scan settings have been checked.
negaflow automatically returns the opaque `capabilityToken` from `capabilities` in the following scan request.<br>
Direct CLI callers should do the same; omitting it keeps the slower compatibility preflight.

Capabilities are read in the state the scan will actually run in. SANE options change which other options are active — `epson2` marks depth inactive in Lineart and brightness inactive once a linear gamma is selected — so a dump taken in the device's default state does not describe the scan. The plug-in applies the transparency source, the scan mode and the neutral colour and gamma settings, reads the options in that state, and carries that state in the token. Requesting a different mode re-reads the options in that mode.

Example full-scan request:

```json
{
  "protocolVersion": 2,
  "requestID": "7A91B43D-90F8-41E2-B71D-04D17CD9E03B",
  "deviceID": "sane-genesys:libusb:001:002",
  "capabilityToken": "<opaque token returned by capabilities>",
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

## SANE configuration

The patched keg uses its own `etc/sane.d` and does not modify a stock Homebrew `dll.conf`.<br>
`detect` automatically repairs backend lines disabled by an older negaflow plugin while preserving distribution and user comments. You can run the same repair manually:

```bash
.build/release/negaflow-scanner-sane repair-sane-config
```

If a legacy `dll.conf.negaflow-backup` exists, the following command replaces the whole current file with that backup. Use it only when the surgical repair above is insufficient because changes made after the backup are also reverted:

```bash
.build/release/negaflow-scanner-sane restore-sane
```

## Repository

| Path | Role |
|---|---|
| `Sources/SANEPluginCore` | SANE discovery, capability parsing, acquisition, TIFF validation, IR, and exposure merging |
| `Sources/negaflow-scanner-sane` | Thin JSON/CLI adapter for negaflow scanner protocol v2 |
| `Tests/SANEPluginCoreTests` | Protocol, process, option-parser, TIFF, and virtual-scanner regression tests |
| `Installer` | One-shot PKG distribution, installer scripts, and Installer.app resources |
| `scripts` | Universal build, signing, packaging, installation, notarization, and release checks |

## Development checks

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

The model-specific virtual scanner tests run real subprocess and TIFF contracts, including preview, full scan, scan area, and IR paths.<br>
They do not emulate scanner motors, optics, USB transport, or final image quality, and are not presented as physical-hardware proof.

## Release build

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
```

The script builds `arm64` and `x86_64`, combines them into a universal executable, creates a dSYM, signs the executable, packages the plug-in, writes SHA-256 checksums, and verifies the archive.<br>
Output is written to `.build/release-artifacts/`.

Distribution signing and notarization additionally require `NEGAFLOW_CODESIGN_IDENTITY`, `NEGAFLOW_NOTARY_KEYCHAIN_PROFILE`, and `NEGAFLOW_RELEASE_MODE=distribution`.

Build the standalone one-shot PKG and DMG with:

```bash
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

The installer build verifies the pinned official Homebrew package before incorporating its component, then produces both the Apple Silicon and the universal variant and checks each PKG and DMG without installing them.<br>
Set `NEGAFLOW_INSTALLER_ARCHITECTURE` to `arm64` or `universal` to build only one variant; the default `all` builds both.<br>
Set `NEGAFLOW_INSTALLER_VARIANT=all` to build both the standard and Coolscan families; the default
builds only the standard family.<br>
Distribution mode additionally requires `NEGAFLOW_INSTALLER_MODE=distribution`, a `NEGAFLOW_INSTALLER_IDENTITY` for the PKG, and the same application signing and notarization credentials used by the release build.

## License

This project is distributed under [GPL-2.0-or-later](LICENSE).<br>
Release archives include the license notice and the full GNU GPL v2 text in [COPYING](COPYING).

The installers include [third-party notices](THIRD_PARTY_NOTICES.md) for the bundled Homebrew
component and, in the Coolscan variant, the patched SANE source built on the user's Mac.<br>
The matching complete plug-in source archive is published beside and included in the release ZIP,<br>
and is also included in both the PKG payload and the DMG.

negaflow is a separate Apache-2.0 project.<br>
Product and scanner names are used only to identify compatible or measured targets; they remain the property of their respective owners.
