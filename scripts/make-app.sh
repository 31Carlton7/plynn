#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
IDENTITY="${IDENTITY:-Developer ID Application: Carlton Aikins (FY9QB79VAP)}"
swift build -c release
APP="build/Plynn.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/PlynnSpike "$APP/Contents/MacOS/Plynn"
cp scripts/Info.plist "$APP/Contents/Info.plist"
codesign --force --options runtime \
  --entitlements scripts/plynn.entitlements \
  --sign "$IDENTITY" "$APP"
echo "Built and signed $APP"
