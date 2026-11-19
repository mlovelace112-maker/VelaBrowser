import Foundation

/// How hard the shield blocks ads and trackers.
enum BlockingLevel: String, CaseIterable, Codable, Identifiable {
    /// No blocking.
    case off
    /// Blocks known trackers and ad networks when another site loads them (like Brave's default).
    case standard
    /// Also blocks them on their own sites, blocks ad-shaped requests anywhere,
    /// and hides leftover ad boxes.
    case aggressive

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// The script-blocking slider. Higher means stricter.
enum ScriptLevel: Int, CaseIterable, Codable, Identifiable {
    /// Every script runs (trackers are still blocked by the shield).
    case allowAll = 0
    /// Only the site's own scripts run; scripts from other companies are blocked.
    case blockThirdParty = 1
    /// No JavaScript at all. Fastest and safest, but many sites will break.
    case blockAll = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .allowAll: "Allow all scripts"
        case .blockThirdParty: "Block third-party scripts"
        case .blockAll: "Block all JavaScript"
        }
    }

    var shortTitle: String {
        switch self {
        case .allowAll: "Allow all"
        case .blockThirdParty: "Block 3rd-party"
        case .blockAll: "Block all"
        }
    }

    /// One sentence explaining what this position does.
    var detail: String {
        switch self {
        case .allowAll: "Every script runs. Known trackers are still blocked by the shield."
        case .blockThirdParty: "Only the site's own scripts run. Scripts from other companies are blocked. Most sites still work."
        case .blockAll: "No JavaScript at all. Fastest and safest, but many sites will break."
        }
    }
}

/// Your privacy and security choices. Saved between launches.
struct PrivacySettings: Codable, Equatable {
    var blockingLevel: BlockingLevel = .standard
    var blockPopups = true
    /// Stops "pop-unders": ad tabs that open when you click anywhere on a page.
    var popUnderProtection = true
    /// Hides full-screen ads that cover a page before you can read it.
    var blockInterstitialAds = true
    /// Blocks ad frames and video ads embedded inside articles.
    var blockEmbeddedAds = true
    var blockThirdPartyCookies = true
    var upgradeToHTTPS = true
    /// HTTPS-Only: if a site has no secure version, show a warning first.
    var httpsOnly = true
    /// Sites where you chose "Continue to Site (Not Secure)".
    var httpAllowedSites: Set<String> = []
    /// Stops websites from reaching devices on your home network (your
    /// router, printer, smart-home hubs) or apps running on your Mac.
    var blockLocalNetworkAccess = true
    var clearCookiesOnQuit = false
    /// Sites whose cookies survive "Clear cookies when I quit" (so you stay signed in).
    var keptSites: Set<String> = []
    /// Sites where you've turned the shield off because something didn't work.
    var shieldsDownSites: Set<String> = []
    /// Sites where you chose "Allow Sign-In": they keep every cookie, including
    /// the ones a sign-in service sets inside them, so logging in works.
    var signInSites: Set<String> = []

    // Scripts
    var scriptLevel: ScriptLevel = .allowAll
    /// Per-site slider positions that override `scriptLevel`.
    var siteScriptLevels: [String: ScriptLevel] = [:]

    // Links and downloads
    var linkCheckerEnabled = true
    var warnBeforeDangerousLinks = true
    var blockDangerousDownloads = true
    /// Check pages and downloads against Google Safe Browsing (needs an API key).
    var safeBrowsingEnabled = true

    // Passwords
    var offerToSavePasswords = true
    /// Fill your saved login when you click into a login form.
    var autoFillPasswords = true
    /// Sites where you chose "Never for This Site" when Vela offered to save a password.
    var neverSavePasswordSites: Set<String> = []

    init() {}

    func scriptLevel(for site: String?) -> ScriptLevel {
        guard let site else { return scriptLevel }
        return siteScriptLevels[site] ?? scriptLevel
    }

    /// The settings that change the compiled blocking rules. When only these
    /// change do we need to rebuild the rules.
    var ruleInputs: RuleInputs {
        RuleInputs(
            blockingLevel: blockingLevel,
            blockInterstitialAds: blockInterstitialAds,
            blockEmbeddedAds: blockEmbeddedAds,
            blockThirdPartyCookies: blockThirdPartyCookies,
            upgradeToHTTPS: upgradeToHTTPS,
            httpAllowedSites: httpAllowedSites,
            blockLocalNetworkAccess: blockLocalNetworkAccess,
            shieldsDownSites: shieldsDownSites,
            signInSites: signInSites,
            scriptLevel: scriptLevel,
            siteScriptLevels: siteScriptLevels
        )
    }

    /// The settings baked into the small scripts Vela adds to each page.
    /// When these change, every tab gets fresh scripts.
    var scriptInputs: ScriptInputs {
        ScriptInputs(
            blockingLevel: blockingLevel,
            popUnderProtection: popUnderProtection,
            blockInterstitialAds: blockInterstitialAds,
            blockEmbeddedAds: blockEmbeddedAds,
            shieldsDownSites: shieldsDownSites
        )
    }

