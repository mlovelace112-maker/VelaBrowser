import AppKit
import SwiftUI

/// The Claude side panel on the right of the window (⇧⌘A): chat with Claude
/// and let it work with your tabs.
struct ClaudePanel: View {
    @Environment(BrowserStore.self) private var store
    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        let claude = store.claude

        VStack(spacing: 0) {
            header(claude)
            Rectangle().fill(Nightglass.stroke).frame(height: 1)

            if claude.hasKey {
                conversation(claude)
                if let confirmation = claude.confirmation {
                    ConfirmationCard(confirmation: confirmation)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                inputBar(claude)
            } else {
                ClaudeKeySetup()
                    .padding(18)
                Spacer()
            }
        }
        .frame(width: 360)
        .background(VisualEffectBackground())
        .overlay(alignment: .leading) {
            Rectangle().fill(Nightglass.stroke).frame(width: 1)
        }
        .animation(Nightglass.spring, value: claude.confirmation)
        // Links in Claude's answers open in a new Vela tab.
        .environment(\.openURL, OpenURLAction { url in
            store.open(url, inNewTab: true)
            return .handled
        })
        .onAppear { isInputFocused = true }
    }

    private func header(_ claude: ClaudeAssistant) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Nightglass.claude)
                .accessibilityHidden(true)
            Text("Claude")
                .font(.system(size: 14, weight: .semibold))
            Picker("Model", selection: Binding(get: { claude.model }, set: { claude.setModel($0) })) {
                ForEach(ClaudeModel.allCases) { model in
                    Text(model.name).tag(model)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .help("Choose a model. Switching starts a new chat.")
            Spacer()
            Button { claude.newChat() } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(IconButtonStyle(size: 26))
                .disabled(claude.messages.isEmpty)
                .help("New Chat")
            Button { store.isClaudePanelVisible = false } label: { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle(size: 26))
                .help("Close Claude (⇧⌘A)")
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
    }

    private func conversation(_ claude: ClaudeAssistant) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if claude.messages.isEmpty {
                        EmptyChat { store.askClaudeInPanel($0) }
                    }
                    ForEach(claude.messages) { message in
                        ChatBubble(message: message)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if claude.isWorking && claude.confirmation == nil {
                        ThinkingDots()
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(14)
            }
            .onChange(of: claude.messages) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: claude.isWorking) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func inputBar(_ claude: ClaudeAssistant) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        return HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask Claude, or tell it what to do…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .lineLimit(1...6)
                .focused($isInputFocused)
                .onSubmit(send)
                .padding(.vertical, 5)

            if claude.isWorking {
                Button { claude.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .help("Stop")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0B0B12))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Nightglass.accent))
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Send")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(shape.fill(Color.black.opacity(0.35)))
        .overlay(shape.strokeBorder(isInputFocused ? Nightglass.claude.opacity(0.6) : Color.white.opacity(0.12)))
        .animation(.easeOut(duration: 0.2), value: isInputFocused)
        .padding(12)
    }

    private func send() {
        guard !store.claude.isWorking else { return }
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        store.claude.send(text)
    }
}

/// Suggestions shown before you've asked anything.
private struct EmptyChat: View {
    let ask: (String) -> Void

    private struct Suggestion {
        let icon: String
        let text: String
    }

    private static let suggestions = [
        Suggestion(icon: "doc.text.magnifyingglass", text: "Summarize this page"),
        Suggestion(icon: "folder", text: "Group my tabs by topic"),
        Suggestion(icon: "square.on.square", text: "Close tabs I have open twice"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What can I help with?")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("I can answer questions, read and summarize pages, open searches, and organize your tabs. I'll ask before closing anything or sending a form.")
                .font(.system(size: 12.5))
                .foregroundStyle(Nightglass.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Self.suggestions, id: \.text) { suggestion in
                SuggestionButton(icon: suggestion.icon, text: suggestion.text) { ask(suggestion.text) }
            }
        }
        .padding(.top, 8)
    }
}

