#!/bin/bash
# Notarize build/Plynn.app with Apple, then staple the ticket.
#
# ONE-TIME SETUP (needs your Apple ID + an app-specific password from
# appleid.apple.com, and your Team ID FY9QB79VAP):
#   xcrun notarytool store-credentials plynn-notary \
#     --apple-id you@example.com --team-id FY9QB79VAP
#
# Then: ./scripts/notarize.sh   (afterwards run make-dmg.sh to package)
set -euo pipefail
cd "$(dirname "$0")/.."

ZIP="build/Plynn-notarize.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Plynn.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile plynn-notary --wait
xcrun stapler staple build/Plynn.app
rm -f "$ZIP"
echo "Notarized and stapled build/Plynn.app"
