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

    // Privacy
    private(set) var privacy = PrivacySettings.load()
    private(set) var trackersBlockedTotal = UserDefaults.standard.integer(forKey: "vela.trackersBlockedTotal")
    private(set) var popupsBlockedTotal = UserDefaults.standard.integer(forKey: "vela.popupsBlockedTotal")
    /// The pop-up shown in the "Pop-up blocked" notice, if any.
    var blockedPopup: BlockedPopup?
    var isCookieManagerVisible = false
    let cookieManager = CookieManager()

    // Security
    let downloadManager = DownloadManager()
    let passwordVault = PasswordVault()
    let safeBrowsing = SafeBrowsing()
    var isPasswordsVisible = false

    // Claude
    let claude = ClaudeAssistant()
    var isClaudePanelVisible = false
    /// "Save password?" waiting for an answer.
    var passwordPrompt: PasswordPrompt?
    /// The compiled blocking rules every tab uses.
    @ObservationIgnored private var ruleList: WKContentRuleList?

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
        configuration = config

        let privateConfig = WKWebViewConfiguration()
        privateConfig.websiteDataStore = .nonPersistent()
        privateConfig.applicationNameForUserAgent = config.applicationNameForUserAgent
        privateConfiguration = privateConfig

        bookmarks = Self.loadBookmarks()
        history = Self.loadHistory()
        applyPopupSetting()
        downloadManager.settings = { [weak self] in self?.privacy ?? PrivacySettings() }
        downloadManager.checkThreat = { [weak self] url in await self?.safeBrowsing.check(url) }
        newTab()
        claude.store = self
        Task { await refreshBlockingRules() }
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
            isPrivate: makePrivate,
            ruleList: ruleList,
            privacy: privacy
        )
        connect(tab)

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

    /// A window a page opened (a target="_blank" link or a sign-in pop-up).
    /// It opens as a tab next to the page, still linked to it.
    func openWindow(configuration: WKWebViewConfiguration, url: URL?, opener: BrowserTab) -> WKWebView {
        let tab = BrowserTab(popupConfiguration: configuration, isPrivate: opener.isPrivate, url: url)
        connect(tab)
        if let index = tabs.firstIndex(where: { $0.id == opener.id }) {
            tab.groupID = opener.isPinned ? nil : opener.groupID
            tabs.insert(tab, at: index + 1)
        } else {
            tabs.append(tab)
        }
        selectedTabID = tab.id
        return tab.webView
    }

    /// Hooks a tab up to the store: history, the shield, downloads and passwords.
    private func connect(_ tab: BrowserTab) {
        tab.settings = { [weak self] in self?.privacy ?? PrivacySettings() }
        tab.checkThreat = { [weak self] url in await self?.safeBrowsing.check(url) }
        tab.onOpenInNewTab = { [weak self, weak tab] url in
            self?.newTab(url: url, opener: tab)
        }
        tab.onFinishLoading = { [weak self, weak tab] in
            if let tab { self?.recordVisit(tab) }
        }
        tab.onTrackerFound = { [weak self, weak tab] domain in
            if let tab { self?.recordTracker(domain, in: tab) }
        }
        tab.onPopupBlocked = { [weak self, weak tab] url, isPopUnder in
            if let tab { self?.recordBlockedPopup(url, isPopUnder: isPopUnder, in: tab) }
        }
        tab.onDownload = { [weak self, weak tab] download in
            self?.downloadManager.track(download, pageURL: tab?.url)
        }
        tab.onLoginFormFound = { [weak self, weak tab] host in
            if let tab, let self { tab.savedLogins = self.passwordVault.entries(for: host) }
        }
        tab.onLoginSubmitted = { [weak self, weak tab] host, username, password in
            if let tab { self?.offerToSave(host: host, username: username, password: password, from: tab) }
        }
        tab.onOpenWindow = { [weak self, weak tab] configuration, url in
            guard let self, let tab else { return nil }
            return self.openWindow(configuration: configuration, url: url, opener: tab)
        }
        tab.onCloseRequested = { [weak self, weak tab] in
            if let tab { self?.close(tab) }
        }
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

    /// Makes a group from these tabs (Claude uses this to group tabs by topic).
    @discardableResult
    func makeGroup(named name: String, color: GroupColor? = nil, tabs members: [BrowserTab]) -> TabGroup {
        let group = TabGroup(name: name, color: color ?? nextGroupColor())
        groups.append(group)
        for tab in members {
            tab.isPinned = false
            tab.groupID = group.id
        }
        removeEmptyGroups()
        return group
    }

    /// Opens the Claude panel and asks it something.
    func askClaudeInPanel(_ text: String) {
        isClaudePanelVisible = true
        claude.send(text)
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

    // MARK: - Privacy shield

    /// Changes privacy settings, saves them, and rebuilds the blocking rules
    /// and page scripts if needed. Pass a tab to reload it once the new rules are ready.
    func updatePrivacy(reloading tab: BrowserTab? = nil, _ change: (inout PrivacySettings) -> Void) {
        let old = privacy
        change(&privacy)
        guard privacy != old else { return }
        privacy.save()
        if privacy.blockPopups != old.blockPopups { applyPopupSetting() }
        if privacy.scriptInputs != old.scriptInputs {
            for tab in tabs { tab.installScripts(for: privacy) }
        }
        if privacy.ruleInputs != old.ruleInputs {
            Task {
                await refreshBlockingRules()
                tab?.webView.reload()
            }
        } else {
            tab?.webView.reload()
        }
    }

    func refreshBlockingRules() async {
        ruleList = await ContentBlocker.compile(for: privacy)
        for tab in tabs { tab.apply(ruleList: ruleList) }
    }

    private func applyPopupSetting() {
        // With this off, WebKit blocks pop-ups that you didn't click for.
        let allowed = !privacy.blockPopups
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = allowed
        privateConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = allowed
        for tab in tabs { tab.setPopupsAllowed(allowed) }
    }

    func shieldsUp(for tab: BrowserTab) -> Bool {
        guard let url = tab.url else { return true }
        return !privacy.shieldsDownSites.contains(Self.siteName(url))
    }

    /// Turns the shield off (or back on) for the tab's website, then reloads it.
    func toggleShields(for tab: BrowserTab) {
        guard let url = tab.url else { return }
        let site = Self.siteName(url)
        updatePrivacy(reloading: tab) { settings in
            if settings.shieldsDownSites.contains(site) {
                settings.shieldsDownSites.remove(site)
            } else {
                settings.shieldsDownSites.insert(site)
            }
        }
    }

    /// The script slider position for this tab's website.
    func scriptLevel(for tab: BrowserTab) -> ScriptLevel {
        privacy.scriptLevel(for: tab.url.map(Self.siteName))
    }

    /// Moves the script slider for one website, then reloads the tab.
    /// Choosing the same position as the global slider removes the override.
    func setScriptLevel(_ level: ScriptLevel, for tab: BrowserTab) {
        guard let url = tab.url else { return }
        let site = Self.siteName(url)
        updatePrivacy(reloading: tab) { settings in
            settings.siteScriptLevels[site] = level == settings.scriptLevel ? nil : level
        }
    }

    func isKept(_ site: String) -> Bool {
        privacy.keptSites.contains(site)
    }

    func toggleKept(_ site: String) {
        updatePrivacy { settings in
            if settings.keptSites.contains(site) {
                settings.keptSites.remove(site)
            } else {
                settings.keptSites.insert(site)
            }
        }
    }

    private func recordTracker(_ domain: String, in tab: BrowserTab) {
        guard privacy.blockingLevel != .off, shieldsUp(for: tab),
              !tab.trackersFound.contains(domain) else { return }
        tab.trackersFound.append(domain)
        trackersBlockedTotal += 1
        UserDefaults.standard.set(trackersBlockedTotal, forKey: "vela.trackersBlockedTotal")
    }

    private func recordBlockedPopup(_ url: URL?, isPopUnder: Bool, in tab: BrowserTab) {
        guard isPopUnder ? privacy.popUnderProtection : privacy.blockPopups else { return }
        if let url { tab.popupsBlocked.append(url) }
        popupsBlockedTotal += 1
        UserDefaults.standard.set(popupsBlockedTotal, forKey: "vela.popupsBlockedTotal")

        let popup = BlockedPopup(tabID: tab.id, url: url, isPopUnder: isPopUnder)
        blockedPopup = popup
        // Hide the notice after a few seconds.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if self?.blockedPopup?.id == popup.id { self?.blockedPopup = nil }
        }
    }

    /// "Allow once": opens the blocked pop-up as a new tab.
    func allowBlockedPopup() {
        guard let popup = blockedPopup, let url = popup.url else {
            blockedPopup = nil
            return
        }
        let opener = tabs.first { $0.id == popup.tabID }
        newTab(url: url, opener: opener)
        blockedPopup = nil
    }

    // MARK: - Passwords

    /// After you submit a login, offers to save it (unless it's already saved).
    private func offerToSave(host: String, username: String, password: String, from tab: BrowserTab) {
        guard !tab.isPrivate, privacy.offerToSavePasswords, !password.isEmpty else { return }
        let site = PasswordVault.normalize(host)
        guard !privacy.neverSavePasswordSites.contains(site) else { return }

        let existing = passwordVault.entries(for: site).first { $0.account == username }
        if let existing, passwordVault.password(for: existing) == password { return }
        passwordPrompt = PasswordPrompt(
            tabID: tab.id,
            server: site,
            account: username,
            password: password,
            isUpdate: existing != nil
        )
    }

    func savePromptedPassword() {
        guard let prompt = passwordPrompt else { return }
        passwordVault.save(server: prompt.server, account: prompt.account, password: prompt.password)
        passwordPrompt = nil
        refreshSavedLogins()
    }

    func neverSavePasswords(for site: String) {
        updatePrivacy { $0.neverSavePasswordSites.insert(site) }
        passwordPrompt = nil
    }

    /// Asks for Touch ID, then types the saved login into the page.
    func fill(_ entry: PasswordEntry, in tab: BrowserTab) async {
        guard await passwordVault.unlock(reason: "fill your password for \(entry.server)"),
              let password = passwordVault.password(for: entry) else { return }
        tab.fillLogin(username: entry.account, password: password, for: entry.server)
    }

    func deletePassword(_ entry: PasswordEntry) {
        passwordVault.delete(entry)
        refreshSavedLogins()
    }

    func savePassword(server: String, account: String, password: String) {
        passwordVault.save(server: server, account: account, password: password)
        refreshSavedLogins()
    }

    /// Updates the key button in every tab after the saved logins change.
    private func refreshSavedLogins() {
        for tab in tabs where !tab.savedLogins.isEmpty || tab.url != nil {
            guard let host = tab.url?.host() else { continue }
            if !tab.savedLogins.isEmpty || !passwordVault.entries(for: host).isEmpty {
                tab.savedLogins = passwordVault.entries(for: host)
            }
        }
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
