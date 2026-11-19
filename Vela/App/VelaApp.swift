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
        }

        // View menu: sidebar and zoom
        CommandGroup(before: .toolbar) {
            Button(store.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                store.isSidebarVisible.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            Button("Zoom In") { store.selectedTab?.zoomIn() }
                .keyboardShortcut("=")
            Button("Zoom Out") { store.selectedTab?.zoomOut() }
                .keyboardShortcut("-")
            Button("Actual Size") { store.selectedTab?.resetZoom() }
                .keyboardShortcut("0")
            Button("Reload Page") { store.selectedTab?.webView.reload() }
                .keyboardShortcut("r")
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
        }
    }
}
