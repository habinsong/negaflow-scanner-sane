#!/usr/bin/env bash
# 배포물을 조립한다. MSYS2(UCRT64) 셸에서 돈다.
#
# 담을 DLL 목록을 **손으로 적지 않는다.** 손으로 적으면 반드시 빠지고, 빠진
# 것은 사용자 기계에서만 드러난다. `ldd` 가 계산하게 한다.
#
#   sane/bin/    scanimage.exe, 백엔드, 그리고 끌고 오는 DLL **전부 한 곳에**
#   sane/etc/sane.d/  백엔드 설정
#
# 백엔드를 `lib/sane/` 에 따로 두면 로드되지 않는다. dlfcn 의 `dlopen` 이
# `LOAD_WITH_ALTERED_SEARCH_PATH` 로 여는 탓에, 의존 DLL 검색이 실행 파일
# 디렉터리가 아니라 **그 백엔드 DLL 의 디렉터리**에서 시작하기 때문이다.
# genesys 는 libtiff 압축 스택까지 16개를 끌고 오므로 반드시 걸린다.
# 실측: 나눠 두면 "지정된 모듈을 찾을 수 없습니다", 합쳐 두면 장치가 나온다.
#
# 이름은 `cygsane-<backend>-1.dll` 이어야 한다. `dll.c` 가 Windows 에서 쓰는
# 접두사·접미사다 (spike E-1).
#   LICENSES/    GPL 전문과 고지
#   source/      GPL 대응 소스 — 배포 의무다
#
# 사용법: make-payload.sh <출력 디렉터리> <플러그인 exe 경로>
set -euo pipefail

OUT=${1:?출력 디렉터리를 달라}
PLUGIN=${2:?negaflow-scanner-sane.exe 경로를 달라}
PREFIX=${MINGW_PREFIX:-/c/msys64/ucrt64}
PRODUCT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"

# `ldd`가 백엔드의 모든 전이 DLL을 실제 UCRT64 트리에서 해석해야 한다.
# MSYS bash를 PowerShell에서 직접 실행하는 경우 PATH에 이 디렉터리가 빠질 수 있다.
export PATH="$PREFIX/bin:$PATH"

[ -x "$PLUGIN" ] || { echo "플러그인 실행 파일이 없다: $PLUGIN" >&2; exit 1; }
[ -x "$PREFIX/bin/scanimage.exe" ] || { echo "scanimage.exe 가 없다: $PREFIX" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/sane/bin" "$OUT/sane/etc/sane.d" "$OUT/LICENSES" "$OUT/source"

# --- 백엔드 -----------------------------------------------------------------
# `test` 는 넣지 않는다. detect 에 가짜 장치가 나타나면 I-17 과 충돌한다.
BACKENDS="genesys epson2 epsonds coolscan2 coolscan3"

echo "백엔드를 담는다: $BACKENDS"
for b in $BACKENDS; do
    src="$PREFIX/lib/sane/libsane-$b-1.dll"
    [ -f "$src" ] || { echo "  없다: $src" >&2; exit 1; }
    cp -f "$src" "$OUT/sane/bin/cygsane-$b-1.dll"
done

# dll.conf 는 우리가 쓴다. 담지 않은 백엔드를 적어두면 로드 실패 로그만 남는다.
for b in $BACKENDS; do echo "$b"; done > "$OUT/sane/etc/sane.d/dll.conf"
for b in $BACKENDS; do
    [ -f "$PREFIX/etc/sane.d/$b.conf" ] && cp -f "$PREFIX/etc/sane.d/$b.conf" "$OUT/sane/etc/sane.d/"
done

# --- 실행 파일과 DLL --------------------------------------------------------
cp -f "$PREFIX/bin/scanimage.exe" "$OUT/sane/bin/"
cp -f "$PLUGIN" "$OUT/"

# ldd 로 전이 의존을 모은다. `$PREFIX` 아래 있는 것만 담는다 — 시스템 DLL 은
# Windows 것이므로 재배포하지 않는다.
collect_deps () {
    ldd "$1" 2>/dev/null | awk -v p="$PREFIX" '
        { for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }
    ' | grep -F "$PREFIX" || true
}

{
    collect_deps "$PREFIX/bin/scanimage.exe"
    for b in $BACKENDS; do collect_deps "$PREFIX/lib/sane/libsane-$b-1.dll"; done
} | sort -u > "$OUT/.deps"

count=0
while read -r dll; do
    [ -f "$dll" ] || continue
    cp -f "$dll" "$OUT/sane/bin/"
    count=$((count + 1))
done < "$OUT/.deps"
rm -f "$OUT/.deps"
echo "DLL $count 개를 담았다"

# --- 라이선스와 소스 --------------------------------------------------------
cp -f "$REPO/COPYING" "$OUT/LICENSES/"
cp -f "$REPO/LICENSE" "$OUT/LICENSES/"
cp -f "$REPO/THIRD_PARTY_NOTICES.md" "$OUT/LICENSES/"
cp -f "$REPO/PROVENANCE.md" "$OUT/LICENSES/"

# GPL 바이너리를 배포하므로 대응 소스를 함께 싣는다. 빌드 중 생성된 소스 트리와
# 패키지 산출물까지 복사하지 않고, 재현에 필요한 레시피·원본 해시·패치만 넣는다.
mkdir -p "$OUT/source/sane-runtime/patches"
cp -f "$PRODUCT_ROOT/sane-runtime/PKGBUILD" "$OUT/source/sane-runtime/"
cp -f "$PRODUCT_ROOT/sane-runtime/SOURCES.md" "$OUT/source/sane-runtime/"
cp -f "$PRODUCT_ROOT/sane-runtime/patches/"*.patch "$OUT/source/sane-runtime/patches/"
git -C "$REPO" archive --format=tar --prefix=negaflow-scanner-sane/ HEAD \
    | gzip > "$OUT/source/negaflow-scanner-sane-source.tar.gz"

cat > "$OUT/source/README.txt" <<'TXT'
This directory carries the source that corresponds to the binaries shipped
here, as GPL-2.0-or-later requires.

  sane-runtime/       the SANE build recipe and patches applied to it,
                      and SOURCES.md, which records the upstream tarball URL
                      and its SHA-256.  Together they rebuild the exact
                      scanimage.exe and backend DLLs in sane/.
  negaflow-scanner-sane-source.tar.gz
                      the plugin's own source at the revision this build came
                      from.

The upstream SANE tarball itself is not copied here; sane-runtime/SOURCES.md
names it with a pinned hash so it can be fetched and verified.
TXT

# --- 매니페스트 -------------------------------------------------------------
# macOS 실행 파일에는 접미사가 없지만 Windows 호스트는 manifest 의 executable 을
# 정확한 상대 파일명으로 해석한다. 배포 payload 에만 .exe 를 적어 두어 두 플랫폼의
# 실행 파일명을 억지로 통일하지 않는다.
sed 's/"executable"[[:space:]]*:[[:space:]]*"negaflow-scanner-sane"/"executable": "negaflow-scanner-sane.exe"/' \
    "$PRODUCT_ROOT/manifest.json" > "$OUT/manifest.json"

echo
echo "배포물: $OUT"
du -sh "$OUT" 2>/dev/null | awk '{print "  크기: " $1}'
find "$OUT" -type f | wc -l | awk '{print "  파일: " $1 " 개"}'
