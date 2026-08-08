#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FORMULA="${1:-$ROOT/Formula/sane-backends-negaflow.rb}"

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [[ ! "$MACOS_MAJOR" =~ ^[0-9]+$ || "$MACOS_MAJOR" -lt 26 ]]; then
  echo "[install-patched-sane] ERROR: Nikon Coolscan support requires macOS 26 or later." >&2
  exit 1
fi

if [[ ! -s "$FORMULA" ]]; then
  echo "[install-patched-sane] ERROR: patched SANE formula is missing: $FORMULA" >&2
  exit 1
fi

if command -v brew >/dev/null 2>&1; then
  BREW="$(command -v brew)"
elif [[ -x /opt/homebrew/bin/brew ]]; then
  BREW=/opt/homebrew/bin/brew
elif [[ -x /usr/local/bin/brew ]]; then
  BREW=/usr/local/bin/brew
else
  echo "[install-patched-sane] ERROR: Homebrew is required." >&2
  exit 1
fi

if ! "$BREW" tap | /usr/bin/grep -Fqx negaflow/scanner; then
  "$BREW" tap-new negaflow/scanner --no-git
fi

TAP_PATH="$("$BREW" --repository negaflow/scanner)"
if [[ -z "$TAP_PATH" || "$TAP_PATH" != /* || ! -d "$TAP_PATH" ]]; then
  echo "[install-patched-sane] ERROR: local Homebrew tap is unavailable." >&2
  exit 1
fi

mkdir -p "$TAP_PATH/Formula"
cp "$FORMULA" "$TAP_PATH/Formula/sane-backends-negaflow.rb"
"$BREW" install negaflow/scanner/sane-backends-negaflow

SANE_PREFIX="$("$BREW" --prefix sane-backends-negaflow)"
if [[ ! -x "$SANE_PREFIX/bin/scanimage" ]]; then
  echo "[install-patched-sane] ERROR: patched scanimage was not installed." >&2
  exit 1
fi

echo "[install-patched-sane] installed: $SANE_PREFIX"
