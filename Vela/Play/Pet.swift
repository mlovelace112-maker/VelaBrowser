import AppKit
import SwiftUI

/// Pip, the little star who lives in the toolbar.
///
/// Pip reacts to your browsing: munches trackers the shield blocks, cheers
/// for badges, bobs along when Spotify is playing, puts on a headband during
/// focus quests, looks worried when a page won't load, and falls asleep when
/// you step away or Vela puts tabs to sleep. Click Pip for a little hello.
///
/// Pip is drawn with `Canvas` (shapes, no images), and `TimelineView`
/// redraws it about 20 times a second so it can breathe and blink.
struct PetView: View {
    @Environment(BrowserStore.self) private var store
    var size: CGFloat = 30
    private var play: Play { Play.shared }

    var body: some View {
        // The mood is worked out on every frame, so Pip notices when you
        // step away even if nothing else in the window changes.
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            let mood = currentMood
            let event = play.petEvent
            Canvas { context, canvasSize in
                PipDrawing(mood: mood, event: event, time: timeline.date, accent: Nightglass.accent, music: Nightglass.spotify)
                    .draw(in: &context, size: canvasSize)
            }
            .accessibilityLabel("Pip, your Vela pet, is \(mood.description)")
        }
        .frame(width: size, height: size)
    }

    private var currentMood: PipMood {
        if let event = play.petEvent, Date().timeIntervalSince(event.date) < 25, event.kind == .sleepy { return .asleep }
        if ActivityLog.secondsSinceInput > 180 { return .asleep }
        if let tab = store.selectedTab, tab.isAsleep { return .asleep }
        if store.selectedTab?.loadError != nil { return .worried }
        if store.isFocusActive { return .focused }
        if store.spotify.isPlaying { return .grooving }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 23 || hour < 5 { return .sleepy }
        return .happy
    }
}

enum PipMood: Equatable {
    case happy, sleepy, asleep, focused, grooving, worried

    var description: String {
        switch self {
        case .happy: "happy"
        case .sleepy: "sleepy"
        case .asleep: "asleep"
        case .focused: "focused"
        case .grooving: "dancing to your music"
        case .worried: "worried"
        }
    }
}

/// Draws Pip into a Canvas. Kept separate from the view so the drawing code
/// reads top to bottom: body, face, then extras like Zzz or music notes.
private struct PipDrawing {
    let mood: PipMood
    let event: PetEvent?
    let time: Date
    let accent: Color
    let music: Color

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let t = time.timeIntervalSinceReferenceDate
        let s = min(size.width, size.height)
        let since = event.map { time.timeIntervalSince($0.date) } ?? 99

        // Movement: gentle breathing, plus a jump, wiggle or bop.
        var dy = sin(t * (mood == .asleep ? 1.4 : 2.6)) * s * 0.03
        var angle = 0.0
        var squash = 1.0
        if mood == .grooving {
            dy += -abs(sin(t * 4.2)) * s * 0.08
            angle = sin(t * 4.2) * 0.12
        }
        if since < 1.2, let kind = event?.kind {
            switch kind {
            case .cheer, .focus:
                dy -= abs(sin(since * .pi * 2.5)) * s * 0.22 * (1.2 - since)
            case .wave:
                angle = sin(since * 14) * 0.25 * (1.2 - since)
            case .munch:
                squash = 1 + sin(since * 22) * 0.07 * (1.2 - since)
            case .worried, .sleepy:
                break
            }
        }

        var ctx = context
        ctx.translateBy(x: size.width / 2, y: size.height / 2 + dy)
        ctx.rotate(by: .radians(angle))
        ctx.scaleBy(x: 2 - squash, y: squash)

