import SwiftUI

/// Your year in Vela, as a short story of slides: time online, top sites,
/// what the shield blocked, focus, reading, streaks and your level. Made on
/// your Mac from what Play counted; nothing leaves it.
///
/// Click, or press → / Space, to go to the next slide.
struct YearInReviewView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var forward = true
    private var play: Play { Play.shared }

    private var year: String { Play.yearKey() }

    var body: some View {
        let slides = makeSlides()
        ZStack {
            LinearGradient(colors: [Color(hex: slides[index].colors.0), Color(hex: slides[index].colors.1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .animation(.easeInOut(duration: 0.6), value: index)
            BackdropPreview(backdrop: .starfield).opacity(0.6)

            VStack(spacing: 0) {
                ProgressDots(count: slides.count, index: index)
                    .padding(.top, 18)
                Spacer()
                slides[index].content
                    .id(index)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                    .padding(.horizontal, 50)
                Spacer()
                HStack {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    if index > 0 {
                        Button { go(-1, slides.count) } label: { Image(systemName: "chevron.left") }
                            .keyboardShortcut(.leftArrow, modifiers: [])
                    }
                    Button(index == slides.count - 1 ? "Start Over" : "Next") { go(1, slides.count) }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.25))
                }
                .padding(18)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 640, height: 520)
        .contentShape(Rectangle())
        .onTapGesture { go(1, slides.count) }
        .onChange(of: index) {
            if index == slides.count - 1 { play.throwConfetti() }
        }
    }

    private func go(_ step: Int, _ count: Int) {
        forward = step > 0
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            index = (index + step + count) % count
        }
    }

    private struct Slide {
        let colors: (UInt32, UInt32)
        let content: AnyView
    }

    private func makeSlides() -> [Slide] {
        let minutes = play.thisYear(.minutes, year: year)
        let days = play.state.yearDays[year] ?? [:]
        let busiest = days.max { $0.value < $1.value }
        let sites = (play.state.yearSites[year] ?? [:]).sorted { $0.value > $1.value }.prefix(5)
        let firstDay = days.keys.min()
        let trackers = play.thisYear(.trackers, year: year)
        let activeDays = max(days.count, 1)
        let badgesThisYear = play.state.badges.values.filter { Play.yearKey($0) == year }.count

        return [
            Slide(colors: (0x2A1F5C, 0x0F3A4A), content: AnyView(
                VStack(spacing: 14) {
                    PetView(size: 90)
                    BigLine(small: "Your", big: "\(year) in Vela")
                    Text(firstDay.map { "Since \(Self.pretty($0)), Vela has been keeping score. Let's look back." }
                         ?? "Vela has only just started counting. Come back after some browsing!")
                        .font(.system(size: 15))
                        .multilineTextAlignment(.center)
                        .opacity(0.85)
                })),
            Slide(colors: (0x0F2A5C, 0x5B2A8C), content: AnyView(
                VStack(spacing: 14) {
                    BigLine(small: "You spent", big: minutes >= 120 ? "\(minutes / 60) hours" : "\(minutes) minutes")
                    Text("actively browsing, across \(days.count) days.")
                        .font(.system(size: 17))
                    if let busiest {
                        Text("Your busiest day was \(Self.pretty(busiest.key)), with \(Int(busiest.value)) minutes.")
                            .font(.system(size: 14)).opacity(0.8)
                    }
                })),
            Slide(colors: (0x4A1E10, 0x8C2A5B), content: AnyView(
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your top sites")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                    if sites.isEmpty {
                        Text("Nothing yet. Go explore!").opacity(0.8)
                    }
                    ForEach(Array(sites.enumerated()), id: \.offset) { rank, site in
                        TopSiteBar(rank: rank + 1, site: site.key, minutes: site.value,
                                   fraction: site.value / max(sites.first?.value ?? 1, 1))
                    }
                }
                .frame(maxWidth: 460))),
            Slide(colors: (0x0E3B33, 0x1B2B5C), content: AnyView(
                VStack(spacing: 14) {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 54))
                    BigLine(small: "The shield blocked", big: "\(trackers.formatted()) trackers")
                    Text("That's about \(trackers / activeDays) a day, plus \(play.thisYear(.popups, year: year)) pop-ups. Pip ate every one.")
                        .font(.system(size: 15)).multilineTextAlignment(.center).opacity(0.85)
                })),
            Slide(colors: (0x0A3A24, 0x135A40), content: AnyView(
                HStack(spacing: 26) {
                    FocusPlanetView(plants: play.state.garden.filter { Play.yearKey($0.date) == year })
                        .frame(width: 220, height: 220)
                    VStack(alignment: .leading, spacing: 10) {
                        BigLine(small: "You focused for", big: "\(play.thisYear(.focusMinutes, year: year)) min", alignment: .leading)
                        Text("\(play.thisYear(.focusSessions, year: year)) focus quests finished.")
                            .font(.system(size: 15)).opacity(0.85)
                    }
                })),
            Slide(colors: (0x4A1430, 0x2A1F5C), content: AnyView(
                VStack(spacing: 14) {
                    Image(systemName: "books.vertical.fill").font(.system(size: 50))
                    BigLine(small: "You finished", big: "\(play.thisYear(.readingDone, year: year)) reads")
                    Text("from your Reading List, opened Reader mode \(play.thisYear(.reader, year: year)) times and scored \(play.thisYear(.bingos, year: year)) bingo lines.")
                        .font(.system(size: 15)).multilineTextAlignment(.center).opacity(0.85)
                })),
            Slide(colors: (0x5C2A0A, 0x8C1F3A), content: AnyView(
                VStack(spacing: 14) {
                    Image(systemName: "flame.fill").font(.system(size: 54))
                    BigLine(small: "Longest streak", big: "\(play.state.bestStreak) days")
                    Text("You earned \(badgesThisYear) badges and finished \(play.thisYear(.challenges, year: year)) weekly challenges.")
                        .font(.system(size: 15)).multilineTextAlignment(.center).opacity(0.85)
                })),
            Slide(colors: (0x3A2A0A, 0x2A1F5C), content: AnyView(
                VStack(spacing: 16) {
                    ProgressRing(progress: play.levelProgress, color: Color(hex: 0xFFD166), lineWidth: 10) {
                        Text("\(play.level)").font(.system(size: 44, weight: .heavy, design: .rounded))
                    }
                    .frame(width: 120, height: 120)
                    BigLine(small: "You're a level \(play.level)", big: play.levelTitle)
                    Text("Thanks for sailing with Vela this year. ✨")
                        .font(.system(size: 16)).opacity(0.9)
                })),
        ]
    }

    /// "2026-11-27" → "Nov 27"
    static func pretty(_ dayKey: String) -> String {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return dayKey }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// A small line over a huge one: "The shield blocked / 12,345 trackers".
private struct BigLine: View {
    let small: String
    let big: String
    var alignment: HorizontalAlignment = .center
    @State private var shown = false

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(small)
                .font(.system(size: 18, weight: .medium))
                .opacity(0.85)
            Text(big)
                .font(.system(size: 50, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .scaleEffect(shown ? 1 : 0.6)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.15)) { shown = true }
        }
    }
}

private struct TopSiteBar: View {
    let rank: Int
    let site: String
    let minutes: Double
    let fraction: Double
    @State private var grown = false

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(site).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(minutes >= 120 ? "\(Int(minutes / 60)) h" : "\(Int(minutes)) min")
                        .font(.system(size: 12)).opacity(0.8)
                }
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: max(6, proxy.size.width * (grown ? fraction : 0)))
                }
                .frame(height: 8)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.1 * Double(rank))) { grown = true }
        }
    }
}

private struct ProgressDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i <= index ? 0.95 : 0.3))
                    .frame(width: i == index ? 26 : 12, height: 4)
            }
        }
        .animation(.spring(response: 0.4), value: index)
    }
}
