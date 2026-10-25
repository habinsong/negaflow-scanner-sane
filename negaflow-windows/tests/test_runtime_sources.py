import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/collect-runtime-sources.py"
SPEC = importlib.util.spec_from_file_location("runtime_sources", SCRIPT)
collector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(collector)


def archive(path, files):
    with tarfile.open(path, "w:gz") as output:
        for name, contents in files.items():
            member = tarfile.TarInfo(name)
            member.size = len(contents)
            output.addfile(member, io.BytesIO(contents))


class RuntimeSourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.payload = self.root / "payload"
        self.runtime = self.payload / "sane/bin"
        self.runtime.mkdir(parents=True)
        for name in collector.SANE_FILES:
            (self.runtime / name).write_bytes(b"local SANE binary")
        (self.runtime / "dependency.dll").write_bytes(b"original DLL")
        self.inventory = self.root / "packages.tsv"
        self.inventory.write_text("mingw-w64-ucrt-x86_64-example\tmingw-w64-example\t1.0-1\n")
        self.binary = self.root / "binary.tar.gz"
        archive(self.binary, {
            ".PKGINFO": b"pkgname = mingw-w64-ucrt-x86_64-example\npkgbase = mingw-w64-example\npkgver = 1.0-1\n",
            "ucrt64/bin/dependency.dll": b"original DLL",
            "ucrt64/share/licenses/example/COPYING": b"Original license text\n",
        })
        self.sources = self.root / "sources.tar.gz"
        self.source_files = {
            "mingw-w64-example/PKGBUILD": b"build() { make; }\n",
            "mingw-w64-example/.SRCINFO": b"pkgbase = mingw-w64-example\n\tpkgver = 1.0\n\tpkgrel = 1\n",
            "mingw-w64-example/upstream.tar.gz": b"upstream source archive",
        }
        archive(self.sources, self.source_files)
        self.upstream = self.root / "backends-1.4.0.tar.bz2"
        self.upstream.write_bytes(b"SANE source archive")
        self.recipe = self.root / "recipe"
        self.recipe.mkdir()
        self.sane_hash = collector.digest(self.upstream)
        (self.recipe / "PKGBUILD").write_text(
            "pkgver=1.4.0\nsha256sums=('" + self.sane_hash + "')\n")
        self.plugin = self.root / "plugin-sources"
        self.plugin.mkdir()
        records = []
        for name in ("tiff", "zlib", "rapidjson"):
            source = self.plugin / (name + ".tar.gz")
            archive(source, {name + "/LICENSE": b"original license", name + "/source.c": b"source"})
            records.append({"name": name, "version": "1.0", "source_path": source.name,
                            "sha512": hashlib.sha512(source.read_bytes()).hexdigest(),
                            "license_members": [name + "/LICENSE"]})
        manifest = {"packages": records,
                    "files_sha256": {record["source_path"]: collector.digest(self.plugin / record["source_path"])
                                     for record in records}}
        (self.plugin / "sources.json").write_text(json.dumps(manifest))

    def collect(self, status=None):
        def fetch(url, cache):
            if "pkg.tar.zst" in url:
                return self.binary
            if "src.tar.zst" in url:
                return self.sources
            return self.upstream
        with patch.object(collector, "fetch", side_effect=fetch):
            return collector.collect(self.payload, self.inventory, self.root / "cache",
                                     self.recipe, self.plugin, status)

    def test_collects_source_archives_original_notices_and_binary_mapping(self):
        result = self.collect()
        self.assertEqual(result["packages"][0]["binaries"], ["dependency.dll"])
        self.assertEqual((self.payload / "source/msys2/sources.tar.gz").read_bytes(), self.sources.read_bytes())
        self.assertEqual((self.payload / "LICENSES/runtime/example/COPYING").read_bytes(), b"Original license text\n")
        self.assertEqual(collector.digest(self.payload / "source/sane-runtime/backends-1.4.0.tar.bz2"), self.sane_hash)
        self.assertTrue((self.payload / "LICENSES/plugin-dependencies/tiff/LICENSE").is_file())

    def test_rejects_dll_that_differs_from_the_recorded_package(self):
        (self.runtime / "dependency.dll").write_bytes(b"different DLL")
        with self.assertRaisesRegex(ValueError, "Installed DLL differs"):
            self.collect()

    def test_rejects_runtime_dll_with_no_source_package(self):
        (self.runtime / "unlisted.dll").write_bytes(b"another DLL")
        with self.assertRaisesRegex(ValueError, "lack corresponding sources.*unlisted"):
            self.collect()

    def test_rejects_recipe_without_actual_upstream_source(self):
        del self.source_files["mingw-w64-example/upstream.tar.gz"]
        archive(self.sources, self.source_files)
        with self.assertRaisesRegex(ValueError, "no upstream source"):
            self.collect()

    def test_rejects_static_sources_for_another_installed_version(self):
        status = self.root / "vcpkg-status"
        status.write_text("Package: tiff\nArchitecture: x64-windows-static\nVersion: 2.0\n")
        with self.assertRaisesRegex(ValueError, "version differs.*tiff"):
            self.collect(status)

    def test_rejects_modified_static_source_archive(self):
        (self.plugin / "tiff.tar.gz").write_bytes(b"modified source")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            self.collect()


if __name__ == "__main__":
    unittest.main()
