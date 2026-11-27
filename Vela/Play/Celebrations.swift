import SwiftUI

/// Everything Play draws over the whole window: confetti, the "Badge earned!"
/// banner and the meteor shower easter egg. Only the banner can be clicked;
/// the rest lets clicks pass through to the page.
struct PlayOverlay: View {
    private var play: Play { Play.shared }

    var body: some View {
        ZStack(alignment: .top) {
            if play.isOn {
                if let until = play.meteorShowerUntil, until > Date() {
                    MeteorShower(until: until)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                ConfettiView(trigger: play.confettiBurst)
                    .allowsHitTesting(false)
                if let celebration = play.celebration {
                    CelebrationBanner(celebration: celebration)
                        .padding(.top, 64)
                        .transition(.move(edge: .top).combined(with: .scale(scale: 0.8)).combined(with: .opacity))
                        .id(celebration.id)
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.65), value: play.celebration)
        .animation(.easeInOut(duration: 0.6), value: play.meteorShowerUntil)
    }
}

/// "Badge earned: Night Owl", sliding in at the top of the window.
struct CelebrationBanner: View {
    let celebration: Celebration
    @State private var glow = false

    var body: some View {
        let color = Color(hex: celebration.color)
        Button { Play.shared.dismissCelebration() } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.25))
                        .frame(width: 52, height: 52)
                        .scaleEffect(glow ? 1.18 : 0.95)
                    Circle()
                        .fill(LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 40, height: 40)
                    Image(systemName: celebration.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: glow)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(celebration.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(celebration.subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Nightglass.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 360, alignment: .leading)
            }
            .padding(.leading, 12)
            .padding(.trailing, 22)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Capsule().fill(color.opacity(0.18)))
            .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1.5))
            .shadow(color: color.opacity(0.45), radius: 24, y: 8)
        }
        .buttonStyle(.plain)
        .help("Click to close")
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}

// MARK: - Confetti

/// A burst of confetti from both bottom corners of the window. Each time
/// `trigger` changes, a new burst fires. Drawn with `Canvas`, which is fast
/// enough for a couple of hundred pieces, and only animates while pieces
/// are in the air.
struct ConfettiView: View {
    let trigger: Int
    @State private var pieces: [ConfettiPiece] = []
    @State private var startedAt = Date.distantPast

    private static let lifetime: TimeInterval = 3.6

    var body: some View {
        TimelineView(.animation(paused: pieces.isEmpty)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(startedAt)
                guard t < Self.lifetime else { return }
                for piece in pieces {
                    draw(piece, at: t, in: &context, size: size)
                }
            }
        }
        .onChange(of: trigger) { fire() }
        .ignoresSafeArea()
    }

    private func fire() {
        startedAt = Date()
        pieces = (0..<170).map { ConfettiPiece.random(fromLeft: $0.isMultiple(of: 2)) }
        let burst = startedAt
        Task {
            try? await Task.sleep(for: .seconds(Self.lifetime))
            if startedAt == burst { pieces = [] }
        }
    }

    private func draw(_ piece: ConfettiPiece, at time: TimeInterval, in context: inout GraphicsContext, size: CGSize) {
        let t = max(0, time - piece.delay)
        // Launched up and inward, then gravity pulls it back down while it flutters.
        let gravity = 1.15 * size.height
        let x = piece.startX * size.width + piece.velocity.dx * size.width * t + sin(t * piece.wobble + piece.phase) * 14
        let y = size.height + 10 + piece.velocity.dy * size.height * t + 0.5 * gravity * t * t
        guard y < size.height + 30 else { return }
        let fade = min(1, max(0, (Self.lifetime - time) / 0.8))

        var piece_context = context
        piece_context.opacity = fade
        piece_context.translateBy(x: x, y: y)
        piece_context.rotate(by: .radians(piece.spin * t + piece.phase))
        // Squash one way to fake the piece flipping over in the air.
        piece_context.scaleBy(x: 1, y: abs(cos(t * piece.wobble * 1.3 + piece.phase)) * 0.8 + 0.2)
        let rect = CGRect(x: -piece.size / 2, y: -piece.size / 3, width: piece.size, height: piece.size * 0.66)
        switch piece.shape {
        case 0: piece_context.fill(Path(rect), with: .color(piece.color))
        case 1: piece_context.fill(Path(ellipseIn: rect), with: .color(piece.color))
        default: piece_context.fill(StarShape().path(in: rect.insetBy(dx: -2, dy: -3)), with: .color(piece.color))
        }
    }
}

struct ConfettiPiece {
    let startX: Double
    let velocity: CGVector
    let delay: Double
    let spin: Double
    let wobble: Double
    let phase: Double
    let size: Double
    let shape: Int
    let color: Color

    static let palette: [UInt32] = [0x8B7CFF, 0xFF5DA2, 0xFFD166, 0x4FD1A5, 0x5B9CFF, 0xFF8A5B, 0xFFFFFF, 0xB9FF9A]

    static func random(fromLeft: Bool) -> ConfettiPiece {
        ConfettiPiece(
            startX: fromLeft ? Double.random(in: 0...0.06) : Double.random(in: 0.94...1),
            velocity: CGVector(dx: (fromLeft ? 1 : -1) * Double.random(in: 0.12...0.42),
                               dy: -Double.random(in: 1.0...1.55)),
            delay: Double.random(in: 0...0.25),
            spin: Double.random(in: -9...9),
            wobble: Double.random(in: 4...9),
            phase: Double.random(in: 0...(2 * .pi)),
            size: Double.random(in: 7...13),
            shape: Int.random(in: 0...5) == 0 ? 2 : Int.random(in: 0...1),
            color: Color(hex: palette.randomElement() ?? 0xFFFFFF)
        )
    }
}

/// A five-pointed star, used for confetti, Pip and the game.
struct StarShape: Shape {
    var points = 5
    var innerRatio = 0.45

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        var path = Path()
        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = Double(i) * .pi / Double(points) - .pi / 2
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Meteor shower (an easter egg)

/// Shooting stars streaking across the window for a few seconds.
struct MeteorShower: View {
    let until: Date
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for i in 0..<26 {
                    let seed = Double(i) * 12.9898
                    let period = 1.6 + (sin(seed) + 1) * 0.9
                    let local = (t + (sin(seed * 3.1) + 1) * 2).truncatingRemainder(dividingBy: period) / period
                    let startX = (sin(seed * 7.7) + 1) / 2 * size.width * 1.2
                    let startY = (sin(seed * 5.3) + 1) / 2 * size.height * 0.35 - 40
                    let travel = size.width * 0.55
                    let head = CGPoint(x: startX - travel * local, y: startY + travel * 0.55 * local)
                    let tail = CGPoint(x: head.x + 90, y: head.y - 50)
                    var path = Path()
                    path.move(to: tail)
                    path.addLine(to: head)
                    let alpha = sin(local * .pi)
                    context.stroke(path, with: .linearGradient(
                        Gradient(colors: [.white.opacity(0), .white.opacity(alpha)]),
                        startPoint: tail, endPoint: head), lineWidth: 2)
                    context.fill(Path(ellipseIn: CGRect(x: head.x - 2.5, y: head.y - 2.5, width: 5, height: 5)),
                                 with: .color(.white.opacity(alpha)))
                }
            }
        }
        .ignoresSafeArea()
    }
}
