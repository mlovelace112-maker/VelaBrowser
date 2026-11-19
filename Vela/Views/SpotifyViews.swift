import AppKit
import SwiftUI
import WebKit

/// The slim Spotify player along the bottom of the window: cover art, the
/// song, play controls, a progress line, your library and devices.
struct SpotifyBar: View {
    @Environment(BrowserStore.self) private var store
    @State private var isLibraryOpen = false
    @State private var isDevicesOpen = false

    var body: some View {
        let spotify = store.spotify

        HStack(spacing: 12) {
            if spotify.isConnected {
                nowPlaying(spotify)
                Spacer(minLength: 12)
                controls(spotify)
                Spacer(minLength: 12)
                trailingButtons(spotify)
            } else {
                setUp(spotify)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(VisualEffectBackground())
        .overlay(alignment: .top) {
            Rectangle().fill(Nightglass.stroke).frame(height: 1)
        }
        .overlay(alignment: .top) {
            if spotify.isConnected, spotify.track != nil {
                ProgressLine(spotify: spotify)
            }
        }
        // The hidden player that makes Vela a Spotify speaker. It has to be in
        // the window for its audio to keep playing.
        .background(alignment: .bottomLeading) {
            if let engine = spotify.engineView {
                EngineHost(webView: engine)
                    .frame(width: 2, height: 2)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func nowPlaying(_ spotify: SpotifyPlayer) -> some View {
        HStack(spacing: 10) {
            CoverArt(url: spotify.track?.artURL, size: 36)
                .scaleEffect(spotify.isPlaying ? 1 : 0.94)
                .animation(Nightglass.spring, value: spotify.isPlaying)
            VStack(alignment: .leading, spacing: 2) {
                if let track = spotify.track {
                    Text(track.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Nightglass.text)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                    Text(track.artist)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Nightglass.mutedText)
                        .lineLimit(1)
                } else {
                    Text("Nothing playing")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Nightglass.secondaryText)
                    Text(spotify.message ?? statusText(spotify))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Nightglass.mutedText)
                        .lineLimit(1)
                }
            }
            .animation(.easeOut(duration: 0.25), value: spotify.track)
            if spotify.track != nil, let message = spotify.message {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Nightglass.caution)
                    .help(message)
            }
        }
        .frame(minWidth: 180, maxWidth: 300, alignment: .leading)
        .contextMenu {
            if let link = spotify.track?.link {
                Button("Open in a New Tab") { store.open(link, inNewTab: true) }
            }
        }
    }

    private func statusText(_ spotify: SpotifyPlayer) -> String {
        switch spotify.engine {
        case .ready: "Pick something from your library to play it in Vela"
        case .starting: "Starting Vela's player…"
        case .unavailable(let reason): reason
        case .off: "Open your library to play something"
        }
    }

    private func controls(_ spotify: SpotifyPlayer) -> some View {
        HStack(spacing: 6) {
            Button { Task { await spotify.previous() } } label: { Image(systemName: "backward.fill") }
                .buttonStyle(IconButtonStyle(size: 30))
                .help("Previous")
            Button { Task { await spotify.togglePlay() } } label: {
                Image(systemName: spotify.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0B0B12))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Nightglass.spotify))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(spotify.isPlaying ? "Pause" : "Play")
            Button { Task { await spotify.next() } } label: { Image(systemName: "forward.fill") }
                .buttonStyle(IconButtonStyle(size: 30))
                .help("Next")
        }
    }

    private func trailingButtons(_ spotify: SpotifyPlayer) -> some View {
        HStack(spacing: 4) {
            if let device = spotify.activeDevice {
                Text(device)
                    .font(.system(size: 11))
                    .foregroundStyle(Nightglass.spotify)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .trailing)
            }
            Button { isLibraryOpen.toggle() } label: { Image(systemName: "music.note.list") }
                .buttonStyle(IconButtonStyle(size: 30))
                .help("Your Library and Search")
                .popover(isPresented: $isLibraryOpen, arrowEdge: .top) {
                    SpotifyLibrary()
                }
            Button { isDevicesOpen.toggle() } label: { Image(systemName: "hifispeaker.and.homepod") }
                .buttonStyle(IconButtonStyle(size: 30))
                .help("Volume and Devices")
                .popover(isPresented: $isDevicesOpen, arrowEdge: .top) {
                    SpotifyDevices()
                }
            Button { withAnimation(Nightglass.spring) { spotify.isBarVisible = false } } label: { Image(systemName: "chevron.down") }
                .buttonStyle(IconButtonStyle(size: 30))
                .help("Hide Player (⌥⌘S)")
        }
    }

    private func setUp(_ spotify: SpotifyPlayer) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Nightglass.spotify)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Nightglass.spotify.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Play Spotify in Vela")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(spotify.message ?? (spotify.clientID.isEmpty
                    ? "Add your Spotify Client ID in Settings ▸ Spotify to get started."
                    : "Sign in to Spotify to play music here."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
                    .lineLimit(1)
            }
            Spacer()
            if spotify.clientID.isEmpty {
                SettingsLink { Text("Open Settings") }
            } else {
                Button(spotify.isConnecting ? "Connecting…" : "Connect Spotify") {
                    Task { await spotify.connect() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Nightglass.spotify)
                .disabled(spotify.isConnecting)
            }
            Button { withAnimation(Nightglass.spring) { spotify.isBarVisible = false } } label: { Image(systemName: "chevron.down") }
                .buttonStyle(IconButtonStyle(size: 30))
                .help("Hide Player (⌥⌘S)")
        }
        .controlSize(.small)
    }
}

