import Foundation
import SwiftUI

// The data behind Vela's playful side: what gets counted, the badges, the
// levels, weekly challenges, reading bingo and the focus planet.
//
// **Privacy:** all of it is counted and kept only on your Mac, in
// ~/Library/Application Support/Vela/play.json. Private tabs never count.

/// Something Vela counts for points. The raw value is the name saved on disk,
/// so never rename one.
enum Stat: String, Codable, CaseIterable {
    case trackers        // trackers the shield blocked
    case popups          // pop-ups and pop-unders blocked
    case pages           // pages you opened
    case minutes         // minutes you actively browsed
    case activeDays      // days you used Vela
    case tidy            // Group Similar Tabs, Put Other Tabs to Sleep…
    case lockdown        // turned on Lockdown Mode for a site
    case focusSessions   // focus quests you finished
    case focusMinutes    // minutes of finished focus quests
    case readingDone     // Reading List items you finished
    case reader          // opened Reader mode
    case bookmarks       // bookmarks you added
    case eggs            // easter eggs found
    case challenges      // weekly challenges finished
    case bingos          // reading bingo lines
    case games           // rounds of Star Catcher
    case nightOwl        // nights you browsed between midnight and 4 AM
    case earlyBird       // mornings you browsed between 4 and 6 AM

    /// How many points one of these is worth: `xp` points for every `per` of them.
    var reward: (per: Int, xp: Int) {
        switch self {
        case .trackers: (10, 2)
        case .popups: (1, 1)
        case .pages: (5, 1)
        case .minutes: (5, 1)
        case .activeDays: (1, 20)
        case .tidy: (1, 10)
        case .lockdown: (1, 25)
        case .focusSessions: (1, 40)
        case .focusMinutes: (1, 1)
        case .readingDone: (1, 20)
        case .reader: (1, 3)
        case .bookmarks: (1, 3)
        case .eggs: (1, 50)
        case .challenges: (1, 0)   // challenges give their own reward
        case .bingos: (1, 0)       // so does bingo
        case .games: (1, 5)
        case .nightOwl: (1, 10)
        case .earlyBird: (1, 10)
        }
    }
}

// MARK: - Levels

/// Levels go up with points. Each level needs 100 more points than the last:
/// level 2 at 100, level 3 at 300, level 4 at 600, level 10 at 4,500.
enum Level {
    static func xpNeeded(for level: Int) -> Int {
        let n = max(level - 1, 0)
        return 50 * n * (n + 1)
    }

    static func level(for xp: Int) -> Int {
        var level = 1
        while xpNeeded(for: level + 1) <= xp { level += 1 }
        return level
    }

    /// How far you are toward the next level, 0 to 1.
    static func progress(for xp: Int) -> Double {
        let level = level(for: xp)
        let start = xpNeeded(for: level), end = xpNeeded(for: level + 1)
        return Double(xp - start) / Double(max(end - start, 1))
    }

    /// Every level has a space name, from a speck of dust to a whole galaxy.
    static func title(for level: Int) -> String {
        let names = ["Stardust", "Spark", "Ember", "Comet", "Meteor", "Nebula",
                     "Pulsar", "Supernova", "Constellation", "Galaxy"]
        if level <= names.count { return names[max(level - 1, 0)] }
        return "Galaxy \(level - names.count + 1)"
    }
}

// MARK: - Badges

/// A badge you can earn. Earned badges are saved by `id`, so never change one.
struct Badge: Identifiable {
    let id: String
    let title: String
    let detail: String
    /// An SF Symbol name.
    let icon: String
    let color: UInt32
    /// Hidden badges show as "???" until you earn them.
    var isSecret = false
    /// True once you've earned it.
    let isEarned: @MainActor (Play) -> Bool

