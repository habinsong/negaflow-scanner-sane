#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${NEGAFLOW_RELEASE_OUTPUT_DIR:-$ROOT/.build/release-artifacts}"
SIGN_IDENTITY="${NEGAFLOW_CODESIGN_IDENTITY:--}"
RELEASE_MODE="${NEGAFLOW_RELEASE_MODE:-local}"
ARM_SCRATCH="$ROOT/.build/release-arm64"
X86_SCRATCH="$ROOT/.build/release-x86_64"
UNIVERSAL_DIR="$ROOT/.build/release-universal"

case "$RELEASE_MODE" in
  local) ;;
  distribution)
    if [ "$SIGN_IDENTITY" = "-" ] || [ -z "${NEGAFLOW_NOTARY_KEYCHAIN_PROFILE:-}" ]; then
      echo "[build-release] ERROR: distribution 모드에는 Developer ID와 notary profile이 필요합니다." >&2
      exit 2
    fi
    ;;
  *) echo "[build-release] ERROR: mode는 local 또는 distribution이어야 합니다." >&2; exit 2 ;;
esac

cd "$ROOT"
python3 "$ROOT/scripts/verify-provenance.py"
swift test
ARM_BIN_DIR="$(swift build -c release --triple arm64-apple-macosx13.0 \
  --scratch-path "$ARM_SCRATCH" --show-bin-path)"
X86_BIN_DIR="$(swift build -c release --triple x86_64-apple-macosx13.0 \
  --scratch-path "$X86_SCRATCH" --show-bin-path)"
swift build -c release --triple arm64-apple-macosx13.0 --scratch-path "$ARM_SCRATCH"
swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path "$X86_SCRATCH"

mkdir -p "$UNIVERSAL_DIR"
UNIVERSAL_BIN="$UNIVERSAL_DIR/negaflow-scanner-sane"
DSYM_BUNDLE="$UNIVERSAL_DIR/negaflow-scanner-sane.dSYM"
lipo -create \
  "$ARM_BIN_DIR/negaflow-scanner-sane" \
  "$X86_BIN_DIR/negaflow-scanner-sane" \
  -output "$UNIVERSAL_BIN"
chmod +x "$UNIVERSAL_BIN"
dsymutil "$UNIVERSAL_BIN" -o "$DSYM_BUNDLE"
bash "$ROOT/scripts/sign-plugin.sh" "$UNIVERSAL_BIN" "$SIGN_IDENTITY"
NEGAFLOW_OVERWRITE_RELEASE="${NEGAFLOW_OVERWRITE_RELEASE:-0}" \
  bash "$ROOT/scripts/package-release.sh" "$UNIVERSAL_BIN" "$DSYM_BUNDLE" "$OUTPUT_DIR"
bash "$ROOT/scripts/verify-release.sh" "$OUTPUT_DIR"

if [ "$RELEASE_MODE" = "distribution" ]; then
  VERSION="$(plutil -extract pluginVersion raw "$ROOT/manifest.json")"
  ZIP="$OUTPUT_DIR/negaflow-sane-$VERSION-mac-universal.zip"
  bash "$ROOT/scripts/notarize-plugin.sh" "$ZIP" "$UNIVERSAL_BIN"
fi

echo "[build-release] complete: mode=$RELEASE_MODE output=$OUTPUT_DIR"
