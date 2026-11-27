import SwiftUI

/// The Play hub: your level, streak, badges, challenges, focus planet,
/// reading bingo, unlocked themes and Year in Review, in one window.
/// Open it from the level chip in the toolbar.
struct PlayHub: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private var play: Play { Play.shared }

    var body: some View {
        @Bindable var play = play

        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    PetView(size: 30)
                    Text("Play")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                .padding(.bottom, 12)
                .padding(.leading, 6)

                ForEach(PlayHubSection.allCases) { section in
                    HubSectionButton(section: section, isSelected: play.hubSection == section) {
                        withAnimation(.easeOut(duration: 0.15)) { play.hubSection = section }
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .padding(.leading, 6)
            }
            .padding(14)
            .frame(width: 190)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.black.opacity(0.25))

            ScrollView {
                Group {
                    switch play.hubSection {
                    case .overview: PlayOverviewSection()
                    case .badges: BadgesSection()
                    case .challenges: ChallengesSection()
                    case .planet: PlanetSection()
                    case .bingo: BingoSection()
                    case .looks: LooksSection()
                    case .year: YearSection()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 820, height: 600)
        .background(NightglassBackdrop())
        .foregroundStyle(Nightglass.text)
    }
}

private struct HubSectionButton: View {
    let section: PlayHubSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(section.title, systemImage: section.icon)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Nightglass.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Nightglass.accent.opacity(0.28) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A heading for a section of the hub.
struct HubTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Nightglass.secondaryText)
            }
        }
        .padding(.bottom, 8)
    }
}

/// A round progress ring with something in the middle.
struct ProgressRing<Center: View>: View {
    let progress: Double
    var color: Color = Nightglass.accent
    var lineWidth: CGFloat = 8
    @ViewBuilder let center: Center

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(AngularGradient(colors: [color.opacity(0.6), color], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
    }
}

// MARK: - Overview

private struct PlayOverviewSection: View {
    @Environment(BrowserStore.self) private var store
    private var play: Play { Play.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LevelHeader()
            HStack(alignment: .top, spacing: 14) {
                StreakCard()
                PrivacyScoreCard()
            }
            WeekAtAGlance()
            RecentBadges()
        }
    }
}

private struct LevelHeader: View {
    private var play: Play { Play.shared }

    var body: some View {
        HStack(spacing: 20) {
            ProgressRing(progress: play.levelProgress, lineWidth: 10) {
                VStack(spacing: 0) {
                    Text("\(play.level)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                    Text("LEVEL")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Nightglass.mutedText)
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 6) {
                Text(play.levelTitle)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Nightglass.accent, Nightglass.claude],
                                                    startPoint: .leading, endPoint: .trailing))
                Text("\(play.state.xp.formatted()) points · \(play.xpToNextLevel.formatted()) to level \(play.level + 1)")
                    .font(.system(size: 13))
                    .foregroundStyle(Nightglass.secondaryText)
                if let next = nextUnlock {
                    Label(next, systemImage: "lock.open.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Nightglass.claude)
                }
            }
            Spacer()
        }
        .padding(18)
        .glassPanel(cornerRadius: 18)
    }

    private var nextUnlock: String? {
        let level = play.level
        let theme = Theme.all.filter { $0.unlockLevel > level }.min { $0.unlockLevel < $1.unlockLevel }
        let backdrop = Backdrop.allCases.filter { $0.unlockLevel > level }.min { $0.unlockLevel < $1.unlockLevel }
        switch (theme, backdrop) {
        case let (theme?, backdrop?):
            return theme.unlockLevel <= backdrop.unlockLevel
                ? "Level \(theme.unlockLevel) unlocks the \(theme.name) theme"
                : "Level \(backdrop.unlockLevel) unlocks the \(backdrop.name) background"
        case let (theme?, nil): return "Level \(theme.unlockLevel) unlocks the \(theme.name) theme"
        case let (nil, backdrop?): return "Level \(backdrop.unlockLevel) unlocks the \(backdrop.name) background"
        default: return nil
        }
    }
}

