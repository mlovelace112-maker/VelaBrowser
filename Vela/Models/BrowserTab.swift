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

    /// Page zoom: 1.0 is 100%. Change it with zoomIn(), zoomOut() or resetZoom().
    private(set) var zoom: Double = 1

    /// Called when a page asks to open a link in a new window/tab.
    @ObservationIgnored var onOpenInNewTab: (@MainActor (URL) -> Void)?
    /// Called when a page finishes loading (used to record History).
    @ObservationIgnored var onFinishLoading: (@MainActor () -> Void)?
    /// Called when the shield's page script spots a tracker.
    @ObservationIgnored var onTrackerFound: (@MainActor (String) -> Void)?
    /// Called when a page tries to open a pop-up without you clicking anything.
    @ObservationIgnored var onPopupBlocked: (@MainActor (URL?) -> Void)?

    private let coordinator: TabCoordinator
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration, isPrivate: Bool = false, ruleList: WKContentRuleList?) {
        // Each tab gets its own "user content controller": the place where
        // blocking rules and our small shield scripts are attached.
        let tabConfiguration = configuration.copy() as! WKWebViewConfiguration
        let contentController = WKUserContentController()
        contentController.addUserScript(ContentBlocker.popupGuardScript())
        contentController.addUserScript(ContentBlocker.trackerScanScript())
        if let ruleList { contentController.add(ruleList) }
        tabConfiguration.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: tabConfiguration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        self.isPrivate = isPrivate
        coordinator = TabCoordinator()

        coordinator.tab = self
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        contentController.add(WeakScriptMessageHandler(coordinator), name: ContentBlocker.messageName)

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

    func load(_ url: URL) {
        self.url = url
        webView.load(URLRequest(url: url))
    }

    /// Swaps in a newly compiled set of blocking rules (or none).
    func apply(ruleList: WKContentRuleList?) {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        if let ruleList { controller.add(ruleList) }
    }

    func setPopupsAllowed(_ allowed: Bool) {
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = allowed
    }

    /// A new page started: forget the previous page's shield stats.
    fileprivate func resetPageStats() {
        trackersFound = []
        popupsBlocked = []
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

/// Receives callbacks from WebKit for one tab.
///
/// This is where the pop-up blocker will live in step 3: every request to
/// open a new window comes through `createWebViewWith`.
@MainActor
final class TabCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var tab: BrowserTab?

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Open target="_blank" links as a new tab instead of a new window.
        if let url = navigationAction.request.url {
            tab?.onOpenInNewTab?(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        tab?.resetPageStats()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tab?.onFinishLoading?()
    }

    /// Messages from the shield scripts running inside the page.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "tracker":
            if let domain = body["domain"] as? String { tab?.onTrackerFound?(domain) }
        case "popup":
            let address = body["url"] as? String ?? ""
            tab?.onPopupBlocked?(URL(string: address))
        default:
            break
        }
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
