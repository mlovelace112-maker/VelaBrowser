import AppKit
import CoreGraphics
import Foundation

/// One day of browsing, counted on your Mac.
struct ActivityDay: Codable, Equatable {
    /// Seconds you actively spent on each site ("youtube.com": 1830).
    var siteSeconds: [String: Double] = [:]
    /// What you searched for, and how many times.
    var searches: [String: Int] = [:]
    var pagesVisited = 0
    var trackersBlocked = 0
    var popupsBlocked = 0

    var totalSeconds: Double { siteSeconds.values.reduce(0, +) }
}

/// The activity report's numbers: which sites you used and for how long,
/// what you searched for, and what the shield blocked.
///
/// **Privacy:** everything is counted and stored only on your Mac, in
/// ~/Library/Application Support/Vela/activity.json. Private tabs are never
/// counted. Time only counts while Vela is in front, you're on that tab, and
/// you've used the mouse or keyboard in the last 2 minutes (or a video is
/// playing). Nothing is sent anywhere unless you click "Write my summary",
/// which sends Claude the totals shown in the report.
@MainActor
@Observable
final class ActivityLog {
    /// "2026-11-20" → that day's numbers. Kept for 60 days.
    private(set) var days: [String: ActivityDay] = [:]
    var isEnabled = UserDefaults.standard.object(forKey: "vela.activityEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "vela.activityEnabled") }
    }

    /// How often time is counted.
    static let tick: TimeInterval = 5
    /// No mouse or keyboard for this long means you've stepped away.
    static let idleLimit: TimeInterval = 120
    private static let keepDays = 60

