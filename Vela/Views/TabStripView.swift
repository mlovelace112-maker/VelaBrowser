import AppKit
import SwiftUI

/// The row of tabs and tab groups along the top of the window.
struct TabStripView: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        HStack(spacing: 4) {
            ForEach(store.stripItems) { item in
                switch item {
                case .group(let group):
                    GroupChip(group: group)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                case .tab(let tab):
                    TabChip(tab: tab)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }

            NewTabButton()

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
        .frame(height: Appearance.shared.settings.compactTabs ? 38 : 44)
        .animation(Nightglass.spring, value: store.stripItems.map(\.id))
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
    @State private var isHovering = false

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
        .frame(width: tab.isPinned ? 36 : nil)
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
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .help(tab.isAsleep ? "\(tab.title) (sleeping to save memory)"
              : container.map { "\(tab.title) (\($0.name))" } ?? (tab.isPinned ? tab.title : ""))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(.isButton)
        .contextMenu { TabContextMenu(tab: tab) }
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
