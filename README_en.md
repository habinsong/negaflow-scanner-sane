# negaflow-scanner-sane

**Installable SANE film-scanner plugin for negaflow.**

<a href="README.md">한국어로 읽기</a>

This is an independent program split out from the Apache-2.0 negaflow app. It uses SANE
(`scanimage`, GPL) to detect and control film scanners, then returns results through the
negaflow JSON/CLI contract. The main negaflow app does not contain SANE code and talks to
this plugin only through a separate OS process, command-line arguments, pipes, and JSON.

- Plugin repository: <https://github.com/habinsong/negaflow-scanner-sane>
- Main app repository: <https://github.com/habinsong/negaflow>

## Why This Is Separate

- The SANE `genesys` backend used by Plustek OpticFilm scanners is GPL-2.0-or-later without a linking exception.
- negaflow is Apache-2.0.
- Keeping scanner code in this GPL project avoids mixing SANE implementation code into the main app binary.
- The process boundary is intentional: the plugin is invoked as a standalone executable and communicates with JSON only.

## Requirements

- macOS 13 or later
- Swift / SwiftPM
- SANE `scanimage` at runtime:

```sh
brew install sane-backends
```

## Build And Install

```sh
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
./install.sh
```

The installer builds a release executable and copies it with `manifest.json` to:

```text
~/Library/Application Support/negaflow/Plugins/sane/
  ├── negaflow-scanner-sane
  └── manifest.json
```

Restart negaflow after installation. The scanner entry appears under `Library → Scanner`.

## Plugin Protocol

The executable is called with subcommands and writes JSON to stdout.

| Command | Input | stdout |
| --- | --- | --- |
| `detect` | none | `{"devices":[{ id, displayName, vendor, model, connectionType, verifiedStatus, ... }]}` |
| `capabilities <deviceId>` | none | `{ "resolutionsDPI":[...], "modes":[...], "bitDepths":[...], "supportsInfrared":... }` |
| `scan` | options JSON on stdin | progress NDJSON, then `{"type":"result","width":...,"height":...,"path":...}` |

Example `scan` options:

```json
{ "deviceID": "sane-genesys:libusb:001:002", "resolutionDPI": 3600, "bitDepth": 16,
  "colorMode": "color", "filmType": "colorNegative", "preview": false,
  "multiExposure": false, "outputPath": "/tmp/scan.tiff" }
```

Manual verification:

```sh
swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

## Layout

```text
Sources/
  SANEPluginCore/          # SANE backend, model types, TIFF loader
    SANEBackend*.swift
    SaneConfigTuner.swift
    ScannerModel.swift
    TIFFLoader.swift
  negaflow-scanner-sane/   # Thin JSON/CLI adapter
    main.swift
    WireProtocol.swift
Tests/SANEPluginCoreTests/
```

## License

GPL-2.0-or-later. Distribution includes `LICENSE` and the GNU GPL v2 text in `COPYING`.