    @ObservationIgnored private var isDirty = false

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vela", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("activity.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode([String: ActivityDay].self, from: data) {
            days = saved
        }
    }

    static func key(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func day(_ date: Date) -> ActivityDay {
        days[Self.key(for: date)] ?? ActivityDay()
    }

    private func update(_ change: (inout ActivityDay) -> Void) {
        guard isEnabled else { return }
        let key = Self.key(for: Date())
        var today = days[key] ?? ActivityDay()
        change(&today)
        days[key] = today
        isDirty = true
    }

    /// Adds time to a site (called every few seconds while you browse).
    func addTime(_ seconds: Double, to site: String) {
        update { $0.siteSeconds[site, default: 0] += seconds }
    }

    /// Counts a page visit, and the search if it was a search results page.
    func recordPage(_ url: URL) {
        update { day in
            day.pagesVisited += 1
            if let query = Self.searchQuery(in: url) {
                day.searches[query, default: 0] += 1
            }
        }
    }

    func recordTrackerBlocked() { update { $0.trackersBlocked += 1 } }
    func recordPopupBlocked() { update { $0.popupsBlocked += 1 } }

    /// The words you searched for on DuckDuckGo, Google or Bing.
    static func searchQuery(in url: URL) -> String? {
        guard let host = url.host()?.lowercased(),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let isSearch = host.hasSuffix("duckduckgo.com")
            || ((host.hasPrefix("www.google.") || host.hasPrefix("google.")) && url.path().hasPrefix("/search"))
            || (host.hasSuffix("bing.com") && url.path().hasPrefix("/search"))
        guard isSearch, let query = items.first(where: { $0.name == "q" })?.value else { return nil }
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty, cleaned.count <= 200 else { return nil }
        return cleaned
    }

    /// Seconds since you last touched the mouse or keyboard.
    static var secondsSinceInput: TimeInterval {
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// Writes to disk if anything changed (every minute, and when Vela quits).
    func save() {
        guard isDirty else { return }
        isDirty = false
        let cutoff = Self.key(for: Date().addingTimeInterval(-Double(Self.keepDays) * 86_400))
        days = days.filter { $0.key >= cutoff }
        if let data = try? JSONEncoder().encode(days) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    func clear() {
        days = [:]
        isDirty = true
        save()
    }
}

struct DayMinutes { let date: Date; let minutes: Double }
struct SiteMinutes { let site: String; let minutes: Double }
struct SearchCount { let query: String; let count: Int }

/// A week (or any run of days) added up, for the report.
struct ActivitySummary {
    var dates: [Date]
    var minutesByDay: [DayMinutes]
    var topSites: [SiteMinutes]
    var topSearches: [SearchCount]
    var totalMinutes: Double
    var pagesVisited: Int
    var trackersBlocked: Int
    var popupsBlocked: Int
    var activeDays: Int

    @MainActor init(log: ActivityLog, endingOn end: Date = Date(), days count: Int = 7) {
        let calendar = Calendar.current
        let lastDay = calendar.startOfDay(for: end)
        dates = (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: lastDay) }
        var sites: [String: Double] = [:]
        var searches: [String: Int] = [:]
        var byDay: [(Date, Double)] = []
        var pages = 0, trackers = 0, popups = 0, active = 0
        for date in dates {
            let day = log.day(date)
            byDay.append((date, day.totalSeconds / 60))
            if day.totalSeconds > 60 { active += 1 }
            for (site, seconds) in day.siteSeconds { sites[site, default: 0] += seconds }
            for (query, times) in day.searches { searches[query, default: 0] += times }
            pages += day.pagesVisited
            trackers += day.trackersBlocked
            popups += day.popupsBlocked
        }
        minutesByDay = byDay.map { DayMinutes(date: $0.0, minutes: $0.1) }
        topSites = sites.sorted { $0.value > $1.value }.prefix(8).map { SiteMinutes(site: $0.key, minutes: $0.value / 60) }
        topSearches = searches.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(10).map { SearchCount(query: $0.key, count: $0.value) }
        totalMinutes = byDay.reduce(0) { $0 + $1.1 }
        pagesVisited = pages
        trackersBlocked = trackers
        popupsBlocked = popups
        activeDays = active
    }

    static func format(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total) min" }
        return total % 60 == 0 ? "\(total / 60) h" : "\(total / 60) h \(total % 60) min"
    }

    /// What Claude gets for "Write my summary": totals only, no page addresses.
    func promptText() -> String {
        var lines = ["Time online in the last 7 days: \(Self.format(minutes: totalMinutes)) over \(activeDays) days."]
        lines.append("Per day: " + minutesByDay.map {
            "\($0.date.formatted(.dateTime.weekday(.abbreviated))) \(Self.format(minutes: $0.minutes))"
        }.joined(separator: ", "))
        lines.append("Top sites by time: " + topSites.map { "\($0.site) \(Self.format(minutes: $0.minutes))" }.joined(separator: "; "))
        if !topSearches.isEmpty {
            lines.append("Top searches: " + topSearches.map { "\"\($0.query)\" ×\($0.count)" }.joined(separator: "; "))
        }
        lines.append("Pages visited: \(pagesVisited). Trackers blocked: \(trackersBlocked). Pop-ups blocked: \(popupsBlocked).")
        return lines.joined(separator: "\n")
    }
}

extension BrowserStore {
    /// Every few seconds: give the time to the site you're looking at.
    func startActivityClock() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(ActivityLog.tick))
                guard let self else { return }
                self.countActiveTime()
            }
        }
    }

    private func countActiveTime() {
        guard activity.isEnabled, NSApp.isActive, NSApp.keyWindow != nil,
              let tab = selectedTab, !tab.isPrivate, tab.focusBlocked == nil,
              let url = tab.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        guard ActivityLog.secondsSinceInput < ActivityLog.idleLimit || tab.isPlayingAudio else { return }
        activity.addTime(ActivityLog.tick, to: BrowserStore.siteName(url))
        play.addBrowsingTime(ActivityLog.tick, site: BrowserStore.siteName(url))
    }

    /// Mondays (or the first launch after one): point at the new report once.
    func announceWeeklyReportIfDue() {
        let key = "vela.lastReportNotice"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard activity.isEnabled, Date().timeIntervalSince(last) > 6.5 * 86_400,
              ActivitySummary(log: activity).totalMinutes >= 30 else { return }
        UserDefaults.standard.set(Date(), forKey: key)
        showNotice("Your weekly report is ready: History ▸ Weekly Report (⌥⌘R)")
    }
}
