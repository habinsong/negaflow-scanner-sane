#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

# The Windows adapter is first-party C++ written for this project. Native source
# is rejected everywhere else so that a vendored SANE tree still fails the check.
FIRST_PARTY_NATIVE_ROOT = "windows"


def fail(message: str) -> None:
    print(f"[provenance] ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def repository_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "-z"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    return [
        ROOT / entry.decode("utf-8")
        for entry in result.stdout.split(b"\0")
        if entry and (ROOT / entry.decode("utf-8")).exists()
    ]


def verify_tree(files: list[Path]) -> tuple[int, int]:
    native_suffixes = {".c", ".cc", ".cpp", ".h", ".hpp", ".m", ".mm"}
    archive_suffixes = {
        ".a", ".dylib", ".so", ".framework", ".xcframework",
        ".zip", ".tar", ".gz", ".dmg", ".pkg",
    }
    vendor_names = {"vendor", "vendors", "third_party", "third-party"}
    binary_count = 0
    text_count = 0
    for path in files:
        relative = path.relative_to(ROOT)
        if path.suffix.lower() in native_suffixes:
            if relative.parts[0] != FIRST_PARTY_NATIVE_ROOT:
                fail(f"vendored native source is not allowed: {relative}")
        if any(part.lower() in vendor_names for part in relative.parts):
            fail(f"vendored directory is not allowed: {relative}")
        if path.suffix.lower() in archive_suffixes:
            fail(f"prebuilt library or archive is not allowed: {relative}")
        data = path.read_bytes()
        if b"\0" in data[:8192]:
            binary_count += 1
        else:
            text_count += 1

    package = (ROOT / "Package.swift").read_text(encoding="utf-8")
    for marker in (
        ".package(",
        ".binaryTarget(",
        ".systemLibrary(",
        '.linkedLibrary("sane")',
    ):
        if marker in package:
            fail(f"Package.swift links or downloads an external package: {marker}")
    return text_count, binary_count


def verify_source_authorship_markers(files: list[Path]) -> None:
    forbidden = (
        "sanei_",
        "#include <sane/",
        "#include \"sane/",
        "dlopen(",
        "dlsym(",
        "darktable",
        "rawtherapee",
        "negadoctor",
    )
    # The adapter's own module directory is `windows/src/sane/`, so a quoted
    # `sane/` include there is first-party and says nothing about SANE linkage.
    # Calls into the SANE C API do, so they are named directly instead.
    windows_forbidden = (
        "sanei_",
        "#include <sane/",
        "sane_init(",
        "sane_open(",
        "sane_start(",
        "sane_control_option(",
        "sane_handle",
        "dlopen(",
        "dlsym(",
        "darktable",
        "rawtherapee",
        "negadoctor",
    )
    own_license = "spdx-license-identifier: gpl-2.0-or-later"
    for path in files:
        relative = path.relative_to(ROOT)
        root = relative.parts[0]
        if root not in {"Sources", "Tests", FIRST_PARTY_NATIVE_ROOT}:
            continue
        text = path.read_text(encoding="utf-8").lower()
        if root == FIRST_PARTY_NATIVE_ROOT:
            for marker in windows_forbidden:
                if marker in text:
                    fail(f"foreign implementation marker {marker!r} found in {relative}")
            # The adapter carries the project's own GPL tag. Any other license
            # tag, or a copyright line, means source arrived from elsewhere.
            if text.replace(own_license, "").find("spdx-license-identifier") != -1:
                fail(f"unexpected third-party license tag in {relative}")
            if "copyright (c)" in text:
                fail(f"unexpected third-party source header in {relative}")
            continue
        for marker in forbidden:
            if marker in text:
                fail(f"foreign implementation marker {marker!r} found in {relative}")
        if "spdx-license-identifier" in text or "copyright (c)" in text:
            fail(f"unexpected third-party source header in {relative}")


def verify_distribution_policy() -> None:
    for required in (
        "LICENSE",
        "COPYING",
        "THIRD_PARTY_NOTICES.md",
        "PROVENANCE.md",
        "manifest.json",
    ):
        if not (ROOT / required).is_file():
            fail(f"required release notice is missing: {required}")

    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("pluginVersion") != "1.0.3":
        fail("manifest pluginVersion must be 1.0.3")

    standard_installer_names = tuple(
        f"negaflow-scanner-sane-{manifest['pluginVersion']}-macos-{architecture}-installer.dmg"
        for architecture in ("arm64", "universal")
    )
    coolscan_installer_names = tuple(
        "negaflow-scanner-sane-"
        f"{manifest['pluginVersion']}-coolscan-macos26-{architecture}-installer.dmg"
        for architecture in ("arm64", "universal")
    )
    for readme_name in (
        "README.md",
        "README_ko.md",
        "README_ja.md",
        "README_zh-Hans.md",
        "README_fr.md",
        "README_de.md",
    ):
        readme = (ROOT / readme_name).read_text(encoding="utf-8")
        for installer_name in standard_installer_names + coolscan_installer_names:
            if installer_name not in readme:
                fail(f"{readme_name} does not name the current installer: {installer_name}")

    notices = (ROOT / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
    for marker in (
        "Homebrew 6.0.11",
        "0545b1b85053ad6292799e8f9b11caee373cb377364f4d293cc4711487a9b944",
        "BSD 2-Clause",
        "does not contain or redistribute a `sane-backends` bottle",
        "f99205c903dfe2fb8990f0c531232c9a00ec9c2c66ac7cb0ce50b4af9f407a72",
        "9bea1ee256c744098576acee98053e094b4a14a2",
    ):
        if marker not in notices:
            fail(f"third-party notice is incomplete: {marker}")

    release_text = "\n".join(
        (ROOT / relative).read_text(encoding="utf-8").lower()
        for relative in (
            "scripts/package-release.sh",
            "scripts/build-installer.sh",
        )
    )
    for marker in (
        'cp "$root/scanimage"',
        "libsane.dylib",
        "sane-backends.bottle",
    ):
        if marker in release_text:
            fail(f"release scripts bundle a SANE runtime: {marker}")

    formula = (ROOT / "Formula/sane-backends-negaflow.rb").read_text(encoding="utf-8")
    for marker in (
        'version "1.4.0-negaflow.2"',
        "depends_on macos: :tahoe",
        'sha256 "f99205c903dfe2fb8990f0c531232c9a00ec9c2c66ac7cb0ce50b4af9f407a72"',
        "cs2_xmalloc (3 * sizeof (SANE_Word))",
        "cs3_xmalloc(3 *",
        "(SANE_UNFIX(s->val[OPT_BR_Y].w) / MM_PER_INCH *",
    ):
        if marker not in formula:
            fail(f"patched SANE formula is incomplete: {marker}")


def main() -> None:
    files = repository_files()
    text_count, binary_count = verify_tree(files)
    verify_source_authorship_markers(files)
    verify_distribution_policy()
    print(
        "[provenance] verified "
        f"files={len(files)} text={text_count} binary={binary_count}"
    )


if __name__ == "__main__":
    main()
