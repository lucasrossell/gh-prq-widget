#!/usr/bin/env bash
# Builds "PR Queue.app" (universal: Apple silicon + Intel) into macos/build/.
#
#   VERSION=0.1.0 scripts/build-app.sh
#
# Signs with SIGN_IDENTITY if set (e.g. "Developer ID Application: …"); otherwise ad hoc,
# which is fine for running it on the Mac that built it.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0-dev}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="build/PR Queue.app"

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PRQueue" "$APP/Contents/MacOS/PRQueue"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    # Hardened runtime and a secure timestamp are both required for notarization.
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "build/PR-Queue-$VERSION.zip"
echo "Built $APP and build/PR-Queue-$VERSION.zip"
