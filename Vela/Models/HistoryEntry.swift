import Foundation

/// One visit to a page, shown in History (⌘Y).
struct HistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: URL
    var date: Date
}

/// Remembers a closed tab so ⇧⌘T can bring it back.
struct ClosedTab {
    let url: URL
    let groupID: UUID?
    let isPrivate: Bool
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case bookmarks = "Bookmarks"
    case history = "History"

    var id: String { rawValue }
    var symbol: String { self == .bookmarks ? "book" : "clock" }
}
