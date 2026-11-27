import AppKit
import SwiftUI

/// One row in the command bar: a tab, a page, a command or a question for Claude.
struct CommandItem: Identifiable {
    enum Kind { case tab, bookmark, history, archived, command, claude, web }

    let id: String
    let kind: Kind
    let icon: String
    let title: String
    var subtitle: String = ""
    /// For pages: shown as the site's icon.
    var url: URL?
    let run: @MainActor () -> Void
}

/// The command bar (⌘K): one box to jump to any tab, bookmark, page from
/// your history or archived tab, run any menu command, search the web, or
/// ask Claude.
///
/// Type a few letters; ↑ and ↓ pick a row, Return opens it, Esc closes.
struct CommandBar: View {
    @Environment(BrowserStore.self) private var store
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        let items = CommandSearch.items(for: query, store: store)

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Nightglass.accent)
                TextField("Search tabs, bookmarks, history and commands, or ask Claude", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundStyle(Nightglass.text)
                    .focused($isFocused)
                    .onSubmit { run(items, at: selected) }
                    .onKeyPress(.downArrow) {
                        selected = min(selected + 1, max(items.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        selected = max(selected - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        close()
                        return .handled
                    }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            if !items.isEmpty {
                Rectangle().fill(Nightglass.stroke).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                CommandRow(item: item, isSelected: index == selected)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { run(items, at: index) }
                                    .onHover { if $0 { selected = index } }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 380)
                    .onChange(of: selected) {
                        if items.indices.contains(selected) { proxy.scrollTo(items[selected].id) }
                    }
                }
            }
        }
        .frame(width: 640)
        .glassPanel(cornerRadius: 16)
        .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
        .onChange(of: query) { selected = 0 }
        .onAppear {
            query = ""
            selected = 0
            DispatchQueue.main.async { isFocused = true }
        }
    }

    private func run(_ items: [CommandItem], at index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        close()
        item.run()
    }

    private func close() {
        store.isCommandBarVisible = false
    }
}

private struct CommandRow: View {
    let item: CommandItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let url = item.url, item.kind != .web {
                    FaviconView(url: url, size: 15)
                } else {
                    Image(systemName: item.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(item.kind == .claude ? Nightglass.claude : Nightglass.secondaryText)
                }
            }
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Nightglass.text)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Nightglass.mutedText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Nightglass.mutedText)
        }
        .padding(.horizontal, 10)
        .frame(height: item.subtitle.isEmpty ? 34 : 42)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Nightglass.accent.opacity(0.22) : Color.clear)
        )
    }

    private var label: String {
        switch item.kind {
        case .tab: "Switch to Tab"
        case .bookmark: "Bookmark"
        case .history: "History"
        case .archived: "Archived"
        case .command: "Command"
        case .claude: "Claude"
        case .web: ""
        }
    }
}

/// Builds the command bar's rows for what you've typed.
@MainActor
enum CommandSearch {
    static func items(for rawQuery: String, store: BrowserStore) -> [CommandItem] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = query.lowercased().split(separator: " ").map(String.init)

        // With nothing typed: your open tabs, then handy commands.
        if words.isEmpty {
            let tabs = store.tabs.filter { $0.id != store.selectedTabID }.prefix(6).map { tabItem($0, store: store) }
            let common = ["New Tab", "Reopen Closed Tab", "Show Claude", "Group Similar Tabs", "Full-Page Screenshot"]
            let all = Self.commands(store)
            let starters = common.compactMap { name in all.first { $0.title.hasPrefix(name) } }
            return Array(tabs) + starters
        }

        var results: [CommandItem] = []
        var seen = Set<String>()
        // A secret word? Show its hidden row first (Play/EasterEggs.swift).
        if let egg = easterEggItem(for: query, store: store) {
            results.append(egg)
        }
        func add(_ items: [CommandItem], limit: Int) {
            var added = 0
            for item in items where added < limit {
                let key = item.url.map { $0.absoluteString } ?? item.id
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                results.append(item)
                added += 1
            }
        }

        // Typed an address: open it first.
        if !query.contains(" "), query.contains("."), let url = BrowserStore.url(from: query),
           !(url.host() ?? "").contains("duckduckgo") {
            results.append(CommandItem(id: "open", kind: .web, icon: "arrow.up.right.square", title: "Open \(query)", url: url) {
                openPage(url, store: store)
            })
        }

        let tabs = ranked(store.tabs.filter { $0.url != nil }, words) { [$0.title, $0.url?.absoluteString ?? ""] }
        add(tabs.map { tabItem($0, store: store) }, limit: 4)

        let commandList = ranked(commands(store), words) { [$0.title, $0.subtitle] }
        add(commandList, limit: 4)

        let bookmarks = ranked(store.bookmarks, words) { [$0.title, $0.url.absoluteString] }
        add(bookmarks.map { bookmark in
            CommandItem(id: "b-\(bookmark.id)", kind: .bookmark, icon: "book", title: bookmark.title,
                        subtitle: bookmark.url.host() ?? "", url: bookmark.url) { openPage(bookmark.url, store: store) }
        }, limit: 3)

