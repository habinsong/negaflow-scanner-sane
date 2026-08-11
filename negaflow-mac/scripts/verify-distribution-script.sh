#!/usr/bin/env bash
set -euo pipefail

# Distribution.xml 의 installation_check() 는 Installer 가 설치를 시작하기 전에 돌린다.
# 여기서 JS 가 터지면 Installer 는 조용히 넘어가거나 원인 없는 실패 화면을 띄우고,
# 사용자는 install.log 를 뒤지기 전에는 이유를 알 수 없다. 그래서 실제 엔진
# (JavaScriptCore) 에 같은 코드를 올려 분기별로 돌려 본다.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISTRIBUTION="${1:-$ROOT/Installer/Distribution.xml}"

if [[ ! -s "$DISTRIBUTION" ]]; then
  echo "[verify-distribution-script] ERROR: distribution file is missing: $DISTRIBUTION" >&2
  exit 1
fi

WORK="$(mktemp -d /tmp/negaflow-distribution-script.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

SCRIPT_JS="$WORK/distribution.js"
awk '/<script>/{flag=1; next} /<\/script>/{flag=0} flag' "$DISTRIBUTION" \
  | sed -e 's/&amp;/\&/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' >"$SCRIPT_JS"

if [[ ! -s "$SCRIPT_JS" ]]; then
  echo "[verify-distribution-script] ERROR: distribution script block is empty." >&2
  exit 1
fi

CLT_GIT="/Library/Developer/CommandLineTools/usr/bin/git"
XCODE_GIT="/Applications/Xcode.app/Contents/Developer/usr/bin/git"
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
XCODE_SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.sdk"

# 이름, macOS 버전, 존재하는 경로들, 기대 결과, 기대 제목 조각.
run_case() {
  local name="$1"
  local product_version="$2"
  local files="$3"
  local expected_result="$4"
  local expected_title="$5"

  local harness="$WORK/case.js"
  {
    printf 'var STUB_VERSION = %s;\n' "$product_version"
    printf 'var STUB_FILES = [%s];\n' "$files"
    cat <<'PRELUDE'
var system = {
    version: { ProductVersion: STUB_VERSION },
    files: {
        fileExistsAtPath: function (path) {
            return STUB_FILES.indexOf(path) !== -1;
        }
    },
    sysctl: function () { return "1"; }
};
var my = { result: {} };
PRELUDE
    cat "$SCRIPT_JS"
    # 결과는 한 줄로 낸다. 파서를 붙이면 러너에 무엇이 깔려 있는지에 검증이 매인다.
    cat <<'EPILOGUE'
String(installation_check()) + "\t" + (my.result.title || "");
EPILOGUE
  } >"$harness"

  local output
  if ! output="$(osascript -l JavaScript "$harness" 2>&1)"; then
    echo "[verify-distribution-script] ERROR: $name: script raised an error:" >&2
    echo "$output" >&2
    exit 1
  fi

  local actual_result="${output%%$'\t'*}"
  local actual_title="${output#*$'\t'}"
  if [[ "$actual_result" != "$expected_result" ]]; then
    echo "[verify-distribution-script] ERROR: $name: expected $expected_result, got '$actual_result'" >&2
    echo "$output" >&2
    exit 1
  fi

  if [[ -n "$expected_title" && "$actual_title" != *"$expected_title"* ]]; then
    echo "[verify-distribution-script] ERROR: $name: title '$actual_title' lacks '$expected_title'" >&2
    exit 1
  fi

  echo "[verify-distribution-script] ok: $name"
}

# 최신 Command Line Tools: 통과한다.
run_case "current command line tools" \
  '"26.5"' "\"$CLT_GIT\", \"$CLT_SDK\"" true ""

# Xcode 만 있는 경우도 통과한다.
run_case "xcode only" \
  '"26.5"' "\"$XCODE_GIT\", \"$XCODE_SDK\"" true ""

# 2026-08-12 에 실제로 설치를 실패시킨 상태다. git 은 있는데 현재 macOS 의 SDK 가 없다.
run_case "outdated command line tools" \
  '"26.5"' "\"$CLT_GIT\"" false "out of date"

# Command Line Tools 자체가 없는 경우.
run_case "missing command line tools" \
  '"26.5"' "" false "are required"

# macOS 14 계열에서도 그 세대의 SDK 를 본다.
run_case "sonoma sdk" \
  '"14.7"' "\"$CLT_GIT\", \"/Library/Developer/CommandLineTools/SDKs/MacOSX14.sdk\"" true ""

# 버전 문자열을 못 읽으면 막지 않는다. 여기서 예외를 던지면 설치가 통째로 막힌다.
run_case "unknown product version" \
  'null' "\"$CLT_GIT\"" true ""

echo "[verify-distribution-script] valid: $DISTRIBUTION"
