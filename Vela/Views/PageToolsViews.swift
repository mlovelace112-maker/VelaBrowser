import SwiftUI

/// The sheet for Claude's page tools: Compare Tabs, Video Summary and
/// Is This Site Legit? (see ClaudePageTools.swift).
struct PageToolSheet: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let initial: PageToolState

    /// The live state (it fills in while Claude works).
    private var state: PageToolState { store.pageTool ?? initial }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Nightglass.stroke).frame(height: 1)
            ScrollView {
                content
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: state.kind == .compare ? 760 : 560, height: state.kind == .compare ? 560 : 500)
        .background(Nightglass.background)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Nightglass.claude)
            Text(state.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Nightglass.text)
            Spacer()
            if state.isWorking { ProgressView().controlSize(.small) }
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private var icon: String {
        switch state.kind {
        case .compare: "tablecells"
        case .video: "play.rectangle"
        case .siteCheck: "checkmark.shield"
        }
    }

    @ViewBuilder private var content: some View {
        if let error = state.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.system(size: 13))
                .foregroundStyle(Nightglass.caution)
                .fixedSize(horizontal: false, vertical: true)
        } else if state.isWorking {
            Text(workingText)
                .font(.system(size: 13))
                .foregroundStyle(Nightglass.mutedText)
        } else if let comparison = state.comparison {
            ComparisonView(comparison: comparison)
        } else if let video = state.video {
            VideoSummaryView(summary: video) { store.seekVideo(to: $0) }
        } else if let check = state.siteCheck {
            SiteCheckView(check: check)
        } else if state.kind == .compare {
            TabPicker()
        }
    }

    private var workingText: String {
        switch state.kind {
        case .compare: "Claude is reading the tabs and building a table…"
        case .video: "Claude is reading the video's captions…"
        case .siteCheck: "Vela is checking the site, then Claude weighs it up…"
        }
    }
}

/// Pick the tabs to compare.
private struct TabPicker: View {
    @Environment(BrowserStore.self) private var store
    @State private var picked: Set<UUID> = []

    var body: some View {
        let tabs = store.comparableTabs
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick 2 to 6 tabs, like products, recipes or plans you're choosing between. Claude reads them and makes a side-by-side table. Private tabs and pages with password boxes are left out.")
                .font(.system(size: 12.5))
                .foregroundStyle(Nightglass.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            if tabs.count < 2 {
                Text("Open at least two web pages first.")
                    .font(.system(size: 13))
                    .foregroundStyle(Nightglass.secondaryText)
            }
            ForEach(tabs) { tab in
                Toggle(isOn: binding(for: tab.id)) {
                    HStack(spacing: 8) {
                        if let url = tab.url { FaviconView(url: url, size: 16) }
                        Text(tab.title).lineLimit(1)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!picked.contains(tab.id) && picked.count >= 6)
            }
            HStack {
                Spacer()
                Button("Compare \(picked.count) Tabs") {
                    store.compare(tabs.filter { picked.contains($0.id) })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(picked.count < 2)
            }
        }
        .onAppear(perform: preselect)
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(get: { picked.contains(id) }, set: { on in
            if on { picked.insert(id) } else { picked.remove(id) }
        })
    }

    /// Starts with the tabs in the current tab's group, or the current tab's site.
    private func preselect() {
        let tabs = store.comparableTabs
        guard let current = store.selectedTab else { return }
        var guess = tabs.filter { current.groupID != nil && $0.groupID == current.groupID }
        if guess.count < 2, let host = current.url?.host() {
            guess = tabs.filter { $0.url?.host() == host }
        }
        if guess.count >= 2 { picked = Set(guess.prefix(6).map(\.id)) }
    }
}

private struct ComparisonView: View {
    let comparison: TabComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text(comparison.summary).textSelection(.enabled)
            } icon: {
                Image(systemName: "sparkle").foregroundStyle(Nightglass.claude)
            }
            .font(.system(size: 13))
            .foregroundStyle(Nightglass.text)
            .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        Text("")
                        ForEach(Array(comparison.columns.enumerated()), id: \.offset) { _, title in
                            Text(title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Nightglass.text)
                                .lineLimit(2)
                                .frame(width: 170, alignment: .leading)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(comparison.rows) { row in
                        ComparisonRow(row: row)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}

private struct ComparisonRow: View {
    let row: TabComparison.Row

    var body: some View {
        GridRow {
            Text(row.name)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Nightglass.mutedText)
                .frame(width: 120, alignment: .leading)
            ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                Text(value)
                    .font(.system(size: 12))
                    .foregroundStyle(value == "Not listed" ? Nightglass.mutedText : Nightglass.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 170, alignment: .leading)
            }
        }
    }
}

private struct VideoSummaryView: View {
    let summary: VideoSummary
    let seek: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(summary.summary)
                .font(.system(size: 13.5))
                .foregroundStyle(Nightglass.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !summary.fromTranscript {
                Text("This video has no captions, so Claude summarized its description instead.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.caution)
            }
            if !summary.moments.isEmpty {
                Text("Key moments (click to jump there)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Nightglass.mutedText)
                    .textCase(.uppercase)
                ForEach(summary.moments) { moment in
                    Button { seek(moment.seconds) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(moment.time)
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Nightglass.accent)
                                .frame(width: 56, alignment: .leading)
                            Text(moment.text)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Nightglass.secondaryText)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct SiteCheckView: View {
    let check: SiteCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(color)
                        .textCase(.uppercase)
                    Text(check.headline)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Nightglass.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.12)))

            list("Why", check.reasons, icon: "sparkle", tint: Nightglass.claude)
            list("What Vela checked", check.signals, icon: "checkmark.circle", tint: Nightglass.mutedText)
            Text("Claude can be wrong. When money or passwords are involved and you're unsure, go to the company's site by typing its address yourself.")
                .font(.system(size: 11))
                .foregroundStyle(Nightglass.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func list(_ title: String, _ items: [String], icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Nightglass.mutedText)
                .textCase(.uppercase)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Label {
                    Text(item).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: icon).foregroundStyle(tint)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Nightglass.secondaryText)
            }
        }
    }

    private var color: Color {
        switch check.verdict {
        case .safe: Nightglass.safe
        case .caution: Nightglass.caution
        case .danger: Nightglass.danger
        }
    }

    private var symbol: String {
        switch check.verdict {
        case .safe: "checkmark.shield.fill"
        case .caution: "exclamationmark.shield.fill"
        case .danger: "xmark.shield.fill"
        }
    }

    private var label: String {
        switch check.verdict {
        case .safe: "Looks legit"
        case .caution: "Be careful"
        case .danger: "Likely a scam"
        }
    }
}

/// The Claude menu: tools that read whole pages.
struct ClaudeToolsMenu: View {
    let store: BrowserStore

    var body: some View {
        Button("Compare Tabs…") { store.showCompareTabs() }
        Button("Summarize This Video") {
            if let tab = store.selectedTab { store.summarizeVideo(in: tab) }
        }
        .disabled(!BrowserStore.isYouTubeVideo(store.selectedTab?.url))
        Button("Is This Site Legit?") {
            if let tab = store.selectedTab { store.checkSite(in: tab) }
        }
        .disabled(store.selectedTab?.url == nil)
        Divider()
        Button("Organize Bookmarks with Claude") { store.organizeBookmarks() }
            .disabled(store.bookmarks.count < 3 || store.isOrganizingBookmarks)
    }
}
