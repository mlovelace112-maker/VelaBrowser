import Foundation
import Observation
import WebKit

/// One browser tab.
///
/// Each tab owns its own `WKWebView` (Apple's WebKit engine, the same one
/// Safari uses), so switching tabs keeps each page exactly where you left it.
///
/// `@Observable` means SwiftUI watches these properties: when `title` or
/// `isLoading` changes, any view that reads them redraws automatically.
@MainActor
@Observable
final class BrowserTab: Identifiable {
    let id = UUID()
    let webView: WKWebView
    /// Private tabs keep no history, cookies or cache after they close.
    let isPrivate: Bool

    var title = "New Tab"
    var url: URL?
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var progress: Double = 0
    /// Which tab group this tab belongs to, if any.
    var groupID: UUID?
    /// Pinned tabs stay small at the left of the tab strip.
    var isPinned = false
    /// Tracker companies the shield caught on the current page.
    var trackersFound: [String] = []
    /// Pop-ups the shield stopped on the current page.
    var popupsBlocked: [URL] = []
    /// The link under the mouse pointer, shown with its safety check at the bottom of the page.
    var hoveredLink: URL?
    /// Set when the link checker stopped a dangerous page from opening.
    var linkWarning: LinkWarning?
    /// Saved logins for this page's website (they make the key button appear).
    var savedLogins: [PasswordEntry] = []

    /// Page zoom: 1.0 is 100%. Change it with zoomIn(), zoomOut() or resetZoom().
    private(set) var zoom: Double = 1

    /// Called when a page asks to open a link in a new window/tab.
    @ObservationIgnored var onOpenInNewTab: (@MainActor (URL) -> Void)?
    /// Called when a page opens a new window (a link with target="_blank" or
    /// a sign-in pop-up). Must return a web view made with this exact configuration.
    @ObservationIgnored var onOpenWindow: (@MainActor (WKWebViewConfiguration, URL?) -> WKWebView?)?
    /// Called when the page closes its own window (window.close()).
    @ObservationIgnored var onCloseRequested: (@MainActor () -> Void)?
    /// Called when a page finishes loading (used to record History).
    @ObservationIgnored var onFinishLoading: (@MainActor () -> Void)?
    /// Called when the shield's page script spots a tracker.
    @ObservationIgnored var onTrackerFound: (@MainActor (String) -> Void)?
    /// Called when the shield stops a pop-up. The flag is true for a pop-under.
    @ObservationIgnored var onPopupBlocked: (@MainActor (URL?, Bool) -> Void)?
    /// Called when a link or page turns into a file download.
    @ObservationIgnored var onDownload: (@MainActor (WKDownload) -> Void)?
    /// Called when the page shows a password box. Passes the website's host.
    @ObservationIgnored var onLoginFormFound: (@MainActor (String) -> Void)?
    /// Called when you submit a login: host, username, password.
    @ObservationIgnored var onLoginSubmitted: (@MainActor (String, String, String) -> Void)?
    /// Asks Google Safe Browsing about an address (set by BrowserStore).
    @ObservationIgnored var checkThreat: (@MainActor (URL) async -> SafeBrowsingThreat?)?
    /// Reads your current privacy settings (set by BrowserStore).
    @ObservationIgnored var settings: @MainActor () -> PrivacySettings = { PrivacySettings() }

    /// The frame (page or embedded frame) that holds the login form.
    @ObservationIgnored fileprivate var loginFrame: WKFrameInfo?
    /// Dangerous links you chose to open anyway.
    @ObservationIgnored fileprivate var allowedDangerousURLs: Set<URL> = []

