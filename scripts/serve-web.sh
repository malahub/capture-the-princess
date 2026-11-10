#!/usr/bin/env bash
# Serve build/web with correct MIME types for .wasm/.pck.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 scripts/serve-web-build.py build/web --port "${1:-8080}"
