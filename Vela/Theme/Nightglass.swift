import AppKit
import SwiftUI

/// Vela's colors and motion. The values come from the current theme in
/// `Appearance`, so every view that uses `Nightglass.accent` updates when you
/// pick a new theme in Settings.
@MainActor
enum Nightglass {
    private static var theme: Theme { Appearance.shared.theme }

    static var background: Color { Color(hex: theme.background) }
    static let stroke = Color.white.opacity(0.10)
    static let text = Color(hex: 0xEDEEF2)
    static let secondaryText = Color(hex: 0xC9CCD6)
    static let mutedText = Color(hex: 0x9BA0AE)

    // Tab colors. Tabs sit right on the see-through glass, so a bright
    // wallpaper or page can show behind them; these stay readable on both.
    /// The tab you're on: pure white.
    static let activeTabText = Color.white
    /// Every other tab: a soft white, much brighter than `mutedText`.
    static let tabText = Color(hex: 0xDCDFE7)
    /// A faint shadow under tab titles and icons that keeps them crisp
    /// when something light shows through the glass.
    static let tabTextShadow = Color.black.opacity(0.5)
    /// A thin dark layer behind the tab row, so the glass never gets light
    /// enough to wash out the text.
    static let tabBacking = Color.black.opacity(0.22)
    static var accent: Color { Appearance.shared.accent }
    static var claude: Color { Color(hex: theme.warm) }
    static var spotify: Color { Color(hex: theme.cool) }

    // Safety colors used by the link checker, downloads and warnings.
    static let safe = Color(hex: 0x4FD49B)
    static let caution = Color(hex: 0xFFC65C)
    static let danger = Color(hex: 0xFF5D6E)

    /// The springy animation used for tabs and groups (nil when animations are off).
    static var spring: Animation? {
        Appearance.shared.settings.animationsEnabled
            ? .spring(response: 0.35, dampingFraction: 0.8)
            : nil
    }
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

/// The dark backdrop with the theme's two soft glows behind the glass.
struct NightglassBackdrop: View {
    var body: some View {
        let appearance = Appearance.shared
        let theme = appearance.theme
        let glow = appearance.settings.glowIntensity

        ZStack {
            Nightglass.background
            RadialGradient(
                colors: [Color(hex: appearance.glowTop).opacity(glow), .clear],
                center: UnitPoint(x: 0.15, y: 0.2), startRadius: 0, endRadius: 700
            )
            RadialGradient(
                colors: [Color(hex: appearance.glowBottom).opacity(glow), .clear],
                center: UnitPoint(x: 0.85, y: 0.8), startRadius: 0, endRadius: 650
            )
        }
        .animation(.easeInOut(duration: 0.4), value: theme)
        .animation(.easeInOut(duration: 1.2), value: appearance.mood)
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
            .shadow(color: Nightglass.tabTextShadow.opacity(0.6), radius: 1, y: 0.5)
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
