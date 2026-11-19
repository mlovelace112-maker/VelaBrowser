import CryptoKit
import Foundation
import Observation

/// The result of scanning a finished download.
enum DownloadScan: Equatable {
    /// Not looked up (no VirusTotal key, or scanning is off).
    case none
    case scanning
    /// No antivirus engine flagged it. The number is how many checked it.
    case clean(Int)
    /// Some engines say it's harmful: flagged, out of how many checked.
    case flagged(Int, Int)
    /// VirusTotal has never seen this exact file (common for brand-new or personal files).
    case unknown
    case failed(String)
}

/// Scans downloads with VirusTotal, the free service that checks a file
/// against about 70 antivirus engines at once.
///
/// **Privately:** Vela never uploads your file. It computes the file's
/// SHA-256 "fingerprint" on your Mac and only asks VirusTotal whether it
/// already knows a file with that fingerprint. Malware that's going around
/// is almost always known.
///
/// This is on top of what macOS already does: Gatekeeper and XProtect check
/// apps and installers when you open them, because Vela tags every download
/// as "from the internet".
@MainActor
@Observable
final class VirusTotal {
    private(set) var hasKey: Bool
    private let secret = KeychainSecret(service: "Vela VirusTotal", account: "api-key")

    init() {
        hasKey = secret.read() != nil
    }

    /// Saves the API key in the Keychain (an empty key removes it).
    func setKey(_ key: String) {
        secret.write(key)
        hasKey = secret.read() != nil
    }

    func lookup(sha256 hash: String) async -> DownloadScan {
        guard let key = secret.read(),
              let url = URL(string: "https://www.virustotal.com/api/v3/files/\(hash)") else { return .none }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(key, forHTTPHeaderField: "x-apikey")
        guard let (data, response) = try? await URLSession(configuration: .ephemeral).data(for: request) else {
            return .failed("Couldn't reach VirusTotal.")
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200:
            break
        case 404:
            return .unknown
        case 401, 403:
            return .failed("VirusTotal didn't accept the API key.")
        case 429:
            return .failed("VirusTotal's free limit was reached. Try again in a minute.")
        case let status:
            return .failed("VirusTotal answered with error \(status).")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let file = json["data"] as? [String: Any],
              let attributes = file["attributes"] as? [String: Any],
              let stats = attributes["last_analysis_stats"] as? [String: Int] else {
            return .failed("VirusTotal sent an answer Vela couldn't read.")
        }
        let harmful = (stats["malicious"] ?? 0) + (stats["suspicious"] ?? 0)
        let checked = (stats["malicious"] ?? 0) + (stats["suspicious"] ?? 0)
            + (stats["harmless"] ?? 0) + (stats["undetected"] ?? 0)
        return harmful > 0 ? .flagged(harmful, checked) : .clean(checked)
    }

    /// The file's SHA-256 fingerprint, read in 1 MB pieces so big files don't fill memory.
    nonisolated static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data
            do { chunk = try handle.read(upToCount: 1_048_576) ?? Data() } catch { return nil }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
