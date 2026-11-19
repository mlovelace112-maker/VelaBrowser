import SwiftUI

/// Vela ▸ Settings… (⌘,), with a tab for each area.
struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            PrivacySettingsTab()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            SecuritySettingsTab()
                .tabItem { Label("Security", systemImage: "lock.shield") }
            ClaudeSettingsTab()
                .tabItem { Label("Claude", systemImage: "sparkle") }
            SpotifySettingsTab()
                .tabItem { Label("Spotify", systemImage: "music.note") }
        }
        .frame(width: 560, height: 560)
    }
}

/// Themes and the parts of the window you can show or hide.
struct AppearanceSettingsTab: View {
    var body: some View {
        @Bindable var appearance = Appearance.shared

        Form {
            Section("Theme") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(Theme.all) { theme in
                        ThemeSwatch(theme: theme, isSelected: appearance.settings.themeID == theme.id) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                appearance.settings.themeID = theme.id
                                appearance.settings.customAccent = nil
                            }
                        }
                    }
                }
                .padding(.vertical, 4)

                ColorPicker("Accent color", selection: Binding(
                    get: { appearance.accent },
                    set: { appearance.settings.customAccent = $0.hexValue }
                ), supportsOpacity: false)

                if appearance.settings.customAccent != nil {
                    Button("Use the theme's accent color") { appearance.settings.customAccent = nil }
                }

                LabeledContent("Background glow") {
                    Slider(value: $appearance.settings.glowIntensity, in: 0...1)
                        .frame(width: 200)
                }
                Toggle("Animations", isOn: $appearance.settings.animationsEnabled)
            }

            Section("Window") {
                Toggle("Show bookmarks bar", isOn: $appearance.settings.showBookmarksBar)
                Toggle("Compact tabs", isOn: $appearance.settings.compactTabs)
                Toggle("Show bookmarks button in toolbar", isOn: $appearance.settings.showBookmarksButton)
                Toggle("Show share button in toolbar", isOn: $appearance.settings.showShareButton)
            }

            Section("New Tab page") {
                Toggle("Show greeting", isOn: $appearance.settings.showGreeting)
                Toggle("Show shortcuts", isOn: $appearance.settings.showShortcuts)
                Toggle("Show blocked trackers count", isOn: $appearance.settings.showBlockedStats)
            }

            Section {
                Button("Reset Appearance to Defaults") { appearance.reset() }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .tint(Nightglass.accent)
    }
}

/// A clickable preview of a theme: its background, glows and accent.
private struct ThemeSwatch: View {
    let theme: Theme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    Color(hex: theme.background)
                    RadialGradient(colors: [Color(hex: theme.glowTop), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 90)
                    RadialGradient(colors: [Color(hex: theme.glowBottom), .clear],
                                   center: .bottomTrailing, startRadius: 0, endRadius: 90)
                    HStack(spacing: 4) {
                        Capsule().fill(Color(hex: theme.accent)).frame(width: 28, height: 6)
                        Circle().fill(Color(hex: theme.warm)).frame(width: 6, height: 6)
                        Circle().fill(Color(hex: theme.cool)).frame(width: 6, height: 6)
                    }
                    .padding(8)
                }
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color(hex: theme.accent) : Color.white.opacity(0.12),
                                      lineWidth: isSelected ? 2 : 1)
                )
                Text(theme.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.name) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
