import Foundation

/// How Vela introduces itself to websites. Vela uses Safari's engine, so it
/// says it's the Safari that's installed on this Mac. Some sites (Slack, for
/// one) turn away browsers that look out of date, so the version number is
/// read from Safari itself instead of being fixed in the code.
enum SafariIdentity {
    /// Safari's version on this Mac, like "27.1". Falls back to a recent one.
    static let version: String = {
        let info = URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: info),
              let full = plist["CFBundleShortVersionString"] as? String else { return "26.0" }
        // "27.1.2" -> "27.1", the way Safari itself reports it.
        let parts = full.split(separator: ".").prefix(2)
        return parts.count == 2 ? parts.joined(separator: ".") : full
    }()

    /// Added after WebKit's own "Mozilla/5.0 (Macintosh; …) AppleWebKit/…".
    static var applicationName: String { "Version/\(version) Safari/605.1.15" }

    /// The whole desktop identity, for requests Vela makes itself.
    static var desktop: String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) \(applicationName)"
    }

    /// An iPhone's identity, so web panels get phone-sized pages.
    static var mobile: String {
        let ios = version.replacingOccurrences(of: ".", with: "_")
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(ios) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(version) Mobile/15E148 Safari/604.1"
    }
}
