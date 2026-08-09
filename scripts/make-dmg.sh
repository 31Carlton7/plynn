#!/bin/bash
# Build a drag-to-Applications DMG at build/Plynn.dmg.
# For public distribution, run scripts/notarize.sh on the app FIRST.
set -euo pipefail
cd "$(dirname "$0")/.."

# SKIP_BUILD=1 packages the existing build/Plynn.app as-is — required after
# notarize.sh, since rebuilding would discard the stapled ticket.
if [[ "${SKIP_BUILD:-}" != "1" ]]; then
  ./scripts/make-app.sh
fi

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
