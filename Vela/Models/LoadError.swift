import Foundation
import WebKit

/// Why a page didn't load, in plain words, for the "This page didn't load" screen.
struct LoadError: Equatable {
    let url: URL
    let code: Int
    let domain: String
    let title: String
    let detail: String

    init(url: URL, error: NSError) {
        self.url = url
        code = error.code
        domain = error.domain
        let site = url.host() ?? url.absoluteString
        switch (error.domain, error.code) {
        case (NSURLErrorDomain, NSURLErrorNotConnectedToInternet):
            title = "You're not connected to the internet"
            detail = "Check your Wi-Fi, then try again."
        case (NSURLErrorDomain, NSURLErrorTimedOut):
            title = "\(site) took too long to answer"
            detail = "The site may be busy. Try again in a moment."
        case (NSURLErrorDomain, NSURLErrorCannotFindHost), (NSURLErrorDomain, NSURLErrorDNSLookupFailed):
            title = "Vela can't find \(site)"
            detail = "Check the address for typos. If it's right, your network may be blocking it."
        case (NSURLErrorDomain, NSURLErrorServerCertificateUntrusted),
             (NSURLErrorDomain, NSURLErrorServerCertificateHasBadDate),
             (NSURLErrorDomain, NSURLErrorServerCertificateHasUnknownRoot),
             (NSURLErrorDomain, NSURLErrorServerCertificateNotYetValid),
             (NSURLErrorDomain, NSURLErrorClientCertificateRejected),
             (NSURLErrorDomain, NSURLErrorClientCertificateRequired):
            title = "Vela can't confirm this is really \(site)"
            detail = "The site's security certificate isn't valid, so Vela stopped before sending anything. If your Mac's date and time are right, don't continue: someone could be pretending to be this site."
        case (NSURLErrorDomain, NSURLErrorSecureConnectionFailed):
            title = "A secure connection to \(site) couldn't be made"
            detail = "This is usually a short hiccup on the network. Try again. If it keeps happening on one Wi-Fi network, that network may be interfering."
        default:
            title = "\(site) didn't load"
            detail = error.localizedDescription
        }
    }

    /// Not really errors: you stopped the page, or it moved on to another one.
    static func isHarmless(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return true }
        // WebKit: "Frame load interrupted" (a download started, or the page
        // replaced itself) and "Plug-in handled load".
        if error.domain == "WebKitErrorDomain" && (error.code == 102 || error.code == 204) { return true }
        return false
    }

    /// Hiccups that usually go away on a second try.
    static func isTemporary(_ error: NSError) -> Bool {
        guard error.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorSecureConnectionFailed,
            NSURLErrorCannotConnectToHost,
            NSURLErrorDNSLookupFailed,
        ].contains(error.code)
    }
}
