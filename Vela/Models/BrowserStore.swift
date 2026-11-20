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
    var tabs: [BrowserTab] = [] {
        didSet {
            // Tell running Safari extensions about tabs that opened or closed.
            let before = Set(oldValue.map(\.id)), after = Set(tabs.map(\.id))
            guard before != after else { return }
            for tab in tabs where !before.contains(tab.id) { extensions.tabOpened(tab) }
            for tab in oldValue where !after.contains(tab.id) { extensions.tabClosed(tab) }
        }
    }
    var groups: [TabGroup] = []
    /// Separate cookie jars for tabs (Personal, Work…). See Containers.swift.
    var containers: [TabContainer] = BrowserStore.loadContainers()
    @ObservationIgnored var containerConfigurations: [UUID: WKWebViewConfiguration] = [:]
    /// Two tabs side by side, or nil. See Containers.swift.
    var splitPair: SplitPair?
    /// Tabs in a list down the left side instead of along the top.
    var verticalTabs = UserDefaults.standard.bool(forKey: "vela.verticalTabs") {
        didSet { UserDefaults.standard.set(verticalTabs, forKey: "vela.verticalTabs") }
    }
    var selectedTabID: UUID? {
        didSet {
            guard selectedTabID != oldValue else { return }
            // Picking a tab outside split view leaves split view.
            if let pair = splitPair, !pair.contains(selectedTabID) { splitPair = nil }
            // Remember when you left the old tab (for tab sleeping), and
            // wake the new one if it was asleep.
            if let old = tabs.first(where: { $0.id == oldValue }) {
                old.lastActive = Date()
                old.capturePreview() // still on screen at this moment
            }
            extensions.tabActivated(selectedTab, previous: tabs.first { $0.id == oldValue })
            if let tab = selectedTab {
                tab.lastActive = Date()
                if !isStarting { tab.wake() }
            }
        }
    }
    /// True until the blocking rules are ready at launch, so restored tabs
    /// don't load before the shield is up.
    @ObservationIgnored private var isStarting = true
    var bookmarks: [Bookmark] = []
    var history: [HistoryEntry] = []
    /// Pages saved to read later. See PageTools.swift.
    var readingList: [ReadingItem] = BrowserStore.loadReadingList()

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
    var isSiteSettingsVisible = false
    let cookieManager = CookieManager()

    // Security
    let downloadManager = DownloadManager()
    let passwordVault = PasswordVault()
    let safeBrowsing = SafeBrowsing()
    var isPasswordsVisible = false

    /// Private @duck.com addresses (see EmailMasking.swift).
    let emailMasking = EmailMasking()

    // Tabs: session restore and sleeping
    /// Reopen the tabs you had open when you last quit.
    var restoresSession = UserDefaults.standard.object(forKey: "vela.restoreSession") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(restoresSession, forKey: "vela.restoreSession")
            saveSession()
        }
    }
    /// Tabs you haven't looked at for this many minutes go to sleep (0 = never).
    var tabSleepMinutes = UserDefaults.standard.object(forKey: "vela.tabSleepMinutes") as? Int ?? 30 {
        didSet { UserDefaults.standard.set(tabSleepMinutes, forKey: "vela.tabSleepMinutes") }
    }
    /// Tabs you haven't opened for this many days close and move to
    /// Tabs ▸ Archived Tabs (0 = never). See TabArchive.swift.
    var archiveAfterDays = UserDefaults.standard.object(forKey: "vela.archiveAfterDays") as? Int ?? 7 {
        didSet { UserDefaults.standard.set(archiveAfterDays, forKey: "vela.archiveAfterDays") }
    }
    /// Tabs Vela tidied away, newest first.
    var archivedTabs: [ArchivedTab] = BrowserStore.loadArchivedTabs()

    // Weekly activity and privacy report (ActivityLog.swift)
    let activity = ActivityLog()
    var isActivityReportVisible = false
    /// "What was that page?" (PageMemory.swift)
    let pageMemory = PageMemory()
    var isPageFinderVisible = false
    /// The Claude tools sheet: compare tabs, video summary, site check.
    var pageTool: PageToolState?
    /// True while Claude sorts your bookmarks into folders.
    var isOrganizingBookmarks = false
    /// A question to start the page finder with (from the command bar).
    var pageFinderQuestion = ""

    // Command bar (⌘K) and link previews (hold ⌥ over a link)
    var isCommandBarVisible = false
    var linkPreview: LinkPreview?

    // Dark mode for every site (SiteTools.swift)
    var darkModeEverywhere = DarkMode.isEnabled {
        didSet { applyDarkModeSettings() }
    }
    var darkModeOffSites = DarkMode.offSites {
        didSet { applyDarkModeSettings() }
    }

    // Focus mode (SiteTools.swift)
    /// When the current focus session ends (.distantFuture: when you stop it).
    var focusUntil: Date?
    var focusSites = UserDefaults.standard.stringArray(forKey: "vela.focusSites") ?? BrowserStore.defaultFocusSites {
        didSet { saveFocusSettings() }
    }
    var focusSchedule = BrowserStore.loadFocusSchedule() {
        didSet { saveFocusSettings(); checkFocus() }
    }
    /// Sites you're taking a 5-minute break on, and when the break ends.
    var focusBreaks: [String: Date] = [:]

    // Web panels (SiteTools.swift)
    var webPanels = BrowserStore.loadWebPanels()
    var selectedPanelID: UUID?
    var isWebPanelVisible = false
    @ObservationIgnored var panelWebViews: [UUID: WKWebView] = [:]
    @ObservationIgnored var panelCoordinators: [UUID: WebPanelCoordinator] = [:]

    // Claude
    let claude = ClaudeAssistant()
    /// Safari extensions from your Mac's apps (SafariExtensions.swift).
    let extensions: SafariExtensions
    /// Talk to Claude (⌥⌘A).
    let voice = VoiceInput()
    var isClaudePanelVisible = false

    // Spotify
    let spotify = SpotifyPlayer()

    /// Safari's bookmarks, read live (see SafariBookmarks.swift).
    let safariBookmarks = SafariBookmarks()
    let defaultBrowser = DefaultBrowser()
    /// "Save password?" waiting for an answer.
    var passwordPrompt: PasswordPrompt?
    /// The compiled blocking rules every tab uses.
    @ObservationIgnored private(set) var ruleList: WKContentRuleList?

    /// Shared settings for every normal tab's web view.
    @ObservationIgnored let configuration: WKWebViewConfiguration
    /// Settings for private tabs: a "non-persistent" data store keeps cookies
    /// and cache in memory only, so they vanish when Vela quits.
    @ObservationIgnored let privateConfiguration: WKWebViewConfiguration
    @ObservationIgnored private var recentlyClosed: [ClosedTab] = []

    init() {
        let extensions = SafariExtensions()
        self.extensions = extensions
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Normal tabs (and containers, which copy this) can run extensions;
        // private tabs never do.
        config.webExtensionController = extensions.controller
        // Identify as Safari so websites serve their normal desktop pages.
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        Self.harden(config)
        configuration = config

        let privateConfig = WKWebViewConfiguration()
        privateConfig.websiteDataStore = .nonPersistent()
        privateConfig.applicationNameForUserAgent = config.applicationNameForUserAgent
        Self.harden(privateConfig)
        privateConfiguration = privateConfig

        bookmarks = Self.loadBookmarks()
        history = Self.loadHistory()
        applyPopupSetting()
        downloadManager.settings = { [weak self] in self?.privacy ?? PrivacySettings() }
        downloadManager.checkThreat = { [weak self] url in await self?.safeBrowsing.check(url) }
        if !restoreSession() { newTab() }
        claude.store = self
        extensions.store = self
        extensions.start()
        Task {
            await refreshBlockingRules()
            isStarting = false
            selectedTab?.wake()
        }
        startTabSleepTimer()
        startActivityClock()
    }

    /// Safer WebKit settings for every tab.
    private static func harden(_ config: WKWebViewConfiguration) {
        // Safari's own warning for known phishing and malware sites.
        config.preferences.isFraudulentWebsiteWarningEnabled = true
        // Go straight to https:// for sites known to support it (the HSTS list).
        config.upgradeKnownHostsToHTTPS = true
        // Pages can't open windows on their own; Vela's pop-up setting decides.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
    }

    /// "Continue to Site (Not Secure)" on the HTTPS-Only warning.
    func continueInsecure(in tab: BrowserTab) {
        guard let url = tab.httpsWarning else { return }
        tab.httpsWarning = nil
        updatePrivacy { $0.httpAllowedSites.insert(Self.siteName(url)) }
        Task {
            await refreshBlockingRules()
            tab.load(url)
        }
    }

    /// "Go Back" on the HTTPS-Only warning.
    func dismissHTTPSWarning(in tab: BrowserTab) {
        tab.httpsWarning = nil
        if tab.webView.url == nil { tab.url = nil }
    }

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedTabID }
    }

    var canReopenClosedTab: Bool { !recentlyClosed.isEmpty }

    // MARK: - Tabs

    @discardableResult
    func newTab(url: URL? = nil, opener: BrowserTab? = nil, isPrivate: Bool = false, select: Bool = true, container: UUID?? = nil) -> BrowserTab {
        let makePrivate = isPrivate || (opener?.isPrivate ?? false)
        // A tab opened from a container tab stays in that container, unless
        // a container (or none) was asked for.
        let containerID = makePrivate ? nil : (container ?? opener?.containerID)
        let tab = BrowserTab(
            configuration: makePrivate ? privateConfiguration : configuration(forContainer: containerID),
            isPrivate: makePrivate,
            ruleList: ruleList,
            privacy: privacy
        )
        tab.containerID = containerID
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
        tab.containerID = opener.containerID
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
        tab.isFocusBlocked = { [weak self] url in self?.focusBlockedSite(for: url) != nil }
        tab.checkThreat = { [weak self] url in await self?.safeBrowsing.check(url) }
        tab.onOpenInNewTab = { [weak self, weak tab] url in
            self?.newTab(url: url, opener: tab)
        }
        tab.onFinishLoading = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.recordVisit(tab)
            self.rememberPage(in: tab)
            self.extensions.tabChanged(tab)
            if tab.id == self.selectedTabID {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    if tab.id == self.selectedTabID { tab.capturePreview() }
                }
            }
            Task { await tab.detectLanguage() }
            if tab.pendingCode != nil { Task { await self.fillPendingCode(in: tab) } }
        }
        (tab.webView as? VelaWebView)?.onTextAction = { [weak self, weak tab] action in
            if let tab { self?.perform(action, in: tab) }
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
            guard let tab, let self else { return }
            tab.savedLogins = self.passwordVault.entries(for: host)
            // Already unlocked in the last 10 minutes and only one login for
            // this site? Fill it right away, no click needed.
            if self.privacy.autoFillPasswords, !tab.didAutoFill,
               tab.savedLogins.count == 1, self.passwordVault.isRecentlyUnlocked {
                Task { await self.fill(tab.savedLogins[0], in: tab) }
            }
        }
        tab.onLoginFieldFocused = { [weak self, weak tab] host in
            guard let tab, let self else { return }
            if tab.savedLogins.isEmpty { tab.savedLogins = self.passwordVault.entries(for: host) }
            self.autoFill(in: tab)
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
        tab.onMediaPermission = { [weak self, weak tab] site, kinds, answer in
            guard let self, let tab else { answer(false); return }
            self.decideMediaPermission(site: site, kinds: kinds, in: tab, answer: answer)
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
            recentlyClosed.append(ClosedTab(url: url, groupID: tab.groupID, isPrivate: tab.isPrivate, containerID: tab.containerID))
            if recentlyClosed.count > 20 { recentlyClosed.removeFirst() }
        }
        tab.webView.stopLoading()
        if splitPair?.contains(tab.id) == true { splitPair = nil }
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
        let tab = newTab(url: closed.url, isPrivate: closed.isPrivate, container: closed.containerID)
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

    /// Shows Vela's image or video grid for a search, in this tab or the selected one.
    func showMediaSearch(_ query: String, kind: MediaSearch.Kind, in tab: BrowserTab? = nil) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let target = tab ?? selectedTab ?? newTab()
        let search = MediaSearch(query: trimmed, kind: kind)
        target.mediaSearch = search
        target.title = search.title
        selectedTabID = target.id
        search.search()
    }

    /// The search words if this is a DuckDuckGo results page.
    static func duckDuckGoQuery(_ url: URL?) -> String? {
        guard let url, let host = url.host(), host == "duckduckgo.com" || host.hasSuffix(".duckduckgo.com"),
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value,
              !query.isEmpty else { return nil }
        return query
    }

    /// A short notice such as "Reader isn't available for this page".
    var pageNotice: String?

    /// Turns Reader mode on or off for a tab (⇧⌘R).
    func toggleReader(for tab: BrowserTab? = nil) async {
        guard let tab = tab ?? selectedTab else { return }
        if tab.reader != nil {
            tab.reader = nil
            return
        }
        guard tab.url != nil, tab.mediaSearch == nil, !tab.isLoading || tab.progress > 0.6 else { return }
        do {
            tab.reader = try await Reader.extract(from: tab)
        } catch {
            showNotice("Reader isn't available for this page.")
        }
    }

    func showNotice(_ text: String) {
        pageNotice = text
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if pageNotice == text { pageNotice = nil }
        }
    }

    /// Copies Safari's bookmarks into Vela's own list, skipping ones you already have.
    @discardableResult
    func importSafariBookmarks() -> Int {
        safariBookmarks.reload(force: true)
        var known = Set(bookmarks.map(\.url))
        var added = 0
        for bookmark in safariBookmarks.allBookmarks where !known.contains(bookmark.url) {
            bookmarks.append(Bookmark(title: bookmark.title, url: bookmark.url))
            known.insert(bookmark.url)
            added += 1
        }
        if added > 0 { saveBookmarks() }
        return added
    }

    /// A link or file opened from another app.
    func openExternal(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        guard ["http", "https", "file"].contains(scheme) else { return }
        if let tab = selectedTab, tab.url == nil, tab.mediaSearch == nil {
            tab.load(url)
        } else {
            newTab(url: url)
        }
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
        for tab in tabs { tab.setPopupsAllowed(privacy.allowsPopups(on: tab.url.map(Self.siteName))) }
    }

    /// Whether this tab's website may open pop-ups (Site Settings).
    func allowsPopups(for tab: BrowserTab) -> Bool {
        guard let url = tab.url else { return false }
        return privacy.popupAllowedSites.contains(Self.siteName(url))
    }

    /// Lets one website open pop-ups even with "Block pop-ups" on, or stops it.
    func setPopupsAllowed(_ allowed: Bool, for site: String) {
        updatePrivacy { settings in
            if allowed { settings.popupAllowedSites.insert(site) } else { settings.popupAllowedSites.remove(site) }
        }
        for tab in tabs where tab.url.map(Self.siteName) == site {
            tab.setPopupsAllowed(privacy.allowsPopups(on: site))
        }
    }

    // MARK: - Camera and microphone

    /// Uses your remembered answer for the site, or asks with a banner.
    private func decideMediaPermission(site: String, kinds: [PermissionKind], in tab: BrowserTab, answer: @escaping @MainActor (Bool) -> Void) {
        let remembered = kinds.map { privacy.permission($0, for: site) }
        if remembered.contains(false) { answer(false); return }
        if !remembered.contains(nil) { answer(true); return }
        tab.permissionRequest?.answer(false) // Only one question at a time.
        tab.permissionRequest = PermissionRequest(site: site, kinds: kinds, answer: answer)
    }

    /// Your answer on the camera/microphone banner.
    func answerPermission(in tab: BrowserTab, allow: Bool, remember: Bool) {
        guard let request = tab.permissionRequest else { return }
        tab.permissionRequest = nil
        if remember && !tab.isPrivate {
            updatePrivacy { settings in
                for kind in request.kinds { settings.setPermission(kind, allow, for: request.site) }
            }
        }
        request.answer(allow)
    }

    // MARK: - Picture in picture and private email

    /// Floats the page's video in a small window that stays on top (⌥⌘V).
    func togglePictureInPicture() async {
        guard let tab = selectedTab, tab.url != nil, !tab.isAsleep else { return }
        switch await tab.togglePictureInPicture() {
        case "none": showNotice("There's no video on this page.")
        case "unsupported": showNotice("This video can't play in picture in picture.")
        default: break
        }
    }

    /// Makes a new @duck.com address, types it into the email box, and copies it (⌥⌘E).
    func fillPrivateEmail() async {
        guard let tab = selectedTab, tab.url != nil else { return }
        guard emailMasking.isConnected else {
            showNotice("Set up email masking first: Settings ▸ Privacy ▸ Email masking.")
            return
        }
        do {
            let address = try await emailMasking.newAddress()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(address, forType: .string)
            let filled = await tab.fillEmail(address)
            showNotice(filled ? "Filled in \(address) (also copied)." : "Copied \(address). Paste it into the email box.")
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    // MARK: - Session restore and tab sleeping

    private static let sessionKey = "vela.session"

    private struct SavedSession: Codable {
        var tabs: [SavedTab]
        var groups: [TabGroup]
        var selected: Int?
    }

    private struct SavedTab: Codable {
        var url: URL
        var title: String
        var isPinned: Bool
        var groupID: UUID?
        var containerID: UUID?
        /// When you last looked at the tab, so tab tidy-up still knows
        /// after a restart. (Optional: older saved sessions don't have it.)
        var lastActive: Date?
    }

    /// Saves your open tabs (never private ones) so the next launch can reopen them.
    /// Runs every minute and when you quit, so even a crash loses little.
    func saveSession() {
        guard restoresSession else {
            UserDefaults.standard.removeObject(forKey: Self.sessionKey)
            return
        }
        let kept = tabs.filter { tab in
            !tab.isPrivate && tab.mediaSearch == nil
                && ["http", "https"].contains(tab.url?.scheme?.lowercased() ?? "")
        }
        let saved = kept.compactMap { tab in
            tab.url.map { SavedTab(url: $0, title: tab.title, isPinned: tab.isPinned, groupID: tab.groupID,
                                   containerID: tab.containerID, lastActive: tab.lastActive) }
        }
        let usedGroups = groups.filter { group in saved.contains { $0.groupID == group.id } }
        let session = SavedSession(tabs: saved, groups: usedGroups, selected: kept.firstIndex { $0.id == selectedTabID })
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        }
    }

    /// Reopens last session's tabs, asleep, so nothing loads until you look at it.
    private func restoreSession() -> Bool {
        guard restoresSession,
              let data = UserDefaults.standard.data(forKey: Self.sessionKey),
              let session = try? JSONDecoder().decode(SavedSession.self, from: data),
              !session.tabs.isEmpty else { return false }
        groups = session.groups
        for saved in session.tabs {
            let tab = BrowserTab(configuration: configuration(forContainer: saved.containerID), ruleList: ruleList, privacy: privacy)
            tab.containerID = containers.contains { $0.id == saved.containerID } ? saved.containerID : nil
            connect(tab)
            tab.isPinned = saved.isPinned
            tab.groupID = saved.isPinned ? nil : saved.groupID
            tab.restoreAsleep(url: saved.url, title: saved.title)
            tab.lastActive = saved.lastActive ?? Date()
            tabs.append(tab)
        }
        removeEmptyGroups()
        let index = min(max(session.selected ?? 0, 0), tabs.count - 1)
        selectedTabID = tabs[index].id
        return true
    }

    private func startTabSleepTimer() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                await self.sleepIdleTabs()
                self.archiveIdleTabs()
                self.checkFocus()
                self.activity.save()
                self.pageMemory.save()
                self.announceWeeklyReportIfDue()
                self.saveSession()
            }
        }
    }

    /// Puts tabs you haven't looked at in a while to sleep. Never the tab
    /// you're on, pinned tabs, or tabs playing sound or using the camera.
    func sleepIdleTabs(force: Bool = false) async {
        guard force || tabSleepMinutes > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(tabSleepMinutes) * 60)
        for tab in tabs where tab.id != selectedTabID && !tab.isAsleep && !tab.isPinned && tab.url != nil
            && splitPair?.contains(tab.id) != true {
            guard force || tab.lastActive < cutoff else { continue }
            if tab.isLoading || tab.isUsingCamera || tab.isUsingMicrophone || tab.permissionRequest != nil { continue }
            if await tab.webView.requestMediaPlaybackState() == .playing { continue }
            tab.sleep()
        }
    }

    /// Tabs ▸ Put Other Tabs to Sleep.
    func sleepOtherTabs() {
        Task { await sleepIdleTabs(force: true) }
    }

    var sleepingTabCount: Int { tabs.filter(\.isAsleep).count }

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

    /// Whether "Allow Sign-In" is on for the tab's website.
    /// Whether this tab's website runs in Lockdown Mode.
    func isLockedDown(_ tab: BrowserTab) -> Bool {
        guard let url = tab.url else { return false }
        return privacy.lockdownSites.contains(Self.siteName(url))
    }

    /// Turns Lockdown Mode on or off for the tab's website, then reloads it.
    func toggleLockdown(for tab: BrowserTab) {
        guard let url = tab.url else { return }
        let site = Self.siteName(url)
        updatePrivacy(reloading: tab) { settings in
            if settings.lockdownSites.contains(site) {
                settings.lockdownSites.remove(site)
            } else {
                settings.lockdownSites.insert(site)
            }
        }
    }

    func allowsSignIn(for tab: BrowserTab) -> Bool {
        guard let url = tab.url else { return false }
        return privacy.signInSites.contains(Self.siteName(url))
    }

    /// Lets the tab's website keep sign-in cookies from other companies
    /// (or stops it), then reloads. Ads and trackers stay blocked.
    func toggleSignIn(for tab: BrowserTab) {
        guard let url = tab.url else { return }
        let site = Self.siteName(url)
        updatePrivacy(reloading: tab) { settings in
            if settings.signInSites.contains(site) {
                settings.signInSites.remove(site)
            } else {
                settings.signInSites.insert(site)
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
        if !tab.isPrivate { activity.recordTrackerBlocked() }
        UserDefaults.standard.set(trackersBlockedTotal, forKey: "vela.trackersBlockedTotal")
    }

    private func recordBlockedPopup(_ url: URL?, isPopUnder: Bool, in tab: BrowserTab) {
        guard isPopUnder ? privacy.popUnderProtection : privacy.blockPopups else { return }
        if let url { tab.popupsBlocked.append(url) }
        popupsBlockedTotal += 1
        if !tab.isPrivate { activity.recordPopupBlocked() }
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

    /// You clicked into a login box: fill your saved login (asking for
    /// Touch ID if needed), or show the list when there's more than one.
    /// Only happens once per page, so clicking around doesn't keep asking.
    func autoFill(in tab: BrowserTab) {
        guard privacy.autoFillPasswords, !tab.didAutoFill, !tab.savedLogins.isEmpty,
              tab.id == selectedTab?.id else { return }
        tab.didAutoFill = true
        if tab.savedLogins.count == 1 {
            Task { await fill(tab.savedLogins[0], in: tab) }
        } else {
            tab.isLoginPickerShown = true
        }
    }

    /// Asks for Touch ID, then types the saved login into the page.
    func fill(_ entry: PasswordEntry, in tab: BrowserTab) async {
        guard await passwordVault.unlock(reason: "fill your password for \(entry.server)"),
              let password = passwordVault.password(for: entry) else { return }
        tab.isLoginPickerShown = false
        tab.fillLogin(username: entry.account, password: password, for: entry.server)
        // A 2FA code too? Copy it, and type it in when the code box appears
        // (on this page or the next one, within 3 minutes).
        if passwordVault.hasCode(entry), let generator = passwordVault.oneTimeCode(for: entry) {
            PasswordVault.copyToClipboard(generator.code())
            tab.pendingCode = PendingCode(entry: entry, generator: generator, until: Date().addingTimeInterval(180))
            try? await Task.sleep(for: .seconds(1))
            await fillPendingCode(in: tab)
        }
    }

    /// "login.example.com" counts as example.com, but "evilexample.com" doesn't.
    static func isSameSite(_ host: String, as site: String) -> Bool {
        host == site || host.hasSuffix("." + site)
    }

    /// Types a waiting 2FA code into the page, if it has a code box.
    func fillPendingCode(in tab: BrowserTab) async {
        guard let pending = tab.pendingCode else { return }
        guard Date() < pending.until, passwordVault.isRecentlyUnlocked,
              let host = tab.url?.host(), Self.isSameSite(PasswordVault.normalize(host), as: pending.entry.server) else {
            if Date() >= pending.until { tab.pendingCode = nil }
            return
        }
        if await tab.fillOneTimeCode(pending.generator.code()) { tab.pendingCode = nil }
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
            let bookmark = Bookmark(title: tab.title, url: url)
            bookmarks.append(bookmark)
            fileNewBookmark(bookmark)
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

    func saveBookmarks() {
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
        guard !tab.isPrivate, !tab.isAsleep, let url = tab.url, url.scheme?.hasPrefix("http") == true else { return }
        if let last = history.first, last.url == url {
            history[0].title = tab.title
            history[0].date = Date()
        } else {
            history.insert(HistoryEntry(title: tab.title, url: url, date: Date()), at: 0)
            activity.recordPage(url)
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
