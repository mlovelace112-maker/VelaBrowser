import Foundation
import Observation
import WebKit

/// One website's stored cookies and data, as listed in the cookie manager.
struct SiteData: Identifiable {
    var id: String { name }
    let name: String
    let record: WKWebsiteDataRecord
    let cookieCount: Int
    let isTracker: Bool
}

/// Lists and deletes the cookies and site data that websites store in Vela.
///
/// WebKit keeps this data in a "website data store". We ask it for a list of
/// sites (data records) and cookies, then delete records when you ask.
/// Private tabs use a separate in-memory store, so they never show up here.
@MainActor
@Observable
final class CookieManager {
    private(set) var sites: [SiteData] = []
    private(set) var isLoading = false

    private let dataStore = WKWebsiteDataStore.default()

    func reload() async {
        isLoading = true
        let records = await fetchRecords()
        let cookies = await fetchCookies()
        sites = records
            .map { record in
                let name = record.displayName
                return SiteData(
                    name: name,
                    record: record,
                    cookieCount: cookies.filter { Self.cookie($0, belongsTo: name) }.count,
                    isTracker: ContentBlocker.isTracker(name)
                )
            }
            // Trackers first, then the sites with the most cookies.
            .sorted { lhs, rhs in
                if lhs.isTracker != rhs.isTracker { return lhs.isTracker }
                if lhs.cookieCount != rhs.cookieCount { return lhs.cookieCount > rhs.cookieCount }
                return lhs.name < rhs.name
            }
        isLoading = false
    }

    func delete(_ site: SiteData) async {
        await remove([site.record])
        await reload()
    }

    func deleteTrackers() async {
        await remove(sites.filter(\.isTracker).map(\.record))
        await reload()
    }

    /// Deletes every site's data except the kept ones (used by "Clear cookies when I quit").
    func deleteAll(keeping kept: Set<String>, thenReload: Bool = true) async {
        let records = await fetchRecords()
        await remove(records.filter { record in
            !kept.contains { record.displayName == $0 || record.displayName.hasSuffix("." + $0) }
        })
        if thenReload { await reload() }
    }

    // MARK: - WebKit calls, wrapped so we can `await` them

    private func fetchRecords() async -> [WKWebsiteDataRecord] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[WKWebsiteDataRecord], Never>) in
            dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                continuation.resume(returning: records)
            }
        }
    }

    private func fetchCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[HTTPCookie], Never>) in
            dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func remove(_ records: [WKWebsiteDataRecord]) async {
        guard !records.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {
                continuation.resume()
            }
        }
    }

    static func cookie(_ cookie: HTTPCookie, belongsTo site: String) -> Bool {
        var domain = cookie.domain.lowercased()
        if domain.hasPrefix(".") { domain.removeFirst() }
        return domain == site || domain.hasSuffix("." + site)
    }
}
