#!/bin/bash
# Signs a finished Vela.app with a real certificate (your Apple Development
# certificate), inside-out: Sparkle's helper programs first, then Sparkle,
# then Vela itself. The release pipeline uses this when the MAC_CERT_P12
# secret is set.
#
#   scripts/sign-app.sh build/Release/Vela.app "Apple Development: Morgan (ABCDE12345)"
#
# Why bother? macOS remembers permissions (Full Disk Access, Keychain items)
# by *who signed* the app. With a real certificate, every update is signed by
# the same "who", so those permissions carry over. Builds signed "to run
# locally" get a new identity every time, and macOS asks again after each update.
set -euo pipefail

APP="$1"
IDENTITY="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
SIGN=(codesign --force --options runtime --timestamp=none --sign "$IDENTITY")

if [[ -d "$SPARKLE" ]]; then
  B="$SPARKLE/Versions/B"
  [[ -d "$B/XPCServices/Installer.xpc" ]] && "${SIGN[@]}" "$B/XPCServices/Installer.xpc"
  [[ -d "$B/XPCServices/Downloader.xpc" ]] && "${SIGN[@]}" --preserve-metadata=entitlements "$B/XPCServices/Downloader.xpc"
  "${SIGN[@]}" "$B/Autoupdate"
  "${SIGN[@]}" "$B/Updater.app"
  "${SIGN[@]}" "$SPARKLE"
fi
"${SIGN[@]}" --entitlements "$ROOT/Vela.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
echo "✓ Signed with $IDENTITY"
