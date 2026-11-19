import SwiftUI

/// The whole browser window, top to bottom:
/// tab strip → toolbar → bookmarks bar → the page (or the New Tab page).
struct ContentView: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                TabStripView()
                ToolbarView()
                BookmarksBarView()
            }
            .background(VisualEffectBackground())
            .overlay(alignment: .bottom) {
                Rectangle().fill(Nightglass.stroke).frame(height: 1)
            }

            ZStack {
                NightglassBackdrop()
                if let tab = store.selectedTab {
                    if tab.url == nil {
                        NewTabPage(tab: tab)
                            .transition(.opacity)
                    } else {
                        // `.id` gives each tab its own view, so switching tabs swaps web views.
                        WebViewContainer(webView: tab.webView)
                            .id(tab.id)
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: store.selectedTab?.url == nil)
        }
        .ignoresSafeArea()
        .background(Nightglass.background)
    }
}