/// The thin line along the top of the bar showing how far into the song you
/// are. Click anywhere on it to jump there.
private struct ProgressLine: View {
    let spotify: SpotifyPlayer
    @State private var isHovering = false

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let duration = max(spotify.track?.duration ?? 1, 1)
                let fraction = spotify.position(at: context.date) / duration
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(isHovering ? 0.14 : 0.06))
                    Rectangle()
                        .fill(LinearGradient(colors: [Nightglass.spotify, Nightglass.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * fraction)
                        .shadow(color: Nightglass.spotify.opacity(0.6), radius: 3)
                        .animation(.linear(duration: 0.5), value: fraction)
                }
            }
            .contentShape(Rectangle().inset(by: -4))
            .onTapGesture(coordinateSpace: .local) { location in
                guard let duration = spotify.track?.duration, geometry.size.width > 0 else { return }
                Task { await spotify.seek(to: duration * max(0, min(1, location.x / geometry.size.width))) }
            }
            .onHover { isHovering = $0 }
        }
        .frame(height: isHovering ? 4 : 2)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .help("Click to jump to a point in the song")
    }
}

/// Album covers, with a soft placeholder while they load.
struct CoverArt: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                shape.fill(Nightglass.spotify.opacity(0.15))
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(Nightglass.spotify)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08)))
        .accessibilityHidden(true)
    }
}

/// Search Spotify and see your playlists. Click anything to play it.
private struct SpotifyLibrary: View {
    @Environment(BrowserStore.self) private var store
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        let spotify = store.spotify
        let showingSearch = !query.trimmingCharacters(in: .whitespaces).isEmpty

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Nightglass.mutedText)
                    .accessibilityHidden(true)
                TextField("Search songs, albums and playlists", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.35)))

            if let message = spotify.message {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(showingSearch ? "Results" : "Your Playlists")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Nightglass.mutedText)

            ScrollView {
                LazyVStack(spacing: 2) {
                    let items = showingSearch ? spotify.searchResults : spotify.playlists
                    if items.isEmpty {
                        Text(showingSearch ? "No results yet." : "No playlists found.")
                            .font(.system(size: 12))
                            .foregroundStyle(Nightglass.mutedText)
                            .padding(20)
                    }
                    ForEach(items) { item in
                        LibraryRow(item: item) { Task { await spotify.play(item) } }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 340, height: 420)
        .onAppear { Task { await spotify.loadPlaylists() } }
        .onChange(of: query) {
            // Wait until you stop typing for a moment before searching.
            searchTask?.cancel()
            let text = query
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await spotify.search(text)
            }
        }
    }
}

