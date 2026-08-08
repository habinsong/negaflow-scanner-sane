#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 <output-source-archive>" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 워크플로와 라이선스·README 는 플랫폼 트리 밖 저장소 루트에 있다.
REPO_ROOT="$(cd "$ROOT/.." && pwd)"
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
  "$REPO_ROOT/.github" \
  "$ROOT/Config" \
  "$ROOT/Formula" \
  "$ROOT/Installer" \
  "$ROOT/Sources" \
  "$ROOT/Tests" \
  "$ROOT/scripts" \
  "$SOURCE_ROOT/"
cp -p \
  "$ROOT/Package.swift" \
  "$ROOT/manifest.json" \
  "$ROOT/install.sh" \
  "$REPO_ROOT/LICENSE" \
  "$REPO_ROOT/COPYING" \
  "$REPO_ROOT/THIRD_PARTY_NOTICES.md" \
  "$REPO_ROOT/PROVENANCE.md" \
  "$REPO_ROOT/README.md" \
  "$REPO_ROOT/README_ko.md" \
  "$REPO_ROOT/README_ja.md" \
  "$REPO_ROOT/README_zh-Hans.md" \
  "$REPO_ROOT/README_fr.md" \
  "$REPO_ROOT/README_de.md" \
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
