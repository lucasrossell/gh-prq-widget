#!/usr/bin/env bash
# Notarizes and staples the app built by build-app.sh, then re-zips it.
#
#   APPLE_ID=… APPLE_TEAM_ID=… APPLE_APP_PASSWORD=… VERSION=0.1.0 scripts/notarize.sh
#
# APPLE_APP_PASSWORD is an app-specific password from account.apple.com, not the Apple ID password.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${APPLE_ID:?}" "${APPLE_TEAM_ID:?}" "${APPLE_APP_PASSWORD:?}"
VERSION="${VERSION:-0.0.0-dev}"
APP="build/PR Queue.app"
ZIP="build/PR-Queue-$VERSION.zip"

xcrun notarytool submit "$ZIP" \
    --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" \
    --wait --timeout 30m

# Stapling attaches the ticket so Gatekeeper doesn't need to look it up online.
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"

rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Notarized $ZIP"
