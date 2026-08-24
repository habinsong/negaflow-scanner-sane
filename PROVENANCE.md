# Code and distribution provenance

Last updated: 2026-08-25

This file records the source and release boundary of `negaflow-scanner-sane`.
It is an auditable project record, not a legal opinion.

## Project code

The Swift, shell, and test code in this repository is distributed under
GPL-2.0-or-later. The scanner protocol model shapes and the small TIFF helper
were adapted by the same author from that author's negaflow ScannerKit and
Chromabase contracts so that the two independently built programs can exchange
the same JSON and TIFF files. They contain no SANE implementation.

The Swift package does not compile or link SANE headers or libraries. It
launches the separately installed `scanimage` executable and parses its
documented command output. The standard installer asks Homebrew for stock
`sane-backends`. The separate macOS 26 Coolscan installer includes a Homebrew
formula that downloads SANE 1.4.0 and applies the upstream `coolscan2`/`coolscan3`
word-list allocation fix before building SANE as a separate keg.

SANE option names, device identifiers, USB identifiers, and values returned by
`scanimage -L` or `scanimage -A` are interoperability facts. The plug-in keeps
the complete reported device identifier and builds arguments only from options
reported by that device. Device behavior is not inferred by copying a SANE
backend implementation.

The `windows/` directory holds the Windows adapter, written for this project in
C++ by the same author and distributed under the same GPL-2.0-or-later terms.
It is a port of the Swift adapter's own logic, checked against the Swift
implementation by the parity harness in `windows/tools/`. Like the Swift
package it compiles and links no SANE headers or libraries; it launches
`scanimage` and parses its documented command output. Its only third-party
build dependencies are libtiff and RapidJSON, resolved from vcpkg at build
time and not vendored into this tree.

Outside `windows/`, the source tree contains no C, C++, or Objective-C. Nowhere
in the tree is there a vendored native dependency, a vendored SANE tree, or a
prebuilt SANE binary. Release verification rejects those additions. The patches
embedded in the Homebrew formula are GPL-2.0-or-later and are distributed as
source with the plug-in — coolscan2/coolscan3 word-list, epson2 scan-height and
infrared frame, and the genesys OpticFilm host-side Gray fixes.

## SANE and negaflow boundary

SANE is installed independently. The standard macOS 14 installer uses
Homebrew's stock `sane-backends`; the separate macOS 26 Coolscan installer uses
the keg-only `sane-backends-negaflow` formula. That formula downloads the pinned
official SANE 1.4.0 source and builds it locally after applying the upstream
two-line Coolscan fix. Neither installer contains a SANE bottle or runtime
binary. The plug-in and SANE remain separately replaceable command-line
programs.

negaflow and this plug-in exchange a versioned JSON/NDJSON protocol through a
separate process. negaflow does not link this plug-in or include it in the
negaflow application bundle. These are architectural facts; whether a
particular distribution is an aggregate or a derivative work must be assessed
from the actual code, communication semantics, and files distributed.

### Windows

The same boundary holds, with one difference that matters for licensing:
**the Windows plug-in ships a built SANE runtime.** There is no Homebrew to
build it on the user's machine, so the plug-in distribution contains GPL
binaries and must carry the corresponding source.

- Recipe and patches: [`sane-runtime/`](sane-runtime/) —
  `PKGBUILD`, eleven patches, and `SOURCES.md` describing each one
- The pinned tarball hash plus that recipe reproduces the exact runtime

The chain stays process-separated at every link:

```text
negaflow (Apache-2.0)
    │  versioned JSON/NDJSON over stdio, separate process
negaflow-scanner-sane.exe (GPL-2.0-or-later)
    │  command line + stdout, separate process
scanimage.exe (GPL-2.0-or-later)
```

The adapter does not link `libsane`. It runs `scanimage` and parses its
output — the same relationship the macOS plug-in has. The Windows adapter's
own sources live in `windows/` and carry this project's GPL tag;
`scripts/verify-provenance.py` fails the build if any third-party licence tag
or copyright line appears there.

- SANE source: <https://gitlab.com/sane-project/backends>
- GNU license FAQ: <https://www.gnu.org/licenses/gpl-faq.html.en>
- Apache/GPL compatibility: <https://www.apache.org/licenses/GPL-compatibility>

## One-shot installer

The installer includes an unmodified component extracted from the pinned,
official Homebrew installer after checking its SHA-256, Apple Developer ID
Installer signature, Team ID, and notarization status. Homebrew is BSD
2-Clause licensed; the complete notice is in `THIRD_PARTY_NOTICES.md`.

The standard installer asks Homebrew to install stock `sane-backends`. The
Coolscan installer asks Homebrew to build and install
`sane-backends-negaflow` on the user's Mac. Both plug-in packages include:

- `LICENSE` and the complete GPL v2 text in `COPYING`;
- `THIRD_PARTY_NOTICES.md`;
- this provenance record;
- the matching complete plug-in source archive.

The Coolscan package additionally includes
`Formula/sane-backends-negaflow.rb`, including the upstream Coolscan fix.
The standalone release publishes the same source archive beside the binary
ZIP and embeds it in the ZIP. Release verification compares both copies and
checks the source tree needed to rebuild the plug-in.

`scripts/verify-installer.sh` expands the PKG and mounts the DMG read-only to
check those files and compare the packaged source archive.

## Automated check

Run:

```bash
python3 scripts/verify-provenance.py
```

The check inventories every tracked or release-candidate file, rejects vendored
native code and SANE linkage, checks the pinned Homebrew and SANE notices and
installer policy, and confirms that release scripts do not copy `scanimage` or
a SANE library. It cannot prove similarity against every program on the
internet or replace a rights review when new code, assets, or dependencies are
introduced.
