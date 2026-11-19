#!/bin/bash
# One-time: saves your Apple Development certificate as GitHub secrets, so the
# release pipeline signs every update as *you*. macOS then keeps Vela's Full
# Disk Access and Keychain permission across updates.
#
#   bash scripts/setup-certificate.sh
#
# What it does:
#   1. Finds the "Apple Development: …" certificate in your Keychain. If you
#      don't have one, it tells you how to make one in Xcode (free).
#   2. Exports just that certificate and its private key, locked with a random
#      password, to a temporary file. (macOS will ask you to allow this.)
#   3. Saves the file as the secret MAC_CERT_P12 and the password as
#      MAC_CERT_PASSWORD, then deletes the file.
set -euo pipefail

REPO="mlovelace112-maker/VelaBrowser"
SECRETS_PAGE="https://github.com/$REPO/settings/secrets/actions"

echo "▸ Looking for your Apple Development certificate…"
IDENTITIES=$(security find-identity -v -p codesigning | grep '"Apple Development' || true)
if [[ -z "$IDENTITIES" ]]; then
  cat <<'MSG'
✗ No Apple Development certificate found. To make one (it's free):
    1. Open Xcode ▸ Settings ▸ Accounts. Add your Apple ID with + if it isn't there.
    2. Select your Apple ID ▸ Manage Certificates… ▸ + ▸ Apple Development ▸ Done.
  Then run this script again.
MSG
  exit 1
fi
COUNT=$(echo "$IDENTITIES" | wc -l | tr -d ' ')
if [[ "$COUNT" -gt 1 ]]; then
  echo "  You have $COUNT. Pick one:"
  echo "$IDENTITIES" | awk -F'"' '{print "    " NR ") " $2}'
  read -r -p "  Number: " PICK
  LINE=$(echo "$IDENTITIES" | sed -n "${PICK}p")
else
  LINE="$IDENTITIES"
fi
HASH=$(echo "$LINE" | awk '{print $2}')
NAME=$(echo "$LINE" | awk -F'"' '{print $2}')
[[ -n "$HASH" ]] || { echo "✗ That wasn't one of the choices."; exit 1; }
echo "  ✓ $NAME"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
P12="$WORK/vela.p12"
PASSWORD=$(uuidgen)

# A tiny Swift program exports exactly one certificate (the command-line
# "security export" can only export all of them at once).
cat > "$WORK/export.swift" <<'SWIFT'
import CryptoKit
import Foundation
import Security

let wantedHash = CommandLine.arguments[1].uppercased()
let password = CommandLine.arguments[2]
let outPath = CommandLine.arguments[3]

let query: [String: Any] = [
    kSecClass as String: kSecClassIdentity,
    kSecMatchLimit as String: kSecMatchLimitAll,
    kSecReturnRef as String: true,
]
var found: CFTypeRef?
guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
      let identities = found as? [SecIdentity] else {
    print("✗ Couldn't read your Keychain."); exit(1)
}
let identity = identities.first { identity in
    var certificate: SecCertificate?
    guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { return false }
    let data = SecCertificateCopyData(certificate) as Data
    let hash = Insecure.SHA1.hash(data: data).map { String(format: "%02X", $0) }.joined()
    return hash == wantedHash
}
guard let identity else { print("✗ Couldn't find that certificate's private key."); exit(1) }

var parameters = SecItemImportExportKeyParameters()
parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
parameters.passphrase = Unmanaged.passRetained(password as AnyObject)
var exported: CFData?
let status = SecItemExport(identity, .formatPKCS12, [], &parameters, &exported)
guard status == errSecSuccess, let exported else {
    print("✗ Export failed (\(status)). If macOS asked to allow it, click Allow and try again."); exit(1)
}
try (exported as Data).write(to: URL(fileURLWithPath: outPath))
SWIFT

echo "▸ Exporting it (if macOS asks to allow access to the key, click Allow)…"
swift "$WORK/export.swift" "$HASH" "$PASSWORD" "$P12"

echo "▸ Saving the GitHub secrets MAC_CERT_P12 and MAC_CERT_PASSWORD…"
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  base64 -i "$P12" | gh secret set MAC_CERT_P12 --repo "$REPO"
  printf '%s' "$PASSWORD" | gh secret set MAC_CERT_PASSWORD --repo "$REPO"
  echo "  ✓ Saved with the GitHub command-line tool."
else
  open "$SECRETS_PAGE/new"
  base64 -i "$P12" | pbcopy
  echo "  In the page that opened, click \"New repository secret\":"
  echo "    Name: MAC_CERT_P12      Secret: paste (⌘V)   ▸ Add secret"
  read -r -p "  Press Return when that's saved… "
  printf '%s' "$PASSWORD" | pbcopy
  echo "  Now add one more secret (click \"New repository secret\" again):"
  echo "    Name: MAC_CERT_PASSWORD Secret: paste (⌘V)   ▸ Add secret"
  read -r -p "  Press Return when that's saved… "
  echo -n "" | pbcopy
  echo "  ✓ Clipboard cleared."
fi

echo
echo "✓ Done. From the next release on, updates are signed as \"$NAME\"."
echo "  The exported file has been deleted; your certificate stays in your Keychain."
