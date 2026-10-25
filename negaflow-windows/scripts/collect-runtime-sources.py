#!/usr/bin/env python3
"""Collect actual sources and notices for the DLLs in a Windows SANE payload.

The tab-separated inventory contains package name, package base and installed
version. make-payload.sh reads these from the local pacman database. The binary
packages are used only to verify DLL ownership and recover original notices;
they are never executed or included in the source distribution.
"""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
from urllib.request import urlopen


REPOSITORY = "https://repo.msys2.org/mingw"
SANE_FILES = {"scanimage.exe", "libsane-1.dll"} | {
    "cygsane-" + backend + "-1.dll"
    for backend in ("genesys", "epson2", "epsonds", "coolscan2", "coolscan3")
}


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def fetch(url, cache):
    destination = cache / url.rsplit("/", 1)[1]
    if not destination.is_file():
        temporary = destination.with_name(destination.name + ".part")
        with urlopen(url, timeout=120) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)
        temporary.replace(destination)
    return destination


def readable_archive(archive):
    if archive.suffix != ".zst":
        return archive
    # Finish decompression before tar reads members. Some bsdtar versions stop
    # reading at the tar terminator and report a broken pipe from the decoder.
    unpacked = archive.with_suffix("")
    if not unpacked.is_file():
        temporary = unpacked.with_name(unpacked.name + ".part")
        with temporary.open("wb") as output:
            subprocess.run(["zstd", "-dc", str(archive)], stdout=output, check=True)
        temporary.replace(unpacked)
    return unpacked


def members(archive):
    return subprocess.check_output(["tar", "-tf", str(readable_archive(archive))], text=True).splitlines()


def read_member(archive, member):
    # tarfile follows archive hard links, including libpng's ABI DLL name.
    import tarfile
    with tarfile.open(readable_archive(archive)) as package:
        return package.extractfile(member).read()


