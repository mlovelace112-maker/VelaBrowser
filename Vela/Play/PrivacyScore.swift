import Foundation

/// One thing that adds to your privacy score, like "Block third-party cookies".
struct PrivacyScorePart: Identifiable {
    let id: String
    let title: String
    let points: Int
    let isOn: Bool
    /// Where to turn it on, for the parts that are off.
    let whereToFix: String
}

extension BrowserStore {
    /// Your privacy score, 0 to 100: the points from every protection that's on.
    /// It feeds Play (a daily bonus and the Privacy Pro badge) and shows in
    /// the Play hub with tips for the parts that are off.
    var privacyScore: Int {
        min(100, privacyScoreParts.filter(\.isOn).reduce(0) { $0 + $1.points })
    }

    var privacyScoreParts: [PrivacyScorePart] {
        let p = privacy
        return [
            PrivacyScorePart(id: "blocking", title: "Block trackers and ads", points: 12,
                             isOn: p.blockingLevel != .off, whereToFix: "Settings ▸ Privacy"),
            PrivacyScorePart(id: "aggressive", title: "Aggressive blocking", points: 5,
                             isOn: p.blockingLevel == .aggressive, whereToFix: "Settings ▸ Privacy ▸ Blocking"),
            PrivacyScorePart(id: "popups", title: "Block pop-ups", points: 6,
                             isOn: p.blockPopups, whereToFix: "Settings ▸ Privacy"),
            PrivacyScorePart(id: "popunders", title: "Stop pop-unders", points: 4,
                             isOn: p.popUnderProtection, whereToFix: "Settings ▸ Privacy"),
            PrivacyScorePart(id: "cookies", title: "Block third-party cookies", points: 12,
                             isOn: p.blockThirdPartyCookies, whereToFix: "Settings ▸ Privacy"),
            PrivacyScorePart(id: "https", title: "HTTPS-Only", points: 10,
                             isOn: p.httpsOnly, whereToFix: "Settings ▸ Security"),
            PrivacyScorePart(id: "fingerprint", title: "Fingerprinting protection", points: 10,
                             isOn: p.fingerprintProtection, whereToFix: "Settings ▸ Privacy"),
            PrivacyScorePart(id: "gpc", title: "Ask sites not to sell your data (GPC)", points: 5,
                             isOn: p.globalPrivacyControl, whereToFix: "Settings ▸ Privacy"),
            PrivacyScorePart(id: "links", title: "Strip tracking from links", points: 6,
                             isOn: p.stripTrackingParameters, whereToFix: "Settings ▸ Privacy"),
            PrivacyScorePart(id: "banners", title: "Auto-reject cookie banners", points: 5,
                             isOn: p.dismissCookieBanners, whereToFix: "Settings ▸ Privacy"),
            PrivacyScorePart(id: "safebrowsing", title: "Google Safe Browsing", points: 6,
                             isOn: p.safeBrowsingEnabled && safeBrowsing.hasKey, whereToFix: "Settings ▸ Security"),
            PrivacyScorePart(id: "downloads", title: "Scan and block dangerous downloads", points: 5,
                             isOn: p.blockDangerousDownloads && p.scanDownloads, whereToFix: "Settings ▸ Security"),
            PrivacyScorePart(id: "local", title: "Keep sites off your home network", points: 4,
                             isOn: p.blockLocalNetworkAccess, whereToFix: "Settings ▸ Privacy"),
            PrivacyScorePart(id: "linkcheck", title: "Check links before you click", points: 5,
                             isOn: p.linkCheckerEnabled, whereToFix: "Settings ▸ Security"),
            PrivacyScorePart(id: "lockdown", title: "Lock down a site you don't trust", points: 5,
                             isOn: !p.lockdownSites.isEmpty, whereToFix: "Shield button ▸ Lockdown Mode"),
        ]
    }
}
