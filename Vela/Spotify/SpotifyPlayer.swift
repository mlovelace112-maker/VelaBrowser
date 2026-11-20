import AppKit
import Foundation
import Observation
import WebKit

/// The song or episode that's playing.
struct SpotifyTrack: Equatable {
    let uri: String
    let title: String
    let artist: String
    let artURL: URL?
    let duration: Double
    let link: URL?
}

/// A track, album or playlist you can play from the library popover.
struct SpotifyItem: Identifiable, Equatable {
    enum Kind: String { case track, album, playlist }

    let uri: String
    let name: String
    let subtitle: String
    let imageURL: URL?
    let kind: Kind

    var id: String { uri }
}

/// A place Spotify can play: Vela itself, your phone, a speaker…
struct SpotifyDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let type: String
    let isActive: Bool
}

/// The Spotify mini player.
///
/// **Two halves:**
/// 1. **Vela as a speaker.** Spotify's Web Playback SDK runs in a tiny hidden
///    web page, so Vela shows up in Spotify as a device called "Vela", like a
///    phone or a smart speaker. That's how music plays without the Spotify app.
/// 2. **The remote control.** The bar's buttons use the Spotify Web API
///    (`api.spotify.com/v1/me/player/…`), which controls whichever device is
///    playing: Vela, or your phone if you started music there.
@MainActor
@Observable
final class SpotifyPlayer {
    enum EngineState: Equatable {
        case off
        case starting
        case ready(deviceID: String)
        case unavailable(String)
    }

    private(set) var clientID: String
    private(set) var isConnected: Bool
    private(set) var isConnecting = false
    var isBarVisible: Bool {
        didSet { UserDefaults.standard.set(isBarVisible, forKey: "vela.spotifyBarVisible") }
    }

    private(set) var track: SpotifyTrack?
    private(set) var isPlaying = false
    /// Seconds into the track when `progressDate` was measured.
    private(set) var progress: Double = 0
    private(set) var progressDate = Date()
    private(set) var volume: Double = 0.6
    private(set) var activeDevice: String?
    private(set) var devices: [SpotifyDevice] = []
    private(set) var engine: EngineState = .off
    var message: String?

    // Library popover
    private(set) var playlists: [SpotifyItem] = []
    private(set) var searchResults: [SpotifyItem] = []

    @ObservationIgnored private var tokens: SpotifyTokens?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private(set) var engineView: WKWebView?
    @ObservationIgnored private var bridge: SpotifyBridge?

    private static let refreshKeychain = KeychainSecret(service: "Vela Spotify", account: "refresh-token")
    private static let clientIDKey = "vela.spotifyClientID"

    init() {
        clientID = UserDefaults.standard.string(forKey: Self.clientIDKey) ?? ""
        isConnected = Self.refreshKeychain.read() != nil
        isBarVisible = UserDefaults.standard.object(forKey: "vela.spotifyBarVisible") as? Bool ?? true
        if isConnected { start() }
    }

    /// Where the progress bar is right now (it keeps moving between updates).
    func position(at date: Date) -> Double {
        guard let track else { return 0 }
        let elapsed = isPlaying ? date.timeIntervalSince(progressDate) : 0
        return min(max(progress + elapsed, 0), track.duration)
    }

    // MARK: - Connecting

    func setClientID(_ id: String) {
        clientID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(clientID, forKey: Self.clientIDKey)
    }

    func connect() async {
        guard !clientID.isEmpty else {
            message = SpotifyError.noClientID.localizedDescription
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let tokens = try await SpotifyAuth.signIn(clientID: clientID)
            self.tokens = tokens
            if let refresh = tokens.refreshToken { Self.refreshKeychain.write(refresh) }
            isConnected = true
            message = nil
            start()
        } catch SpotifyError.cancelled {
            // You closed the sign-in window; nothing to report.
        } catch {
            message = error.localizedDescription
        }
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        engineView?.evaluateJavaScript("window.velaPlayer && window.velaPlayer.disconnect()")
        engineView = nil
        bridge = nil
        engine = .off
        tokens = nil
        Self.refreshKeychain.write("")
        isConnected = false
        track = nil
        isPlaying = false
        devices = []
        playlists = []
        searchResults = []
    }

