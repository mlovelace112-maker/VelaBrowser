import SwiftUI

/// Vela ▸ Settings… (⌘,), with a tab for each area.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            PrivacySettingsTab()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            SecuritySettingsTab()
                .tabItem { Label("Security", systemImage: "lock.shield") }
            SiteSettingsList()
                .tabItem { Label("Sites", systemImage: "globe") }
            FocusSettingsTab()
                .tabItem { Label("Focus", systemImage: "leaf") }
            ClaudeSettingsTab()
                .tabItem { Label("Claude", systemImage: "sparkle") }
            SpotifySettingsTab()
                .tabItem { Label("Spotify", systemImage: "music.note") }
        }
        .frame(width: 560, height: 560)
    }
}

/// Default browser, Safari bookmarks and reader mode.
struct GeneralSettingsTab: View {
    @Environment(BrowserStore.self) private var store
    @State private var importResult: String?

    var body: some View {
        let defaultBrowser = store.defaultBrowser
        let safari = store.safariBookmarks
        @Bindable var reader = ReaderSettings.shared

        Form {
            Section("Default browser") {
                if defaultBrowser.isDefault {
                    Label("Vela is your default browser", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Nightglass.safe)
                } else {
                    HStack {
                        Text("Open links from other apps in Vela")
                        Spacer()
                        Button("Make Vela the Default Browser") {
                            Task { await defaultBrowser.makeDefault() }
                        }
                    }
                }
            }

            Section {
                switch safari.status {
                case .loaded:
                    LabeledContent("Status", value: "\(safari.allBookmarks.count) bookmarks in \(safari.folders.count) folders")
                    HStack {
                        Button("Copy All into Vela Bookmarks") {
                            let added = store.importSafariBookmarks()
                            importResult = added == 0 ? "Everything was already in Vela." : "Copied \(added) bookmarks."
                        }
                        if let importResult {
                            Text(importResult).foregroundStyle(Nightglass.mutedText)
                        }
                    }
                case .needsAccess:
                    Text("Vela needs Full Disk Access to read Safari's bookmarks. Turn on Vela in System Settings ▸ Privacy & Security ▸ Full Disk Access (use + to add it).")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Open Full Disk Access Settings") { safari.openFullDiskAccessSettings() }
                        Button("Check Again") { safari.reload(force: true) }
                    }
                case .notFound:
                    Text("No Safari bookmarks were found on this Mac.")
                }
            } header: {
                Text("Safari bookmarks")
            } footer: {
                Text("Vela reads Safari's bookmarks live (sidebar ▸ Safari) and never changes them. Bookmarks synced to Safari through iCloud show up too.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
            }

            TabsSettingsSection()
            ContainersSettingsSection()

            UpdatesSection()

            Section("Reader") {
                Picker("Text size", selection: $reader.fontSize) {
                    ForEach([15.0, 17, 19, 21, 24], id: \.self) { size in
                        Text("\(Int(size)) pt").tag(size)
                    }
                }
                Picker("Font", selection: $reader.font) {
                    ForEach(ReaderFont.allCases) { font in
                        Text(font.name).tag(font)
                    }
                }
                Picker("Page", selection: $reader.page) {
                    ForEach(ReaderPage.allCases) { page in
                        Text(page.name).tag(page)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .tint(Nightglass.accent)
        .onAppear {
            defaultBrowser.refresh()
            safari.reload()
        }
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

            DarkModeSettingsSection()

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

/// Settings ▸ General ▸ Updates. See Updater.swift for how updates work.
struct UpdatesSection: View {
    var body: some View {
        @Bindable var updater = Updater.shared

        Section("Updates") {
            LabeledContent("Version", value: updater.versionDescription)
            if updater.isAvailable {
                Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                Toggle(isOn: $updater.installsAutomatically) {
                    Text("Install updates automatically")
                    Text("Updates, including security fixes, install when you quit Vela.")
                }
                .disabled(!updater.checksAutomatically)
                Toggle(isOn: $updater.getsBetaUpdates) {
                    Text("Get beta updates")
                    Text("Try new features as soon as they're merged. Beta builds are a little less tested.")
                }
                HStack {
                    Button("Check Now") { updater.checkNow() }
                    if let last = updater.lastCheck {
                        Text("Last checked \(last.formatted(.relative(presentation: .named)))")
                            .foregroundStyle(Nightglass.mutedText)
                    }
                }
            }
            if let pending = updater.pendingMacOSUpdate {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.shield.fill").foregroundStyle(Nightglass.caution)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("macOS update available")
                        Text("\(pending). Vela uses Safari's web engine, which only gets security fixes through macOS updates.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Nightglass.mutedText)
                    }
                    Spacer()
                    Button("Open Software Update") { updater.openSoftwareUpdate() }
                }
            }
            if !updater.isAvailable, let reason = updater.unavailableReason {
                Text(reason)
                    .foregroundStyle(Nightglass.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
