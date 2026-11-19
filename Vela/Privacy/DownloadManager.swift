import AppKit
import CoreServices
import Foundation
import Observation
import WebKit

/// Where a download is up to.
enum DownloadState: Equatable {
    case downloading
    case finished
    case failed(String)
    /// Stopped by Vela's download guard before anything was saved.
    case blocked(String)
    case cancelled
}

/// One file in the Downloads list.
@MainActor
@Observable
final class DownloadItem: Identifiable {
    let id = UUID()
    var filename: String
    /// The file's own address.
    let sourceURL: URL?
    /// The page you were on when the download started.
    let pageURL: URL?
    /// Where the file was saved on your Mac.
    var fileURL: URL?
    var progress: Double = 0
    var state: DownloadState = .downloading
    /// The VirusTotal result once it's saved.
    var scan: DownloadScan = .none
    /// The file's SHA-256 fingerprint (shown so you can compare it with the website's).
    var sha256: String?

    @ObservationIgnored fileprivate var download: WKDownload?

    init(filename: String, sourceURL: URL?, pageURL: URL?) {
        self.filename = filename
        self.sourceURL = sourceURL
        self.pageURL = pageURL
    }
}

/// A risky download waiting for you to say "Download Anyway" or "Cancel".
struct DownloadWarning: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let reason: String
}

/// Saves files to your Downloads folder, after the download guard checks them.
///
/// **What keeps you safe:**
/// 1. `DownloadGuard` blocks or questions risky files *before* they're saved.
/// 2. Every saved file gets macOS's "quarantine" tag. That's what makes macOS
///    ask "This was downloaded from the internet. Open it?" and lets
///    Gatekeeper and XProtect (Apple's built-in malware scanner) check apps
///    and installers before they run. Without the tag, macOS skips those checks.
@MainActor
@Observable
final class DownloadManager {
    var items: [DownloadItem] = []
    var pendingWarning: DownloadWarning?
    let virusTotal = VirusTotal()

    /// Reads your current privacy settings (set by BrowserStore).
    @ObservationIgnored var settings: @MainActor () -> PrivacySettings = { PrivacySettings() }
    /// Asks Google Safe Browsing about a file's address (set by BrowserStore).
    @ObservationIgnored var checkThreat: (@MainActor (URL) async -> SafeBrowsingThreat?)?

    @ObservationIgnored private let delegate = DownloadDelegate()
    @ObservationIgnored private var itemsByDownload: [ObjectIdentifier: DownloadItem] = [:]
    @ObservationIgnored private var warningContinuation: CheckedContinuation<Bool, Never>?

    init() {
        delegate.manager = self
    }

    var activeCount: Int {
        items.filter { $0.state == .downloading }.count
    }

    /// Average progress of the downloads still running (0 to 1).
    var overallProgress: Double {
        let active = items.filter { $0.state == .downloading }
        guard !active.isEmpty else { return 0 }
        return active.map(\.progress).reduce(0, +) / Double(active.count)
    }

    /// Called when a tab hands over a download.
    func track(_ download: WKDownload, pageURL: URL?) {
        download.delegate = delegate
        let source = download.originalRequest?.url
        let item = DownloadItem(
            filename: source?.lastPathComponent ?? "Download",
            sourceURL: source,
            pageURL: pageURL
        )
        item.download = download
        items.insert(item, at: 0)
        itemsByDownload[ObjectIdentifier(download)] = item
    }

    func cancel(_ item: DownloadItem) {
        item.download?.cancel(nil)
        item.state = .cancelled
        stopTracking(item)
    }

    func reveal(_ item: DownloadItem) {
        guard let url = item.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ item: DownloadItem) {
        guard let url = item.fileURL else { return }
        NSWorkspace.shared.open(url)
    }

    func clearFinished() {
        items.removeAll { $0.state != .downloading }
    }

    /// Answers the "Download anyway?" question.
    func resolveWarning(_ keep: Bool) {
        let continuation = warningContinuation
        warningContinuation = nil
        pendingWarning = nil
        continuation?.resume(returning: keep)
    }

    // MARK: - Called by the download delegate