private struct StreakCard: View {
    private var play: Play { Play.shared }
    @State private var flicker = false

    var body: some View {
        let streak = play.currentStreak
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFD166), Color(hex: 0xFF5D3D)],
                                                    startPoint: .top, endPoint: .bottom))
                    .scaleEffect(flicker ? 1.08 : 0.94)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: flicker)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(streak)")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                    Text(streak == 1 ? "day streak" : "day streak")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Nightglass.secondaryText)
                }
            }
            WeekDots()
            Text("Best: \(play.state.bestStreak) days")
                .font(.system(size: 12))
                .foregroundStyle(Nightglass.mutedText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 16)
        .onAppear { flicker = true }
    }
}

/// Seven dots for the last seven days: lit when you used Vela that day.
private struct WeekDots: View {
    private var play: Play { Play.shared }

    var body: some View {
        let days = (0..<7).reversed().map { Date().addingTimeInterval(-Double($0) * 86_400) }
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let used = (play.state.yearDays[Play.yearKey(day)]?[Play.dayKey(day)] ?? 0) > 0
                    || Play.dayKey(day) == play.state.lastActiveDay
                VStack(spacing: 3) {
                    Circle()
                        .fill(used ? Color(hex: 0xFF8A5B) : Color.white.opacity(0.1))
                        .frame(width: 14, height: 14)
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 9))
                        .foregroundStyle(Nightglass.mutedText)
                }
            }
        }
    }
}

private struct PrivacyScoreCard: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        let score = store.privacyScore
        let color = score >= 90 ? Nightglass.safe : (score >= 70 ? Nightglass.caution : Nightglass.danger)
        let missing = store.privacyScoreParts.filter { !$0.isOn }.sorted { $0.points > $1.points }
        HStack(alignment: .top, spacing: 14) {
            ProgressRing(progress: Double(score) / 100, color: color, lineWidth: 7) {
                Text("\(score)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
            }
            .frame(width: 66, height: 66)
            VStack(alignment: .leading, spacing: 5) {
                Text("Privacy score")
                    .font(.system(size: 14, weight: .semibold))
                if missing.isEmpty {
                    Text("Every protection is on. Perfect!")
                        .font(.system(size: 12))
                        .foregroundStyle(Nightglass.secondaryText)
                } else {
                    ForEach(missing.prefix(3)) { part in
                        Text("+\(part.points) \(part.title) (\(part.whereToFix))")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Nightglass.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 16)
    }
}

private struct WeekAtAGlance: View {
    private var play: Play { Play.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This week's challenges")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("See all") { play.hubSection = .challenges }
                    .buttonStyle(.plain)
                    .foregroundStyle(Nightglass.accent)
            }
            ForEach(play.weeklyChallenges) { challenge in
                ChallengeRow(challenge: challenge, compact: true)
            }
        }
        .padding(16)
        .glassPanel(cornerRadius: 16)
    }
}

private struct RecentBadges: View {
    private var play: Play { Play.shared }

    var body: some View {
        let earned = play.earnedBadges.sorted { (play.state.badges[$0.id] ?? .distantPast) > (play.state.badges[$1.id] ?? .distantPast) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Badges: \(earned.count) of \(Badge.all.count)")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("See all") { play.hubSection = .badges }
                    .buttonStyle(.plain)
                    .foregroundStyle(Nightglass.accent)
            }
            if earned.isEmpty {
                Text("Keep browsing: your first badge is one page away.")
                    .font(.system(size: 12))
                    .foregroundStyle(Nightglass.secondaryText)
            } else {
                HStack(spacing: 12) {
                    ForEach(earned.prefix(7)) { badge in
                        BadgeMedal(badge: badge, isEarned: true, size: 46)
                            .help("\(badge.title): \(badge.detail)")
                    }
                }
            }
        }
        .padding(16)
        .glassPanel(cornerRadius: 16)
    }
}

// MARK: - Badges

/// A badge's round medal: colorful when earned, grey with a lock when not.
struct BadgeMedal: View {
    let badge: Badge
    let isEarned: Bool
    var size: CGFloat = 64

