import SwiftUI

/// Back, forward, reload, the address bar and the bookmark star.
struct ToolbarView: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            if let tab = store.selectedTab {
                Button { tab.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(IconButtonStyle())
                    .disabled(!tab.canGoBack)
                    .help("Back (⌘[)")

                Button { tab.webView.goForward() } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(IconButtonStyle())
                    .disabled(!tab.canGoForward)
                    .help("Forward (⌘])")

                Button {
                    if tab.isLoading {
                        tab.webView.stopLoading()
                    } else {
                        tab.webView.reload()
                    }
                } label: {
                    Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                }
                .buttonStyle(IconButtonStyle())
                .disabled(tab.url == nil)
                .help(tab.isLoading ? "Stop" : "Reload (⌘R)")

                AddressBar(tab: tab)
                    .padding(.horizontal, 6)

                Button { store.toggleBookmark(for: tab) } label: {
                    let saved = store.isBookmarked(tab.url)
                    Image(systemName: saved ? "star.fill" : "star")
                        .foregroundStyle(saved ? Nightglass.accent : Nightglass.secondaryText)
                }
                .buttonStyle(IconButtonStyle())
                .disabled(tab.url == nil)
                .help("Bookmark This Page (⌘D)")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            if let tab = store.selectedTab, tab.isLoading {
                LoadingBar(progress: tab.progress)
            }
        }
    }
}

/// The thin glowing line that shows how much of the page has loaded.
struct LoadingBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(LinearGradient(
                    colors: [Nightglass.accent, Nightglass.claude],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(width: geometry.size.width * max(0.05, progress))
                .shadow(color: Nightglass.accent.opacity(0.6), radius: 4)
                .animation(.easeOut(duration: 0.25), value: progress)
        }
        .frame(height: 2)
        .transition(.opacity)
    }
}

/// Type a web address or a search. Shows the page's address when you're not typing.
struct AddressBar: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tab.url?.scheme == "https" ? Nightglass.spotify : Nightglass.mutedText)
                .accessibilityHidden(true)

            TextField("Search or enter address", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(Nightglass.text)
                .focused($isFocused)
                .onSubmit {
                    store.navigate(text, in: tab)
                    isFocused = false
                }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(shape.fill(Color.black.opacity(0.35)))
        .overlay(
            shape.strokeBorder(
                isFocused ? Nightglass.accent.opacity(0.75) : Color.white.opacity(0.12),
                lineWidth: isFocused ? 1.5 : 1
            )
        )
        .shadow(color: Nightglass.accent.opacity(isFocused ? 0.3 : 0), radius: 10)
        .animation(.easeOut(duration: 0.2), value: isFocused)
        .onAppear { text = displayText }
        .onChange(of: tab.url) { if !isFocused { text = displayText } }
        .onChange(of: tab.id) { text = displayText }
        .onChange(of: isFocused) { if !isFocused { text = displayText } }
        .onChange(of: store.addressBarFocusRequest) { isFocused = true }
    }

    private var displayText: String {
        tab.url?.absoluteString ?? ""
    }

    private var iconName: String {
        if tab.url == nil { return "magnifyingglass" }
        return tab.url?.scheme == "https" ? "lock.fill" : "globe"
    }
}