    fileprivate func destination(for download: WKDownload, response: URLResponse, suggestedFilename: String) async -> URL? {
        guard let item = itemsByDownload[ObjectIdentifier(download)] else { return nil }
        let name = DownloadGuard.cleanFilename(suggestedFilename)
        item.filename = name

        if settings().safeBrowsingEnabled, let source = response.url ?? item.sourceURL,
           let threat = await checkThreat?(source) {
            item.state = .blocked(threat.reason + ".")
            stopTracking(item)
            return nil
        }

        if settings().blockDangerousDownloads {
            let verdict = DownloadGuard.assess(
                filename: suggestedFilename,
                source: response.url ?? item.sourceURL,
                page: item.pageURL
            )
            switch verdict {
            case .allow:
                break
            case .block(let reason):
                item.state = .blocked(reason)
                stopTracking(item)
                return nil
            case .warn(let reason):
                let keep = await askUser(DownloadWarning(filename: name, reason: reason))
                guard keep else {
                    item.state = .cancelled
                    stopTracking(item)
                    return nil
                }
            }
        }

        guard let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            item.state = .failed("Couldn't find your Downloads folder")
            stopTracking(item)
            return nil
        }
        let url = uniqueURL(in: folder, name: name)
        item.fileURL = url
        followProgress(of: item, download: download)
        return url
    }

    fileprivate func didFinish(_ download: WKDownload) {
        guard let item = itemsByDownload[ObjectIdentifier(download)] else { return }
        item.progress = 1
        item.state = .finished
        if let url = item.fileURL {
            quarantine(url, item: item)
            scan(item, at: url)
        }
        stopTracking(item)
    }

    /// Fingerprints the file on your Mac, then asks VirusTotal about it.
    private func scan(_ item: DownloadItem, at url: URL) {
        let lookUp = settings().scanDownloads && virusTotal.hasKey
        if lookUp { item.scan = .scanning }
        Task {
            let hash = await Task.detached(priority: .utility) { VirusTotal.sha256(of: url) }.value
            item.sha256 = hash
            guard lookUp, let hash else {
                item.scan = .none
                return
            }
            item.scan = await virusTotal.lookup(sha256: hash)
        }
    }

    /// "Move to Trash" for a file VirusTotal flagged.
    func trash(_ item: DownloadItem) {
        guard let url = item.fileURL else { return }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        item.fileURL = nil
        item.state = .blocked("Moved to the Trash.")
    }

    fileprivate func didFail(_ download: WKDownload, error: Error) {
        guard let item = itemsByDownload[ObjectIdentifier(download)] else { return }
        // Blocked or cancelled downloads also end up here; keep that reason.
        if item.state == .downloading {
            item.state = .failed(error.localizedDescription)
        }
        stopTracking(item)
    }

    // MARK: - Helpers

    private func askUser(_ warning: DownloadWarning) async -> Bool {
        resolveWarning(false) // Only one question at a time: an older one counts as "Cancel".
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            warningContinuation = continuation
            pendingWarning = warning
        }
    }

    private func stopTracking(_ item: DownloadItem) {
        if let download = item.download {
            itemsByDownload[ObjectIdentifier(download)] = nil
        }
        item.download = nil
    }

    /// Updates the progress bar a few times a second until the download ends.
    private func followProgress(of item: DownloadItem, download: WKDownload) {
        Task { [weak item] in
            while let item, item.state == .downloading {
                item.progress = download.progress.fractionCompleted
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// "photo.jpg" → "photo (2).jpg" if "photo.jpg" already exists.
    private func uniqueURL(in folder: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            let numbered = ext.isEmpty ? "\(base) (\(number))" : "\(base) (\(number)).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            number += 1
        }
        return candidate
    }

    /// Adds macOS's "downloaded from the internet" tag so Gatekeeper checks the file.
    private func quarantine(_ url: URL, item: DownloadItem) {
        var properties: [String: Any] = [
            kLSQuarantineAgentNameKey as String: "Vela",
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
        ]
        if let source = item.sourceURL { properties[kLSQuarantineDataURLKey as String] = source }
        if let page = item.pageURL { properties[kLSQuarantineOriginURLKey as String] = page }

        var values = URLResourceValues()
        values.quarantineProperties = properties
        var fileURL = url
        do {
            try fileURL.setResourceValues(values)
        } catch {
            NSLog("Vela: couldn't mark download as quarantined: %@", error.localizedDescription)
        }
    }
}

/// Receives download events from WebKit and passes them to the manager.
@MainActor
private final class DownloadDelegate: NSObject, WKDownloadDelegate {
    weak var manager: DownloadManager?

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        await manager?.destination(for: download, response: response, suggestedFilename: suggestedFilename)
    }

    func downloadDidFinish(_ download: WKDownload) {
        manager?.didFinish(download)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        manager?.didFail(download, error: error)
    }
}