        let history = ranked(Array(store.history.prefix(2_000)), words) { [$0.title, $0.url.absoluteString] }
        add(history.map { entry in
            CommandItem(id: "h-\(entry.id)", kind: .history, icon: "clock", title: entry.title.isEmpty ? entry.url.absoluteString : entry.title,
                        subtitle: entry.url.host() ?? "", url: entry.url) { openPage(entry.url, store: store) }
        }, limit: 3)

        let archived = ranked(store.archivedTabs, words) { [$0.title, $0.url.absoluteString] }
        add(archived.map { item in
            CommandItem(id: "a-\(item.id)", kind: .archived, icon: "archivebox", title: item.title,
                        subtitle: item.url.host() ?? "", url: item.url) { store.restore(item) }
        }, limit: 2)

        results.append(CommandItem(id: "claude", kind: .claude, icon: "sparkle", title: "Ask Claude: “\(query)”") {
            store.claude.ask(query, about: store.selectedTab)
        })
        if store.pageMemory.isEnabled, !store.pageMemory.pages.isEmpty {
            results.append(CommandItem(id: "finder", kind: .claude, icon: "clock.arrow.circlepath",
                                       title: "Find a page I've seen: “\(query)”") {
                store.pageFinderQuestion = query
                store.isPageFinderVisible = true
            })
        }
        results.append(CommandItem(id: "web", kind: .web, icon: "magnifyingglass", title: "Search the web for “\(query)”") {
            store.navigateInUsefulTab(query)
        })
        return results
    }

    /// Items whose text contains every typed word, best matches first:
    /// a title that starts with what you typed beats one that only contains it.
    private static func ranked<T>(_ items: [T], _ words: [String], text: (T) -> [String]) -> [T] {
        var scored: [(T, Int)] = []
        for item in items {
            let fields = text(item).map { $0.lowercased() }
            let joined = fields.joined(separator: " ")
            guard words.allSatisfy({ joined.contains($0) }) else { continue }
            let title = fields.first ?? ""
            var score = 0
            if let first = words.first {
                if title.hasPrefix(first) { score += 3 }
                if title.split(separator: " ").contains(where: { $0.hasPrefix(first) }) { score += 2 }
                if fields.dropFirst().contains(where: { $0.contains("://\(first)") || $0.contains("://www.\(first)") }) { score += 2 }
            }
            scored.append((item, score))
        }
        // Stable: equal scores keep their original order (most recent first).
        return scored.enumerated()
            .sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }
            .map(\.element.0)
    }

    private static func tabItem(_ tab: BrowserTab, store: BrowserStore) -> CommandItem {
        CommandItem(id: "t-\(tab.id)", kind: .tab, icon: "square.on.square", title: tab.title,
                    subtitle: tab.url?.host() ?? "", url: tab.url) { store.select(tab) }
    }

    /// Opens a page in this tab if it's empty, otherwise in a new tab.
    private static func openPage(_ url: URL, store: BrowserStore) {
        store.open(url, inNewTab: store.selectedTab?.url != nil)
    }

    /// Everything the command bar can do, named the way the menus name it.
    private static func commands(_ store: BrowserStore) -> [CommandItem] {
        let tab = store.selectedTab
        func command(_ title: String, _ icon: String, _ keywords: String = "", _ run: @escaping @MainActor () -> Void) -> CommandItem {
            CommandItem(id: "c-\(title)", kind: .command, icon: icon, title: title, subtitle: keywords, run: run)
        }
        var list: [CommandItem] = [
            command("New Tab", "plus") { store.newTab() },
            command("New Private Tab", "eyeglasses", "incognito") { store.newTab(isPrivate: true) },
            command("Reopen Closed Tab", "arrow.uturn.backward", "undo close") { store.reopenClosedTab() },
            command("Show Claude", "sparkle", "chat ai assistant") { store.isClaudePanelVisible = true },
            command("Talk to Claude", "mic", "voice speak dictate") { store.talkToClaude() },
            command("Compare Tabs", "tablecells", "claude side by side versus products") { store.showCompareTabs() },
            command("Watched Pages", "eye", "watch monitor price changes alert") { store.isWatchSheetVisible = true },
            command("Save Tabs as Workspace", "square.stack", "session save set") { store.isWorkspaceSheetVisible = true },
            command("Organize Bookmarks with Claude", "folder", "sort folders tags smart") { store.organizeBookmarks() },
            command("Show History", "clock") { store.showSidebar(.history) },
            command("Weekly Report", "chart.bar", "activity time online stats screen time") { store.isActivityReportVisible = true },
            command("Show Bookmarks", "book") { store.showSidebar(.bookmarks) },
            command("Show Reading List", "eyeglasses", "read later") { store.showSidebar(.readingList) },
            command("Highlights & Notes", "highlighter", "annotations marked passages") { store.isHighlightsVisible = true },
            command("Keyboard Shortcuts", "keyboard", "keys customize hotkeys") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
            command(store.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar", "sidebar.left") { store.isSidebarVisible.toggle() },
            command("Group Similar Tabs", "square.stack.3d.up", "organize") { store.groupSimilarTabs() },
            command(store.verticalTabs ? "Horizontal Tabs" : "Vertical Tabs", "sidebar.squares.left", "layout") { store.verticalTabs.toggle() },
            command("Put Other Tabs to Sleep", "moon.zzz", "memory") { store.sleepOtherTabs() },
            command("Passwords", "key", "logins") { store.isPasswordsVisible = true },
            command("Manage Cookies and Site Data", "list.bullet.rectangle", "cookies") { store.isCookieManagerVisible = true },
            command("Site Settings", "globe", "permissions") { store.isSiteSettingsVisible = true },
            command("Settings", "gearshape", "preferences") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
            command("Check for Updates", "arrow.down.circle", "update") { Updater.shared.checkNow() },
            command(store.isWebPanelVisible ? "Hide Web Panels" : "Show Web Panels", "rectangle.righthalf.inset.filled", "calendar gmail sidebar") {
                store.toggleWebPanels()
            },
            command(store.darkModeEverywhere ? "Turn Off Dark Mode for Websites" : "Turn On Dark Mode for Websites", "moon", "theme night") {
                store.darkModeEverywhere.toggle()
            },
        ]
        if store.isFocusActive {
            list.append(command("Turn Off Focus Mode", "leaf", "distraction block") { store.stopFocus() })
        } else {
            list += [
                command("Focus for 25 Minutes", "leaf", "distraction block youtube pomodoro") { store.startFocus(minutes: 25) },
                command("Focus for 1 Hour", "leaf", "distraction block youtube") { store.startFocus(minutes: 60) },
                command("Focus Until I Turn It Off", "leaf", "distraction block youtube") { store.startFocus(minutes: nil) },
            ]
        }
        if !store.archivedTabs.isEmpty {
            list.append(command("Show Archived Tabs", "archivebox", "tidy") {
                store.showNotice("Archived tabs are in the Tabs menu, or type their name here")
            })
        }
        if let tab, BrowserStore.isYouTubeVideo(tab.url) {
            list.append(command("Summarize This Video", "play.rectangle", "claude youtube transcript") { store.summarizeVideo(in: tab) })
        }
        if let tab, tab.url != nil {
            list += [
                command("Close Tab", "xmark") { store.close(tab) },
                command("Duplicate Tab", "plus.square.on.square") { store.duplicate(tab) },
                command(tab.isPinned ? "Unpin Tab" : "Pin Tab", "pin") { store.togglePin(tab) },
                command("Archive This Tab", "archivebox") { store.archive(tab) },
                command(store.isBookmarked(tab.url) ? "Remove Bookmark" : "Bookmark This Page", "bookmark") { store.toggleBookmark(for: tab) },
                command("Add to Reading List", "eyeglasses", "read later") { store.addToReadingList() },
                command("Copy Link", "link", "address url") { store.copyLink(of: tab) },
                command("Find on Page", "magnifyingglass", "search") { store.showFindBar() },
                command("Reload Page", "arrow.clockwise", "refresh") { tab.webView.reload() },
                command(store.readAloudPlayer.state == .idle ? "Read Aloud" : "Stop Reading Aloud", "speaker.wave.2", "speak voice listen tts") { store.readAloud() },
                command("Is This Site Legit?", "checkmark.shield", "claude scam fraud safe trust check") { store.checkSite(in: tab) },
                command(tab.reader == nil ? "Show Reader" : "Hide Reader", "doc.plaintext", "article") {
                    Task { await store.toggleReader(for: tab) }
                },
                command("Full-Page Screenshot", "camera.viewfinder", "capture image") { Task { await store.takeScreenshot(.fullPageImage) } },
                command("Picture in Picture", "pip", "video") { Task { await store.togglePictureInPicture() } },
                command("Open in Split View", "rectangle.split.2x1", "side by side") { store.openSplitViewWithNewTab() },
                command(tab.isMuted ? "Unmute Tab" : "Mute Tab", "speaker.slash", "sound audio") { tab.toggleMute() },
                command("Video Faster", "forward", "speed playback") { store.changeVideoSpeed(faster: true) },
                command("Video Slower", "backward", "speed playback") { store.changeVideoSpeed(faster: false) },
                command("Normal Video Speed", "play", "speed playback") { store.setVideoSpeed(1) },
                command("Summarize This Page", "sparkle", "claude tldr") { store.askClaudeInPanel("Summarize this page") },
            ]
            if store.darkModeEverywhere {
                list.append(command(store.isDarkModeOn(for: tab) ? "Dark Mode Off for This Site" : "Dark Mode On for This Site", "moon", "theme night") {
                    store.toggleDarkMode(for: tab)
                })
            }
            if tab.pageLanguage != nil {
                list.append(command("Translate Page", "translate") { tab.translateRequests += 1 })
            }
        }
        return list + playCommands(store)
    }
}

extension BrowserStore {
    /// Loads typed text (an address or a search) in this tab if it's empty,
    /// otherwise in a new tab.
    func navigateInUsefulTab(_ input: String) {
        if let tab = selectedTab, tab.url == nil {
            navigate(input, in: tab)
        } else {
            navigate(input, in: newTab())
        }
    }
}