    private func start() {
        startEngine()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                // Check often while music plays, less often when it doesn't.
                try? await Task.sleep(for: .seconds(self.isPlaying ? 3 : 8))
            }
        }
        Task { await loadPlaylists() }
    }

    /// A fresh access token, renewing it when it's about to run out.
    private func accessToken() async throws -> String {
        if let tokens, tokens.expires.timeIntervalSinceNow > 60 { return tokens.accessToken }
        guard let refresh = tokens?.refreshToken ?? Self.refreshKeychain.read() else {
            throw SpotifyError.notConnected
        }
        do {
            let fresh = try await SpotifyAuth.refresh(refresh, clientID: clientID)
            if let newRefresh = fresh.refreshToken, newRefresh != refresh { Self.refreshKeychain.write(newRefresh) }
            tokens = SpotifyTokens(accessToken: fresh.accessToken, refreshToken: fresh.refreshToken ?? refresh, expires: fresh.expires)
            return fresh.accessToken
        } catch SpotifyError.signIn(let reason) where reason.contains("invalid") || reason.contains("revoked") {
            // The sign-in was withdrawn (for example from your Spotify account page).
            disconnect()
            throw SpotifyError.notConnected
        }
    }

    // MARK: - Web API

    @discardableResult
    private func api(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: [String: Any]? = nil,
        retrying: Bool = false
    ) async throws -> [String: Any]? {
        let token = try await accessToken()
        var components = URLComponents(string: "https://api.spotify.com/v1" + path)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else if method != "GET" {
            request.httpBody = Data()
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, !retrying {
            tokens = nil
            return try await api(method, path, query: query, body: body, retrying: true)
        }
        if status == 204 || data.isEmpty { return nil }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else {
            let error = json?["error"] as? [String: Any]
            let message = error?["message"] as? String ?? ""
            let reason = error?["reason"] as? String ?? ""
            if status == 404, reason == "NO_ACTIVE_DEVICE" || message.localizedCaseInsensitiveContains("no active device") {
                throw SpotifyError.noDevice
            }
            throw SpotifyError.api(status: status, message: message)
        }
        return json
    }

    /// Asks Spotify what's playing.
    func refresh() async {
        do {
            guard let state = try await api("GET", "/me/player", query: ["additional_types": "episode"]) else {
                // 204: nothing is playing anywhere.
                isPlaying = false
                activeDevice = nil
                return
            }
            isPlaying = state["is_playing"] as? Bool ?? false
            progress = ((state["progress_ms"] as? NSNumber)?.doubleValue ?? 0) / 1000
            progressDate = Date()
            if let device = state["device"] as? [String: Any] {
                activeDevice = device["name"] as? String
                if let percent = (device["volume_percent"] as? NSNumber)?.doubleValue { volume = percent / 100 }
            }
            if let item = state["item"] as? [String: Any] {
                let parsed = Self.track(from: item)
                if parsed != track { track = parsed }
            }
        } catch {
            // A missed update isn't worth a message; the next one will try again.
        }
    }

    private static func track(from item: [String: Any]) -> SpotifyTrack {
        let album = item["album"] as? [String: Any]
        let show = item["show"] as? [String: Any]
        let artists = (item["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let images = (album?["images"] ?? item["images"] ?? show?["images"]) as? [[String: Any]]
        return SpotifyTrack(
            uri: item["uri"] as? String ?? "",
            title: item["name"] as? String ?? "Unknown",
            artist: artists.isEmpty ? (show?["name"] as? String ?? "") : artists.joined(separator: ", "),
            artURL: smallestImage(images, atLeast: 64),
            duration: ((item["duration_ms"] as? NSNumber)?.doubleValue ?? 0) / 1000,
            link: ((item["external_urls"] as? [String: Any])?["spotify"] as? String).flatMap(URL.init(string:))
        )
    }

    /// Spotify lists cover art from largest to smallest; take the smallest that's big enough.
    private static func smallestImage(_ images: [[String: Any]]?, atLeast size: Int) -> URL? {
        let sorted = (images ?? []).sorted {
            (($0["width"] as? NSNumber)?.intValue ?? 0) < (($1["width"] as? NSNumber)?.intValue ?? 0)
        }
        let pick = sorted.first { (($0["width"] as? NSNumber)?.intValue ?? size) >= size } ?? sorted.last
        return (pick?["url"] as? String).flatMap(URL.init(string:))
    }

    // MARK: - Controls

    func togglePlay() async {
        await run {
            if self.isPlaying {
                try await self.api("PUT", "/me/player/pause")
                self.isPlaying = false
            } else {
                try await self.play(body: nil)
            }
        }
    }

    func next() async { await run { _ = try await self.api("POST", "/me/player/next") } }

    func previous() async { await run { _ = try await self.api("POST", "/me/player/previous") } }

    func seek(to seconds: Double) async {
        progress = seconds
        progressDate = Date()
        await run { _ = try await self.api("PUT", "/me/player/seek", query: ["position_ms": String(Int(seconds * 1000))]) }
    }

    func setVolume(_ value: Double) async {
        volume = value
        await run(refreshing: false) {
            _ = try await self.api("PUT", "/me/player/volume", query: ["volume_percent": String(Int(value * 100))])
        }
    }

    func play(_ item: SpotifyItem) async {
        let body: [String: Any] = item.kind == .track ? ["uris": [item.uri]] : ["context_uri": item.uri]
        await run { try await self.play(body: body) }
    }

    /// Starts playback. If nothing is playing anywhere, Vela itself becomes the speaker.
    private func play(body: [String: Any]?) async throws {
        do {
            try await api("PUT", "/me/player/play", body: body)
        } catch SpotifyError.noDevice {
            guard case .ready(let deviceID) = engine else { throw SpotifyError.noDevice }
            try await api("PUT", "/me/player/play", query: ["device_id": deviceID], body: body ?? [:])
        }
        isPlaying = true
    }

    func loadDevices() async {
        await run(refreshing: false) {
            let json = try await self.api("GET", "/me/player/devices")
            self.devices = (json?["devices"] as? [[String: Any]] ?? []).compactMap { device in
                guard let id = device["id"] as? String else { return nil }
                return SpotifyDevice(
                    id: id,
                    name: device["name"] as? String ?? "Device",
                    type: device["type"] as? String ?? "",
                    isActive: device["is_active"] as? Bool ?? false
                )
            }
        }
    }

    /// Moves playback to another device, such as from your phone to Vela.
    func transfer(to device: SpotifyDevice) async {
        await run { _ = try await self.api("PUT", "/me/player", body: ["device_ids": [device.id], "play": true]) }
        await loadDevices()
    }

    /// Runs a control, shows any error, then checks what's playing.
    private func run(refreshing: Bool = true, _ action: () async throws -> Void) async {
        do {
            try await action()
            message = nil
        } catch {
            message = error.localizedDescription
        }
        if refreshing {
            try? await Task.sleep(for: .milliseconds(350))
            await refresh()
        }
    }

    // MARK: - Library

    func loadPlaylists() async {
        guard let json = try? await api("GET", "/me/playlists", query: ["limit": "30"]) else { return }
        playlists = (json["items"] as? [Any] ?? []).compactMap { Self.item(from: $0, kind: .playlist) }
    }

    func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        do {
            guard let json = try await api("GET", "/search", query: ["q": query, "type": "track,album,playlist", "limit": "6"]) else { return }
            var results: [SpotifyItem] = []
            for kind in [SpotifyItem.Kind.track, .album, .playlist] {
                let section = json[kind.rawValue + "s"] as? [String: Any]
                results += (section?["items"] as? [Any] ?? []).compactMap { Self.item(from: $0, kind: kind) }
            }
            searchResults = results
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private static func item(from value: Any, kind: SpotifyItem.Kind) -> SpotifyItem? {
        // Spotify sometimes sends `null` in these lists; skip those.
        guard let json = value as? [String: Any], let uri = json["uri"] as? String else { return nil }
        let subtitle: String
        let images: [[String: Any]]?
        switch kind {
        case .track:
            subtitle = (json["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
            images = (json["album"] as? [String: Any])?["images"] as? [[String: Any]]
        case .album:
            subtitle = "Album · " + (json["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
            images = json["images"] as? [[String: Any]]
        case .playlist:
            let owner = (json["owner"] as? [String: Any])?["display_name"] as? String
            subtitle = "Playlist" + (owner.map { " · \($0)" } ?? "")
            images = json["images"] as? [[String: Any]]
        }
        return SpotifyItem(
            uri: uri,
            name: json["name"] as? String ?? "Untitled",
            subtitle: subtitle,
            imageURL: smallestImage(images, atLeast: 64),
            kind: kind
        )
    }

    // MARK: - Vela as a speaker (Web Playback SDK)

    private func startEngine() {
        guard engineView == nil else { return }
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = SafariIdentity.applicationName
        let bridge = SpotifyBridge { [weak self] message in self?.handleEngineMessage(message) }
        configuration.userContentController.add(bridge, name: "velaSpotify")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 2, height: 2), configuration: configuration)
        webView.loadHTMLString(Self.engineHTML, baseURL: URL(string: "https://vela.app/spotify"))
        self.bridge = bridge
        engineView = webView
        engine = .starting
    }

    private func handleEngineMessage(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "needToken":
            Task {
                guard let token = try? await accessToken() else { return }
                engineView?.callAsyncJavaScript(
                    "if (window.__velaToken) { window.__velaToken(token); }",
                    arguments: ["token": token],
                    in: nil,
                    in: .page,
                    completionHandler: nil
                )
            }
        case "ready":
            if let id = body["deviceID"] as? String { engine = .ready(deviceID: id) }
        case "notReady":
            engine = .starting
        case "error":
            let kind = body["kind"] as? String ?? ""
            let text = body["message"] as? String ?? ""
            if kind == "initialization" || kind == "account" {
                engine = .unavailable(kind == "account"
                    ? "Playing music in Vela needs Spotify Premium."
                    : "This Mac's WebKit can't run Spotify's player (\(text)). The bar can still control Spotify on your phone or another device.")
            } else if kind == "authentication" {
                tokens = nil
            }
        case "state":
            Task { await refresh() }
        default:
            break
        }
    }

    /// The hidden page that runs Spotify's player.
    private static let engineHTML = """
    <!doctype html>
    <html><head><meta charset="utf-8"></head><body>
    <script>
      const post = (message) => window.webkit.messageHandlers.velaSpotify.postMessage(message);
      window.onSpotifyWebPlaybackSDKReady = () => {
        const player = new Spotify.Player({
          name: 'Vela',
          volume: 0.6,
          getOAuthToken: (callback) => { window.__velaToken = callback; post({ type: 'needToken' }); }
        });
        player.addListener('ready', ({ device_id }) => post({ type: 'ready', deviceID: device_id }));
        player.addListener('not_ready', () => post({ type: 'notReady' }));
        player.addListener('initialization_error', ({ message }) => post({ type: 'error', kind: 'initialization', message }));
        player.addListener('authentication_error', ({ message }) => post({ type: 'error', kind: 'authentication', message }));
        player.addListener('account_error', ({ message }) => post({ type: 'error', kind: 'account', message }));
        player.addListener('playback_error', ({ message }) => post({ type: 'error', kind: 'playback', message }));
        player.addListener('player_state_changed', () => post({ type: 'state' }));
        player.connect();
        window.velaPlayer = player;
      };
    </script>
    <script src="https://sdk.scdn.co/spotify-player.js"></script>
    </body></html>
    """
}

/// Passes messages from the hidden player page to Swift.
@MainActor
private final class SpotifyBridge: NSObject, WKScriptMessageHandler {
    let onMessage: @MainActor ([String: Any]) -> Void

    init(onMessage: @escaping @MainActor ([String: Any]) -> Void) {
        self.onMessage = onMessage
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        onMessage(body)
    }
}
