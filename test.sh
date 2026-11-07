#!/bin/bash
# Non-destructive tests: build, ISO parsing, device enumeration, startup disk detection.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH="$(uname -m)"
OUT="$ROOT/build"

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

mkdir -p "$OUT"

echo "1/2  Building self-test"
swiftc \
    -parse-as-library \
    -swift-version 5 \
    -sdk "$SDK" \
    -target "${ARCH}-apple-macos14.0" \
    "$ROOT"/Sources/Models.swift \
    "$ROOT"/Sources/Services/*.swift \
    "$ROOT"/Tests/SelfTest.swift \
    -o "$OUT/selftest"

echo "2/2  Running self-test"
"$OUT/selftest" "$@"

echo "OK"