// MARK: - Download guard

enum DownloadVerdict: Equatable {
    case allow
    case warn(String)
    case block(String)
}

/// Decides whether a file is safe to save, by its name and where it came from.
///
/// This is the same kind of check Safari and Chrome do before their online
/// malware lookups: some file types can only hurt a Mac (or are useless on
/// one), and some names are designed to trick you.
@MainActor
enum DownloadGuard {
    /// Windows programs and scripts. They can't run on a Mac and are a top way to spread malware.
    static let windowsPrograms: Set<String> = [
        "exe", "scr", "pif", "com", "bat", "cmd", "vbs", "vbe", "jse", "wsf", "wsh",
        "hta", "cpl", "msi", "msp", "lnk", "reg", "ps1",
    ]

    /// Mac apps, installers and scripts: fine from a site you trust, risky otherwise.
    static let macPrograms: Set<String> = [
        "dmg", "pkg", "mpkg", "app", "command", "tool", "sh", "zsh", "bash", "csh",
        "scpt", "applescript", "workflow", "terminal", "jar", "py", "pl", "rb",
    ]

    /// Office documents that can contain macros (hidden programs).
    static let macroDocuments: Set<String> = [
        "docm", "dotm", "xlsm", "xltm", "xlam", "pptm", "potm", "ppam",
    ]

    /// File types a program might pretend to be: "invoice.pdf.exe".
    private static let disguises: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "jpg", "jpeg",
        "png", "gif", "heic", "mp3", "mp4", "mov", "avi", "zip",
    ]

    /// Invisible characters that can flip how a name displays, so
    /// "photo‮gpj.app" looks like "photoppa.jpg".
    private static let trickCharacters: Set<UInt32> = [
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069, 0x200E, 0x200F,
    ]

    static func assess(filename: String, source: URL?, page: URL?) -> DownloadVerdict {
        if filename.unicodeScalars.contains(where: { trickCharacters.contains($0.value) }) {
            return .block("Its name uses hidden characters to disguise its real file type.")
        }
        if let host = source?.host(), ContentBlocker.isTracker(host) {
            return .block("It comes from an ad network (\(host)), not the website you were on.")
        }
        if let host = page?.host(), ContentBlocker.isTracker(host) {
            return .block("It was started by an ad network page (\(host)).")
        }

        let parts = filename.lowercased().split(separator: ".").map(String.init)
        let ext = parts.count > 1 ? parts[parts.count - 1] : ""
        let inner = parts.count > 2 ? parts[parts.count - 2] : ""
        let isProgram = windowsPrograms.contains(ext) || macPrograms.contains(ext)

        if isProgram && disguises.contains(inner) {
            return .block("It pretends to be a .\(inner) file but is really a .\(ext) program.")
        }
        if windowsPrograms.contains(ext) {
            return .block("It's a Windows program (.\(ext)). It can't run on a Mac, and files like this are a common way to spread viruses.")
        }

        let site = (page ?? source).map(BrowserStore.siteName) ?? "this website"
        if macPrograms.contains(ext) {
            let insecure = source?.scheme == "http" ? " It's also coming over an unencrypted (http) connection." : ""
            return .warn("It's an app, installer or script (.\(ext)). Only open it if you trust \(site).\(insecure)")
        }
        if macroDocuments.contains(ext) {
            return .warn("It's an Office document with macros, which can run hidden programs when opened.")
        }
        return .allow
    }

    /// Removes characters that could disguise a file name or point outside the Downloads folder.
    static func cleanFilename(_ name: String) -> String {
        let scalars = name.unicodeScalars.filter { !trickCharacters.contains($0.value) }
        var cleaned = String(String.UnicodeScalarView(scalars))
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        return cleaned.isEmpty ? "Download" : cleaned
    }
}
