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
#
# The GitHub release pipeline runs this same script, and also sets:
#   VERSION=1.2       the version people see (default: MARKETING_VERSION in Xcode)
#   BUILD_NUMBER=142  the number the updater compares (must always go up)
# It also makes Vela-<version>.zip, the file the updater downloads.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build"
INSTALL=false
[[ "${1:-}" == "--install" ]] && INSTALL=true

VERSIONING=()
[[ -n "${VERSION:-}" ]] && VERSIONING+=(MARKETING_VERSION="$VERSION")
[[ -n "${BUILD_NUMBER:-}" ]] && VERSIONING+=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER")

SIGNING=(CODE_SIGN_IDENTITY="-")
if [[ -n "${TEAM:-}" ]]; then
  SIGNING=(DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="Apple Development" CODE_SIGN_STYLE=Automatic)
  echo "▸ Signing with team $TEAM"
else
  echo "▸ Signing to run locally (set TEAM=… to sign with your Apple ID)"
fi

echo "▸ Building Vela (Release)…"
rm -rf "$BUILD"
# On GitHub (CI is set), show the full log so build errors are easy to read.
FILTER=(grep -E "^(\*\*|error|warning: .*Vela)")
[[ -n "${CI:-}" ]] && FILTER=(cat)
# Sparkle (the updater) comes from Swift Package Manager, which needs a scheme.
# SourcePackages is kept in ./build so the release pipeline can find
# Sparkle's signing tool there.
set +e
xcodebuild \
  -project Vela.xcodeproj \
  -scheme Vela \
  -configuration Release \
  -clonedSourcePackagesDirPath "$BUILD/SourcePackages" \
  SYMROOT="$BUILD" \
  -allowProvisioningUpdates \
  "${SIGNING[@]}" \
  ${VERSIONING[@]+"${VERSIONING[@]}"} \
  build | "${FILTER[@]}"
# The exit status of xcodebuild itself (not of the filter after it).
STATUS=${PIPESTATUS[0]}
set -e

APP="$BUILD/Release/Vela.app"
# Xcode creates Vela.app before compiling, so an app folder alone doesn't
# mean the build worked. Check xcodebuild's result and the program inside.
if [[ $STATUS -ne 0 || ! -x "$APP/Contents/MacOS/Vela" ]]; then
  echo "✗ The build failed. Open Vela.xcodeproj in Xcode and press ⌘B to see the errors."
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$BUILD/Vela-$VERSION.dmg"

# The updater downloads a zip ("ditto" keeps the app's signature intact).
ZIP="$BUILD/Vela-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Making ${DMG}…"
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
echo "  Update zip: $ZIP"
