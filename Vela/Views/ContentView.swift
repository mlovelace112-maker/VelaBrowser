import SwiftUI

/// The whole browser window, top to bottom:
/// tab strip → toolbar → bookmarks bar → (find bar) → sidebar + the page +
/// Claude → the Spotify bar.
struct ContentView: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                TabStripView()
                ToolbarView()
                    .zIndex(1)
                if Appearance.shared.settings.showBookmarksBar {
                    BookmarksBarView()
                }
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
            // Draw above the page, so address bar suggestions can hang over it.
            .zIndex(1)

            HStack(spacing: 0) {
                if store.isSidebarVisible {
                    SidebarView()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                PageArea()

                if store.isClaudePanelVisible {
                    ClaudePanel()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $store.isPasswordsVisible) {
                PasswordsView()
            }

            if store.spotify.isBarVisible {
                SpotifyBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .background(Nightglass.background)
        .animation(Nightglass.spring, value: store.isSidebarVisible)
        .animation(Nightglass.spring, value: store.isClaudePanelVisible)
        .animation(Nightglass.spring, value: store.spotify.isBarVisible)
        .animation(Nightglass.spring, value: store.isFindBarVisible)
        .sheet(isPresented: $store.isCookieManagerVisible) {
            CookieManagerView()
        }
        .sheet(isPresented: $store.isSiteSettingsVisible) {
            SiteSettingsSheet()
        }
        .alert(
            downloadQuestion,
            isPresented: Binding(
                get: { store.downloadManager.pendingWarning != nil },
                set: { if !$0 { store.downloadManager.resolveWarning(false) } }
            )
        ) {
            Button("Download Anyway", role: .destructive) { store.downloadManager.resolveWarning(true) }
            Button("Cancel", role: .cancel) { store.downloadManager.resolveWarning(false) }
        } message: {
            Text(store.downloadManager.pendingWarning?.reason ?? "")
        }
    }

    private var downloadQuestion: String {
        guard let warning = store.downloadManager.pendingWarning else { return "Download this file?" }
        return "Download “\(warning.filename)”?"
    }
}

/// The page itself, with everything that floats over it: the link bubble,
/// dangerous-link warnings, "Save password?", "Pop-up blocked" and Claude's
/// quick answers.
private struct PageArea: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        ZStack {
            NightglassBackdrop()
            if let tab = store.selectedTab {
                if let search = tab.mediaSearch {
                    MediaSearchView(tab: tab, search: search)
                        .id(tab.id)
                        .transition(.opacity)
                } else if let article = tab.reader {
                    ReaderView(tab: tab, article: article)
                        .id(tab.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if tab.url == nil {
                    NewTabPage(tab: tab)
                        .transition(.opacity)
                } else {
                    // `.id` gives each tab its own view, so switching tabs swaps web views.
                    WebViewContainer(webView: tab.webView)
                        .id(tab.id)
                    if let warning = tab.linkWarning {
                        LinkWarningView(tab: tab, warning: warning)
                            .transition(.opacity)
                    } else if let insecure = tab.httpsWarning {
                        HTTPSWarningView(tab: tab, url: insecure)
                            .transition(.opacity)
                    }
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let tab = store.selectedTab, let link = tab.hoveredLink, tab.linkWarning == nil {
                LinkStatusBubble(url: link)
                    .padding(10)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: store.selectedTab?.hoveredLink)
        .overlay(alignment: .topTrailing) {
            if let prompt = store.passwordPrompt, prompt.tabID == store.selectedTabID {
                PasswordSaveBanner(prompt: prompt)
                    .padding(14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Nightglass.spring, value: store.passwordPrompt)
        .overlay(alignment: .topLeading) {
            if let tab = store.selectedTab, let request = tab.permissionRequest {
                PermissionBanner(tab: tab, request: request)
                    .padding(14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Nightglass.spring, value: store.selectedTab?.permissionRequest)
        .animation(.easeOut(duration: 0.2), value: store.selectedTab?.url == nil)
        .animation(.easeOut(duration: 0.2), value: store.selectedTab?.mediaSearch == nil)
        .animation(Nightglass.spring, value: store.selectedTab?.reader)
        .overlay(alignment: .bottom) {
            if let notice = store.pageNotice {
                Label(notice, systemImage: "info.circle")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Nightglass.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glassPanel(cornerRadius: 12)
                    .padding(.bottom, 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Nightglass.spring, value: store.pageNotice)
        .overlay(alignment: .bottom) {
            if let popup = store.blockedPopup, popup.tabID == store.selectedTabID {
                PopupBlockedToast(popup: popup)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Nightglass.spring, value: store.blockedPopup)
        .overlay(alignment: .topTrailing) {
            if let tab = store.selectedTab, tab.mediaSearch == nil, store.passwordPrompt?.tabID != tab.id,
               let query = BrowserStore.duckDuckGoQuery(tab.url) {
                MediaSearchPill(tab: tab, query: query)
                    .padding(14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Nightglass.spring, value: store.selectedTab?.url)
        .overlay(alignment: .top) {
            if let answer = store.claude.quickAnswer {
                QuickAnswerCard(answer: answer)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Nightglass.spring, value: store.claude.quickAnswer?.id)
    }
}
