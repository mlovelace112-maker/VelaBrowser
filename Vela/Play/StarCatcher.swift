import SwiftUI

/// Star Catcher: Vela's offline mini-game, shown on the "You're not connected
/// to the internet" page.
///
/// Steer the little sail-ship with the mouse or the ← → arrow keys. Catch
/// falling stars for points (gold ones are worth 5), dodge the asteroids.
/// Three hits and the round is over. It speeds up as you go.
@MainActor
@Observable
final class StarCatcherGame {
    enum Phase { case ready, playing, over }

    struct Thing: Identifiable {
        let id = UUID()
        var x: Double
        var y: Double
        let speed: Double
        let kind: Kind
        let spin: Double
        enum Kind { case star, goldStar, asteroid }
    }

    static let size = CGSize(width: 560, height: 320)
    static let shipY: Double = Double(StarCatcherGame.size.height) - 34

    private(set) var phase: Phase = .ready
    private(set) var score = 0
    private(set) var lives = 3
    private(set) var things: [Thing] = []
    private(set) var shipX: Double = Double(StarCatcherGame.size.width) / 2
    private(set) var hitAt: Date?
    private(set) var catchAt: Date?
    var targetX: Double?
    var leftHeld = false
    var rightHeld = false

    private var elapsed = 0.0
    private var spawnClock = 0.0
    private var last: Date?

    var best: Int { Play.shared.state.gameBest }

    func start() {
        phase = .playing
        score = 0
        lives = 3
        things = []
        elapsed = 0
        spawnClock = 0
        last = nil
        hitAt = nil
    }

    /// Moves everything forward by one frame (about 60 times a second).
    func step(now: Date = Date()) {
        guard phase == .playing else { last = nil; return }
        let dt = min(now.timeIntervalSince(last ?? now), 1.0 / 20)
        last = now
        elapsed += dt

        // Steering: arrow keys push the ship; the mouse pulls it toward the pointer.
        let width = Double(Self.size.width)
        if leftHeld { shipX -= 420 * dt; targetX = nil }
        if rightHeld { shipX += 420 * dt; targetX = nil }
        if let targetX { shipX += (targetX - shipX) * min(1, dt * 14) }
        shipX = min(max(shipX, 24), width - 24)

        // New things fall faster and more often as time goes on.
        spawnClock -= dt
        if spawnClock <= 0 {
            spawnClock = max(0.28, 0.75 - elapsed * 0.008)
            let asteroidChance = min(0.55, 0.28 + elapsed * 0.004)
            let roll = Double.random(in: 0...1)
            let kind: Thing.Kind = roll < asteroidChance ? .asteroid : (roll > 0.94 ? .goldStar : .star)
            things.append(Thing(x: Double.random(in: 20...(width - 20)), y: -20,
                                speed: Double.random(in: 110...170) + elapsed * 3.5,
                                kind: kind, spin: Double.random(in: -3...3)))
        }

        var kept: [Thing] = []
        for var thing in things {
            thing.y += thing.speed * dt
            let caught = abs(thing.y - Self.shipY) < 20 && abs(thing.x - shipX) < 30
            if caught {
                switch thing.kind {
                case .star: score += 1; catchAt = now
                case .goldStar: score += 5; catchAt = now
                case .asteroid:
                    lives -= 1
                    hitAt = now
                    if lives <= 0 { end() }
                }
                continue
            }
            if thing.y < Double(Self.size.height) + 30 { kept.append(thing) }
        }
        things = kept
    }

    private func end() {
        phase = .over
        Play.shared.gameOver(score: score)
    }

    var elapsedTime: Double { elapsed }
}

/// The game card under the "no internet" message.
struct StarCatcherCard: View {
    @State private var game = StarCatcherGame()
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("While you wait: Star Catcher", systemImage: "sailboat.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Nightglass.text)
                Spacer()
                Text("Best \(game.best)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color(hex: 0xFFD166))
            }
            StarCatcherBoard(game: game)
                .frame(width: StarCatcherGame.size.width, height: StarCatcherGame.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Nightglass.stroke))
                .contentShape(Rectangle())
                .onTapGesture {
                    isFocused = true
                    if game.phase != .playing { game.start() }
                }
                .onContinuousHover { phase in
                    if case .active(let point) = phase { game.targetX = point.x }
                }
                .focusable()
                .focused($isFocused)
                .focusEffectDisabled()
                .onKeyPress(keys: [.leftArrow, .rightArrow, .space], phases: [.down, .repeat, .up]) { press in
                    let down = press.phase != .up
                    if press.key == .leftArrow { game.leftHeld = down }
                    if press.key == .rightArrow { game.rightHeld = down }
                    if press.key == .space, press.phase == .down, game.phase != .playing { game.start() }
                    return .handled
                }
                .task {
                    // The game clock: about 60 steps a second while this card is on screen.
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(16))
                        game.step()
                    }
                }
            Text("Mouse or ← → to steer · catch ⭐ · dodge the rocks · Space to start")
                .font(.system(size: 11))
                .foregroundStyle(Nightglass.mutedText)
        }
        .padding(16)
        .glassPanel(cornerRadius: 18)
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        .onAppear { isFocused = true }
    }
}

