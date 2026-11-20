import Foundation

/// A saved page. `Codable` lets us turn a list of bookmarks into JSON
/// and save it on disk, then read it back the next time Vela opens.
struct Bookmark: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: URL
    /// The folder Claude (or you) filed it in. Optional, so bookmarks saved
    /// before folders existed still load.
    var folder: String?
    /// A few words that help search find it ("dinner", "taxes").
    var tags: [String]?
}
