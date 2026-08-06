#!/usr/bin/env bash
# 배포물을 조립하고 실행 파일 하나로 감싼다. MSYS2(UCRT64) 셸에서 돈다.
#
# 사용법: make-installer.sh [<플러그인 exe 경로>]
#
# 버전은 manifest.json 의 pluginVersion 을 쓴다. 두 곳에 적으면 언젠가
# 갈라진다.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PLUGIN=${1:-"$REPO/build/Release/negaflow-scanner-sane.exe"}
PAYLOAD="$HERE/payload"

command -v makensis >/dev/null 2>&1 || {
    echo "makensis 가 없다. pacman -S mingw-w64-ucrt-x86_64-nsis" >&2
    exit 1
}

VERSION=$(sed -n 's/.*"pluginVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
          "$REPO/manifest.json")
[ -n "$VERSION" ] || { echo "manifest.json 에서 pluginVersion 을 못 읽었다" >&2; exit 1; }

bash "$HERE/make-payload.sh" "$PAYLOAD" "$PLUGIN"

echo
echo "설치 프로그램을 만든다 (버전 $VERSION)"
cd "$HERE"
# -INPUTCHARSET 을 준다. .nsi 는 BOM 없는 UTF-8 인데(저장소의 다른 파일과
# 같게), Unicode 스크립트에서 makensis 는 BOM 이 없으면 인코딩을 못 정하고
# 첫 줄에서 멈춘다.
makensis -V2 -INPUTCHARSET UTF8 \
         -DPAYLOAD="$(cygpath -w "$PAYLOAD")" -DVERSION="$VERSION" \
         negaflow-scanner-sane.nsi

OUT="$HERE/negaflow-scanner-sane-$VERSION-x64-setup.exe"
[ -f "$OUT" ] || { echo "설치 프로그램이 안 나왔다" >&2; exit 1; }
echo
echo "설치 프로그램: $OUT"
ls -l --block-size=1 "$OUT" | awk '{printf "  크기: %.1f MB\n", $5 / 1048576}'
echo "  서명하지 않았다 — SmartScreen 경고가 뜬다 (D-1)"
