import AppKit
import SwiftUI

/// Custom keyboard shortcuts: Settings ▸ Shortcuts lets you change (or turn
/// off) the shortcut of any Vela menu command. Menu items use
/// `.velaShortcut(...)` instead of `.keyboardShortcut(...)`, which looks up
/// your change first.
@MainActor
@Observable
final class Shortcuts {
    static let shared = Shortcuts()

    /// A shortcut you picked. `key` is nil when you turned the shortcut off.
    struct Custom: Codable, Equatable {
        var key: String?
        var modifiers: Int

        var shortcut: KeyboardShortcut? {
            guard let key, let character = key.first else { return nil }
            return KeyboardShortcut(KeyEquivalent(character), modifiers: EventModifiers(rawValue: modifiers))
        }
    }

    private(set) var custom: [String: Custom] = [:]
    /// Every command with a shortcut, and its built-in one (filled in as menus are built).
    @ObservationIgnored private(set) var defaults: [String: KeyboardShortcut] = [:]

    private static let key = "vela.shortcuts"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: Custom].self, from: data) {
            custom = saved
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(custom) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func register(_ id: String, _ shortcut: KeyboardShortcut) {
        if defaults[id] == nil { defaults[id] = shortcut }
    }

    func resolved(_ id: String) -> KeyboardShortcut? {
        if let mine = custom[id] { return mine.shortcut }
        return defaults[id]
    }

    func set(_ id: String, key: Character, modifiers: EventModifiers) {
        custom[id] = Custom(key: String(key), modifiers: modifiers.rawValue)
        save()
    }

    func turnOff(_ id: String) {
        custom[id] = Custom(key: nil, modifiers: 0)
        save()
    }

    func reset(_ id: String) {
        custom[id] = nil
        save()
    }

    func resetAll() {
        custom = [:]
        save()
    }

    /// Other commands already using this shortcut.
    func conflicts(with shortcut: KeyboardShortcut, except id: String) -> [String] {
        defaults.keys.filter { $0 != id && resolved($0).map { Self.same($0, shortcut) } == true }.sorted()
    }

    static func same(_ a: KeyboardShortcut, _ b: KeyboardShortcut) -> Bool {
        a.key.character == b.key.character && a.modifiers == b.modifiers
    }

    /// "⌥⌘R"
    static func describe(_ shortcut: KeyboardShortcut?) -> String {
        guard let shortcut else { return "None" }
        var text = ""
        if shortcut.modifiers.contains(.control) { text += "⌃" }
        if shortcut.modifiers.contains(.option) { text += "⌥" }
        if shortcut.modifiers.contains(.shift) { text += "⇧" }
        if shortcut.modifiers.contains(.command) { text += "⌘" }
        let names: [Character: String] = [
            KeyEquivalent.leftArrow.character: "←", KeyEquivalent.rightArrow.character: "→",
            KeyEquivalent.upArrow.character: "↑", KeyEquivalent.downArrow.character: "↓",
            KeyEquivalent.return.character: "↩", KeyEquivalent.tab.character: "⇥",
            KeyEquivalent.space.character: "Space", KeyEquivalent.delete.character: "⌫",
        ]
        return text + (names[shortcut.key.character] ?? String(shortcut.key.character).uppercased())
    }

    /// The key you pressed, as a menu key, or nil for keys that can't be used.
    static func keyCharacter(for event: NSEvent) -> Character? {
        switch event.keyCode {
        case 123: return KeyEquivalent.leftArrow.character
        case 124: return KeyEquivalent.rightArrow.character
        case 125: return KeyEquivalent.downArrow.character
        case 126: return KeyEquivalent.upArrow.character
        case 36: return KeyEquivalent.return.character
        case 48: return KeyEquivalent.tab.character
        case 49: return KeyEquivalent.space.character
        case 51: return KeyEquivalent.delete.character
        default: return event.charactersIgnoringModifiers?.lowercased().first
        }
    }

    static func modifiers(for event: NSEvent) -> EventModifiers {
        var modifiers: EventModifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}

private struct CustomShortcut: ViewModifier {
    let id: String
    let shortcut: KeyboardShortcut

    func body(content: Content) -> some View {
        let shortcuts = Shortcuts.shared
        shortcuts.register(id, shortcut)
        return content.keyboardShortcut(shortcuts.resolved(id))
    }
}

extension View {
    /// A menu shortcut you can change in Settings ▸ Shortcuts.
    func velaShortcut(_ id: String, _ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        modifier(CustomShortcut(id: id, shortcut: KeyboardShortcut(key, modifiers: modifiers)))
    }
}

/// Settings ▸ Shortcuts.
struct ShortcutSettingsTab: View {
    @State private var recording: String?
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        let shortcuts = Shortcuts.shared
        let ids = shortcuts.defaults.keys.sorted()
        Form {
            Section {
                if ids.isEmpty {
                    Text("Open a menu once, and its commands appear here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(ids, id: \.self) { id in
                    row(id, shortcuts)
                }
            } header: {
                Text("Menu shortcuts")
            } footer: {
                Text(hint ?? "Click a shortcut, then press the new keys. Shortcuts need ⌘ or ⌃. Esc cancels.")
            }
            Button("Restore All Built-in Shortcuts") { shortcuts.resetAll() }
                .disabled(shortcuts.custom.isEmpty)
        }
        .formStyle(.grouped)
        .onDisappear(perform: stopRecording)
    }

    private func row(_ id: String, _ shortcuts: Shortcuts) -> some View {
        let current = shortcuts.resolved(id)
        let clashes = current.map { shortcuts.conflicts(with: $0, except: id) } ?? []
        return LabeledContent {
            HStack(spacing: 6) {
                if !clashes.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Nightglass.caution)
                        .help("Also used by: \(clashes.joined(separator: ", "))")
                }
                Button(recording == id ? "Press keys…" : Shortcuts.describe(current)) { startRecording(id) }
                    .frame(minWidth: 90)
                Menu {
                    Button("Turn Off") { shortcuts.turnOff(id) }
                    Button("Use Built-in (\(Shortcuts.describe(shortcuts.defaults[id])))") { shortcuts.reset(id) }
                        .disabled(shortcuts.custom[id] == nil)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        } label: {
            Text(id)
        }
    }

    private func startRecording(_ id: String) {
        stopRecording()
        recording = id
        hint = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stopRecording()
                return nil
            }
            let modifiers = Shortcuts.modifiers(for: event)
            guard modifiers.contains(.command) || modifiers.contains(.control) else {
                hint = "Include ⌘ or ⌃, so the shortcut doesn't get in the way of typing."
                return nil
            }
            if let character = Shortcuts.keyCharacter(for: event) {
                Shortcuts.shared.set(id, key: character, modifiers: modifiers)
            }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }
}
