#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/Build/CodexProfileManager.app"
SPARKLE_FRAMEWORK="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGN_OPTIONS=""
if [ "$SIGN_IDENTITY" != "-" ]; then
    SIGN_OPTIONS="--options runtime"
fi

swift build -c release
"$ROOT/Scripts/generate_icon.swift" "$ROOT/Support/AppIcon.icns"
rm -rf "$BUILD"
mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Resources" "$BUILD/Contents/Frameworks"
cp "$ROOT/.build/release/CodexProfileManager" "$BUILD/Contents/MacOS/CodexProfileManager"
cp "$ROOT/Support/Info.plist" "$BUILD/Contents/Info.plist"
cp "$ROOT/Support/AppIcon.icns" "$BUILD/Contents/Resources/AppIcon.icns"
if ! otool -l "$BUILD/Contents/MacOS/CodexProfileManager" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$BUILD/Contents/MacOS/CodexProfileManager"
fi
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    ditto "$SPARKLE_FRAMEWORK" "$BUILD/Contents/Frameworks/Sparkle.framework"
else
    echo "Missing Sparkle.framework. Run: swift package resolve" >&2
    exit 1
fi
codesign --force --deep $SIGN_OPTIONS --sign "$SIGN_IDENTITY" "$BUILD/Contents/Frameworks/Sparkle.framework"
codesign --force --deep $SIGN_OPTIONS --sign "$SIGN_IDENTITY" "$BUILD"
echo "Built $BUILD"
