import AppKit
import SwiftUI

/// The row of tabs and tab groups along the top of the window.
///
/// Tabs shrink as you open more, down to a readable width. Past that the row
/// scrolls sideways (trackpad swipe or mouse wheel), the edges fade to show
/// there's more, and ⌄ lists every tab. Pinned tabs always stay in view.
struct TabStripView: View {
    @Environment(BrowserStore.self) private var store
    @State private var stripWidth: CGFloat = 1_000
    @State private var scroller = TabScroller()
    @State private var position = ScrollPosition(edge: .leading)

    private var compact: Bool { Appearance.shared.settings.compactTabs }

    var body: some View {
        let items = store.stripItems
        let pinned = items.filter(\.isPinnedTab)
        let others = items.filter { !$0.isPinnedTab }

        HStack(spacing: 4) {
            ForEach(pinned) { item in
                if case .tab(let tab) = item {
                    TabChip(tab: tab).transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            scrollingTabs(others)
            if scroller.isOverflowing { AllTabsMenu() }

            // Empty space you can drag to move the window (the title bar is hidden).
            Color.clear
                .frame(minWidth: 60, maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())

            Button { store.groupSimilarTabs() } label: {
                Image(systemName: "square.stack.3d.up")
            }
            .buttonStyle(IconButtonStyle(size: 28))
            .help("Group Similar Tabs (⇧⌘G)")
        }
        .padding(.leading, 80) // room for the red/yellow/green window buttons
        .padding(.trailing, 10)
        .frame(height: compact ? 38 : 44)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stripWidth = $0 }
        .animation(Nightglass.spring, value: items.map(\.id))
        .onChange(of: store.selectedTabID) { _, id in
            guard let id, store.selectedTab?.isPinned == false else { return }
            withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(id: id, anchor: .center) }
        }
        .onAppear { scroller.start { delta in scroll(by: delta) } }
        .onDisappear { scroller.stop() }
    }

    private func scrollingTabs(_ items: [StripItem]) -> some View {
        let width = tabWidth(for: items)
        return ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(items) { item in
                    switch item {
                    case .group(let group):
                        GroupChip(group: group)
                            .id(group.id)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    case .tab(let tab):
                        TabChip(tab: tab, width: width)
                            .id(tab.id)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                NewTabButton()
            }
            .scrollTargetLayout()
            .padding(.horizontal, 2)
            .frame(maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { scroller.contentWidth = $0 }
        }
        .scrollIndicators(.never)
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in scroller.offset = x }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { scroller.viewportWidth = $0 }
        .frame(maxWidth: scroller.contentWidth > 0 ? scroller.contentWidth : .infinity)
        .mask { edgeFade }
        .onHover { scroller.isHovering = $0 }
    }

    /// Fades whichever edge has more tabs past it.
    private var edgeFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: scroller.offset > 1 ? 22 : 0)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: scroller.offset < scroller.maxOffset - 1 ? 22 : 0)
        }
    }

    /// Shares the room between tabs, but never below a readable width.
    private func tabWidth(for items: [StripItem]) -> CGFloat {
        let minimum: CGFloat = compact ? 104 : 124
        let maximum: CGFloat = compact ? 160 : 200
        var tabCount = 0
        var groupCount = 0
        for item in items {
            if case .tab = item { tabCount += 1 } else { groupCount += 1 }
        }
        guard tabCount > 0 else { return maximum }
        let pinnedCount = store.tabs.filter(\.isPinned).count
        // Window buttons, pinned tabs, group labels, +, ⌄, drag space and the group button.
        let fixed = 90 + CGFloat(pinnedCount) * 40 + CGFloat(groupCount) * 110 + 32 + 32 + 60 + 32
        let share = (stripWidth - fixed) / CGFloat(tabCount) - 4
        return min(maximum, max(minimum, share))
    }

    /// Mouse wheel (up and down) scrolls the tabs sideways.
    private func scroll(by delta: CGFloat) {
        let target = min(max(0, scroller.offset - delta), scroller.maxOffset)
        position.scrollTo(x: target)
    }
}

