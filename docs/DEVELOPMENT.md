# Development

[Docs home](README.md)

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

Every protocol v2 event carries `protocolVersion`, `requestID`, and an increasing `sequence`. A
successful result contains `appliedOptions` only after the output TIFF and the applied scan settings
have been checked. negaflow returns the opaque `capabilityToken` from `capabilities` in the next
scan request automatically. Direct CLI callers should do the same; omitting it keeps the slower
compatibility preflight.

Capabilities are read in the state the scan will actually run in, because SANE options change which
other options are active. `epson2` marks depth inactive in Lineart and brightness inactive once a
linear gamma is selected, so a dump taken in the device's default state does not describe the scan.
The plugin applies the transparency source, the scan mode and the neutral colour and gamma settings,
reads the options in that state, and carries that state in the token. Requesting a different mode
re-reads the options in that mode.

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

## Requested values and failures

- A requested DPI must exist in the device's list or range. It is not snapped to the nearest
  resolution.
- A 16-bit request succeeds only when SANE uses a depth above 8 and the decoded file is a 16-bit
  TIFF.
- A physical scan area is advertised only with usable millimetre `-x/-y` ranges. Positioned scanning
  also needs `-l/-t`.
- Source, mode, depth, resolution, preview, and geometry are checked again after dependent options
  are applied.
- Preview does not silently add IR or multi-exposure.
- Hardware multi-exposure is not simulated with brightness, contrast, or gamma.
- A failed or mismatched result is discarded and returned as an error.

## Repository

| Path | Role |
|---|---|
| `Sources/SANEPluginCore` | SANE discovery, capability parsing, acquisition, TIFF validation, IR, and exposure merging |
| `Sources/negaflow-scanner-sane` | Thin JSON/CLI adapter for negaflow scanner protocol v2 |
| `Tests/SANEPluginCoreTests` | Protocol, process, option-parser, TIFF, and virtual-scanner regression tests |
| `Installer` | One-shot PKG distribution, installer scripts, and Installer.app resources |
| `scripts` | Universal build, signing, packaging, installation, notarization, and release checks |

## Checks

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

The model-specific virtual scanner tests run real subprocess and TIFF contracts, including preview,
full scan, scan area, and IR paths. They do not emulate scanner motors, optics, USB transport, or
final image quality, and they are not proof on physical hardware.

## Release build

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
```

The script builds `arm64` and `x86_64`, combines them into a universal executable, creates a dSYM,
signs the executable, packages the plugin, writes SHA-256 checksums, and verifies the archive.
Output goes to `.build/release-artifacts/`.

Distribution signing and notarization also need `NEGAFLOW_CODESIGN_IDENTITY`,
`NEGAFLOW_NOTARY_KEYCHAIN_PROFILE`, and `NEGAFLOW_RELEASE_MODE=distribution`.

Build the standalone one-shot PKG and DMG with:

```bash
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

The installer build verifies the pinned official Homebrew package before it takes in that component,
then produces the Apple Silicon and the universal variant and checks each PKG and DMG without
installing them. Set `NEGAFLOW_INSTALLER_ARCHITECTURE` to `arm64` or `universal` to build only one
variant; the default `all` builds both. Set `NEGAFLOW_INSTALLER_VARIANT=all` to build the standard
and Coolscan families; the default builds only the standard family. Distribution mode also needs
`NEGAFLOW_INSTALLER_MODE=distribution`, a `NEGAFLOW_INSTALLER_IDENTITY` for the PKG, and the same
application signing and notarization credentials used by the release build.