private struct SuggestionButton: View {
    let icon: String
    let text: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(text, systemImage: icon)
                .font(.system(size: 12.5))
                .foregroundStyle(Nightglass.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(isHovering ? 0.09 : 0.05))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

/// One message in the chat.
private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Nightglass.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Nightglass.accent.opacity(0.24))
                    )
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(message.actions) { action in
                    Label(action.text, systemImage: action.icon)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Nightglass.claude)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Nightglass.claude.opacity(0.12)))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                if !message.text.isEmpty {
                    ClaudeMarkdown(text: message.text)
                }
            }
        case .notice:
            Label(message.text, systemImage: message.isError ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(message.isError ? Nightglass.danger : Nightglass.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "Close 3 tabs?" with Allow and Don't Allow.
private struct ConfirmationCard: View {
    @Environment(BrowserStore.self) private var store
    let confirmation: ClaudeConfirmation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(confirmation.title, systemImage: "hand.raised.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Nightglass.caution)
            Text(confirmation.detail)
                .font(.system(size: 12))
                .foregroundStyle(Nightglass.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Don't Allow") { store.claude.answerConfirmation(false) }
                Button(confirmation.allowLabel) { store.claude.answerConfirmation(true) }
                    .buttonStyle(.borderedProminent)
                    .tint(Nightglass.accent)
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: 12)
    }
}

/// Where you paste your Anthropic API key.
struct ClaudeKeySetup: View {
    @Environment(BrowserStore.self) private var store
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Connect Claude", systemImage: "sparkle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Nightglass.text)
            Text("Vela talks to Claude with your own Anthropic API key. Usage is billed to your Anthropic account, separately from a Claude subscription.")
                .font(.system(size: 12.5))
                .foregroundStyle(Nightglass.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                .font(.system(size: 12.5))
            HStack {
                SecureField("Paste your API key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save", action: save)
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Your key is kept in your Mac's Keychain.")
                .font(.system(size: 11))
                .foregroundStyle(Nightglass.mutedText)
        }
    }

    private func save() {
        store.claude.setKey(key)
        key = ""
    }
}

/// Claude's answer to a question typed in the address bar.
struct QuickAnswerCard: View {
    @Environment(BrowserStore.self) private var store
    let answer: QuickAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Nightglass.claude)
                    .symbolEffect(.pulse, isActive: answer.isWorking)
                    .accessibilityHidden(true)
                Text(answer.question)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Nightglass.text)
                    .lineLimit(2)
                Spacer()
                Text("Haiku")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Nightglass.mutedText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                Button { store.claude.dismissQuickAnswer() } label: { Image(systemName: "xmark") }
                    .buttonStyle(IconButtonStyle(size: 24))
                    .help("Close")
            }

            if let error = answer.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Nightglass.danger)
                    .fixedSize(horizontal: false, vertical: true)
                if !store.claude.hasKey {
                    ClaudeKeySetup()
                }
            } else if answer.text.isEmpty {
                ThinkingDots()
            } else {
                // Short answers fit; long ones scroll.
                ViewThatFits(in: .vertical) {
                    ClaudeMarkdown(text: answer.text)
                    ScrollView { ClaudeMarkdown(text: answer.text) }
                }
                .frame(maxHeight: 320)
            }

            if !answer.isWorking, answer.error == nil, !answer.text.isEmpty {
                HStack(spacing: 10) {
                    Button {
                        store.claude.continueInPanel()
                    } label: {
                        Label("Continue in Side Panel", systemImage: "sidebar.right")
                    }
                    .disabled(store.claude.isWorking)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(answer.text, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Spacer()
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: 660)
        .glassPanel(cornerRadius: 18)
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .shadow(color: Nightglass.claude.opacity(0.18), radius: 30)
        .environment(\.openURL, OpenURLAction { url in
            store.open(url, inNewTab: true)
            return .handled
        })
    }
}

/// Renders Claude's Markdown: bold, italics, code and links, with headings
/// and bullet lists tidied up for a narrow panel.
struct ClaudeMarkdown: View {
    let text: String

    var body: some View {
        Text(Self.render(text))
            .font(.system(size: 13))
            .foregroundStyle(Nightglass.text)
            .tint(Nightglass.accent)
            .lineSpacing(2)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func render(_ text: String) -> AttributedString {
        let lines = text.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                return "**" + String(trimmed[marker.upperBound...]) + "**"
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let indent = String(line.prefix { $0 == " " })
                return indent + "• " + String(trimmed.dropFirst(2))
            }
            return line
        }
        let source = lines.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(text)
    }
}

/// Three softly pulsing dots while Claude is thinking.
struct ThinkingDots: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Nightglass.claude)
                    .frame(width: 6, height: 6)
                    .opacity(isAnimating ? 1 : 0.25)
                    .scaleEffect(isAnimating ? 1 : 0.7)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .padding(.vertical, 4)
        .onAppear { isAnimating = true }
        .accessibilityLabel("Claude is working")
    }
}

/// Settings ▸ Claude.
struct ClaudeSettingsTab: View {
    @Environment(BrowserStore.self) private var store
    @State private var keyDraft = ""

    var body: some View {
        let claude = store.claude

        Form {
            Section {
                if claude.hasKey {
                    HStack {
                        Label("API key saved in your Keychain", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Nightglass.safe)
                        Spacer()
                        Button("Remove Key") { claude.setKey("") }
                            .controlSize(.small)
                    }
                } else {
                    HStack {
                        SecureField("Paste your API key", text: $keyDraft)
                        Button("Save") {
                            claude.setKey(keyDraft)
                            keyDraft = ""
                        }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } header: {
                Text("Anthropic API key")
            } footer: {
                Text("Get a key at console.anthropic.com ▸ API Keys. Usage is billed to that account, separately from a Claude subscription.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
            }

            Section("Models") {
                Picker("Side panel", selection: Binding(get: { claude.model }, set: { claude.setModel($0) })) {
                    ForEach(ClaudeModel.allCases) { model in
                        Text("\(model.name) – \(model.detail)").tag(model)
                    }
                }
                LabeledContent("Address bar", value: "Haiku 5.5 (fast quick answers)")
            }

            Section("What Claude can see") {
                Label("Address bar questions send your question plus the current page's title and address.", systemImage: "magnifyingglass")
                Label("In the side panel, Claude sees tab titles and addresses when it lists your tabs, and a page's text only when it reads that page.", systemImage: "sidebar.right")
                Label("Private tabs are never shared with Claude.", systemImage: "eye.slash")
                Label("Claude asks before closing tabs or sending a form.", systemImage: "hand.raised")
            }
            .font(.system(size: 12.5))
        }
        .formStyle(.grouped)
        .tint(Nightglass.accent)
    }
}
