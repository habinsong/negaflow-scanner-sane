#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


# 소스 검사는 macOS 패키지 트리를 훑고, 라이선스·README 는 저장소 루트에 있다.
ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT.parent

# The Windows adapter is first-party C++ written for this project. Native source
# is rejected everywhere else so that a vendored SANE tree still fails the check.
FIRST_PARTY_NATIVE_ROOT = "negaflow-windows"
WINDOWS_USB_BINDING_DESCRIPTORS = frozenset(
    {
        Path("negaflow-windows/tools/usbscan-bind/generate-inf.py"),
        Path("negaflow-windows/tools/usbscan-bind/install.ps1"),
        Path("negaflow-windows/tools/usbscan-bind/negaflow-usbscan.inf"),
    }
)


def fail(message: str) -> None:
    print(f"[provenance] ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def repository_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "-z"],
        cwd=REPO_ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    return [
        REPO_ROOT / entry.decode("utf-8")
        for entry in result.stdout.split(b"\0")
        if entry and (REPO_ROOT / entry.decode("utf-8")).exists()
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
        relative = path.relative_to(REPO_ROOT)
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
        relative = path.relative_to(REPO_ROOT)
        root = relative.parts[0]
        if root == "negaflow-mac" and len(relative.parts) > 1:
            root = relative.parts[1]
        if root not in {"Sources", "Tests", FIRST_PARTY_NATIVE_ROOT}:
            continue
        # 문서는 구현이 아니다. 트리를 분리하며 windows_docs 가 Windows 트리 안으로
        # 들어왔는데, 다른 구현을 설명하는 문장이 이식 흔적으로 잡히면 안 된다.
        if root == FIRST_PARTY_NATIVE_ROOT and relative.parts[1:2] == ("docs",):
            continue
        raw = path.read_bytes()
        # App icons and other resources live beside first-party source. They
        # are not authorship text; decoding them as UTF-8 crashes the gate.
        if b"\0" in raw[:8192]:
            continue
        try:
            text = raw.decode("utf-8").lower()
        except UnicodeDecodeError as exc:
            fail(f"source file is not valid UTF-8: {relative} ({exc})")
        if root == FIRST_PARTY_NATIVE_ROOT:
            for marker in windows_forbidden:
                # The USB binding scripts and generated INF name sanei_usb only
                # in comments explaining why usbscan.sys is required. They neither
                # include nor call a SANE API, so exempt that exact documentation
                # reference without weakening the implementation-marker check.
                if relative in WINDOWS_USB_BINDING_DESCRIPTORS and marker == "sanei_":
                    continue
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
    ):
        if not (REPO_ROOT / required).is_file():
            fail(f"required release notice is missing: {required}")
    if not (ROOT / "manifest.json").is_file():
            fail(f"required release notice is missing: {required}")

    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    # 버전을 여기 글자로 박아 두면 정당한 인상마다 이 검사가 깨진다. 지켜야 할 것은 "어느
    # 숫자냐"가 아니라 **매니페스트와 README 가 같은 숫자를 말한다는 것**이고, 그 대조는
    # 바로 아래에서 한다 - 설치 파일 이름을 이 값에서 만들어 여섯 README 에서 찾는다.
    plugin_version = manifest.get("pluginVersion")
    if not isinstance(plugin_version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", plugin_version):
        fail(f"manifest pluginVersion must be x.y.z, found {plugin_version!r}")

    # 접미사 없는 쪽이 기본 배포본(패치 SANE 동봉, macOS 26+)이고, OpticFilm 전용이
    # 시스템 SANE을 쓰는 macOS 14+ 빌드다.
    standard_installer_names = tuple(
        "negaflow-scanner-sane-"
        f"{manifest['pluginVersion']}-opticfilm-macos14-{architecture}-installer.dmg"
        for architecture in ("arm64", "universal")
    )
    coolscan_installer_names = tuple(
        f"negaflow-scanner-sane-{manifest['pluginVersion']}-macos26-{architecture}-installer.dmg"
        for architecture in ("arm64", "universal")
    )
    # 설치 파일 표는 macOS 문서에 있다. 최상위 README 는 두 플랫폼을 함께 소개하고
    # 자세한 설치는 각 플랫폼 문서로 넘긴다.
    for readme_name in (
        "negaflow-mac/docs/README.md",
        "negaflow-mac/docs/README_ko.md",
        "negaflow-mac/docs/README_ja.md",
        "negaflow-mac/docs/README_zh-Hans.md",
        "negaflow-mac/docs/README_fr.md",
        "negaflow-mac/docs/README_de.md",
    ):
        readme = (REPO_ROOT / readme_name).read_text(encoding="utf-8")
        for installer_name in standard_installer_names + coolscan_installer_names:
            if installer_name not in readme:
                fail(f"{readme_name} does not name the current installer: {installer_name}")

    notices = (REPO_ROOT / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
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
    # 버전은 패치를 하나 더할 때마다 올라간다. 그 숫자를 검사기에 글자로 박아 두면 정당한
    # 인상마다 CI 가 깨진다 - 실제로 formula 가 negaflow.4 로 올라간 뒤 이 줄만 .3 에 남아
    # CI 가 이틀 동안 멈춰 있었다. 지켜야 할 것은 "어느 숫자냐"가 아니라 **negaflow 패치본
    # 이라는 것**과 **그 인상이 기록과 함께 간다는 것**이다. 둘을 맞물려 본다.
    version = re.search(
        r'^\s*version "(1\.4\.0-negaflow\.\d+)"$', formula, re.MULTILINE
    )
    if version is None:
        fail("patched SANE formula must carry a 1.4.0-negaflow.N version")
    else:
        record = (ROOT / "sane-runtime/SOURCES.md").read_text(encoding="utf-8")
        if version.group(1) not in record:
            fail(
                "sane-runtime/SOURCES.md does not record formula version "
                f"{version.group(1)}"
            )

    for marker in (
        "depends_on macos: :tahoe",
        'sha256 "f99205c903dfe2fb8990f0c531232c9a00ec9c2c66ac7cb0ce50b4af9f407a72"',
        "cs2_xmalloc (3 * sizeof (SANE_Word))",
        "cs3_xmalloc(3 *",
        "(SANE_UNFIX(s->val[OPT_BR_Y].w) / MM_PER_INCH *",
        # epson2 적외선: sane.h 가 SANE_FRAME_IR 을 #if 0 으로 막아 두어 IR 모드가 통째로
        # 컴파일에서 빠진다. 그 #ifdef 를 걷어내고 결과를 IR 프레임 타입 대신 GRAY 로
        # 내보내는 두 패치가 살아 있는지 확인한다.
        "-#ifdef SANE_FRAME_IR",
        "-\t\ts->params.format = SANE_FRAME_IR;",
        "+\t\ts->params.format = SANE_FRAME_GRAY;",
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