def collect(payload, inventory, cache, recipe_directory, plugin_sources, vcpkg_status=None,
            installer_version=None):
    runtime = payload / "sane" / "bin"
    source = payload / "source"
    archives = source / "msys2"
    notices = payload / "LICENSES" / "runtime"
    for directory in (cache, archives, notices):
        directory.mkdir(parents=True, exist_ok=True)

    plugin_manifest = json.loads((plugin_sources / "sources.json").read_text(encoding="utf-8"))
    provided = {package["name"]: package for package in plugin_manifest["packages"]}
    if not {"tiff", "zlib", "rapidjson"}.issubset(provided):
        raise ValueError("Plugin dependency sources are incomplete")
    if vcpkg_status is not None:
        installed = set()
        for paragraph in vcpkg_status.read_text(encoding="utf-8").split("\n\n"):
            fields = dict(line.split(": ", 1) for line in paragraph.splitlines() if ": " in line)
            if fields.get("Architecture") != "x64-windows-static" or "Version" not in fields:
                continue
            name = fields["Package"]
            if name.startswith("vcpkg-"):
                continue
            installed.add(name)
            expected = provided.get(name, {})
            if (expected.get("version") != fields["Version"]
                    or expected.get("port_version", 0) != int(fields.get("Port-Version", "0"))):
                raise ValueError("Plugin dependency source version differs from installed vcpkg package: " + name)
        if not {"tiff", "zlib", "rapidjson"}.issubset(installed):
            raise ValueError("vcpkg status does not describe the plugin's static dependencies")
    files = plugin_manifest.get("files_sha256", {})
    if not files:
        raise ValueError("Plugin dependency manifest has no file checksums")
    for name, expected in files.items():
        relative = PurePosixPath(name)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("Unsafe plugin dependency path: " + name)
        if digest(plugin_sources.joinpath(*relative.parts)) != expected:
            raise ValueError("Plugin dependency source checksum mismatch: " + name)
    for package in provided.values():
        archive = plugin_sources / package["source_path"]
        if package["source_path"] not in files:
            raise ValueError("Plugin dependency source is not covered by checksums: " + package["name"])
        if hashlib.sha512(archive.read_bytes()).hexdigest() != package["sha512"]:
            raise ValueError("Plugin dependency upstream checksum mismatch: " + package["name"])
        license_directory = payload / "LICENSES" / "plugin-dependencies" / package["name"]
        license_directory.mkdir(parents=True, exist_ok=True)
        for member in package["license_members"]:
            (license_directory / PurePosixPath(member).name).write_bytes(read_member(archive, member))
    installer = plugin_manifest.get("installer")
    if installer_version is not None and (not installer or installer["version"] != installer_version.strip().lstrip("v")):
        raise ValueError("NSIS source version differs from the installer compiler")
    if installer:
        if installer["source_path"] not in files:
            raise ValueError("NSIS source is not covered by checksums")
        installer_license = payload / "LICENSES" / "NSIS-COPYING.txt"
        installer_license.write_bytes(read_member(plugin_sources / installer["source_path"], installer["license_member"]))
    destination = source / "plugin-dependencies"
    if plugin_sources.resolve() != destination.resolve():
        destination.mkdir(parents=True, exist_ok=True)
        for name in files:
            output = destination / name
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(plugin_sources / name, output)
        shutil.copyfile(plugin_sources / "sources.json", destination / "sources.json")

    binaries = {path.name: path for path in runtime.iterdir()
                if path.suffix.lower() in (".dll", ".exe")}
    missing_sane = SANE_FILES - binaries.keys()
    if missing_sane:
        raise ValueError("SANE payload is incomplete: " + ", ".join(sorted(missing_sane)))
    uncovered = set(binaries) - SANE_FILES
    packages = []
    seen = set()
    for line in inventory.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        name, base, version = line.split("\t")
        if not all(re.fullmatch(r"[A-Za-z0-9_.+~:-]+", value)
                   for value in (name, base, version)):
            raise ValueError("Invalid package inventory line: " + line)
        if name in seen:
            raise ValueError("Duplicate package: " + name)
        seen.add(name)
        binary_url = REPOSITORY + "/ucrt64/" + name + "-" + version + "-any.pkg.tar.zst"
        binary = fetch(binary_url, cache)
        names = members(binary)
        info = read_member(binary, ".PKGINFO").decode("utf-8")
        for key, value in (("pkgname", name), ("pkgbase", base), ("pkgver", version)):
            if key + " = " + value not in info.splitlines():
                raise ValueError("Package metadata mismatch: " + name + "/" + key)
        matched = []
        for member in names:
            relative = PurePosixPath(member)
            if relative.parent != PurePosixPath("ucrt64/bin") or relative.name not in uncovered:
                continue
            contents = read_member(binary, member)
            if hashlib.sha256(contents).hexdigest() != digest(binaries[relative.name]):
                raise ValueError("Installed DLL differs from its package: " + relative.name)
            matched.append(relative.name)
        if not matched:
            raise ValueError("Package owns no remaining payload DLLs: " + name)
        uncovered.difference_update(matched)

        source_url = REPOSITORY + "/sources/" + base + "-" + version + ".src.tar.zst"
        archive = fetch(source_url, cache)
        source_members = members(archive)
        if base + "/PKGBUILD" not in source_members:
            raise ValueError("Source package has no build recipe: " + archive.name)
        source_info = read_member(archive, base + "/.SRCINFO").decode("utf-8")
        source_fields = dict(line.strip().split(" = ", 1) for line in source_info.splitlines()
                             if " = " in line and line.strip().split(" = ", 1)[0]
                             in ("pkgbase", "pkgver", "pkgrel"))
        if (source_fields.get("pkgbase") != base
                or source_fields.get("pkgver", "") + "-" + source_fields.get("pkgrel", "") != version):
            raise ValueError("Source package version differs from its binary package: " + name)
        if not any(re.search(r"\.tar\.(gz|xz|bz2)$|/objects/pack/.*\.pack$", item)
                   for item in source_members):
            raise ValueError("Source package has no upstream source: " + archive.name)
        shutil.copyfile(archive, archives / archive.name)

        package_notices = []
        for member in names:
            relative = PurePosixPath(member)
            if not member.startswith("ucrt64/share/licenses/") or member.endswith("/"):
                continue
            if ".." in relative.parts:
                raise ValueError("Unsafe notice path: " + member)
            destination = notices.joinpath(*relative.parts[3:])
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(read_member(binary, member))
            package_notices.append(destination.relative_to(payload).as_posix())
        if not package_notices:
            raise ValueError("Package has no redistributed license text: " + name)
        metadata = archives / (name + ".PKGINFO")
        metadata.write_text(info, encoding="utf-8")
        if ".BUILDINFO" in names:
            metadata.with_suffix(".BUILDINFO").write_bytes(read_member(binary, ".BUILDINFO"))
        packages.append({
            "name": name, "base": base, "version": version,
            "binary_url": binary_url, "binary_sha256": digest(binary),
            "source_url": source_url, "source_sha256": digest(archive),
            "source_path": "msys2/" + archive.name,
            "binaries": sorted(matched), "notices": package_notices,
        })
        print("Collected " + base + " " + version, flush=True)
    if uncovered:
        raise ValueError("Payload binaries lack corresponding sources: " + ", ".join(sorted(uncovered)))

    recipe = (recipe_directory / "PKGBUILD").read_text(encoding="utf-8")
    version = re.search(r"^pkgver=([0-9.]+)$", recipe, re.MULTILINE).group(1)
    expected = re.search(r"sha256sums=\('([a-f0-9]{64})'", recipe).group(1)
    upstream_url = ("https://gitlab.com/sane-project/backends/-/archive/" + version
                    + "/backends-" + version + ".tar.bz2")
    upstream = fetch(upstream_url, cache)
    if digest(upstream) != expected:
        raise ValueError("SANE upstream SHA-256 does not match PKGBUILD")
    sane_source = source / "sane-runtime"
    sane_source.mkdir(exist_ok=True)
    if recipe_directory.resolve() != sane_source.resolve():
        shutil.copytree(recipe_directory, sane_source, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns("src", "pkg", "*.pkg.tar.zst", "*.tar.*"))
    shutil.copyfile(upstream, sane_source / upstream.name)
    shutil.copyfile(Path(__file__), sane_source / "collect-runtime-sources.py")
    manifest = {
        "schema": 1,
        "sane": {"version": version, "source_url": upstream_url,
                 "source_sha256": expected, "binaries": sorted(SANE_FILES)},
        "packages": sorted(packages, key=lambda package: package["name"]),
        "payload_sha256": {name: digest(path) for name, path in sorted(binaries.items())},
    }
    (source / "runtime-sources.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--payload", type=Path, required=True)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--recipe-directory", type=Path, required=True)
    parser.add_argument("--plugin-sources", type=Path, required=True)
    parser.add_argument("--vcpkg-status", type=Path)
    parser.add_argument("--installer-version")
    args = parser.parse_args()
    try:
        collect(args.payload, args.inventory, args.cache, args.recipe_directory,
                args.plugin_sources, args.vcpkg_status, args.installer_version)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print("[collect-runtime-sources] " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
