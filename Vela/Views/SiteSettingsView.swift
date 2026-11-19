import SwiftUI

// MARK: - Site Settings (per-site permissions)

/// One page with every choice you've made for a website: camera,
/// microphone, pop-ups, JavaScript, the shield, sign-in, insecure access,
/// kept cookies and passwords. Open it from the shield panel or Settings ▸ Sites.
struct SiteSettingsList: View {
    @Environment(BrowserStore.self) private var store
    @State private var search = ""

    var body: some View {
        let sites = store.privacy.customizedSites.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }

        Form {
            if store.privacy.customizedSites.isEmpty {
                Section {
                    Text("No site settings yet. When you allow a site to use the camera, turn the shield off, change its JavaScript and so on, it shows up here.")
                        .foregroundStyle(Nightglass.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Section {
                    TextField("Search sites", text: $search)
                }
                ForEach(sites, id: \.self) { site in
                    SiteSection(site: site)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// All the switches for one website.
private struct SiteSection: View {
    @Environment(BrowserStore.self) private var store
    let site: String

    var body: some View {
        let privacy = store.privacy

        Section {
            ForEach(PermissionKind.allCases) { kind in
                Picker(selection: Binding(
                    get: { Answer(privacy.permission(kind, for: site)) },
                    set: { answer in store.updatePrivacy { $0.setPermission(kind, answer.value, for: site) } }
                )) {
                    ForEach(Answer.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label(kind.title, systemImage: kind.icon)
                }
            }
            Toggle(isOn: Binding(
                get: { privacy.popupAllowedSites.contains(site) },
                set: { store.setPopupsAllowed($0, for: site) }
            )) {
                Label("Allow pop-ups", systemImage: "macwindow.on.rectangle")
            }
            Picker(selection: Binding(
                get: { privacy.scriptLevel(for: site) },
                set: { level in store.updatePrivacy { $0.siteScriptLevels[site] = level == $0.scriptLevel ? nil : level } }
            )) {
                ForEach(ScriptLevel.allCases) { Text($0.shortTitle).tag($0) }
            } label: {
                Label("JavaScript", systemImage: "curlybraces")
            }
            toggle("Shield on", icon: "checkmark.shield", isOn: !privacy.shieldsDownSites.contains(site)) { on in
                store.updatePrivacy { if on { $0.shieldsDownSites.remove(site) } else { $0.shieldsDownSites.insert(site) } }
            }
            toggle("Allow sign-in cookies", icon: "person.badge.key", isOn: privacy.signInSites.contains(site)) { on in
                store.updatePrivacy { if on { $0.signInSites.insert(site) } else { $0.signInSites.remove(site) } }
            }
            toggle("Allow without a secure connection", icon: "lock.open", isOn: privacy.httpAllowedSites.contains(site)) { on in
                store.updatePrivacy { if on { $0.httpAllowedSites.insert(site) } else { $0.httpAllowedSites.remove(site) } }
            }
            toggle("Keep cookies when clearing", icon: "pin", isOn: privacy.keptSites.contains(site)) { on in
                store.updatePrivacy { if on { $0.keptSites.insert(site) } else { $0.keptSites.remove(site) } }
            }
            toggle("Offer to save passwords", icon: "key", isOn: !privacy.neverSavePasswordSites.contains(site)) { on in
                store.updatePrivacy { if on { $0.neverSavePasswordSites.remove(site) } else { $0.neverSavePasswordSites.insert(site) } }
            }
        } header: {
            HStack {
                Text(site)
                Spacer()
                Button("Reset") { store.updatePrivacy { $0.forget(site: site) } }
                    .controlSize(.small)
                    .help("Forget every choice for \(site)")
            }
        }
        .toggleStyle(.switch)
        .tint(Nightglass.accent)
    }

    private func toggle(_ title: String, icon: String, isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: set)) {
            Label(title, systemImage: icon)
        }
    }

    /// Ask / Allow / Block, for the camera and microphone pickers.
    private enum Answer: String, CaseIterable, Identifiable {
        case ask, allow, block
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var value: Bool? { self == .ask ? nil : self == .allow }
        init(_ value: Bool?) { self = value == nil ? .ask : (value! ? .allow : .block) }
    }
}

/// Site Settings as its own window-sized sheet (from the shield panel).
struct SiteSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Site Settings").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            SiteSettingsList()
        }
        .frame(width: 520, height: 600)
    }
}

// MARK: - Camera and microphone banner

/// "zoom.us wants to use your camera" over the page.
struct PermissionBanner: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab
    let request: PermissionRequest
    @State private var remember = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: request.kinds.first?.icon ?? "video.fill")
                    .foregroundStyle(Nightglass.caution)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Nightglass.caution.opacity(0.18)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use your \(request.description)?")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text("\(request.site) is asking.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Nightglass.mutedText)
                        .lineLimit(1)
                }
            }
            if !tab.isPrivate {
                Toggle("Remember for \(request.site)", isOn: $remember)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Don't Allow") { store.answerPermission(in: tab, allow: false, remember: remember) }
                Button("Allow") { store.answerPermission(in: tab, allow: true, remember: remember) }
                    .buttonStyle(.borderedProminent)
                    .tint(Nightglass.accent)
            }
            .font(.system(size: 12))
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 340)
        .glassPanel(cornerRadius: 14)
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}

