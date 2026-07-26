#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(plutil -extract pluginVersion raw "$ROOT/manifest.json")"
OUTPUT_DIR="${NEGAFLOW_INSTALLER_OUTPUT_DIR:-$ROOT/.build/release-artifacts}"
INSTALLER_MODE="${NEGAFLOW_INSTALLER_MODE:-local}"
INSTALLER_ARCHITECTURE="${NEGAFLOW_INSTALLER_ARCHITECTURE:-all}"
APP_SIGN_IDENTITY="${NEGAFLOW_CODESIGN_IDENTITY:--}"
PKG_SIGN_IDENTITY="${NEGAFLOW_INSTALLER_IDENTITY:-}"
HOMEBREW_VERSION="${NEGAFLOW_HOMEBREW_PKG_VERSION:-6.0.11}"
HOMEBREW_SHA256="${NEGAFLOW_HOMEBREW_PKG_SHA256:-0545b1b85053ad6292799e8f9b11caee373cb377364f4d293cc4711487a9b944}"
HOMEBREW_TEAM_ID="${NEGAFLOW_HOMEBREW_TEAM_ID:-927JGANW46}"
HOMEBREW_URL="${NEGAFLOW_HOMEBREW_PKG_URL:-https://github.com/Homebrew/brew/releases/download/$HOMEBREW_VERSION/Homebrew.pkg}"

case "$INSTALLER_ARCHITECTURE" in
  all)
    for architecture in arm64 universal; do
      NEGAFLOW_INSTALLER_ARCHITECTURE="$architecture" bash "$0"
    done
    exit 0
    ;;
  arm64|universal) ;;
  *)
    echo "[build-installer] ERROR: NEGAFLOW_INSTALLER_ARCHITECTURE must be arm64, universal, or all." >&2
    exit 2
    ;;
esac

for command in curl pkgbuild productbuild pkgutil hdiutil plutil lipo codesign shasum tar xcrun spctl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "[build-installer] ERROR: required command is missing: $command" >&2
    exit 1
  fi
done

