import AppKit
import Observation
import UniformTypeIdentifiers

/// Checks whether Vela is your default browser, and asks macOS to make it one.
@MainActor
@Observable
final class DefaultBrowser {
    private(set) var isDefault = false

    init() {
        refresh()
    }

    func refresh() {
        let current = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        isDefault = current?.resolvingSymlinksInPath() == Bundle.main.bundleURL.resolvingSymlinksInPath()
    }

    /// macOS shows its own "Use Vela as your default browser?" question.
    func makeDefault() async {
        let app = Bundle.main.bundleURL
        let workspace = NSWorkspace.shared
        do {
            try await workspace.setDefaultApplication(at: app, toOpenURLsWithScheme: "http")
            try await workspace.setDefaultApplication(at: app, toOpenURLsWithScheme: "https")
            try? await workspace.setDefaultApplication(at: app, toOpen: .html)
        } catch {
            // You chose "Keep Safari" (or similar); nothing to do.
        }
        refresh()
    }
}
