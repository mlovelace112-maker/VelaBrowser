import SwiftUI

/// "Cookies and site data": see what each website has stored, delete it,
/// and mark sites to keep (so you stay signed in when cookies are cleared on quit).
struct CookieManagerView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var confirmDeleteAll = false

    var body: some View {
        let manager = store.cookieManager
        let sites = manager.sites.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Cookies and Site Data")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Nightglass.mutedText)
                    .accessibilityHidden(true)
                TextField("Search sites", text: $search)
                    .textFieldStyle(.plain)
                Text("\(manager.sites.count) sites")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.35)))

            ScrollView {
                LazyVStack(spacing: 2) {
                    if manager.isLoading && manager.sites.isEmpty {
                        ProgressView().padding(30)
                    } else if sites.isEmpty {
                        Text(search.isEmpty ? "No websites have stored anything yet." : "No matches.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Nightglass.mutedText)
                            .padding(30)
                    }
                    ForEach(sites) { site in
                        CookieRow(site: site)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack(spacing: 10) {
                Toggle("Clear cookies when I quit, except kept sites", isOn: store.privacyBinding(\.clearCookiesOnQuit))
                    .toggleStyle(.switch)
                    .tint(Nightglass.accent)
                    .font(.system(size: 12.5))
                Spacer()
                Button("Delete All Trackers") {
                    Task { await manager.deleteTrackers() }
                }
                .disabled(!manager.sites.contains(where: \.isTracker))
                Button("Delete All…", role: .destructive) { confirmDeleteAll = true }
                    .disabled(manager.sites.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 620, height: 540)
        .background(Nightglass.background)
        .task { await manager.reload() }
        .confirmationDialog("Delete cookies and data for all sites?", isPresented: $confirmDeleteAll) {
            Button("Delete All Except Kept Sites", role: .destructive) {
                Task { await manager.deleteAll(keeping: store.privacy.keptSites) }
            }
        } message: {
            Text("You'll be signed out of websites that aren't marked Keep.")
        }
    }
}

private struct CookieRow: View {
    @Environment(BrowserStore.self) private var store
    let site: SiteData
    @State private var isHovering = false

    var body: some View {
        let kept = store.isKept(site.name)

        HStack(spacing: 12) {
            FaviconView(url: URL(string: "https://\(site.name)"), size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(site.name).font(.system(size: 13.5))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
            }
            Spacer()
            if site.isTracker {
                Tag(text: "Tracker", color: Nightglass.claude)
            }
            Button { store.toggleKept(site.name) } label: {
                Label(kept ? "Kept" : "Keep", systemImage: kept ? "pin.fill" : "pin")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(kept ? Nightglass.spotify : Nightglass.secondaryText)
            }
            .buttonStyle(.plain)
            .help(kept ? "This site's cookies are kept when you quit" : "Keep this site's cookies when you quit")
            Button("Delete") {
                Task { await store.cookieManager.delete(site) }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(isHovering ? 0.05 : 0)))
        .onHover { isHovering = $0 }
    }

    private var detail: String {
        switch site.cookieCount {
        case 0: "Site data only"
        case 1: "1 cookie"
        default: "\(site.cookieCount) cookies"
        }
    }
}

private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.16)))
    }
}

/// The Privacy tab of Settings (⌘,).
struct PrivacySettingsTab: View {
    @Environment(BrowserStore.self) private var store
    @State private var showCookies = false

    var body: some View {
        Form {
            Section("Privacy and Security") {
                PrivacyControls()
                Toggle("Clear cookies when I quit, except kept sites", isOn: store.privacyBinding(\.clearCookiesOnQuit))
                    .toggleStyle(.switch)
                    .tint(Nightglass.accent)
                Button("Manage Cookies and Site Data…") { showCookies = true }
            }
            Section("Ads") {
                AdControls()
            }
            .toggleStyle(.switch)
            .tint(Nightglass.accent)
            Section("Blocked so far") {
                LabeledContent("Trackers and ads", value: "\(store.trackersBlockedTotal)")
                LabeledContent("Pop-ups", value: "\(store.popupsBlockedTotal)")
            }
            if !store.privacy.httpAllowedSites.isEmpty {
                Section("Allowed without a secure connection") {
                    ForEach(store.privacy.httpAllowedSites.sorted(), id: \.self) { site in
                        HStack {
                            Text(site)
                            Spacer()
                            Button("Remove") {
                                store.updatePrivacy { $0.httpAllowedSites.remove(site) }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            if !store.privacy.signInSites.isEmpty {
                Section("Sign-in allowed on") {
                    ForEach(store.privacy.signInSites.sorted(), id: \.self) { site in
                        HStack {
                            Text(site)
                            Spacer()
                            Button("Remove") {
                                store.updatePrivacy { $0.signInSites.remove(site) }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            if !store.privacy.shieldsDownSites.isEmpty {
                Section("Shield turned off for") {
                    ForEach(store.privacy.shieldsDownSites.sorted(), id: \.self) { site in
                        HStack {
                            Text(site)
                            Spacer()
                            Button("Turn Shield Back On") {
                                store.updatePrivacy { $0.shieldsDownSites.remove(site) }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showCookies) { CookieManagerView() }
    }
}