    @MainActor
    static let all: [Badge] = [
        Badge(id: "liftoff", title: "Liftoff", detail: "Browse your first page with Play on.",
              icon: "airplane.departure", color: 0x8B7CFF) { $0.total(.pages) >= 1 },
        Badge(id: "trackers-100", title: "Tracker Snack", detail: "Block 100 trackers.",
              icon: "fork.knife", color: 0x4FD1A5) { $0.total(.trackers) >= 100 },
        Badge(id: "trackers-1000", title: "Blocked 1,000 Trackers", detail: "The shield stopped 1,000 trackers.",
              icon: "shield.lefthalf.filled", color: 0x4FD1A5) { $0.total(.trackers) >= 1_000 },
        Badge(id: "trackers-10000", title: "Tracker Black Hole", detail: "Block 10,000 trackers.",
              icon: "circle.hexagongrid.fill", color: 0x2A1F5C) { $0.total(.trackers) >= 10_000 },
        Badge(id: "popups-50", title: "Pop-up Popper", detail: "Block 50 pop-ups.",
              icon: "bubble.left.and.exclamationmark.bubble.right", color: 0xE8875F) { $0.total(.popups) >= 50 },
        Badge(id: "tidy-10", title: "Tab Tidy Master", detail: "Tidy your tabs 10 times (group, sleep or archive).",
              icon: "square.stack.3d.up.fill", color: 0x5B9CFF) { $0.total(.tidy) >= 10 },
        Badge(id: "night-owl", title: "Night Owl", detail: "Browse between midnight and 4 AM.",
              icon: "moon.stars.fill", color: 0x6C5CE7) { $0.total(.nightOwl) >= 1 },
        Badge(id: "early-bird", title: "Early Bird", detail: "Browse between 4 and 6 AM.",
              icon: "sunrise.fill", color: 0xF2C14E) { $0.total(.earlyBird) >= 1 },
        Badge(id: "streak-3", title: "Warming Up", detail: "Use Vela 3 days in a row.",
              icon: "flame", color: 0xFF8A5B) { $0.state.bestStreak >= 3 },
        Badge(id: "streak-7", title: "Week of Wonders", detail: "A 7-day streak.",
              icon: "flame.fill", color: 0xFF6B3D) { $0.state.bestStreak >= 7 },
        Badge(id: "streak-30", title: "Full Orbit", detail: "A 30-day streak.",
              icon: "circle.dashed.inset.filled", color: 0xFF4D6D) { $0.state.bestStreak >= 30 },
        Badge(id: "streak-100", title: "Century Star", detail: "A 100-day streak.",
              icon: "star.circle.fill", color: 0xFFD166) { $0.state.bestStreak >= 100 },
        Badge(id: "lockdown", title: "Fort Knox", detail: "Turn on Lockdown Mode for a site.",
              icon: "lock.shield.fill", color: 0xD0D3DA) { $0.total(.lockdown) >= 1 },
        Badge(id: "privacy-90", title: "Privacy Pro", detail: "Reach a privacy score of 90.",
              icon: "hand.raised.fill", color: 0x4FD49B) { $0.state.bestPrivacyScore >= 90 },
        Badge(id: "focus-1", title: "First Bloom", detail: "Finish your first focus quest.",
              icon: "leaf.fill", color: 0x4FD49B) { $0.total(.focusSessions) >= 1 },
        Badge(id: "focus-10", title: "Green Thumb", detail: "Finish 10 focus quests.",
              icon: "tree.fill", color: 0x2FA36B) { $0.total(.focusSessions) >= 10 },
        Badge(id: "focus-600", title: "Deep Space Focus", detail: "Focus for 10 hours in total.",
              icon: "scope", color: 0x5B9CFF) { $0.total(.focusMinutes) >= 600 },
        Badge(id: "reading-5", title: "Bookworm", detail: "Finish 5 Reading List items.",
              icon: "books.vertical.fill", color: 0xF07FB4) { $0.total(.readingDone) >= 5 },
        Badge(id: "bingo", title: "Bingo!", detail: "Get a line on your reading bingo card.",
              icon: "square.grid.3x3.fill", color: 0xF07FB4) { $0.total(.bingos) >= 1 },
        Badge(id: "reader-10", title: "Quiet Reader", detail: "Open Reader mode 10 times.",
              icon: "doc.plaintext.fill", color: 0xB9ADFF) { $0.total(.reader) >= 10 },
        Badge(id: "challenge-all", title: "Challenge Champion", detail: "Finish all three weekly challenges in one week.",
              icon: "trophy.fill", color: 0xFFD166) { $0.state.perfectWeeks >= 1 },
        Badge(id: "explorer", title: "Explorer", detail: "Open 1,000 pages.",
              icon: "safari.fill", color: 0x5B9CFF) { $0.total(.pages) >= 1_000 },
        Badge(id: "level-5", title: "Meteor Rising", detail: "Reach level 5.",
              icon: "sparkles", color: 0x8B7CFF) { $0.level >= 5 },
        Badge(id: "level-10", title: "Galaxy Brain", detail: "Reach level 10.",
              icon: "hurricane", color: 0xB9ADFF) { $0.level >= 10 },
        Badge(id: "star-catcher", title: "Star Catcher", detail: "Score 50 in Star Catcher, the offline game.",
              icon: "star.fill", color: 0xFFD166) { $0.state.gameBest >= 50 },
        Badge(id: "egg-1", title: "Curious Cat", detail: "Find a secret.",
              icon: "eye.fill", color: 0xF2C14E, isSecret: true) { $0.state.eggsFound.count >= 1 },
        Badge(id: "egg-all", title: "Egg Hunter", detail: "Find every secret.",
              icon: "oval.portrait.fill", color: 0xF2C14E, isSecret: true) {
            $0.state.eggsFound.count >= EasterEgg.allCases.count
        },
    ]
}

