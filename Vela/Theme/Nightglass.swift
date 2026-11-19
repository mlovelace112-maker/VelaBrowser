import AppKit
import SwiftUI

/// Vela's "Nightglass" look: dark, sleek, frosted glass.
/// Change a color here and it changes everywhere.
enum Nightglass {
    static let background = Color(hex: 0x07080C)
    static let stroke = Color.white.opacity(0.10)
    static let text = Color(hex: 0xEDEEF2)
    static let secondaryText = Color(hex: 0xC9CCD6)
    static let mutedText = Color(hex: 0x9BA0AE)
    static let accent = Color(hex: 0x8B7CFF)
    static let claude = Color(hex: 0xE8875F)
    static let spotify = Color(hex: 0x4FD1A5)

    /// The springy animation used for tabs and groups.
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
}

extension Color {
    /// Lets us write colors the way designers do: Color(hex: 0x8B7CFF)
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Real macOS window blur (what you see through the frosted toolbar).
/// `NSViewRepresentable` is how SwiftUI borrows an older AppKit view.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

/// The dark backdrop with soft violet and teal glows behind the glass.
struct NightglassBackdrop: View {
    var body: some View {
        ZStack {
            Nightglass.background
            RadialGradient(
                colors: [Color(hex: 0x2A1F5C), .clear],
                center: UnitPoint(x: 0.15, y: 0.2), startRadius: 0, endRadius: 700
            )
            RadialGradient(
                colors: [Color(hex: 0x0F3A4A), .clear],
                center: UnitPoint(x: 0.85, y: 0.8), startRadius: 0, endRadius: 650
            )
        }
    }
}

extension View {
    /// A frosted-glass card with a hairline border.
    func glassPanel(cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Nightglass.stroke))
    }
}

/// Small square toolbar buttons that light up when you hover over them.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, size: size)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isHovering ? Nightglass.text : Nightglass.secondaryText)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.14 : (isHovering ? 0.08 : 0)))
            )
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