case "$INSTALLER_MODE" in
  local) ;;
  distribution)
    if [[ "$APP_SIGN_IDENTITY" != Developer\ ID\ Application:* \
          || "$PKG_SIGN_IDENTITY" != Developer\ ID\ Installer:* \
          || -z "${NEGAFLOW_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
      echo "[build-installer] ERROR: distribution mode requires Developer ID Application," >&2
      echo "Developer ID Installer, and NEGAFLOW_NOTARY_KEYCHAIN_PROFILE." >&2
      exit 2
    fi
    ;;
  *)
    echo "[build-installer] ERROR: NEGAFLOW_INSTALLER_MODE must be local or distribution." >&2
    exit 2
    ;;
esac

BASE_NAME="negaflow-scanner-sane-$VERSION-macos-$INSTALLER_ARCHITECTURE-installer"
SOURCE_NAME="negaflow-scanner-sane-$VERSION-source.tar.gz"
PKG_NAME="$BASE_NAME.pkg"
DMG_NAME="$BASE_NAME.dmg"
CHECKSUM_NAME="$BASE_NAME-SHA256SUMS.txt"

mkdir -p "$OUTPUT_DIR"
for name in "$PKG_NAME" "$DMG_NAME" "$CHECKSUM_NAME"; do
  if [[ -e "$OUTPUT_DIR/$name" && "${NEGAFLOW_OVERWRITE_INSTALLER:-0}" != "1" ]]; then
    echo "[build-installer] ERROR: existing artifact: $OUTPUT_DIR/$name" >&2
    exit 1
  fi
done

WORK="$(mktemp -d /tmp/negaflow-sane-installer.XXXXXX)"
cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

RELEASE_OUTPUT="$WORK/release"
mkdir -p "$RELEASE_OUTPUT"
NEGAFLOW_RELEASE_OUTPUT_DIR="$RELEASE_OUTPUT" \
NEGAFLOW_OVERWRITE_RELEASE=1 \
NEGAFLOW_RELEASE_MODE=local \
NEGAFLOW_CODESIGN_IDENTITY="$APP_SIGN_IDENTITY" \
  bash "$ROOT/scripts/build-release.sh"

UNIVERSAL_PLUGIN_BINARY="$ROOT/.build/release-universal/negaflow-scanner-sane"
if [[ ! -x "$UNIVERSAL_PLUGIN_BINARY" ]]; then
  echo "[build-installer] ERROR: universal plug-in binary is missing." >&2
  exit 1
fi
PLUGIN_BINARY="$UNIVERSAL_PLUGIN_BINARY"
if [[ "$INSTALLER_ARCHITECTURE" == "arm64" ]]; then
  PLUGIN_BINARY="$WORK/negaflow-scanner-sane-arm64"
  lipo "$UNIVERSAL_PLUGIN_BINARY" -thin arm64 -output "$PLUGIN_BINARY"
  chmod +x "$PLUGIN_BINARY"
  bash "$ROOT/scripts/sign-plugin.sh" "$PLUGIN_BINARY" "$APP_SIGN_IDENTITY"
fi

CACHE_DIR="$ROOT/.build/installer-cache"
CACHED_HOMEBREW="$CACHE_DIR/Homebrew-$HOMEBREW_VERSION.pkg"
mkdir -p "$CACHE_DIR"
if [[ ! -f "$CACHED_HOMEBREW" ]]; then
  DOWNLOAD="$WORK/Homebrew.pkg.download"
  curl --fail --location --proto '=https' --tlsv1.2 \
    --output "$DOWNLOAD" "$HOMEBREW_URL"
  mv "$DOWNLOAD" "$CACHED_HOMEBREW"
fi

ACTUAL_HOMEBREW_SHA256="$(shasum -a 256 "$CACHED_HOMEBREW" | awk '{print $1}')"
if [[ "$ACTUAL_HOMEBREW_SHA256" != "$HOMEBREW_SHA256" ]]; then
  echo "[build-installer] ERROR: Homebrew package SHA-256 mismatch." >&2
  echo "expected=$HOMEBREW_SHA256 actual=$ACTUAL_HOMEBREW_SHA256" >&2
  exit 1
fi

HOMEBREW_SIGNATURE="$WORK/homebrew-signature.txt"
pkgutil --check-signature "$CACHED_HOMEBREW" >"$HOMEBREW_SIGNATURE"
if ! grep -Fq "Developer ID Installer:" "$HOMEBREW_SIGNATURE" \
   || ! grep -Fq "($HOMEBREW_TEAM_ID)" "$HOMEBREW_SIGNATURE" \
   || ! grep -Fq "Notarization: trusted by the Apple notary service" "$HOMEBREW_SIGNATURE"; then
  echo "[build-installer] ERROR: Homebrew package signature or notarization is not trusted." >&2
  exit 1
fi

COMPONENTS="$WORK/components"
mkdir -p "$COMPONENTS"
HOMEBREW_EXPANDED="$WORK/homebrew-expanded"
pkgutil --expand "$CACHED_HOMEBREW" "$HOMEBREW_EXPANDED"
if [[ ! -d "$HOMEBREW_EXPANDED/Homebrew.pkg" ]]; then
  echo "[build-installer] ERROR: official Homebrew component package is missing." >&2
  exit 1
fi
pkgutil --flatten \
  "$HOMEBREW_EXPANDED/Homebrew.pkg" \
  "$COMPONENTS/HomebrewComponent.pkg"

SETUP_SCRIPTS="$WORK/setup-scripts"
mkdir -p "$SETUP_SCRIPTS/sane"

SOURCE_ARCHIVE="$RELEASE_OUTPUT/$SOURCE_NAME"
if [[ ! -s "$SOURCE_ARCHIVE" ]]; then
  echo "[build-installer] ERROR: matching source archive is missing." >&2
  exit 1
fi

cp "$ROOT/Installer/Scripts/postinstall" "$SETUP_SCRIPTS/postinstall"
cp "$ROOT/Installer/Scripts/install-plugin-user.sh" "$SETUP_SCRIPTS/install-plugin-user.sh"
cp "$PLUGIN_BINARY" "$SETUP_SCRIPTS/sane/negaflow-scanner-sane"
cp "$ROOT/manifest.json" "$SETUP_SCRIPTS/sane/manifest.json"
cp "$SOURCE_ARCHIVE" "$SETUP_SCRIPTS/sane/"
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
  "$SETUP_SCRIPTS/sane/"
chmod +x \
  "$SETUP_SCRIPTS/postinstall" \
  "$SETUP_SCRIPTS/install-plugin-user.sh" \
  "$SETUP_SCRIPTS/sane/negaflow-scanner-sane"

pkgbuild \
  --nopayload \
  --scripts "$SETUP_SCRIPTS" \
  --identifier com.habinsong.negaflow.scanner-sane.setup \
  --version "$VERSION" \
  --min-os-version 14.0 \
  "$COMPONENTS/negaflowScannerSetup.pkg"

RENDERED_DISTRIBUTION="$WORK/Distribution.xml"
sed \
  -e "s/@HOMEBREW_VERSION@/$HOMEBREW_VERSION/g" \
  -e "s/@PLUGIN_VERSION@/$VERSION/g" \
  -e "s/@HOST_ARCHITECTURES@/$(
    if [[ "$INSTALLER_ARCHITECTURE" == "arm64" ]]; then
      printf 'arm64'
    else
      printf 'x86_64,arm64'
    fi
  )/g" \
  "$ROOT/Installer/Distribution.xml" >"$RENDERED_DISTRIBUTION"

