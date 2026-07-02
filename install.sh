#!/usr/bin/env bash
# install.sh — negaflow-scanner-sane 플러그인을 빌드하고 negaflow 플러그인 디렉토리에 설치한다.
#
#   ~/Library/Application Support/negaflow/Plugins/sane/
#     ├── negaflow-scanner-sane   (실행파일)
#     └── manifest.json
#
# negaflow 앱은 시작 시 이 디렉토리를 스캔해 플러그인을 발견하고, JSON/CLI 프로토콜로만 통신한다.
#
# 요구사항: Swift(SwiftPM), 그리고 런타임에 SANE `scanimage`(예: `brew install sane-backends`).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "[install] building release…"
swift build -c release

BIN="$ROOT/.build/release/negaflow-scanner-sane"
if [ ! -x "$BIN" ]; then
  echo "[install] ERROR: 빌드 산출물을 찾을 수 없습니다: $BIN" >&2
  exit 1
fi

DEST="$HOME/Library/Application Support/negaflow/Plugins/sane"
mkdir -p "$DEST"
cp "$BIN" "$DEST/negaflow-scanner-sane"
cp "$ROOT/manifest.json" "$DEST/manifest.json"
chmod +x "$DEST/negaflow-scanner-sane"

echo "[install] installed to: $DEST"
echo "[install] negaflow 를 재시작하면 '스캐너 불러오기'에서 스캐너가 인식됩니다."
if ! command -v scanimage >/dev/null 2>&1; then
  echo "[install] 참고: 'scanimage' 가 PATH 에 없습니다. 'brew install sane-backends' 를 설치하세요."
fi
