import AppKit
import WebKit

/// Things Claude can do with text on a page, from the right-click menu.
enum TextAction {
    // With text selected
    case explain, summarize, define, translate, askAbout
    // In a text box you're typing in
    case fixGrammar, shorter, friendlier, professional

    var title: String {
        switch self {
        case .explain: "Explain"
        case .summarize: "Summarize"
        case .define: "Define"
        case .translate: "Translate to English"
        case .askAbout: "Ask Claude About This…"
        case .fixGrammar: "Fix Spelling and Grammar"
        case .shorter: "Make It Shorter"
        case .friendlier: "Make It Friendlier"
        case .professional: "Make It More Professional"
        }
    }

    var isRewrite: Bool {
        switch self {
        case .fixGrammar, .shorter, .friendlier, .professional: true
        default: false
        }
    }

    /// What Claude is asked to do with the selected text.
    func question(about text: String) -> String {
        switch self {
        case .explain: "Explain this in simple terms:\n\n\(text)"
        case .summarize: "Summarize this in a few short points:\n\n\(text)"
        case .define: "Define this, briefly, with an example:\n\n\(text)"
        case .translate: "Translate this into English:\n\n\(text)"
        case .askAbout: "About this text from the page:\n\n“\(text)”\n\n"
        default: text
        }
    }

    /// How a rewrite should change your text.
    var rewriteInstruction: String {
        switch self {
        case .fixGrammar: "Fix spelling, grammar and punctuation only. Change nothing else."
        case .shorter: "Make it noticeably shorter and clearer, keeping every important point."
        case .friendlier: "Make it warmer and friendlier, keeping it natural and the same length or shorter."
        case .professional: "Make it polished and professional, keeping it concise."
        default: ""
        }
    }
}

/// Vela's web view: WebKit's own, plus Claude in the right-click menu.
final class VelaWebView: WKWebView {
    /// Set by the store; runs when you pick a Claude item from the menu.
    var onTextAction: ((TextAction) -> Void)?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard onTextAction != nil else { return }
        // WebKit only offers Copy when text is selected, and Paste in text boxes.
        let ids = Set(menu.items.compactMap { $0.identifier?.rawValue })
        let titles = Set(menu.items.map(\.title))
        let hasSelection = ids.contains("WKMenuItemIdentifierCopy") || titles.contains("Copy")
        let isEditable = ids.contains("WKMenuItemIdentifierPaste") || titles.contains("Paste")

        var added: [NSMenuItem] = []
        if isEditable {
            added.append(submenu("Rewrite with Claude", [.fixGrammar, .shorter, .friendlier, .professional]))
        }
        if hasSelection {
            added.append(submenu("Ask Claude", [.explain, .summarize, .define, .translate, .askAbout]))
        }
        guard !added.isEmpty else { return }
        menu.insertItem(.separator(), at: 0)
        for item in added.reversed() { menu.insertItem(item, at: 0) }
    }

    private func submenu(_ title: String, _ actions: [TextAction]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)
        let menu = NSMenu(title: title)
        for action in actions {
            let handler = MenuHandler { [weak self] in self?.onTextAction?(action) }
            let entry = NSMenuItem(title: action.title, action: #selector(MenuHandler.run), keyEquivalent: "")
            entry.target = handler
            entry.representedObject = handler // keeps the handler alive with the item
            menu.addItem(entry)
        }
        item.submenu = menu
        return item
    }
}

/// Lets a menu item run a Swift closure.
private final class MenuHandler: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run() { handler() }
}

private enum TextScripts {
    /// The selected text on the page (or in a frame's text box).
    static let selection = """
    const el = document.activeElement;
    if (el && (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') && el.type !== 'password'
        && el.selectionStart !== el.selectionEnd) {
      return el.value.slice(el.selectionStart, el.selectionEnd).slice(0, 8000);
    }
    const s = window.getSelection();
    return s ? s.toString().slice(0, 8000) : '';
    """

    /// Remembers the text box you're in, and returns the text to rewrite:
    /// what you selected in it, or all of it.
    static let captureField = """
    const el = document.activeElement;
    if (!el) return null;
    const textTypes = ['text', 'search', 'email', 'url', ''];
    if (el.tagName === 'TEXTAREA' || (el.tagName === 'INPUT' && textTypes.includes(el.type))) {
      const s = el.selectionStart, e = el.selectionEnd;
      const all = s === e;
      window.__velaEdit = { el, start: all ? 0 : s, end: all ? el.value.length : e };
      return el.value.slice(window.__velaEdit.start, window.__velaEdit.end).slice(0, 8000);
    }
    if (el.isContentEditable) {
      const sel = window.getSelection();
      let range;
      if (sel && !sel.isCollapsed && el.contains(sel.anchorNode)) { range = sel.getRangeAt(0).cloneRange(); }
      else { range = document.createRange(); range.selectNodeContents(el); }
      window.__velaEdit = { el, range };
      return range.toString().slice(0, 8000);
    }
    return null;
    """

    /// Puts the rewrite in place, as if typed, so ⌘Z undoes it.
    static let replaceField = """
    const t = window.__velaEdit;
    if (!t || !t.el.isConnected) return false;
    t.el.focus();
    if (t.range) {
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(t.range);
      if (!document.execCommand('insertText', false, text)) { t.range.deleteContents(); t.range.insertNode(document.createTextNode(text)); }
    } else {
      t.el.setSelectionRange(t.start, t.end);
      if (!document.execCommand('insertText', false, text)) {
        t.el.setRangeText(text, t.start, t.end, 'end');
        t.el.dispatchEvent(new Event('input', { bubbles: true }));
      }
    }
    window.__velaEdit = null;
    return true;
    """
}

extension BrowserStore {
    /// A Claude item from the right-click menu.
    func perform(_ action: TextAction, in tab: BrowserTab) {
        Task {
            if action.isRewrite {
                await rewriteField(action, in: tab)
            } else {
                guard let text = try? await tab.runScript(TextScripts.selection, arguments: [:]) as? String,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    showNotice("Select some text first")
                    return
                }
                if action == .askAbout {
                    isClaudePanelVisible = true
                    claude.pendingDraft = action.question(about: text)
                } else {
                    claude.ask(action.question(about: text), about: tab)
                }
            }
        }
    }

    private func rewriteField(_ action: TextAction, in tab: BrowserTab) async {
        guard claude.hasKey else {
            showNotice("Add your Claude API key in Settings ▸ Claude first")
            return
        }
        guard let original = try? await tab.runScript(TextScripts.captureField, arguments: [:]) as? String,
              !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showNotice("Click into a text box with some writing first")
            return
        }
        showNotice("Claude is rewriting…")
        let request = ClaudeRequest(
            model: .haiku,
            system: """
            You rewrite text someone is typing on a website. \(action.rewriteInstruction) Keep their \
            language, meaning, names, numbers and links. Reply with only the rewritten text: no quotes, \
            no explanations.
            """,
            messages: [["role": "user", "content": original]],
            maxTokens: 4_000,
            effort: "low"
        )
        do {
            let response = try await ClaudeClient.stream(request) { _ in }
            let rewritten = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rewritten.isEmpty, response.stopReason != "refusal" else {
                showNotice("Claude couldn't rewrite that")
                return
            }
            let done = (try? await tab.runScript(TextScripts.replaceField, arguments: ["text": rewritten])) as? Bool ?? false
            showNotice(done ? "Rewritten. Press ⌘Z to undo." : "The text box went away, so nothing was changed")
        } catch {
            showNotice(error.localizedDescription)
        }
    }
}
