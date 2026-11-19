import SwiftUI

/// Sidebar, back, forward, reload, the address bar, bookmarks and share.
struct ToolbarView: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            Button { withAnimation(Nightglass.spring) { store.isSidebarVisible.toggle() } } label: {
                Image(systemName: "sidebar.left")
                    .foregroundStyle(store.isSidebarVisible ? Nightglass.accent : Nightglass.secondaryText)
            }
            .buttonStyle(IconButtonStyle())
            .help("Show Sidebar (⇧⌘L)")

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

                ShieldButton(tab: tab)

                if !store.downloadManager.items.isEmpty {
                    DownloadsButton()
                        .transition(.scale.combined(with: .opacity))
                }

                // Star: add or remove this page from your bookmarks.
                Button { store.toggleBookmark(for: tab) } label: {
                    let saved = store.isBookmarked(tab.url)
                    Image(systemName: saved ? "star.fill" : "star")
                        .foregroundStyle(saved ? Nightglass.accent : Nightglass.secondaryText)
                        .symbolEffect(.bounce, value: saved)
                }
                .buttonStyle(IconButtonStyle())
                .disabled(tab.url == nil)
                .help("Bookmark This Page (⌘D)")

                // Book: open your list of bookmarks.
                if Appearance.shared.settings.showBookmarksButton {
                    Button { withAnimation(Nightglass.spring) { store.showSidebar(.bookmarks) } } label: {
                        Image(systemName: "book")
                            .foregroundStyle(
                                store.isSidebarVisible && store.sidebarSection == .bookmarks
                                    ? Nightglass.accent : Nightglass.secondaryText
                            )
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Show Bookmarks (⌥⌘B)")
                }

                if Appearance.shared.settings.showShareButton, let url = tab.url {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Share")
                }

                PageMenu(tab: tab)
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

/// The "•••" menu: zoom, find, private tab, history and more.
struct PageMenu: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab

    var body: some View {
        Menu {
            Button("New Tab") { store.newTab() }
            Button("New Private Tab") { store.newTab(isPrivate: true) }
            Button("Reopen Closed Tab") { store.reopenClosedTab() }
                .disabled(!store.canReopenClosedTab)
            Divider()
            Button("Passwords…") { store.isPasswordsVisible = true }
            Divider()
            Button("Find on Page…") { store.showFindBar() }
                .disabled(tab.url == nil)
            Section("Zoom: \(Int((tab.zoom * 100).rounded()))%") {
                Button("Zoom In") { tab.zoomIn() }
                Button("Zoom Out") { tab.zoomOut() }
                Button("Actual Size") { tab.resetZoom() }
            }
            Divider()
            Button("Show Bookmarks") { withAnimation(Nightglass.spring) { store.showSidebar(.bookmarks) } }
            Button("Show History") { withAnimation(Nightglass.spring) { store.showSidebar(.history) } }
            Button("Bookmark All Tabs") { store.addBookmarksForAllTabs() }
            Divider()
            Button("Copy Link") { store.copyLink(of: tab) }
                .disabled(tab.url == nil)
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 30, height: 30)
        .help("More")
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

            if tab.isPrivate {
                Text("Private")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Nightglass.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Nightglass.accent.opacity(0.18)))
            }

            TextField(tab.isPrivate ? "Search privately or enter address" : "Search or enter address", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(Nightglass.text)
                .focused($isFocused)
                .onSubmit {
                    store.navigate(text, in: tab)
                    isFocused = false
                }

            // Key: fill a saved password into this page's login form.
            if !tab.savedLogins.isEmpty {
                Menu {
                    ForEach(tab.savedLogins) { entry in
                        Button(entry.account.isEmpty ? "Password for \(entry.server)" : entry.account) {
                            Task { await store.fill(entry, in: tab) }
                        }
                    }
                    Divider()
                    Button("Open Passwords…") { store.isPasswordsVisible = true }
                } label: {
                    Image(systemName: "key.fill")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .tint(Nightglass.accent)
                .help("Fill saved password")
                .accessibilityLabel("Fill saved password")
            }

            // Shows the zoom level when it isn't 100%. Click to reset.
            if tab.zoom != 1 {
                Button { tab.resetZoom() } label: {
                    Text("\(Int((tab.zoom * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Nightglass.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Reset Zoom (⌘0)")
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
