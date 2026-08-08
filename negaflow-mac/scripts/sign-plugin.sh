#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 <plugin-executable> [codesign-identity|-]" >&2
  exit 2
fi

EXECUTABLE="$1"
SIGN_IDENTITY="${2:--}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTITLEMENTS="$ROOT/Config/Plugin.entitlements"

if [ ! -x "$EXECUTABLE" ]; then
  echo "[sign-plugin] ERROR: 실행파일이 없습니다: $EXECUTABLE" >&2
  exit 1
fi

sign_args=(--force --options runtime --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" = "-" ]; then
  sign_args+=(--timestamp=none)
else
  if [[ "$SIGN_IDENTITY" != Developer\ ID\ Application:* ]]; then
    echo "[sign-plugin] ERROR: 배포 서명은 Developer ID Application 인증서여야 합니다." >&2
    exit 1
  fi
  identities="$(security find-identity -v -p codesigning)"
  if ! grep -Fq "\"$SIGN_IDENTITY\"" <<< "$identities"; then
    echo "[sign-plugin] ERROR: Keychain에서 인증서를 찾을 수 없습니다: $SIGN_IDENTITY" >&2
    exit 1
  fi
  sign_args+=(--timestamp)
fi

codesign "${sign_args[@]}" --entitlements "$ENTITLEMENTS" "$EXECUTABLE"
codesign --verify --strict --verbose=2 "$EXECUTABLE"
details="$(codesign -dv --verbose=4 "$EXECUTABLE" 2>&1)"
if ! grep -q 'runtime' <<< "$details"; then
  echo "[sign-plugin] ERROR: hardened runtime 플래그가 없습니다." >&2
  exit 1
fi

echo "[sign-plugin] signed: $EXECUTABLE"
