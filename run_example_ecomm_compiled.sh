#!/usr/bin/env bash
set -euo pipefail

# Directories
ROOT="."
ECOMM="$ROOT/examples/ecomm"
COMPILED="$ECOMM/compiled"
TPLS_OUT="$COMPILED/tpls"

# Clear generated templates
echo "==> Clearing generated templates in $TPLS_OUT..."
rm -rf "$TPLS_OUT"
mkdir "$TPLS_OUT"

# Generate templates (auto-detects layouts, pages, and standalone files)
echo "==> Generating templates..."
odin run cli -- \
  -src="$ECOMM/tpls" \
  -dest="$TPLS_OUT" \
  -pkg=tpls

echo "==> Generated files:"
ls -1 "$TPLS_OUT"/*.odin

# 4. Build and run the compiled server
echo "==> Building compiled server..."
odin build "$COMPILED" -collection:ohtml="$ROOT" -out:"$COMPILED/server"

echo "==> Starting server..."
"$COMPILED/server"