@MainActor
extension StripItem {
    var isPinnedTab: Bool {
        switch self {
        case .tab(let tab): tab.isPinned
        case .group: false
        }
    }
}

/// Keeps track of the tab row's scrolling, and turns an ordinary mouse
/// wheel into sideways scrolling while the pointer is over the tabs.
@MainActor
@Observable
final class TabScroller {
    var offset: CGFloat = 0
    var contentWidth: CGFloat = 0
    var viewportWidth: CGFloat = 0
    @ObservationIgnored var isHovering = false
    @ObservationIgnored private var monitor: Any?

    var maxOffset: CGFloat { max(0, contentWidth - viewportWidth) }
    var isOverflowing: Bool { contentWidth > viewportWidth + 1 }

    func start(_ scroll: @escaping @MainActor (CGFloat) -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isHovering, self.isOverflowing,
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
            // A mouse wheel moves in "lines"; a trackpad in points.
            let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
            scroll(step)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// ⌄ at the end of a long tab row: every tab in a list.
private struct AllTabsMenu: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        Menu {
            ForEach(store.tabs) { tab in
                Button {
                    store.select(tab)
                } label: {
                    if tab.id == store.selectedTabID {
                        Label(tab.title, systemImage: "checkmark")
                    } else {
                        Text(tab.title)
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 28, height: 28)
        .help("All Tabs (\(store.tabs.count))")
    }
}

/// The + button. Click for a new tab; right-click (or hold) for a private
/// tab or a tab in a container.
struct NewTabButton: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        Button { store.newTab() } label: {
            Image(systemName: "plus")
        }
        .buttonStyle(IconButtonStyle(size: 28))
        .help("New Tab (⌘T). Right-click for a private tab or a container.")
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
    }
}

/// One tab in the strip. Pinned tabs shrink to just their icon.
/// In vertical tabs, `isVertical` makes it a full-width row.
struct TabChip: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab
    var isVertical = false
    /// Set by the tab row: every tab gets the same width.
    var width: CGFloat? = nil
    @State private var isHovering = false
    @State private var showsPreview = false
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        let isSelected = store.selectedTabID == tab.id
        let group = store.group(for: tab)
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let compact = Appearance.shared.settings.compactTabs
        let container = store.container(for: tab)
        let isInSplit = store.splitPair?.contains(tab.id) == true

        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                FaviconView(url: tab.url)
                if tab.isPrivate {
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(1.5)
                        .background(Circle().fill(Nightglass.accent))
                        .offset(x: 5, y: 4)
                }
            }
            if !tab.isPinned {
                Text(tab.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isSelected ? Nightglass.text : Nightglass.mutedText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                // Speaker: this tab is playing sound. Click to mute it.
                if tab.isPlayingAudio || tab.isMuted {
                    Button { tab.toggleMute() } label: {
                        Image(systemName: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(tab.isMuted ? Nightglass.mutedText : Nightglass.accent)
                    }
                    .buttonStyle(IconButtonStyle(size: 18))
                    .help(tab.isMuted ? "Unmute this tab (⌃⌘M)" : "Mute this tab (⌃⌘M)")
                    .accessibilityLabel(tab.isMuted ? "Unmute tab" : "Mute tab")
                }
                if tab.isUsingCamera || tab.isUsingMicrophone {
                    Button { tab.stopCapture() } label: {
                        Image(systemName: tab.isUsingCamera ? "video.fill" : "mic.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Nightglass.danger)
                    }
                    .buttonStyle(IconButtonStyle(size: 18))
                    .help("This tab is using your \(tab.isUsingCamera ? "camera" : "microphone"). Click to turn it off.")
                }
                if isHovering || isSelected {
                    Button { store.close(tab) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(IconButtonStyle(size: 18))
                    .help("Close Tab (⇧⌘W)")
                }
            }
        }
        .padding(.horizontal, tab.isPinned ? 0 : 10)
        .frame(width: tab.isPinned ? 36 : width)
        .frame(minWidth: tab.isPinned ? 36 : (isVertical ? 0 : (compact ? 70 : 90)),
               maxWidth: tab.isPinned ? 36 : (isVertical ? .infinity : (compact ? 160 : 200)))
        .frame(height: compact ? 26 : 30)
        .background(shape.fill(Color.white.opacity(isSelected ? 0.12 : (isHovering ? 0.06 : 0))))
        .overlay(shape.strokeBorder(
            tab.isPrivate ? Nightglass.accent.opacity(isSelected ? 0.6 : 0.3) : Color.white.opacity(isSelected ? 0.14 : 0)
        ))
        .overlay(alignment: .bottom) {
            if let group, !isVertical {
                Capsule().fill(group.color.color).frame(height: 2).padding(.horizontal, 10)
            }
        }
        // Containers get a colored line on top (on the left in vertical tabs).
        .overlay(alignment: isVertical ? .leading : .top) {
            if let container {
                Capsule().fill(container.color.color)
                    .frame(width: isVertical ? 3 : nil, height: isVertical ? nil : 2)
                    .padding(isVertical ? .vertical : .horizontal, isVertical ? 7 : 10)
            }
        }
        // Split view: a small side-by-side icon.
        .overlay(alignment: .topTrailing) {
            if isInSplit && !tab.isPinned {
                Image(systemName: "rectangle.split.2x1.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Nightglass.accent)
                    .padding(3)
            }
        }
        .shadow(color: .black.opacity(isSelected ? 0.35 : 0), radius: 8, y: 3)
        // Sleeping tabs fade a little, like Firefox and Edge.
        .opacity(tab.isAsleep && !isSelected ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            // ⌥-click: show this tab next to the current one.
            if NSEvent.modifierFlags.contains(.option), store.selectedTabID != tab.id {
                store.openSplitView(with: tab)
            } else {
                store.select(tab)
            }
        }
        .onHover { hovering in
            isHovering = hovering
            hoverPreview(hovering)
        }
        .popover(isPresented: $showsPreview, arrowEdge: isVertical ? .trailing : .bottom) {
            TabPreviewCard(tab: tab)
        }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .help(tab.isAsleep ? "\(tab.title) (sleeping to save memory)"
              : container.map { "\(tab.title) (\($0.name))" } ?? (tab.isPinned ? tab.title : ""))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(.isButton)
        .contextMenu { TabContextMenu(tab: tab) }
    }

    /// After resting on another tab for a moment, show a picture of its page.
    private func hoverPreview(_ hovering: Bool) {
        previewTask?.cancel()
        guard hovering, store.selectedTabID != tab.id, tab.url != nil,
              UserDefaults.standard.object(forKey: "vela.tabPreviews") as? Bool ?? true else {
            showsPreview = false
            return
        }
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            showsPreview = true
        }
    }
}

/// The picture and address shown when you hover over a tab.
private struct TabPreviewCard: View {
    let tab: BrowserTab

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let preview = tab.preview {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 300, height: 180, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text(tab.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Nightglass.text)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(tab.url?.host() ?? "")
                if tab.isAsleep { Text("· Sleeping to save memory") }
            }
            .font(.system(size: 11))
            .foregroundStyle(Nightglass.mutedText)
        }
        .padding(10)
        .frame(width: 320, alignment: .leading)
    }
}