private struct LibraryRow: View {
    let item: SpotifyItem
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                CoverArt(url: item.imageURL, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Nightglass.text)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Nightglass.mutedText)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Nightglass.spotify)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(isHovering ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Volume, and which device plays the music.
private struct SpotifyDevices: View {
    @Environment(BrowserStore.self) private var store
    @State private var volume = 0.6

    var body: some View {
        let spotify = store.spotify

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").foregroundStyle(Nightglass.mutedText)
                Slider(value: $volume, in: 0...1, onEditingChanged: { editing in
                    if !editing { Task { await spotify.setVolume(volume) } }
                })
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(Nightglass.mutedText)
            }

            Text("Play On")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Nightglass.mutedText)

            if spotify.devices.isEmpty {
                Text("No devices found. Vela appears here once its player has started.")
                    .font(.system(size: 12))
                    .foregroundStyle(Nightglass.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(spotify.devices) { device in
                Button { Task { await spotify.transfer(to: device) } } label: {
                    HStack {
                        Image(systemName: icon(for: device.type))
                            .frame(width: 18)
                        Text(device.name)
                        Spacer()
                        if device.isActive {
                            Image(systemName: "checkmark").foregroundStyle(Nightglass.spotify)
                        }
                    }
                    .font(.system(size: 12.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if case .unavailable(let reason) = spotify.engine {
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundStyle(Nightglass.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear {
            volume = spotify.volume
            Task { await spotify.loadDevices() }
        }
    }

    private func icon(for type: String) -> String {
        switch type.lowercased() {
        case "smartphone": "iphone"
        case "computer": "laptopcomputer"
        case "speaker": "hifispeaker"
        case "tv": "tv"
        default: "music.note"
        }
    }
}

/// Puts the hidden player's web view into the window.
private struct EngineHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Settings ▸ Spotify.
struct SpotifySettingsTab: View {
    @Environment(BrowserStore.self) private var store
    @State private var clientIDDraft = ""

    var body: some View {
        @Bindable var spotify = store.spotify

        Form {
            Section {
                HStack {
                    TextField("Client ID", text: $clientIDDraft, prompt: Text("Paste from the Spotify dashboard"))
                    Button("Save") { spotify.setClientID(clientIDDraft) }
                        .disabled(clientIDDraft.trimmingCharacters(in: .whitespaces) == spotify.clientID)
                }
                LabeledContent("Redirect URI") {
                    HStack {
                        Text(SpotifyAuth.redirectURI)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(SpotifyAuth.redirectURI, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Copy")
                    }
                }
            } header: {
                Text("Spotify app")
            } footer: {
                Text("At developer.spotify.com/dashboard, create an app, add the redirect URI above, and tick Web API and Web Playback SDK. Then paste its Client ID here. Playing music needs Spotify Premium.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
            }

            Section("Account") {
                if spotify.isConnected {
                    HStack {
                        Label("Connected to Spotify", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Nightglass.safe)
                        Spacer()
                        Button("Disconnect") { spotify.disconnect() }
                            .controlSize(.small)
                    }
                } else {
                    Button(spotify.isConnecting ? "Connecting…" : "Connect Spotify") {
                        Task { await spotify.connect() }
                    }
                    .disabled(spotify.clientID.isEmpty || spotify.isConnecting)
                }
                if let message = spotify.message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Nightglass.caution)
                }
                Toggle("Show the player bar", isOn: $spotify.isBarVisible)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .tint(Nightglass.accent)
        .onAppear { clientIDDraft = store.spotify.clientID }
    }
}
