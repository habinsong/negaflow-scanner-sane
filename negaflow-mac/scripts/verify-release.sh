#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <release-artifact-directory>" >&2
  exit 2
fi

OUTPUT_DIR="$1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(plutil -extract pluginVersion raw "$ROOT/manifest.json")"
BASE_NAME="negaflow-sane-$VERSION-mac-universal"
ZIP="$OUTPUT_DIR/$BASE_NAME.zip"
DSYM_ZIP="$OUTPUT_DIR/$BASE_NAME.dSYM.zip"
SOURCE_NAME="negaflow-sane-$VERSION-source.tar.gz"
SOURCE_ARCHIVE="$OUTPUT_DIR/$SOURCE_NAME"
CHECKSUMS="$OUTPUT_DIR/SHA256SUMS.txt"
for artifact in "$ZIP" "$DSYM_ZIP" "$SOURCE_ARCHIVE" "$CHECKSUMS"; do
  if [ ! -s "$artifact" ]; then
    echo "[verify-release] ERROR: artifact가 없습니다: $artifact" >&2
    exit 1
  fi
done

(
  cd "$OUTPUT_DIR"
  shasum -a 256 -c "${CHECKSUMS##*/}"
)

TEMPORARY="$(mktemp -d /tmp/negaflow-sane-verify.XXXXXX)"
trap 'rm -rf "$TEMPORARY"' EXIT
ditto -x -k "$ZIP" "$TEMPORARY/release"
ditto -x -k "$DSYM_ZIP" "$TEMPORARY/dsym"
RELEASE_ROOT="$TEMPORARY/release/negaflow-scanner-sane-$VERSION"
PLUGIN="$RELEASE_ROOT/sane"
EXECUTABLE="$PLUGIN/negaflow-scanner-sane"
MANIFEST="$PLUGIN/manifest.json"
PACKAGED_SOURCE="$PLUGIN/$SOURCE_NAME"

test -x "$EXECUTABLE"
test -s "$PLUGIN/LICENSE"
test -s "$PLUGIN/COPYING"
test -s "$PLUGIN/THIRD_PARTY_NOTICES.md"
test -s "$PLUGIN/PROVENANCE.md"
test -s "$PACKAGED_SOURCE"
for readme in README.md README_ko.md README_ja.md README_zh-Hans.md README_fr.md README_de.md; do
  test -s "$PLUGIN/$readme"
done
test -x "$RELEASE_ROOT/install.sh"
bash -n "$RELEASE_ROOT/install.sh"
if find "$RELEASE_ROOT" -path '*/Formula/sane-backends-negaflow.rb' -print -quit | grep -q .; then
  echo "[verify-release] ERROR: standard ZIP contains the Coolscan Formula installer." >&2
  exit 1
fi
[ "$(plutil -extract schemaVersion raw "$MANIFEST")" = "1" ]
[ "$(plutil -extract protocolVersion raw "$MANIFEST")" = "2" ]
[ "$(plutil -extract id raw "$MANIFEST")" = "sane" ]
[ "$(plutil -extract pluginVersion raw "$MANIFEST")" = "$VERSION" ]
[ "$(shasum -a 256 "$PACKAGED_SOURCE" | awk '{print $1}')" \
  = "$(shasum -a 256 "$SOURCE_ARCHIVE" | awk '{print $1}')" ]
tar -tzf "$SOURCE_ARCHIVE" \
  | grep -Eq "^negaflow-scanner-sane-$VERSION/Package.swift$"
tar -tzf "$SOURCE_ARCHIVE" \
  | grep -Eq "^negaflow-scanner-sane-$VERSION/Sources/SANEPluginCore/"
codesign --verify --strict --verbose=2 "$EXECUTABLE"

architectures="$(lipo -archs "$EXECUTABLE")"
grep -qw arm64 <<< "$architectures"
grep -qw x86_64 <<< "$architectures"
executable_uuids="$(dwarfdump --uuid "$EXECUTABLE" | awk '{print $2}' | sort)"
dsym_bundle="$(find "$TEMPORARY/dsym" -type d -name '*.dSYM' -print -quit)"
dsym_uuids="$(dwarfdump --uuid "$dsym_bundle" | awk '{print $2}' | sort)"
[ -n "$executable_uuids" ]
[ "$executable_uuids" = "$dsym_uuids" ]

NEGAFLOW_PLUGINS_DIR="$TEMPORARY/installed" \
  bash "$RELEASE_ROOT/install.sh" >/dev/null
INSTALLED="$TEMPORARY/installed/sane/negaflow-scanner-sane"
test -x "$INSTALLED"
test -s "$TEMPORARY/installed/sane/$SOURCE_NAME"
[ "$(shasum -a 256 "$EXECUTABLE" | awk '{print $1}')" \
  = "$(shasum -a 256 "$INSTALLED" | awk '{print $1}')" ]

echo "[verify-release] valid: version=$VERSION architectures=$architectures"
