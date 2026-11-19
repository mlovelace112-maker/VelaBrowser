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

    var title = "New Tab"
    var url: URL?
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var progress: Double = 0
    /// Which tab group this tab belongs to, if any.
    var groupID: UUID?

    /// Called when a page asks to open a link in a new window/tab.
    @ObservationIgnored var onOpenInNewTab: (@MainActor (URL) -> Void)?

    private let coordinator: TabCoordinator
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        coordinator = TabCoordinator()

        coordinator.tab = self
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator

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
final class TabCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
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
}
