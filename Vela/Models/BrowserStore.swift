import AppKit
import Foundation
import Observation
import WebKit

/// The browser's "brain": all tabs, tab groups, bookmarks and history live here.
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
    var history: [HistoryEntry] = []

    // Window panels
    var isSidebarVisible = false
    var sidebarSection: SidebarSection = .bookmarks
    var isFindBarVisible = false

    /// Bumped by ⌘L; the address bar watches it and grabs keyboard focus.
    var addressBarFocusRequest = 0
    /// Bumped by ⌘F; the find bar watches it and grabs keyboard focus.
    var findBarFocusRequest = 0

    /// Shared settings for every normal tab's web view.
    @ObservationIgnored let configuration: WKWebViewConfiguration
    /// Settings for private tabs: a "non-persistent" data store keeps cookies
    /// and cache in memory only, so they vanish when Vela quits.
    @ObservationIgnored let privateConfiguration: WKWebViewConfiguration
    @ObservationIgnored private var recentlyClosed: [ClosedTab] = []

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Identify as Safari so websites serve their normal desktop pages.
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        // Pages can't open windows on their own; links still work (see TabCoordinator).
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration = config

        let privateConfig = WKWebViewConfiguration()
        privateConfig.websiteDataStore = .nonPersistent()
        privateConfig.applicationNameForUserAgent = config.applicationNameForUserAgent
        privateConfig.preferences.javaScriptCanOpenWindowsAutomatically = false
        privateConfiguration = privateConfig

        bookmarks = Self.loadBookmarks()
        history = Self.loadHistory()
        newTab()
    }

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedTabID }
    }

    var canReopenClosedTab: Bool { !recentlyClosed.isEmpty }

    // MARK: - Tabs

    @discardableResult
    func newTab(url: URL? = nil, opener: BrowserTab? = nil, isPrivate: Bool = false, select: Bool = true) -> BrowserTab {
        let makePrivate = isPrivate || (opener?.isPrivate ?? false)
        let tab = BrowserTab(
            configuration: makePrivate ? privateConfiguration : configuration,
            isPrivate: makePrivate
        )
        tab.onOpenInNewTab = { [weak self, weak tab] url in
            self?.newTab(url: url, opener: tab)
        }
        tab.onFinishLoading = { [weak self, weak tab] in
            if let tab { self?.recordVisit(tab) }
        }

        // Open next to the tab that opened it, inside the same group.
        if let opener, let index = tabs.firstIndex(where: { $0.id == opener.id }) {
            tab.groupID = opener.isPinned ? nil : opener.groupID
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

    /// Selects the tab to the right (or left with `forward: false`), wrapping around.
    func selectAdjacentTab(forward: Bool) {
        let visible = stripItems.compactMap { item -> BrowserTab? in
            if case .tab(let tab) = item { return tab } else { return nil }
        }
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selectedTabID } ?? 0
        let next = (current + (forward ? 1 : -1) + visible.count) % visible.count
        selectedTabID = visible[next].id
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if let url = tab.url {
            recentlyClosed.append(ClosedTab(url: url, groupID: tab.groupID, isPrivate: tab.isPrivate))
            if recentlyClosed.count > 20 { recentlyClosed.removeFirst() }
        }
        tab.webView.stopLoading()
        tabs.remove(at: index)
        removeEmptyGroups()

        if tabs.isEmpty {
            newTab()
        } else if selectedTabID == tab.id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
    }

    func closeOtherTabs(except keep: BrowserTab) {
        for tab in tabs where tab.id != keep.id && !tab.isPinned { close(tab) }
        selectedTabID = keep.id
    }

    func closeTabsToTheRight(of tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        for other in tabs[(index + 1)...] where !other.isPinned { close(other) }
    }

    /// ⇧⌘T: brings back the most recently closed tab.
    func reopenClosedTab() {
        guard let closed = recentlyClosed.popLast() else { return }
        let tab = newTab(url: closed.url, isPrivate: closed.isPrivate)
        if let groupID = closed.groupID, groups.contains(where: { $0.id == groupID }) {
            tab.groupID = groupID
        }
    }

    func duplicate(_ tab: BrowserTab) {
        newTab(url: tab.url, opener: tab)
    }

    func togglePin(_ tab: BrowserTab) {
        tab.isPinned.toggle()
        if tab.isPinned {
            tab.groupID = nil
            removeEmptyGroups()
        }
    }

    func copyLink(of tab: BrowserTab) {
        guard let url = tab.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
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

    /// The order the tab strip draws things in: pinned tabs first, then
    /// everything else. Tabs in a group are drawn together right after their
    /// group's chip, and hidden when it's collapsed.
    var stripItems: [StripItem] {
        var items: [StripItem] = tabs.filter(\.isPinned).map { StripItem.tab($0) }
        var seenGroups = Set<UUID>()

        for tab in tabs where !tab.isPinned {
            guard let groupID = tab.groupID,
                  let group = groups.first(where: { $0.id == groupID }) else {
                items.append(.tab(tab))
                continue
            }
            if seenGroups.contains(groupID) { continue }
            seenGroups.insert(groupID)

            items.append(.group(group))
            if !group.isCollapsed {
                items += tabs.filter { $0.groupID == groupID && !$0.isPinned }.map { StripItem.tab($0) }
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

    /// How many open, unpinned tabs show the same website as this one.
    func sameSiteTabCount(as tab: BrowserTab) -> Int {
        guard let url = tab.url else { return 0 }
        let site = Self.siteName(url)
        return tabs.filter { !$0.isPinned && $0.url.map(Self.siteName) == site }.count
    }

    /// Combines similar tabs: any website open in two or more ungrouped tabs
    /// gets its own group.
    func groupSimilarTabs() {
        let ungrouped = tabs.filter { $0.groupID == nil && !$0.isPinned && $0.url != nil }
        let bySite = Dictionary(grouping: ungrouped) { Self.siteName($0.url!) }

        for (site, siteTabs) in bySite.sorted(by: { $0.key < $1.key }) where siteTabs.count >= 2 {
            let group = TabGroup(name: site, color: nextGroupColor())
            groups.append(group)
            siteTabs.forEach { $0.groupID = group.id }
        }
    }

    /// Puts every tab from this tab's website into one group, joining the
    /// tab's existing group if it already has one.
    func groupTabsFromSameSite(as tab: BrowserTab) {
        guard let url = tab.url else { return }
        let site = Self.siteName(url)
        let target: TabGroup
        if let existing = group(for: tab) {
            target = existing
        } else {
            target = TabGroup(name: site, color: nextGroupColor())
            groups.append(target)
        }
        for other in tabs where !other.isPinned && other.url.map(Self.siteName) == site {
            other.groupID = target.id
        }
        removeEmptyGroups()
    }

    func addToNewGroup(_ tab: BrowserTab) {
        let name = tab.url.map(Self.siteName) ?? "New Group"
        let group = TabGroup(name: name, color: nextGroupColor())
        groups.append(group)
        tab.isPinned = false
        tab.groupID = group.id
        removeEmptyGroups()
    }

    func move(_ tab: BrowserTab, to group: TabGroup) {
        tab.isPinned = false
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
        let used = Set(groups.map(\.color))
        return GroupColor.allCases.first { !used.contains($0) }
            ?? GroupColor.allCases[groups.count % GroupColor.allCases.count]
    }

    private func removeEmptyGroups() {
        groups.removeAll { group in !tabs.contains { $0.groupID == group.id } }
    }

    // MARK: - Panels

    func showSidebar(_ section: SidebarSection) {
        if isSidebarVisible && sidebarSection == section {
            isSidebarVisible = false
        } else {
            sidebarSection = section
            isSidebarVisible = true
        }
    }

    func showFindBar() {
        isFindBarVisible = true
        findBarFocusRequest += 1
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

    func addBookmarksForAllTabs() {
        for tab in tabs {
            guard let url = tab.url, !isBookmarked(url) else { continue }
            bookmarks.append(Bookmark(title: tab.title, url: url))
        }
        saveBookmarks()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }

    func open(_ url: URL, inNewTab: Bool = false) {
        if !inNewTab, let tab = selectedTab {
            tab.load(url)
        } else {
            newTab(url: url)
        }
    }

    func open(_ bookmark: Bookmark) {
        open(bookmark.url)
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

    // MARK: - History

    private static let historyKey = "vela.history"
    private static let historyLimit = 1000

    /// Saves a visit, unless the tab is private or it's the same page as the last visit.
    func recordVisit(_ tab: BrowserTab) {
        guard !tab.isPrivate, let url = tab.url, url.scheme?.hasPrefix("http") == true else { return }
        if let last = history.first, last.url == url {
            history[0].title = tab.title
            history[0].date = Date()
        } else {
            history.insert(HistoryEntry(title: tab.title, url: url, date: Date()), at: 0)
            if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        }
        saveHistory()
    }

    func removeHistoryEntry(_ entry: HistoryEntry) {
        history.removeAll { $0.id == entry.id }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    private static func loadHistory() -> [HistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return [] }
        return saved
    }
}
