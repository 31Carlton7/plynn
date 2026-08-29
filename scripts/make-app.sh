#!/bin/bash
# Build a Sequoia 15 / Intel .app with Command Line Tools (no Xcode 26, no MLX).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Plynn

BIN="$(swift build -c release --show-bin-path)/Plynn"
APP="build/Plynn.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Plynn"
cp scripts/Info.plist "$APP/Contents/Info.plist"
if [[ -f scripts/AppIcon.icns ]]; then
  cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign so TCC (mic / speech / accessibility) can attach to the bundle.
# Skip --options runtime: hardened runtime + ad-hoc often blocks the event tap
# on Sequoia without a Developer ID.
codesign --force --deep \
  --entitlements scripts/plynn.entitlements \
  --sign - "$APP"

echo "Built $APP (Intel / macOS 15, Apple Speech on-device)"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Plynn.app
  ditto "$APP" /Applications/Plynn.app
  echo "Installed to /Applications/Plynn.app"
fi
