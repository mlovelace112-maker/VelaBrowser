import SwiftUI

/// The left sidebar (⇧⌘L) with your Bookmarks and History, like Safari's.
struct SidebarView: View {
    @Environment(BrowserStore.self) private var store
    @State private var search = ""

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 12) {
            Picker("Section", selection: $store.sidebarSection) {
                ForEach(SidebarSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.symbol).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

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
        .background(VisualEffectBackground(material: .sidebar))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Nightglass.stroke).frame(width: 1)
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
        let items = store.bookmarks.filter { matches($0.title, $0.url) }
        if items.isEmpty {
            EmptyHint(text: search.isEmpty ? "No bookmarks yet. Click ☆ in the toolbar to add one." : "No matches.")
        }
        ForEach(items) { bookmark in
            SidebarRow(title: bookmark.title, url: bookmark.url, detail: BrowserStore.siteName(bookmark.url)) {
                store.open(bookmark.url)
            }
            .contextMenu {
                Button("Open in New Tab") { store.open(bookmark.url, inNewTab: true) }
                Button("Delete Bookmark", role: .destructive) { store.removeBookmark(bookmark) }
            }
        }
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
