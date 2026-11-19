import AppKit
import CryptoKit
import Foundation

// MARK: - Importing from the Passwords app

/// Brings in passwords exported from Apple's Passwords app (or Chrome,
/// Firefox, Brave, Edge and 1Password, which use the same kind of file).
///
/// **Why an export file?** Apple keeps the Passwords app's logins (your
/// iCloud Keychain) for Safari only. No other browser is allowed to read
/// them, so the safe way in is: Passwords ▸ File ▸ Export All Passwords…,
/// import here, then let Vela delete the exported file.
///
/// The file is a spreadsheet saved as plain text ("CSV"): one login per
/// line, with columns like `Title,URL,Username,Password,Notes,OTPAuth`.
enum PasswordImporter {
    struct Result {
        var imported = 0
        var skipped = 0
        /// 2FA keys that came along.
        var codes = 0
    }

    enum ImportError: LocalizedError {
        case unreadable
        case missingColumns

        var errorDescription: String? {
            switch self {
            case .unreadable: "Vela couldn't read that file."
            case .missingColumns: "That file doesn't look like a password export. It needs URL, username and password columns."
            }
        }
    }

    /// Reads the file and saves every login into Vela's Keychain store.
    @MainActor
    static func importFile(_ url: URL, into vault: PasswordVault) throws -> Result {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw ImportError.unreadable }
        let rows = parseCSV(text)
        guard let header = rows.first?.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }) else {
            throw ImportError.missingColumns
        }
        func column(_ names: [String]) -> Int? { header.firstIndex { names.contains($0) } }
        guard let urlColumn = column(["url", "website", "login_uri", "web site", "origin_url"]),
              let passwordColumn = column(["password", "login_password"]) else {
            throw ImportError.missingColumns
        }
        let userColumn = column(["username", "user name", "login_username", "email", "login"])
        // The Passwords app's 2FA keys ("otpauth://totp/…").
        let codeColumn = column(["otpauth", "otp", "totp", "login_totp", "one-time password"])

        var result = Result()
        for row in rows.dropFirst() {
            guard row.count > max(urlColumn, passwordColumn) else { result.skipped += 1; continue }
            let address = row[urlColumn].trimmingCharacters(in: .whitespaces)
            let password = row[passwordColumn]
            let username = userColumn.flatMap { row.count > $0 ? row[$0] : nil } ?? ""
            guard !password.isEmpty, let host = host(from: address) else { result.skipped += 1; continue }
            if vault.save(server: host, account: username, password: password) {
                result.imported += 1
                if let codeColumn, row.count > codeColumn,
                   let generator = OneTimeCode(setupText: row[codeColumn]) {
                    vault.saveCode(generator, for: PasswordEntry(server: host, account: username))
                    result.codes += 1
                }
            } else {
                result.skipped += 1
            }
        }
        return result
    }

    /// Overwrites the exported file with random bytes, then deletes it, so
    /// your passwords don't sit in a readable file in Downloads.
    static func destroy(_ url: URL) {
        if let handle = try? FileHandle(forWritingTo: url) {
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: 0)
            var random = SystemRandomNumberGenerator()
            let noise = Data((0..<Int(min(size, 50_000_000))).map { _ in UInt8.random(in: 0...255, using: &random) })
            try? handle.write(contentsOf: noise)
            try? handle.synchronize()
            try? handle.close()
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// "https://www.example.com/login" → "example.com"; plain "example.com" works too.
    @MainActor
    static func host(from address: String) -> String? {
        guard !address.isEmpty else { return nil }
        let withScheme = address.contains("://") ? address : "https://" + address
        guard let host = URL(string: withScheme)?.host(), !host.isEmpty else { return nil }
        return PasswordVault.normalize(host)
    }

    /// A small CSV reader: handles "quoted, fields", doubled "" quotes and
    /// line breaks inside quotes (which notes often have).
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
                continue
            }
            switch char {
            case "\"": inQuotes = true
            case ",": row.append(field); field = ""
            case "\n", "\r\n", "\r":
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            default: field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        // Strip a byte-order mark some apps put at the very start.
        if var first = rows.first, let cell = first.first, cell.hasPrefix("\u{FEFF}") {
            first[0] = String(cell.dropFirst())
            rows[0] = first
        }
        return rows
    }
}

// MARK: - Password health check

/// One finding from the password check.
struct PasswordIssue: Identifiable {
    enum Kind: String {
        case breached = "Found in a data breach"
        case reused = "Used on more than one site"
        case weak = "Easy to guess"
    }

    let id = UUID()
    let entry: PasswordEntry
    let kinds: [Kind]
}

/// Looks for weak, reused and breached passwords.
///
/// **Breach check, privately:** Vela uses the free "Have I Been Pwned"
/// service with a trick called k-anonymity. It scrambles your password into
/// a code (a SHA-1 hash), sends only the first 5 characters of that code,
/// and gets back every breached code that starts the same way. The match is
/// done on your Mac, so neither your password nor its full code ever leaves it.
enum PasswordHealth {
    @MainActor
    static func check(_ vault: PasswordVault, includeBreaches: Bool) async -> [PasswordIssue] {
        var passwords: [PasswordEntry: String] = [:]
        for entry in vault.entries {
            if let password = vault.password(for: entry) { passwords[entry] = password }
        }

        var usage: [String: Int] = [:]
        for password in passwords.values { usage[password, default: 0] += 1 }

        var breached: Set<String> = []
        if includeBreaches {
            for password in Set(passwords.values) where await isBreached(password) {
                breached.insert(password)
            }
        }

        return passwords.compactMap { entry, password -> PasswordIssue? in
            var kinds: [PasswordIssue.Kind] = []
            if breached.contains(password) { kinds.append(.breached) }
            if usage[password, default: 0] > 1 { kinds.append(.reused) }
            if isWeak(password) { kinds.append(.weak) }
            return kinds.isEmpty ? nil : PasswordIssue(entry: entry, kinds: kinds)
        }
        .sorted { ($0.kinds.count, $0.entry.server) > ($1.kinds.count, $1.entry.server) }
    }

    static func isWeak(_ password: String) -> Bool {
        if password.count < 10 { return true }
        let kinds = [
            password.contains { $0.isLowercase },
            password.contains { $0.isUppercase },
            password.contains { $0.isNumber },
            password.contains { !$0.isLetter && !$0.isNumber },
        ].filter { $0 }.count
        if kinds < 2 { return true }
        let lower = password.lowercased()
        let common = ["password", "123456", "qwerty", "letmein", "welcome", "iloveyou", "admin", "abc123", "monkey", "dragon"]
        return common.contains { lower.contains($0) }
    }

    private static func isBreached(_ password: String) async -> Bool {
        let hash = Insecure.SHA1.hash(data: Data(password.utf8)).map { String(format: "%02X", $0) }.joined()
        let prefix = String(hash.prefix(5))
        let suffix = hash.dropFirst(5)
        guard let url = URL(string: "https://api.pwnedpasswords.com/range/\(prefix)") else { return false }
        var request = URLRequest(url: url)
        request.setValue("true", forHTTPHeaderField: "Add-Padding") // hides how many results came back
        request.setValue("Vela-Browser", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession(configuration: .ephemeral).data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let body = String(data: data, encoding: .utf8) else { return false }
        return body.split(whereSeparator: \.isNewline).contains { line in
            let parts = line.split(separator: ":")
            return parts.count == 2 && parts[0] == suffix && parts[1] != "0"
        }
    }
}
