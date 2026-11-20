import Foundation
import WebKit

// MARK: - Dark mode for every site

/// Turns bright websites dark so they match Nightglass.
///
/// **How it works:** sites that already have a dark look use it (Vela tells
/// them you prefer dark). For the rest, after the page appears, a small script
/// checks whether its background is light. If it is, Vela flips the page's
/// colors and flips photos and videos back, so text and backgrounds go dark
/// but pictures look normal. Turn it off for one site with View ▸ Dark Mode
/// for This Site, or everywhere in Settings ▸ Appearance.
enum DarkMode {
    static let enabledKey = "vela.darkMode"
    static let offSitesKey = "vela.darkModeOffSites"

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var offSites: Set<String> { Set(UserDefaults.standard.stringArray(forKey: offSitesKey) ?? []) }

    static func script() -> WKUserScript {
        let off = (try? JSONEncoder().encode(offSites.sorted())).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let source = """
        (() => {
          if (window.__velaDark) return;
          const host = location.hostname;
          const offSites = \(off);
          const startOn = \(isEnabled ? "true" : "false") && !offSites.some((s) => host === s || host.endsWith('.' + s));
          const style = document.createElement('style');
          style.textContent =
            'html{filter:invert(0.9) hue-rotate(180deg)!important;background:#fff!important}' +
            'img,video,canvas,iframe,embed,object,svg image,[style*="background-image"]{filter:invert(1) hue-rotate(180deg)!important}' +
            '[style*="background-image"] img{filter:none!important}';
          const brightness = (color) => {
            const m = /rgba?\\(([^)]+)\\)/.exec(color || '');
            if (!m) return null;
            const p = m[1].split(',').map(parseFloat);
            if (p.length > 3 && p[3] < 0.1) return null;
            return (0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]) / 255;
          };
          const pageIsLight = () => {
            for (const el of [document.body, document.documentElement]) {
              if (!el) continue;
              const b = brightness(getComputedStyle(el).backgroundColor);
              if (b !== null) return b > 0.55;
            }
            return true; // No background at all means white.
          };
          let on = false;
          const set = (want) => {
            const should = want && (on || pageIsLight());
            if (should && !on) { (document.head || document.documentElement).appendChild(style); on = true; }
            else if (!should && on) { style.remove(); on = false; }
          };
          window.__velaDark = { set };
          if (!startOn) return;
          if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => set(true));
          else set(true);
          // Some pages paint their background late.
          setTimeout(() => { if (!on) set(true); }, 900);
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient)
    }
}

extension BrowserStore {
    func isDarkModeOn(for tab: BrowserTab) -> Bool {
        guard darkModeEverywhere, let url = tab.url else { return false }
        return !darkModeOffSites.contains(BrowserStore.siteName(url))
    }

    /// View ▸ Dark Mode for This Site.
    func toggleDarkMode(for tab: BrowserTab) {
        guard let url = tab.url else { return }
        let site = BrowserStore.siteName(url)
        if darkModeOffSites.contains(site) { darkModeOffSites.remove(site) } else { darkModeOffSites.insert(site) }
    }

    /// Called when either dark mode setting changes: updates open pages right
    /// away, and the script that new pages get.
    func applyDarkModeSettings() {
        UserDefaults.standard.set(darkModeEverywhere, forKey: DarkMode.enabledKey)
        UserDefaults.standard.set(Array(darkModeOffSites).sorted(), forKey: DarkMode.offSitesKey)
        for tab in tabs {
            tab.installScripts(for: privacy)
            guard tab.url != nil, !tab.isAsleep else { continue }
            tab.webView.callAsyncJavaScript(
                "if (window.__velaDark) window.__velaDark.set(on);",
                arguments: ["on": isDarkModeOn(for: tab)], in: nil, in: .defaultClient
            ) { _ in }
        }
    }
}

// MARK: - Focus mode

/// Hours when focus mode turns itself on.
struct FocusSchedule: Codable, Equatable {
    var isEnabled = false
    /// Minutes after midnight.
    var start = 9 * 60
    var end = 17 * 60
    var weekdaysOnly = true

    func isActive(at date: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        let calendar = Calendar.current
        if weekdaysOnly, calendar.isDateInWeekend(date) { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // A schedule like 10 PM to 6 AM wraps past midnight.
        return start <= end ? (now >= start && now < end) : (now >= start || now < end)
    }
}

/// Focus mode: blocks distracting sites (YouTube to start with) for a while,
/// or during set hours. A blocked page shows a calm "Stay focused" screen
/// with a way to take a 5-minute break.
extension BrowserStore {
    static let defaultFocusSites = ["youtube.com"]

    static func loadFocusSchedule() -> FocusSchedule {
        guard let data = UserDefaults.standard.data(forKey: "vela.focusSchedule"),
              let schedule = try? JSONDecoder().decode(FocusSchedule.self, from: data) else { return FocusSchedule() }
        return schedule
    }

    func saveFocusSettings() {
        UserDefaults.standard.set(focusSites, forKey: "vela.focusSites")
        if let data = try? JSONEncoder().encode(focusSchedule) {
            UserDefaults.standard.set(data, forKey: "vela.focusSchedule")
        }
    }

    var isFocusActive: Bool {
        if let focusUntil, focusUntil > Date() { return true }
        return focusSchedule.isActive()
    }

    /// The focus site a web address belongs to, if focus mode is blocking it now.
    func focusBlockedSite(for url: URL) -> String? {
        guard isFocusActive, let host = url.host()?.lowercased() else { return nil }
        let site = focusSites.first { host == $0 || host.hasSuffix("." + $0) }
        guard let site else { return nil }
        if let breakEnd = focusBreaks[site], breakEnd > Date() { return nil }
        return site
    }

    /// Starts a focus session. nil minutes: until you stop it.
    func startFocus(minutes: Int?) {
        focusUntil = minutes.map { Date().addingTimeInterval(Double($0) * 60) } ?? .distantFuture
        focusBreaks = [:]
        blockOpenFocusSites()
        showNotice(minutes.map { "Focus mode on for \($0 < 60 ? "\($0) minutes" : "\($0 / 60) hour\($0 >= 120 ? "s" : "")")" }
                   ?? "Focus mode on until you turn it off")
    }

    func stopFocus() {
        focusUntil = nil
        if !focusSchedule.isActive() {
            for tab in tabs where tab.focusBlocked != nil { leaveFocusScreen(in: tab, load: true) }
        }
        showNotice(focusSchedule.isActive() ? "Your focus hours are still on (Settings ▸ Focus)" : "Focus mode off")
    }

    /// Runs every minute: ends finished sessions and starts scheduled ones.
    func checkFocus() {
        if let focusUntil, focusUntil <= Date() {
            self.focusUntil = nil
            if !focusSchedule.isActive() { showNotice("Focus session finished. Nice work!") }
        }
        if isFocusActive { blockOpenFocusSites() }
    }

    /// Covers tabs already showing a blocked site, and pauses their videos.
    func blockOpenFocusSites() {
        for tab in tabs where tab.focusBlocked == nil {
            guard let url = tab.url, focusBlockedSite(for: url) != nil else { continue }
            tab.focusBlocked = url
            tab.webView.pauseAllMediaPlayback(completionHandler: nil)
        }
    }

    /// "Take a 5-minute break" on the focus screen.
    func takeFocusBreak(in tab: BrowserTab) {
        guard let url = tab.focusBlocked, let site = focusBlockedSite(for: url) else { return }
        focusBreaks[site] = Date().addingTimeInterval(5 * 60)
        leaveFocusScreen(in: tab, load: true)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5 * 60 + 1))
            self?.blockOpenFocusSites()
        }
    }

    /// "Go back" on the focus screen (or the screen going away).
    func leaveFocusScreen(in tab: BrowserTab, load: Bool) {
        guard let url = tab.focusBlocked else { return }
        tab.focusBlocked = nil
        if load {
            if tab.webView.url == url { tab.webView.reload() } else { tab.load(url) }
        } else if tab.webView.url == url || tab.webView.url == nil {
            if tab.webView.canGoBack { tab.webView.goBack() } else { tab.url = nil; tab.title = "New Tab" }
        }
    }

    var focusStatus: String? {
        guard isFocusActive else { return nil }
        if let focusUntil, focusUntil > Date(), focusUntil != .distantFuture {
            let minutes = Int(ceil(focusUntil.timeIntervalSinceNow / 60))
            return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
        }
        return focusUntil == .distantFuture ? "On" : "Scheduled"
    }
}

// MARK: - Web panels

/// A small always-there site in the right-hand panel, like Calendar or Gmail.
struct WebPanel: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var url: URL
    var icon: String

    static let defaults = [
        WebPanel(name: "Calendar", url: URL(string: "https://calendar.google.com/")!, icon: "calendar"),
        WebPanel(name: "Gmail", url: URL(string: "https://mail.google.com/")!, icon: "envelope"),
    ]
}

/// Keeps panel pages inside the panel, and opens links to other sites in tabs.
@MainActor
final class WebPanelCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    let home: String
    let openInTab: @MainActor (URL) -> Void

    init(home: URL, openInTab: @escaping @MainActor (URL) -> Void) {
        self.home = LinkChecker.registrableDomain(home.host() ?? "")
        self.openInTab = openInTab
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        if navigationAction.shouldPerformDownload { return (.cancel, preferences) }
        if navigationAction.navigationType == .linkActivated,
           navigationAction.targetFrame?.isMainFrame ?? true,
           let url = navigationAction.request.url,
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           LinkChecker.registrableDomain(url.host() ?? "") != home {
            openInTab(url)
            return (.cancel, preferences)
        }
        return (.allow, preferences)
    }

    /// target="_blank" links open in a normal tab.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { openInTab(url) }
        return nil
    }
}

extension BrowserStore {
    /// Phone-sized pages fit the narrow panel much better.
    private static var panelUserAgent: String { SafariIdentity.mobile }

    static func loadWebPanels() -> [WebPanel] {
        guard let data = UserDefaults.standard.data(forKey: "vela.webPanels"),
              let panels = try? JSONDecoder().decode([WebPanel].self, from: data) else { return WebPanel.defaults }
        return panels
    }

    private func saveWebPanels() {
        if let data = try? JSONEncoder().encode(webPanels) {
            UserDefaults.standard.set(data, forKey: "vela.webPanels")
        }
    }

    var selectedPanel: WebPanel? {
        webPanels.first { $0.id == selectedPanelID } ?? webPanels.first
    }

    /// The panel's page. Made once and kept, so it stays signed in and
    /// scrolled where you left it.
    func webView(for panel: WebPanel) -> WKWebView {
        if let existing = panelWebViews[panel.id] { return existing }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = self.configuration.websiteDataStore
        if let ruleList { configuration.userContentController.add(ruleList) }
        configuration.userContentController.addUserScript(DarkMode.script())
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.panelUserAgent
        let coordinator = WebPanelCoordinator(home: panel.url) { [weak self] url in
            self?.newTab(url: url)
        }
        panelCoordinators[panel.id] = coordinator
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.load(URLRequest(url: panel.url))
        panelWebViews[panel.id] = webView
        return webView
    }

    func toggleWebPanels() {
        isWebPanelVisible.toggle()
    }

    func addWebPanel(name: String, address: String) {
        guard let url = BrowserStore.url(from: address), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let panel = WebPanel(name: trimmed.isEmpty ? BrowserStore.siteName(url) : trimmed, url: url, icon: "globe")
        webPanels.append(panel)
        selectedPanelID = panel.id
        saveWebPanels()
    }

    func removeWebPanel(_ panel: WebPanel) {
        webPanels.removeAll { $0.id == panel.id }
        panelWebViews[panel.id] = nil
        panelCoordinators[panel.id] = nil
        if selectedPanelID == panel.id { selectedPanelID = webPanels.first?.id }
        saveWebPanels()
    }
}
