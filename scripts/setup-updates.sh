#!/bin/bash
# One-time setup for Vela's self-updates. Run it on your Mac from the
# VelaBrowser folder:
#
#   bash scripts/setup-updates.sh
#
# It makes the **update signing key**, a pair of matching keys:
#   • The private key signs each new version. It's saved in your Mac's
#     Keychain and copied into a GitHub secret, so the release pipeline can
#     sign builds. It never goes into the code.
#   • The public key goes into Vela-Info.plist. Vela uses it to check that an
#     update really came from your pipeline before installing it.
#
# If you already ran this, it reuses the same key (making a new one would
# stop existing copies of Vela from accepting updates).
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="mlovelace112-maker/VelaBrowser"
SECRETS_PAGE="https://github.com/$REPO/settings/secrets/actions"
PACKAGES="$PWD/build/SourcePackages"

echo "▸ Downloading Sparkle (the updater) to get its key tool…"
xcodebuild -resolvePackageDependencies -project Vela.xcodeproj -scheme Vela \
  -clonedSourcePackagesDirPath "$PACKAGES" >/dev/null
GENERATE_KEYS=$(find "$PACKAGES" -type f -name generate_keys -path '*/bin/*' | head -1)
if [[ ! -x "$GENERATE_KEYS" ]]; then
  echo "✗ Couldn't find Sparkle's generate_keys tool in $PACKAGES"
  exit 1
fi

echo "▸ Making the update signing key (or reusing the one in your Keychain)…"
echo "  If macOS asks to use your Keychain, click Always Allow."
"$GENERATE_KEYS" >/dev/null
PUBLIC_KEY=$("$GENERATE_KEYS" -p)

KEYFILE=$(mktemp)
trap 'rm -f "$KEYFILE"' EXIT
rm -f "$KEYFILE"
"$GENERATE_KEYS" -x "$KEYFILE" >/dev/null

echo "▸ Saving the private key as the GitHub secret SPARKLE_PRIVATE_KEY…"
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO" < "$KEYFILE"
  echo "  ✓ Saved with the GitHub command-line tool."
else
  pbcopy < "$KEYFILE"
  echo "  The private key is now on your clipboard. In the page that opens:"
  echo "    1. Click \"New repository secret\"."
  echo "    2. Name: SPARKLE_PRIVATE_KEY"
  echo "    3. Secret: paste (⌘V), then click \"Add secret\"."
  open "$SECRETS_PAGE/new"
  read -r -p "  Press Return once the secret is saved… "
  echo -n "" | pbcopy
  echo "  ✓ Clipboard cleared."
fi

echo
echo "✓ Done. Last step: send Claude this public key (it's safe to share),"
echo "  and it will go into Vela-Info.plist:"
echo
echo "    $PUBLIC_KEY"
echo
echo "Optional, but recommended: also save your Apple Development certificate as"
echo "a secret, so macOS keeps Full Disk Access and Keychain permission after"
echo "each update: run  bash scripts/setup-certificate.sh"
