import SwiftUI

/// The left sidebar (⇧⌘L) with your Bookmarks and History, like Safari's.
struct SidebarView: View {
    @Environment(BrowserStore.self) private var store
    @State private var search = ""

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 12) {
            // Section switcher. (A standard segmented picker grew wider than
            // the sidebar once it had four sections, pushing the sidebar off
            // the left edge of the window, so these share the width evenly.)
            HStack(spacing: 2) {
                ForEach(SidebarSection.allCases) { section in
                    let isSelected = store.sidebarSection == section
                    Button { store.sidebarSection = section } label: {
                        VStack(spacing: 2) {
                            Image(systemName: section.symbol)
                                .font(.system(size: 12, weight: .semibold))
                            Text(section.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(isSelected ? Nightglass.text : Nightglass.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(isSelected ? 0.12 : 0)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(section.rawValue)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.3)))

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Nightglass.mutedText)
                    .accessibilityHidden(true)
                TextField("Search \(store.sidebarSection.rawValue.lowercased())", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.3)))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    switch store.sidebarSection {
                    case .bookmarks: bookmarksList
                    case .history: historyList
                    case .safari: safariList
                    case .readingList: ReadingListSection(search: search)
                    }
                }
            }
            .scrollIndicators(.never)

            if store.sidebarSection == .history && !store.history.isEmpty {
                Button("Clear History…") { confirmClear = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Nightglass.claude)
            }
        }
        .padding(14)
        .frame(width: 290)
        .frame(maxHeight: .infinity)
        .clipped()
        .background(VisualEffectBackground(material: .sidebar))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Nightglass.stroke).frame(width: 1)
        }
        .onChange(of: store.sidebarSection) {
            if store.sidebarSection == .safari { store.safariBookmarks.reload() }
        }
        .confirmationDialog("Clear all browsing history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { store.clearHistory() }
        } message: {
            Text("This removes every page from History. Bookmarks are kept.")
        }
    }

    @State private var confirmClear = false

    // MARK: Bookmarks

    @ViewBuilder
    private var bookmarksList: some View {
        let items = store.bookmarks.filter(matches)
        let folders = store.bookmarkFolders
        if store.claude.hasKey && !store.bookmarks.isEmpty && search.isEmpty {
            organizeButton(hasFolders: !folders.isEmpty)
        }
        if items.isEmpty {
            EmptyHint(text: search.isEmpty ? "No bookmarks yet. Click ☆ in the toolbar to add one." : "No matches.")
        }
        if folders.isEmpty {
            ForEach(items) { bookmarkRow($0) }
        } else {
            ForEach(folders + [""], id: \.self) { folder in
                let inFolder = items.filter { ($0.folder ?? "") == folder }
                if !inFolder.isEmpty {
                    folderHeader(folder.isEmpty ? "Other" : folder)
                    ForEach(inFolder) { bookmarkRow($0) }
                }
            }
        }
    }

    private func bookmarkRow(_ bookmark: Bookmark) -> some View {
        SidebarRow(title: bookmark.title, url: bookmark.url, detail: bookmarkDetail(bookmark)) {
            store.open(bookmark.url)
        }
        .contextMenu {
            Button("Open in New Tab") { store.open(bookmark.url, inNewTab: true) }
            Menu("Move to Folder") {
                ForEach(store.bookmarkFolders, id: \.self) { folder in
                    Button(folder) { store.move(bookmark, toFolder: folder) }
                        .disabled(bookmark.folder == folder)
                }
                if bookmark.folder != nil {
                    Divider()
                    Button("Remove from Folder") { store.move(bookmark, toFolder: nil) }
                }
            }
            .disabled(store.bookmarkFolders.isEmpty)
            Button("Delete Bookmark", role: .destructive) { store.removeBookmark(bookmark) }
        }
    }

    private func bookmarkDetail(_ bookmark: Bookmark) -> String {
        let site = BrowserStore.siteName(bookmark.url)
        guard let tags = bookmark.tags, !tags.isEmpty else { return site }
        return site + " · " + tags.joined(separator: ", ")
    }

    private func folderHeader(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Nightglass.mutedText)
            .textCase(.uppercase)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .padding(.horizontal, 8)
    }

    private func organizeButton(hasFolders: Bool) -> some View {
        Button { store.organizeBookmarks() } label: {
            HStack(spacing: 6) {
                if store.isOrganizingBookmarks {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "sparkle")
                }
                Text(store.isOrganizingBookmarks ? "Claude is sorting…" : (hasFolders ? "Re-sort with Claude" : "Organize with Claude"))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Nightglass.claude)
        }
        .buttonStyle(.plain)
        .disabled(store.isOrganizingBookmarks)
        .help("Claude sorts your bookmarks into folders using only their titles and addresses")
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private func matches(_ bookmark: Bookmark) -> Bool {
        matches(bookmark.title, bookmark.url)
            || (bookmark.folder ?? "").localizedCaseInsensitiveContains(search)
            || (bookmark.tags ?? []).contains { $0.localizedCaseInsensitiveContains(search) }
    }

    // MARK: Safari

    @ViewBuilder
    private var safariList: some View {
        let safari = store.safariBookmarks
        switch safari.status {
        case .needsAccess:
            VStack(alignment: .leading, spacing: 10) {
                Text("Vela needs Full Disk Access to read Safari's bookmarks. macOS protects Safari's folder, and Vela only ever reads it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Nightglass.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("In System Settings, turn on Vela under Full Disk Access (use + to add it if it isn't listed), then come back here.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Full Disk Access Settings") { safari.openFullDiskAccessSettings() }
                    .controlSize(.small)
                Button("Check Again") { safari.reload(force: true) }
                    .controlSize(.small)
            }
            .padding(8)
        case .notFound:
            EmptyHint(text: "No Safari bookmarks were found on this Mac.")
        case .loaded:
            Button {
                importedCount = store.importSafariBookmarks()
            } label: {
                Label(importLabel, systemImage: importedCount == nil ? "square.and.arrow.down" : "checkmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Nightglass.accent)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            ForEach(safari.folders) { folder in
                let items = folder.bookmarks.filter { matches($0.title, $0.url) }
                if !items.isEmpty {
                    Text(folder.path)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Nightglass.mutedText)
                        .textCase(.uppercase)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                        .padding(.horizontal, 8)
                    ForEach(items) { bookmark in
                        SidebarRow(title: bookmark.title, url: bookmark.url, detail: BrowserStore.siteName(bookmark.url)) {
                            store.open(bookmark.url)
                        }
                        .contextMenu {
                            Button("Open in New Tab") { store.open(bookmark.url, inNewTab: true) }
                        }
                    }
                }
            }
        }
    }

    @State private var importedCount: Int?

    private var importLabel: String {
        guard let importedCount else { return "Copy All into Vela Bookmarks" }
        return importedCount == 0 ? "Already in Vela" : "Copied \(importedCount) bookmarks"
    }

    // MARK: History

    @ViewBuilder
    private var historyList: some View {
        let items = store.history.filter { matches($0.title, $0.url) }
        if items.isEmpty {
            EmptyHint(text: search.isEmpty ? "Pages you visit will show up here. Private tabs are never saved." : "No matches.")
        }
        ForEach(daySections(items), id: \.day) { section in
            Text(dayTitle(section.day))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Nightglass.mutedText)
                .textCase(.uppercase)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .padding(.horizontal, 8)
            ForEach(section.entries) { entry in
                SidebarRow(
                    title: entry.title,
                    url: entry.url,
                    detail: entry.date.formatted(date: .omitted, time: .shortened)
                ) {
                    store.open(entry.url)
                }
                .contextMenu {
                    Button("Open in New Tab") { store.open(entry.url, inNewTab: true) }
                    Button("Remove from History", role: .destructive) { store.removeHistoryEntry(entry) }
                }
            }
        }
    }

    private func matches(_ title: String, _ url: URL) -> Bool {
        search.isEmpty
            || title.localizedCaseInsensitiveContains(search)
            || url.absoluteString.localizedCaseInsensitiveContains(search)
    }

    private struct DaySection {
        let day: Date
        let entries: [HistoryEntry]
    }

    private func daySections(_ entries: [HistoryEntry]) -> [DaySection] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { DaySection(day: $0, entries: byDay[$0] ?? []) }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .complete, time: .omitted)
    }
}

/// One clickable bookmark or history row.
private struct SidebarRow: View {
    let title: String
    let url: URL
    let detail: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                FaviconView(url: url, size: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Nightglass.text)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Nightglass.mutedText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(url.absoluteString)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct EmptyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Nightglass.mutedText)
            .padding(8)
    }
}
