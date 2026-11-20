import SwiftUI

/// History ▸ Find a Page I've Seen (⌥⌘Y): describe a page in your own words
/// ("the lemon chicken recipe from Tuesday") and Vela finds it.
///
/// Vela searches the pages it remembers on your Mac first. Then Claude reads
/// only your question and short excerpts of the best few matches, and points
/// at the right one.
struct PageFinderView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var matches: [RememberedPage] = []
    @State private var answer = ""
    @State private var picked: [URL] = []
    @State private var isAsking = false
    @State private var error: String?
    @State private var searched = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Nightglass.accent)
                TextField("Describe a page you've seen, like “the lemon chicken recipe from Tuesday”", text: $question)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isFocused)
                    .onSubmit(find)
                if isAsking { ProgressView().controlSize(.small) }
                Button("Done") { dismiss() }
            }
            .padding(.horizontal, 18)
            .frame(height: 56)

            Rectangle().fill(Nightglass.stroke).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !store.pageMemory.isEnabled {
                        note("Page memory is off. Turn it on in Settings ▸ Privacy ▸ Page memory.")
                    } else if store.pageMemory.pages.isEmpty {
                        note("Vela hasn't remembered any pages yet. It starts with the pages you visit from now on.")
                    } else if !searched {
                        note("Vela remembers the words on \(store.pageMemory.pages.count.formatted()) pages you've visited, only on this Mac. Private tabs, the Banking container and pages with password boxes are never remembered.")
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Nightglass.caution)
                    }
                    if !answer.isEmpty {
                        Label {
                            Text(answer).textSelection(.enabled)
                        } icon: {
                            Image(systemName: "sparkle").foregroundStyle(Nightglass.claude)
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Nightglass.text)
                    }
                    if searched && matches.isEmpty {
                        note("No remembered pages match that. Try other words, or a different day.")
                    }
                    ForEach(ordered) { page in
                        PageMatchRow(page: page, isPick: picked.contains(page.url)) {
                            dismiss()
                            store.open(page.url, inNewTab: store.selectedTab?.url != nil)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 640, height: 520)
        .background(Nightglass.background)
        .onAppear {
            if !store.pageFinderQuestion.isEmpty {
                question = store.pageFinderQuestion
                store.pageFinderQuestion = ""
                find()
            }
            DispatchQueue.main.async { isFocused = true }
        }
    }

    /// Claude's picks first, then the other matches.
    private var ordered: [RememberedPage] {
        let picks = picked.compactMap { url in matches.first { $0.url == url } }
        return picks + matches.filter { !picked.contains($0.url) }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Nightglass.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func find() {
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty, !isAsking else { return }
        matches = store.pageMemory.search(asked)
        searched = true
        answer = ""
        picked = []
        error = nil
        guard !matches.isEmpty, store.claude.hasKey else { return }

        let listing = matches.enumerated().map { index, page in
            """
            [\(index + 1)] \(page.title)
            Address: \(page.url.absoluteString)
            Visited: \(page.date.formatted(date: .complete, time: .shortened))
            Excerpt: \(PageMemory.excerpt(of: page, for: asked))
            """
        }.joined(separator: "\n\n")
        let request = ClaudeRequest(
            model: .haiku,
            system: """
            You help someone find a web page they visited before. You get their description and a few \
            candidate pages from their own browsing history (with excerpts). Today is \
            \(Date().formatted(date: .complete, time: .omitted)). Reply with JSON only, no other text: \
            {"answer": "one or two sentences naming the most likely page and why, or saying none fit", \
            "pages": [numbers of the matching candidates, best first, empty if none fit]}
            """,
            messages: [["role": "user", "content": "I'm looking for: \(asked)\n\nCandidates:\n\n\(listing)"]],
            maxTokens: 600,
            effort: "low"
        )
        isAsking = true
        let candidates = matches
        Task {
            defer { isAsking = false }
            do {
                let response = try await ClaudeClient.stream(request) { _ in }
                guard let reply = Self.parse(response.text) else {
                    answer = response.text
                    return
                }
                answer = reply.answer
                picked = reply.pages.compactMap { candidates.indices.contains($0 - 1) ? candidates[$0 - 1].url : nil }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private struct Reply: Decodable {
        var answer: String
        var pages: [Int]
    }

    private static func parse(_ text: String) -> Reply? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        return try? JSONDecoder().decode(Reply.self, from: Data(text[start...end].utf8))
    }
}

private struct PageMatchRow: View {
    let page: RememberedPage
    let isPick: Bool
    let open: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            FaviconView(url: page.url, size: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(page.title.isEmpty ? page.url.absoluteString : page.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Nightglass.text)
                        .lineLimit(1)
                    if isPick {
                        Text("Best match")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Nightglass.claude)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Nightglass.claude.opacity(0.16)))
                    }
                }
                Text("\(page.url.host() ?? "") · \(page.date.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11))
                    .foregroundStyle(Nightglass.mutedText)
                Text(String(page.text.prefix(180)))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(isHovering ? 0.08 : (isPick ? 0.05 : 0))))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: open)
    }
}

/// Settings ▸ Privacy ▸ Page memory.
struct PageMemorySettingsSection: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        @Bindable var memory = store.pageMemory
        Section {
            Toggle(isOn: $memory.isEnabled) {
                Text("Remember the words on pages I visit")
                Text("Lets History ▸ Find a Page I've Seen (⌥⌘Y) search what you read. Saved only on this Mac. Turning this off forgets everything.")
            }
            LabeledContent("Remembered", value: "\(store.pageMemory.pages.count.formatted()) pages")
            Button("Forget All Remembered Pages", role: .destructive) { store.pageMemory.clear() }
                .disabled(store.pageMemory.pages.isEmpty)
        } header: {
            Text("Page memory")
        }
        .toggleStyle(.switch)
        .tint(Nightglass.accent)
    }
}
