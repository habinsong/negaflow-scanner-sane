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
# 라이선스·README 는 플랫폼 트리 밖 저장소 루트에 있다.
REPO_ROOT="$(cd "$ROOT/.." && pwd)"
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
BASE_NAME="negaflow-sane-$VERSION-mac-universal"
ZIP_NAME="$BASE_NAME.zip"
DSYM_NAME="$BASE_NAME.dSYM.zip"
SOURCE_NAME="negaflow-sane-$VERSION-source.tar.gz"
mkdir -p "$OUTPUT_DIR"
for name in "$ZIP_NAME" "$DSYM_NAME" "$SOURCE_NAME"; do
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
  "$PLUGIN_DIR/"
cp "$ROOT/scripts/install-release.sh" "$RELEASE_ROOT/install.sh"
chmod +x \
  "$PLUGIN_DIR/negaflow-scanner-sane" \
  "$RELEASE_ROOT/install.sh"

bash "$ROOT/scripts/create-source-archive.sh" "$STAGING/$SOURCE_NAME"
cp "$STAGING/$SOURCE_NAME" "$PLUGIN_DIR/$SOURCE_NAME"
ditto -c -k --sequesterRsrc --keepParent "$RELEASE_ROOT" "$STAGING/$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$DSYM_BUNDLE" "$STAGING/$DSYM_NAME"
for name in "$ZIP_NAME" "$DSYM_NAME" "$SOURCE_NAME"; do
  mv -f "$STAGING/$name" "$OUTPUT_DIR/$name"
done

# 체크섬은 묶음마다 따로 두지 않고 릴리스 폴더 전체를 한 장에 적는다.
bash "$ROOT/scripts/write-release-checksums.sh" "$OUTPUT_DIR"

echo "[package-release] zip: $OUTPUT_DIR/$ZIP_NAME"
echo "[package-release] dSYM: $OUTPUT_DIR/$DSYM_NAME"
echo "[package-release] source: $OUTPUT_DIR/$SOURCE_NAME"
