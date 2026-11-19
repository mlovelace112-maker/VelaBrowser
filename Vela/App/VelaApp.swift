import SwiftUI

/// The entry point of the app. `@main` tells macOS to start here.
///
/// A SwiftUI app is a tree of *scenes* (windows) that contain *views*.
/// We create one `BrowserStore` (the browser's "brain") and hand it to
/// every view through the environment.
@main
struct VelaApp: App {
    @State private var store = BrowserStore()

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
    }
}

/// Menu bar items and keyboard shortcuts (⌘T, ⌘L, ⌘R, ...).
struct BrowserCommands: Commands {
    let store: BrowserStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { store.newTab() }
                .keyboardShortcut("t")
        }
        CommandMenu("Navigate") {
            Button("Open Location") { store.addressBarFocusRequest += 1 }
                .keyboardShortcut("l")
            Button("Reload Page") { store.selectedTab?.webView.reload() }
                .keyboardShortcut("r")
            Button("Back") { store.selectedTab?.webView.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { store.selectedTab?.webView.goForward() }
                .keyboardShortcut("]")
            Divider()
            Button("Bookmark This Page") {
                if let tab = store.selectedTab { store.toggleBookmark(for: tab) }
            }
            .keyboardShortcut("d")
            Button("Group Similar Tabs") { store.groupSimilarTabs() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Close Tab") {
                if let tab = store.selectedTab { store.close(tab) }
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
        }
    }
}