private struct StarCatcherBoard: View {
    let game: StarCatcherGame

    var body: some View {
        let accent = Nightglass.accent
        // Redrawn every frame; the game itself moves in StarCatcherCard's clock.
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
        Canvas { context, size in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // Sky.
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(hex: 0x0A0820), Color(hex: 0x1A1240)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            for i in 0..<45 {
                let seed = Double(i) * 12.345
                let x = (sin(seed) * 0.5 + 0.5) * size.width
                let y = ((sin(seed * 1.9) * 0.5 + 0.5) * size.height + game.elapsedTime * 12 * Double(1 + i % 3))
                    .truncatingRemainder(dividingBy: size.height)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.5)))
            }

            // Falling stars and asteroids.
            for thing in game.things {
                var ctx = context
                ctx.translateBy(x: thing.x, y: thing.y)
                ctx.rotate(by: .radians(thing.spin * (t.truncatingRemainder(dividingBy: 100))))
                switch thing.kind {
                case .star:
                    ctx.fill(StarShape().path(in: CGRect(x: -11, y: -11, width: 22, height: 22)), with: .color(Color(hex: 0xFFF3B0)))
                case .goldStar:
                    ctx.addFilter(.shadow(color: Color(hex: 0xFFD166), radius: 8))
                    ctx.fill(StarShape().path(in: CGRect(x: -14, y: -14, width: 28, height: 28)), with: .color(Color(hex: 0xFFC233)))
                case .asteroid:
                    var rock = Path()
                    for k in 0..<9 {
                        let a = Double(k) / 9 * 2 * .pi
                        let r = 13 + sin(Double(k) * 2.7 + thing.spin) * 3
                        let p = CGPoint(x: cos(a) * r, y: sin(a) * r)
                        if k == 0 { rock.move(to: p) } else { rock.addLine(to: p) }
                    }
                    rock.closeSubpath()
                    ctx.fill(rock, with: .color(Color(hex: 0x6E6A7C)))
                    ctx.fill(Path(ellipseIn: CGRect(x: -5, y: -4, width: 5, height: 5)), with: .color(Color(hex: 0x4E4A5C)))
                }
            }

            // The ship: a little hull with a big sail (Vela means "the sails").
            var ship = context
            ship.translateBy(x: game.shipX, y: StarCatcherGame.shipY)
            if let hit = game.hitAt, Date().timeIntervalSince(hit) < 0.6 {
                ship.opacity = Int(Date().timeIntervalSince(hit) * 12).isMultiple(of: 2) ? 0.3 : 1
            }
            var hull = Path()
            hull.move(to: CGPoint(x: -24, y: 6))
            hull.addLine(to: CGPoint(x: 24, y: 6))
            hull.addLine(to: CGPoint(x: 16, y: 16))
            hull.addLine(to: CGPoint(x: -16, y: 16))
            hull.closeSubpath()
            ship.fill(hull, with: .color(Color(hex: 0xE8875F)))
            var sail = Path()
            sail.move(to: CGPoint(x: 0, y: -26))
            sail.addLine(to: CGPoint(x: 18, y: 2))
            sail.addLine(to: CGPoint(x: 0, y: 2))
            sail.closeSubpath()
            ship.fill(sail, with: .color(accent))
            var jib = Path()
            jib.move(to: CGPoint(x: -2, y: -20))
            jib.addLine(to: CGPoint(x: -2, y: 2))
            jib.addLine(to: CGPoint(x: -15, y: 2))
            jib.closeSubpath()
            ship.fill(jib, with: .color(.white.opacity(0.85)))
            if let caught = game.catchAt, Date().timeIntervalSince(caught) < 0.3 {
                ship.opacity = 1 - Date().timeIntervalSince(caught) / 0.3
                ship.stroke(Path(ellipseIn: CGRect(x: -30, y: -32, width: 60, height: 52)), with: .color(Color(hex: 0xFFD166)), lineWidth: 2)
            }

            // Score and lives.
            context.draw(Text("\(game.score)").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Color.white),
                         at: CGPoint(x: 28, y: 22))
            context.draw(Text(String(repeating: "♥︎", count: max(game.lives, 0))).font(.system(size: 15)).foregroundStyle(Color(hex: 0xFF5D6E)),
                         at: CGPoint(x: size.width - 36, y: 22))

            switch game.phase {
            case .ready:
                context.draw(Text("Click or press Space to play").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Color.white),
                             at: CGPoint(x: size.width / 2, y: size.height / 2 - 10))
            case .over:
                context.draw(Text("Game over! \(game.score) stars").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Color.white),
                             at: CGPoint(x: size.width / 2, y: size.height / 2 - 18))
                context.draw(Text(game.score >= game.best && game.score > 0 ? "New best! Click to play again" : "Best \(game.best) · click to play again")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0xFFD166)),
                             at: CGPoint(x: size.width / 2, y: size.height / 2 + 14))
            case .playing:
                break
            }
        }
        }
    }
}
