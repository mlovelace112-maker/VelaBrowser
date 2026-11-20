import SwiftUI
import WebKit

/// Toolbar buttons for running Safari extensions, next to the address bar.
struct ExtensionToolbarButtons: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        let extensions = store.extensions
        // Read so the buttons redraw when an icon or badge changes.
        let _ = extensions.revision
        ForEach(extensions.running, id: \.bundleID) { item in
            ExtensionButton(bundleID: item.bundleID, context: item.context)
        }
    }
}

private struct ExtensionButton: View {
    @Environment(BrowserStore.self) private var store
    let bundleID: String
    let context: WKWebExtensionContext
    @State private var frame: CGRect = .zero

    var body: some View {
        let extensions = store.extensions
        let action = extensions.action(for: context)
        let icon = action?.icon(for: CGSize(width: 16, height: 16)) ?? context.webExtension.icon(for: CGSize(width: 16, height: 16))
        let waiting = extensions.requests.contains { $0.bundleID == bundleID && $0.tabID == store.selectedTabID }

        Button { extensions.click(bundleID, anchor: frame) } label: {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 16, height: 16)
                } else {
                    Image(systemName: "puzzlepiece.extension")
                }
            }
            .overlay(alignment: .topTrailing) {
                if let badge = action?.badgeText, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(Nightglass.danger))
                        .offset(x: 7, y: -6)
                } else if waiting {
                    Circle().fill(Nightglass.caution).frame(width: 6, height: 6).offset(x: 4, y: -3)
                }
            }
        }
        .buttonStyle(IconButtonStyle(size: 28))
        .disabled(action?.isEnabled == false)
        .help(action?.label ?? extensions.name(of: bundleID))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
    }
}

/// "Grammarly wants to read and change this site." Shown over the page.
struct ExtensionAccessBanner: View {
    @Environment(BrowserStore.self) private var store
    let request: ExtensionAccessRequest

    var body: some View {
        let extensions = store.extensions
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("**\(request.name)** wants to read and change \(request.host)")
            } icon: {
                Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(Nightglass.accent)
            }
            .font(.system(size: 13))
            .foregroundStyle(Nightglass.text)
            Text("It could see what you type and read on this site.")
                .font(.system(size: 11.5))
                .foregroundStyle(Nightglass.mutedText)
            HStack(spacing: 8) {
                Button("Don't Allow") { extensions.answer(request, .never) }
                Button("Allow Today") { extensions.answer(request, .today) }
                Button("Always Allow on This Site") { extensions.answer(request, .always) }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 400, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Nightglass.stroke))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }
}

/// Settings ▸ Extensions.
struct ExtensionSettingsTab: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        let extensions = store.extensions
        Form {
            Section {
                if extensions.found.isEmpty {
                    Text("No Safari extensions were found. Install one from the Mac App Store (search for the extension's name with \"Safari\"), then click Look Again.")
                        .foregroundStyle(.secondary)
                }
                ForEach(extensions.found) { item in
                    ExtensionRow(item: item)
                }
            } header: {
                Text("Safari extensions on this Mac")
            } footer: {
                Text("Extensions ask before they can read a site, and never run in private tabs. Older Safari extensions that only work inside Safari are marked Not compatible.")
            }
            Button("Look Again") { extensions.refresh() }
        }
        .formStyle(.grouped)
        .onAppear { extensions.refresh() }
    }
}

private struct ExtensionRow: View {
    @Environment(BrowserStore.self) private var store
    let item: FoundExtension

    var body: some View {
        let extensions = store.extensions
        VStack(alignment: .leading, spacing: 6) {
            if item.isWebExtension {
                Toggle(isOn: Binding(get: { extensions.isEnabled(item) }, set: { extensions.setEnabled(item, $0) })) {
                    Text(item.name)
                    Text("From \(item.appName)")
                }
            } else {
                LabeledContent {
                    Text("Not compatible").foregroundStyle(.secondary)
                } label: {
                    Text(item.name)
                    Text("From \(item.appName). This older kind of extension only runs inside Safari.")
                }
            }
            if let problem = extensions.problems[item.bundleID] {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(Nightglass.caution)
            }
            let sites = extensions.allowedSites(for: item.bundleID)
            if !sites.isEmpty {
                Text("Always allowed on:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ForEach(sites, id: \.self) { host in
                    HStack {
                        Text(host).font(.system(size: 11.5))
                        Spacer()
                        Button("Remove") { extensions.forgetSite(host, for: item.bundleID) }
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}
