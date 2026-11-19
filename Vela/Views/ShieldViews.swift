import SwiftUI

extension BrowserStore {
    /// Connects a toggle or picker straight to one privacy setting.
    /// Example: `Toggle("Block pop-ups", isOn: store.privacyBinding(\.blockPopups))`
    func privacyBinding<Value>(_ keyPath: WritableKeyPath<PrivacySettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.privacy[keyPath: keyPath] },
            set: { newValue in self.updatePrivacy { $0[keyPath: keyPath] = newValue } }
        )
    }
}

/// The shield button in the toolbar, with a badge counting trackers blocked on this page.
struct ShieldButton: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab
    @State private var isOpen = false

    var body: some View {
        let isUp = store.shieldsUp(for: tab) && store.privacy.blockingLevel != .off
        let count = tab.trackersFound.count

        Button { isOpen.toggle() } label: {
            Image(systemName: isUp ? "shield.lefthalf.filled" : "shield.slash")
                .foregroundStyle(isUp ? Nightglass.accent : Nightglass.mutedText)
                .overlay(alignment: .topTrailing) {
                    if isUp && count > 0 {
                        Text("\(count)")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Color(hex: 0x0B0B12))
                            .padding(.horizontal, 3.5)
                            .frame(minWidth: 14, minHeight: 13)
                            .background(Capsule().fill(Nightglass.accent))
                            .offset(x: 9, y: -7)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(Nightglass.spring, value: count)
        }
        .buttonStyle(IconButtonStyle())
        .help(isUp ? "Shield: \(count) trackers blocked on this page" : "Shield is off for this site")
        .accessibilityLabel(isUp ? "Privacy shield, \(count) trackers blocked" : "Privacy shield off")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ShieldPopover(tab: tab)
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}

/// The panel that drops down from the shield button.
struct ShieldPopover: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tab: BrowserTab
    @State private var showTrackers = false

    var body: some View {
        let site = tab.url.map(BrowserStore.siteName) ?? "New Tab"
        let isUp = store.shieldsUp(for: tab)

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: isUp ? "checkmark.shield.fill" : "shield.slash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isUp ? Nightglass.accent : Nightglass.mutedText)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Nightglass.accent.opacity(isUp ? 0.22 : 0.08))
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isUp ? "Shield is on" : "Shield is off")
                        .font(.system(size: 15, weight: .semibold))
                    Text(site)
                        .font(.system(size: 12))
                        .foregroundStyle(Nightglass.mutedText)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("Shield for \(site)", isOn: Binding(
                    get: { isUp },
                    set: { _ in store.toggleShields(for: tab) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Nightglass.accent)
                .disabled(tab.url == nil)
            }

            HStack(spacing: 8) {
                StatTile(value: tab.trackersFound.count, label: "Trackers", color: Nightglass.accent)
                StatTile(value: tab.popupsBlocked.count, label: "Pop-ups", color: Nightglass.claude)
                StatTile(value: store.trackersBlockedTotal, label: "All time", color: Nightglass.spotify)
            }

            if !tab.trackersFound.isEmpty {
                DisclosureGroup("Blocked on this page", isExpanded: $showTrackers) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(tab.trackersFound, id: \.self) { domain in
                            Text(domain)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Nightglass.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
                .font(.system(size: 12.5, weight: .medium))
            }

            Divider()

            PrivacyControls()

            Button {
                dismiss()
                store.isCookieManagerVisible = true
            } label: {
                Label("Manage Cookies and Site Data…", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Nightglass.accent)
        }
        .padding(18)
        .frame(width: 350)
    }
}

/// The privacy switches. Used in the shield panel and in Settings (⌘,).
struct PrivacyControls: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            SettingRow("Block trackers and ads") {
                Picker("Blocking level", selection: store.privacyBinding(\.blockingLevel)) {
                    ForEach(BlockingLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }
            SettingRow("Block pop-ups") {
                Toggle("Block pop-ups", isOn: store.privacyBinding(\.blockPopups))
            }
            SettingRow("Block third-party cookies") {
                Toggle("Block third-party cookies", isOn: store.privacyBinding(\.blockThirdPartyCookies))
            }
            SettingRow("Upgrade connections to HTTPS") {
                Toggle("Upgrade connections to HTTPS", isOn: store.privacyBinding(\.upgradeToHTTPS))
            }
        }
        .toggleStyle(.switch)
        .tint(Nightglass.accent)
    }
}

/// A label on the left and a control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            control.labelsHidden()
        }
        .padding(.vertical, 7)
    }
}

/// A big number with a small label, like "31 Trackers".
struct StatTile: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(Nightglass.spring, value: value)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Nightglass.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }
}

/// "Pop-up blocked from example.com · Allow once" at the bottom of the window.
struct PopupBlockedToast: View {
    @Environment(BrowserStore.self) private var store
    let popup: BlockedPopup

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .foregroundStyle(Nightglass.claude)
                .accessibilityHidden(true)
            Text(popup.url.map { "Pop-up blocked from \(BrowserStore.siteName($0))" } ?? "Pop-up blocked")
                .font(.system(size: 13))
            if popup.url != nil {
                Button("Allow once") { store.allowBlockedPopup() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.18)))
            }
            Button { store.blockedPopup = nil } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(IconButtonStyle(size: 22))
            .help("Dismiss")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassPanel(cornerRadius: 14)
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}
