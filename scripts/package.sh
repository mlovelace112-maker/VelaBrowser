#!/bin/bash
# Builds a finished copy of Vela and wraps it in a disk image.
#
#   ./scripts/package.sh                 build Vela.app and Vela-<version>.dmg in ./build
#   ./scripts/package.sh --install       …and copy Vela.app into /Applications
#   TEAM=ABCDE12345 ./scripts/package.sh  sign with your free Apple ID team (recommended:
#                                        Full Disk Access and Keychain access then
#                                        survive future updates)
#
# Find your team ID in Xcode ▸ Settings ▸ Accounts, or in the project's
# Signing & Capabilities tab.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build"
INSTALL=false
[[ "${1:-}" == "--install" ]] && INSTALL=true

SIGNING=(CODE_SIGN_IDENTITY="-")
if [[ -n "${TEAM:-}" ]]; then
  SIGNING=(DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="Apple Development" CODE_SIGN_STYLE=Automatic)
  echo "▸ Signing with team $TEAM"
else
  echo "▸ Signing to run locally (set TEAM=… to sign with your Apple ID)"
fi

echo "▸ Building Vela (Release)…"
rm -rf "$BUILD"
xcodebuild \
  -project Vela.xcodeproj \
  -target Vela \
  -configuration Release \
  SYMROOT="$BUILD" \
  -allowProvisioningUpdates \
  "${SIGNING[@]}" \
  build | grep -E "^(\*\*|error|warning: .*Vela)" || true

APP="$BUILD/Release/Vela.app"
if [[ ! -d "$APP" ]]; then
  echo "✗ The build failed. Open Vela.xcodeproj in Xcode and press ⌘B to see the errors."
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$BUILD/Vela-$VERSION.dmg"

echo "▸ Making $DMG…"
STAGING="$BUILD/dmg"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Vela.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Vela $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

if $INSTALL; then
  echo "▸ Installing to /Applications…"
  osascript -e 'tell application "Vela" to quit' 2>/dev/null || true
  sleep 1
  rm -rf "/Applications/Vela.app"
  ditto "$APP" "/Applications/Vela.app"
  # Tell macOS about the new copy so it shows up as a browser choice.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Vela.app" || true
  open "/Applications/Vela.app"
fi

echo "✓ Done"
echo "  App:        $APP"
echo "  Disk image: $DMG"
