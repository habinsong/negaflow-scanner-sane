#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  echo "usage: $0 <installer-pkg> <installer-dmg> <arm64|universal>" >&2
  exit 2
fi

PKG="$1"
DMG="$2"
EXPECTED_ARCHITECTURE="$3"
MODE="${NEGAFLOW_INSTALLER_MODE:-local}"
case "$EXPECTED_ARCHITECTURE" in
  arm64|universal) ;;
  *)
    echo "[verify-installer] ERROR: expected architecture must be arm64 or universal." >&2
    exit 2
    ;;
esac

if [[ ! -s "$PKG" || ! -s "$DMG" ]]; then
  echo "[verify-installer] ERROR: installer artifact is missing." >&2
  exit 1
fi

for command in pkgutil hdiutil plutil lipo codesign shasum installer tar xcrun spctl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "[verify-installer] ERROR: required command is missing: $command" >&2
    exit 1
  fi
done

TEMPORARY="$(mktemp -d /tmp/negaflow-sane-installer-verify.XXXXXX)"
mounted=0
cleanup() {
  if [[ "$mounted" -eq 1 ]]; then
    hdiutil detach "$TEMPORARY/mount" >/dev/null || true
  fi
  rm -rf "$TEMPORARY"
}
trap cleanup EXIT

EXPANDED="$TEMPORARY/expanded"
pkgutil --expand-full "$PKG" "$EXPANDED"
DISTRIBUTION="$EXPANDED/Distribution"
if [[ ! -f "$DISTRIBUTION" ]]; then
  echo "[verify-installer] ERROR: product distribution is missing." >&2
  exit 1
fi

homebrew_line="$(grep -n '#HomebrewComponent.pkg' "$DISTRIBUTION" | head -n1 | cut -d: -f1)"
setup_line="$(grep -n '#negaflowScannerSetup.pkg' "$DISTRIBUTION" | head -n1 | cut -d: -f1)"
if [[ -z "$homebrew_line" || -z "$setup_line" || "$homebrew_line" -ge "$setup_line" ]]; then
  echo "[verify-installer] ERROR: Homebrew must precede the SANE/plug-in setup component." >&2
  exit 1
fi
grep -Fq 'homebrew_required()' "$DISTRIBUTION"
grep -Fq 'installation_check()' "$DISTRIBUTION"
grep -Fq 'min="14.0.0"' "$DISTRIBUTION"

HOMEBREW_PACKAGE_INFO="$(find "$EXPANDED" -path '*HomebrewComponent.pkg/PackageInfo' -print -quit)"
SETUP_PACKAGE_INFO="$(find "$EXPANDED" -path '*negaflowScannerSetup.pkg/PackageInfo' -print -quit)"
if [[ -z "$HOMEBREW_PACKAGE_INFO" || -z "$SETUP_PACKAGE_INFO" ]]; then
  echo "[verify-installer] ERROR: component package metadata is missing." >&2
  exit 1
fi
grep -Fq 'identifier="sh.brew.homebrew"' "$HOMEBREW_PACKAGE_INFO"
grep -Fq 'identifier="com.habinsong.negaflow.scanner-sane.setup"' "$SETUP_PACKAGE_INFO"

POSTINSTALL="$(find "$EXPANDED" -path '*negaflowScannerSetup.pkg/Scripts/postinstall' -print -quit)"
USER_INSTALLER="$(find "$EXPANDED" -path '*negaflowScannerSetup.pkg/Scripts/install-plugin-user.sh' -print -quit)"
PLUGIN="$(find "$EXPANDED" -path '*negaflowScannerSetup.pkg/Scripts/sane/negaflow-scanner-sane' -print -quit)"
MANIFEST="$(find "$EXPANDED" -path '*negaflowScannerSetup.pkg/Scripts/sane/manifest.json' -print -quit)"
SOURCE_ARCHIVE="$(find "$EXPANDED" -path '*negaflowScannerSetup.pkg/Scripts/sane/negaflow-scanner-sane-*-source.tar.gz' -print -quit)"
LICENSE_NOTICE="$(find "$EXPANDED" -path '*negaflowScannerSetup.pkg/Scripts/sane/LICENSE' -print -quit)"
GPL_TEXT="$(find "$EXPANDED" -path '*negaflowScannerSetup.pkg/Scripts/sane/COPYING' -print -quit)"
THIRD_PARTY_NOTICE="$(find "$EXPANDED" -path '*negaflowScannerSetup.pkg/Scripts/sane/THIRD_PARTY_NOTICES.md' -print -quit)"
PROVENANCE="$(find "$EXPANDED" -path '*negaflowScannerSetup.pkg/Scripts/sane/PROVENANCE.md' -print -quit)"
if [[ -z "$POSTINSTALL" || -z "$USER_INSTALLER" || -z "$PLUGIN" || -z "$MANIFEST" \
      || -z "$SOURCE_ARCHIVE" || -z "$LICENSE_NOTICE" || -z "$GPL_TEXT" \
      || -z "$THIRD_PARTY_NOTICE" || -z "$PROVENANCE" ]]; then
  echo "[verify-installer] ERROR: setup scripts or plug-in payload are missing." >&2
  exit 1
fi
test -s "$LICENSE_NOTICE"
test -s "$GPL_TEXT"
test -s "$THIRD_PARTY_NOTICE"
test -s "$PROVENANCE"