// MARK: - Weekly challenges

/// A challenge for the week, like "Block 300 trackers".
struct ChallengeTemplate: Identifiable {
    let id: String
    let stat: Stat
    let target: Int
    let xp: Int
    let icon: String
    let title: String

    static let all: [ChallengeTemplate] = [
        ChallengeTemplate(id: "trk-300", stat: .trackers, target: 300, xp: 80, icon: "shield.fill", title: "Block 300 trackers"),
        ChallengeTemplate(id: "trk-800", stat: .trackers, target: 800, xp: 120, icon: "shield.lefthalf.filled", title: "Block 800 trackers"),
        ChallengeTemplate(id: "focus-3", stat: .focusSessions, target: 3, xp: 120, icon: "leaf.fill", title: "Finish 3 focus quests"),
        ChallengeTemplate(id: "focus-90", stat: .focusMinutes, target: 90, xp: 100, icon: "timer", title: "Focus for 90 minutes"),
        ChallengeTemplate(id: "read-2", stat: .readingDone, target: 2, xp: 80, icon: "books.vertical.fill", title: "Finish 2 Reading List items"),
        ChallengeTemplate(id: "tidy-3", stat: .tidy, target: 3, xp: 60, icon: "square.stack.3d.up.fill", title: "Tidy your tabs 3 times"),
        ChallengeTemplate(id: "days-5", stat: .activeDays, target: 5, xp: 100, icon: "flame.fill", title: "Use Vela on 5 days"),
        ChallengeTemplate(id: "reader-5", stat: .reader, target: 5, xp: 60, icon: "doc.plaintext", title: "Read 5 pages in Reader mode"),
        ChallengeTemplate(id: "pages-200", stat: .pages, target: 200, xp: 60, icon: "safari", title: "Explore 200 pages"),
        ChallengeTemplate(id: "popups-10", stat: .popups, target: 10, xp: 60, icon: "xmark.rectangle", title: "Block 10 pop-ups"),
        ChallengeTemplate(id: "lockdown-1", stat: .lockdown, target: 1, xp: 60, icon: "lock.shield", title: "Lock down a site you don't trust"),
        ChallengeTemplate(id: "bookmark-5", stat: .bookmarks, target: 5, xp: 50, icon: "star.fill", title: "Bookmark 5 great pages"),
    ]

