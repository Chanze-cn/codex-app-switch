#!/bin/sh
set -eu

if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <version> <download-url> <zip-path> <output-appcast>" >&2
    exit 64
fi

VERSION="$1"
DOWNLOAD_URL="$2"
ZIP_PATH="$3"
OUTPUT="$4"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGN_UPDATE="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"

if [ ! -x "$SIGN_UPDATE" ]; then
    echo "Missing Sparkle sign_update tool. Run: swift package resolve" >&2
    exit 1
fi

if [ ! -f "$ZIP_PATH" ]; then
    echo "Missing update archive: $ZIP_PATH" >&2
    exit 1
fi

SIGN_OUTPUT=""
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    KEY_FILE="$(mktemp)"
    trap 'rm -f "$KEY_FILE"' EXIT
    printf "%s" "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
    SIGN_OUTPUT="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$ZIP_PATH")"
else
    SIGN_OUTPUT="$("$SIGN_UPDATE" --account "${SPARKLE_KEY_ACCOUNT:-codex-profile-manager}" "$ZIP_PATH")"
fi

ED_SIGNATURE="$(printf "%s\n" "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -1)"
LENGTH="$(printf "%s\n" "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p' | head -1)"

if [ -z "$ED_SIGNATURE" ] || [ -z "$LENGTH" ]; then
    echo "Could not parse Sparkle signature output:" >&2
    printf "%s\n" "$SIGN_OUTPUT" >&2
    exit 1
fi

PUB_DATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"
RELEASE_NOTES_URL="https://github.com/Chanze-cn/codex-app-switch/releases/tag/v$VERSION"

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Codex Profile Manager Updates</title>
    <link>https://github.com/Chanze-cn/codex-app-switch</link>
    <description>Release updates for Codex Profile Manager.</description>
    <language>zh-cn</language>
    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>$RELEASE_NOTES_URL</sparkle:releaseNotesLink>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure
          url="$DOWNLOAD_URL"
          sparkle:edSignature="$ED_SIGNATURE"
          length="$LENGTH"
          type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

echo "Created $OUTPUT"