    var body: some View {
        let color = Color(hex: badge.color)
        ZStack {
            Circle()
                .fill(isEarned
                      ? AnyShapeStyle(RadialGradient(colors: [color.opacity(0.95), color.opacity(0.45)],
                                                     center: .topLeading, startRadius: 0, endRadius: size))
                      : AnyShapeStyle(Color.white.opacity(0.06)))
            Circle()
                .strokeBorder(isEarned ? Color.white.opacity(0.55) : Color.white.opacity(0.12), lineWidth: 2)
            Image(systemName: isEarned ? badge.icon : (badge.isSecret ? "questionmark" : "lock.fill"))
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(isEarned ? Color.white : Nightglass.mutedText)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: isEarned ? color.opacity(0.5) : .clear, radius: 10)
    }
}

private struct BadgesSection: View {
    private var play: Play { Play.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HubTitle(title: "Badges", subtitle: "\(play.earnedBadges.count) of \(Badge.all.count) earned. Each one is worth 50 points.")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 18) {
                ForEach(Badge.all) { badge in
                    BadgeTile(badge: badge, earnedOn: play.state.badges[badge.id])
                }
            }
        }
    }
}

private struct BadgeTile: View {
    let badge: Badge
    let earnedOn: Date?

    var body: some View {
        let hidden = badge.isSecret && earnedOn == nil
        VStack(spacing: 8) {
            BadgeMedal(badge: badge, isEarned: earnedOn != nil)
            Text(hidden ? "???" : badge.title)
                .font(.system(size: 12.5, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(hidden ? "A secret. Try poking around." : badge.detail)
                .font(.system(size: 11))
                .foregroundStyle(Nightglass.mutedText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let earnedOn {
                Text(earnedOn.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Nightglass.claude)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .top)
        .glassPanel(cornerRadius: 14)
        .opacity(earnedOn == nil ? 0.75 : 1)
    }
}

// MARK: - Challenges

struct ChallengeRow: View {
    let challenge: ChallengeTemplate
    var compact = false
    private var play: Play { Play.shared }

    var body: some View {
        let progress = play.progress(of: challenge)
        let done = play.isDone(challenge)
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color(hex: 0xFFD166) : Nightglass.accent.opacity(0.22))
                    .frame(width: compact ? 30 : 44, height: compact ? 30 : 44)
                Image(systemName: done ? "checkmark" : challenge.icon)
                    .font(.system(size: compact ? 13 : 18, weight: .bold))
                    .foregroundStyle(done ? Color.black : Nightglass.accent)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(challenge.title)
                        .font(.system(size: compact ? 12.5 : 14, weight: .semibold))
                        .strikethrough(done)
                    Spacer()
                    Text(done ? "Done! +\(challenge.xp)" : "\(progress)/\(challenge.target) · +\(challenge.xp)")
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(done ? Color(hex: 0xFFD166) : Nightglass.secondaryText)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: done ? [Color(hex: 0xFFD166), Color(hex: 0xFF8A5B)] : [Nightglass.accent.opacity(0.7), Nightglass.accent],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * Double(progress) / Double(max(challenge.target, 1)))
                    }
                }
                .frame(height: compact ? 6 : 9)
            }
        }
    }
}

private struct ChallengesSection: View {
    private var play: Play { Play.shared }

    var body: some View {
        let done = play.weeklyChallenges.filter { play.isDone($0) }.count
        VStack(alignment: .leading, spacing: 16) {
            HubTitle(title: "Weekly challenges",
                     subtitle: "Three new challenges every Monday. Finish all three for a 150-point bonus.")
            VStack(spacing: 18) {
                ForEach(play.weeklyChallenges) { challenge in
                    ChallengeRow(challenge: challenge)
                }
            }
            .padding(18)
            .glassPanel(cornerRadius: 16)

            HStack(spacing: 14) {
                PlayStatTile(value: "\(done)/3", label: "done this week", icon: "checkmark.seal.fill")
                PlayStatTile(value: Play.weekEnds.formatted(.relative(presentation: .named)), label: "new challenges", icon: "clock.fill")
                PlayStatTile(value: "\(play.state.perfectWeeks)", label: "perfect weeks", icon: "trophy.fill")
            }
        }
    }
}

