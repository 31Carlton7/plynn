#!/bin/bash
# Full release: build → notarize → DMG → signed appcast → GitHub release.
# Prereqs: notarytool profile "plynn-notary" stored, Sparkle EdDSA key in
# Keychain, gh CLI authed. Version comes from scripts/Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" scripts/Info.plist)
TAG="v$VERSION"

./scripts/make-app.sh
./scripts/notarize.sh
SKIP_BUILD=1 ./scripts/make-dmg.sh

# Sparkle appcast: sign the DMG with the EdDSA key and emit appcast.xml.
RELEASE_DIR="build/release-$VERSION"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
cp build/Plynn.dmg "$RELEASE_DIR/"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast "$RELEASE_DIR" \
  --download-url-prefix "https://github.com/31Carlton7/plynn/releases/download/$TAG/"

gh release create "$TAG" \
  "$RELEASE_DIR/Plynn.dmg" "$RELEASE_DIR/appcast.xml" \
  --title "Plynn $VERSION" --generate-notes
echo "Released $TAG"
