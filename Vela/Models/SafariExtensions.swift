import AppKit
import WebKit

// Safari extensions in Vela.
//
// Safari extensions you install from the Mac App Store live inside their
// app, in its PlugIns folder. Since macOS 15.4, WebKit can run the modern
// kind ("Safari web extensions") in any browser built on it, so Vela finds
// them there and runs them in its tabs. Older "Safari app extensions" only
// run inside Safari itself, so Vela lists them as not compatible.
//
// **Ask first:** an extension can't read or change a site until you say so.
// When a page an extension wants opens, Vela asks once ("Allow Today",
// "Always Allow on This Site", "Don't Allow") and remembers your answer.
// Extensions never run in private tabs.

/// A Safari extension Vela found inside an app on this Mac.
struct FoundExtension: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let appName: String
    let bundleURL: URL
    /// False for older Safari app extensions, which only Safari can run.
    let isWebExtension: Bool
}

/// A question shown over the page: may this extension use this site?
struct ExtensionAccessRequest: Identifiable, Equatable {
    let id = UUID()
    let bundleID: String
    let name: String
    let host: String
    let tabID: UUID?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// Your choices, saved between launches.
private struct ExtensionPrefs: Codable {
    var enabled: [String] = []
    /// Sites each extension may always use (bundle ID → hosts).
    var allowedSites: [String: [String]] = [:]
    /// Sites each extension may never use.
    var blockedSites: [String: [String]] = [:]
}

@MainActor
@Observable
final class SafariExtensions: NSObject {
    let controller = WKWebExtensionController()
    private(set) var found: [FoundExtension] = []
    /// Running extensions, by bundle ID.
    private(set) var contexts: [String: WKWebExtensionContext] = [:]
    private(set) var problems: [String: String] = [:]
    private(set) var requests: [ExtensionAccessRequest] = []
    /// Bumped when an extension's button changes (icon, badge).
    private(set) var revision = 0

    @ObservationIgnored weak var store: BrowserStore?
    @ObservationIgnored private var prefs: ExtensionPrefs
    @ObservationIgnored private var adapters: [UUID: ExtensionTab] = [:]
    @ObservationIgnored private var window: ExtensionWindow!
    /// Where the button you clicked sits, so a popup can point at it.
    @ObservationIgnored var popupAnchor: CGRect = .zero
    /// Programmatic permission questions waiting for your answer.
    @ObservationIgnored private var replies: [UUID: (Bool) -> Void] = [:]

    private static let prefsKey = "vela.extensions"

    override init() {
        if let data = UserDefaults.standard.data(forKey: Self.prefsKey),
           let saved = try? JSONDecoder().decode(ExtensionPrefs.self, from: data) {
            prefs = saved
        } else {
            prefs = ExtensionPrefs()
        }
        super.init()
        window = ExtensionWindow(owner: self)
        controller.delegate = self
    }

