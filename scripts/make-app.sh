#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
IDENTITY="${IDENTITY:-Developer ID Application: Carlton Aikins (FY9QB79VAP)}"

# MLX's Metal shaders only compile under xcodebuild — SwiftPM CLI builds ship
# no metallib and the LLM dies at runtime (see mlx-swift README).
xcodebuild build -scheme Plynn -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData -quiet

BUILT="build/DerivedData/Build/Products/Release"
APP="build/Plynn.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILT/Plynn" "$APP/Contents/MacOS/Plynn"
# SPM resource bundles (incl. mlx-swift_Cmlx.bundle with mlx.metallib) resolve
# via Bundle.main.resourceURL inside an .app — they belong in Contents/Resources.
for b in "$BUILT"/*.bundle; do
  cp -R "$b" "$APP/Contents/Resources/"
done
cp scripts/Info.plist "$APP/Contents/Info.plist"
codesign --force --options runtime --deep \
  --entitlements scripts/plynn.entitlements \
  --sign "$IDENTITY" "$APP"
echo "Built and signed $APP"
