#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <signed-universal-binary> <dsym-bundle> <output-directory>" >&2
  exit 2
fi

EXECUTABLE="$1"
DSYM_BUNDLE="$2"
OUTPUT_DIR="$3"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/manifest.json"

codesign --verify --strict --verbose=2 "$EXECUTABLE"
ARCHITECTURES="$(lipo -archs "$EXECUTABLE")"
for architecture in arm64 x86_64; do
  if ! grep -qw "$architecture" <<< "$ARCHITECTURES"; then
    echo "[package-release] ERROR: universal binary에 $architecture 아키텍처가 없습니다." >&2
    exit 1
  fi
done
EXECUTABLE_UUIDS="$(dwarfdump --uuid "$EXECUTABLE" | awk '{print $2}' | sort)"
DSYM_UUIDS="$(dwarfdump --uuid "$DSYM_BUNDLE" | awk '{print $2}' | sort)"
if [ -z "$EXECUTABLE_UUIDS" ] || [ "$EXECUTABLE_UUIDS" != "$DSYM_UUIDS" ]; then
  echo "[package-release] ERROR: 실행파일과 dSYM UUID가 일치하지 않습니다." >&2
  exit 1
fi

VERSION="$(plutil -extract pluginVersion raw "$MANIFEST")"
BASE_NAME="negaflow-scanner-sane-$VERSION-macos-universal"
ZIP_NAME="$BASE_NAME.zip"
DSYM_NAME="$BASE_NAME.dSYM.zip"
SOURCE_NAME="negaflow-scanner-sane-$VERSION-source.tar.gz"
CHECKSUM_NAME="$BASE_NAME-SHA256SUMS.txt"
mkdir -p "$OUTPUT_DIR"
for name in "$ZIP_NAME" "$DSYM_NAME" "$SOURCE_NAME" "$CHECKSUM_NAME"; do
  if [ -e "$OUTPUT_DIR/$name" ] && [ "${NEGAFLOW_OVERWRITE_RELEASE:-0}" != "1" ]; then
    echo "[package-release] ERROR: 기존 artifact가 있습니다: $OUTPUT_DIR/$name" >&2
    exit 1
  fi
done

STAGING="$(mktemp -d /tmp/negaflow-sane-release.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
RELEASE_ROOT="$STAGING/negaflow-scanner-sane-$VERSION"
PLUGIN_DIR="$RELEASE_ROOT/sane"
mkdir -p "$PLUGIN_DIR"
cp "$EXECUTABLE" "$PLUGIN_DIR/negaflow-scanner-sane"
cp "$MANIFEST" "$PLUGIN_DIR/manifest.json"
cp \
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
  "$PLUGIN_DIR/"
cp "$ROOT/scripts/install-release.sh" "$RELEASE_ROOT/install.sh"
chmod +x "$PLUGIN_DIR/negaflow-scanner-sane" "$RELEASE_ROOT/install.sh"

bash "$ROOT/scripts/create-source-archive.sh" "$STAGING/$SOURCE_NAME"
cp "$STAGING/$SOURCE_NAME" "$PLUGIN_DIR/$SOURCE_NAME"
ditto -c -k --sequesterRsrc --keepParent "$RELEASE_ROOT" "$STAGING/$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$DSYM_BUNDLE" "$STAGING/$DSYM_NAME"
(
  cd "$STAGING"
  shasum -a 256 "$ZIP_NAME" "$DSYM_NAME" "$SOURCE_NAME" \
    | sed 's#  .*/#  #' > "$CHECKSUM_NAME"
)
for name in "$ZIP_NAME" "$DSYM_NAME" "$SOURCE_NAME" "$CHECKSUM_NAME"; do
  mv -f "$STAGING/$name" "$OUTPUT_DIR/$name"
done

echo "[package-release] zip: $OUTPUT_DIR/$ZIP_NAME"
echo "[package-release] dSYM: $OUTPUT_DIR/$DSYM_NAME"
echo "[package-release] source: $OUTPUT_DIR/$SOURCE_NAME"
echo "[package-release] checksums: $OUTPUT_DIR/$CHECKSUM_NAME"
