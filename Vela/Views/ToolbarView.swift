import AppKit
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
                Button {
                    if tab.mediaSearch != nil {
                        // Leave the image or video grid for the page underneath.
                        tab.mediaSearch = nil
                        tab.title = tab.webView.title.flatMap { $0.isEmpty ? nil : $0 } ?? "New Tab"
                    } else {
                        tab.webView.goBack()
                    }
                } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(IconButtonStyle())
                    .disabled(!tab.canGoBack && tab.mediaSearch == nil)
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

                ClaudeButton()

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

/// The sparkle button that opens the Claude side panel.
struct ClaudeButton: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        Button { withAnimation(Nightglass.spring) { store.isClaudePanelVisible.toggle() } } label: {
            Image(systemName: "sparkle")
                .foregroundStyle(store.isClaudePanelVisible ? Nightglass.claude : Nightglass.secondaryText)
                .symbolEffect(.bounce, value: store.isClaudePanelVisible)
                .symbolEffect(.pulse, isActive: store.claude.isWorking && !store.isClaudePanelVisible)
        }
        .buttonStyle(IconButtonStyle())
        .help("Claude (⇧⌘A)")
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
            Menu("New Tab in Container") {
                ForEach(store.containers) { container in
                    Button { store.newTab(container: container.id) } label: { Label(container.name, systemImage: container.icon) }
                }
            }
            Button("Reopen Closed Tab") { store.reopenClosedTab() }
                .disabled(!store.canReopenClosedTab)
            Divider()
            Button(store.splitPair == nil ? "Split View with New Tab" : "Close Split View") {
                if store.splitPair == nil { store.openSplitViewWithNewTab() } else { store.closeSplitView() }
            }
            Toggle("Vertical Tabs", isOn: Binding(get: { store.verticalTabs }, set: { store.verticalTabs = $0 }))
            Divider()
            Button("Passwords…") { store.isPasswordsVisible = true }
            Divider()
            Button("Image Search") { store.showMediaSearch(mediaQuery, kind: .images, in: tab) }
                .disabled(mediaQuery.isEmpty)
            Button("Video Search") { store.showMediaSearch(mediaQuery, kind: .videos, in: tab) }
                .disabled(mediaQuery.isEmpty)
            Divider()
            Button("Summarize Page with Claude") { store.askClaudeInPanel("Summarize this page.") }
                .disabled(tab.url == nil || tab.isPrivate)
            Button(tab.translation == .translated ? "Show Original" : "Translate Page") {
                if tab.translation == .translated { Task { await tab.showOriginalText() } } else { tab.translateRequests += 1 }
            }
            .disabled(tab.pageLanguage == nil)
            Divider()
            Button("Add to Reading List") { store.addToReadingList(tab) }
                .disabled(tab.url == nil || tab.isPrivate || store.isInReadingList(tab.url))
            Menu("Screenshot") {
                Button("Full Page as Image") { Task { await store.takeScreenshot(.fullPageImage, of: tab) } }
                Button("Full Page as PDF") { Task { await store.takeScreenshot(.fullPagePDF, of: tab) } }
                Button("Visible Area (Copy and Save)") { Task { await store.takeScreenshot(.visibleArea, of: tab) } }
            }
            .disabled(tab.url == nil)
            Divider()
            Button("Picture in Picture") { Task { await store.togglePictureInPicture() } }
                .disabled(tab.url == nil)
            Button("Fill Private Email Address") { Task { await store.fillPrivateEmail() } }
                .disabled(tab.url == nil)
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

    /// What to search images and videos for: your DuckDuckGo search, or this page's title.
    private var mediaQuery: String {
        BrowserStore.duckDuckGoQuery(tab.url) ?? tab.mediaSearch?.query ?? (tab.url == nil ? "" : tab.title)
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
    /// What you last typed, kept so "Ask Claude" works even if clicking it
    /// takes focus away from the address bar first.
    @State private var typed = ""
    /// Suggestions from your tabs, bookmarks, history and DuckDuckGo.
    @State private var suggestions = SuggestionEngine()
    /// Stays true for a moment after the address bar loses focus, so a
    /// click on a suggestion still lands.
    @State private var showsSuggestions = false
    @State private var showsSiteInfo = false
    /// Where the address bar and the suggestion list are in the window, so a
    /// click anywhere else can close the list.
    @State private var fieldFrame: CGRect = .zero
    @State private var listFrame: CGRect = .zero
    /// Watches clicks and Esc while the list is open (see watchForDismiss).
    @State private var dismissMonitor: Any?

    /// The address bar itself: lock, text field and the small buttons.
    @ViewBuilder private var fieldBox: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

        HStack(spacing: 8) {
            Button { showsSiteInfo.toggle() } label: {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tab.url?.scheme == "https" ? Nightglass.spotify : Nightglass.mutedText)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(tab.url == nil)
            .help("Connection, certificate and site permissions")
            .accessibilityLabel("Site information")
            .popover(isPresented: $showsSiteInfo, arrowEdge: .bottom) { SiteInfoView(tab: tab) }

            if let container = store.container(for: tab) {
                ContainerBadge(container: container)
            }
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
                    if let pick = suggestions.selectedItem {
                        open(pick)
                    } else {
                        store.navigate(text, in: tab)
                        isFocused = false
                    }
                }
                // ↑ and ↓ move through the suggestions, Esc closes them.
                .onKeyPress(.downArrow) {
                    guard showsSuggestions, !suggestions.items.isEmpty else { return .ignored }
                    suggestions.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard showsSuggestions, !suggestions.items.isEmpty else { return .ignored }
                    suggestions.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard showsSuggestions, !suggestions.items.isEmpty else {
                        isFocused = false
                        return .handled
                    }
                    suggestions.clear()
                    return .handled
                }
                // Tab sends what you typed to Claude instead of searching.
                .onKeyPress(.tab) {
                    guard canAsk else { return .ignored }
                    askClaude()
                    return .handled
                }

            if isFocused && canAsk {
                Button(action: askClaude) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                        Text("Ask Claude")
                        Text("⇥").opacity(0.65)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Nightglass.claude)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Nightglass.claude.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .help("Ask Claude instead of searching (Tab)")
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

            // Key: fill a saved password into this page's login form.
            //      It opens by itself when you click into a login box and
            //      this site has more than one saved login.
            if !tab.savedLogins.isEmpty {
                @Bindable var tab = tab
                Button { tab.isLoginPickerShown.toggle() } label: {
                    Image(systemName: "key.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Nightglass.accent)
                }
                .buttonStyle(.plain)
                .help("Fill saved password")
                .accessibilityLabel("Fill saved password")
                .popover(isPresented: $tab.isLoginPickerShown, arrowEdge: .bottom) {
                    LoginPicker(tab: tab)
                }
            }

            // Translate: only on pages in another language.
            if tab.pageLanguage != nil, tab.mediaSearch == nil, tab.reader == nil, !isFocused {
                TranslateButton(tab: tab)
            }

            // Reader: show just the article.
            if tab.url != nil, tab.mediaSearch == nil, !isFocused {
                Button { Task { await store.toggleReader(for: tab) } } label: {
                    Image(systemName: tab.reader == nil ? "doc.plaintext" : "doc.plaintext.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tab.reader == nil ? Nightglass.mutedText : Nightglass.accent)
                }
                .buttonStyle(.plain)
                .help(tab.reader == nil ? "Show Reader (⇧⌘R)" : "Hide Reader (⇧⌘R)")
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { fieldFrame = $0 }
        .background(shape.fill(Color.black.opacity(0.35)))
        .overlay(
            shape.strokeBorder(
                isFocused ? Nightglass.accent.opacity(0.75) : Color.white.opacity(0.12),
                lineWidth: isFocused ? 1.5 : 1
            )
        )
        .shadow(color: Nightglass.accent.opacity(isFocused ? 0.3 : 0), radius: 10)
        .animation(.easeOut(duration: 0.2), value: isFocused)
        .animation(.easeOut(duration: 0.15), value: isFocused && canAsk)
    }

    /// The address bar with the suggestion list dropping down under it.
    private var fieldWithSuggestions: some View {
        fieldBox
        .overlay(alignment: .topLeading) {
            if showsSuggestions && !suggestions.items.isEmpty {
                SuggestionList(engine: suggestions, onPick: open)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { listFrame = $0 }
                    .offset(y: 40)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: showsSuggestions && !suggestions.items.isEmpty)
    }

    // Built in three parts (fieldBox, fieldWithSuggestions, body) so the
    // Swift compiler can check it in reasonable time.
    var body: some View {
        fieldWithSuggestions
        .onChange(of: text) {
            if isFocused {
                typed = text
                if text != displayText {
                    suggestions.update(for: text, store: store, tab: tab)
                    showsSuggestions = true // typing again after Esc brings them back
                }
            }
        }
        .onChange(of: showsSuggestions) {
            if showsSuggestions { watchForDismiss() } else { stopWatchingForDismiss() }
        }
        .onDisappear { stopWatchingForDismiss() }
        .onChange(of: isFocused) {
            if isFocused {
                showsSuggestions = true
            } else {
                // Wait a moment so a click on a suggestion still counts.
                Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    if !isFocused {
                        showsSuggestions = false
                        suggestions.clear()
                    }
                }
            }
        }
        .onAppear { text = displayText }
        .onChange(of: tab.url) { if !isFocused { text = displayText } }
        .onChange(of: tab.id) {
            hideSuggestions()
            text = displayText
        }
        .onChange(of: isFocused) { if !isFocused { text = displayText } }
        .onChange(of: store.addressBarFocusRequest) { isFocused = true }
    }

    /// Closes the suggestion list (what you typed stays in the address bar).
    private func hideSuggestions() {
        showsSuggestions = false
        suggestions.clear()
    }

    /// While the list is open, a click anywhere outside the address bar and
    /// the list closes it, and so does Esc. SwiftUI alone misses clicks on
    /// the web page, because WebKit takes those clicks itself.
    private func watchForDismiss() {
        guard dismissMonitor == nil else { return }
        dismissMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { event in
            if event.type == .keyDown {
                // 53 is the Esc key.
                guard event.keyCode == 53, showsSuggestions, !suggestions.items.isEmpty else { return event }
                hideSuggestions()
                return nil
            }
            guard let content = event.window?.contentView else {
                hideSuggestions()
                return event
            }
            // AppKit counts up from the bottom of the window; SwiftUI counts
            // down from the top.
            let point = CGPoint(x: event.locationInWindow.x,
                                y: content.bounds.height - event.locationInWindow.y)
            if !fieldFrame.contains(point) && !listFrame.contains(point) {
                hideSuggestions()
            }
            return event
        }
    }

    private func stopWatchingForDismiss() {
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor) }
        dismissMonitor = nil
    }

    /// You've typed something other than the page's address.
    private var canAsk: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != displayText
    }

    /// Opens a suggestion: switches to an open tab, or loads the page or search.
    private func open(_ suggestion: Suggestion) {
        suggestions.clear()
        showsSuggestions = false
        isFocused = false
        if case .tab(let id) = suggestion.kind, let other = store.tabs.first(where: { $0.id == id }) {
            store.select(other)
            text = displayText
            // A brand-new empty tab isn't needed once you've switched away.
            if tab.url == nil, tab.mediaSearch == nil, store.tabs.count > 1 { store.close(tab) }
        } else if let url = suggestion.url {
            tab.load(url)
        }
    }

    private func askClaude() {
        let question = typed.isEmpty ? text : typed
        store.claude.ask(question, about: tab)
        typed = ""
        isFocused = false
        text = displayText
    }

    private var displayText: String {
        tab.url?.absoluteString ?? ""
    }

    private var iconName: String {
        if tab.url == nil { return "magnifyingglass" }
        return tab.url?.scheme == "https" ? "lock.fill" : "globe"
    }
}

