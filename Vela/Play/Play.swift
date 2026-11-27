import AppKit
import Foundation
import Observation
import SwiftUI

/// A moment worth celebrating: a badge, a new level, a finished challenge.
/// Shows as a banner at the top of the window with confetti.
struct Celebration: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let color: UInt32
    var confetti = true
}

/// Something for Pip (the pet in the toolbar) to react to.
struct PetEvent: Identifiable, Equatable {
    enum Kind: Equatable { case munch, cheer, wave, sleepy, worried, focus }
    let id = UUID()
    /// When it happened: Pip plays the matching move for a second or two.
    let date = Date()
    let kind: Kind
    /// What Pip says in its speech bubble (nil: just the animation).
    let line: String?
}

/// Vela's playful side: points, levels, streaks, badges, weekly challenges,
/// reading bingo, the focus planet and the celebrations that go with them.
///
/// **How it fits in:** the browser calls `record(_:)` when something worth
/// counting happens (a tracker blocked, a page opened, a focus quest
/// finished). `Play` adds the points, checks whether that earned a badge,
/// finished a challenge or reached a new level, and if so sets
/// `celebration`, which the window shows with confetti.
///
/// Everything stays on your Mac (see PlayModels.swift).
@MainActor
@Observable
final class Play {
    /// The one Play for the app. The browser store and every view share it.
    static let shared = Play()

    private(set) var state: PlayState
    var settings: PlaySettings {
        didSet { saveSettings() }
    }

    /// The banner showing right now, and the ones waiting their turn.
    private(set) var celebration: Celebration?
    @ObservationIgnored private var celebrationQueue: [Celebration] = []
    /// Bumped to fire confetti without a banner (easter eggs).
    private(set) var confettiBurst = 0
    /// The latest thing Pip should react to.
    private(set) var petEvent: PetEvent?
    @ObservationIgnored private var lastBubble = Date.distantPast
    /// A meteor shower across the window, until this time (an easter egg).
    var meteorShowerUntil: Date?
    /// The rainbow easter egg cycles the accent color until this time.
    var rainbowUntil: Date?

    // Windows
    var isHubVisible = false
    var hubSection: PlayHubSection = .overview
    var isYearInReviewVisible = false

    /// Supplied by the browser: today's privacy score, 0 to 100.
    @ObservationIgnored var privacyScore: () -> Int = { 0 }

    @ObservationIgnored private var isDirty = false
    /// Browsing seconds not yet added to the year's site totals.
    @ObservationIgnored private var pendingSeconds: [String: Double] = [:]

