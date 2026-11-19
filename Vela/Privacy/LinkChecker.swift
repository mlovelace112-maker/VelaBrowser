import Foundation
import WebKit

/// How safe a link looks.
enum LinkVerdict: Int, Comparable {
    case safe, caution, dangerous

    static func < (lhs: LinkVerdict, rhs: LinkVerdict) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The link checker's findings for one web address.
struct LinkReport: Equatable {
    var verdict: LinkVerdict = .safe
    var reasons: [String] = []

    mutating func flag(_ level: LinkVerdict, _ reason: String) {
        verdict = max(verdict, level)
        reasons.append(reason)
    }
}

/// A dangerous page the link checker stopped, shown as a warning over the tab.
struct LinkWarning: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let report: LinkReport
}

/// Checks web addresses for common scam and phishing tricks.
///
/// **How it works:** everything here runs on your Mac, instantly, with no
/// internet lookups. It looks at the *shape* of the address, not the page:
/// fake "@" addresses, look-alike letters, brand names on the wrong website,
/// link shorteners that hide where you're going, and web endings that scams
/// favor. It can't know about a brand-new scam site with an ordinary-looking
/// name. That would need an online threat list (see the README).
@MainActor
enum LinkChecker {
    static func check(_ url: URL) -> LinkReport {
        var report = LinkReport()
        let scheme = url.scheme?.lowercased() ?? ""

        if scheme == "javascript" {
            report.flag(.caution, "Runs a script instead of opening a page")
            return report
        }
        if scheme == "data" {
            report.flag(.caution, "A page hidden inside the link itself, a common phishing trick")
            return report
        }
        guard scheme == "http" || scheme == "https",
              let host = url.host()?.lowercased(), !host.isEmpty else { return report }

        let labels = host.split(separator: ".").map(String.init)
        let domain = registrableDomain(host)
        let tld = labels.last ?? ""
        let isLocal = isLocalHost(host)

        // "https://paypal.com@evil.example" really goes to evil.example.
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if components?.user != nil || components?.password != nil {
            report.flag(.dangerous, "Everything before the “@” is ignored, so this really goes to \(host)")
        }

        // Look-alike international letters, e.g. a Cyrillic "а" in place of "a".
        let usesLookalikes = labels.contains { $0.hasPrefix("xn--") }
        if usesLookalikes {
            report.flag(.caution, "Uses international letters that can look like ordinary ones")
        }

        let riskyEnding = riskyTLDs.contains(tld)
        if riskyEnding {
            report.flag(.caution, "Uses a web ending (.\(tld)) that scams often use")
        }

        // A brand name on a website that brand doesn't own.
        if let brand = impersonatedBrand(host: host, domain: domain) {
            let tokens = Set(host.split(whereSeparator: { $0 == "." || $0 == "-" }).map(String.init))
            let path = url.path().lowercased()
            let asksToSignIn = !tokens.isDisjoint(with: credentialWords)
                || signInPathWords.contains { path.contains($0) }
            if asksToSignIn || riskyEnding || usesLookalikes {
                report.flag(.dangerous, "Pretends to be \(brand.name), but isn't one of \(brand.name)'s websites")
            } else {
                report.flag(.caution, "Mentions \(brand.name), but isn't run by \(brand.name)")
            }
        }

        if isIPAddress(host) && !isLocal {
            report.flag(.caution, "Goes to a bare number address instead of a named website")
        }
        if shorteners.contains(domain) {
            report.flag(.caution, "A shortened link: the real destination is hidden")
        }
        if labels.count >= 6 {
            report.flag(.caution, "An unusually long web address")
        }
        if ContentBlocker.isTracker(host) {
            report.flag(.caution, "Goes through an ad or tracking company")
        }

        let ext = url.pathExtension.lowercased()
        if DownloadGuard.windowsPrograms.contains(ext) {
            report.flag(.caution, "Downloads a Windows program (.\(ext))")
        } else if DownloadGuard.macPrograms.contains(ext) {
            report.flag(.caution, "Downloads an app, installer or script (.\(ext))")
        }

        if scheme == "http" && !isLocal {
            report.flag(.caution, "Not encrypted (http)")
        }
        return report
    }

