import Foundation

/// Smart bookmarks: Claude sorts your bookmarks into folders and adds a few
/// tags so search finds them. Claude sees only bookmark titles and
/// addresses, never the pages. Once you've organized them, each new
/// bookmark is filed into a folder as you save it.
extension BrowserStore {
    /// One bookmark's place, as Claude sent it back.
    private struct Filing {
        var number: Int
        var folder: String
        var tags: [String]
    }

    /// How many bookmarks go to Claude in one request. Small batches keep
    /// each answer short, so it can't be cut off part-way.
    private static let batchSize = 60

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
        guard !isOrganizingBookmarks else { return }
        guard bookmarks.count >= 3 else {
            let hint = safariBookmarks.allBookmarks.isEmpty
                ? "Add a few more bookmarks first."
                : "Your Safari bookmarks aren't Vela's own yet: open the Bookmarks sidebar ▸ Safari ▸ Copy All into Vela Bookmarks, then try again."
            showNotice("Vela has only \(bookmarks.count) bookmark\(bookmarks.count == 1 ? "" : "s"). \(hint)")
            return
        }
        isOrganizingBookmarks = true
        let all = bookmarks
        showNotice("Claude is sorting \(all.count) bookmarks…")
        Task {
            defer { isOrganizingBookmarks = false }
            var filed = 0
            var failure: Error?
            for start in stride(from: 0, to: all.count, by: Self.batchSize) {
                let batch = Array(all[start..<min(start + Self.batchSize, all.count)])
                do {
                    // Each batch sees the folders made so far, so they stay consistent.
                    let filings = try await askForFolders(batch, existing: bookmarkFolders, maxFolders: 12)
                    filed += apply(filings, to: batch)
                } catch {
                    failure = error
                    break
                }
            }
            if filed > 0 {
                let rest = failure.map { " Some were left as they were: \($0.localizedDescription)" } ?? ""
                showNotice("Claude sorted \(filed) bookmarks into \(bookmarkFolders.count) folders.\(rest)")
            } else {
                showNotice(failure?.localizedDescription ?? "Claude couldn't sort these bookmarks. Try again.")
            }
        }
    }

    /// Files a bookmark you just saved, once your bookmarks have folders.
    func fileNewBookmark(_ bookmark: Bookmark) {
        guard claude.hasKey, !bookmarkFolders.isEmpty else { return }
        let folders = bookmarkFolders
        Task {
            guard let filings = try? await askForFolders([bookmark], existing: folders, maxFolders: folders.count + 1),
                  apply(filings, to: [bookmark]) > 0,
                  let folder = bookmarks.first(where: { $0.id == bookmark.id })?.folder else { return }
            showNotice("Bookmarked in \(folder)")
        }
    }

    func move(_ bookmark: Bookmark, toFolder folder: String?) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index].folder = folder
        saveBookmarks()
    }

    private func askForFolders(_ items: [Bookmark], existing: [String], maxFolders: Int) async throws -> [Filing] {
        let listing = items.enumerated().map { index, bookmark in
            let title = bookmark.title.isEmpty ? Self.siteName(bookmark.url) : bookmark.title
            return "\(index + 1). \(title.prefix(120)) — \(bookmark.url.absoluteString.prefix(200))"
        }.joined(separator: "\n")
        let folders = existing.isEmpty ? "There are no folders yet." : "Existing folders: \(existing.joined(separator: ", "))."
        let request = ClaudeRequest(
            model: .haiku,
            system: """
            You organize someone's browser bookmarks into folders. \(folders) Prefer existing folders; make a \
            new one only when nothing fits, with at most \(maxFolders) folders in all. Folder names are 1 to 3 \
            words in title case, like "Recipes", "Work", "Shopping", "News". Give each bookmark 1 to 3 short \
            lowercase tags. Reply with JSON only, no other text: {"bookmarks": [{"n": 1, "folder": "Recipes", \
            "tags": ["dinner"]}]}, one entry per bookmark, using its number.
            """,
            messages: [["role": "user", "content": listing]],
            // Generous on purpose: only what Claude writes is billed, and a
            // tight limit can cut the answer off before the JSON ends.
            maxTokens: 16_000,
            effort: "low"
        )
        let response = try await ClaudeClient.stream(request) { _ in }
        if response.stopReason == "refusal" { throw PageToolError.message("Claude declined to sort these bookmarks.") }
        let filings = Self.parseFilings(response.text)
        guard !filings.isEmpty else {
            throw PageToolError.message(response.stopReason == "max_tokens"
                ? "Claude's answer was cut off. Try again."
                : "Claude's answer didn't come back in the expected shape. Try again.")
        }
        return filings
    }

    /// Reads Claude's reply loosely: numbers may come as text, and a bad entry
    /// is skipped instead of spoiling the rest.
    private static func parseFilings(_ text: String) -> [Filing] {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let json = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any],
              let entries = json["bookmarks"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            let number = (entry["n"] as? Int) ?? Int(entry["n"] as? String ?? "")
            guard let number, let folder = entry["folder"] as? String,
                  !folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let tags = (entry["tags"] as? [Any] ?? []).compactMap { $0 as? String }
            return Filing(number: number, folder: folder, tags: tags)
        }
    }

    /// Puts Claude's folders and tags on the bookmarks. Returns how many were filed.
    @discardableResult
    private func apply(_ filings: [Filing], to items: [Bookmark]) -> Int {
        var count = 0
        for filing in filings where items.indices.contains(filing.number - 1) {
            let id = items[filing.number - 1].id
            guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { continue }
            let folder = filing.folder.trimmingCharacters(in: .whitespacesAndNewlines)
            bookmarks[index].folder = String(folder.prefix(40))
            bookmarks[index].tags = filing.tags.isEmpty ? nil : Array(filing.tags.prefix(3))
            count += 1
        }
        if count > 0 { saveBookmarks() }
        return count
    }
}