/// A small glass tile with a big number.
struct PlayStatTile: View {
    let value: String
    let label: String
    let icon: String
    var color: Color = Nightglass.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Nightglass.mutedText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 14)
    }
}

// MARK: - Focus planet

private struct PlanetSection: View {
    @Environment(BrowserStore.self) private var store
    private var play: Play { Play.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HubTitle(title: "Focus planet",
                     subtitle: "Start a focus quest: distracting sites are blocked until the timer ends. Finish it and something grows here.")
            HStack(alignment: .top, spacing: 18) {
                FocusPlanetView(plants: play.state.garden)
                    .frame(width: 330, height: 330)
                    .glassPanel(cornerRadius: 20)
                VStack(alignment: .leading, spacing: 12) {
                    if store.isFocusActive {
                        Label("Quest in progress: \(store.focusStatus ?? "on")", systemImage: "timer")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Nightglass.safe)
                        Button("End quest early") { store.stopFocus() }
                    } else {
                        Text("Start a quest")
                            .font(.system(size: 14, weight: .semibold))
                        ForEach([25, 50, 90], id: \.self) { minutes in
                            Button {
                                store.startFocus(minutes: minutes)
                            } label: {
                                Label("\(minutes) minutes", systemImage: minutes >= 90 ? "tree.fill" : (minutes >= 50 ? "camera.macro" : "leaf.fill"))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Nightglass.safe.opacity(0.75))
                            .controlSize(.large)
                        }
                    }
                    PlayStatTile(value: "\(play.state.garden.count)", label: "things growing", icon: "leaf.fill", color: Nightglass.safe)
                    PlayStatTile(value: "\(play.total(.focusMinutes)) min", label: "focused in all", icon: "timer", color: Nightglass.safe)
                    Text("Longer quests grow rarer things: flowers at 15 minutes, trees at 30, crystals at an hour.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Nightglass.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Reading bingo

private struct BingoSection: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private var play: Play { Play.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HubTitle(title: "Reading bingo",
                     subtitle: "Save pages to your Reading List (⇧⌘D). When you finish one, it fills a square it matches. Three in a row is BINGO.")
            HStack(alignment: .top, spacing: 18) {
                BingoCardView()
                    .frame(width: 360)
                VStack(alignment: .leading, spacing: 12) {
                    PlayStatTile(value: "\(play.state.bingoFilled.count)/9", label: "squares filled", icon: "square.grid.3x3.fill", color: Color(hex: 0xF07FB4))
                    PlayStatTile(value: "\(play.total(.bingos))", label: "bingos all time", icon: "star.fill", color: Color(hex: 0xF07FB4))
                    PlayStatTile(value: "\(store.readingList.filter { !$0.isRead }.count)", label: "waiting in your Reading List", icon: "books.vertical.fill", color: Color(hex: 0xF07FB4))
                    Button("Open Reading List") {
                        dismiss()
                        store.showSidebar(.readingList)
                    }
                    Button("New card") { play.newBingoCard() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Nightglass.mutedText)
                }
            }
        }
    }
}

struct BingoCardView: View {
    private var play: Play { Play.shared }

    var body: some View {
        let card = play.state.bingoCard
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Array(card.enumerated()), id: \.offset) { index, id in
                BingoTile(square: BingoSquare.find(id), isFilled: play.state.bingoFilled.contains(index))
            }
        }
        .padding(10)
        .glassPanel(cornerRadius: 18)
    }
}

private struct BingoTile: View {
    let square: BingoSquare
    let isFilled: Bool

