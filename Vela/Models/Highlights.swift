import Foundation

/// A passage you highlighted on a page, with an optional note. Saved only on
/// your Mac, and put back whenever you open the page again.
struct Highlight: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    /// A little of the text around it, to find the right spot again.
    var prefix: String
    var suffix: String
    var note: String = ""
    var date = Date()
}

/// The highlights for one page.
struct HighlightedPage: Codable, Identifiable, Equatable {
    var id: String { address }
    var address: String
    var title: String
    var highlights: [Highlight]
}

@MainActor
@Observable
final class HighlightStore {
    private(set) var pages: [HighlightedPage] = []

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vela", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("highlights.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode([HighlightedPage].self, from: data) {
            pages = saved
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pages) { try? data.write(to: Self.fileURL, options: .atomic) }
    }

    /// The page address without its "#section" part.
    static func key(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.string ?? url.absoluteString
    }

    func highlights(for url: URL) -> [Highlight] {
        pages.first { $0.address == Self.key(for: url) }?.highlights ?? []
    }

    func add(_ highlight: Highlight, url: URL, title: String) {
        let key = Self.key(for: url)
        if let index = pages.firstIndex(where: { $0.address == key }) {
            pages[index].highlights.append(highlight)
            pages[index].title = title
        } else {
            pages.insert(HighlightedPage(address: key, title: title, highlights: [highlight]), at: 0)
        }
        save()
    }

    func setNote(_ note: String, for id: UUID) {
        for page in pages.indices {
            if let index = pages[page].highlights.firstIndex(where: { $0.id == id }) {
                pages[page].highlights[index].note = note
            }
        }
        save()
    }

    func remove(_ id: UUID) {
        for page in pages.indices { pages[page].highlights.removeAll { $0.id == id } }
        pages.removeAll { $0.highlights.isEmpty }
        save()
    }

    func highlight(_ id: UUID) -> Highlight? {
        pages.lazy.flatMap(\.highlights).first { $0.id == id }
    }
}

enum HighlightScripts {
    /// Finds `text` on the page (using the words around it) and marks it.
    static let functions = """
    function velaFull() {
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      const nodes = []; let full = ''; let node;
      while ((node = walker.nextNode())) { nodes.push({ node, start: full.length }); full += node.data; }
      return { nodes, full };
    }
    function velaWrap(nodes, start, end, id, note) {
      for (const item of nodes) {
        const nodeEnd = item.start + item.node.data.length;
        if (nodeEnd <= start || item.start >= end) continue;
        if (item.node.parentElement && item.node.parentElement.closest('script,style,noscript,textarea')) continue;
        let target = item.node;
        const from = Math.max(0, start - item.start);
        const to = Math.min(target.data.length, end - item.start);
        if (from > 0) target = target.splitText(from);
        if (to - from < target.data.length) target.splitText(to - from);
        if (!target.data.trim()) continue;
        const mark = document.createElement('mark');
        mark.dataset.velaHl = id;
        mark.style.cssText = 'background: rgba(255, 214, 92, 0.55); color: inherit; border-radius: 2px; padding: 0;';
        if (note) mark.title = note;
        target.parentNode.insertBefore(mark, target);
        mark.appendChild(target);
      }
    }
    """

    /// Marks what you selected and returns it, with a little text on each side.
    static let create = functions + """
    const selection = window.getSelection();
    if (!selection || selection.isCollapsed || !document.body) return null;
    const range = selection.getRangeAt(0);
    const before = document.createRange();
    before.setStart(document.body, 0);
    before.setEnd(range.startContainer, range.startOffset);
    const start = before.toString().length;
    const text = range.toString();
    if (!text.trim()) return null;
    const { nodes, full } = velaFull();
    const end = start + text.length;
    velaWrap(nodes, start, end, id, '');
    selection.removeAllRanges();
    return { text, prefix: full.slice(Math.max(0, start - 32), start), suffix: full.slice(end, end + 32) };
    """

    /// Puts saved highlights back on the page.
    static let restore = functions + """
    for (const h of highlights) {
      if (document.querySelector('mark[data-vela-hl="' + h.id + '"]')) continue;
      const { nodes, full } = velaFull();
      let start = full.indexOf(h.prefix + h.text + h.suffix);
      if (start >= 0) start += h.prefix.length; else start = full.indexOf(h.text);
      if (start < 0) continue;
      velaWrap(nodes, start, start + h.text.length, h.id, h.note);
    }
    return true;
    """

    static let remove = """
    document.querySelectorAll('mark[data-vela-hl="' + id + '"]').forEach(mark => mark.replaceWith(...mark.childNodes));
    return true;
    """

    static let setNote = """
    document.querySelectorAll('mark[data-vela-hl="' + id + '"]').forEach(mark => { mark.title = note; });
    return true;
    """
}

extension BrowserStore {
    /// Right-click ▸ Highlight (or Highlight with Note…).
    func highlightSelection(in tab: BrowserTab, withNote: Bool) {
        guard !tab.isPrivate else {
            showNotice("Highlights aren't saved in private tabs")
            return
        }
        guard let url = tab.url else { return }
        let id = UUID()
        Task {
            guard let result = try? await tab.runScript(HighlightScripts.create, arguments: ["id": id.uuidString]) as? [String: Any],
                  let text = result["text"] as? String else {
                showNotice("Select some text to highlight first")
                return
            }
            let highlight = Highlight(id: id, text: text, prefix: result["prefix"] as? String ?? "",
                                      suffix: result["suffix"] as? String ?? "")
            highlights.add(highlight, url: url, title: tab.title)
            if withNote { editingHighlightID = id }
        }
    }

    /// After a page loads: put its highlights back.
    func restoreHighlights(in tab: BrowserTab) {
        guard !tab.isPrivate, let url = tab.url else { return }
        let saved = highlights.highlights(for: url)
        guard !saved.isEmpty else { return }
        let list = saved.map { ["id": $0.id.uuidString, "text": $0.text, "prefix": $0.prefix, "suffix": $0.suffix, "note": $0.note] }
        Task { _ = try? await tab.runScript(HighlightScripts.restore, arguments: ["highlights": list]) }
    }

    func setHighlightNote(_ note: String, for id: UUID) {
        highlights.setNote(note, for: id)
        for tab in tabs where !tab.isPrivate {
            Task { _ = try? await tab.runScript(HighlightScripts.setNote, arguments: ["id": id.uuidString, "note": note]) }
        }
    }

    func removeHighlight(_ id: UUID) {
        highlights.remove(id)
        for tab in tabs where !tab.isPrivate {
            Task { _ = try? await tab.runScript(HighlightScripts.remove, arguments: ["id": id.uuidString]) }
        }
    }
}