    /// This week's three, picked the same way all week from the week's date.
    static func forWeek(_ week: String) -> [ChallengeTemplate] {
        var seed = week.unicodeScalars.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1.value) }
        var pool = all, picked: [ChallengeTemplate] = []
        while picked.count < 3, !pool.isEmpty {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let index = Int((seed >> 33) % UInt64(pool.count))
            let choice = pool.remove(at: index)
            // One challenge per kind of thing, so the three feel different.
            if picked.contains(where: { $0.stat == choice.stat }) { continue }
            picked.append(choice)
        }
        return picked
    }
}

// MARK: - Reading bingo

/// One square on the reading bingo card. It fills when you finish a
/// Reading List item that matches it.
struct BingoSquare: Identifiable {
    let id: String
    let title: String
    let icon: String
    let matches: (BingoRead) -> Bool

    static let free = BingoSquare(id: "free", title: "Free star", icon: "star.fill") { _ in true }

    static let all: [BingoSquare] = [
        BingoSquare(id: "morning", title: "Read before noon", icon: "sun.max.fill") { $0.hour < 12 },
        BingoSquare(id: "evening", title: "Read after 6 PM", icon: "moon.fill") { $0.hour >= 18 },
        BingoSquare(id: "weekend", title: "Read on a weekend", icon: "sofa.fill") { $0.isWeekend },
        BingoSquare(id: "oldie", title: "Saved a week ago or more", icon: "hourglass") { $0.daysSaved >= 7 },
        BingoSquare(id: "same-day", title: "Saved and read the same day", icon: "bolt.fill") { $0.daysSaved < 1 },
        BingoSquare(id: "news", title: "A news story", icon: "newspaper.fill") {
            $0.host.containsAny(["news", "nytimes", "bbc.", "cnn.", "theguardian", "npr.org", "reuters", "apnews", "washingtonpost", "wsj."])
        },
        BingoSquare(id: "wiki", title: "A Wikipedia rabbit hole", icon: "globe") { $0.host.contains("wikipedia.org") },
        BingoSquare(id: "blog", title: "Someone's blog or newsletter", icon: "pencil.line") {
            $0.host.containsAny(["substack", "medium.com", "blog", "wordpress", "ghost.io"]) || $0.path.contains("/blog")
        },
        BingoSquare(id: "video", title: "A video", icon: "play.rectangle.fill") {
            $0.host.containsAny(["youtube", "youtu.be", "vimeo", "twitch"])
        },
        BingoSquare(id: "howto", title: "A how-to or guide", icon: "wrench.and.screwdriver.fill") {
            $0.title.containsAny(["how to", "how i", "guide", "tutorial", "tips"])
        },
        BingoSquare(id: "recipe", title: "A recipe", icon: "fork.knife") {
            $0.title.containsAny(["recipe", "cook", "bake"]) || $0.host.containsAny(["recipe", "food", "cooking", "allrecipes", "bonappetit"])
        },
        BingoSquare(id: "question", title: "A title that asks a question", icon: "questionmark.bubble.fill") {
            $0.title.contains("?")
        },
        BingoSquare(id: "numbers", title: "A list (“10 ways…”)", icon: "list.number") {
            $0.title.first?.isNumber == true
        },
        BingoSquare(id: "new-site", title: "From a site you rarely visit", icon: "sparkle.magnifyingglass") { $0.isNewSite },
        BingoSquare(id: "anything", title: "Any 3 reads in one day", icon: "3.circle.fill") { $0.readsToday >= 3 },
    ]

    static func find(_ id: String) -> BingoSquare {
        if id == free.id { return free }
        return all.first { $0.id == id } ?? free
    }

    /// A fresh card: 8 random squares around a free star in the middle.
    static func newCard() -> [String] {
        var ids = all.map(\.id).shuffled().prefix(8).map { $0 }
        ids.insert(free.id, at: 4)
        return ids
    }

