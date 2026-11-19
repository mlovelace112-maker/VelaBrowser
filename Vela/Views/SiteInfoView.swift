import AppKit
import Security
import SecurityInterface
import SwiftUI
import WebKit

/// The site info panel: click the 🔒 at the left of the address bar.
///
/// It answers "is this really the site I think it is, and is my connection
/// private?" by showing the site's **certificate**: the ID card a website
/// shows your browser. A trusted company (the "issuer", like Let's Encrypt
/// or DigiCert) checked that whoever runs the site controls its name, and
/// signed the card. The panel also shows what this site is allowed to do.
struct SiteInfoView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tab: BrowserTab
    @State private var certificate: CertificateSummary?
    @State private var storedItems: Int?
    @State private var cleared = false

    var body: some View {
        let site = tab.url.map(BrowserStore.siteName) ?? ""
        let isSecure = tab.url?.scheme == "https" && tab.webView.hasOnlySecureContent
        let privacy = store.privacy

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: isSecure ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSecure ? Nightglass.safe : Nightglass.caution)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill((isSecure ? Nightglass.safe : Nightglass.caution).opacity(0.16)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(site).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(isSecure ? "Connection is secure" : tab.url?.scheme == "https"
                         ? "Parts of this page aren't secure" : "Connection is not secure")
                        .font(.system(size: 12))
                        .foregroundStyle(isSecure ? Nightglass.safe : Nightglass.caution)
                }
            }

            Text(isSecure
                 ? "What you send and see here is encrypted, so people on your network (like public Wi-Fi) can't read it."
                 : "Don't type passwords or card numbers here. Others on your network could see or change what's sent.")
                .font(.system(size: 12))
                .foregroundStyle(Nightglass.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            if let certificate {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Certificate").font(.system(size: 12.5, weight: .semibold))
                    row("Issued to", certificate.subject)
                    row("Issued by", certificate.issuer)
                    if let expires = certificate.expires {
                        row("Valid until", expires.formatted(date: .abbreviated, time: .omitted),
                            warn: expires.timeIntervalSinceNow < 14 * 24 * 3600)
                    }
                    Button("Show Certificate…") { showCertificate() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.25)))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("This site").font(.system(size: 12.5, weight: .semibold))
                status("Shield", store.shieldsUp(for: tab) ? "On" : "Off", icon: "checkmark.shield")
                status("Trackers blocked", "\(tab.trackersFound.count)", icon: "eye.slash")
                status("JavaScript", store.scriptLevel(for: tab).shortTitle, icon: "curlybraces")
                ForEach(PermissionKind.allCases) { kind in
                    status(kind.title, answer(privacy.permission(kind, for: site)), icon: kind.icon)
                }
                if privacy.lockdownSites.contains(site) {
                    status("Lockdown Mode", "On", icon: "lock.shield")
                }
                if let storedItems {
                    status("Cookies and site data", cleared ? "Cleared" : storedItems == 0 ? "None" : "Stored", icon: "internaldrive")
                }
            }

            HStack {
                Button {
                    dismiss()
                    store.isSiteSettingsVisible = true
                } label: { Label("Site Settings…", systemImage: "globe") }
                Spacer()
                Button("Clear Cookies and Data") { Task { await clearData(for: site) } }
                    .disabled(storedItems == 0 || cleared)
                    .help("Signs you out of \(site) and forgets what it stored on your Mac")
            }
            .font(.system(size: 12))
            .controlSize(.small)
        }
        .padding(18)
        .frame(width: 340)
        .task {
            certificate = CertificateSummary(trust: tab.webView.serverTrust)
            storedItems = await records(for: site).count
        }
    }

    private func row(_ label: String, _ value: String, warn: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Nightglass.mutedText).frame(width: 78, alignment: .leading)
            Text(value).foregroundStyle(warn ? Nightglass.caution : Nightglass.text).lineLimit(2).textSelection(.enabled)
        }
        .font(.system(size: 12))
    }

    private func status(_ label: String, _ value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon).foregroundStyle(Nightglass.secondaryText)
            Spacer()
            Text(value).foregroundStyle(Nightglass.mutedText)
        }
        .font(.system(size: 12))
    }

    private func answer(_ value: Bool?) -> String {
        switch value {
        case .some(true): "Allowed"
        case .some(false): "Blocked"
        case .none: "Ask"
        }
    }

    /// Apple's own certificate viewer, with every detail.
    private func showCertificate() {
        guard let trust = tab.webView.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else { return }
        dismiss()
        SFCertificatePanel.shared()?.runModal(forCertificates: chain, showGroup: true)
    }

    private func records(for site: String) async -> [WKWebsiteDataRecord] {
        let store = tab.webView.configuration.websiteDataStore
        let all = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        return all.filter { $0.displayName == site || $0.displayName.hasSuffix("." + site) }
    }

    private func clearData(for site: String) async {
        let store = tab.webView.configuration.websiteDataStore
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: await records(for: site))
        cleared = true
        tab.webView.reload()
    }
}

/// The parts of a certificate worth showing.
struct CertificateSummary {
    let subject: String
    let issuer: String
    let expires: Date?

    init?(trust: SecTrust?) {
        guard let trust, let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return nil }
        subject = SecCertificateCopySubjectSummary(leaf) as String? ?? "Unknown"
        issuer = chain.count > 1 ? (SecCertificateCopySubjectSummary(chain[1]) as String? ?? "Unknown") : "Itself (self-signed)"
        // "Not valid after" date.
        var expiry: Date?
        let keys = [kSecOIDX509V1ValidityNotAfter] as CFArray
        if let values = SecCertificateCopyValues(leaf, keys, nil) as? [String: Any],
           let entry = values[kSecOIDX509V1ValidityNotAfter as String] as? [String: Any],
           let seconds = entry[kSecPropertyKeyValue as String] as? NSNumber {
            // Certificates count from January 1, 2001.
            expiry = Date(timeIntervalSinceReferenceDate: seconds.doubleValue)
        }
        expires = expiry
    }
}
