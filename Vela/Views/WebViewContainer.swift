import SwiftUI
import WebKit

/// Shows a tab's `WKWebView` inside SwiftUI.
///
/// WebKit's web view is an AppKit view, not a SwiftUI view, so we wrap it.
/// The tab keeps the web view alive; this wrapper only puts it on screen.
struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
