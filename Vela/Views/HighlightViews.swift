import SwiftUI

/// Bookmarks ▸ Highlights & Notes (⇧⌘H): every passage you highlighted,
/// grouped by page, with its note. Click a page to open it.
struct HighlightsView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        let pages = filtered
        VStack(spacing: 0) {
            HStack {
                Label("Highlights & Notes", systemImage: "highlighter")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Rectangle().fill(Nightglass.stroke).frame(height: 1)

            if store.highlights.pages.isEmpty {
                ContentUnavailableView("No highlights yet", systemImage: "highlighter",
                                       description: Text("Select text on a page, right-click it and choose Highlight. Highlights come back whenever you open the page again."))
            } else if pages.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List {
                    ForEach(pages) { page in
                        Section {
                            ForEach(page.highlights) { highlight in
                                HighlightRow(highlight: highlight)
                            }
                        } header: {
                            Button {
                                if let url = URL(string: page.address) {
                                    store.open(url, inNewTab: true)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(page.title.isEmpty ? page.address : page.title)
                                        .lineLimit(1)
                                    Image(systemName: "arrow.up.right.square")
                                }
                            }
                            .buttonStyle(.plain)
                            .help(page.address)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 620, height: 520)
    }

    private var filtered: [HighlightedPage] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return store.highlights.pages }
        return store.highlights.pages.compactMap { page in
            let titleMatches = page.title.lowercased().contains(query) || page.address.lowercased().contains(query)
            var copy = page
            if !titleMatches {
                copy.highlights = page.highlights.filter {
                    $0.text.lowercased().contains(query) || $0.note.lowercased().contains(query)
                }
            }
            return copy.highlights.isEmpty ? nil : copy
        }
    }
}

/// One highlight: the passage, its note (editable) and a delete button.
private struct HighlightRow: View {
    @Environment(BrowserStore.self) private var store
    let highlight: Highlight
    @State private var note = ""
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 1, green: 0.84, blue: 0.36))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(highlight.text)
                    .font(.system(size: 13))
                    .lineLimit(6)
                    .textSelection(.enabled)
                TextField("Add a note", text: $note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Nightglass.mutedText)
                    .onSubmit { save() }
                Text(highlight.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Nightglass.mutedText)
            }
            Spacer(minLength: 0)
            Button {
                store.removeHighlight(highlight.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0.35)
            .help("Delete highlight")
        }
        .padding(.vertical, 4)
        .onHover { isHovered = $0 }
        .onAppear { note = highlight.note }
        .onDisappear { save() }
        .onChange(of: isHovered) { _, hovered in if !hovered { save() } }
    }

    private func save() {
        if note != highlight.note { store.setHighlightNote(note, for: highlight.id) }
    }
}

/// Right-click ▸ Highlight with Note…: a small sheet to write the note.
struct HighlightNoteSheet: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Note", systemImage: "note.text")
                .font(.system(size: 14, weight: .semibold))
            if let highlight = store.highlights.highlight(id) {
                Text("“\(highlight.text)”")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Nightglass.mutedText)
                    .lineLimit(4)
            }
            TextEditor(text: $note)
                .font(.system(size: 13))
                .frame(height: 110)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.setHighlightNote(note, for: id)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 400)
        .onAppear { note = store.highlights.highlight(id)?.note ?? "" }
    }
}

/// Lets `.sheet(item:)` take the note editor's highlight id.
struct EditingHighlight: Identifiable {
    let id: UUID
}
