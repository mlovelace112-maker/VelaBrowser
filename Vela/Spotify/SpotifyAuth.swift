import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

enum SpotifyError: LocalizedError {
    case noClientID
    case cancelled
    case signIn(String)
    case notConnected
    case noDevice
    case api(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noClientID: "Paste your Spotify Client ID in Settings ▸ Spotify first."
        case .cancelled: "Spotify sign-in was cancelled."
        case .signIn(let message): "Spotify sign-in didn't work: \(message)"
        case .notConnected: "Connect Spotify in Settings ▸ Spotify."
        case .noDevice: "Nothing is playing yet. Pick something from your library, or wait a moment for Vela's player to start."
        case .api(403, _): "Spotify said no. Playback control needs Spotify Premium, and your account must be added to the app's users in the Spotify dashboard."
        case .api(429, _): "Spotify asked Vela to slow down. Try again in a moment."
        case .api(let status, let message): message.isEmpty ? "Spotify returned an error (\(status))." : message
        }
    }
}

/// The keys Spotify gives Vela after you sign in.
struct SpotifyTokens {
    let accessToken: String
    let refreshToken: String?
    let expires: Date
}

/// Signing in to Spotify.
///
/// **How it works (OAuth with PKCE):** Vela opens Spotify's sign-in page in a
/// secure sheet. After you approve, Spotify sends the browser to
/// `vela-spotify://callback?code=…`, and macOS hands that address back to Vela.
/// Vela trades the one-time code for an *access token* (good for an hour) and
/// a *refresh token* (used to get new access tokens). PKCE is a secret Vela
/// invents for each sign-in so a stolen code is useless to anyone else, which
/// is why Vela doesn't need a "client secret".
@MainActor
enum SpotifyAuth {
    static let redirectURI = "vela-spotify://callback"
    static let scopes = [
        "streaming",
        "user-read-email",
        "user-read-private",
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "playlist-read-private",
    ]

    /// The sign-in sheet; kept alive while it's open.
    private static var session: ASWebAuthenticationSession?
    private static var presenter: AuthPresenter?

    static func signIn(clientID: String) async throws -> SpotifyTokens {
        let verifier = randomVerifier()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let state = UUID().uuidString

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callback: .customScheme("vela-spotify")) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: SpotifyError.cancelled)
                } else {
                    continuation.resume(throwing: SpotifyError.signIn(error?.localizedDescription ?? "no reply"))
                }
            }
            let presenter = AuthPresenter(anchor: NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow())
            session.presentationContextProvider = presenter
            Self.session = session
            Self.presenter = presenter
            if !session.start() {
                continuation.resume(throwing: SpotifyError.signIn("the sign-in window couldn't open"))
            }
        }
        session = nil
        presenter = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw error == "access_denied" ? SpotifyError.cancelled : SpotifyError.signIn(error)
        }
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw SpotifyError.signIn("Spotify's reply didn't match this sign-in")
        }

        return try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
    }

    static func refresh(_ refreshToken: String, clientID: String) async throws -> SpotifyTokens {
        try await requestTokens([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
    }

    private static func requestTokens(_ form: [String: String]) async throws -> SpotifyTokens {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(form).utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let access = json["access_token"] as? String else {
            let reason = json["error_description"] as? String ?? json["error"] as? String ?? "unknown error"
            throw SpotifyError.signIn(reason)
        }
        let lifetime = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return SpotifyTokens(
            accessToken: access,
            refreshToken: json["refresh_token"] as? String,
            expires: Date().addingTimeInterval(lifetime)
        )
    }

    /// 64 random letters and digits.
    private static func randomVerifier() -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var random = SystemRandomNumberGenerator()
        return String((0..<64).map { _ in characters.randomElement(using: &random)! })
    }

    private static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.map { key, value in
            key + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
        }
        .joined(separator: "&")
    }
}

/// Tells the sign-in sheet which window to attach to.
private final class AuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: NSWindow

    init(anchor: NSWindow) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}

private extension Data {
    /// Base64 that's safe in a web address: no "+", "/" or "=".
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
