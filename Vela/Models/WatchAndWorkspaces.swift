import Foundation
import UserNotifications
import WebKit

// MARK: - Watch a page

/// A page Vela checks every so often, telling you when it changes, or when
/// what you asked about happens ("tell me when the price drops below $50").
struct WatchedPage: Codable, Identifiable, Equatable {
    var id = UUID()
    var url: URL
    var title: String
    /// What to look for, in your words. Empty means "any change".
    var instruction: String
    var everyHours: Double
    var lastChecked: Date?
    /// The page's text last time, to compare with.
    var lastText: String = ""
    /// The most recent news, shown in the list.
    var lastNews: String?
    var lastNewsDate: Date?
    var isPaused = false

    var isDue: Bool {
        guard !isPaused else { return false }
        guard let lastChecked else { return true }
        return Date().timeIntervalSince(lastChecked) >= everyHours * 3_600
    }
}

/// A saved set of tabs you can open again later.
struct Workspace: Codable, Identifiable, Equatable {
    struct Page: Codable, Equatable {
        var url: URL
        var title: String
    }
    var id = UUID()
    var name: String
    var pages: [Page]
    var saved = Date()
}

/// Watched pages and workspaces, saved in Application Support.
@MainActor
@Observable
final class SavedLists {
    var watched: [WatchedPage] = [] { didSet { save() } }
    var workspaces: [Workspace] = [] { didSet { save() } }

    private struct File: Codable {
        var watched: [WatchedPage]
        var workspaces: [Workspace]
    }

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vela", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("watched-and-workspaces.json")
    }

    @ObservationIgnored private var isLoading = true

    init() {
        if let data = try? Data(contentsOf: Self.fileURL), let file = try? JSONDecoder().decode(File.self, from: data) {
            watched = file.watched
            workspaces = file.workspaces
        }
        isLoading = false
    }

    private func save() {
        guard !isLoading, let data = try? JSONEncoder().encode(File(watched: watched, workspaces: workspaces)) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}

