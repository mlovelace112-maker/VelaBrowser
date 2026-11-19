import SwiftUI

/// The whole browser window, top to bottom:
/// tab strip → toolbar → bookmarks bar → (find bar) → sidebar + the page.
struct ContentView: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                TabStripView()
                ToolbarView()
                BookmarksBarView()
                if store.isFindBarVisible, let tab = store.selectedTab, tab.url != nil {
                    Rectangle().fill(Nightglass.stroke).frame(height: 1)
                    FindBar(tab: tab)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .background(VisualEffectBackground())
            .overlay(alignment: .bottom) {
                Rectangle().fill(Nightglass.stroke).frame(height: 1)
            }

            HStack(spacing: 0) {
                if store.isSidebarVisible {
                    SidebarView()
                        .transition(.move(edge: .leading).combined(with: .opacity))
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
        }
        .ignoresSafeArea()
        .background(Nightglass.background)
        .animation(Nightglass.spring, value: store.isSidebarVisible)
        .animation(Nightglass.spring, value: store.isFindBarVisible)
    }
}
