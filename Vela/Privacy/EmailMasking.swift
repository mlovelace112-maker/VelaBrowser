import Foundation
import Observation

/// Email masking with DuckDuckGo Email Protection (free).
///
/// **The idea:** instead of giving a website your real email address, Vela
/// makes a new random one, like `k7bq2mx9@duck.com`, for that site.
/// DuckDuckGo forwards its mail to your real inbox (with trackers removed).
/// If the site leaks or spams it, you turn off that one address and nothing
/// else changes.
///
/// **Why DuckDuckGo and not iCloud Hide My Email?** Apple only offers Hide My
/// Email inside Safari and Mail. There's no way for other apps to make those
/// addresses. DuckDuckGo's service is free and works from any app.
///
/// **Signing in:** you need a Duck Address (make one free at
/// duckduckgo.com/email). Vela asks DuckDuckGo to email you a one-time
/// passphrase, you paste it into Settings, and Vela keeps the resulting key
/// in your Keychain.
@MainActor
@Observable
final class EmailMasking {
    /// Your Duck Address name: "morgan" for morgan@duck.com.
    private(set) var username: String?
    /// True after "Email me a passphrase", until you paste it.
    private(set) var isWaitingForPassphrase = false
    private(set) var isConnected = false
    private(set) var isWorking = false
    var errorMessage: String?

    private static let usernameKey = "vela.duckAddress"
    private let secret = KeychainSecret(service: "Vela DuckDuckGo Email Protection", account: "access-token")
    private let base = "https://quack.duckduckgo.com/api"

    init() {
        username = UserDefaults.standard.string(forKey: Self.usernameKey)
        isConnected = secret.read() != nil
    }

    /// Step 1: DuckDuckGo emails a one-time passphrase to your real inbox.
    func sendPassphrase(to address: String) async {
        let name = address.lowercased()
            .replacingOccurrences(of: "@duck.com", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }) else {
            errorMessage = "Type your Duck Address, like yourname@duck.com."
            return
        }
        await run {
            _ = try await self.request("auth/loginlink", query: ["user": name])
            self.username = name
            UserDefaults.standard.set(name, forKey: Self.usernameKey)
            self.isWaitingForPassphrase = true
        }
    }

    /// Step 2: trades the passphrase for a key and saves it in the Keychain.
    func signIn(passphrase: String) async {
        guard let username else { return }
        let words = passphrase.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).joined(separator: " ")
        await run {
            let login = try await self.request("auth/login", query: ["otp": words, "user": username])
            guard let token = login["token"] as? String else { throw MaskingError("That passphrase didn't work. Check the email and try again.") }
            let dashboard = try await self.request("email/dashboard", token: token)
            guard let user = dashboard["user"] as? [String: Any],
                  let accessToken = user["access_token"] as? String else {
                throw MaskingError("DuckDuckGo signed you in but didn't send a key. Try again.")
            }
            self.secret.write(accessToken)
            self.isConnected = true
            self.isWaitingForPassphrase = false
        }
    }

    func signOut() {
        secret.write("")
        isConnected = false
        isWaitingForPassphrase = false
    }

    /// Makes a brand-new private address, like "k7bq2mx9@duck.com".
    func newAddress() async throws -> String {
        guard let token = secret.read() else { throw MaskingError("Set up email masking in Settings ▸ Privacy first.") }
        let reply = try await request("email/addresses", method: "POST", token: token)
        guard let name = reply["address"] as? String, !name.isEmpty else {
            throw MaskingError("DuckDuckGo didn't send an address. Try again in a moment.")
        }
        return name + "@duck.com"
    }

    // MARK: Talking to DuckDuckGo

    private func run(_ work: @escaping () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        do { try await work() } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func request(_ path: String, method: String = "GET", query: [String: String] = [:], token: String? = nil) async throws -> [String: Any] {
        guard var components = URLComponents(string: "\(base)/\(path)") else { throw MaskingError("Bad address.") }
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw MaskingError("Bad address.") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 {
            if token != nil, path == "email/addresses" { signOut() }
            throw MaskingError("DuckDuckGo didn't accept the sign-in. Set up email masking again in Settings ▸ Privacy.")
        }
        guard (200..<300).contains(status) else { throw MaskingError("DuckDuckGo answered with error \(status). Try again later.") }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

struct MaskingError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
