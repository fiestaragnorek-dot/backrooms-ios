#!/usr/bin/env bash
set -euo pipefail

# Local unsigned IPA build for SideStore/AltStore-style signing.
# Requirements on Mac:
#   - Xcode installed
#   - Xcode command line tools selected
#   - XcodeGen: brew install xcodegen

APP_NAME="Backrooms"
PROJECT="Backrooms.xcodeproj"
SCHEME="Backrooms"
DERIVED="build"
CONFIG="Release"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "ERROR: xcodebuild not found. Install Xcode first."
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: xcodegen not found. Install it with: brew install xcodegen"
  exit 1
fi

echo "==> Xcode version"
xcodebuild -version

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building unsigned app"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  EXPANDED_CODE_SIGN_IDENTITY="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  ENABLE_BITCODE=NO \
  ONLY_ACTIVE_ARCH=NO \
  clean build

APP_PATH="$(find "$DERIVED/Build/Products/${CONFIG}-iphoneos" -name "${APP_NAME}.app" -type d | head -1)"
if [[ -z "$APP_PATH" ]]; then
  echo "ERROR: ${APP_NAME}.app not found"
  exit 1
fi

echo "==> Packaging IPA"
rm -rf Payload "${APP_NAME}.ipa"
mkdir -p Payload
cp -R "$APP_PATH" Payload/
zip -qr "${APP_NAME}.ipa" Payload
rm -rf Payload

echo "==> Done: ${APP_NAME}.ipa"
ls -lh "${APP_NAME}.ipa"
