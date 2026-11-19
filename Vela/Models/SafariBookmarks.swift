import AppKit
import Foundation
import Observation

/// A Safari bookmarks folder, flattened: "Favorites", "Bookmarks Menu ▸ News"…
struct SafariFolder: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let bookmarks: [Bookmark]
}

/// Reads Safari's bookmarks live from ~/Library/Safari/Bookmarks.plist.
///
/// **How it works:** Safari keeps every bookmark in one property-list file:
/// folders ("WebBookmarkTypeList") hold bookmarks ("WebBookmarkTypeLeaf") and
/// more folders. Vela re-reads it whenever you switch back to Vela, so a
/// bookmark you add in Safari (or on your iPhone, through iCloud) shows up.
/// Vela only ever *reads* this file; it never changes Safari's bookmarks.
///
/// **Why Full Disk Access:** macOS protects Safari's folder. You grant Vela
/// access once in System Settings ▸ Privacy & Security ▸ Full Disk Access.
@MainActor
@Observable
final class SafariBookmarks {
    enum Status: Equatable {
        case loaded
        case needsAccess
        case notFound
    }

    private(set) var folders: [SafariFolder] = []
    private(set) var status: Status = .notFound
    @ObservationIgnored private var lastModified: Date?

    static let file = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Safari/Bookmarks.plist")
    static let fullDiskAccessSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    init() {
        reload()
    }

    var allBookmarks: [Bookmark] { folders.flatMap(\.bookmarks) }

    /// Re-reads the file if Safari changed it since last time.
    func reload(force: Bool = false) {
        let files = FileManager.default
        guard files.fileExists(atPath: Self.file.path) else {
            status = files.isReadableFile(atPath: Self.file.deletingLastPathComponent().path) ? .notFound : .needsAccess
            return
        }
        let modified = (try? files.attributesOfItem(atPath: Self.file.path))?[.modificationDate] as? Date
        if !force, status == .loaded, modified == lastModified { return }

        guard let data = try? Data(contentsOf: Self.file),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            // The file exists but can't be read: Full Disk Access hasn't been granted.
            status = .needsAccess
            folders = []
            return
        }
        var result: [SafariFolder] = []
        for child in root["Children"] as? [[String: Any]] ?? [] {
            Self.collect(child, path: [], into: &result)
        }
        folders = result.filter { !$0.bookmarks.isEmpty }
        lastModified = modified
        status = .loaded
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(Self.fullDiskAccessSettings)
    }

    private static func collect(_ node: [String: Any], path: [String], into folders: inout [SafariFolder]) {
        guard node["WebBookmarkType"] as? String == "WebBookmarkTypeList" else { return }
        let name = displayName(node["Title"] as? String ?? "Folder")
        // Skip the History entry and other built-in placeholders.
        if name == "History" || node["WebBookmarkIdentifier"] as? String == "History" { return }
        let fullPath = path + [name]
        var bookmarks: [Bookmark] = []
        var subfolders: [[String: Any]] = []

        for child in node["Children"] as? [[String: Any]] ?? [] {
            switch child["WebBookmarkType"] as? String {
            case "WebBookmarkTypeLeaf":
                guard let address = child["URLString"] as? String, let url = URL(string: address),
                      let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { continue }
                let title = (child["URIDictionary"] as? [String: Any])?["title"] as? String
                bookmarks.append(Bookmark(title: title?.isEmpty == false ? title! : BrowserStore.siteName(url), url: url))
            case "WebBookmarkTypeList":
                subfolders.append(child)
            default:
                break
            }
        }
        folders.append(SafariFolder(path: fullPath.joined(separator: " ▸ "), bookmarks: bookmarks))
        for subfolder in subfolders {
            collect(subfolder, path: fullPath, into: &folders)
        }
    }

    /// Safari's internal folder names → the names you see in Safari.
    private static func displayName(_ title: String) -> String {
        switch title {
        case "BookmarksBar": "Favorites"
        case "BookmarksMenu": "Bookmarks Menu"
        case "com.apple.ReadingList": "Reading List"
        default: title
        }
    }
}
