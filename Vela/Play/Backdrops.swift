import SwiftUI

/// The moving background you picked in the Play hub (unlocked by leveling
/// up), drawn behind the New Tab page. Nothing when Play is off or you
/// picked "Still glow". Respects Settings ▸ Appearance ▸ Animations.
struct PlayBackdropLayer: View {
    private var play: Play { Play.shared }

    var body: some View {
        let backdrop = Backdrop(rawValue: play.settings.backdrop) ?? .none
        if play.isOn, backdrop != .none, backdrop.unlockLevel <= play.level,
           Appearance.shared.settings.animationsEnabled {
            BackdropPreview(backdrop: backdrop)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

/// Draws one of the moving backgrounds, at any size.
struct BackdropPreview: View {
    let backdrop: Backdrop

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                switch backdrop {
                case .none: break
                case .starfield: Self.stars(in: &context, size: size, t: t)
                case .aurora: Self.aurora(in: &context, size: size, t: t)
                case .meteors:
                    Self.stars(in: &context, size: size, t: t, count: 60)
                    Self.meteors(in: &context, size: size, t: t)
                case .nebula: Self.nebula(in: &context, size: size, t: t)
                }
            }
        }
    }

    static func stars(in context: inout GraphicsContext, size: CGSize, t: Double, count: Int = 140) {
        for i in 0..<count {
            let seed = Double(i) * 43.758
            let x = (sin(seed) * 0.5 + 0.5) * size.width
            // Stars drift slowly upward, like the sky turning.
            let y = ((sin(seed * 2.3) * 0.5 + 0.5) * size.height - t * (2 + Double(i % 4))).truncatingRemainder(dividingBy: size.height)
            let wrappedY = y < 0 ? y + size.height : y
            let twinkle = 0.25 + 0.75 * (sin(t * (0.8 + Double(i % 7) * 0.3) + seed) * 0.5 + 0.5)
            let r = 0.5 + Double(i % 4) * 0.35
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: wrappedY - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(twinkle * 0.85)))
        }
    }

    static func aurora(in context: inout GraphicsContext, size: CGSize, t: Double) {
        var blurred = context
        blurred.addFilter(.blur(radius: 40))
        let colors: [UInt32] = [0x4FD1A5, 0x5B9CFF, 0xB9ADFF]
        for (i, hex) in colors.enumerated() {
            var path = Path()
            let baseY = size.height * (0.25 + Double(i) * 0.12)
            path.move(to: CGPoint(x: 0, y: baseY))
            for step in stride(from: 0.0, through: 1.0, by: 0.05) {
                let x = step * size.width
                let y = baseY + sin(step * 6 + t * (0.4 + Double(i) * 0.15)) * size.height * 0.06
                    + sin(step * 13 - t * 0.7) * size.height * 0.02
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: baseY + size.height * 0.18))
            path.addLine(to: CGPoint(x: 0, y: baseY + size.height * 0.18))
            path.closeSubpath()
            blurred.fill(path, with: .color(Color(hex: hex).opacity(0.32 + 0.1 * sin(t * 0.5 + Double(i)))))
        }
    }

    static func meteors(in context: inout GraphicsContext, size: CGSize, t: Double) {
        for i in 0..<5 {
            let seed = Double(i) * 91.7
            let period = 5.0 + Double(i)
            let local = (t + seed).truncatingRemainder(dividingBy: period) / period
            guard local < 0.25 else { continue }
            let p = local / 0.25
            let startX = (sin(seed) * 0.5 + 0.5) * size.width + size.width * 0.3
            let startY = (sin(seed * 1.3) * 0.5 + 0.5) * size.height * 0.4
            let head = CGPoint(x: startX - p * size.width * 0.5, y: startY + p * size.width * 0.28)
            let tail = CGPoint(x: head.x + 120, y: head.y - 67)
            var path = Path()
            path.move(to: tail)
            path.addLine(to: head)
            context.stroke(path, with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(sin(p * .pi))]),
                                                       startPoint: tail, endPoint: head), lineWidth: 2)
        }
    }

    static func nebula(in context: inout GraphicsContext, size: CGSize, t: Double) {
        var blurred = context
        blurred.addFilter(.blur(radius: 60))
        let clouds: [(UInt32, Double, Double)] = [(0x8B7CFF, 0.3, 0.35), (0xFF5DA2, 0.7, 0.55), (0x4FD1A5, 0.5, 0.8), (0x5B9CFF, 0.2, 0.7)]
        for (i, cloud) in clouds.enumerated() {
            let x = (cloud.1 + sin(t * 0.08 + Double(i) * 2) * 0.12) * size.width
            let y = (cloud.2 + cos(t * 0.06 + Double(i)) * 0.1) * size.height
            let r = min(size.width, size.height) * (0.28 + 0.05 * sin(t * 0.2 + Double(i)))
            blurred.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(Color(hex: cloud.0).opacity(0.28)))
        }
        stars(in: &context, size: size, t: t, count: 70)
    }
}