    /// The 8 lines that make a bingo: 3 rows, 3 columns, 2 diagonals.
    static let lines: [[Int]] = [
        [0, 1, 2], [3, 4, 5], [6, 7, 8],
        [0, 3, 6], [1, 4, 7], [2, 5, 8],
        [0, 4, 8], [2, 4, 6],
    ]
}

/// What Vela knows about a Reading List item you just finished.
struct BingoRead {
    let title: String
    let host: String
    let path: String
    let hour: Int
    let isWeekend: Bool
    let daysSaved: Double
    let isNewSite: Bool
    let readsToday: Int
}

extension String {
    func containsAny(_ words: [String]) -> Bool {
        let lower = lowercased()
        return words.contains { lower.contains($0) }
    }
}

// MARK: - Focus planet

/// Something that grew on your focus planet after a focus quest.
struct Plant: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case sprout, flower, tulip, tree, pine, mushroom, cactus, crystal
    }

    var id = UUID()
    var kind: Kind
    /// Where it stands around the planet, in degrees.
    var angle: Double
    /// 0.5 (a short quest) to 1.4 (two hours or more).
    var size: Double
    var minutes: Int
    var date = Date()

    /// Longer quests grow bigger, rarer things.
    static func grown(minutes: Int, existing: [Plant]) -> Plant {
        let kinds: [Kind]
        switch minutes {
        case ..<15: kinds = [.sprout]
        case ..<30: kinds = [.flower, .tulip, .mushroom]
        case ..<60: kinds = [.tree, .pine, .cactus, .flower]
        default: kinds = [.tree, .pine, .crystal]
        }
        // Spread plants out: take the angle farthest from the others.
        let taken = existing.map(\.angle)
        let candidates = (0..<36).map { Double($0) * 10 + Double.random(in: -3...3) }
        let angle = candidates.max { a, b in
            Self.gap(a, taken) < Self.gap(b, taken)
        } ?? Double.random(in: 0..<360)
        let size = min(1.4, 0.5 + Double(minutes) / 120)
        return Plant(kind: kinds.randomElement() ?? .sprout, angle: angle, size: size, minutes: minutes)
    }

    private static func gap(_ angle: Double, _ taken: [Double]) -> Double {
        taken.map { abs(((angle - $0 + 540).truncatingRemainder(dividingBy: 360)) - 180) }.min() ?? 360
    }
}

// MARK: - Easter eggs

/// Secret words you can type in the command bar (⌘K).
enum EasterEgg: String, CaseIterable, Codable {
    case party, stargaze, hello, vela, rainbow, answer

    /// The exact words that trigger it.
    var phrases: [String] {
        switch self {
        case .party: ["party", "celebrate", "confetti"]
        case .stargaze: ["stargaze", "shooting star", "meteor shower"]
        case .hello: ["hello pip", "hi pip", "pet pip"]
        case .vela: ["vela", "what is vela"]
        case .rainbow: ["rainbow", "taste the rainbow"]
        case .answer: ["42", "the answer"]
        }
    }

    var hint: String {
        switch self {
        case .party: "Throw a party"
        case .stargaze: "Make a wish"
        case .hello: "Say hello to Pip"
        case .vela: "Where the name comes from"
        case .rainbow: "Every color at once"
        case .answer: "Life, the universe and everything"
        }
    }

    static func matching(_ text: String) -> EasterEgg? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.first { $0.phrases.contains(cleaned) }
    }
}

// MARK: - Saved state

/// Everything Play remembers. Saved as JSON; every field has a default, so
/// adding a field later never loses what's already saved.
struct PlayState: Codable, Equatable {
    var xp = 0
    /// Lifetime totals.
    var totals: [String: Int] = [:]
    /// "2026-W48" → that week's totals (the last 8 weeks are kept).
    var weeks: [String: [String: Int]] = [:]
    /// "2026" → that year's totals, for Year in Review.
    var years: [String: [String: Int]] = [:]
    /// "2026" → minutes on each site that year (the top 200 are kept).
    var yearSites: [String: [String: Double]] = [:]
    /// "2026" → minutes each day that year ("2026-11-27": 95).
    var yearDays: [String: [String: Double]] = [:]

