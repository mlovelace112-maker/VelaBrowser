# Security

## Reporting a problem

Please don't open a public issue for a security problem. Use **Security ▸ Report a vulnerability** on this repository instead. Only the owner sees it.

## How Vela's updates are protected

- **Signed updates.** Each release zip is signed with a private Ed25519 key that only lives in this repository's Actions secrets. Vela checks the signature against the public key built into the app (`SUPublicEDKey` in `Vela-Info.plist`) and refuses an update that doesn't match.
- **Code signing.** Releases are signed with the owner's Apple Development certificate, so macOS can tell a real Vela update from a look-alike.
- **Checksums.** Every release includes `Vela-<version>-SHA256.txt`. On a Mac you can check a download with `shasum -a 256 Vela-<version>.dmg`.
- **Pinned build tools.** The workflows use GitHub Actions pinned to exact commits, and Dependabot proposes updates to them.
- **No secrets in pull requests.** The Build check runs with read-only access and never sees the signing keys. Only the Release workflow, which runs on `main`, can use them.

## How Vela measures up to the OWASP Top 10

[OWASP](https://owasp.org) publishes the ten most common ways software gets attacked. Vela is a browser, not a website, so some items apply to the sites you visit rather than to Vela. Here is each one, and what Vela does about it.

### Web application risks (OWASP Top 10, 2021)

| Risk | What it means for Vela | What Vela does |
|---|---|---|
| **A01 Broken access control** | A web page reaching things it shouldn't: your files, your home network, your camera, other sites' data. | Camera and microphone need your OK per site (Site Settings). Web pages can't open `file://` addresses. Websites can't reach `localhost`, your router or other home-network devices. Autofill only fills the exact site a login was saved for. Pop-ups and new windows need a click. |
| **A02 Cryptographic failures** | Data sent or stored without encryption. | Insecure `http://` is upgraded to HTTPS, and sites with no secure version show a warning first. Passwords and API keys live in the macOS Keychain, never in plain files. Imported password exports are shredded after use. |
| **A03 Injection** | Untrusted text being run as code. | Vela's own scripts run in a separate JavaScript world that pages can't touch. Values from pages (usernames, passwords, link text) are size-limited and passed as data, never pasted into code. Page text sent to Claude is fenced off as untrusted. |
| **A04 Insecure design** | Risky features with no guard rails. | Claude can't read or click on pages with a password box, and asks before closing tabs or sending forms. Dangerous downloads are blocked, and risky ones ask first. |
| **A05 Security misconfiguration** | Unsafe defaults. | Safe defaults: tracker blocking, third-party cookie blocking, HTTPS upgrade, Apple's fraudulent-site warning, and no automatic pop-ups are all on from the first launch. |
| **A06 Vulnerable and outdated components** | Running old code with known holes. | Vela updates itself (automatically by default), urgent fixes can be marked critical, Dependabot watches the build tools, and Vela tells you when a macOS update with WebKit fixes is waiting. |
| **A07 Identification and authentication failures** | Weak or leaked passwords. | Touch ID unlocks saved passwords for 10 minutes. The password check finds weak, reused and breached passwords. The generator makes strong ones. |
| **A08 Software and data integrity failures** | Tampered updates or build pipelines. | Updates are EdDSA-signed and checked before install, releases are code-signed and come with SHA-256 checksums, and GitHub Actions are pinned to exact commits. Pull-request builds never see signing keys. |
| **A09 Security logging and monitoring failures** | Not noticing an attack. | The shield shows what was blocked on each page, and the link checker and warnings explain why something was stopped. Vela keeps no remote logs about you. |
| **A10 Server-side request forgery** | Tricking a program into calling internal addresses for an attacker. | The home-network block stops web pages from calling private addresses. Claude's "open" tool only opens `http`/`https` addresses. |

### Risks from the AI features (OWASP Top 10 for LLM Applications, 2025)

| Risk | What Vela does |
|---|---|
| **LLM01 Prompt injection** | Page text is wrapped and labeled as untrusted, and Claude is told never to follow instructions inside it. Actions that change things need your OK. |
| **LLM02 Sensitive information disclosure** | Claude never sees private tabs or pages with a password box, and only reads a page when asked. |
| **LLM05 Improper output handling** | Claude's answers are shown as text, not run as code. Links open in new tabs and go through the link checker. |
| **LLM06 Excessive agency** | Claude has a short, fixed list of browser tools. Closing tabs and sending forms ask first, and **Stop** cancels at any time. |
| **LLM10 Unbounded consumption** | Each chat turn has a cap on tool steps, and your API key stays in the Keychain. |

### What Vela can't do

- **Notarization:** Vela isn't notarized by Apple (that needs a paid developer account), so macOS asks once before the first launch.
- **Passkeys and the Passwords app:** Apple only lets approved browsers use passkeys and doesn't let any browser except Safari read the Passwords app, which is why Vela imports an export file instead.
- **WebKit bugs:** these are fixed by Apple through macOS updates, which is why Vela reminds you about them.