// MARK: - Settings sections

/// Settings ▸ General ▸ Tabs: session restore and tab sleeping.
struct TabsSettingsSection: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        @Bindable var store = store

        Section {
            Toggle(isOn: $store.restoresSession) {
                Text("Reopen my tabs when Vela starts")
                Text("Private tabs are never saved. Reopened tabs load when you click them.")
            }
            Picker(selection: $store.tabSleepMinutes) {
                Text("Never").tag(0)
                Text("After 15 minutes").tag(15)
                Text("After 30 minutes").tag(30)
                Text("After 1 hour").tag(60)
                Text("After 2 hours").tag(120)
            } label: {
                Text("Put unused tabs to sleep")
                Text("Frees memory and battery. Pinned tabs and tabs playing sound or using the camera stay awake.")
            }
            if store.sleepingTabCount > 0 {
                LabeledContent("Sleeping now", value: "\(store.sleepingTabCount) tabs")
            }
        } header: {
            Text("Tabs")
        }
        .toggleStyle(.switch)
        .tint(Nightglass.accent)
    }
}

/// Settings ▸ Privacy ▸ Email masking (DuckDuckGo).
struct EmailMaskingSection: View {
    @Environment(BrowserStore.self) private var store
    @State private var address = ""
    @State private var passphrase = ""

    var body: some View {
        let masking = store.emailMasking

        Section {
            if masking.isConnected {
                HStack {
                    Label("Connected as \(masking.username ?? "your Duck Address")@duck.com", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Nightglass.safe)
                    Spacer()
                    Button("Sign Out") { masking.signOut() }
                        .controlSize(.small)
                }
                Text("On a sign-up form, press ⌥⌘E (or ••• ▸ Fill Private Email Address). Vela makes a new address, fills it in and copies it.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if masking.isWaitingForPassphrase {
                Text("DuckDuckGo emailed a one-time passphrase to the inbox your Duck Address forwards to. Paste it here.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField("Passphrase", text: $passphrase)
                    Button("Sign In") { Task { await masking.signIn(passphrase: passphrase) } }
                        .disabled(passphrase.trimmingCharacters(in: .whitespaces).isEmpty || masking.isWorking)
                }
            } else {
                HStack {
                    TextField("yourname@duck.com", text: $address)
                    Button("Email Me a Passphrase") { Task { await masking.sendPassphrase(to: address) } }
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || masking.isWorking)
                }
            }
            if masking.isWorking { ProgressView().controlSize(.small) }
            if let error = masking.errorMessage {
                Text(error).foregroundStyle(Nightglass.danger).font(.system(size: 12))
            }
        } header: {
            Text("Email masking")
        } footer: {
            if !masking.isConnected {
                Text("Give sites a private @duck.com address instead of your real one. DuckDuckGo forwards the mail to you, and you can turn off any address that gets spam. It's free: make a Duck Address at duckduckgo.com/email.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
            }
        }
    }
}

/// Settings ▸ Security ▸ Download scanning (VirusTotal).
struct DownloadScanSection: View {
    @Environment(BrowserStore.self) private var store
    @State private var keyDraft = ""

    var body: some View {
        let virusTotal = store.downloadManager.virusTotal

        Section {
            Toggle(isOn: store.privacyBinding(\.scanDownloads)) {
                Text("Scan downloads with VirusTotal")
                Text("Checks each finished download against about 70 antivirus engines. Only the file's SHA-256 fingerprint is sent, never the file.")
            }
            .toggleStyle(.switch)
            .tint(Nightglass.accent)
            if virusTotal.hasKey {
                HStack {
                    Label("API key saved in your Keychain", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Nightglass.safe)
                    Spacer()
                    Button("Remove Key") { virusTotal.setKey("") }
                        .controlSize(.small)
                }
            } else {
                HStack {
                    SecureField("Paste your VirusTotal API key", text: $keyDraft)
                    Button("Save") {
                        virusTotal.setKey(keyDraft)
                        keyDraft = ""
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        } header: {
            Text("Download scanning")
        } footer: {
            if !virusTotal.hasKey {
                Text("Get a free key: sign up at virustotal.com, then click your name ▸ API Key. The free key allows 4 lookups a minute.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
            }
        }
    }
}