    var streak = 0
    var bestStreak = 0
    /// The last day you used Vela ("2026-11-27").
    var lastActiveDay: String?

    /// Badge id → when you earned it.
    var badges: [String: Date] = [:]
    /// Challenge ids finished, per week.
    var challengesDone: [String: [String]] = [:]
    var perfectWeeks = 0

    var bingoCard: [String] = BingoSquare.newCard()
    var bingoFilled: [Int] = [4]
    var bingoLinesScored: [Int] = []
    /// Sites a bingo read came from, to spot "a site you rarely visit".
    var readSites: [String] = []

    var garden: [Plant] = []
    var bestPrivacyScore = 0
    var lastPrivacyDay: String?
    var gameBest = 0
    var eggsFound: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlayState()
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        xp = get(.xp, d.xp)
        totals = get(.totals, d.totals)
        weeks = get(.weeks, d.weeks)
        years = get(.years, d.years)
        yearSites = get(.yearSites, d.yearSites)
        yearDays = get(.yearDays, d.yearDays)
        streak = get(.streak, d.streak)
        bestStreak = get(.bestStreak, d.bestStreak)
        lastActiveDay = get(.lastActiveDay, d.lastActiveDay)
        badges = get(.badges, d.badges)
        challengesDone = get(.challengesDone, d.challengesDone)
        perfectWeeks = get(.perfectWeeks, d.perfectWeeks)
        bingoCard = get(.bingoCard, d.bingoCard)
        bingoFilled = get(.bingoFilled, d.bingoFilled)
        bingoLinesScored = get(.bingoLinesScored, d.bingoLinesScored)
        readSites = get(.readSites, d.readSites)
        garden = get(.garden, d.garden)
        bestPrivacyScore = get(.bestPrivacyScore, d.bestPrivacyScore)
        lastPrivacyDay = get(.lastPrivacyDay, d.lastPrivacyDay)
        gameBest = get(.gameBest, d.gameBest)
        eggsFound = get(.eggsFound, d.eggsFound)
        if bingoCard.count != 9 { bingoCard = BingoSquare.newCard(); bingoFilled = [4]; bingoLinesScored = [] }
    }
}

/// Your Play switches. Saved separately from the progress above.
struct PlaySettings: Codable, Equatable {
    /// The main switch. Off hides everything playful (your progress is kept).
    var isEnabled = true
    var showPet = true
    var confetti = true
    var sounds = true
    var petBubbles = true
    var offlineGame = true
    /// Tint Vela with the colors of the album that's playing on Spotify.
    var moodTheming = true
    /// The moving background you picked (unlocked by leveling up).
    var backdrop = Backdrop.none.rawValue

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlaySettings()
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        isEnabled = get(.isEnabled, d.isEnabled)
        showPet = get(.showPet, d.showPet)
        confetti = get(.confetti, d.confetti)
        sounds = get(.sounds, d.sounds)
        petBubbles = get(.petBubbles, d.petBubbles)
        offlineGame = get(.offlineGame, d.offlineGame)
        moodTheming = get(.moodTheming, d.moodTheming)
        backdrop = get(.backdrop, d.backdrop)
    }
}

/// Moving backgrounds behind the New Tab page, unlocked by leveling up.
enum Backdrop: String, CaseIterable, Identifiable {
    case none, starfield, aurora, meteors, nebula

    var id: String { rawValue }

    var name: String {
        switch self {
        case .none: "Still glow"
        case .starfield: "Twinkling stars"
        case .aurora: "Aurora"
        case .meteors: "Meteor shower"
        case .nebula: "Drifting nebula"
        }
    }

    var unlockLevel: Int {
        switch self {
        case .none: 1
        case .starfield: 3
        case .aurora: 5
        case .meteors: 7
        case .nebula: 9
        }
    }
}
