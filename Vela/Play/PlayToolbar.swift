import SwiftUI

/// Pip plus the level-and-streak chip, in the toolbar. Click the chip to
/// open the Play hub. Hidden when Play is off.
struct PlayToolbarItems: View {
    private var play: Play { Play.shared }

    var body: some View {
        if play.isOn {
            HStack(spacing: 2) {
                if play.settings.showPet {
                    PetToolbarItem()
                }
                PlayChip()
            }
            .transition(.scale.combined(with: .opacity))
        }
    }
}

/// "⭐ 4  🔥 12": your level (with a ring filling toward the next one) and
/// your streak.
struct PlayChip: View {
    private var play: Play { Play.shared }
    @State private var isHovering = false
    @State private var shimmer = false

    var body: some View {
        Button {
            play.hubSection = .overview
            play.isHubVisible = true
        } label: {
            HStack(spacing: 7) {
                ProgressRing(progress: play.levelProgress, lineWidth: 2.5) {
                    Text("\(play.level)")
                        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 21, height: 21)
                .contentTransition(.numericText())

                if play.currentStreak > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFD166), Color(hex: 0xFF5D3D)],
                                                            startPoint: .top, endPoint: .bottom))
                            .symbolEffect(.bounce, value: play.currentStreak)
                        Text("\(play.currentStreak)")
                            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, play.currentStreak > 0 ? 9 : 4)
            .frame(height: 28)
            .background(
                Capsule().fill(LinearGradient(colors: [Nightglass.accent.opacity(isHovering ? 0.45 : 0.3),
                                                       Nightglass.claude.opacity(isHovering ? 0.35 : 0.2)],
                                              startPoint: .leading, endPoint: .trailing))
            )
            .overlay(
                Capsule().strokeBorder(
                    AngularGradient(colors: [Nightglass.accent, Nightglass.claude, Color(hex: 0xFFD166), Nightglass.accent],
                                    center: .center, angle: .degrees(shimmer ? 360 : 0)),
                    lineWidth: 1.2)
            )
            .scaleEffect(isHovering ? 1.05 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: play.level)
        .help("Level \(play.level) \(play.levelTitle) · \(play.currentStreak)-day streak. Open Play.")
        .onAppear {
            guard Appearance.shared.settings.animationsEnabled else { return }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { shimmer = true }
        }
    }
}

/// A card on the New Tab page: your streak, level and this week's challenges
/// at a glance, with a button to start a focus quest.
struct PlayNewTabCard: View {
    @Environment(BrowserStore.self) private var store
    private var play: Play { Play.shared }

    var body: some View {
        if play.isOn {
            Button {
                play.hubSection = .overview
                play.isHubVisible = true
            } label: {
                HStack(spacing: 16) {
                    PetView(size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Level \(play.level) \(play.levelTitle) · \(play.xpToNextLevel.formatted()) points to go")
                            .font(.system(size: 12))
                            .foregroundStyle(Nightglass.secondaryText)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.1))
                                Capsule()
                                    .fill(LinearGradient(colors: [Nightglass.accent, Nightglass.claude],
                                                         startPoint: .leading, endPoint: .trailing))
                                    .frame(width: proxy.size.width * play.levelProgress)
                            }
                        }
                        .frame(height: 6)
                    }
                    .frame(width: 240)
                    Divider().frame(height: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(play.weeklyChallenges) { challenge in
                            HStack(spacing: 6) {
                                Image(systemName: play.isDone(challenge) ? "checkmark.circle.fill" : challenge.icon)
                                    .foregroundStyle(play.isDone(challenge) ? Color(hex: 0xFFD166) : Nightglass.accent)
                                    .frame(width: 14)
                                Text("\(challenge.title) · \(play.progress(of: challenge))/\(challenge.target)")
                                    .foregroundStyle(Nightglass.secondaryText)
                            }
                            .font(.system(size: 11.5))
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .glassPanel(cornerRadius: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Play")
        }
    }

    private var headline: String {
        let streak = play.currentStreak
        switch streak {
        case 0: return "Welcome back! Start a new streak today."
        case 1: return "Day 1 of a new streak 🔥"
        default: return "\(streak)-day streak 🔥 Keep it going!"
        }
    }
}
