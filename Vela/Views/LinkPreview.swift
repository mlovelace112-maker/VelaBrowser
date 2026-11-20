import AppKit
import SwiftUI
import WebKit

/// Link preview: hold ⌥ (Option) over a link to peek at the page in a small
/// window without leaving the one you're on. Ask Claude for a summary, open
/// it, or press Esc to close it.
///
/// The preview uses the same cookies and privacy shield as the tab you're in
/// (and stays private in a private tab). Links the link checker flags as
/// dangerous are never previewed.
@MainActor
@Observable
final class LinkPreview: Identifiable {
    let id = UUID()
    let url: URL
    let webView: WKWebView
    /// The tab the link was in, so "Open" knows its container.
    let tabID: UUID
    var summary = ""
    var isSummarizing = false
    var error: String?
    @ObservationIgnored var summaryTask: Task<Void, Never>?

    init(url: URL, from tab: BrowserTab, ruleList: WKContentRuleList?) {
        self.url = url
        tabID = tab.id
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = tab.webView.configuration.websiteDataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        if let ruleList { configuration.userContentController.add(ruleList) }
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = tab.webView.customUserAgent
        webView.allowsMagnification = true
        webView.load(URLRequest(url: url))
    }

    func stop() {
        summaryTask?.cancel()
        webView.stopLoading()
    }
}

extension BrowserStore {
    /// Shows a preview of the link under the pointer in the current tab.
    func previewHoveredLink() {
        guard linkPreview == nil, !isCommandBarVisible,
              let tab = selectedTab, let url = tab.hoveredLink,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              LinkChecker.check(url).verdict != .dangerous else { return }
        linkPreview = LinkPreview(url: url, from: tab, ruleList: ruleList)
    }

    func closeLinkPreview() {
        linkPreview?.stop()
        linkPreview = nil
    }

    /// "Open": in a new tab next to the current one (same container).
    func openLinkPreview(inNewTab: Bool) {
        guard let preview = linkPreview else { return }
        let address = preview.webView.url ?? preview.url
        closeLinkPreview()
        if inNewTab, let tab = tabs.first(where: { $0.id == preview.tabID }) {
            newTab(url: address, opener: tab)
        } else {
            open(address)
        }
    }

    /// Asks Claude (Haiku, for speed) for a short summary of the previewed page.
    func summarizeLinkPreview() {
        guard let preview = linkPreview, !preview.isSummarizing else { return }
        preview.summary = ""
        preview.error = nil
        preview.isSummarizing = true
        preview.summaryTask = Task { [weak preview] in
            guard let preview else { return }
            defer { preview.isSummarizing = false }
            // Give the page up to 10 seconds to finish loading.
            for _ in 0..<40 where preview.webView.isLoading {
                try? await Task.sleep(for: .milliseconds(250))
            }
            let script = """
            return {
              hasPassword: !!document.querySelector('input[type=password]'),
              title: document.title || '',
              text: (document.body ? document.body.innerText : '').slice(0, 24000)
            };
            """
            guard let page = try? await preview.webView.callAsyncJavaScript(script, contentWorld: .defaultClient) as? [String: Any],
                  let text = page["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                preview.error = "Vela couldn't read this page."
                return
            }
            // Same rule as the Claude panel: pages with password boxes stay on your Mac.
            if page["hasPassword"] as? Bool == true {
                preview.error = "This page has a password box, so Vela won't send it to Claude."
                return
            }
            let title = page["title"] as? String ?? ""
            let request = ClaudeRequest(
                model: .haiku,
                system: """
                You summarize web pages for someone deciding whether to open a link. Reply with 3 to 5 \
                short bullet points ("• " at the start of each line) covering what the page is and its main \
                points. Plain text, no headings. If it looks like an ad, a scam or a sign-in wall, say so first.
                """,
                messages: [["role": "user", "content": "Title: \(title)\nAddress: \(preview.url.absoluteString)\n\n\(text)"]],
                maxTokens: 1_000,
                effort: "low"
            )
            do {
                _ = try await ClaudeClient.stream(request) { piece in
                    preview.summary += piece
                }
            } catch {
                if !Task.isCancelled { preview.error = error.localizedDescription }
            }
        }
    }
}

/// The floating preview card, centered over the page.
struct LinkPreviewCard: View {
    @Environment(BrowserStore.self) private var store
    let preview: LinkPreview

    var body: some View {
        ZStack {
            // Click outside the card to close it.
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture { store.closeLinkPreview() }

            VStack(spacing: 0) {
                header
                Rectangle().fill(Nightglass.stroke).frame(height: 1)
                WebViewContainer(webView: preview.webView)
                    .frame(minHeight: 240)
                if preview.isSummarizing || !preview.summary.isEmpty || preview.error != nil {
                    Rectangle().fill(Nightglass.stroke).frame(height: 1)
                    summaryView
                }
            }
            .frame(maxWidth: 720, maxHeight: 620)
            .glassPanel(cornerRadius: 14)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
            .padding(36)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            FaviconView(url: preview.url, size: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(preview.url.host() ?? preview.url.absoluteString)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Nightglass.text)
                    .lineLimit(1)
                Text(preview.url.absoluteString)
                    .font(.system(size: 11))
                    .foregroundStyle(Nightglass.mutedText)
                    .lineLimit(1)
            }
            Spacer()
            Button { store.summarizeLinkPreview() } label: {
                Label("Summarize", systemImage: "sparkle")
            }
            .foregroundStyle(Nightglass.claude)
            .disabled(preview.isSummarizing)
            .help("Ask Claude what this page is about")
            Button { store.openLinkPreview(inNewTab: true) } label: {
                Label("Open in New Tab", systemImage: "plus.square.on.square")
            }
            .help("Open in a new tab")
            Button { store.closeLinkPreview() } label: { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle(size: 24))
                .help("Close (Esc)")
        }
        .font(.system(size: 12, weight: .medium))
        .buttonStyle(.plain)
        .foregroundStyle(Nightglass.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: 46)
    }

    private var summaryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let error = preview.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Nightglass.caution)
                } else if preview.summary.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Claude is reading the page…").foregroundStyle(Nightglass.mutedText)
                    }
                } else {
                    Text(preview.summary)
                        .foregroundStyle(Nightglass.text)
                        .textSelection(.enabled)
                }
            }
            .font(.system(size: 12.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .frame(maxHeight: 170)
    }
}

/// Watches the keyboard for the command bar and link previews:
/// holding ⌥ over a link opens a preview, and Esc closes either one.
/// (WebKit takes key presses while you're on a page, so SwiftUI alone
/// wouldn't see them.)
struct KeyboardWatcher: View {
    @Environment(BrowserStore.self) private var store
    @State private var monitor: Any?
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .background { ExtraSheets() }
            .onAppear(perform: start)
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown {
                holdTask?.cancel()
                // 53 is Esc.
                guard event.keyCode == 53 else { return event }
                if store.linkPreview != nil {
                    store.closeLinkPreview()
                    return nil
                }
                if store.isCommandBarVisible {
                    store.isCommandBarVisible = false
                    return nil
                }
                return event
            }
            // ⌥ pressed on its own: wait a moment, so ⌥-click and ⌥-shortcuts
            // don't pop up previews, then preview the link under the pointer.
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            holdTask?.cancel()
            if flags == .option, store.selectedTab?.hoveredLink != nil {
                holdTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled,
                          NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option,
                          NSEvent.pressedMouseButtons == 0 else { return }
                    store.previewHoveredLink()
                }
            }
            return event
        }
    }
}
