#!/usr/bin/env bash
# 배포물을 조립하고 실행 파일 하나로 감싼다. MSYS2(UCRT64) 셸에서 돈다.
#
# 사용법: make-installer.sh [<플러그인 exe 경로>]
#
# 버전은 manifest.json 의 pluginVersion 을 쓴다. 두 곳에 적으면 언젠가
# 갈라진다.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PRODUCT_ROOT="$(cd "$HERE/../.." && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
PLUGIN=${1:-"$REPO/negaflow-windows/out/build/Release/negaflow-scanner-sane.exe"}
PAYLOAD="$HERE/payload"

MAKENSIS=${MAKENSIS:-makensis}
command -v "$MAKENSIS" >/dev/null 2>&1 || {
    echo "makensis 가 없다. pacman -S mingw-w64-ucrt-x86_64-nsis" >&2
    exit 1
}

VERSION=$(sed -n 's/.*"pluginVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
          "$PRODUCT_ROOT/manifest.json")
[ -n "$VERSION" ] || { echo "manifest.json 에서 pluginVersion 을 못 읽었다" >&2; exit 1; }

bash "$HERE/make-payload.sh" "$PAYLOAD" "$PLUGIN"

# 설치 화면이 쓰는 브랜딩 비트맵을 앱 아이콘에서 굽는다. 저장소에 BMP 를 넣어 두면 아이콘을
# 바꿔도 설치 화면이 옛 아이콘으로 남는다.
BRANDING="$(mktemp -d)"
trap 'rm -rf "$BRANDING"' EXIT
powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(cygpath -w "$REPO/negaflow-windows/scripts/generate-installer-branding.ps1")" \
    -SourceIcon "$(cygpath -w "$REPO/negaflow-windows/src/app/AppIcon-1024.png")" \
    -OutputDirectory "$(cygpath -w "$BRANDING")" >/dev/null
for bitmap in welcome.bmp header.bmp; do
    [ -f "$BRANDING/$bitmap" ] || { echo "브랜딩 비트맵이 안 나왔다: $bitmap" >&2; exit 1; }
done

echo
echo "설치 프로그램을 만든다 (버전 $VERSION)"
cd "$HERE"
# -INPUTCHARSET 을 준다. .nsi 는 BOM 없는 UTF-8 인데(저장소의 다른 파일과
# 같게), Unicode 스크립트에서 makensis 는 BOM 이 없으면 인코딩을 못 정하고
# 첫 줄에서 멈춘다.
"$MAKENSIS" -V2 -INPUTCHARSET UTF8 \
         -DPAYLOAD="$(cygpath -w "$PAYLOAD")" -DVERSION="$VERSION" \
         -DBRANDING="$(cygpath -w "$BRANDING")" \
         negaflow-scanner-sane.nsi

OUT="$HERE/negaflow-scanner-sane-$VERSION-x64-setup.exe"
[ -f "$OUT" ] || { echo "설치 프로그램이 안 나왔다" >&2; exit 1; }
echo
echo "설치 프로그램: $OUT"
ls -l --block-size=1 "$OUT" | awk '{printf "  크기: %.1f MB\n", $5 / 1048576}'
echo "  서명하지 않았다 — SmartScreen 경고가 뜬다 (D-1)"
