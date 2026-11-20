import SwiftUI

/// The small player at the bottom of the page while Vela reads aloud.
struct ReadAloudBar: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        let player = store.readAloudPlayer
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(Nightglass.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(player.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Nightglass.text)
                    .lineLimit(1)
                ProgressView(value: player.progress)
                    .progressViewStyle(.linear)
                    .tint(Nightglass.accent)
            }
            .frame(width: 200)
            Button { player.togglePause() } label: {
                Image(systemName: player.state == .paused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(IconButtonStyle(size: 26))
            .help(player.state == .paused ? "Resume" : "Pause")
            Menu {
                ForEach(ReadAloud.rates, id: \.self) { rate in
                    Button {
                        player.setRate(rate)
                    } label: {
                        if rate == player.rate {
                            Label("\(rate.formatted())×", systemImage: "checkmark")
                        } else {
                            Text("\(rate.formatted())×")
                        }
                    }
                }
            } label: {
                Text("\(player.rate.formatted())×")
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Reading speed")
            Button { player.stop() } label: { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle(size: 26))
                .help("Stop reading")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Nightglass.stroke))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}

/// Claude ▸ Watch This Page…: watch the current page, and see every watched page.
struct WatchPagesSheet: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var instruction = ""
    @State private var everyHours: Double = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Watched Pages", systemImage: "eye")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Nightglass.text)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            Rectangle().fill(Nightglass.stroke).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    addSection
                    listSection
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 560, height: 520)
        .background(Nightglass.background)
    }

    @ViewBuilder private var addSection: some View {
        if let tab = store.selectedTab, tab.url != nil, !tab.isPrivate {
            VStack(alignment: .leading, spacing: 8) {
                Text("Watch \(tab.title)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Nightglass.text)
                    .lineLimit(1)
                TextField("What should Vela look for? Like “price drops below $50”. Leave empty for any change.", text: $instruction)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Picker("Check every", selection: $everyHours) {
                        Text("Hour").tag(1.0)
                        Text("6 hours").tag(6.0)
                        Text("Day").tag(24.0)
                    }
                    .fixedSize()
                    Spacer()
                    Button("Watch This Page") {
                        store.watchCurrentPage(instruction: instruction, everyHours: everyHours)
                        instruction = ""
                    }
                    .keyboardShortcut(.defaultAction)
                }
                Text("Vela checks while it's open and sends a notification. With something to look for, Claude compares the page's text before and now; pages with a password box are only checked for any change.")
                    .font(.system(size: 11))
                    .foregroundStyle(Nightglass.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var listSection: some View {
        if store.saved.watched.isEmpty {
            Text("You're not watching any pages yet.")
                .font(.system(size: 12.5))
                .foregroundStyle(Nightglass.mutedText)
        }
        ForEach(store.saved.watched) { page in
            WatchedRow(page: page)
        }
    }
}

private struct WatchedRow: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let page: WatchedPage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            FaviconView(url: page.url, size: 16).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title.isEmpty ? page.url.absoluteString : page.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Nightglass.text)
                    .lineLimit(1)
                Text(page.instruction.isEmpty ? "Any change" : page.instruction)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.secondaryText)
                    .lineLimit(2)
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(page.lastNews == nil ? Nightglass.mutedText : Nightglass.accent)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Open Page") {
                    dismiss()
                    store.open(page.url, inNewTab: true)
                }
                Button("Check Now") { Task { await store.check(page.id) } }
                Button(page.isPaused ? "Resume Watching" : "Pause Watching") {
                    if let index = store.saved.watched.firstIndex(where: { $0.id == page.id }) {
                        store.saved.watched[index].isPaused.toggle()
                    }
                }
                Divider()
                Button("Stop Watching", role: .destructive) { store.saved.watched.removeAll { $0.id == page.id } }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    private var statusLine: String {
        if page.isPaused { return "Paused" }
        if let news = page.lastNews, let date = page.lastNewsDate {
            return "\(news) (\(date.formatted(.relative(presentation: .named))))"
        }
        let every = "Checks every \(BrowserStore.describe(hours: page.everyHours))"
        guard let checked = page.lastChecked else { return every }
        return "\(every) · last checked \(checked.formatted(.relative(presentation: .named)))"
    }
}

/// Tabs ▸ Save Tabs as Workspace…
struct SaveWorkspaceSheet: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        let count = store.tabs.filter { !$0.isPrivate && $0.url != nil }.count
        VStack(alignment: .leading, spacing: 12) {
            Text("Save \(count) Tabs as a Workspace")
                .font(.system(size: 14, weight: .semibold))
            TextField("Name, like “Trip planning”", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Text("Open it again from Tabs ▸ Workspaces. Private tabs aren't saved.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || count == 0)
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.saveWorkspace(named: name)
        dismiss()
    }
}

/// Tabs ▸ Workspaces.
struct WorkspacesMenu: View {
    let store: BrowserStore

    var body: some View {
        Button("Save Tabs as Workspace…") { store.isWorkspaceSheetVisible = true }
        Menu("Workspaces") {
            if store.saved.workspaces.isEmpty {
                Text("No saved workspaces")
            }
            ForEach(store.saved.workspaces) { workspace in
                Menu("\(workspace.name) (\(workspace.pages.count))") {
                    Button("Open Tabs") { store.openWorkspace(workspace, replacing: false) }
                    Button("Switch to This Workspace") { store.openWorkspace(workspace, replacing: true) }
                    Divider()
                    Button("Delete Workspace") { store.deleteWorkspace(workspace) }
                }
            }
        }
    }
}
