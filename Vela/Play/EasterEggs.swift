import SwiftUI

/// Secret words for the command bar (⌘K). Type one exactly and a hidden row
/// appears. The list is in `EasterEgg` (PlayModels.swift).
extension BrowserStore {
    func runEasterEgg(_ egg: EasterEgg) {
        let firstTime = !play.state.eggsFound.contains(egg.rawValue)
        switch egg {
        case .party:
            play.throwConfetti()
            play.sound("Hero")
            play.bubble(.cheer, "🎉 Party time!", force: true)
        case .stargaze:
            play.meteorShowerUntil = Date().addingTimeInterval(9)
            play.bubble(.wave, "Make a wish! 🌠", force: true)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(9.2))
                self?.play.meteorShowerUntil = nil
            }
        case .hello:
            play.bubble(.wave, "Hi there! You found me. I'm Pip! ✨", force: true)
        case .vela:
            play.celebrate(Celebration(
                title: "Vela: the sails",
                subtitle: "Vela is a constellation in the southern sky, the sails of the great ship Argo. Your browser is named after it.",
                icon: "sailboat.fill", color: 0x8B7CFF, confetti: false))
        case .rainbow:
            runRainbow()
        case .answer:
            play.throwConfetti()
            play.bubble(.cheer, "42! Now, what was the question again?", force: true)
        }
        play.found(egg)
        if firstTime {
            play.sound("Purr")
            let left = EasterEgg.allCases.count - play.state.eggsFound.count
            play.celebrate(Celebration(
                title: "Secret found!",
                subtitle: left == 0 ? "That's every secret. You're a true egg hunter." : "\(left) more hidden in Vela.",
                icon: "eye.fill", color: 0xF2C14E))
        }
    }

    /// Cycles Vela's accent color through the rainbow for six seconds.
    private func runRainbow() {
        let saved = Appearance.shared.mood
        play.rainbowUntil = Date().addingTimeInterval(6)
        play.bubble(.cheer, "Wheee! 🌈", force: true)
        Task { [weak self] in
            var hue = 0.0
            while let until = self?.play.rainbowUntil, until > Date() {
                withAnimation(.linear(duration: 0.15)) {
                    Appearance.shared.mood = MoodPalette.fromHue(hue, saturation: 0.85)
                }
                hue = (hue + 0.04).truncatingRemainder(dividingBy: 1)
                try? await Task.sleep(for: .milliseconds(150))
            }
            self?.play.rainbowUntil = nil
            withAnimation(.easeInOut(duration: 0.8)) { Appearance.shared.mood = saved }
        }
    }
}

extension CommandSearch {
    /// A hidden row when what you typed is one of the secret words.
    static func easterEggItem(for query: String, store: BrowserStore) -> CommandItem? {
        guard Play.shared.isOn, let egg = EasterEgg.matching(query) else { return nil }
        return CommandItem(id: "egg-\(egg.rawValue)", kind: .command, icon: "sparkles",
                           title: "✨ \(egg.hint)…", subtitle: "A secret!") {
            store.runEasterEgg(egg)
        }
    }

    /// Play's commands, added to the command bar's list.
    static func playCommands(_ store: BrowserStore) -> [CommandItem] {
        guard Play.shared.isOn else { return [] }
        func open(_ section: PlayHubSection) {
            Play.shared.hubSection = section
            Play.shared.isHubVisible = true
        }
        return [
            CommandItem(id: "c-Play", kind: .command, icon: "sparkles", title: "Play: Level, Streak and Badges",
                        subtitle: "xp points game achievements") { open(.overview) },
            CommandItem(id: "c-Quest", kind: .command, icon: "leaf.fill", title: "Start a 25-Minute Focus Quest",
                        subtitle: "focus timer pomodoro planet garden") { store.startFocus(minutes: 25) },
            CommandItem(id: "c-Planet", kind: .command, icon: "globe.americas.fill", title: "Show My Focus Planet",
                        subtitle: "garden plants") { open(.planet) },
            CommandItem(id: "c-Challenges", kind: .command, icon: "trophy", title: "Weekly Challenges",
                        subtitle: "goals quests") { open(.challenges) },
            CommandItem(id: "c-Bingo", kind: .command, icon: "square.grid.3x3", title: "Reading Bingo",
                        subtitle: "reading list card") { open(.bingo) },
            CommandItem(id: "c-Year", kind: .command, icon: "calendar", title: "Year in Review",
                        subtitle: "recap wrapped summary") { Play.shared.isYearInReviewVisible = true },
        ]
    }
}
