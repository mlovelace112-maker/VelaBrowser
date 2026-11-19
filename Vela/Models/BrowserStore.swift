import Foundation
import Observation
import WebKit

/// The browser's "brain": all tabs, tab groups and bookmarks live here.
///
/// Views never change data directly. They call methods on the store, such as
/// `newTab()`, `close(_:)` or `groupSimilarTabs()`, and SwiftUI redraws
/// whatever changed. Keeping the logic in one place makes it easy to add
/// features later, like Claude controlling the browser.
@MainActor
@Observable
final class BrowserStore {
    var tabs: [BrowserTab] = []
    var groups: [TabGroup] = []
    var selectedTabID: UUID?
    var bookmarks: [Bookmark] = []
    /// Bumped by ⌘L; the address bar watches it and grabs keyboard focus.
    var addressBarFocusRequest = 0

    /// Shared settings for every tab's web view.
    @ObservationIgnored let configuration: WKWebViewConfiguration

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Identify as Safari so websites serve their normal desktop pages.
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        // Pages can't open windows on their own; links still work (see TabCoordinator).
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration = config

        bookmarks = Self.loadBookmarks()
        newTab()
    }

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedTabID }
    }

    // MARK: - Tabs

    @discardableResult
    func newTab(url: URL? = nil, opener: BrowserTab? = nil, select: Bool = true) -> BrowserTab {
        let tab = BrowserTab(configuration: configuration)
        tab.onOpenInNewTab = { [weak self, weak tab] url in
            self?.newTab(url: url, opener: tab)
        }

        // Open next to the tab that opened it, inside the same group.
        if let opener, let index = tabs.firstIndex(where: { $0.id == opener.id }) {
            tab.groupID = opener.groupID
            tabs.insert(tab, at: index + 1)
        } else {
            tabs.append(tab)
        }

        if let url { tab.load(url) }
        if select { selectedTabID = tab.id }
        if url == nil { addressBarFocusRequest += 1 }
        return tab
    }

    func select(_ tab: BrowserTab) {
        selectedTabID = tab.id
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tab.webView.stopLoading()
        tabs.remove(at: index)
        removeEmptyGroups()

        if tabs.isEmpty {
            newTab()
        } else if selectedTabID == tab.id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
    }

    /// Loads whatever was typed: a web address, or a search if it isn't one.
    func navigate(_ input: String, in tab: BrowserTab? = nil) {
        guard let target = tab ?? selectedTab, let url = Self.url(from: input) else { return }
        target.load(url)
    }

    /// Turns typed text into a URL. "apple.com" becomes https://apple.com,
    /// and "best pizza near me" becomes a DuckDuckGo search.
    static func url(from input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about"].contains(scheme) {
            return url
        }
        if text.hasPrefix("localhost"), let url = URL(string: "http://" + text) {
            return url
        }
        if !text.contains(" "), text.contains("."),
           let url = URL(string: "https://" + text), url.host() != nil {
            return url
        }

        var search = URLComponents(string: "https://duckduckgo.com/")!
        search.queryItems = [URLQueryItem(name: "q", value: text)]
        return search.url
    }

    /// "www.apple.com" → "apple.com"
    static func siteName(_ url: URL) -> String {
        var host = url.host() ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    // MARK: - Tab groups

    /// The order the tab strip draws things in. Tabs in a group are drawn
    /// together right after their group's chip, and hidden when it's collapsed.
    var stripItems: [StripItem] {
        var items: [StripItem] = []
        var seenGroups = Set<UUID>()

        for tab in tabs {
            guard let groupID = tab.groupID,
                  let group = groups.first(where: { $0.id == groupID }) else {
                items.append(.tab(tab))
                continue
            }
            if seenGroups.contains(groupID) { continue }
            seenGroups.insert(groupID)

            items.append(.group(group))
            if !group.isCollapsed {
                items += tabs.filter { $0.groupID == groupID }.map { StripItem.tab($0) }
            }
        }
        return items
    }

    func group(for tab: BrowserTab) -> TabGroup? {
        guard let groupID = tab.groupID else { return nil }
        return groups.first { $0.id == groupID }
    }

    func tabCount(in group: TabGroup) -> Int {
        tabs.filter { $0.groupID == group.id }.count
    }

    /// Combines similar tabs: any website open in two or more ungrouped tabs
    /// gets its own group.
    func groupSimilarTabs() {
        let ungrouped = tabs.filter { $0.groupID == nil && $0.url != nil }
        let bySite = Dictionary(grouping: ungrouped) { Self.siteName($0.url!) }

        for (site, siteTabs) in bySite.sorted(by: { $0.key < $1.key }) where siteTabs.count >= 2 {
            let group = TabGroup(name: site, color: nextGroupColor())
            groups.append(group)
            siteTabs.forEach { $0.groupID = group.id }
        }
    }

    func addToNewGroup(_ tab: BrowserTab) {
        let name = tab.url.map(Self.siteName) ?? "New Group"
        let group = TabGroup(name: name, color: nextGroupColor())
        groups.append(group)
        tab.groupID = group.id
    }

    func move(_ tab: BrowserTab, to group: TabGroup) {
        tab.groupID = group.id
        removeEmptyGroups()
    }

    func removeFromGroup(_ tab: BrowserTab) {
        tab.groupID = nil
        removeEmptyGroups()
    }

    func toggleCollapsed(_ group: TabGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].isCollapsed.toggle()

        // If we just hid the tab you're looking at, switch to a visible one.
        if groups[index].isCollapsed, selectedTab?.groupID == group.id,
           let visible = tabs.first(where: { $0.groupID != group.id }) {
            selectedTabID = visible.id
        }
    }

    func rename(_ group: TabGroup, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].name = trimmed
    }

    func setColor(_ color: GroupColor, for group: TabGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].color = color
    }

    func ungroup(_ group: TabGroup) {
        for tab in tabs where tab.groupID == group.id { tab.groupID = nil }
        groups.removeAll { $0.id == group.id }
    }

    func closeGroup(_ group: TabGroup) {
        for tab in tabs.filter({ $0.groupID == group.id }) { close(tab) }
    }

    private func nextGroupColor() -> GroupColor {
        GroupColor.allCases[groups.count % GroupColor.allCases.count]
    }

    private func removeEmptyGroups() {
        groups.removeAll { group in !tabs.contains { $0.groupID == group.id } }
    }

    // MARK: - Bookmarks

    func isBookmarked(_ url: URL?) -> Bool {
        guard let url else { return false }
        return bookmarks.contains { $0.url == url }
    }

    func toggleBookmark(for tab: BrowserTab) {
        guard let url = tab.url else { return }
        if let index = bookmarks.firstIndex(where: { $0.url == url }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.append(Bookmark(title: tab.title, url: url))
        }
        saveBookmarks()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }

    func open(_ bookmark: Bookmark) {
        if let tab = selectedTab {
            tab.load(bookmark.url)
        } else {
            newTab(url: bookmark.url)
        }
    }

    private static let bookmarksKey = "vela.bookmarks"

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: Self.bookmarksKey)
        }
    }

    private static func loadBookmarks() -> [Bookmark] {
        if let data = UserDefaults.standard.data(forKey: bookmarksKey),
           let saved = try? JSONDecoder().decode([Bookmark].self, from: data) {
            return saved
        }
        // Starter bookmarks the first time Vela opens.
        return [
            Bookmark(title: "DuckDuckGo", url: URL(string: "https://duckduckgo.com")!),
            Bookmark(title: "Spotify", url: URL(string: "https://open.spotify.com")!),
            Bookmark(title: "YouTube", url: URL(string: "https://www.youtube.com")!),
            Bookmark(title: "Wikipedia", url: URL(string: "https://www.wikipedia.org")!),
            Bookmark(title: "GitHub", url: URL(string: "https://github.com")!),
            Bookmark(title: "Claude", url: URL(string: "https://claude.ai")!),
        ]
    }
}
