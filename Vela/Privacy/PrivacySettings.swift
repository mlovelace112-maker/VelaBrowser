import Foundation

/// How hard the shield blocks ads and trackers.
enum BlockingLevel: String, CaseIterable, Codable, Identifiable {
    /// No blocking.
    case off
    /// Blocks known trackers and ad networks when another site loads them (like Brave's default).
    case standard
    /// Also blocks them on their own sites and hides common leftover ad boxes.
    case aggressive

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Your privacy choices. Saved between launches.
struct PrivacySettings: Codable, Equatable {
    var blockingLevel: BlockingLevel = .standard
    var blockPopups = true
    var blockThirdPartyCookies = true
    var upgradeToHTTPS = true
    var clearCookiesOnQuit = false
    /// Sites whose cookies survive "Clear cookies when I quit" (so you stay signed in).
    var keptSites: Set<String> = []
    /// Sites where you've turned the shield off because something didn't work.
    var shieldsDownSites: Set<String> = []

    /// The settings that change the compiled blocking rules. When only these
    /// change do we need to rebuild the rules.
    var ruleInputs: RuleInputs {
        RuleInputs(
            blockingLevel: blockingLevel,
            blockThirdPartyCookies: blockThirdPartyCookies,
            upgradeToHTTPS: upgradeToHTTPS,
            shieldsDownSites: shieldsDownSites
        )
    }

    struct RuleInputs: Equatable {
        let blockingLevel: BlockingLevel
        let blockThirdPartyCookies: Bool
        let upgradeToHTTPS: Bool
        let shieldsDownSites: Set<String>
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
}
