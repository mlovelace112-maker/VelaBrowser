import Foundation

/// Smart bookmarks: Claude sorts your bookmarks into folders and adds a few
/// tags so search finds them. Claude sees only bookmark titles and
/// addresses, never the pages. Once you've organized them, each new
/// bookmark is filed into a folder as you save it.
extension BrowserStore {
    private struct Filing: Decodable {
        struct Item: Decodable {
            var n: Int
            var folder: String
            var tags: [String]?
        }
        var bookmarks: [Item]
    }

    /// Folder names in use, in alphabetical order.
    var bookmarkFolders: [String] {
        Array(Set(bookmarks.compactMap(\.folder))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Bookmarks ▸ Organize with Claude: files every bookmark into a folder.
    func organizeBookmarks() {
        guard claude.hasKey else {
            showNotice("Add your Claude API key in Settings ▸ Claude first")
            return
        }
        guard bookmarks.count >= 3, !isOrganizingBookmarks else { return }
        isOrganizingBookmarks = true
        let batch = Array(bookmarks.prefix(400))
        Task {
            defer { isOrganizingBookmarks = false }
            do {
                let filing = try await askForFolders(batch, existing: bookmarkFolders, maxFolders: 12)
                apply(filing, to: batch)
                showNotice("Claude sorted your bookmarks into \(bookmarkFolders.count) folders")
            } catch {
                showNotice(error.localizedDescription)
            }
        }
    }

    /// Files a bookmark you just saved, once your bookmarks have folders.
    func fileNewBookmark(_ bookmark: Bookmark) {
        guard claude.hasKey, !bookmarkFolders.isEmpty else { return }
        let folders = bookmarkFolders
        Task {
            guard let filing = try? await askForFolders([bookmark], existing: folders, maxFolders: folders.count + 1) else { return }
            apply(filing, to: [bookmark])
            if let folder = bookmarks.first(where: { $0.id == bookmark.id })?.folder {
                showNotice("Bookmarked in \(folder)")
            }
        }
    }

    func move(_ bookmark: Bookmark, toFolder folder: String?) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index].folder = folder
        saveBookmarks()
    }

    private func askForFolders(_ items: [Bookmark], existing: [String], maxFolders: Int) async throws -> Filing {
        let listing = items.enumerated().map { index, bookmark in
            "\(index + 1). \(bookmark.title) — \(bookmark.url.absoluteString)"
        }.joined(separator: "\n")
        let folders = existing.isEmpty ? "There are no folders yet." : "Existing folders: \(existing.joined(separator: ", "))."
        let system = """
        You organize someone's browser bookmarks into folders. \(folders) Prefer existing folders; make a \
        new one only when nothing fits, with at most \(maxFolders) folders in all. Folder names are 1 to 3 \
        words in title case, like "Recipes", "Work", "Shopping", "News". Give each bookmark 1 to 3 short \
        lowercase tags. Return: {"bookmarks": [{"n": 1, "folder": "Recipes", "tags": ["dinner"]}]}, one \
        entry per bookmark, using its number.
        """
        return try await Self.askClaudeForJSON(Filing.self, system: system, prompt: listing,
                                               maxTokens: min(16_000, 400 + items.count * 40))
    }

    private func apply(_ filing: Filing, to items: [Bookmark]) {
        for entry in filing.bookmarks where items.indices.contains(entry.n - 1) {
            let id = items[entry.n - 1].id
            guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { continue }
            let folder = entry.folder.trimmingCharacters(in: .whitespacesAndNewlines)
            bookmarks[index].folder = folder.isEmpty ? nil : String(folder.prefix(40))
            bookmarks[index].tags = entry.tags.map { Array($0.prefix(3)) }
        }
        saveBookmarks()
    }
}
