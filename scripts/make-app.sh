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
# Sparkle ships as a binary framework; it must live in Contents/Frameworks.
mkdir -p "$APP/Contents/Frameworks"
SPARKLE=$(find build/DerivedData -type d -name "Sparkle.framework" -not -path "*dSYM*" | head -1)
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
cp scripts/Info.plist "$APP/Contents/Info.plist"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Plynn" 2>/dev/null || true
codesign --force --options runtime \
  --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --deep \
  --entitlements scripts/plynn.entitlements \
  --sign "$IDENTITY" "$APP"
echo "Built and signed $APP"

# --install: replace the copy in /Applications (relaunch is the caller's job).
if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Plynn.app
  ditto "$APP" /Applications/Plynn.app
  echo "Installed to /Applications/Plynn.app"
fi
