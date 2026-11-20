import Foundation

/// The words on one page you've read, kept so you can find it again.
struct RememberedPage: Codable, Identifiable, Equatable {
    var id: URL { url }
    var url: URL
    var title: String
    var date: Date
    /// The start of the page's text (up to 4,000 characters).
    var text: String
}

/// "What was that page?": a search of what you've actually read, not just
/// page titles.
///
/// **Privacy:** the text of pages you visit is saved only on your Mac
/// (~/Library/Application Support/Vela/page-memory.json). Never saved:
/// private tabs, the Banking container, pages with password boxes, and pages
/// on sites where the shield is off. When you ask a question, Vela finds the
/// best matches on your Mac first, then sends Claude only your question and
/// short excerpts of those few pages.
@MainActor
@Observable
final class PageMemory {
    private(set) var pages: [RememberedPage] = []
    var isEnabled = UserDefaults.standard.object(forKey: "vela.pageMemory") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "vela.pageMemory")
            if !isEnabled { clear() }
        }
    }

    private static let limit = 1_500
    private static let textLimit = 4_000
    @ObservationIgnored private var isDirty = false

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vela", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("page-memory.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode([RememberedPage].self, from: data) {
            pages = saved
        }
    }

    func remember(url: URL, title: String, text: String) {
        guard isEnabled else { return }
        let cleaned = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard cleaned.count >= 80 else { return }
        pages.removeAll { $0.url == url }
        pages.insert(RememberedPage(url: url, title: title, date: Date(), text: String(cleaned.prefix(Self.textLimit))), at: 0)
        if pages.count > Self.limit { pages.removeLast(pages.count - Self.limit) }
        isDirty = true
    }

    func save() {
        guard isDirty else { return }
        isDirty = false
        if let data = try? JSONEncoder().encode(pages) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    func clear() {
        pages = []
        isDirty = true
        save()
    }

    // MARK: Searching (all on your Mac)

    private static let ignoredWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "was", "were", "what", "which", "where", "when", "who",
        "about", "from", "page", "site", "website", "article", "saw", "seen", "read", "looked", "find", "some",
        "there", "had", "have", "has", "one", "thing", "something", "that's", "i've", "you", "your", "my", "me",
        "last", "week", "today", "yesterday", "ago", "day", "days", "remember", "again", "think", "its", "it's",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "earlier", "recently",
    ]

    /// The days a question points at ("yesterday", "on Tuesday", "last week"), if any.
    static func dateRange(in question: String, now: Date = Date()) -> ClosedRange<Date>? {
        let calendar = Calendar.current
        let text = question.lowercased()
        let today = calendar.startOfDay(for: now)
        func days(_ start: Int, _ end: Int) -> ClosedRange<Date>? {
            guard let from = calendar.date(byAdding: .day, value: -start, to: today),
                  let to = calendar.date(byAdding: .day, value: -end + 1, to: today) else { return nil }
            return from...to
        }
        if text.contains("today") { return days(0, 0) }
        if text.contains("yesterday") { return days(1, 1) }
        if text.contains("last week") || text.contains("this week") || text.contains("past week") { return days(7, 0) }
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        if let index = names.firstIndex(where: { text.contains($0) }) {
            let weekdayToday = calendar.component(.weekday, from: now) - 1
            var back = (weekdayToday - index + 7) % 7
            if back == 0 { back = 7 }
            return days(back, back)
        }
        return nil
    }

    static func words(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !ignoredWords.contains($0) }
    }

    /// The best-matching pages for a question, best first.
    func search(_ question: String, limit: Int = 8) -> [RememberedPage] {
        let terms = Array(Set(Self.words(in: question)))
        let range = Self.dateRange(in: question)
        let candidates = range.map { range in pages.filter { range.contains($0.date) } } ?? pages
        if terms.isEmpty { return Array(candidates.prefix(limit)) }

        var scored: [(RememberedPage, Double)] = []
        for (position, page) in candidates.enumerated() {
            let title = page.title.lowercased()
            let body = page.text.lowercased()
            let address = page.url.absoluteString.lowercased()
            var score = 0.0
            var matched = 0
            for term in terms {
                var hit = false
                if title.contains(term) { score += 5; hit = true }
                if address.contains(term) { score += 3; hit = true }
                let count = body.components(separatedBy: term).count - 1
                if count > 0 { score += min(Double(count), 5); hit = true }
                if hit { matched += 1 }
            }
            guard matched > 0 else { continue }
            // Pages matching more of your words win; newer pages break ties.
            score *= Double(matched) / Double(terms.count)
            score += 0.5 / Double(position + 1)
            scored.append((page, score))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// About 600 characters of the page around the first word you asked about.
    static func excerpt(of page: RememberedPage, for question: String) -> String {
        let lower = page.text.lowercased()
        let terms = words(in: question)
        let start: String.Index = terms.lazy.compactMap { lower.range(of: $0)?.lowerBound }.first ?? lower.startIndex
        let offset = max(0, lower.distance(from: lower.startIndex, to: start) - 150)
        let begin = page.text.index(page.text.startIndex, offsetBy: min(offset, page.text.count))
        return String(page.text[begin...].prefix(600))
    }
}

extension BrowserStore {
    /// After a page finishes loading: remember its words (see PageMemory).
    func rememberPage(in tab: BrowserTab) {
        guard pageMemory.isEnabled, !tab.isPrivate, shieldsUp(for: tab),
              container(for: tab)?.name.lowercased() != "banking",
              let url = tab.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        Task {
            let script = """
            if (document.querySelector('input[type=password]')) return null;
            return (document.body ? document.body.innerText : '').slice(0, 12000);
            """
            guard let text = try? await tab.runScript(script, arguments: [:]) as? String,
                  tab.url == url else { return }
            pageMemory.remember(url: url, title: tab.title, text: text)
        }
    }
}