        // Body: a chubby five-pointed star with soft, rounded points, glowing
        // a little. (The glow is a filter on its own copy of the context, so
        // the face drawn after it stays crisp.)
        let bodyRect = CGRect(x: -s * 0.44, y: -s * 0.44, width: s * 0.88, height: s * 0.88)
        let body = StarShape(points: 5, innerRatio: 0.62).path(in: bodyRect)
        let light = mood == .asleep ? accent.opacity(0.7) : accent
        var glowing = ctx
        glowing.addFilter(.shadow(color: accent.opacity(mood == .asleep ? 0.2 : 0.55), radius: s * 0.12))
        glowing.fill(body, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.9), light]),
                                                 startPoint: CGPoint(x: 0, y: -s * 0.45), endPoint: CGPoint(x: 0, y: s * 0.4)))
        ctx.stroke(body, with: .color(light), style: StrokeStyle(lineWidth: s * 0.08, lineJoin: .round))
        ctx.fill(body, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.9), light]),
                                             startPoint: CGPoint(x: 0, y: -s * 0.45), endPoint: CGPoint(x: 0, y: s * 0.4)))

        drawFace(in: &ctx, s: s, t: t, since: since)
        drawExtras(in: &context, size: size, s: s, t: t)
    }

    private func drawFace(in ctx: inout GraphicsContext, s: CGFloat, t: Double, since: Double) {
        let ink = Color(hex: 0x1B1530)
        let eyeY = -s * 0.02, eyeX = s * 0.12
        let closed = mood == .asleep
        // Blink for a moment every 4 seconds.
        let blink = t.truncatingRemainder(dividingBy: 4.0) < 0.13
        let sleepy = mood == .sleepy

        for side in [-1.0, 1.0] {
            let x = eyeX * side
            if closed || blink {
                var lid = Path()
                lid.move(to: CGPoint(x: x - s * 0.06, y: eyeY))
                lid.addQuadCurve(to: CGPoint(x: x + s * 0.06, y: eyeY), control: CGPoint(x: x, y: eyeY + s * 0.05))
                ctx.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))
            } else {
                let h = s * (sleepy ? 0.07 : (mood == .worried ? 0.14 : 0.12))
                let eye = CGRect(x: x - s * 0.055, y: eyeY - h / 2, width: s * 0.11, height: h)
                ctx.fill(Path(ellipseIn: eye), with: .color(ink))
                ctx.fill(Path(ellipseIn: CGRect(x: x - s * 0.02, y: eyeY - h / 2 + s * 0.015, width: s * 0.035, height: s * 0.035)),
                         with: .color(.white))
            }
        }

        // Focus headband.
        if mood == .focused {
            let band = CGRect(x: -s * 0.24, y: -s * 0.17, width: s * 0.48, height: s * 0.06)
            ctx.fill(Path(roundedRect: band, cornerRadius: s * 0.03), with: .color(Color(hex: 0xFF5D6E)))
        }

        // Rosy cheeks.
        for side in [-1.0, 1.0] {
            ctx.fill(Path(ellipseIn: CGRect(x: side * s * 0.2 - s * 0.045, y: s * 0.07, width: s * 0.09, height: s * 0.05)),
                     with: .color(Color(hex: 0xFF7FB0).opacity(0.55)))
        }

        // Mouth: a smile, a chomp, a little "o" or a wobbly line.
        let mouthY = s * 0.1
        var mouth = Path()
        if event?.kind == .munch, since < 1.0 {
            let open = abs(sin(since * 16)) * s * 0.07 + s * 0.01
            mouth.addEllipse(in: CGRect(x: -s * 0.05, y: mouthY - open / 2, width: s * 0.1, height: open))
            ctx.fill(mouth, with: .color(ink))
        } else if mood == .worried || mood == .asleep {
            mouth.addEllipse(in: CGRect(x: -s * 0.025, y: mouthY - s * 0.02, width: s * 0.05, height: s * 0.045))
            ctx.fill(mouth, with: .color(ink.opacity(0.8)))
        } else {
            let wide = (event?.kind == .cheer && since < 2) || mood == .grooving
            mouth.move(to: CGPoint(x: -s * (wide ? 0.09 : 0.06), y: mouthY - s * 0.01))
            mouth.addQuadCurve(to: CGPoint(x: s * (wide ? 0.09 : 0.06), y: mouthY - s * 0.01),
                               control: CGPoint(x: 0, y: mouthY + s * (wide ? 0.11 : 0.07)))
            ctx.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))
        }
    }

    /// Zzz while asleep, music notes while grooving, sparkles when cheering.
    private func drawExtras(in ctx: inout GraphicsContext, size: CGSize, s: CGFloat, t: Double) {
        let since = event.map { time.timeIntervalSince($0.date) } ?? 99
        if mood == .asleep {
            for i in 0..<2 {
                let phase = (t * 0.5 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let point = CGPoint(x: size.width * 0.78 + phase * s * 0.15, y: size.height * 0.3 - phase * s * 0.35)
                ctx.opacity = 1 - phase
                ctx.draw(Text("z").font(.system(size: s * (0.22 + phase * 0.12), weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white), at: point)
            }
            ctx.opacity = 1
        } else if mood == .grooving {
            let phase = (t * 0.6).truncatingRemainder(dividingBy: 1)
            ctx.opacity = 1 - phase
            ctx.draw(Text("♪").font(.system(size: s * 0.3, weight: .bold)).foregroundStyle(music),
                     at: CGPoint(x: size.width * 0.85, y: size.height * 0.35 - phase * s * 0.4))
            ctx.opacity = 1
        }
        if event?.kind == .cheer, since < 1.6 {
            for i in 0..<5 {
                let a = Double(i) / 5 * 2 * .pi + 0.3
                let r = s * (0.45 + since * 0.35)
                let p = CGPoint(x: size.width / 2 + cos(a) * r, y: size.height / 2 + sin(a) * r)
                ctx.opacity = max(0, 1 - since / 1.6)
                ctx.fill(StarShape().path(in: CGRect(x: p.x - s * 0.07, y: p.y - s * 0.07, width: s * 0.14, height: s * 0.14)),
                         with: .color(Color(hex: 0xFFD166)))
            }
            ctx.opacity = 1
        }
    }
}

/// Pip in the toolbar, with a speech bubble that pops up now and then.
struct PetToolbarItem: View {
    @Environment(BrowserStore.self) private var store
    private var play: Play { Play.shared }
    @State private var bubble: String?

    var body: some View {
        Button {
            let line = Self.hellos.randomElement() ?? "Hi!"
            play.bubble(.cheer, line, force: true)
        } label: {
            PetView(size: 30)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Pip, your Vela pet. Click to say hi.")
        .overlay(alignment: .top) {
            if let bubble {
                SpeechBubble(text: bubble)
                    .fixedSize()
                    .offset(y: 42)
                    .transition(.scale(scale: 0.6, anchor: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: bubble)
        .onChange(of: play.petEvent) {
            guard let line = play.petEvent?.line else { return }
            bubble = line
            let shown = line
            Task {
                try? await Task.sleep(for: .seconds(4.5))
                if bubble == shown { bubble = nil }
            }
        }
    }

    static var hellos: [String] { [
        "Hi! I'm Pip. ✨", "Boop!", "I ate \(Play.shared.total(.trackers).formatted()) trackers so far. Yum.",
        "Want to start a focus quest? Click the level chip!", "Twinkle twinkle!", "You're doing great.",
        "Psst… try typing secret words in ⌘K.", "Stars need naps too. Zzz… just kidding!",
    ] }
}

struct SpeechBubble: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(Color.white)
                .frame(width: 12, height: 7)
            Text(text)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(hex: 0x1B1530))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                .frame(maxWidth: 260)
        }
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
