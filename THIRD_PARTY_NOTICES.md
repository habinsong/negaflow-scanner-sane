# Third-party notices

The standard and Coolscan installers contain or install the following
independent software.

## Homebrew 6.0.11

- Project: <https://github.com/Homebrew/brew>
- Installer source: <https://github.com/Homebrew/brew/releases/tag/6.0.11>
- Included file: the Homebrew component extracted from the official `Homebrew.pkg` after
  verification, without altering its payload or installer scripts
- Upstream SHA-256: `0545b1b85053ad6292799e8f9b11caee373cb377364f4d293cc4711487a9b944`
- Upstream installer signature: `Developer ID Installer: Patrick Linnane (927JGANW46)`
- License: BSD 2-Clause

```text
BSD 2-Clause License

Copyright (c) 2009-present, Homebrew contributors
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## SANE backends

- Project: <https://www.sane-project.org/>
- Upstream source:
  <https://gitlab.com/-/project/429008/uploads/843c156420e211859e974f78f64c3ea3/sane-backends-1.4.0.tar.gz>
- Upstream version: 1.4.0
- Upstream SHA-256: `f99205c903dfe2fb8990f0c531232c9a00ec9c2c66ac7cb0ce50b4af9f407a72`
- License: GPL-2.0-or-later
- Upstream fix: <https://gitlab.com/sane-project/backends/-/commit/9bea1ee256c744098576acee98053e094b4a14a2>
- Distribution method: the standard installer asks Homebrew for stock `sane-backends`; the
  Coolscan installer downloads the pinned upstream source and builds it on the user's Mac using
  `Formula/sane-backends-negaflow.rb`

The installer distribution does not contain or redistribute a `sane-backends` bottle or SANE runtime binary.
The Coolscan installer's GPL source payload contains a Homebrew formula with the upstream two-line
`coolscan2`/`coolscan3` word-list allocation fix. Homebrew verifies the pinned source SHA-256,
applies that patch, and builds the separate `sane-backends-negaflow` keg locally.

### Windows redistributes the runtime, macOS does not

The sentence above describes macOS only. **The Windows plugin ships a built SANE
runtime** — there is no Homebrew to build it on the user's machine — so the
obligations are different and stronger.

- Upstream source: `backends-1.4.0.tar.bz2` from
  <https://gitlab.com/sane-project/backends/-/archive/1.4.0/backends-1.4.0.tar.bz2>
- Upstream SHA-256: `813ef8818a498cbb11615f657cd6dc66536ef34df4a557d9cd63086622f6123d`
- License: GPL-2.0-or-later (with the SANE exception)
- Modifications: eight patches, all in [`sane-runtime/patches/`](sane-runtime/patches/),
  described in [`sane-runtime/SOURCES.md`](sane-runtime/SOURCES.md)
- Build recipe: [`sane-runtime/PKGBUILD`](sane-runtime/PKGBUILD), based on the
  MSYS2 `mingw-w64-sane` package
- Backends built: `genesys epson2 epsonds coolscan2 coolscan3 test`

`001-fix-build-on-mingw.patch` is taken unchanged from MSYS2's
`mingw-w64-sane` package (GPL-2.0-or-later, same licence as the work it patches):
<https://github.com/msys2/MINGW-packages/tree/master/mingw-w64-sane>

The other seven are written for this project.

**Because a Windows release distributes GPL binaries, it must carry the
corresponding source.** The recipe above plus the pinned tarball hash reproduces
the exact runtime; ship that source alongside, or a written offer for it. The
plugin's own source is this repository, which is GPL-2.0-or-later.

The runtime links libusb-1.0 (LGPL-2.1-or-later) dynamically, so the user can
substitute their own build. See
[`negaflow-windows/docs/07-distribution/gpl-compliance.md`](negaflow-windows/docs/07-distribution/gpl-compliance.md).

### The Windows installer carries NSIS

The single-file installer is built with NSIS, so the shipped
`negaflow-scanner-sane-<version>-x64-setup.exe` contains NSIS stub code.

- Project: <https://nsis.sourceforge.io/>
- Licence: zlib/libpng licence, with the exception that the Common Public
  Licence covers some plug-ins (none of which this installer uses)
- Version: whatever `mingw-w64-ucrt-x86_64-nsis` provides in the build
  environment; the tested build is 3.12
- Installer script: [`Installer/windows/negaflow-scanner-sane.nsi`](negaflow-mac/Installer/windows/negaflow-scanner-sane.nsi)

The GPL binaries sit inside that executable as data and are extracted unchanged.
That is aggregation, not a combined work, so the NSIS stub's licence and the
payload's GPL do not interact.

## negaflow-scanner-sane

- Project: <https://github.com/habinsong/negaflow-scanner-sane>
- License: GPL-2.0-or-later

The Swift implementation in this repository was written for this plug-in. It invokes the separately
installed `scanimage` command and does not link SANE headers or libraries. See
[PROVENANCE.md](PROVENANCE.md) for the source and distribution inventory.

The plug-in's [license notice](LICENSE) and the complete [GNU GPL v2 text](COPYING) are included in
the release ZIP, package, and disk image. The matching complete source archive is published beside
and inside the release ZIP, inside the installable plug-in payload, and at the top level of the disk
image.
