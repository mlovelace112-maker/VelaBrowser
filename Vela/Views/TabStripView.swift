import AppKit
import SwiftUI

/// The row of tabs and tab groups along the top of the window.
///
/// Tabs stretch to share the whole width of the window, and shrink as you
/// open more (or make the window smaller), down to a readable width. Past that the row
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
                .frame(width: 60)
                .frame(maxHeight: .infinity)
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
        .background(Nightglass.tabBacking)
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
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { scroller.groupWidths[group.id] = $0 }
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
        .frame(maxWidth: .infinity) // takes all the room between pinned tabs and the drag space
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

    /// Shares all the room in the row between the tabs, so they stretch to
    /// fill the window and resize with it, but never below a readable width
    /// (then the row scrolls instead).
    private func tabWidth(for items: [StripItem]) -> CGFloat {
        let minimum: CGFloat = compact ? 104 : 124
        var tabCount = 0
        var groupsWidth: CGFloat = 0
        for item in items {
            switch item {
            case .tab: tabCount += 1
            case .group(let group): groupsWidth += (scroller.groupWidths[group.id] ?? 110) + 4
            }
        }
        guard tabCount > 0 else { return minimum }
        // The room the scrolling row really has (measured), or a guess before the first layout.
        var room = scroller.viewportWidth
        if room <= 0 {
            let pinnedCount = store.tabs.filter(\.isPinned).count
            room = stripWidth - 90 - CGFloat(pinnedCount) * 40 - 60 - 32
        }
        // Less the group labels, the + button, padding and the gaps between tabs.
        let available = room - groupsWidth - 32 - 4 - 2
        let share = (available / CGFloat(tabCount)).rounded(.down) - 4
        return max(minimum, share)
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
    /// How wide each group label is, so tabs can share the rest.
    var groupWidths: [UUID: CGFloat] = [:]
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
                .foregroundStyle(Nightglass.tabText)
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
        // Worked out up here (not inside the modifiers below) so the Swift
        // compiler doesn't have to puzzle out one giant expression.
        let titleColor: Color = isSelected ? Nightglass.activeTabText
            : (isHovering ? Nightglass.text : Nightglass.tabText)
        // The tab you're on gets a brighter glass pill; the others a faint
        // dark one, so their text has something steady to sit on.
        let fill: Color = isSelected ? Color.white.opacity(0.16)
            : (isHovering ? Color.white.opacity(0.09) : Color.black.opacity(0.12))
        let border: Color = tab.isPrivate ? Nightglass.accent.opacity(isSelected ? 0.6 : 0.3)
            : Color.white.opacity(isSelected ? 0.2 : (isHovering ? 0.08 : 0))
        let fade: Double = tab.isAsleep && !isSelected && !isHovering ? 0.72 : 1
        let tooltip: String = tab.isAsleep ? "\(tab.title) (sleeping to save memory)"
            : container.map { "\(tab.title) (\($0.name))" } ?? (tab.isPinned ? tab.title : "")

        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                FaviconView(url: tab.url)
                    .shadow(color: Nightglass.tabTextShadow, radius: 1, y: 0.5)
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
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(titleColor)
                    .shadow(color: Nightglass.tabTextShadow, radius: 1.5, y: 0.5)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                // Speaker: this tab is playing sound. Click to mute it.
                if tab.isPlayingAudio || tab.isMuted {
                    Button { tab.toggleMute() } label: {
                        Image(systemName: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(tab.isMuted ? Nightglass.tabText : Nightglass.accent)
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
               maxWidth: tab.isPinned ? 36 : (isVertical || width != nil ? .infinity : (compact ? 160 : 200)))
        .frame(height: compact ? 26 : 30)
        .background(shape.fill(fill))
        .overlay(shape.strokeBorder(border))
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
        // Sleeping tabs fade a little, like Firefox and Edge, but stay readable.
        .opacity(fade)
        .contentShape(Rectangle())
        .onTapGesture {
            // ⌥-click: show this tab next to the current one.
            if NSEvent.modifierFlags.contains(.option), store.selectedTabID != tab.id {
                store.openSplitView(with: tab)
            } else {
                // Close the hover preview first, so the click isn't spent
                // closing it and the tab switches on the first click.
                previewTask?.cancel()
                showsPreview = false
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
        .help(tooltip)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(.isButton)
        .contextMenu { TabContextMenu(tab: tab) }
    }

    /// After resting on another tab for a moment, show a picture of its page.
    private func hoverPreview(_ hovering: Bool) {
        previewTask?.cancel()
        guard hovering, store.selectedTabID != tab.id, tab.url != nil else {
            showsPreview = false
            return
        }
        let showsPictures = UserDefaults.standard.object(forKey: "vela.tabPreviews") as? Bool ?? true
        previewTask = Task {
            // A sleeping tab starts loading while you hover, so clicking it
            // doesn't mean waiting for the whole page.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            tab.prepareToShow()
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, showsPictures else { return }
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
                    .foregroundStyle(Nightglass.activeTabText)
                    .lineLimit(1)
                Text("\(store.tabCount(in: group))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Nightglass.tabText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tint)
                    .rotationEffect(.degrees(group.isCollapsed ? 0 : 90))
            }
            .shadow(color: Nightglass.tabTextShadow, radius: 1.5, y: 0.5)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(Color.black.opacity(0.18)))
            .background(Capsule().fill(tint.opacity(0.26)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.7)))
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
    @State private var icon: NSImage?

    var body: some View {
        let host = url?.host()
        Group {
            if host != nil {
                if let icon = icon ?? host.flatMap { FaviconCache.shared.cached($0) } {
                    Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                        // A black logo (GitHub, X, Notion…) would vanish on the
                        // dark glass, so it gets a small light tile behind it.
                        .padding(FaviconCache.shared.isDark(icon) ? size * 0.1 : 0)
                        .background(FaviconCache.shared.isDark(icon) ? Color.white.opacity(0.9) : Color.clear)
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.28))
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
        .task(id: host) {
            icon = nil
            guard let host else { return }
            icon = await FaviconCache.shared.icon(for: host)
        }
    }
}

/// Site icons, downloaded once per website and kept in memory. Before,
/// every tab, bookmark and address bar fetched its icon again whenever it
/// was redrawn (for example on every tab switch), with a grey square
/// flashing in the meantime.
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()
    private var icons: [String: NSImage] = [:]
    private var loading: [String: Task<NSImage?, Never>] = [:]

    private var darkness: [ObjectIdentifier: Bool] = [:]

    func cached(_ host: String) -> NSImage? { icons[host] }

    /// True when an icon is almost all black or very dark grey, so it would
    /// be hard to see on Vela's dark glass. Worked out once per icon.
    func isDark(_ image: NSImage) -> Bool {
        let key = ObjectIdentifier(image)
        if let known = darkness[key] { return known }
        // Shrink the icon to 16×16 and average the brightness of the
        // pixels you can actually see (ignoring the transparent ones).
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        var dark = false
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            pixels.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: 16, height: 16,
                                              bitsPerComponent: 8, bytesPerRow: 16 * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return }
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            }
            var brightness = 0.0
            var visible = 0.0
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let alpha = Double(pixels[i + 3]) / 255
                guard alpha > 0.4 else { continue }
                // Colors are premultiplied, so divide the transparency back out.
                let r = Double(pixels[i]) / 255 / alpha
                let g = Double(pixels[i + 1]) / 255 / alpha
                let b = Double(pixels[i + 2]) / 255 / alpha
                brightness += 0.2126 * r + 0.7152 * g + 0.0722 * b
                visible += 1
            }
            // Mostly opaque icons have their own background, so leave those alone.
            dark = visible > 0 && visible < 16 * 16 * 0.85 && brightness / visible < 0.22
        }
        if darkness.count > 500 { darkness.removeAll() }
        darkness[key] = dark
        return dark
    }

    func icon(for host: String) async -> NSImage? {
        if let icon = icons[host] { return icon }
        if let task = loading[host] { return await task.value }
        let task = Task<NSImage?, Never> {
            guard let url = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico"),
                  let response = try? await URLSession.shared.data(from: url) else { return nil }
            return NSImage(data: response.0)
        }
        loading[host] = task
        let icon = await task.value
        loading[host] = nil
        if let icon {
            if icons.count > 500 { icons.removeAll() }
            icons[host] = icon
        }
        return icon
    }
}