    var body: some View {
        let pink = Color(hex: 0xF07FB4)
        VStack(spacing: 6) {
            Image(systemName: square.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isFilled ? .white : pink)
            Text(square.title)
                .font(.system(size: 10.5, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(isFilled ? .white : Nightglass.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isFilled ? AnyShapeStyle(LinearGradient(colors: [pink, Color(hex: 0x8B7CFF)], startPoint: .topLeading, endPoint: .bottomTrailing))
                               : AnyShapeStyle(Color.white.opacity(0.05)))
        )
        .overlay(alignment: .topTrailing) {
            if isFilled {
                Image(systemName: "star.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0xFFD166))
                    .padding(6)
                    .transition(.scale)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isFilled)
    }
}

// MARK: - Themes and backgrounds

private struct LooksSection: View {
    private var play: Play { Play.shared }

    var body: some View {
        @Bindable var play = play
        @Bindable var appearance = Appearance.shared

        VStack(alignment: .leading, spacing: 16) {
            HubTitle(title: "Themes and backgrounds",
                     subtitle: "Level up to unlock new themes and moving backgrounds for the New Tab page.")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(Theme.all) { theme in
                    UnlockableThemeSwatch(theme: theme, isUnlocked: theme.unlockLevel <= play.level,
                                          isSelected: appearance.settings.themeID == theme.id) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            appearance.settings.themeID = theme.id
                            appearance.settings.customAccent = nil
                        }
                    }
                }
            }
            Text("Moving background")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 6)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                ForEach(Backdrop.allCases) { backdrop in
                    BackdropChoice(backdrop: backdrop, isUnlocked: backdrop.unlockLevel <= play.level,
                                   isSelected: play.settings.backdrop == backdrop.rawValue) {
                        play.settings.backdrop = backdrop.rawValue
                    }
                }
            }
            Toggle("Color Vela with the album that's playing on Spotify", isOn: $play.settings.moodTheming)
                .toggleStyle(.switch)
                .tint(Nightglass.accent)
                .padding(.top, 6)
        }
    }
}

/// A theme preview that shows a lock and the level needed until you reach it.
struct UnlockableThemeSwatch: View {
    let theme: Theme
    let isUnlocked: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Color(hex: theme.background)
                    RadialGradient(colors: [Color(hex: theme.glowTop), .clear], center: .topLeading, startRadius: 0, endRadius: 90)
                    RadialGradient(colors: [Color(hex: theme.glowBottom), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 90)
                    if isUnlocked {
                        Capsule().fill(Color(hex: theme.accent)).frame(width: 30, height: 6)
                    } else {
                        VStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                            Text("Level \(theme.unlockLevel)")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color(hex: theme.accent) : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                )
                Text(theme.name)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
        .help(isUnlocked ? theme.name : "Reach level \(theme.unlockLevel) to unlock \(theme.name)")
    }
}

private struct BackdropChoice: View {
    let backdrop: Backdrop
    let isUnlocked: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Nightglass.background
                    if isUnlocked {
                        BackdropPreview(backdrop: backdrop)
                    } else {
                        VStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                            Text("Level \(backdrop.unlockLevel)")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Nightglass.accent : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                )
                Text(backdrop.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
    }
}

// MARK: - Year in Review

private struct YearSection: View {
    private var play: Play { Play.shared }

    var body: some View {
        let year = Play.yearKey()
        VStack(alignment: .leading, spacing: 16) {
            HubTitle(title: "Your \(year) in Vela",
                     subtitle: "A private recap made on your Mac from what Play counted. Nothing is sent anywhere.")
            HStack(spacing: 14) {
                PlayStatTile(value: hours(play.thisYear(.minutes)), label: "browsing", icon: "clock.fill")
                PlayStatTile(value: play.thisYear(.trackers).formatted(), label: "trackers blocked", icon: "shield.fill", color: Nightglass.safe)
                PlayStatTile(value: play.thisYear(.pages).formatted(), label: "pages explored", icon: "safari.fill", color: Color(hex: 0x5B9CFF))
            }
            Button {
                play.isHubVisible = false
                play.isYearInReviewVisible = true
            } label: {
                Label("Play my Year in Review", systemImage: "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Nightglass.accent)
            .controlSize(.large)
        }
    }

    private func hours(_ minutes: Int) -> String {
        minutes >= 120 ? "\(minutes / 60) hours" : "\(minutes) min"
    }
}
