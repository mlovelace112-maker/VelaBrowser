import SwiftUI
import WebKit

/// Reader mode (⇧⌘R): the article on a calm page, with text size, font and
/// page color controls floating in the corner.
struct ReaderView: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab
    let article: ReaderArticle

    var body: some View {
        let settings = ReaderSettings.shared
        let accent = Appearance.shared.settings.customAccent ?? Appearance.shared.theme.accent

        ReaderWebView(
            html: Reader.page(for: article, settings: settings, accent: String(format: "#%06X", accent)),
            baseURL: article.url
        ) { url in
            tab.load(url)
        }
        .overlay(alignment: .topTrailing) {
            ReaderControls(close: { tab.reader = nil })
                .padding(14)
        }
    }
}

private struct ReaderControls: View {
    let close: () -> Void

    var body: some View {
        @Bindable var settings = ReaderSettings.shared

        HStack(spacing: 4) {
            Button { settings.fontSize = max(13, settings.fontSize - 2) } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .buttonStyle(IconButtonStyle(size: 28))
            .help("Smaller Text")
            Button { settings.fontSize = min(30, settings.fontSize + 2) } label: {
                Image(systemName: "textformat.size.larger")
            }
            .buttonStyle(IconButtonStyle(size: 28))
            .help("Larger Text")

            Menu {
                Picker("Font", selection: $settings.font) {
                    ForEach(ReaderFont.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "textformat")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 28, height: 28)
            .help("Font")

            ForEach(ReaderPage.allCases) { page in
                Button { settings.page = page } label: {
                    Circle()
                        .fill(color(for: page))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(settings.page == page ? Nightglass.accent : Color.white.opacity(0.25),
                                                       lineWidth: settings.page == page ? 2 : 1))
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(page.name) Page")
            }

            Divider().frame(height: 18)

            Button(action: close) { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle(size: 28))
                .keyboardShortcut(.cancelAction)
                .help("Leave Reader (⇧⌘R)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .glassPanel(cornerRadius: 14)
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }

    private func color(for page: ReaderPage) -> Color {
        switch page {
        case .night: Color(hex: 0x0E0F16)
        case .sepia: Color(hex: 0xF4ECD8)
        case .paper: Color(hex: 0xFBFBFA)
        }
    }
}

/// A small web view that shows the reader page with page scripts turned off.
/// Clicking a link leaves Reader and opens it in the tab.
private struct ReaderWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL
    let openLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.parent = self
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ReaderWebView?
        var lastHTML = ""

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url, let parent else { return .allow }
            // A jump to a heading in the same article stays in Reader.
            var bare = URLComponents(url: url, resolvingAgainstBaseURL: false)
            bare?.fragment = nil
            if bare?.url == parent.baseURL, url.fragment != nil { return .allow }
            if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                parent.openLink(url)
            }
            return .cancel
        }
    }
}
