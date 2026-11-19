import Foundation
import Observation

/// One row in the list under the address bar.
struct Suggestion: Identifiable, Equatable {
    enum Kind: Equatable {
        /// An open tab: "Switch to Tab" instead of opening it twice.
        case tab(UUID)
        case bookmark
        case history
        /// A DuckDuckGo search suggestion.
        case search
    }

    let id = UUID()
    let kind: Kind
    let title: String
    /// The address shown under the title, or empty for searches.
    let detail: String
    let url: URL?

    var icon: String {
        switch kind {
        case .tab: "square.on.square"
        case .bookmark: "star.fill"
        case .history: "clock.arrow.circlepath"
        case .search: "magnifyingglass"
        }
    }
}

/// Finds address bar suggestions as you type: your open tabs, bookmarks
/// (Vela's and Safari's), history, and DuckDuckGo's search suggestions.
///
/// **How matches are ranked:** a site whose name *starts with* what you
/// typed ranks highest ("git" → github.com), then words in a page's title,
/// then anywhere in the address. Bookmarks and pages you visit often get
/// a boost. The best one becomes the **Top Hit**: Return opens it, the way
/// Safari does. Everything here happens on your Mac, except the DuckDuckGo
/// suggestions, which send what you type to DuckDuckGo (never in private tabs).
@MainActor
@Observable
final class SuggestionEngine {
    private(set) var items: [Suggestion] = []
    /// The highlighted row (↑/↓ move it). nil means "just use what I typed".
    var selected: Int?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var query = ""

    /// The highlighted suggestion, if any.
    var selectedItem: Suggestion? {
        guard let selected, items.indices.contains(selected) else { return nil }
        return items[selected]
    }

    func clear() {
        searchTask?.cancel()
        query = ""
        items = []
        selected = nil
    }

    func moveSelection(by step: Int) {
        guard !items.isEmpty else { return }
        let next = (selected ?? -1) + step
        selected = next < 0 ? nil : min(next, items.count - 1)
    }

    func update(for text: String, store: BrowserStore, tab: BrowserTab) {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed != query else { return }
        query = typed
        searchTask?.cancel()
        guard !typed.isEmpty else {
            items = []
            selected = nil
            return
        }

        let local = Self.localMatches(for: typed.lowercased(), store: store, current: tab)
        items = local
        // A strong match (the site's name starts with what you typed) is the Top Hit.
        selected = local.first.map { Self.isTopHit($0, for: typed) } == true ? 0 : nil

        // DuckDuckGo suggestions, after a short pause in typing.
        guard store.privacy.searchSuggestions, !tab.isPrivate, !typed.contains("://") else { return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let phrases = await Self.duckDuckGoSuggestions(for: typed)
            guard !Task.isCancelled, let self, self.query == typed else { return }
            let known = Set(local.map { $0.title.lowercased() })
            let searches = phrases
                .filter { !known.contains($0.lowercased()) && $0.lowercased() != typed.lowercased() }
                .prefix(4)
                .map { phrase in
                    Suggestion(kind: .search, title: phrase, detail: "", url: BrowserStore.url(from: phrase))
                }
            self.items = local + searches
        }
    }

    // MARK: Matching on your Mac

    private static func localMatches(for query: String, store: BrowserStore, current: BrowserTab) -> [Suggestion] {
        // Open tabs first (up to 3), so you switch instead of opening a duplicate.
        var seen = Set<String>()
        var results: [Suggestion] = []
        let tabs = store.tabs
            .filter { $0.id != current.id && $0.url != nil && (!$0.isPrivate || current.isPrivate) }
            .compactMap { tab -> (BrowserTab, Int)? in
                let score = Self.score(title: tab.title, url: tab.url!, query: query)
                return score > 0 ? (tab, score) : nil
            }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
        for (tab, _) in tabs {
            let url = tab.url!
            seen.insert(key(url))
            results.append(Suggestion(kind: .tab(tab.id), title: tab.title, detail: "Switch to Tab · " + shortAddress(url), url: url))
        }

        // Bookmarks and history, scored together.
        var visits: [String: Int] = [:]
        for entry in store.history { visits[key(entry.url), default: 0] += 1 }
        var candidates: [(Suggestion, Int)] = []
        let bookmarks = store.bookmarks + store.safariBookmarks.allBookmarks
        for bookmark in bookmarks {
            let base = score(title: bookmark.title, url: bookmark.url, query: query)
            guard base > 0 else { continue }
            let bonus = 15 + min((visits[key(bookmark.url)] ?? 0) * 5, 40)
            candidates.append((Suggestion(kind: .bookmark, title: bookmark.title, detail: shortAddress(bookmark.url), url: bookmark.url), base + bonus))
        }
        for (index, entry) in store.history.enumerated() {
            let base = score(title: entry.title, url: entry.url, query: query)
            guard base > 0 else { continue }
            // Pages you visit often, and recently, rank higher.
            let bonus = min((visits[key(entry.url)] ?? 0) * 5, 40) + (index < 50 ? 10 : 0)
            candidates.append((Suggestion(kind: .history, title: entry.title, detail: shortAddress(entry.url), url: entry.url), base + bonus))
        }
        for (suggestion, _) in candidates.sorted(by: { $0.1 > $1.1 }) {
            guard let url = suggestion.url, seen.insert(key(url)).inserted else { continue }
            results.append(suggestion)
            if results.count >= 7 { break }
        }
        return results
    }

    /// How well a page matches what you typed (0 means not at all).
    private static func score(title: String, url: URL, query: String) -> Int {
        let host = (url.host() ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
        let address = url.absoluteString.lowercased()
        let lowerTitle = title.lowercased()
        if host.hasPrefix(query) { return 100 }
        if host.split(separator: ".").contains(where: { $0.hasPrefix(query) }) { return 70 }
        if lowerTitle.hasPrefix(query) { return 60 }
        if lowerTitle.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(query) }) { return 45 }
        if query.count >= 3, lowerTitle.contains(query) { return 30 }
        if query.count >= 3, address.contains(query) { return 20 }
        return 0
    }

    /// Return opens a Top Hit only when the site's name starts with what you
    /// typed and you typed one word ("git" → github.com, but not "git tutorial").
    private static func isTopHit(_ suggestion: Suggestion, for typed: String) -> Bool {
        guard !typed.contains(" "), typed.count >= 2, let host = suggestion.url?.host()?.lowercased() else { return false }
        return host.replacingOccurrences(of: "www.", with: "").hasPrefix(typed.lowercased())
    }

    /// "https://www.github.com/" → "github.com"
    private static func shortAddress(_ url: URL) -> String {
        var text = url.absoluteString
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }

    /// The same page with or without "www." or a trailing "/" counts once.
    private static func key(_ url: URL) -> String {
        shortAddress(url).lowercased()
    }

    // MARK: DuckDuckGo

    /// Asks DuckDuckGo's autocomplete for search ideas.
    private static func duckDuckGoSuggestions(for query: String) async -> [String] {
        var components = URLComponents(string: "https://duckduckgo.com/ac/")!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: "list")]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession(configuration: .ephemeral).data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        // Usually ["what you typed", ["idea 1", "idea 2", …]]
        if let list = json as? [Any], list.count > 1, let phrases = list[1] as? [String] {
            return phrases
        }
        // Older format: [{"phrase": "idea 1"}, …]
        if let objects = json as? [[String: Any]] {
            return objects.compactMap { $0["phrase"] as? String }
        }
        return []
    }
}
