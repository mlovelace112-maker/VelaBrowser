import AppKit
import SwiftUI
import WebKit

/// Tabs in a list down the left side (Tabs ▸ Vertical Tabs, ⌃⌘V).
/// Handy with lots of tabs: titles stay readable instead of shrinking.
struct VerticalTabsView: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        let pinned = store.tabs.filter(\.isPinned)

        VStack(alignment: .leading, spacing: 8) {
            if !pinned.isEmpty {
                // Pinned tabs as a grid of icons at the top, like Arc.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 6)], spacing: 6) {
                    ForEach(pinned) { tab in TabChip(tab: tab, isVertical: true) }
                }
                Rectangle().fill(Nightglass.stroke).frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(store.stripItems) { item in
                        switch item {
                        case .group(let group):
                            GroupChip(group: group)
                                .frame(maxWidth: 206, alignment: .leading)
                                .padding(.top, 6)
                        case .tab(let tab) where !tab.isPinned:
                            TabChip(tab: tab, isVertical: true)
                                .padding(.leading, tab.groupID == nil ? 0 : 12)
                        case .tab:
                            EmptyView()
                        }
                    }
                }
                .animation(Nightglass.spring, value: store.stripItems.map(\.id))
            }

            HStack {
                Button { store.newTab() } label: {
                    Label("New Tab", systemImage: "plus")
                        .font(.system(size: 12.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Nightglass.mutedText)
                .contextMenu {
                    Button("New Private Tab") { store.newTab(isPrivate: true) }
                    Section("New Tab in Container") {
                        ForEach(store.containers) { container in
                            Button { store.newTab(container: container.id) } label: {
                                Label(container.name, systemImage: container.icon)
                            }
                        }
                    }
                }
                Button { store.groupSimilarTabs() } label: { Image(systemName: "square.stack.3d.up") }
                    .buttonStyle(IconButtonStyle(size: 24))
                    .help("Group Similar Tabs (⇧⌘G)")
            }
            .padding(.horizontal, 6)
        }
        .padding(10)
        .frame(width: 230)
        .clipped() // nothing inside may push the list off the window's edge
        .background(VisualEffectBackground())
        .overlay(alignment: .trailing) {
            Rectangle().fill(Nightglass.stroke).frame(width: 1)
        }
    }
}

/// With vertical tabs there's no tab strip on top, so this thin bar keeps
/// room for the red/yellow/green buttons and something to drag the window by.
struct WindowDragBar: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
    }
}

/// The second page in split view: the tab you're not typing in. Click
/// anywhere in it to switch the address bar to it.
struct SplitPane: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab
    @State private var clickWatcher: Any?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                FaviconView(url: tab.url, size: 13)
                Text(tab.url == nil ? "New Tab" : tab.title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
                    .lineLimit(1)
                Spacer()
                Button { store.closeSplitView() } label: { Image(systemName: "xmark") }
                    .buttonStyle(IconButtonStyle(size: 20))
                    .help("Close Split View (⌥⌘D)")
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color.black.opacity(0.25))
            .contentShape(Rectangle())
            .onTapGesture { store.select(tab) }

            if tab.url == nil {
                NewTabPage(tab: tab)
            } else {
                WebViewContainer(webView: tab.webView)
                    .id(tab.id)
            }
        }
        .opacity(0.92)
        .onAppear(perform: watchClicks)
        .onDisappear {
            if let clickWatcher { NSEvent.removeMonitor(clickWatcher) }
            clickWatcher = nil
        }
    }

    /// A click inside this page makes it the active one (WebKit takes the
    /// click itself, so SwiftUI never sees it).
    private func watchClicks() {
        let webView = tab.webView
        let tabID = tab.id
        clickWatcher = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if event.window === webView.window,
               webView.bounds.contains(webView.convert(event.locationInWindow, from: nil)),
               let target = store.tabs.first(where: { $0.id == tabID }) {
                store.select(target)
            }
            return event
        }
    }
}
