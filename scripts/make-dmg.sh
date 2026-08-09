#!/bin/bash
# Build a drag-to-Applications DMG at build/Plynn.dmg.
# For public distribution, run scripts/notarize.sh on the app FIRST.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/make-app.sh

VERSION=$(defaults read "$PWD/build/Plynn.app/Contents/Info" CFBundleShortVersionString)
STAGE="build/dmg-stage"
DMG="build/Plynn.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto build/Plynn.app "$STAGE/Plynn.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Plynn $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGE"
echo "Created $DMG (version $VERSION)"
