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
# Vela.entitlements turns off macOS "library validation" so Sparkle loads in
# builds signed to run locally (those have no team ID). With a real
# certificate, Vela and Sparkle share one team ID, so library validation can
# stay on: macOS then refuses to load any code into Vela that isn't signed by
# the same team (or by Apple).
ENTITLEMENTS="$(mktemp -t vela-entitlements).plist"
cp "$ROOT/Vela.entitlements" "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Delete :com.apple.security.cs.disable-library-validation" "$ENTITLEMENTS" 2>/dev/null || true
"${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"
rm -f "$ENTITLEMENTS"
codesign --verify --deep --strict "$APP"

# With library validation on, Vela only launches if Sparkle carries the same
# team ID, so stop the release here rather than ship an app that won't open.
team_of() { codesign -dv "$1" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}'; }
APP_TEAM="$(team_of "$APP")"
if [[ -z "$APP_TEAM" || "$APP_TEAM" == "not set" ]]; then
  echo "✗ $IDENTITY has no team ID, so Vela couldn't load Sparkle with library validation on." >&2
  exit 1
fi
if [[ -d "$SPARKLE" ]]; then
  for part in "$SPARKLE" "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app"; do
    if [[ "$(team_of "$part")" != "$APP_TEAM" ]]; then
      echo "✗ $part isn't signed by team $APP_TEAM, so Vela would refuse to load it." >&2
      exit 1
    fi
  done
fi
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q disable-library-validation; then
  echo "✗ Library validation is still turned off in the signed app." >&2
  exit 1
fi
echo "✓ Library validation is on (team $APP_TEAM)"
echo "✓ Signed with $IDENTITY"
