#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 <output-source-archive>" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(plutil -extract pluginVersion raw "$ROOT/manifest.json")"
for command in plutil tar gzip; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "[create-source-archive] ERROR: required command is missing: $command" >&2
    exit 1
  fi
done
OUTPUT_PARENT="$(dirname "$1")"
mkdir -p "$OUTPUT_PARENT"
OUTPUT_ARCHIVE="$(cd "$OUTPUT_PARENT" && pwd)/$(basename "$1")"
WORK="$(mktemp -d /tmp/negaflow-sane-source.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

SOURCE_ROOT="$WORK/negaflow-scanner-sane-$VERSION"
mkdir -p "$SOURCE_ROOT"
cp -pR \
  "$ROOT/.github" \
  "$ROOT/Config" \
  "$ROOT/Installer" \
  "$ROOT/Sources" \
  "$ROOT/Tests" \
  "$ROOT/scripts" \
  "$SOURCE_ROOT/"
cp -p \
  "$ROOT/Package.swift" \
  "$ROOT/manifest.json" \
  "$ROOT/install.sh" \
  "$ROOT/LICENSE" \
  "$ROOT/COPYING" \
  "$ROOT/THIRD_PARTY_NOTICES.md" \
  "$ROOT/PROVENANCE.md" \
  "$ROOT/README.md" \
  "$ROOT/README_ko.md" \
  "$ROOT/README_ja.md" \
  "$ROOT/README_zh-Hans.md" \
  "$ROOT/README_fr.md" \
  "$ROOT/README_de.md" \
  "$SOURCE_ROOT/"
find "$SOURCE_ROOT" \
  \( -name '.DS_Store' -o -name '__pycache__' -o -name '*.pyc' \) \
  -prune -exec rm -rf {} +
touch -r "$ROOT/Package.swift" "$SOURCE_ROOT"

UNCOMPRESSED="$WORK/negaflow-scanner-sane-$VERSION-source.tar"
COPYFILE_DISABLE=1 tar -C "$WORK" -cf "$UNCOMPRESSED" \
  "negaflow-scanner-sane-$VERSION"
gzip -n -c "$UNCOMPRESSED" >"$OUTPUT_ARCHIVE"
test -s "$OUTPUT_ARCHIVE"

echo "[create-source-archive] source: $OUTPUT_ARCHIVE"
