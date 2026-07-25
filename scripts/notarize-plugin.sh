#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <signed-plugin-zip> <signed-plugin-executable>" >&2
  exit 2
fi

ARCHIVE="$1"
EXECUTABLE="$2"
PROFILE="${NEGAFLOW_NOTARY_KEYCHAIN_PROFILE:-}"
if [ ! -f "$ARCHIVE" ] || [ "${ARCHIVE##*.}" != "zip" ]; then
  echo "[notarize-plugin] ERROR: 제출할 ZIP이 없습니다." >&2
  exit 1
fi
if [ -z "$PROFILE" ]; then
  echo "[notarize-plugin] ERROR: NEGAFLOW_NOTARY_KEYCHAIN_PROFILE이 필요합니다." >&2
  exit 2
fi
details="$(codesign -dv --verbose=4 "$EXECUTABLE" 2>&1)"
if ! grep -q '^Authority=Developer ID Application:' <<< "$details"; then
  echo "[notarize-plugin] ERROR: Developer ID Application 서명이 필요합니다." >&2
  exit 1
fi

result="$(mktemp /tmp/negaflow-sane-notary.XXXXXX.json)"
trap 'rm -f "$result"' EXIT
xcrun notarytool submit "$ARCHIVE" \
  --keychain-profile "$PROFILE" \
  --wait \
  --output-format json > "$result"
status="$(plutil -extract status raw -o - "$result")"
if [ "$status" != "Accepted" ]; then
  echo "[notarize-plugin] ERROR: notarization status=$status" >&2
  exit 1
fi

# 단독 실행파일에는 ticket을 staple할 수 없으므로 온라인 ticket을 Gatekeeper가 조회한다.
spctl --assess --type execute --verbose=4 "$EXECUTABLE"
echo "[notarize-plugin] accepted: $(plutil -extract id raw -o - "$result")"
