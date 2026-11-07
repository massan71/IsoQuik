#!/bin/bash
# Generates Resources/AppIcon.icns from a CoreGraphics/AppKit drawing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swift "$ROOT/Tools/make_icon.swift" "$TMP/icon_1024.png" >/dev/null

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

emit() {
    local pixels="$1"
    local name="$2"
    sips -z "$pixels" "$pixels" "$TMP/icon_1024.png" --out "$ICONSET/icon_${name}.png" >/dev/null
}

emit 16   "16x16"
emit 32   "16x16@2x"
emit 32   "32x32"
emit 64   "32x32@2x"
emit 128  "128x128"
emit 256  "128x128@2x"
emit 256  "256x256"
emit 512  "256x256@2x"
emit 512  "512x512"
emit 1024 "512x512@2x"

iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "Created: $ROOT/Resources/AppIcon.icns"
