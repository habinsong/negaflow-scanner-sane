# Code and distribution provenance

This file records the source and release boundary of `negaflow-scanner-sane`.
It is an auditable project record, not a legal opinion.

## Project code

The Swift, shell, and test code in this repository is distributed under
GPL-2.0-or-later. The scanner protocol model shapes and the small TIFF helper
were adapted by the same author from that author's negaflow ScannerKit and
Chromabase contracts so that the two independently built programs can exchange
the same JSON and TIFF files. They contain no SANE implementation.

The package does not compile, link, or vendor SANE headers, libraries, backend
source, or device tables. It launches the separately installed `scanimage`
executable and parses its documented command output.

SANE option names, device identifiers, USB identifiers, and values returned by
`scanimage -L` or `scanimage -A` are interoperability facts. The plug-in keeps
the complete reported device identifier and builds arguments only from options
reported by that device. Device behavior is not inferred by copying a SANE
backend implementation.

The source tree contains no C, C++, Objective-C, third-party package dependency,
vendored source tree, or prebuilt SANE binary. Release verification rejects
those additions.

## SANE and negaflow boundary

SANE is installed independently through the official Homebrew
`sane-backends` formula. This repository's one-shot installer does not contain
a SANE bottle. The plug-in and SANE remain separately replaceable command-line
programs.

negaflow and this plug-in exchange a versioned JSON/NDJSON protocol through a
separate process. negaflow does not link this plug-in or include it in the
negaflow application bundle. These are architectural facts; whether a
particular distribution is an aggregate or a derivative work must be assessed
from the actual code, communication semantics, and files distributed.

- SANE source: <https://gitlab.com/sane-project/backends>
- GNU license FAQ: <https://www.gnu.org/licenses/gpl-faq.en.html>
- Apache/GPL compatibility: <https://www.apache.org/licenses/GPL-compatibility>

## One-shot installer

The installer includes an unmodified component extracted from the pinned,
official Homebrew installer after checking its SHA-256, Apple Developer ID
Installer signature, Team ID, and notarization status. Homebrew is BSD
2-Clause licensed; the complete notice is in `THIRD_PARTY_NOTICES.md`.

The installer then asks Homebrew to download and install `sane-backends` on the
user's Mac. The plug-in package includes:

- `LICENSE` and the complete GPL v2 text in `COPYING`;
- `THIRD_PARTY_NOTICES.md`;
- this provenance record;
- the matching complete plug-in source archive.

The standalone release publishes that same source archive beside the binary
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
native code and SANE linkage, checks the pinned Homebrew notice and installer
policy, and confirms that release scripts do not copy `scanimage` or a SANE
library. It cannot prove similarity against every program on the internet or
replace a rights review when new code, assets, or dependencies are introduced.