/// Everything you can do to a tab with a right-click.
struct TabContextMenu: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab

    var body: some View {
        let site = tab.url.map(BrowserStore.siteName)
        let sameSiteCount = store.sameSiteTabCount(as: tab)

        Button("New Tab to the Right") { store.newTab(opener: tab) }
        Button("Duplicate Tab") { store.duplicate(tab) }
            .disabled(tab.url == nil)
        Button("Reload Tab") { tab.webView.reload() }
            .disabled(tab.url == nil)
        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") {
            withAnimation(Nightglass.spring) { store.togglePin(tab) }
        }
        Button("Put Tab to Sleep") { tab.sleep() }
            .disabled(tab.isAsleep || tab.url == nil || store.selectedTabID == tab.id)
        Button(tab.isMuted ? "Unmute Tab" : "Mute Tab") { tab.toggleMute() }
            .disabled(tab.url == nil)
        Button("Archive Tab") { store.archive(tab) }
            .disabled(tab.url == nil || tab.isPrivate)
        Button("Open in Split View") { store.openSplitView(with: tab) }
            .disabled(store.selectedTabID == tab.id)
        if !tab.isPrivate {
            Menu("Reopen in Container") {
                if tab.containerID != nil {
                    Button("No Container") { store.reopen(tab, inContainer: nil) }
                }
                ForEach(store.containers.filter { $0.id != tab.containerID }) { container in
                    Button { store.reopen(tab, inContainer: container.id) } label: {
                        Label(container.name, systemImage: container.icon)
                    }
                }
            }
            .disabled(tab.url == nil)
        }

        Divider()

        // Grouping
        if let site, sameSiteCount >= 2 {
            Button("Group All \(site) Tabs (\(sameSiteCount))") {
                withAnimation(Nightglass.spring) { store.groupTabsFromSameSite(as: tab) }
            }
        }
        Button("Group Similar Tabs") {
            withAnimation(Nightglass.spring) { store.groupSimilarTabs() }
        }
        if tab.groupID == nil {
            Button("Add to New Group") {
                withAnimation(Nightglass.spring) { store.addToNewGroup(tab) }
            }
        } else {
            Button("Remove from Group") {
                withAnimation(Nightglass.spring) { store.removeFromGroup(tab) }
            }
        }
        let otherGroups = store.groups.filter { $0.id != tab.groupID }
        if !otherGroups.isEmpty {
            Menu("Move to Group") {
                ForEach(otherGroups) { target in
                    Button(target.name) {
                        withAnimation(Nightglass.spring) { store.move(tab, to: target) }
                    }
                }
            }
        }

        Divider()

        Button(store.isBookmarked(tab.url) ? "Remove Bookmark" : "Bookmark This Tab") {
            store.toggleBookmark(for: tab)
        }
        .disabled(tab.url == nil)
        Button("Copy Link") { store.copyLink(of: tab) }
            .disabled(tab.url == nil)
        if let url = tab.url {
            ShareLink("Share…", item: url)
        }

        Divider()

        Button("Close Tab") { withAnimation(Nightglass.spring) { store.close(tab) } }
        Button("Close Other Tabs") { withAnimation(Nightglass.spring) { store.closeOtherTabs(except: tab) } }
            .disabled(store.tabs.count < 2)
        Button("Close Tabs to the Right") { withAnimation(Nightglass.spring) { store.closeTabsToTheRight(of: tab) } }
    }
}