    struct ScriptInputs: Equatable {
        let blockingLevel: BlockingLevel
        let popUnderProtection: Bool
        let blockInterstitialAds: Bool
        let blockEmbeddedAds: Bool
        let shieldsDownSites: Set<String>
    }

    struct RuleInputs: Equatable {
        let blockingLevel: BlockingLevel
        let blockInterstitialAds: Bool
        let blockEmbeddedAds: Bool
        let blockThirdPartyCookies: Bool
        let upgradeToHTTPS: Bool
        let httpAllowedSites: Set<String>
        let blockLocalNetworkAccess: Bool
        let shieldsDownSites: Set<String>
        let signInSites: Set<String>
        let scriptLevel: ScriptLevel
        let siteScriptLevels: [String: ScriptLevel]
    }

    // MARK: Saving

    /// Reads saved settings. Any setting missing from an older save keeps its
    /// default, so adding new settings never wipes your existing choices.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PrivacySettings()
        blockingLevel = try c.decodeIfPresent(BlockingLevel.self, forKey: .blockingLevel) ?? d.blockingLevel
        blockPopups = try c.decodeIfPresent(Bool.self, forKey: .blockPopups) ?? d.blockPopups
        popUnderProtection = try c.decodeIfPresent(Bool.self, forKey: .popUnderProtection) ?? d.popUnderProtection
        blockInterstitialAds = try c.decodeIfPresent(Bool.self, forKey: .blockInterstitialAds) ?? d.blockInterstitialAds
        blockEmbeddedAds = try c.decodeIfPresent(Bool.self, forKey: .blockEmbeddedAds) ?? d.blockEmbeddedAds
        blockThirdPartyCookies = try c.decodeIfPresent(Bool.self, forKey: .blockThirdPartyCookies) ?? d.blockThirdPartyCookies
        upgradeToHTTPS = try c.decodeIfPresent(Bool.self, forKey: .upgradeToHTTPS) ?? d.upgradeToHTTPS
        httpsOnly = try c.decodeIfPresent(Bool.self, forKey: .httpsOnly) ?? d.httpsOnly
        httpAllowedSites = try c.decodeIfPresent(Set<String>.self, forKey: .httpAllowedSites) ?? d.httpAllowedSites
        blockLocalNetworkAccess = try c.decodeIfPresent(Bool.self, forKey: .blockLocalNetworkAccess) ?? d.blockLocalNetworkAccess
        clearCookiesOnQuit = try c.decodeIfPresent(Bool.self, forKey: .clearCookiesOnQuit) ?? d.clearCookiesOnQuit
        keptSites = try c.decodeIfPresent(Set<String>.self, forKey: .keptSites) ?? d.keptSites
        shieldsDownSites = try c.decodeIfPresent(Set<String>.self, forKey: .shieldsDownSites) ?? d.shieldsDownSites
        signInSites = try c.decodeIfPresent(Set<String>.self, forKey: .signInSites) ?? d.signInSites
        scriptLevel = try c.decodeIfPresent(ScriptLevel.self, forKey: .scriptLevel) ?? d.scriptLevel
        siteScriptLevels = try c.decodeIfPresent([String: ScriptLevel].self, forKey: .siteScriptLevels) ?? d.siteScriptLevels
        linkCheckerEnabled = try c.decodeIfPresent(Bool.self, forKey: .linkCheckerEnabled) ?? d.linkCheckerEnabled
        warnBeforeDangerousLinks = try c.decodeIfPresent(Bool.self, forKey: .warnBeforeDangerousLinks) ?? d.warnBeforeDangerousLinks
        blockDangerousDownloads = try c.decodeIfPresent(Bool.self, forKey: .blockDangerousDownloads) ?? d.blockDangerousDownloads
        safeBrowsingEnabled = try c.decodeIfPresent(Bool.self, forKey: .safeBrowsingEnabled) ?? d.safeBrowsingEnabled
        offerToSavePasswords = try c.decodeIfPresent(Bool.self, forKey: .offerToSavePasswords) ?? d.offerToSavePasswords
        autoFillPasswords = try c.decodeIfPresent(Bool.self, forKey: .autoFillPasswords) ?? d.autoFillPasswords
        neverSavePasswordSites = try c.decodeIfPresent(Set<String>.self, forKey: .neverSavePasswordSites) ?? d.neverSavePasswordSites
    }

    private static let key = "vela.privacy"

    static func load() -> PrivacySettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(PrivacySettings.self, from: data) else {
            return PrivacySettings()
        }
        return saved
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// A pop-up the shield just stopped, shown in the "Pop-up blocked" notice.
struct BlockedPopup: Identifiable, Equatable {
    let id = UUID()
    let tabID: UUID
    let url: URL?
    var isPopUnder = false
}