extension BrowserStore {
    /// Claude ▸ Watch This Page…
    func watchCurrentPage(instruction: String, everyHours: Double) {
        guard let tab = selectedTab, let url = tab.url, !tab.isPrivate else { return }
        let page = WatchedPage(url: url, title: tab.title, instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
                               everyHours: everyHours)
        saved.watched.removeAll { $0.url == url }
        saved.watched.append(page)
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await check(page.id)
        }
        showNotice("Vela will check this page every \(Self.describe(hours: everyHours))")
    }

    static func describe(hours: Double) -> String {
        switch hours {
        case ..<1.5: "hour"
        case 24: "day"
        default: "\(Int(hours)) hours"
        }
    }

    /// Called every few minutes: checks the pages that are due.
    func checkWatchedPages() {
        for page in saved.watched where page.isDue {
            Task { await check(page.id) }
        }
    }

    func check(_ id: UUID) async {
        guard let page = saved.watched.first(where: { $0.id == id }) else { return }
        update(id) { $0.lastChecked = Date() }
        guard let text = await PageReader.text(of: page.url, dataStore: configuration.websiteDataStore) else { return }
        let previous = page.lastText
        update(id) { $0.lastText = String(text.prefix(12_000)) }
        guard !previous.isEmpty else { return } // first look: nothing to compare yet

        if page.instruction.isEmpty {
            guard Self.meaningfullyDifferent(previous, text) else { return }
            report(id, "The page changed since \(page.lastChecked?.formatted(date: .abbreviated, time: .shortened) ?? "last time").")
            return
        }
        guard claude.hasKey, !text.hasPrefix("[password]") else { return }
        struct Verdict: Decodable {
            var notify: Bool
            var message: String
        }
        let system = """
        You watch a web page for someone and decide whether to tell them something. Their request: \
        "\(page.instruction)". Compare the page before and now. Notify only when the request is met now \
        and wasn't before, or the thing they care about clearly changed. Return: {"notify": true or false, \
        "message": "one short sentence for a notification, with the key number or fact"}.
        """
        let prompt = "Page: \(page.title) (\(page.url.absoluteString))\n\nBEFORE:\n\(previous.prefix(6_000))\n\nNOW:\n\(text.prefix(6_000))"
        if let verdict = try? await Self.askClaudeForJSON(Verdict.self, system: system, prompt: prompt), verdict.notify {
            report(id, verdict.message)
        }
    }

    private func update(_ id: UUID, _ change: (inout WatchedPage) -> Void) {
        guard let index = saved.watched.firstIndex(where: { $0.id == id }) else { return }
        change(&saved.watched[index])
    }

    private func report(_ id: UUID, _ message: String) {
        guard let page = saved.watched.first(where: { $0.id == id }) else { return }
        update(id) {
            $0.lastNews = message
            $0.lastNewsDate = Date()
        }
        let content = UNMutableNotificationContent()
        content.title = page.title.isEmpty ? (page.url.host() ?? "Watched page") : page.title
        content.body = message
        content.sound = .default
        content.userInfo = ["url": page.url.absoluteString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: page.id.uuidString + "-\(Date().timeIntervalSince1970)",
                                                                     content: content, trigger: nil))
    }

    /// Ignores tiny changes (a clock, a view counter) by comparing words.
    static func meaningfullyDifferent(_ a: String, _ b: String) -> Bool {
        let wordsA = Set(a.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }))
        let wordsB = Set(b.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }))
        let changed = wordsA.symmetricDifference(wordsB).count
        return changed >= max(5, (wordsA.count + wordsB.count) / 100)
    }

    // MARK: Workspaces

    /// Tabs ▸ Save Tabs as Workspace…
    func saveWorkspace(named name: String) {
        let pages = tabs.filter { !$0.isPrivate }.compactMap { tab in
            tab.url.map { Workspace.Page(url: $0, title: tab.title) }
        }
        guard !pages.isEmpty else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.workspaces.removeAll { $0.name == trimmed }
        saved.workspaces.append(Workspace(name: trimmed.isEmpty ? "Workspace" : trimmed, pages: pages))
        showNotice("Saved \(pages.count) tabs as \(trimmed)")
    }

    /// Opens a workspace's tabs. With `replacing`, your other tabs close first
    /// (pinned tabs stay, and ⇧⌘T brings closed tabs back).
    func openWorkspace(_ workspace: Workspace, replacing: Bool) {
        if replacing {
            for tab in tabs where !tab.isPinned { close(tab) }
        }
        var first: BrowserTab?
        for page in workspace.pages {
            let tab = newTab(url: page.url, select: false)
            if first == nil { first = tab }
        }
        if let first { select(first) }
    }

    func deleteWorkspace(_ workspace: Workspace) {
        saved.workspaces.removeAll { $0.id == workspace.id }
    }
}

/// Loads a page out of sight and reads its text (for watched pages).
@MainActor
final class PageReader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?

    /// The page's text, "[password]…" if it has a password box, or nil if it didn't load.
    static func text(of url: URL, dataStore: WKWebsiteDataStore) async -> String? {
        let reader = PageReader()
        return await reader.read(url, dataStore: dataStore)
    }

    private func read(_ url: URL, dataStore: WKWebsiteDataStore) async -> String? {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.applicationNameForUserAgent = SafariIdentity.applicationName
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        let loaded: String? = await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.load(URLRequest(url: url, timeoutInterval: 30))
            Task {
                try? await Task.sleep(for: .seconds(40))
                self.finish(nil)
            }
        }
        self.webView = nil
        return loaded
    }

    private func finish(_ text: String?) {
        continuation?.resume(returning: text)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task {
            // Let pages that fill in with scripts settle.
            try? await Task.sleep(for: .seconds(3))
            let script = """
            const hasPassword = !!document.querySelector('input[type=password]');
            const text = (document.body ? document.body.innerText : '').replace(/\\s+/g, ' ').slice(0, 20000);
            return (hasPassword ? '[password]' : '') + text;
            """
            let text = try? await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient) as? String
            finish(text)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finish(nil) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { finish(nil) }
}
