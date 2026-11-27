import SwiftUI

/// Your focus planet: a little world that slowly turns, with something new
/// growing on it for every focus quest you finish. Drawn with `Canvas`.
struct FocusPlanetView: View {
    let plants: [Plant]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                drawSky(in: &context, size: size, t: t)
                let center = CGPoint(x: size.width / 2, y: size.height / 2 + 10)
                // The planet gets a little bigger as your garden grows.
                let radius = min(size.width, size.height) * (0.24 + min(Double(plants.count), 40) * 0.002)
                let spin = t * 4 // degrees per second
                drawPlanet(in: &context, center: center, radius: radius)
                for plant in plants.sorted(by: { $0.size < $1.size }) {
                    draw(plant, in: &context, center: center, radius: radius, spin: spin, t: t)
                }
                if plants.isEmpty {
                    context.draw(Text("Finish a focus quest to plant your first sprout")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7)),
                                 at: CGPoint(x: size.width / 2, y: size.height - 24))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel("Your focus planet, with \(plants.count) things growing on it")
    }

    private func drawSky(in context: inout GraphicsContext, size: CGSize, t: Double) {
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Color(hex: 0x0B0A1E), Color(hex: 0x16103A)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        for i in 0..<40 {
            let seed = Double(i) * 78.233
            let x = (sin(seed) * 0.5 + 0.5) * size.width
            let y = (sin(seed * 1.7) * 0.5 + 0.5) * size.height
            let twinkle = 0.35 + 0.65 * (sin(t * (1 + Double(i % 5) * 0.4) + seed) * 0.5 + 0.5)
            let r = 0.6 + Double(i % 3) * 0.5
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(twinkle * 0.8)))
        }
    }

    private func drawPlanet(in context: inout GraphicsContext, center: CGPoint, radius: Double) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        var glow = context
        glow.addFilter(.blur(radius: 24))
        glow.fill(Path(ellipseIn: rect.insetBy(dx: -10, dy: -10)), with: .color(Color(hex: 0x4FD49B).opacity(0.35)))
        context.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [Color(hex: 0x7FE8B0), Color(hex: 0x2FA36B), Color(hex: 0x135A40)]),
            center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.4),
            startRadius: 0, endRadius: radius * 1.6))
        // A couple of darker patches, like continents.
        for (dx, dy, r) in [(-0.3, 0.2, 0.28), (0.35, -0.1, 0.2), (0.1, 0.5, 0.16)] {
            let patch = CGRect(x: center.x + radius * dx - radius * r, y: center.y + radius * dy - radius * r * 0.7,
                               width: radius * r * 2, height: radius * r * 1.4)
            context.fill(Path(ellipseIn: patch), with: .color(Color(hex: 0x135A40).opacity(0.45)))
        }
    }

    private func draw(_ plant: Plant, in context: inout GraphicsContext, center: CGPoint, radius: Double, spin: Double, t: Double) {
        let angle = (plant.angle + spin) * .pi / 180
        // Plants on the far side of the planet are hidden behind it.
        let base = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        var ctx = context
        ctx.translateBy(x: base.x, y: base.y)
        ctx.rotate(by: .radians(angle + .pi / 2))
        let h = 22 * plant.size
        let sway = sin(t * 1.5 + plant.angle) * 0.06
        ctx.rotate(by: .radians(sway))

        switch plant.kind {
        case .sprout:
            ctx.stroke(stem(h * 0.6), with: .color(Color(hex: 0x7FE8B0)), lineWidth: 2)
            ctx.fill(leaf(at: CGPoint(x: 0, y: -h * 0.6), size: h * 0.35, flip: false), with: .color(Color(hex: 0x9CF5C4)))
            ctx.fill(leaf(at: CGPoint(x: 0, y: -h * 0.6), size: h * 0.35, flip: true), with: .color(Color(hex: 0x7FE8B0)))
        case .flower, .tulip:
            ctx.stroke(stem(h), with: .color(Color(hex: 0x4FD49B)), lineWidth: 2)
            let color = Color(hex: plant.kind == .flower ? 0xFF7FB0 : 0xFFD166)
            for i in 0..<5 {
                let a = Double(i) / 5 * 2 * .pi
                let p = CGPoint(x: cos(a) * h * 0.18, y: -h + sin(a) * h * 0.18)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - h * 0.13, y: p.y - h * 0.13, width: h * 0.26, height: h * 0.26)), with: .color(color))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: -h * 0.09, y: -h - h * 0.09, width: h * 0.18, height: h * 0.18)), with: .color(Color(hex: 0xFFF3B0)))
        case .tree:
            ctx.fill(Path(CGRect(x: -h * 0.06, y: -h * 0.6, width: h * 0.12, height: h * 0.6)), with: .color(Color(hex: 0x8A5A3B)))
            ctx.fill(Path(ellipseIn: CGRect(x: -h * 0.36, y: -h * 1.25, width: h * 0.72, height: h * 0.72)), with: .color(Color(hex: 0x2FA36B)))
            ctx.fill(Path(ellipseIn: CGRect(x: -h * 0.22, y: -h * 1.2, width: h * 0.34, height: h * 0.3)), with: .color(Color(hex: 0x6FDD9F).opacity(0.7)))
        case .pine:
            ctx.fill(Path(CGRect(x: -h * 0.05, y: -h * 0.3, width: h * 0.1, height: h * 0.3)), with: .color(Color(hex: 0x8A5A3B)))
            var tree = Path()
            tree.move(to: CGPoint(x: 0, y: -h * 1.35))
            tree.addLine(to: CGPoint(x: h * 0.32, y: -h * 0.25))
            tree.addLine(to: CGPoint(x: -h * 0.32, y: -h * 0.25))
            tree.closeSubpath()
            ctx.fill(tree, with: .color(Color(hex: 0x1F8A5A)))
        case .mushroom:
            ctx.fill(Path(roundedRect: CGRect(x: -h * 0.08, y: -h * 0.45, width: h * 0.16, height: h * 0.45), cornerRadius: 2), with: .color(Color(hex: 0xF3E9DC)))
            var cap = Path()
            cap.addArc(center: CGPoint(x: 0, y: -h * 0.45), radius: h * 0.3, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            cap.closeSubpath()
            ctx.fill(cap, with: .color(Color(hex: 0xFF5D6E)))
            ctx.fill(Path(ellipseIn: CGRect(x: -h * 0.12, y: -h * 0.66, width: h * 0.08, height: h * 0.08)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: h * 0.06, y: -h * 0.6, width: h * 0.07, height: h * 0.07)), with: .color(.white))
        case .cactus:
            let green = Color(hex: 0x3FBF7F)
            ctx.fill(Path(roundedRect: CGRect(x: -h * 0.1, y: -h, width: h * 0.2, height: h), cornerRadius: h * 0.1), with: .color(green))
            ctx.fill(Path(roundedRect: CGRect(x: h * 0.1, y: -h * 0.65, width: h * 0.2, height: h * 0.1), cornerRadius: 2), with: .color(green))
            ctx.fill(Path(roundedRect: CGRect(x: h * 0.2, y: -h * 0.85, width: h * 0.1, height: h * 0.3), cornerRadius: h * 0.05), with: .color(green))
        case .crystal:
            var gem = Path()
            gem.move(to: CGPoint(x: 0, y: -h * 1.3))
            gem.addLine(to: CGPoint(x: h * 0.22, y: -h * 0.5))
            gem.addLine(to: CGPoint(x: 0, y: 0))
            gem.addLine(to: CGPoint(x: -h * 0.22, y: -h * 0.5))
            gem.closeSubpath()
            var shine = ctx
            shine.addFilter(.shadow(color: Color(hex: 0xB9ADFF), radius: 6 + sin(t * 2) * 3))
            shine.fill(gem, with: .linearGradient(Gradient(colors: [Color(hex: 0xE4DEFF), Color(hex: 0x8B7CFF)]),
                                                  startPoint: CGPoint(x: 0, y: -h * 1.3), endPoint: .zero))
        }
    }

    private func stem(_ height: Double) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: -height))
        return path
    }

    private func leaf(at point: CGPoint, size: Double, flip: Bool) -> Path {
        let rect = CGRect(x: flip ? point.x - size : point.x, y: point.y - size * 0.3, width: size, height: size * 0.6)
        return Path(ellipseIn: rect)
    }
}
