import Foundation

/// Brings your settings over from when Vela ran in the macOS sandbox.
///
/// **Why this exists:** sandboxed apps keep their data in a private
/// "container" (~/Library/Containers/app.vela.Vela). Vela left the sandbox so
/// it can read Safari's bookmarks, which means it now saves to the normal
/// places in ~/Library. This copies your bookmarks, history and settings, and
/// the website data that keeps you signed in, across once.
enum SandboxMigration {
    private static let doneKey = "vela.migratedFromSandbox"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey), !isSandboxed else { return }
        defer { defaults.set(true, forKey: doneKey) }

        let files = FileManager.default
        let home = files.homeDirectoryForCurrentUser
        let bundleID = Bundle.main.bundleIdentifier ?? "app.vela.Vela"
        let container = home.appending(path: "Library/Containers/\(bundleID)/Data/Library")
        guard files.fileExists(atPath: container.path) else { return }

        // Settings, bookmarks and history (all stored as preferences).
        let oldPreferences = container.appending(path: "Preferences/\(bundleID).plist")
        if let data = try? Data(contentsOf: oldPreferences),
           let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for (key, value) in values where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        // Cookies and website data, so you stay signed in to sites.
        let copies: [(from: String, to: String)] = [
            ("WebKit", "Library/WebKit/\(bundleID)"),
            ("HTTPStorages/\(bundleID)", "Library/HTTPStorages/\(bundleID)"),
            ("HTTPStorages/\(bundleID).binarycookies", "Library/HTTPStorages/\(bundleID).binarycookies"),
        ]
        for copy in copies {
            let source = container.appending(path: copy.from)
            let destination = home.appending(path: copy.to)
            guard files.fileExists(atPath: source.path), !files.fileExists(atPath: destination.path) else { continue }
            try? files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? files.copyItem(at: source, to: destination)
        }
    }

    private static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}
