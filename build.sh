#!/usr/bin/env bash
# Heavy Flag — local build. Export is produced here, never in CI.
#   ./build.sh          -> build/web/
set -euo pipefail
cd "$(dirname "$0")"

echo "== parse gate"
OUT=$(godot --headless --path . --quit-after 40 2>&1 || true)
if echo "$OUT" | grep -qE 'SCRIPT ERROR|Parse Error'; then
	echo "$OUT" | grep -E 'SCRIPT ERROR|Parse Error' -A2 | head -20
	echo "BUILD BLOCKED: fix the parse errors above"
	exit 1
fi
echo "   clean"

mkdir -p build/web
touch build/.gdignore

echo "== import"
godot --headless --path . --import >/dev/null 2>&1 || true

echo "== export"
godot --headless --path . --export-release "Web" "$PWD/build/web/index.html"

if [ ! -f build/web/index.wasm ]; then
	echo "FAIL: no index.wasm — check the Web preset and export templates"
	exit 1
fi
echo
echo "== artifacts"
ls -lh build/web | tail -n +2 | awk '{printf "  %-28s %s\n", $9, $5}'
echo
echo "serve: python3 scripts/serve-web.sh"

# the export writes the project name into the shell; keep the shipped title in step
sed -i 's|<title>Heavy Flag</title>|<title>Capture The Princess</title>|' build/web/index.html
sed -i 's|"projectName": *"Heavy Flag"|"projectName": "Capture The Princess"|' build/web/index.html
