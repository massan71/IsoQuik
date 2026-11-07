#!/bin/bash
# Builds IsoQuik.app without Xcode, using the Command Line Tools.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH="${ARCH:-$(uname -m)}"
APP="$ROOT/build/IsoQuik.app"

# With only the Command Line Tools, SDK 27 lacks the SwiftUIMacros plugin
# needed by SwiftUI macros. The SDK 26.5 bundled with the CLT works.
# If full Xcode is installed, use Xcode's default SDK.
if [ -z "${SDK:-}" ]; then
    DEVELOPER_DIR="$(xcode-select -p)"
    if [[ "$DEVELOPER_DIR" == *"/Xcode"* ]]; then
        SDK="$(xcrun --show-sdk-path)"
    elif [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ]; then
        SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
    else
        SDK="$(xcrun --show-sdk-path)"
    fi
fi

PLIST="$ROOT/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=(
    "$ROOT"/Sources/*.swift
    "$ROOT"/Sources/Services/*.swift
)

echo "Building IsoQuik ${VERSION} (${BUILD}) for ${ARCH} (macOS 14+)…"
swiftc \
    -O \
    -parse-as-library \
    -swift-version 5 \
    -sdk "$SDK" \
    -target "${ARCH}-apple-macos14.0" \
    "${SOURCES[@]}" \
    -o "$APP/Contents/MacOS/IsoQuik"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

# The debug symbol bundle (if any) is not needed in the app and may carry
# extended attributes that break ad-hoc signing.
rm -rf "$APP/Contents/MacOS/IsoQuik.dSYM"

# Extended attributes (e.g. com.apple.provenance, FinderInfo) break
# ad-hoc signing, especially in folders managed by a file provider.
SIGNED=0
for _ in 1 2 3; do
    xattr -cr "$APP" 2>/dev/null || true
    if codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null 2>&1; then
        SIGNED=1
        break
    fi
done

if [ "$SIGNED" -eq 0 ]; then
    echo "Warning: ad-hoc signing failed. The app may still launch." >&2
fi

echo "Created: $APP"
echo "Launch:  open \"$APP\""
