import SwiftUI

/// The entry point of the app. `@main` tells macOS to start here.
///
/// A SwiftUI app is a tree of *scenes* (windows) that contain *views*.
/// We create one `BrowserStore` (the browser's "brain") and hand it to
/// every view through the environment.
@main
struct VelaApp: App {
    /// Connects our AppDelegate (launch and quit handling) to the SwiftUI app.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var store: BrowserStore { appDelegate.store }

    var body: some Scene {
        Window("Vela", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            BrowserCommands(store: store)
        }

        // Vela ▸ Settings… (⌘,)
        Settings {
            SettingsView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}

/// Menu bar items and keyboard shortcuts. Most match Safari's.
struct BrowserCommands: Commands {
    let store: BrowserStore

    var body: some Commands {
        // File menu
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { store.newTab() }
                .keyboardShortcut("t")
            Button("New Private Tab") { store.newTab(isPrivate: true) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Reopen Closed Tab") { store.reopenClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Close Tab") {
                if let tab = store.selectedTab { store.close(tab) }
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            Divider()
            Button("Open Location…") { store.addressBarFocusRequest += 1 }
                .keyboardShortcut("l")
            Button("Command Bar…") { store.isCommandBarVisible.toggle() }
                .keyboardShortcut("k")
        }

        // Vela menu
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Updater.shared.checkNow() }
                .disabled(!Updater.shared.isAvailable)
        }
        CommandGroup(after: .appSettings) {
            Button("Make Vela the Default Browser") {
                Task { await store.defaultBrowser.makeDefault() }
            }
            .disabled(store.defaultBrowser.isDefault)
        }

        // Shield
        CommandGroup(after: .newItem) {
            Divider()
            Button("Manage Cookies and Site Data…") { store.isCookieManagerVisible = true }
                .keyboardShortcut("k", modifiers: [.command, .option])
            Button("Passwords…") { store.isPasswordsVisible = true }
                .keyboardShortcut("p", modifiers: [.command, .option])
        }

        // Edit menu: Find
        CommandGroup(after: .textEditing) {
            Button("Find on Page…") { store.showFindBar() }
                .keyboardShortcut("f")
            Button("Fill Private Email Address") { Task { await store.fillPrivateEmail() } }
                .keyboardShortcut("e", modifiers: [.command, .option])
        }

        // View menu: sidebar and zoom
        CommandGroup(before: .toolbar) {
            Button(store.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                store.isSidebarVisible.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            Button(store.isClaudePanelVisible ? "Hide Claude" : "Show Claude") {
                store.isClaudePanelVisible.toggle()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            Button(store.spotify.isBarVisible ? "Hide Spotify Player" : "Show Spotify Player") {
                store.spotify.isBarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            Divider()
            Button("Zoom In") { store.selectedTab?.zoomIn() }
                .keyboardShortcut("=")
            Button("Zoom Out") { store.selectedTab?.zoomOut() }
                .keyboardShortcut("-")
            Button("Actual Size") { store.selectedTab?.resetZoom() }
                .keyboardShortcut("0")
            Button("Reload Page") { store.selectedTab?.webView.reload() }
                .keyboardShortcut("r")
            Button(store.selectedTab?.reader == nil ? "Show Reader" : "Hide Reader") {
                Task { await store.toggleReader() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Picture in Picture") { Task { await store.togglePictureInPicture() } }
                .keyboardShortcut("v", modifiers: [.command, .option])
            Button("Translate Page") { store.selectedTab?.translateRequests += 1 }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(store.selectedTab?.pageLanguage == nil)
            Button("Add to Reading List") { store.addToReadingList() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Full-Page Screenshot") { Task { await store.takeScreenshot(.fullPageImage) } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            VideoMenu(store: store)
            SiteToolsMenu(store: store)
            Divider()
        }

        // History menu
        CommandMenu("History") {
            Button("Back") { store.selectedTab?.webView.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { store.selectedTab?.webView.goForward() }
                .keyboardShortcut("]")
            Divider()
            Button("Show All History") { store.showSidebar(.history) }
                .keyboardShortcut("y")
            Button("Find a Page I've Seen…") { store.isPageFinderVisible = true }
                .keyboardShortcut("y", modifiers: [.command, .option])
            Button("Weekly Report") { store.isActivityReportVisible = true }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Clear History") { store.clearHistory() }
        }

        // Bookmarks menu
        CommandMenu("Bookmarks") {
            Button("Show Bookmarks") { store.showSidebar(.bookmarks) }
                .keyboardShortcut("b", modifiers: [.command, .option])
            Button("Add Bookmark") {
                if let tab = store.selectedTab { store.toggleBookmark(for: tab) }
            }
            .keyboardShortcut("d")
            Button("Bookmark All Tabs") { store.addBookmarksForAllTabs() }
        }

        // Tabs menu
        CommandMenu("Tabs") {
            Button("Show Next Tab") { store.selectAdjacentTab(forward: true) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Show Previous Tab") { store.selectAdjacentTab(forward: false) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Divider()
            Button("Group Similar Tabs") { store.groupSimilarTabs() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Pin Tab") {
                if let tab = store.selectedTab { store.togglePin(tab) }
            }
            Button("Duplicate Tab") {
                if let tab = store.selectedTab { store.duplicate(tab) }
            }
            Divider()
            Button(store.splitPair == nil ? "Split View with New Tab" : "Close Split View") {
                if store.splitPair == nil { store.openSplitViewWithNewTab() } else { store.closeSplitView() }
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            Toggle("Vertical Tabs", isOn: Binding(get: { store.verticalTabs }, set: { store.verticalTabs = $0 }))
                .keyboardShortcut("v", modifiers: [.command, .control])
            Menu("New Tab in Container") {
                ForEach(store.containers) { container in
                    Button(container.name) { store.newTab(container: container.id) }
                }
            }
            Divider()
            Menu("Archived Tabs") {
                if store.archivedTabs.isEmpty {
                    Text("No archived tabs")
                }
                ForEach(store.archivedTabs.prefix(25)) { item in
                    Button(item.title.isEmpty ? item.url.absoluteString : item.title) { store.restore(item) }
                }
                if !store.archivedTabs.isEmpty {
                    Divider()
                    Button("Clear Archived Tabs") { store.clearArchivedTabs() }
                }
            }
            Button("Archive This Tab") {
                if let tab = store.selectedTab { store.archive(tab) }
            }
            .disabled(store.selectedTab?.url == nil || store.selectedTab?.isPrivate == true)
            Button("Put Other Tabs to Sleep") { store.sleepOtherTabs() }
            Button("Site Settings…") { store.isSiteSettingsVisible = true }
        }
    }
}

/// View ▸ Video: speed, skip and mute for whatever is playing in this tab.
struct VideoMenu: View {
    let store: BrowserStore

    var body: some View {
        Menu("Video") {
            Button("Faster") { store.changeVideoSpeed(faster: true) }
                .keyboardShortcut(".", modifiers: [.command, .control])
            Button("Slower") { store.changeVideoSpeed(faster: false) }
                .keyboardShortcut(",", modifiers: [.command, .control])
            Button("Normal Speed") { store.setVideoSpeed(1) }
                .keyboardShortcut("0", modifiers: [.command, .control])
            Divider()
            Button("Skip Forward 10 Seconds") { store.selectedTab?.skipMedia(by: 10) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
            Button("Skip Back 10 Seconds") { store.selectedTab?.skipMedia(by: -10) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
            Divider()
            Button(store.selectedTab?.isMuted == true ? "Unmute Tab" : "Mute Tab") { store.selectedTab?.toggleMute() }
                .keyboardShortcut("m", modifiers: [.command, .control])
        }
        .disabled(store.selectedTab?.url == nil)
    }
}

/// View menu: dark mode, web panels and focus mode.
struct SiteToolsMenu: View {
    let store: BrowserStore

    var body: some View {
        Toggle("Dark Mode for This Site", isOn: Binding(
            get: { store.selectedTab.map { store.isDarkModeOn(for: $0) } ?? false },
            set: { _ in if let tab = store.selectedTab { store.toggleDarkMode(for: tab) } }
        ))
        .disabled(!store.darkModeEverywhere || store.selectedTab?.url == nil)
        Button(store.isWebPanelVisible ? "Hide Web Panels" : "Show Web Panels") { store.toggleWebPanels() }
            .keyboardShortcut("p", modifiers: [.command, .control])
        Menu("Focus") {
            if store.isFocusActive {
                Button("Turn Off Focus Mode") { store.stopFocus() }
            } else {
                Button("Focus for 25 Minutes") { store.startFocus(minutes: 25) }
                Button("Focus for 1 Hour") { store.startFocus(minutes: 60) }
                Button("Focus for 2 Hours") { store.startFocus(minutes: 120) }
                Button("Focus Until I Turn It Off") { store.startFocus(minutes: nil) }
            }
        }
    }
}
