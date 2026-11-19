import AppKit

/// Handles app-wide events from macOS: launching and quitting.
///
/// It also owns the `BrowserStore`, so that when you quit, Vela can still
/// reach your settings and clear cookies before it closes.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = BrowserStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set the Dock icon directly from the asset catalog. macOS caches app
        // icons aggressively, so this makes the Vela icon appear right away.
        if let icon = NSImage(named: "VelaIcon") {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store.privacy.clearCookiesOnQuit else { return .terminateNow }

        // Clearing data takes a moment, so ask macOS to wait ("terminate later"),
        // delete everything except kept sites, then say "OK, quit now".
        let kept = store.privacy.keptSites
        Task {
            await store.cookieManager.deleteAll(keeping: kept, thenReload: false)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
