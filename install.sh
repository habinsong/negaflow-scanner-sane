#!/usr/bin/env bash
# install.sh — negaflow-scanner-sane 플러그인을 빌드하고 negaflow 플러그인 디렉토리에 설치한다.
#
#   ~/Library/Application Support/negaflow/Plugins/sane/
#     ├── negaflow-scanner-sane   (실행파일)
#     └── manifest.json
#
# negaflow 앱은 시작 시 이 디렉토리를 스캔해 플러그인을 발견하고, JSON/CLI 프로토콜로만 통신한다.
#
# 요구사항: Swift(SwiftPM), Homebrew.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# 무엇을 설치하는지 밝힌다. clone 이 "already exists" 로 실패한 뒤 예전 체크아웃을 그대로
# 빌드해도 로그만 봐서는 알 수 없었고, 그대로 옛 플러그인을 설치한 채 테스트하게 된다.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  SUBJECT="$(git -C "$ROOT" log -1 --format=%s 2>/dev/null || true)"
  DIRTY=""
  [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ] && DIRTY=" (uncommitted changes)"
  echo "[install] source: $COMMIT$DIRTY — $SUBJECT"
  if git -C "$ROOT" fetch --quiet origin 2>/dev/null; then
    BEHIND="$(git -C "$ROOT" rev-list --count HEAD..@{upstream} 2>/dev/null || echo 0)"
    if [ "${BEHIND:-0}" -gt 0 ]; then
      echo "[install] WARNING: 이 체크아웃은 origin 보다 $BEHIND 커밋 뒤쳐져 있습니다." >&2
      echo "[install] WARNING: 최신 수정으로 테스트하려면 'git pull' 후 다시 실행하세요." >&2
    fi
  fi
else
  echo "[install] WARNING: git 체크아웃이 아니라 어떤 버전인지 확인할 수 없습니다." >&2
fi

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
