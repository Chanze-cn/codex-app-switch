#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/Build/CodexProfileManager.app"

swift build -c release
"$ROOT/Scripts/generate_icon.swift" "$ROOT/Support/AppIcon.icns"
rm -rf "$BUILD"
mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Resources"
cp "$ROOT/.build/release/CodexProfileManager" "$BUILD/Contents/MacOS/CodexProfileManager"
cp "$ROOT/Support/Info.plist" "$BUILD/Contents/Info.plist"
cp "$ROOT/Support/AppIcon.icns" "$BUILD/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$BUILD"
echo "Built $BUILD"