BUILT_PKG="$WORK/$PKG_NAME"
productbuild_args=(
  --distribution "$RENDERED_DISTRIBUTION"
  --package-path "$COMPONENTS"
  --resources "$ROOT/Installer/Resources"
)
if [[ "$INSTALLER_MODE" == "distribution" ]]; then
  productbuild_args+=(--sign "$PKG_SIGN_IDENTITY" --timestamp)
fi
productbuild "${productbuild_args[@]}" "$BUILT_PKG"

notarize_artifact() {
  local artifact="$1"
  local kind="$2"
  local result="$WORK/notary-$kind-result.json"

  xcrun notarytool submit "$artifact" \
    --keychain-profile "$NEGAFLOW_NOTARY_KEYCHAIN_PROFILE" \
    --wait \
    --output-format json >"$result"
  if [[ "$(plutil -extract status raw -o - "$result")" != "Accepted" ]]; then
    echo "[build-installer] ERROR: $kind notarization was not accepted." >&2
    exit 1
  fi
  xcrun stapler staple "$artifact"
  xcrun stapler validate "$artifact"
}

if [[ "$INSTALLER_MODE" == "distribution" ]]; then
  notarize_artifact "$BUILT_PKG" "pkg"
  spctl --assess --type install --verbose=4 "$BUILT_PKG"
fi

DMG_ROOT="$WORK/dmg"
mkdir -p "$DMG_ROOT"
cp "$BUILT_PKG" "$DMG_ROOT/Install negaflow Scanner.pkg"
cp "$SOURCE_ARCHIVE" "$DMG_ROOT/"
cp \
  "$ROOT/THIRD_PARTY_NOTICES.md" \
  "$ROOT/LICENSE" \
  "$ROOT/COPYING" \
  "$ROOT/PROVENANCE.md" \
  "$ROOT/README.md" \
  "$ROOT/README_ko.md" \
  "$ROOT/README_ja.md" \
  "$ROOT/README_zh-Hans.md" \
  "$ROOT/README_fr.md" \
  "$ROOT/README_de.md" \
  "$DMG_ROOT/"

BUILT_DMG="$WORK/$DMG_NAME"
hdiutil create \
  -volname "negaflow Scanner Installer" \
  -srcfolder "$DMG_ROOT" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$BUILT_DMG"

if [[ "$INSTALLER_MODE" == "distribution" ]]; then
  codesign --force --timestamp --sign "$APP_SIGN_IDENTITY" "$BUILT_DMG"
  notarize_artifact "$BUILT_DMG" "dmg"
fi

(
  cd "$WORK"
  shasum -a 256 "$PKG_NAME" "$DMG_NAME" >"$CHECKSUM_NAME"
)

NEGAFLOW_INSTALLER_MODE="$INSTALLER_MODE" \
  bash "$ROOT/scripts/verify-installer.sh" \
    "$BUILT_PKG" \
    "$BUILT_DMG" \
    "$INSTALLER_ARCHITECTURE"

mv -f "$BUILT_PKG" "$OUTPUT_DIR/$PKG_NAME"
mv -f "$BUILT_DMG" "$OUTPUT_DIR/$DMG_NAME"
mv -f "$WORK/$CHECKSUM_NAME" "$OUTPUT_DIR/$CHECKSUM_NAME"

echo "[build-installer] pkg: $OUTPUT_DIR/$PKG_NAME"
echo "[build-installer] dmg: $OUTPUT_DIR/$DMG_NAME"
echo "[build-installer] checksums: $OUTPUT_DIR/$CHECKSUM_NAME"
echo "[build-installer] mode: $INSTALLER_MODE"
echo "[build-installer] architecture: $INSTALLER_ARCHITECTURE"
