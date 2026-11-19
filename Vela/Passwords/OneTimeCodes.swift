import CryptoKit
import Foundation
import Security
import SwiftUI

// MARK: - The math behind 6-digit codes

/// A two-factor authentication (2FA) code generator, the same kind as
/// Google Authenticator or the Passwords app.
///
/// **How it works (TOTP):** when you turned on 2FA, the website gave you a
/// secret key (usually as a QR code). Your phone and the website both mix
/// that key with the current time, every 30 seconds, and keep the last six
/// digits. Same key + same time = same code, so the site knows it's you
/// without anything being sent. The key never leaves your Keychain.
struct OneTimeCode: Equatable {
    enum Algorithm: String { case sha1, sha256, sha512 }

    let secret: Data
    var digits = 6
    var period = 30
    var algorithm = Algorithm.sha1

    /// Accepts the `otpauth://totp/…` address from a QR code or the
    /// Passwords app export, or the bare setup key a site shows under
    /// "Can't scan the code?" (like `JBSW Y3DP EHPK 3PXP`).
    init?(setupText: String) {
        let text = setupText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("otpauth://") {
            guard let components = URLComponents(string: text),
                  components.host?.lowercased() == "totp",
                  let items = components.queryItems,
                  let key = items.first(where: { $0.name.lowercased() == "secret" })?.value,
                  let secret = Self.base32Decode(key), !secret.isEmpty else { return nil }
            self.secret = secret
            for item in items {
                switch item.name.lowercased() {
                case "digits": if let value = Int(item.value ?? ""), (6...8).contains(value) { digits = value }
                case "period": if let value = Int(item.value ?? ""), (10...120).contains(value) { period = value }
                case "algorithm": if let value = Algorithm(rawValue: (item.value ?? "").lowercased()) { algorithm = value }
                default: break
                }
            }
        } else {
            guard let secret = Self.base32Decode(text), secret.count >= 10 else { return nil }
            self.secret = secret
        }
    }

    /// The code right now (or at another time), like "492039".
    func code(at date: Date = Date()) -> String {
        var counter = UInt64(date.timeIntervalSince1970 / Double(period)).bigEndian
        let message = Data(bytes: &counter, count: 8)
        let key = SymmetricKey(data: secret)
        let hash: Data
        switch algorithm {
        case .sha1: hash = Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: hash = Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: hash = Data(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
        // "Dynamic truncation" from the standard (RFC 4226): pick 4 bytes
        // based on the last byte, then keep the last `digits` digits.
        let offset = Int(hash[hash.count - 1] & 0x0f)
        let value = (UInt32(hash[offset] & 0x7f) << 24)
            | (UInt32(hash[offset + 1]) << 16)
            | (UInt32(hash[offset + 2]) << 8)
            | UInt32(hash[offset + 3])
        var modulus: UInt32 = 1
        for _ in 0..<digits { modulus *= 10 }
        let number = String(value % modulus)
        return String(repeating: "0", count: digits - number.count) + number
    }

    /// Seconds until the code changes.
    func secondsLeft(at date: Date = Date()) -> Int {
        period - Int(date.timeIntervalSince1970) % period
    }

    /// Saved form: a standard otpauth:// address.
    var setupAddress: String {
        "otpauth://totp/Vela?secret=\(Self.base32Encode(secret))&digits=\(digits)&period=\(period)&algorithm=\(algorithm.rawValue.uppercased())"
    }

    // MARK: Base32 (the letters-and-digits format setup keys use)

    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func base32Decode(_ text: String) -> Data? {
        var bits: UInt64 = 0
        var bitCount = 0
        var bytes: [UInt8] = []
        for char in text.uppercased() where !" -=".contains(char) {
            guard let index = alphabet.firstIndex(of: char) else { return nil }
            bits = (bits << 5) | UInt64(index)
            bitCount += 5
            if bitCount >= 8 {
                bitCount -= 8
                bytes.append(UInt8((bits >> UInt64(bitCount)) & 0xff))
            }
        }
        return Data(bytes)
    }

    static func base32Encode(_ data: Data) -> String {
        var result = ""
        var bits: UInt64 = 0
        var bitCount = 0
        for byte in data {
            bits = (bits << 8) | UInt64(byte)
            bitCount += 8
            while bitCount >= 5 {
                bitCount -= 5
                result.append(alphabet[Int((bits >> UInt64(bitCount)) & 31)])
            }
        }
        if bitCount > 0 { result.append(alphabet[Int((bits << UInt64(5 - bitCount)) & 31)]) }
        return result
    }
}

// MARK: - Keeping keys in the Keychain

extension PasswordVault {
    private static let codeService = "Vela 2FA"

    /// Loads which logins have a 2FA key (not the keys themselves).
    func loadCodeIDs() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.codeService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            entriesWithCodes = []
            return
        }
        entriesWithCodes = Set(items.compactMap { $0[kSecAttrAccount as String] as? String })
    }

    func hasCode(_ entry: PasswordEntry) -> Bool {
        entriesWithCodes.contains(entry.id)
    }