    var isOn: Bool { settings.isEnabled }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(PlayState.self, from: data) {
            state = saved
        } else {
            state = PlayState()
        }
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(PlaySettings.self, from: data) {
            settings = saved
        } else {
            settings = PlaySettings()
        }
    }

    // MARK: - Reading the numbers

    var level: Int { Level.level(for: state.xp) }
    var levelTitle: String { Level.title(for: level) }
    var levelProgress: Double { Level.progress(for: state.xp) }
    var xpToNextLevel: Int { Level.xpNeeded(for: level + 1) - state.xp }

    func total(_ stat: Stat) -> Int { state.totals[stat.rawValue] ?? 0 }
    func thisWeek(_ stat: Stat) -> Int { state.weeks[Self.weekKey()]?[stat.rawValue] ?? 0 }
    func thisYear(_ stat: Stat, year: String = Play.yearKey()) -> Int { state.years[year]?[stat.rawValue] ?? 0 }

    /// The streak as it stands today: it's broken if you skipped yesterday.
    var currentStreak: Int {
        guard let last = state.lastActiveDay else { return 0 }
        let today = Self.dayKey(), yesterday = Self.dayKey(Date().addingTimeInterval(-86_400))
        return last == today || last == yesterday ? state.streak : 0
    }

    var earnedBadges: [Badge] { Badge.all.filter { state.badges[$0.id] != nil } }

    // MARK: - Counting

    /// Counts something and gives its points. Does nothing when Play is off.
    func record(_ stat: Stat, by amount: Int = 1) {
        guard isOn, amount > 0 else { return }
        let before = total(stat)
        let after = before + amount
        state.totals[stat.rawValue] = after

        let week = Self.weekKey()
        state.weeks[week, default: [:]][stat.rawValue, default: 0] += amount
        state.years[Self.yearKey(), default: [:]][stat.rawValue, default: 0] += amount

        let reward = stat.reward
        let points = (after / reward.per - before / reward.per) * reward.xp
        isDirty = true
        addXP(points)
        checkChallenges()
        checkBadges()
    }

    /// Call when a page finishes loading in a normal tab: keeps the streak
    /// going and spots night owls and early birds.
    func recordPage(at date: Date = Date()) {
        guard isOn else { return }
        markActive(on: date)
        record(.pages)
        let hour = Calendar.current.component(.hour, from: date)
        let today = Self.dayKey(date)
        if hour < 4, UserDefaults.standard.string(forKey: "vela.play.owlDay") != today {
            UserDefaults.standard.set(today, forKey: "vela.play.owlDay")
            record(.nightOwl)
            bubble(.wave, "Hoo hoo! Still up?")
        } else if (4..<6).contains(hour), UserDefaults.standard.string(forKey: "vela.play.birdDay") != today {
            UserDefaults.standard.set(today, forKey: "vela.play.birdDay")
            record(.earlyBird)
            bubble(.cheer, "Up with the sun!")
        }
    }

    /// Adds active browsing time (called every few seconds).
    func addBrowsingTime(_ seconds: Double, site: String) {
        guard isOn else { return }
        pendingSeconds[site, default: 0] += seconds
        let total = pendingSeconds.values.reduce(0, +)
        guard total >= 60 else { return }
        // Once a minute: fold it into the year's numbers.
        let year = Self.yearKey(), day = Self.dayKey()
        for (site, secs) in pendingSeconds {
            state.yearSites[year, default: [:]][site, default: 0] += secs / 60
        }
        state.yearDays[year, default: [:]][day, default: 0] += total / 60
        pendingSeconds = [:]
        trimYearSites(year)
        record(.minutes, by: Int(total / 60))
    }

    private func trimYearSites(_ year: String) {
        guard let sites = state.yearSites[year], sites.count > 250 else { return }
        let kept = sites.sorted { $0.value > $1.value }.prefix(200)
        state.yearSites[year] = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    /// A tracker was blocked on `site`: points, and now and then Pip eats it.
    func trackerBlocked(_ domain: String) {
        guard isOn else { return }
        record(.trackers)
        let count = total(.trackers)
        if count % 25 == 0 {
            bubble(.munch, "Nom! That's \(count.formatted()) trackers gobbled.")
        } else {
            pet(.munch)
        }
    }

    // MARK: - Streaks

    private func markActive(on date: Date) {
        let today = Self.dayKey(date)
        guard state.lastActiveDay != today else { return }
        let yesterday = Self.dayKey(date.addingTimeInterval(-86_400))
        state.streak = state.lastActiveDay == yesterday ? state.streak + 1 : 1
        state.bestStreak = max(state.bestStreak, state.streak)
        state.lastActiveDay = today
        record(.activeDays)
        // A streak bonus: 5 more points for each day in a row, up to 50.
        addXP(min(state.streak * 5, 50))
        if [3, 7, 14, 30, 50, 100, 200, 365].contains(state.streak) {
            celebrate(Celebration(title: "\(state.streak)-day streak!", subtitle: "You've used Vela \(state.streak) days in a row.",
                                  icon: "flame.fill", color: 0xFF8A5B))
        } else if state.streak > 1 {
            bubble(.cheer, "Day \(state.streak) in a row! 🔥")
        }
        checkPrivacyScore()
    }

    /// Once a day: points for your privacy score, and the best score so far.
    func checkPrivacyScore() {
        guard isOn else { return }
        let score = privacyScore()
        state.bestPrivacyScore = max(state.bestPrivacyScore, score)
        let today = Self.dayKey()
        if state.lastPrivacyDay != today {
            state.lastPrivacyDay = today
            addXP(score / 5)
        }
        isDirty = true
        checkBadges()
    }

    // MARK: - Points and levels

    private func addXP(_ points: Int) {
        guard points > 0 else { return }
        let oldLevel = level
        state.xp += points
        isDirty = true
        let newLevel = level
        guard newLevel > oldLevel else { return }
        var subtitle = "You're now a \(Level.title(for: newLevel))."
        if let theme = Theme.all.first(where: { $0.unlockLevel == newLevel }) {
            subtitle += " New theme unlocked: \(theme.name)."
        }
        if let backdrop = Backdrop.allCases.first(where: { $0.unlockLevel == newLevel && $0 != .none }) {
            subtitle += " New background: \(backdrop.name)."
        }
        celebrate(Celebration(title: "Level \(newLevel)!", subtitle: subtitle, icon: "sparkles", color: 0x8B7CFF))
        sound("Hero")
        save()
    }

    private func checkBadges() {
        for badge in Badge.all where state.badges[badge.id] == nil && badge.isEarned(self) {
            state.badges[badge.id] = Date()
            isDirty = true
            addXP(50)
            celebrate(Celebration(title: badge.title, subtitle: "Badge earned: \(badge.detail)",
                                  icon: badge.icon, color: badge.color))
            sound("Glass")
            save()
        }
    }

    // MARK: - Weekly challenges

    var weeklyChallenges: [ChallengeTemplate] { ChallengeTemplate.forWeek(Self.weekKey()) }

    func progress(of challenge: ChallengeTemplate) -> Int { min(thisWeek(challenge.stat), challenge.target) }

    func isDone(_ challenge: ChallengeTemplate) -> Bool {
        state.challengesDone[Self.weekKey()]?.contains(challenge.id) == true
    }

    private func checkChallenges() {
        let week = Self.weekKey()
        for challenge in weeklyChallenges where !isDone(challenge) && thisWeek(challenge.stat) >= challenge.target {
            state.challengesDone[week, default: []].append(challenge.id)
            state.totals[Stat.challenges.rawValue, default: 0] += 1
            state.years[Self.yearKey(), default: [:]][Stat.challenges.rawValue, default: 0] += 1
            addXP(challenge.xp)
            let doneCount = state.challengesDone[week]?.count ?? 0
            if doneCount == 3 {
                state.perfectWeeks += 1
                addXP(150)
                celebrate(Celebration(title: "All three challenges done!", subtitle: "+150 bonus points. See you next week.",
                                      icon: "trophy.fill", color: 0xFFD166))
            } else {
                celebrate(Celebration(title: "Challenge complete", subtitle: "\(challenge.title): +\(challenge.xp) points",
                                      icon: challenge.icon, color: 0xFFD166))
            }
        }
        // Keep only the last 8 weeks of weekly numbers.
        if state.weeks.count > 8 {
            for key in state.weeks.keys.sorted().dropLast(8) {
                state.weeks[key] = nil
                state.challengesDone[key] = nil
            }
        }
    }

    // MARK: - Reading bingo

    /// A Reading List item was marked as read: fill a bingo square if it fits one.
    func finishedReading(url: URL, title: String, added: Date) {
        guard isOn else { return }
        record(.readingDone)
        let host = url.host()?.lowercased() ?? ""
        let calendar = Calendar.current
        let now = Date()
        let read = BingoRead(
            title: title, host: host, path: url.path().lowercased(),
            hour: calendar.component(.hour, from: now),
            isWeekend: calendar.isDateInWeekend(now),
            daysSaved: now.timeIntervalSince(added) / 86_400,
            isNewSite: !state.readSites.contains(host),
            readsToday: readsToday()
        )
        state.readSites.append(host)
        if state.readSites.count > 300 { state.readSites.removeFirst(state.readSites.count - 300) }

        guard let index = state.bingoCard.indices.first(where: { index in
            !state.bingoFilled.contains(index) && BingoSquare.find(state.bingoCard[index]).matches(read)
        }) else {
            bubble(.cheer, "Finished one! It didn't match a bingo square this time.")
            return
        }
        state.bingoFilled.append(index)
        let square = BingoSquare.find(state.bingoCard[index])
        bubble(.cheer, "Bingo square: \(square.title)!")

        for (lineIndex, line) in BingoSquare.lines.enumerated()
        where !state.bingoLinesScored.contains(lineIndex) && line.allSatisfy({ state.bingoFilled.contains($0) }) {
            state.bingoLinesScored.append(lineIndex)
            record(.bingos)
            addXP(150)
            celebrate(Celebration(title: "BINGO!", subtitle: "A full line on your reading card. +150 points",
                                  icon: "square.grid.3x3.fill", color: 0xF07FB4))
        }
        if state.bingoFilled.count == 9 {
            addXP(300)
            celebrate(Celebration(title: "Blackout!", subtitle: "You filled the whole card. +300 points and a fresh card.",
                                  icon: "star.square.on.square.fill", color: 0xF07FB4))
            newBingoCard()
        }
        isDirty = true
    }

    func newBingoCard() {
        state.bingoCard = BingoSquare.newCard()
        state.bingoFilled = [4]
        state.bingoLinesScored = []
        isDirty = true
    }

    private func readsToday() -> Int {
        let key = "vela.play.readsDay", countKey = "vela.play.readsCount"
        let today = Self.dayKey()
        let count = (UserDefaults.standard.string(forKey: key) == today ? UserDefaults.standard.integer(forKey: countKey) : 0) + 1
        UserDefaults.standard.set(today, forKey: key)
        UserDefaults.standard.set(count, forKey: countKey)
        return count
    }

    // MARK: - Focus quests and the planet

    /// When the current focus quest started, and how long it's meant to last.
    @ObservationIgnored private var questStart: Date?
    @ObservationIgnored private var questMinutes: Int?

    func focusStarted(minutes: Int?) {
        questStart = Date()
        questMinutes = minutes
        pet(.focus)
    }

    /// A timed focus quest ran to the end: grow something on the planet.
    func focusFinished() {
        guard let start = questStart else { return }
        let minutes = questMinutes ?? Int(Date().timeIntervalSince(start) / 60)
        questStart = nil
        questMinutes = nil
        grow(minutes: minutes, early: false)
    }

    /// You stopped focus mode yourself. Open-ended quests count if they ran
    /// 15 minutes; a timed one stopped early still earns a sprout after 10.
    func focusStopped() {
        guard let start = questStart else { return }
        let minutes = Int(Date().timeIntervalSince(start) / 60)
        let planned = questMinutes
        questStart = nil
        questMinutes = nil
        if planned == nil, minutes >= 15 {
            grow(minutes: minutes, early: false)
        } else if minutes >= 10 {
            grow(minutes: min(minutes, 14), early: true)
        }
    }

    private func grow(minutes: Int, early: Bool) {
        guard isOn, minutes > 0 else { return }
        let plant = Plant.grown(minutes: minutes, existing: state.garden)
        state.garden.append(plant)
        isDirty = true
        if early {
            record(.focusMinutes, by: minutes)
            bubble(.cheer, "A little sprout for \(minutes) minutes of focus.")
        } else {
            record(.focusSessions)
            record(.focusMinutes, by: minutes)
            celebrate(Celebration(title: "Focus quest complete!", subtitle: "\(minutes) minutes. A new \(plant.kind.rawValue) grew on your planet.",
                                  icon: "leaf.fill", color: 0x4FD49B))
        }
        save()
    }

    // MARK: - Easter eggs and the mini-game

    func found(_ egg: EasterEgg) {
        guard isOn else { return }
        if !state.eggsFound.contains(egg.rawValue) {
            state.eggsFound.append(egg.rawValue)
            record(.eggs)
        }
        isDirty = true
    }

    func gameOver(score: Int) {
        guard isOn else { return }
        record(.games)
        if score > state.gameBest {
            state.gameBest = score
            isDirty = true
            checkBadges()
        }
    }

    // MARK: - Celebrations and Pip

    func celebrate(_ item: Celebration) {
        guard isOn else { return }
        if celebration == nil {
            show(item)
        } else if celebrationQueue.count < 4 {
            celebrationQueue.append(item)
        }
    }

    private func show(_ item: Celebration) {
        celebration = item
        if item.confetti, settings.confetti { confettiBurst += 1 }
        pet(.cheer)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.5))
            guard let self, self.celebration?.id == item.id else { return }
            self.dismissCelebration()
        }
    }

    func dismissCelebration() {
        celebration = nil
        if !celebrationQueue.isEmpty {
            let next = celebrationQueue.removeFirst()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.4))
                self?.show(next)
            }
        }
    }

    /// Fires confetti on its own (easter eggs, the Play hub's party button).
    func throwConfetti() {
        guard isOn, settings.confetti else { return }
        confettiBurst += 1
    }

    /// Pip reacts, without saying anything.
    func pet(_ kind: PetEvent.Kind) {
        guard isOn else { return }
        petEvent = PetEvent(kind: kind, line: nil)
    }

    /// Pip reacts and says something (at most one bubble every 90 seconds,
    /// unless `force`).
    func bubble(_ kind: PetEvent.Kind, _ line: String, force: Bool = false) {
        guard isOn else { return }
        let canTalk = settings.petBubbles && (force || Date().timeIntervalSince(lastBubble) > 90)
        if canTalk { lastBubble = Date() }
        petEvent = PetEvent(kind: kind, line: canTalk ? line : nil)
    }

    func sound(_ name: String) {
        guard isOn, settings.sounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: - Saving

    func save() {
        guard isDirty else { return }
        isDirty = false
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    /// Settings ▸ Play ▸ Start Over.
    func resetProgress() {
        state = PlayState()
        isDirty = true
        save()
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    private static let settingsKey = "vela.play.settings"

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vela", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("play.json")
    }

    // MARK: - Dates

    /// "2026-11-27"
    nonisolated static func dayKey(_ date: Date = Date()) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// "2026-W48": the week runs Monday to Sunday.
    nonisolated static func weekKey(_ date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    nonisolated static func yearKey(_ date: Date = Date()) -> String {
        String(Calendar.current.component(.year, from: date))
    }

    /// When this week's challenges reset (next Monday at midnight).
    static var weekEnds: Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.end
        return start ?? Date().addingTimeInterval(7 * 86_400)
    }
}

/// The sections of the Play hub window.
enum PlayHubSection: String, CaseIterable, Identifiable {
    case overview, badges, challenges, planet, bingo, looks, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .badges: "Badges"
        case .challenges: "Challenges"
        case .planet: "Focus Planet"
        case .bingo: "Reading Bingo"
        case .looks: "Themes"
        case .year: "Year in Review"
        }
    }

    var icon: String {
        switch self {
        case .overview: "sparkles"
        case .badges: "rosette"
        case .challenges: "trophy"
        case .planet: "globe.americas.fill"
        case .bingo: "square.grid.3x3"
        case .looks: "paintpalette"
        case .year: "calendar"
        }
    }
}
