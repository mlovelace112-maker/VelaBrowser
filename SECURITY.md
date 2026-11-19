# Security

## Reporting a problem

Please don't open a public issue for a security problem. Use **Security ▸ Report a vulnerability** on this repository instead. Only the owner sees it.

## How Vela's updates are protected

- **Signed updates.** Each release zip is signed with a private Ed25519 key that only lives in this repository's Actions secrets. Vela checks the signature against the public key built into the app (`SUPublicEDKey` in `Vela-Info.plist`) and refuses an update that doesn't match.
- **Code signing.** Releases are signed with the owner's Apple Development certificate, so macOS can tell a real Vela update from a look-alike.
- **Checksums.** Every release includes `Vela-<version>-SHA256.txt`. On a Mac you can check a download with `shasum -a 256 Vela-<version>.dmg`.
- **Pinned build tools.** The workflows use GitHub Actions pinned to exact commits, and Dependabot proposes updates to them.
- **No secrets in pull requests.** The Build check runs with read-only access and never sees the signing keys. Only the Release workflow, which runs on `main`, can use them.
