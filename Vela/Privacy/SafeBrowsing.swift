import Foundation
import Observation
import Security

/// What Google Safe Browsing says a page or file is.
enum SafeBrowsingThreat: String {
    case malware = "MALWARE"
    case phishing = "SOCIAL_ENGINEERING"
    case unwantedSoftware = "UNWANTED_SOFTWARE"
    case harmfulApp = "POTENTIALLY_HARMFUL_APPLICATION"

    var reason: String {
        switch self {
        case .malware: "Google Safe Browsing lists this site as spreading malware"
        case .phishing: "Google Safe Browsing lists this site as a phishing scam that tries to steal passwords or card numbers"
        case .unwantedSoftware: "Google Safe Browsing lists this site as offering harmful or unwanted software"
        case .harmfulApp: "Google Safe Browsing lists this site as offering a harmful app"
        }
    }
}

/// Checks web addresses against Google's list of dangerous sites, the same
/// list Safari, Chrome and Firefox use.
///
/// **How it works:** before a page opens, Vela asks Google "is this address on
/// your list?" To keep this private-ish, Vela sends only the site and path,
/// never the part after "?" (which can hold search words or account details),
/// and remembers answers so each address is only checked once in a while.
/// If Google is slow or unreachable, the page opens normally.
///
/// It needs a free API key from Google Cloud, kept in your Keychain.
@MainActor
@Observable
final class SafeBrowsing {
    private(set) var hasKey = false

    @ObservationIgnored private var apiKey: String?
    @ObservationIgnored private var cache: [String: (threat: SafeBrowsingThreat?, expires: Date)] = [:]

    private static let keychainService = "Vela Safe Browsing"
    private static let keychainAccount = "api-key"

    init() {
        apiKey = Self.loadKey()
        hasKey = apiKey != nil
    }

    /// Returns the threat if Google lists this address, or nil if it's not listed
    /// (or the check couldn't be done).
    func check(_ url: URL) async -> SafeBrowsingThreat? {
        guard let apiKey, let address = Self.lookupAddress(for: url) else { return nil }
        if let cached = cache[address], cached.expires > Date() { return cached.threat }

        var components = URLComponents(string: "https://safebrowsing.googleapis.com/v4/threatMatches:find")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 2
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "client": ["clientId": "vela-browser", "clientVersion": "1.0"],
            "threatInfo": [
                "threatTypes": ["MALWARE", "SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE", "POTENTIALLY_HARMFUL_APPLICATION"],
                "platformTypes": ["ANY_PLATFORM"],
                "threatEntryTypes": ["URL"],
                "threatEntries": [["url": address]],
            ] as [String: Any],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let matches = json["matches"] as? [[String: Any]] ?? []
            let threat = matches.compactMap { ($0["threatType"] as? String).flatMap(SafeBrowsingThreat.init(rawValue:)) }.first
            // Remember safe answers for 30 minutes and dangerous ones for 5.
            cache[address] = (threat, Date().addingTimeInterval(threat == nil ? 1800 : 300))
            if cache.count > 2000 { cache.removeAll() }
            return threat
        } catch {
            return nil
        }
    }

    /// "https://example.com/login?user=me#top" → "https://example.com/login"
    private static func lookupAddress(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty, host != "localhost" else { return nil }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url?.absoluteString
    }

    // MARK: - API key (stored in the Keychain)

    /// Saves a new key, or removes it when `key` is empty.
    func setKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        SecItemDelete(match as CFDictionary)
        if !trimmed.isEmpty {
            var item = match
            item[kSecValueData as String] = Data(trimmed.utf8)
            SecItemAdd(item as CFDictionary, nil)
        }
        apiKey = trimmed.isEmpty ? nil : trimmed
        hasKey = apiKey != nil
        cache.removeAll()
    }

    private static func loadKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }
}
