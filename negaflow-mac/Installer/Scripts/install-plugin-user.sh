#!/bin/bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "[negaflow-installer] ERROR: plug-in source directory is required." >&2
  exit 2
fi

source_plugin="$1"
manifest="$source_plugin/manifest.json"
executable="$source_plugin/negaflow-scanner-sane"

if [[ ! -d "$source_plugin" || -L "$source_plugin" || ! -f "$manifest" || -L "$manifest" \
      || ! -x "$executable" || -L "$executable" ]]; then
  echo "[negaflow-installer] ERROR: packaged plug-in is incomplete or unsafe." >&2
  exit 1
fi

if [[ "$(plutil -extract schemaVersion raw "$manifest")" != "1" \
      || "$(plutil -extract protocolVersion raw "$manifest")" != "2" \
      || "$(plutil -extract id raw "$manifest")" != "sane" \
      || "$(plutil -extract executable raw "$manifest")" != "negaflow-scanner-sane" ]]; then
  echo "[negaflow-installer] ERROR: unsupported plug-in manifest." >&2
  exit 1
fi

codesign --verify --strict --verbose=2 "$executable"

if [[ -z "${HOME:-}" || "$HOME" != /* || "$HOME" == "/" ]]; then
  echo "[negaflow-installer] ERROR: invalid user home directory." >&2
  exit 1
fi

umask 022
plugin_root="$HOME/Library/Application Support/negaflow/Plugins"
destination="$plugin_root/sane"
mkdir -p "$plugin_root"
chmod go-w "$HOME/Library/Application Support/negaflow" "$plugin_root"

staging="$(mktemp -d "$plugin_root/.sane-install.XXXXXX")"
previous="$plugin_root/.sane-previous.$$"
cleanup() {
  rm -rf "$staging" "$previous"
}
trap cleanup EXIT

ditto "$source_plugin" "$staging/sane"
chmod -R go-w "$staging/sane"
chmod +x "$staging/sane/negaflow-scanner-sane"

if [[ -e "$destination" ]]; then
  mv "$destination" "$previous"
fi
if ! mv "$staging/sane" "$destination"; then
  if [[ -e "$previous" ]]; then
    mv "$previous" "$destination"
  fi
  echo "[negaflow-installer] ERROR: could not replace the installed plug-in." >&2
  exit 1
fi
rm -rf "$previous"

echo "[negaflow-installer] plug-in installed: $destination"
