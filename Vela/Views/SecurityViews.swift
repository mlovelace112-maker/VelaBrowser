import AppKit
import SwiftUI

// MARK: - Link checker

/// The little bubble at the bottom of the page that shows where the link
/// under your mouse goes, with the link checker's verdict.
struct LinkStatusBubble: View {
    let url: URL

    var body: some View {
        let report = LinkChecker.check(url)
        let color = Self.color(for: report.verdict)

        HStack(spacing: 7) {
            Image(systemName: Self.icon(for: report.verdict))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(url.absoluteString)
                .foregroundStyle(Nightglass.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            if report.verdict != .safe, let reason = report.reasons.first {
                Text(reason)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 10)
        .frame(height: 26)
        .frame(maxWidth: 640, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .glassPanel(cornerRadius: 8)
        .allowsHitTesting(false)
    }

    static func color(for verdict: LinkVerdict) -> Color {
        switch verdict {
        case .safe: Nightglass.safe
        case .caution: Nightglass.caution
        case .dangerous: Nightglass.danger
        }
    }

    static func icon(for verdict: LinkVerdict) -> String {
        switch verdict {
        case .safe: "checkmark.shield.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .dangerous: "xmark.shield.fill"
        }
    }
}

/// Covers the page when the link checker stops a dangerous link.
struct LinkWarningView: View {
    let tab: BrowserTab
    let warning: LinkWarning

    var body: some View {
        ZStack {
            NightglassBackdrop()
            RadialGradient(
                colors: [Nightglass.danger.opacity(0.22), .clear],
                center: .top, startRadius: 0, endRadius: 520
            )

            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "xmark.shield.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Nightglass.danger)
                    .accessibilityHidden(true)

                Text("Vela stopped a dangerous link")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))

                Text(warning.url.host() ?? warning.url.absoluteString)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Nightglass.secondaryText)
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(warning.report.reasons, id: \.self) { reason in
                        Label(reason, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 13))
                            .foregroundStyle(Nightglass.text)
                    }
                }

                Text("Pages like this often copy real websites to steal passwords or card numbers.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Nightglass.mutedText)

                HStack(spacing: 12) {
                    Button("Go Back") { tab.dismissLinkWarning() }
                        .buttonStyle(.borderedProminent)
                        .tint(Nightglass.accent)
                        .keyboardShortcut(.defaultAction)
                    Button("Open Anyway") { tab.openDangerousLinkAnyway() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Nightglass.danger)
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 520, alignment: .leading)
            .glassPanel(cornerRadius: 18)
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        }
    }
}

// MARK: - Downloads

/// The toolbar's downloads button, with a ring that fills as files download.
struct DownloadsButton: View {
    @Environment(BrowserStore.self) private var store
    @State private var isOpen = false

    var body: some View {
        let manager = store.downloadManager

        Button { isOpen.toggle() } label: {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(manager.activeCount > 0 ? Nightglass.accent : Nightglass.secondaryText)
                .overlay {
                    if manager.activeCount > 0 {
                        Circle()
                            .trim(from: 0, to: max(0.03, manager.overallProgress))
                            .stroke(Nightglass.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 22, height: 22)
                            .animation(.easeOut(duration: 0.25), value: manager.overallProgress)
                    }
                }
        }
        .buttonStyle(IconButtonStyle())
        .help("Downloads")
        .accessibilityLabel("Downloads")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            DownloadsPopover()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}

struct DownloadsPopover: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        let manager = store.downloadManager

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Downloads").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Clear") { manager.clearFinished() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Nightglass.accent)
                    .disabled(manager.items.allSatisfy { $0.state == .downloading })
            }

            if manager.items.isEmpty {
                Text("Nothing downloaded yet.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Nightglass.mutedText)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(manager.items) { item in
                            DownloadRow(item: item)
                        }
                    }
                }
                .frame(maxHeight: 340)
            }

            Text("Files are checked before saving and marked as downloaded from the internet, so macOS scans apps before they open.")
                .font(.system(size: 11))
                .foregroundStyle(Nightglass.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 380)
    }
}

private struct DownloadRow: View {
    @Environment(BrowserStore.self) private var store
    let item: DownloadItem