/// The colored pill that names a group. Click it to collapse or expand.
struct GroupChip: View {
    @Environment(BrowserStore.self) private var store
    let group: TabGroup
    @State private var isRenaming = false
    @State private var draftName = ""

    var body: some View {
        let tint = group.color.color

        Button {
            withAnimation(Nightglass.spring) { store.toggleCollapsed(group) }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(group.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("\(store.tabCount(in: group))")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.7)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(group.isCollapsed ? 0 : 90))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(tint.opacity(0.16)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.45)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(group.isCollapsed ? "Expand group" : "Collapse group")
        .contextMenu {
            Button("Rename Group…") {
                draftName = group.name
                isRenaming = true
            }
            Menu("Color") {
                ForEach(GroupColor.allCases, id: \.self) { color in
                    Button(color.name) { store.setColor(color, for: group) }
                }
            }
            Divider()
            Button("Ungroup") { withAnimation(Nightglass.spring) { store.ungroup(group) } }
            Button("Close Group") { withAnimation(Nightglass.spring) { store.closeGroup(group) } }
        }
        .alert("Rename Group", isPresented: $isRenaming) {
            TextField("Name", text: $draftName)
            Button("Save") { store.rename(group, to: draftName) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// A website's little icon, with a fallback while it loads.
struct FaviconView: View {
    let url: URL?
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let host = url?.host(),
               let iconURL = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") {
                AsyncImage(url: iconURL) { image in
                    image.resizable().interpolation(.high).scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.15))
                }
            } else {
                Image(systemName: "sparkle")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Nightglass.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}
