import Foundation
import SwiftUI

/// A tab Vela tidied away because you hadn't opened it in a while.
struct ArchivedTab: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: URL
    /// When it was archived.
    var date: Date
    var containerID: UUID?
}

/// Tab tidy-up: tabs you haven't opened for a few days close by themselves
/// and wait in Tabs ▸ Archived Tabs (and in the ⌘K command bar), so the tab
/// strip stays short without losing anything.
///
/// Never archived: the tab you're on, pinned tabs, private tabs, tabs in
/// split view, and tabs playing sound or using the camera or microphone.
extension BrowserStore {
    private static let archiveKey = "vela.archivedTabs"
    /// How many archived tabs Vela keeps (oldest are forgotten).
    private static let archiveLimit = 300

    static func loadArchivedTabs() -> [ArchivedTab] {
        guard let data = UserDefaults.standard.data(forKey: archiveKey),
              let items = try? JSONDecoder().decode([ArchivedTab].self, from: data) else { return [] }
        return items
    }

    private func saveArchivedTabs() {
        if let data = try? JSONEncoder().encode(archivedTabs) {
            UserDefaults.standard.set(data, forKey: Self.archiveKey)
        }
    }

    /// Runs every minute (with tab sleeping).
    func archiveIdleTabs() {
        guard archiveAfterDays > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(archiveAfterDays) * 86_400)
        let idle = tabs.filter { tab in
            tab.id != selectedTabID && !tab.isPinned && !tab.isPrivate && tab.mediaSearch == nil
                && tab.lastActive < cutoff && splitPair?.contains(tab.id) != true
                && !tab.isPlayingAudio && !tab.isUsingCamera && !tab.isUsingMicrophone
                && ["http", "https"].contains(tab.url?.scheme?.lowercased() ?? "")
        }
        guard !idle.isEmpty else { return }
        for tab in idle { archive(tab) }
        let days = archiveAfterDays == 1 ? "a day" : "\(archiveAfterDays) days"
        showNotice(idle.count == 1
                   ? "Archived 1 tab you hadn't opened in \(days) (Tabs ▸ Archived Tabs)"
                   : "Archived \(idle.count) tabs you hadn't opened in \(days) (Tabs ▸ Archived Tabs)")
    }

    /// Closes a tab and keeps it in Archived Tabs.
    func archive(_ tab: BrowserTab) {
        if let url = tab.url, !tab.isPrivate {
            archivedTabs.removeAll { $0.url == url }
            archivedTabs.insert(ArchivedTab(title: tab.title, url: url, date: Date(), containerID: tab.containerID), at: 0)
            if archivedTabs.count > Self.archiveLimit { archivedTabs.removeLast(archivedTabs.count - Self.archiveLimit) }
            saveArchivedTabs()
        }
        close(tab)
    }

    /// Opens an archived tab again (in its container) and takes it off the list.
    func restore(_ item: ArchivedTab) {
        let container = containers.contains { $0.id == item.containerID } ? item.containerID : nil
        newTab(url: item.url, container: .some(container))
        archivedTabs.removeAll { $0.id == item.id }
        saveArchivedTabs()
    }

    func clearArchivedTabs() {
        archivedTabs = []
        saveArchivedTabs()
    }
}

/// Settings ▸ General ▸ Tabs: the tidy-up picker.
struct TabArchiveSetting: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Picker(selection: $store.archiveAfterDays) {
            Text("Never").tag(0)
            Text("After 1 day").tag(1)
            Text("After 3 days").tag(3)
            Text("After 7 days").tag(7)
            Text("After 30 days").tag(30)
        } label: {
            Text("Archive tabs I haven't opened")
            Text("They close and wait in Tabs ▸ Archived Tabs and the ⌘K command bar. Pinned tabs never do.")
        }
    }
}
