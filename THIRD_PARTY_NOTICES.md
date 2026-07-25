# Third-party notices

The one-shot installer contains or installs the following independent software.

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
- Homebrew formula: <https://formulae.brew.sh/formula/sane-backends>
- License reported by Homebrew: GPL-2.0-or-later
- Distribution method: downloaded and installed by Homebrew on the user's Mac

The installer does not contain or redistribute a `sane-backends` bottle. The version and dependencies
are resolved by the official Homebrew formula at installation time.

## negaflow-scanner-sane

- Project: <https://github.com/habinsong/negaflow-scanner-sane>
- License: GPL-2.0-or-later

The Swift implementation in this repository was written for this plug-in. It invokes the separately
installed `scanimage` command and does not contain SANE backend source, headers, libraries, or device
tables. See [PROVENANCE.md](PROVENANCE.md) for the source and distribution inventory.

The plug-in's [license notice](LICENSE) and the complete [GNU GPL v2 text](COPYING) are included in
the release ZIP, package, and disk image. The matching complete source archive is published beside
and inside the release ZIP, inside the installable plug-in payload, and at the top level of the disk
image.
