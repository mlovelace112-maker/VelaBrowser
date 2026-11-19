import AppKit
import Foundation
import Observation
import Sparkle

/// Keeps Vela up to date, the way Firefox and Brave update themselves.
///
/// It uses **Sparkle**, the standard updater for Mac apps that don't come from
/// the App Store. Here's how an update reaches you:
///
/// 1. GitHub builds a new Vela whenever a change is merged (see
///    `.github/workflows/release.yml`).
/// 2. The build is **signed** with a private key that only GitHub knows, and
///    added to a small list of versions called the *appcast* (`appcast.xml`).
/// 3. Once a day, Vela reads the appcast. If there's a newer build, Sparkle
///    shows "A new version of Vela is available" with the release notes.
/// 4. Before installing, Sparkle checks the signature against the public key
///    in `Vela-Info.plist` (`SUPublicEDKey`). A download that someone tampered
///    with won't match, so it's thrown away.
///
/// **Channels:** every item in the appcast is either stable (no channel) or
/// marked `beta`. Sparkle asks `allowedChannels(for:)` which channels you want,
/// so turning on "Get beta updates" is all it takes to see beta builds.
@Observable
final class Updater: NSObject, SPUUpdaterDelegate {
    static let shared = Updater()

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    private static let betaKey = "vela.updates.beta"

    /// True once Sparkle is running. When false, `unavailableReason` says why.
    private(set) var isAvailable = false
    private(set) var unavailableReason: String?

    /// Whether to also offer beta builds (new features, a little less tested).
    var getsBetaUpdates: Bool {
        didSet {
            UserDefaults.standard.set(getsBetaUpdates, forKey: Self.betaKey)
            // Look right away, so switching to beta feels immediate.
            if getsBetaUpdates { controller?.updater.checkForUpdatesInBackground() }
        }
    }

    /// Download and install updates by themselves (when you quit Vela).
    /// Security fixes then reach you without a click.
    var installsAutomatically: Bool {
        didSet { controller?.updater.automaticallyDownloadsUpdates = installsAutomatically }
    }

    /// Set when macOS has an update waiting (it often includes security
    /// fixes for WebKit, the engine Vela and Safari use for web pages).
    private(set) var pendingMacOSUpdate: String?

    /// Whether Vela checks once a day by itself.
    var checksAutomatically: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    /// "1.1 (142)": the version people see, then the build number Sparkle compares.
    var versionDescription: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    override init() {
        getsBetaUpdates = UserDefaults.standard.bool(forKey: Self.betaKey)
        checksAutomatically = true
        installsAutomatically = true
        super.init()
    }

    /// Called once at launch by the AppDelegate.
    func start() {
        #if DEBUG
        // A copy run from Xcode would otherwise offer to replace itself.
        unavailableReason = "Updates are off in copies run from Xcode."
        #else
        // The public key is 32 bytes written as 44 characters of Base64. Until
        // `scripts/setup-updates.sh` has filled it in, there's nothing to check
        // downloads against, so Vela doesn't look for updates at all.
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard key.count == 44 else {
            unavailableReason = "Updates aren't set up yet. Run scripts/setup-updates.sh once."
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.controller = controller
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        // Install updates automatically unless you've turned that off.
        let autoKey = "vela.updates.autoInstallChosen"
        if !UserDefaults.standard.bool(forKey: autoKey) {
            controller.updater.automaticallyDownloadsUpdates = true
            UserDefaults.standard.set(true, forKey: autoKey)
        }
        installsAutomatically = controller.updater.automaticallyDownloadsUpdates
        isAvailable = true
        #endif
    }

    /// Asks macOS whether a system update is waiting. Uses the list macOS
    /// already downloaded in the background (`--no-scan`), so it's quick.
    func checkMacOSUpdates() async -> String? {
        let found = await Task.detached(priority: .utility) { () -> String? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
            process.arguments = ["--list", "--no-scan"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            // Lines look like: "* Label: macOS Golden Gate 27.2.2-…"
            return output.split(separator: "\n")
                .first { $0.contains("Label:") && ($0.contains("macOS") || $0.contains("Security") || $0.contains("Safari")) }
                .map { $0.components(separatedBy: "Label:").last?.trimmingCharacters(in: .whitespaces) ?? "" }
        }.value
        await MainActor.run { pendingMacOSUpdate = found }
        return found
    }

    /// Opens System Settings ▸ General ▸ Software Update.
    func openSoftwareUpdate() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Vela ▸ Check for Updates… Shows a window either way, so you get an answer.
    func checkNow() {
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        // Read straight from UserDefaults: Sparkle may ask from any thread.
        UserDefaults.standard.bool(forKey: Self.betaKey) ? ["beta"] : []
    }
}