    @discardableResult
    func saveCode(_ code: OneTimeCode, for entry: PasswordEntry) -> Bool {
        removeCode(for: entry, reloading: false)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.codeService,
            kSecAttrAccount as String: entry.id,
            kSecAttrLabel as String: "\(entry.server) 2FA (Vela)",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data(code.setupAddress.utf8),
        ]
        let saved = SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        loadCodeIDs()
        return saved
    }

    /// The login's 2FA generator. Only call this after Touch ID.
    func oneTimeCode(for entry: PasswordEntry) -> OneTimeCode? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.codeService,
            kSecAttrAccount as String: entry.id,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let text = String(data: data, encoding: .utf8) else { return nil }
        return OneTimeCode(setupText: text)
    }

    func removeCode(for entry: PasswordEntry, reloading: Bool = true) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.codeService,
            kSecAttrAccount as String: entry.id,
        ]
        SecItemDelete(query as CFDictionary)
        if reloading { loadCodeIDs() }
    }
}

// MARK: - Filling a code into a page

/// After Vela fills a login that has 2FA, the code waits here until the
/// site shows its "Enter the code" box.
struct PendingCode {
    let entry: PasswordEntry
    let generator: OneTimeCode
    let until: Date
}

extension BrowserTab {
    /// Types a 2FA code into the page's code box, if it has one. Handles one
    /// box ("Enter the 6-digit code") and six separate one-digit boxes.
    func fillOneTimeCode(_ code: String) async -> Bool {
        let body = """
        const visible = (el) => !el.disabled && !el.readOnly && (el.offsetWidth || el.offsetHeight);
        const set = (el, value) => {
          const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
          setter.call(el, value);
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
        };
        const inputs = [...document.querySelectorAll('input')].filter((el) =>
          visible(el) && ['text', 'tel', 'number', ''].includes((el.type || '').toLowerCase()));
        // Six one-digit boxes in a row.
        const singles = inputs.filter((el) => el.maxLength === 1);
        if (singles.length >= code.length) {
          for (let i = 0; i < code.length; i++) set(singles[i], code[i]);
          singles[code.length - 1].focus();
          return true;
        }
        const words = /one.?time|otp|totp|2fa|mfa|two.?factor|verification|verify|auth.*code|security.?code|^code$|token|pin/i;
        const field = inputs.find((el) => el.autocomplete === 'one-time-code')
          || inputs.find((el) => words.test([el.name, el.id, el.placeholder, el.getAttribute('aria-label')].join(' '))
             && (el.maxLength < 0 || el.maxLength >= code.length) && (el.maxLength < 0 || el.maxLength <= 10));
        if (!field) return false;
        set(field, code);
        field.focus();
        return true;
        """
        return (try? await runScript(body, arguments: ["code": code])) as? Bool ?? false
    }
}

// MARK: - Showing codes in Passwords (⌥⌘P)

/// The live code under a login, with a ring that empties as it runs out.
struct OneTimeCodeLabel: View {
    let generator: OneTimeCode

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = generator.secondsLeft(at: context.date)
            HStack(spacing: 6) {
                Text(spaced(generator.code(at: context.date)))
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(left <= 5 ? Nightglass.caution : Nightglass.accent)
                ZStack {
                    Circle().stroke(Nightglass.mutedText.opacity(0.3), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: CGFloat(left) / CGFloat(generator.period))
                        .stroke(left <= 5 ? Nightglass.caution : Nightglass.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 12, height: 12)
                .accessibilityLabel("\(left) seconds left")
            }
        }
    }

    /// "492039" → "492 039", easier to read.
    private func spaced(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return String(code.prefix(3)) + " " + String(code.suffix(3))
    }
}

/// "Add 2FA Code" sheet: paste the setup key or otpauth:// address.
struct AddOneTimeCodeView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entry: PasswordEntry
    @State private var setupText = ""

    var body: some View {
        let generator = OneTimeCode(setupText: setupText)

        VStack(alignment: .leading, spacing: 14) {
            Text("2FA Code for \(entry.server)")
                .font(.system(size: 16, weight: .semibold))
            Text("On the website's two-factor setup page, choose \"Can't scan the code?\" or \"Enter key manually\", then paste the key here. Vela keeps it in your Keychain and makes the 6-digit codes for you.")
                .font(.system(size: 12))
                .foregroundStyle(Nightglass.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Setup key, like JBSW Y3DP EHPK 3PXP", text: $setupText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5, design: .monospaced))
            if let generator {
                HStack {
                    Text("Code now:").font(.system(size: 12)).foregroundStyle(Nightglass.mutedText)
                    OneTimeCodeLabel(generator: generator)
                }
                Text("Type this code into the website to finish turning on 2FA.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
            } else if !setupText.isEmpty {
                Text("That doesn't look like a setup key. It's letters A–Z and digits 2–7, usually 16 or 32 of them.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.danger)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    if let generator { store.passwordVault.saveCode(generator, for: entry) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(generator == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
