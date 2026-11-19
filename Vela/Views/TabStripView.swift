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

            Button { store.newTab() } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(IconButtonStyle(size: 28))
            .help("New Tab (⌘T)")

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
        .frame(height: 44)
        .animation(Nightglass.spring, value: store.stripItems.map(\.id))
    }
}

/// One tab in the strip.
struct TabChip: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab
    @State private var isHovering = false

    var body: some View {
        let isSelected = store.selectedTabID == tab.id
        let group = store.group(for: tab)
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)

        HStack(spacing: 8) {
            FaviconView(url: tab.url)
            Text(tab.title)
                .font(.system(size: 12.5))
                .foregroundStyle(isSelected ? Nightglass.text : Nightglass.mutedText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if isHovering || isSelected {
                Button { store.close(tab) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(IconButtonStyle(size: 18))
                .help("Close Tab")
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 90, maxWidth: 200)
        .frame(height: 30)
        .background(shape.fill(Color.white.opacity(isSelected ? 0.12 : (isHovering ? 0.06 : 0))))
        .overlay(shape.strokeBorder(Color.white.opacity(isSelected ? 0.14 : 0)))
        .overlay(alignment: .bottom) {
            if let group {
                Capsule().fill(group.color.color).frame(height: 2).padding(.horizontal, 10)
            }
        }
        .shadow(color: .black.opacity(isSelected ? 0.35 : 0), radius: 8, y: 3)
        .contentShape(Rectangle())
        .onTapGesture { store.select(tab) }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button("New Tab to the Right") { store.newTab(opener: tab) }
            Divider()
            if tab.groupID == nil {
                Button("Add to New Group") { withAnimation(Nightglass.spring) { store.addToNewGroup(tab) } }
            } else {
                Button("Remove from Group") { withAnimation(Nightglass.spring) { store.removeFromGroup(tab) } }
            }
            if !store.groups.isEmpty {
                Menu("Move to Group") {
                    ForEach(store.groups) { target in
                        Button(target.name) { withAnimation(Nightglass.spring) { store.move(tab, to: target) } }
                    }
                }
            }
            Divider()
            Button("Close Tab") { store.close(tab) }
        }
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
