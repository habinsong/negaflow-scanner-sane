#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_PLUGIN="$ROOT/sane"
PLUGIN_ROOT="${NEGAFLOW_PLUGINS_DIR:-$HOME/Library/Application Support/negaflow/Plugins}"
DESTINATION="$PLUGIN_ROOT/sane"

if [ ! -d "$SOURCE_PLUGIN" ]; then
  echo "[install-release] ERROR: 배포물의 sane 디렉터리가 없습니다." >&2
  exit 1
fi
MANIFEST="$SOURCE_PLUGIN/manifest.json"
EXECUTABLE="$SOURCE_PLUGIN/negaflow-scanner-sane"
if [ ! -f "$MANIFEST" ] || [ ! -x "$EXECUTABLE" ]; then
  echo "[install-release] ERROR: manifest 또는 실행파일이 없습니다." >&2
  exit 1
fi
if [ "$(plutil -extract schemaVersion raw "$MANIFEST")" != "1" ] \
    || [ "$(plutil -extract protocolVersion raw "$MANIFEST")" != "2" ] \
    || [ "$(plutil -extract id raw "$MANIFEST")" != "sane" ] \
    || [ "$(plutil -extract executable raw "$MANIFEST")" != "negaflow-scanner-sane" ]; then
  echo "[install-release] ERROR: 지원하지 않는 plugin manifest입니다." >&2
  exit 1
fi
codesign --verify --strict --verbose=2 "$EXECUTABLE"

mkdir -p "$PLUGIN_ROOT"
STAGING="$(mktemp -d "$PLUGIN_ROOT/.sane-install.XXXXXX")"
PREVIOUS="$PLUGIN_ROOT/.sane-previous.$$"
trap 'rm -rf "$STAGING" "$PREVIOUS"' EXIT
ditto "$SOURCE_PLUGIN" "$STAGING/sane"
chmod +x "$STAGING/sane/negaflow-scanner-sane"

if [ -e "$DESTINATION" ]; then
  mv "$DESTINATION" "$PREVIOUS"
fi
if ! mv "$STAGING/sane" "$DESTINATION"; then
  if [ -e "$PREVIOUS" ]; then mv "$PREVIOUS" "$DESTINATION"; fi
  echo "[install-release] ERROR: 설치 교체에 실패했습니다." >&2
  exit 1
fi
rm -rf "$PREVIOUS"

echo "[install-release] installed: $DESTINATION"
echo "[install-release] Negaflow에서 새 실행파일 hash를 다시 승인하세요."