bash -n "$POSTINSTALL"
bash -n "$USER_INSTALLER"
grep -Fq 'run_brew_as_console_user install sane-backends' "$POSTINSTALL"
codesign --verify --strict --verbose=2 "$PLUGIN"
architectures="$(lipo -archs "$PLUGIN")"
case "$EXPECTED_ARCHITECTURE" in
  arm64)
    [[ "$architectures" == "arm64" ]]
    ;;
  universal)
    grep -qw arm64 <<<"$architectures"
    grep -qw x86_64 <<<"$architectures"
    ;;
esac
[[ "$(plutil -extract protocolVersion raw "$MANIFEST")" == "2" ]]
[[ "$(plutil -extract id raw "$MANIFEST")" == "sane" ]]
tar -tzf "$SOURCE_ARCHIVE" | grep -E '^negaflow-scanner-sane-[^/]+/Package.swift$' >/dev/null
tar -tzf "$SOURCE_ARCHIVE" | grep -E '^negaflow-scanner-sane-[^/]+/Sources/SANEPluginCore/' >/dev/null
tar -tzf "$SOURCE_ARCHIVE" | grep -E '^negaflow-scanner-sane-[^/]+/LICENSE$' >/dev/null
tar -tzf "$SOURCE_ARCHIVE" | grep -E '^negaflow-scanner-sane-[^/]+/COPYING$' >/dev/null
tar -tzf "$SOURCE_ARCHIVE" | grep -E '^negaflow-scanner-sane-[^/]+/THIRD_PARTY_NOTICES.md$' >/dev/null
tar -tzf "$SOURCE_ARCHIVE" | grep -E '^negaflow-scanner-sane-[^/]+/PROVENANCE.md$' >/dev/null

TEST_HOME="$TEMPORARY/user-home"
mkdir -p "$TEST_HOME"
HOME="$TEST_HOME" USER="$(id -un)" LOGNAME="$(id -un)" \
  bash "$USER_INSTALLER" "$(dirname "$MANIFEST")"
INSTALLED="$TEST_HOME/Library/Application Support/negaflow/Plugins/sane"
test -x "$INSTALLED/negaflow-scanner-sane"
test -s "$INSTALLED/manifest.json"
test -s "$INSTALLED/LICENSE"
test -s "$INSTALLED/COPYING"
test -s "$INSTALLED/THIRD_PARTY_NOTICES.md"
test -s "$INSTALLED/PROVENANCE.md"
INSTALLED_SOURCE="$(find "$INSTALLED" -maxdepth 1 -name 'negaflow-scanner-sane-*-source.tar.gz' -print -quit)"
test -s "$INSTALLED_SOURCE"
if find "$TEST_HOME/Library/Application Support/negaflow/Plugins" \
  \( -perm -0020 -o -perm -0002 \) -print | grep -q .; then
  echo "[verify-installer] ERROR: simulated user installation is group/other writable." >&2
  exit 1
fi

installer -pkginfo -pkg "$PKG" >/dev/null
installer -showChoicesXML -pkg "$PKG" >/dev/null
SIGNATURE="$TEMPORARY/package-signature.txt"
if pkgutil --check-signature "$PKG" >"$SIGNATURE" 2>&1; then
  signature_present=1
else
  signature_present=0
fi
if [[ "$MODE" == "distribution" ]]; then
  if [[ "$signature_present" -ne 1 ]]; then
    echo "[verify-installer] ERROR: distribution package is not signed." >&2
    exit 1
  fi
  grep -Fq 'Developer ID Installer:' "$SIGNATURE"
  grep -Fq 'signed by a developer certificate issued by Apple for distribution' "$SIGNATURE"
  xcrun stapler validate "$PKG"
  spctl --assess --type install --verbose=4 "$PKG"
elif [[ "$signature_present" -ne 1 ]]; then
  grep -Fq 'Status: no signature' "$SIGNATURE"
fi

hdiutil verify "$DMG" >/dev/null
if [[ "$MODE" == "distribution" ]]; then
  xcrun stapler validate "$DMG"
fi
mkdir -p "$TEMPORARY/mount"
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$TEMPORARY/mount" >/dev/null
mounted=1

DMG_PKG="$TEMPORARY/mount/Install negaflow Scanner.pkg"
test -s "$DMG_PKG"
test -s "$TEMPORARY/mount/THIRD_PARTY_NOTICES.md"
test -s "$TEMPORARY/mount/LICENSE"
test -s "$TEMPORARY/mount/COPYING"
test -s "$TEMPORARY/mount/PROVENANCE.md"
DMG_SOURCE="$(find "$TEMPORARY/mount" -maxdepth 1 -name 'negaflow-scanner-sane-*-source.tar.gz' -print -quit)"
test -s "$DMG_SOURCE"
for readme in README.md README_ko.md README_ja.md README_zh-Hans.md README_fr.md README_de.md; do
  test -s "$TEMPORARY/mount/$readme"
done

if [[ "$(shasum -a 256 "$PKG" | awk '{print $1}')" \
      != "$(shasum -a 256 "$DMG_PKG" | awk '{print $1}')" ]]; then
  echo "[verify-installer] ERROR: package in DMG does not match the standalone package." >&2
  exit 1
fi
if [[ "$(shasum -a 256 "$SOURCE_ARCHIVE" | awk '{print $1}')" \
      != "$(shasum -a 256 "$DMG_SOURCE" | awk '{print $1}')" ]]; then
  echo "[verify-installer] ERROR: source archive in DMG does not match the package copy." >&2
  exit 1
fi

hdiutil detach "$TEMPORARY/mount" >/dev/null
mounted=0

echo "[verify-installer] valid: mode=$MODE expected=$EXPECTED_ARCHITECTURE architectures=$architectures"