    // MARK: - Hover script

    /// Tells Vela which link the mouse is over, so the status bubble at the
    /// bottom of the page can show where it goes and whether it looks safe.
    /// It runs in Vela's private script world, so pages can't fake it.
    static func hoverScript() -> WKUserScript {
        let source = """
        (() => {
          if (window.__velaLinks) return;
          window.__velaLinks = true;
          let current = '';
          const post = (url) => {
            if (url === current) return;
            current = url;
            try { window.webkit.messageHandlers.\(ContentBlocker.clientMessageName).postMessage({ type: 'hover', url }); } catch (e) {}
          };
          document.addEventListener('mouseover', (e) => {
            const link = e.target && e.target.closest ? e.target.closest('a[href]') : null;
            post(link && typeof link.href === 'string' ? link.href : '');
          }, true);
          document.addEventListener('mouseout', (e) => { if (!e.relatedTarget) post(''); }, true);
          window.addEventListener('pagehide', () => post(''));
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)
    }

    // MARK: - Helpers

    /// "login.secure.example.co.uk" → "example.co.uk"
    static func registrableDomain(_ host: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return host }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if twoPartEndings.contains(lastTwo) {
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    private static func isIPAddress(_ host: String) -> Bool {
        if host.contains(":") { return true } // IPv6
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }

    private static func isLocalHost(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".local") || host.hasPrefix("127.")
            || host.hasPrefix("192.168.") || host.hasPrefix("10.")
    }

    private struct Brand {
        let name: String
        let keyword: String
        /// Websites the brand really owns (besides "keyword.com", "keyword.co.uk" and so on).
        let domains: Set<String>
    }

    private static func impersonatedBrand(host: String, domain: String) -> Brand? {
        let tokens = host.split(whereSeparator: { $0 == "." || $0 == "-" }).map(String.init)
        for brand in brands {
            // Matches "paypal" or "paypal" glued to a sign-in word ("paypalsecure"),
            // but not words that merely contain it ("pineapple").
            let mentioned = tokens.contains { token in
                guard token.contains(brand.keyword) else { return false }
                if token == brand.keyword { return true }
                let rest = token.replacingOccurrences(of: brand.keyword, with: "")
                return credentialWords.contains(rest)
            }
            guard mentioned else { continue }

            let firstLabel = domain.split(separator: ".").first.map(String.init) ?? ""
            let ending = domain.split(separator: ".").dropFirst().joined(separator: ".")
            let ownsDomain = brand.domains.contains(domain)
                || (firstLabel == brand.keyword && commonEndings.contains(ending))
            if !ownsDomain { return brand }
        }
        return nil
    }

    // MARK: - Lists

    private static let brands: [Brand] = [
        Brand(name: "PayPal", keyword: "paypal", domains: ["paypal.me", "paypalobjects.com"]),
        Brand(name: "Apple", keyword: "apple", domains: ["icloud.com", "apple.news", "mzstatic.com", "cdn-apple.com"]),
        Brand(name: "iCloud", keyword: "icloud", domains: ["apple.com"]),
        Brand(name: "Microsoft", keyword: "microsoft", domains: ["microsoftonline.com", "live.com", "office.com", "azure.com", "msn.com", "windows.com", "bing.com"]),
        Brand(name: "Microsoft Outlook", keyword: "outlook", domains: ["live.com", "office.com", "microsoft.com", "office365.com"]),
        Brand(name: "Microsoft Office", keyword: "office365", domains: ["office.com", "microsoft.com"]),
        Brand(name: "Google", keyword: "google", domains: ["googleusercontent.com", "gstatic.com", "googleapis.com", "youtube.com", "withgoogle.com", "googlesource.com", "googleblog.com", "blog.google", "goo.gl"]),
        Brand(name: "Gmail", keyword: "gmail", domains: ["google.com"]),
        Brand(name: "Amazon", keyword: "amazon", domains: ["amazonaws.com", "a2z.com", "media-amazon.com", "amazontrust.com"]),
        Brand(name: "Netflix", keyword: "netflix", domains: ["nflxext.com", "nflximg.net", "nflxvideo.net"]),
        Brand(name: "Facebook", keyword: "facebook", domains: ["fb.com", "fbcdn.net", "facebook.net", "meta.com"]),
        Brand(name: "Instagram", keyword: "instagram", domains: ["cdninstagram.com"]),
        Brand(name: "WhatsApp", keyword: "whatsapp", domains: ["whatsapp.net"]),
        Brand(name: "Spotify", keyword: "spotify", domains: ["scdn.co", "spotifycdn.com"]),
        Brand(name: "Chase", keyword: "chase", domains: ["jpmorganchase.com", "chasecdn.com"]),
        Brand(name: "Wells Fargo", keyword: "wellsfargo", domains: ["wf.com"]),
        Brand(name: "Bank of America", keyword: "bankofamerica", domains: ["bofa.com"]),
        Brand(name: "Coinbase", keyword: "coinbase", domains: []),
        Brand(name: "Binance", keyword: "binance", domains: ["binance.us"]),
        Brand(name: "MetaMask", keyword: "metamask", domains: ["metamask.io"]),
        Brand(name: "Venmo", keyword: "venmo", domains: []),
        Brand(name: "DocuSign", keyword: "docusign", domains: ["docusign.net"]),
        Brand(name: "Dropbox", keyword: "dropbox", domains: ["dropboxusercontent.com", "db.tt"]),
        Brand(name: "USPS", keyword: "usps", domains: []),
        Brand(name: "FedEx", keyword: "fedex", domains: []),
        Brand(name: "DHL", keyword: "dhl", domains: []),
        Brand(name: "the IRS", keyword: "irs", domains: ["irs.gov"]),
        Brand(name: "Steam", keyword: "steampowered", domains: ["steamcommunity.com", "steamstatic.com"]),
    ]

    /// Words scam sites glue onto brand names: "paypal-login", "apple-verify".
    private static let credentialWords: Set<String> = [
        "login", "logon", "signin", "sign", "secure", "security", "verify", "verification",
        "account", "accounts", "support", "update", "wallet", "billing", "id", "auth",
        "confirm", "recovery", "unlock", "help", "service", "pay", "payment", "refund",
    ]

    /// Words in the page path that mean "type your password here".
    private static let signInPathWords: [String] = [
        "login", "signin", "logon", "verify", "verification", "wallet", "billing",
        "confirm", "recovery", "unlock", "password",
    ]

    /// Web endings a brand might legitimately use for its country sites.
    private static let commonEndings: Set<String> = [
        "com", "net", "org", "co.uk", "de", "fr", "ca", "com.au", "co.jp", "it", "es", "nl",
        "ie", "in", "com.br", "com.mx", "ch", "se", "no", "dk", "be", "at", "pl", "co.nz",
    ]

    /// Endings with two parts, so "example.co.uk" is the site, not "co.uk".
    private static let twoPartEndings: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "net.au", "org.au", "co.nz", "co.jp",
        "co.kr", "com.br", "com.mx", "com.cn", "com.tr", "co.in", "co.za", "com.sg", "com.hk",
    ]

    private static let riskyTLDs: Set<String> = [
        "zip", "mov", "top", "xyz", "tk", "ml", "ga", "cf", "gq", "icu", "cyou", "buzz", "rest",
        "click", "country", "kim", "work", "loan", "men", "gdn", "review", "cam", "quest", "sbs",
        "bond", "monster", "lol", "beauty", "hair",
    ]

    private static let shorteners: Set<String> = [
        "bit.ly", "tinyurl.com", "goo.gl", "ow.ly", "is.gd", "buff.ly", "rebrand.ly", "cutt.ly",
        "shorturl.at", "rb.gy", "tiny.cc", "bit.do", "s.id", "v.gd", "t.ly", "shorte.st", "adf.ly",
    ]
}