    private let coordinator: TabCoordinator
    private let contentController: WKUserContentController
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration, isPrivate: Bool = false, ruleList: WKContentRuleList?, privacy: PrivacySettings) {
        // Each tab gets its own "user content controller": the place where
        // blocking rules and our small page scripts are attached.
        let tabConfiguration = configuration.copy() as! WKWebViewConfiguration
        let contentController = WKUserContentController()
        if let ruleList { contentController.add(ruleList) }
        tabConfiguration.userContentController = contentController
        self.contentController = contentController

        webView = WKWebView(frame: .zero, configuration: tabConfiguration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        self.isPrivate = isPrivate
        coordinator = TabCoordinator()

        coordinator.tab = self
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        // Two mailboxes for messages from page scripts: one in the page's own
        // script world, one in Vela's private world that pages can't reach.
        contentController.add(WeakScriptMessageHandler(coordinator), name: ContentBlocker.messageName)
        contentController.add(WeakScriptMessageHandler(coordinator), contentWorld: .defaultClient, name: ContentBlocker.clientMessageName)
        installScripts(for: privacy)

        // Key-Value Observing (KVO): WebKit tells us whenever these change.
        observations = [
            watch(\.title),
            watch(\.url),
            watch(\.isLoading),
            watch(\.canGoBack),
            watch(\.canGoForward),
            watch(\.estimatedProgress),
        ]
    }

    /// A tab for a window that a page opened, such as "Sign in with Google".
    ///
    /// **Why it's special:** WebKit links this window to the page that opened
    /// it (`window.opener`), so the sign-in pop-up can hand your login back to
    /// the site and close itself. That link only works if the new web view uses
    /// the *exact* configuration WebKit gives us, so this tab shares the opener's
    /// blocking rules, scripts and message mailboxes instead of making its own.
    init(popupConfiguration: WKWebViewConfiguration, isPrivate: Bool, url: URL?) {
        contentController = popupConfiguration.userContentController
        webView = WKWebView(frame: .zero, configuration: popupConfiguration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        self.isPrivate = isPrivate
        coordinator = TabCoordinator()
        self.url = url

        coordinator.tab = self
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator

        observations = [
            watch(\.title),
            watch(\.url),
            watch(\.isLoading),
            watch(\.canGoBack),
            watch(\.canGoForward),
            watch(\.estimatedProgress),
        ]
    }

    func load(_ url: URL) {
        self.url = url
        webView.load(URLRequest(url: url))
    }

    /// Swaps in a newly compiled set of blocking rules (or none).
    func apply(ruleList: WKContentRuleList?) {
        contentController.removeAllContentRuleLists()
        if let ruleList { contentController.add(ruleList) }
    }

    /// (Re)adds Vela's page scripts. New scripts take effect on the next page load.
    func installScripts(for privacy: PrivacySettings) {
        contentController.removeAllUserScripts()
        contentController.addUserScript(ContentBlocker.popupGuardScript(
            popUnderProtection: privacy.blockingLevel != .off && privacy.popUnderProtection,
            shieldsDownSites: privacy.shieldsDownSites
        ))
        contentController.addUserScript(ContentBlocker.trackerScanScript())
        if let cleaner = ContentBlocker.adCleanerScript(for: privacy) {
            contentController.addUserScript(cleaner)
        }
        contentController.addUserScript(LinkChecker.hoverScript())
        contentController.addUserScript(PasswordScripts.loginScript())
    }

    /// "Open Anyway" on the dangerous-link warning.
    func openDangerousLinkAnyway() {
        guard let warning = linkWarning else { return }
        allowedDangerousURLs.insert(warning.url)
        linkWarning = nil
        load(warning.url)
    }

    /// "Go Back" on the dangerous-link warning.
    func dismissLinkWarning() {
        linkWarning = nil
        url = webView.url // A brand-new tab goes back to the New Tab page.
    }

    /// Types a saved login into the page's login form.
    func fillLogin(username: String, password: String, for server: String) {
        // Only ever fill into the website the login was saved for.
        if let loginFrame {
            guard PasswordVault.normalize(loginFrame.securityOrigin.host) == server else { return }
        } else {
            guard let url, PasswordVault.normalize(url.host() ?? "") == server else { return }
        }
        webView.callAsyncJavaScript(
            PasswordScripts.fillFunction,
            arguments: ["username": username, "password": password],
            in: loginFrame,
            in: .defaultClient,
            completionHandler: nil
        )
    }

    func setPopupsAllowed(_ allowed: Bool) {
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = allowed
    }

    /// A new page started: forget the previous page's shield stats.
    fileprivate func resetPageStats() {
        trackersFound = []
        popupsBlocked = []
        hoveredLink = nil
        savedLogins = []
        loginFrame = nil
    }

    func zoomIn() { setZoom(zoom + 0.1) }
    func zoomOut() { setZoom(zoom - 0.1) }
    func resetZoom() { setZoom(1) }

    private func setZoom(_ value: Double) {
        // Round to whole percents so 0.1 steps don't drift (e.g. 1.2000000002).
        zoom = (min(max(value, 0.5), 3) * 100).rounded() / 100
        webView.pageZoom = zoom
    }

    private func watch<Value>(_ keyPath: KeyPath<WKWebView, Value>) -> NSKeyValueObservation {
        webView.observe(keyPath, options: [.new]) { [weak self] _, _ in
            // WebKit reports changes on the main thread, which is where UI state lives.
            MainActor.assumeIsolated { self?.syncFromWebView() }
        }
    }

    /// Copies the web view's current state into our observable properties.
    private func syncFromWebView() {
        if let current = webView.url { url = current }
        let pageTitle = webView.title ?? ""
        if !pageTitle.isEmpty {
            title = pageTitle
        } else if let url {
            title = BrowserStore.siteName(url)
        }
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        progress = webView.estimatedProgress
    }
}

/// Receives callbacks from WebKit for one tab: new windows, navigation
/// decisions, downloads and messages from Vela's page scripts.
@MainActor
final class TabCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var tab: BrowserTab?

    // MARK: New windows and pop-ups

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let tab else { return nil }
        let url = navigationAction.request.url
        let settings = tab.settings()

        // Pop-under protection: never open a new tab straight to an ad network.
        if settings.blockingLevel != .off, settings.popUnderProtection, shieldsUp(for: tab, settings),
           let url, let host = url.host(), ContentBlocker.isTracker(host) {
            tab.onPopupBlocked?(url, true)
            return nil
        }
        // Open the new window as a tab that stays linked to this page.
        return tab.onOpenWindow?(configuration, url)
    }

    /// The page called window.close(), e.g. a sign-in pop-up that's finished.
    func webViewDidClose(_ webView: WKWebView) {
        tab?.onCloseRequested?()
    }

    // MARK: Navigation decisions

    /// Asked before every page (and frame) loads. This is where JavaScript gets
    /// switched off for "Block all JavaScript", the link checker stops dangerous
    /// pages, and "download this" links become downloads.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        guard let tab else { return (.allow, preferences) }
        let settings = tab.settings()

        if navigationAction.shouldPerformDownload {
            return (.download, preferences)
        }

        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let pageURL = isMainFrame ? navigationAction.request.url : webView.url
        let site = pageURL.map(BrowserStore.siteName)
        preferences.allowsContentJavaScript = settings.scriptLevel(for: site) != .blockAll

        if isMainFrame, let url = navigationAction.request.url {
            let isRevisit = navigationAction.navigationType == .backForward || navigationAction.navigationType == .reload
            if settings.linkCheckerEnabled, settings.warnBeforeDangerousLinks, !isRevisit,
               !tab.allowedDangerousURLs.contains(url) {
                let report = LinkChecker.check(url)
                if report.verdict == .dangerous {
                    tab.linkWarning = LinkWarning(url: url, report: report)
                    return (.cancel, preferences)
                }
            }
            // Google Safe Browsing: known malware and phishing sites.
            if settings.safeBrowsingEnabled, !isRevisit, !tab.allowedDangerousURLs.contains(url),
               let threat = await tab.checkThreat?(url) {
                var report = LinkReport()
                report.flag(.dangerous, threat.reason)
                tab.linkWarning = LinkWarning(url: url, report: report)
                return (.cancel, preferences)
            }
            tab.linkWarning = nil
        }
        return (.allow, preferences)
    }

    /// Asked when the server answers. Files a page can't display become downloads.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        let isAttachment = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?
            .lowercased().hasPrefix("attachment") ?? false

        if navigationResponse.isForMainFrame {
            return (isAttachment || !navigationResponse.canShowMIMEType) ? .download : .allow
        }
        // Hidden frames can't start downloads (a common "drive-by download" trick).
        return navigationResponse.canShowMIMEType && !isAttachment ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        tab?.onDownload?(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        tab?.onDownload?(download)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        tab?.resetPageStats()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tab?.onFinishLoading?()
    }

    // MARK: Messages from page scripts

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let tab, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }

        if message.name == ContentBlocker.clientMessageName {
            handleClientMessage(type, body: body, frame: message.frameInfo, tab: tab)
            return
        }
        switch type {
        case "tracker":
            if let domain = body["domain"] as? String { tab.onTrackerFound?(domain) }
        case "popup":
            let address = body["url"] as? String ?? ""
            let isPopUnder = body["popunder"] as? Bool ?? false
            tab.onPopupBlocked?(URL(string: address), isPopUnder)
        default:
            break
        }
    }

    /// Messages from Vela's private script world (link hover and passwords).
    private func handleClientMessage(_ type: String, body: [String: Any], frame: WKFrameInfo, tab: BrowserTab) {
        // The website a message really came from, according to WebKit, not the page.
        let origin = frame.securityOrigin
        let isSecure = origin.protocol == "https" || origin.host == "localhost"

        switch type {
        case "hover":
            guard frame.isMainFrame, tab.settings().linkCheckerEnabled else { return }
            let address = body["url"] as? String ?? ""
            tab.hoveredLink = address.isEmpty ? nil : URL(string: address)
        case "loginForm":
            guard isSecure else { return }
            tab.loginFrame = frame
            tab.onLoginFormFound?(origin.host)
        case "credentials":
            guard isSecure,
                  let username = body["username"] as? String,
                  let password = body["password"] as? String else { return }
            tab.onLoginSubmitted?(origin.host, username, password)
        default:
            break
        }
    }

    private func shieldsUp(for tab: BrowserTab, _ settings: PrivacySettings) -> Bool {
        guard let url = tab.url else { return true }
        return !settings.shieldsDownSites.contains(BrowserStore.siteName(url))
    }
}

/// WebKit keeps a strong hold on message handlers, which would keep a closed
/// tab alive forever. This small go-between holds the real handler weakly.
@MainActor
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
