import AppKit
import Observation
import SwiftUI

/// A color scheme for Vela. Every theme is dark and glassy; they differ in mood.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let background: UInt32
    let accent: UInt32
    /// A warm second color (loading bar, warnings, pop-up notices).
    let warm: UInt32
    /// A cool third color (secure lock, "kept" sites, the music bar).
    let cool: UInt32
    /// The two soft glows behind the glass.
    let glowTop: UInt32
    let glowBottom: UInt32

    static let all: [Theme] = [
        Theme(id: "nightglass", name: "Nightglass", background: 0x07080C, accent: 0x8B7CFF,
              warm: 0xE8875F, cool: 0x4FD1A5, glowTop: 0x2A1F5C, glowBottom: 0x0F3A4A),
        Theme(id: "aurora", name: "Aurora", background: 0x050F0D, accent: 0x4FD1A5,
              warm: 0xF2C14E, cool: 0x5B9CFF, glowTop: 0x0E3B33, glowBottom: 0x1B2B5C),
        Theme(id: "ember", name: "Ember", background: 0x0E0806, accent: 0xFF8A5B,
              warm: 0xF2C14E, cool: 0x7FD8C4, glowTop: 0x4A1E10, glowBottom: 0x3A1030),
        Theme(id: "ocean", name: "Deep Ocean", background: 0x050A14, accent: 0x5B9CFF,
              warm: 0xFFB38A, cool: 0x4FD1A5, glowTop: 0x0F2A5C, glowBottom: 0x0A3A4A),
        Theme(id: "rose", name: "Rosé", background: 0x0D0709, accent: 0xF07FB4,
              warm: 0xFFB38A, cool: 0xB9ADFF, glowTop: 0x4A1430, glowBottom: 0x2A1F5C),
        Theme(id: "graphite", name: "Graphite", background: 0x0B0B0C, accent: 0xD0D3DA,
              warm: 0xE8875F, cool: 0x8FD6B8, glowTop: 0x1E1F24, glowBottom: 0x16171A),
    ]
}

/// Everything you can customize about how Vela looks. Saved between launches.
struct AppearanceSettings: Codable, Equatable {
    var themeID = "nightglass"
    /// Your own accent color, replacing the theme's (nil = use the theme's).
    var customAccent: UInt32?
    /// How strong the colored glows behind the glass are, 0 to 1.
    var glowIntensity = 1.0
    var animationsEnabled = true

    // Window elements
    var showBookmarksBar = true
    var compactTabs = false
    var showShareButton = true
    var showBookmarksButton = true

    // New Tab page
    var showGreeting = true
    var showShortcuts = true
    var showBlockedStats = true
}

/// The current look of the app. Views read colors through `Nightglass`, which
/// reads them from here, so changing a theme recolors the whole app instantly.
@MainActor
@Observable
final class Appearance {
    static let shared = Appearance()

    var settings: AppearanceSettings {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(AppearanceSettings.self, from: data) {
            settings = saved
        } else {
            settings = AppearanceSettings()
        }
    }

    var theme: Theme {
        Theme.all.first { $0.id == settings.themeID } ?? Theme.all[0]
    }

    var accent: Color { Color(hex: settings.customAccent ?? theme.accent) }

    func reset() {
        settings = AppearanceSettings()
    }

    private static let key = "vela.appearance"

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

extension Color {
    /// The color as a 0xRRGGBB number, for saving a custom accent.
    var hexValue: UInt32? {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = UInt32((rgb.redComponent * 255).rounded())
        let g = UInt32((rgb.greenComponent * 255).rounded())
        let b = UInt32((rgb.blueComponent * 255).rounded())
        return (r << 16) | (g << 8) | b
    }
}
