#!/bin/bash
# Builds IsoQuik.app and packages it as build/IsoQuik-<version>.dmg,
# with an Applications shortcut for drag-and-drop installation.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
DMG="$ROOT/build/IsoQuik-$VERSION.dmg"

"$ROOT/build.sh"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$ROOT/build/IsoQuik.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "IsoQuik $VERSION" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$DMG" >/dev/null

hdiutil verify "$DMG" >/dev/null
echo "Created: $DMG"