    private func savePrefs() {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: Self.prefsKey)
        }
    }

    // MARK: Finding and loading

    /// Looks for extensions, then starts the ones you turned on.
    func start() {
        refresh()
        for item in found where prefs.enabled.contains(item.bundleID) && item.isWebExtension {
            Task { await load(item) }
        }
    }

    /// Looks through your Applications folders for Safari extensions.
    func refresh() {
        let fileManager = FileManager.default
        var folders = [URL(fileURLWithPath: "/Applications"),
                       fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        folders += folders.compactMap { folder in
            let utilities = folder.appendingPathComponent("Utilities")
            return fileManager.fileExists(atPath: utilities.path) ? utilities : nil
        }
        var results: [FoundExtension] = []
        for folder in folders {
            let apps = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for app in apps where app.pathExtension == "app" {
                let plugins = app.appendingPathComponent("Contents/PlugIns")
                let appexes = (try? fileManager.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)) ?? []
                for appex in appexes where appex.pathExtension == "appex" {
                    if let item = Self.describe(appex, in: app) { results.append(item) }
                }
            }
        }
        found = results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func describe(_ appex: URL, in app: URL) -> FoundExtension? {
        guard let info = NSDictionary(contentsOf: appex.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              let point = (info["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String,
              point == "com.apple.Safari.web-extension" || point == "com.apple.Safari.extension",
              let bundleID = info["CFBundleIdentifier"] as? String else { return nil }
        let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? appex.deletingPathExtension().lastPathComponent
        return FoundExtension(bundleID: bundleID, name: name, appName: app.deletingPathExtension().lastPathComponent,
                              bundleURL: appex, isWebExtension: point == "com.apple.Safari.web-extension")
    }

    func isEnabled(_ item: FoundExtension) -> Bool { prefs.enabled.contains(item.bundleID) }

    func setEnabled(_ item: FoundExtension, _ on: Bool) {
        if on {
            if !prefs.enabled.contains(item.bundleID) { prefs.enabled.append(item.bundleID) }
            savePrefs()
            Task { await load(item) }
        } else {
            prefs.enabled.removeAll { $0 == item.bundleID }
            savePrefs()
            unload(item.bundleID)
        }
    }

    private func load(_ item: FoundExtension) async {
        guard contexts[item.bundleID] == nil, let bundle = Bundle(url: item.bundleURL) else { return }
        do {
            let webExtension = try await WKWebExtension(appExtensionBundle: bundle)
            let context = WKWebExtensionContext(for: webExtension)
            context.uniqueIdentifier = item.bundleID
            // Features like storage and tabs are allowed, as Safari does.
            // Reading websites waits for your answer, site by site.
            for permission in webExtension.requestedPermissions {
                context.setPermissionStatus(.grantedExplicitly, for: permission)
            }
            for host in prefs.allowedSites[item.bundleID] ?? [] {
                if let pattern = Self.pattern(for: host) { context.setPermissionStatus(.grantedExplicitly, for: pattern) }
            }
            for host in prefs.blockedSites[item.bundleID] ?? [] {
                if let pattern = Self.pattern(for: host) { context.setPermissionStatus(.deniedExplicitly, for: pattern) }
            }
            try controller.load(context)
            contexts[item.bundleID] = context
            problems[item.bundleID] = nil
            announceOpenTabs()
            if let tab = store?.selectedTab { checkAccess(for: tab) }
        } catch {
            problems[item.bundleID] = error.localizedDescription
        }
    }

    private func unload(_ bundleID: String) {
        guard let context = contexts.removeValue(forKey: bundleID) else { return }
        try? controller.unload(context)
        requests.removeAll { $0.bundleID == bundleID }
    }

    private static func pattern(for host: String) -> WKWebExtension.MatchPattern? {
        try? WKWebExtension.MatchPattern(string: "*://\(host)/*")
    }

    func name(of bundleID: String) -> String {
        found.first { $0.bundleID == bundleID }?.name ?? bundleID
    }

    func allowedSites(for bundleID: String) -> [String] { prefs.allowedSites[bundleID] ?? [] }

    /// Settings: stop allowing an extension on a site.
    func forgetSite(_ host: String, for bundleID: String) {
        prefs.allowedSites[bundleID]?.removeAll { $0 == host }
        prefs.blockedSites[bundleID]?.removeAll { $0 == host }
        savePrefs()
        if let pattern = Self.pattern(for: host) {
            contexts[bundleID]?.setPermissionStatus(.unknown, for: pattern)
        }
    }

    // MARK: Asking first

    /// After a page loads: does a running extension want this site?
    func checkAccess(for tab: BrowserTab) {
        guard !tab.isPrivate, let url = tab.url, let host = url.host()?.lowercased(),
              ["http", "https"].contains(url.scheme ?? "") else { return }
        for (bundleID, context) in contexts {
            let wants = context.webExtension.allRequestedMatchPatterns.contains { $0.matches(url) }
            guard wants else { continue }
            switch context.permissionStatus(for: url) {
            case .grantedExplicitly, .grantedImplicitly, .deniedExplicitly: continue
            default: break
            }
            guard !requests.contains(where: { $0.bundleID == bundleID && $0.host == host }) else { continue }
            requests.append(ExtensionAccessRequest(bundleID: bundleID, name: name(of: bundleID), host: host, tabID: tab.id))
        }
    }

    enum Answer { case today, always, never }

    func answer(_ request: ExtensionAccessRequest, _ answer: Answer) {
        requests.removeAll { $0.id == request.id }
        guard let context = contexts[request.bundleID], let pattern = Self.pattern(for: request.host) else {
            replies.removeValue(forKey: request.id)?(false)
            return
        }
        switch answer {
        case .today:
            context.setPermissionStatus(.grantedExplicitly, for: pattern, expirationDate: Date().addingTimeInterval(86_400))
        case .always:
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
            prefs.allowedSites[request.bundleID, default: []].append(request.host)
            prefs.blockedSites[request.bundleID]?.removeAll { $0 == request.host }
        case .never:
            context.setPermissionStatus(.deniedExplicitly, for: pattern)
            prefs.blockedSites[request.bundleID, default: []].append(request.host)
        }
        savePrefs()
        if let reply = replies.removeValue(forKey: request.id) {
            reply(answer != .never)
        } else if answer != .never, let store,
                  let tab = store.tabs.first(where: { $0.id == request.tabID }) {
            // The extension's scripts join the page on a fresh load.
            tab.webView.reload()
        }
    }

    // MARK: Tabs

    func adapter(for tab: BrowserTab) -> ExtensionTab {
        if let made = adapters[tab.id] { return made }
        let made = ExtensionTab(tab: tab, owner: self)
        adapters[tab.id] = made
        return made
    }

    func tabOpened(_ tab: BrowserTab) {
        guard !tab.isPrivate, !contexts.isEmpty else { return }
        controller.didOpenTab(adapter(for: tab))
    }

    func tabClosed(_ tab: BrowserTab) {
        requests.removeAll { $0.tabID == tab.id }
        guard let made = adapters.removeValue(forKey: tab.id), !contexts.isEmpty else { return }
        controller.didCloseTab(made, windowIsClosing: false)
    }

    func tabActivated(_ tab: BrowserTab?, previous: BrowserTab?) {
        guard !contexts.isEmpty, let tab, !tab.isPrivate else { return }
        controller.didActivateTab(adapter(for: tab), previousActiveTab: previous.flatMap { $0.isPrivate ? nil : adapter(for: $0) })
        revision += 1
    }

    func tabChanged(_ tab: BrowserTab) {
        guard !contexts.isEmpty, !tab.isPrivate else { return }
        controller.didChangeTabProperties([.title, .loading], for: adapter(for: tab))
        checkAccess(for: tab)
        revision += 1
    }

    private func announceOpenTabs() {
        guard let store else { return }
        controller.didOpenWindow(window)
        for tab in store.tabs where !tab.isPrivate { controller.didOpenTab(adapter(for: tab)) }
        if let selected = store.selectedTab, !selected.isPrivate {
            controller.didActivateTab(adapter(for: selected), previousActiveTab: nil)
        }
        controller.didFocusWindow(window)
    }

    var normalTabs: [BrowserTab] { store?.tabs.filter { !$0.isPrivate } ?? [] }

    // MARK: Toolbar buttons

    /// Running extensions, in name order, for the toolbar.
    var running: [(bundleID: String, context: WKWebExtensionContext)] {
        contexts.map { ($0.key, $0.value) }.sorted { name(of: $0.bundleID) < name(of: $1.bundleID) }
    }

    func action(for context: WKWebExtensionContext) -> WKWebExtension.Action? {
        let tab = store?.selectedTab.flatMap { $0.isPrivate ? nil : adapter(for: $0) }
        return context.action(for: tab)
    }

    /// Clicking an extension's button: shows its popup, or runs its action.
    func click(_ bundleID: String, anchor: CGRect) {
        guard let context = contexts[bundleID] else { return }
        popupAnchor = anchor
        let tab = store?.selectedTab.flatMap { $0.isPrivate ? nil : adapter(for: $0) }
        context.performAction(for: tab)
    }
}

// MARK: - WebKit asks Vela about windows, tabs and permissions

extension SafariExtensions: WKWebExtensionControllerDelegate {
    func webExtensionController(_ controller: WKWebExtensionController,
                                openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        [window]
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        window
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void) {
        guard let store else { return completionHandler(nil, nil) }
        let tab = store.newTab(url: configuration.url, select: configuration.shouldBeActive)
        completionHandler(adapter(for: tab), nil)
    }

    /// An extension asks for more features while running (its "optional"
    /// permissions, like reading cookies or history). The ones it listed when
    /// you turned it on were already allowed; anything new asks you first.
    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        let alreadyListed = extensionContext.webExtension.requestedPermissions
        let new = permissions.subtracting(alreadyListed)
        guard !new.isEmpty else { return completionHandler(permissions, nil) }
        let name = self.name(of: extensionContext.uniqueIdentifier)
        let alert = NSAlert()
        alert.messageText = "Allow “\(name)” to use more features?"
        alert.informativeText = "It's asking for: " + new.map(\.rawValue).sorted().joined(separator: ", ")
            + ".\n\nOnly allow this if you trust the extension and expected it to ask."
        alert.addButton(withTitle: "Don't Allow")
        alert.addButton(withTitle: "Allow")
        let allowed = alert.runModal() == .alertSecondButtonReturn
        completionHandler(allowed ? permissions : permissions.subtracting(new), nil)
    }

    /// An extension asks for sites while running: ask you about this tab's site.
    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        guard let url = (tab as? ExtensionTab)?.tab?.url else { return completionHandler([], nil) }
        let matching = matchPatterns.filter { $0.matches(url) }
        ask(about: url, for: extensionContext, tab: (tab as? ExtensionTab)?.tab) { allowed in
            completionHandler(allowed ? matching : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        guard let first = urls.first, let host = first.host() else { return completionHandler([], nil) }
        ask(about: first, for: extensionContext, tab: (tab as? ExtensionTab)?.tab) { allowed in
            completionHandler(allowed ? urls.filter { $0.host() == host } : [], nil)
        }
    }

    private func ask(about url: URL, for context: WKWebExtensionContext, tab: BrowserTab?, reply: @escaping (Bool) -> Void) {
        guard let bundleID = context.uniqueIdentifier as String?, let host = url.host()?.lowercased() else { return reply(false) }
        let request = ExtensionAccessRequest(bundleID: bundleID, name: name(of: bundleID), host: host, tabID: tab?.id)
        replies[request.id] = reply
        requests.append(request)
    }

    /// Shows an extension's popup under its toolbar button.
    func webExtensionController(_ controller: WKWebExtensionController,
                                presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext,
                                completionHandler: @escaping ((any Error)?) -> Void) {
        guard let popover = action.popupPopover,
              let view = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else {
            return completionHandler(nil)
        }
        var rect = popupAnchor
        if !view.isFlipped { rect.origin.y = view.bounds.height - rect.maxY }
        popover.behavior = .transient
        popover.show(relativeTo: rect, of: view, preferredEdge: .minY)
        completionHandler(nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                didUpdate action: WKWebExtension.Action,
                                forExtensionContext context: WKWebExtensionContext) {
        revision += 1
    }
}

// MARK: - How a Vela tab looks to an extension

@MainActor
final class ExtensionTab: NSObject, WKWebExtensionTab {
    weak var tab: BrowserTab?
    weak var owner: SafariExtensions?

    init(tab: BrowserTab, owner: SafariExtensions) {
        self.tab = tab
        self.owner = owner
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        owner.flatMap { $0.windowObject }
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        guard let tab, let owner else { return NSNotFound }
        return owner.normalTabs.firstIndex { $0.id == tab.id } ?? NSNotFound
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { tab?.webView }
    func title(for context: WKWebExtensionContext) -> String? { tab?.title }
    func url(for context: WKWebExtensionContext) -> URL? { tab?.url }
    func isSelected(for context: WKWebExtensionContext) -> Bool { tab?.id == owner?.store?.selectedTabID }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !(tab?.isLoading ?? false) }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if let tab { owner?.store?.select(tab) }
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if let tab { owner?.store?.close(tab) }
        completionHandler(nil)
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        tab?.load(url)
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if fromOrigin { tab?.webView.reloadFromOrigin() } else { tab?.webView.reload() }
        completionHandler(nil)
    }

    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        tab?.webView.goBack()
        completionHandler(nil)
    }

    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        tab?.webView.goForward()
        completionHandler(nil)
    }
}

extension SafariExtensions {
    var windowObject: ExtensionWindow { window }
}

/// Vela's window, as extensions see it (one window holding every normal tab).
@MainActor
final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    weak var owner: SafariExtensions?

    init(owner: SafariExtensions) { self.owner = owner }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let owner else { return [] }
        return owner.normalTabs.map { owner.adapter(for: $0) }
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let owner, let tab = owner.store?.selectedTab, !tab.isPrivate else { return nil }
        return owner.adapter(for: tab)
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState { .normal }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        NSApp.mainWindow?.frame ?? .null
    }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }
}