/// The list under the key button: pick a saved login to fill.
private struct LoginPicker: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Fill a saved login")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Nightglass.mutedText)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            ForEach(tab.savedLogins) { entry in
                Button {
                    Task { await store.fill(entry, in: tab) }
                } label: {
                    Label(entry.account.isEmpty ? "Password for \(entry.server)" : entry.account,
                          systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider().padding(.vertical, 4)
            Button("Open Passwords…") {
                tab.isLoginPickerShown = false
                store.isPasswordsVisible = true
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
        .padding(.vertical, 10)
        .frame(minWidth: 220)
    }
}

/// The list under the address bar while you type.
private struct SuggestionList: View {
    let engine: SuggestionEngine
    let onPick: (Suggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(engine.items.enumerated()), id: \.element.id) { index, item in
                if index > 0, item.kind == .search, engine.items[index - 1].kind != .search {
                    Text("DuckDuckGo")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Nightglass.mutedText)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                }
                SuggestionRow(item: item, isSelected: engine.selected == index, isTopHit: index == 0 && engine.selected == 0)
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(item) }
                    .onHover { if $0 { engine.selected = index } }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 12)
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
    }
}

private struct SuggestionRow: View {
    let item: Suggestion
    let isSelected: Bool
    let isTopHit: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(item.kind == .bookmark ? Nightglass.caution : Nightglass.mutedText)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title.isEmpty ? item.detail : item.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Nightglass.text)
                    .lineLimit(1)
                if !item.detail.isEmpty, !item.title.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Nightglass.mutedText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if isTopHit {
                Text("Top Hit  ↩")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Nightglass.accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Nightglass.accent.opacity(0.22) : Color.clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