    var body: some View {
        let manager = store.downloadManager

        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.state == .downloading {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .tint(Nightglass.accent)
                }
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(item.state == .finished || item.state == .downloading ? Nightglass.mutedText : color)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            switch item.state {
            case .downloading:
                Button { manager.cancel(item) } label: { Image(systemName: "xmark") }
                    .buttonStyle(IconButtonStyle(size: 24))
                    .help("Cancel")
            case .finished:
                Button { manager.reveal(item) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(IconButtonStyle(size: 24))
                    .help("Show in Finder")
            default:
                EmptyView()
            }
        }
        .padding(8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if item.state == .finished { manager.open(item) } }
    }

    private var status: String {
        switch item.state {
        case .downloading: "\(Int((item.progress * 100).rounded()))%"
        case .finished: "Saved to Downloads"
        case .failed(let reason): "Failed: \(reason)"
        case .blocked(let reason): "Blocked. \(reason)"
        case .cancelled: "Cancelled"
        }
    }

    private var icon: String {
        switch item.state {
        case .downloading: "arrow.down.circle"
        case .finished: "doc.fill"
        case .failed: "exclamationmark.circle"
        case .blocked: "xmark.shield.fill"
        case .cancelled: "minus.circle"
        }
    }

    private var color: Color {
        switch item.state {
        case .downloading, .finished: Nightglass.accent
        case .failed, .cancelled: Nightglass.mutedText
        case .blocked: Nightglass.danger
        }
    }
}

// MARK: - Passwords

/// "Save password for example.com?" after you sign in somewhere.
struct PasswordSaveBanner: View {
    @Environment(BrowserStore.self) private var store
    let prompt: PasswordPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .foregroundStyle(Nightglass.accent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Nightglass.accent.opacity(0.18)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(prompt.isUpdate ? "Update saved password?" : "Save password?")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(prompt.account.isEmpty ? prompt.server : "\(prompt.account) · \(prompt.server)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Nightglass.mutedText)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 8) {
                Button("Never for This Site") { store.neverSavePasswords(for: prompt.server) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Nightglass.mutedText)
                Spacer()
                Button("Not Now") { store.passwordPrompt = nil }
                Button(prompt.isUpdate ? "Update" : "Save") { store.savePromptedPassword() }
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

// MARK: - Settings

/// The Security tab of Settings (⌘,).
struct SecuritySettingsTab: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        let privacy = store.privacy

        Form {
            Section {
                ScriptSlider(level: store.privacyBinding(\.scriptLevel))
                    .padding(.vertical, 4)
            } header: {
                Text("JavaScript on all sites")
            } footer: {
                Text("Change one site from the shield button in the toolbar.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
            }

            if !privacy.siteScriptLevels.isEmpty {
                Section("JavaScript site settings") {
                    ForEach(privacy.siteScriptLevels.keys.sorted(), id: \.self) { site in
                        HStack {
                            Text(site)
                            Spacer()
                            Text(privacy.siteScriptLevels[site]?.shortTitle ?? "")
                                .foregroundStyle(Nightglass.mutedText)
                            Button("Reset") {
                                store.updatePrivacy { $0.siteScriptLevels[site] = nil }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }

            Section("Links") {
                Toggle(isOn: store.privacyBinding(\.linkCheckerEnabled)) {
                    Text("Check links when I point at them")
                    Text("Shows where a link goes, and whether it looks safe, at the bottom of the page")
                }
                Toggle(isOn: store.privacyBinding(\.warnBeforeDangerousLinks)) {
                    Text("Stop dangerous links")
                    Text("Shows a warning instead of opening pages that look like scams")
                }
                .disabled(!privacy.linkCheckerEnabled)
            }

            Section("Downloads") {
                Toggle(isOn: store.privacyBinding(\.blockDangerousDownloads)) {
                    Text("Block dangerous downloads")
                    Text("Blocks Windows programs, disguised files and downloads from ad networks, and asks before saving apps and installers")
                }
                Button("Open Downloads Folder") {
                    if let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                        NSWorkspace.shared.open(folder)
                    }
                }
            }

            Section("Passwords") {
                Toggle("Offer to save passwords", isOn: store.privacyBinding(\.offerToSavePasswords))
                Button("Open Passwords…") { store.isPasswordsVisible = true }
                if !privacy.neverSavePasswordSites.isEmpty {
                    ForEach(privacy.neverSavePasswordSites.sorted(), id: \.self) { site in
                        HStack {
                            Text("Never save for \(site)")
                            Spacer()
                            Button("Remove") {
                                store.updatePrivacy { $0.neverSavePasswordSites.remove(site) }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .tint(Nightglass.accent)
    }
}
