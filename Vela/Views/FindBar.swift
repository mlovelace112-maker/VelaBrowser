import AppKit
import SwiftUI
import WebKit

/// ⌘F: search for text on the current page, like Safari's Find bar.
/// Return finds the next match, Shift-Return the previous one, Esc closes.
struct FindBar: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab
    @State private var query = ""
    @State private var notFound = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Nightglass.mutedText)
                .accessibilityHidden(true)

            TextField("Find on page", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .onSubmit { find(backwards: NSEvent.modifierFlags.contains(.shift)) }
                .onChange(of: query) { find(backwards: false) }
                .frame(maxWidth: 320)

            if notFound && !query.isEmpty {
                Text("Not found")
                    .font(.system(size: 12))
                    .foregroundStyle(Nightglass.claude)
                    .transition(.opacity)
            }

            Button { find(backwards: true) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(IconButtonStyle(size: 24))
                .disabled(query.isEmpty)
                .help("Previous match (⇧↩)")
            Button { find(backwards: false) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(IconButtonStyle(size: 24))
                .disabled(query.isEmpty)
                .help("Next match (↩)")

            Spacer()

            Button("Done") { close() }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Nightglass.accent)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .animation(.easeOut(duration: 0.15), value: notFound)
        .onAppear { isFocused = true }
        .onChange(of: store.findBarFocusRequest) { isFocused = true }
    }

    private func find(backwards: Bool) {
        guard !query.isEmpty else {
            notFound = false
            return
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        tab.webView.find(query, configuration: configuration) { result in
            notFound = !result.matchFound
        }
    }

    private func close() {
        withAnimation(Nightglass.spring) { store.isFindBarVisible = false }
        // Clear the highlighted match.
        tab.webView.evaluateJavaScript("window.getSelection().removeAllRanges()")
    }
}
