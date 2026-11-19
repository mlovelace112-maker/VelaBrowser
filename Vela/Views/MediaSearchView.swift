import AppKit
import SwiftUI

/// Vela's own image and video results: a glass grid that fills the tab.
struct MediaSearchView: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab
    let search: MediaSearch
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 18) {
                    if search.kind == .images {
                        imageGrid
                    } else {
                        videoGrid
                    }
                    footer
                }
                .padding(20)
            }
        }
        .overlay {
            if let image = search.preview {
                ImagePreview(image: image, search: search, tab: tab)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(Nightglass.spring, value: search.preview)
        .onAppear { draft = search.query }
        .onChange(of: search.query) { draft = search.query }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Nightglass.mutedText)
                    .accessibilityHidden(true)
                TextField("Search \(search.kind.rawValue.lowercased())", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit { search.search(draft) }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: 520, minHeight: 36)
            .glassPanel(cornerRadius: 12)

            KindPicker(selection: search.kind) { kind in
                search.search(draft, kind: kind)
                tab.title = search.title
            }

            Button {
                var components = URLComponents(string: "https://duckduckgo.com/")!
                components.queryItems = [URLQueryItem(name: "q", value: search.query)]
                if let url = components.url { tab.load(url) }
            } label: {
                Label("Web", systemImage: "globe")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Nightglass.secondaryText)
            .help("Show web results")

            Spacer()
            Text("Results from DuckDuckGo")
                .font(.system(size: 11))
                .foregroundStyle(Nightglass.mutedText)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var imageGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            ForEach(Array(search.images.enumerated()), id: \.element.id) { index, image in
                ImageTile(image: image, index: index) { search.preview = image }
                    .onAppear { if index >= search.images.count - 8 { search.loadMore() } }
            }
        }
    }

    private var videoGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 16)], spacing: 18) {
            ForEach(Array(search.videos.enumerated()), id: \.element.id) { index, video in
                VideoTile(video: video, index: index) { tab.load(video.page) }
                    .onAppear { if index >= search.videos.count - 6 { search.loadMore() } }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if search.isLoading {
            ProgressView()
                .controlSize(.small)
                .padding(20)
        } else if let error = search.error {
            VStack(spacing: 10) {
                Label(error, systemImage: "wifi.exclamationmark")
                    .foregroundStyle(Nightglass.caution)
                Button("Try Again") { search.search() }
            }
            .font(.system(size: 12.5))
            .padding(30)
        } else if search.isEmpty {
            Text("No \(search.kind.rawValue.lowercased()) found for “\(search.query)”.")
                .font(.system(size: 13))
                .foregroundStyle(Nightglass.mutedText)
                .padding(40)
        }
    }
}

/// "Images | Videos" with a sliding highlight.
private struct KindPicker: View {
    let selection: MediaSearch.Kind
    let choose: (MediaSearch.Kind) -> Void
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MediaSearch.Kind.allCases) { kind in
                Button { if kind != selection { choose(kind) } } label: {
                    Label(kind.rawValue, systemImage: kind == .images ? "photo.on.rectangle" : "play.rectangle")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(kind == selection ? Nightglass.text : Nightglass.mutedText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if kind == selection {
                                Capsule()
                                    .fill(Nightglass.accent.opacity(0.28))
                                    .matchedGeometryEffect(id: "highlight", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.3)))
        .animation(Nightglass.spring, value: selection)
    }
}

/// Fades and lifts each tile in, one after another.
private struct Arrival: ViewModifier {
    let index: Int
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 12)
            .onAppear {
                withAnimation(Nightglass.spring?.delay(Double(index % 24) * 0.025)) { isVisible = true }
            }
    }
}

private struct ImageTile: View {
    let image: ImageResult
    let index: Int
    let open: () -> Void
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        Button(action: open) {
            AsyncImage(url: image.thumbnail) { loaded in
                loaded.resizable().scaledToFill()
            } placeholder: {
                shape.fill(Color.white.opacity(0.05))
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(image.title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    Text(image.source).font(.system(size: 10.5)).opacity(0.75).lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .opacity(isHovering ? 1 : 0)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(isHovering ? Nightglass.accent.opacity(0.7) : Color.white.opacity(0.08)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.03 : 1)
        .shadow(color: Nightglass.accent.opacity(isHovering ? 0.3 : 0), radius: 12)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovering)
        .modifier(Arrival(index: index))
        .help(image.title)
    }
}

private struct VideoTile: View {
    let video: VideoResult
    let index: Int
    let open: () -> Void
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: video.thumbnail) { loaded in
                    loaded.resizable().scaledToFill()
                } placeholder: {
                    shape.fill(Color.white.opacity(0.05))
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(shape)
                .overlay(alignment: .bottomTrailing) {
                    if !video.duration.isEmpty {
                        Text(video.duration)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.7)))
                            .padding(6)
                    }
                }
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(.black.opacity(0.45)))
                        .scaleEffect(isHovering ? 1 : 0.6)
                        .opacity(isHovering ? 1 : 0)
                }
                .overlay(shape.strokeBorder(isHovering ? Nightglass.accent.opacity(0.7) : Color.white.opacity(0.08)))

                Text(video.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Nightglass.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(details)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(y: isHovering ? -3 : 0)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovering)
        .modifier(Arrival(index: index))
    }

    private var details: String {
        var parts = [video.publisher]
        if let views = video.views {
            parts.append(views.formatted(.number.notation(.compactName)) + " views")
        }
        if let published = video.published {
            parts.append(published.formatted(.relative(presentation: .named)))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// A big view of one image, with ways to open it or the page it's from.
private struct ImagePreview: View {
    let image: ImageResult
    let search: MediaSearch
    let tab: BrowserTab

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .onTapGesture { search.preview = nil }
            VStack(spacing: 14) {
                AsyncImage(url: image.image) { phase in
                    switch phase {
                    case .success(let loaded):
                        loaded.resizable().scaledToFit()
                    case .failure:
                        // Some sites block hotlinking; fall back to the thumbnail.
                        AsyncImage(url: image.thumbnail) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                    default:
                        ProgressView()
                    }
                }
                .frame(maxWidth: 900, maxHeight: 560)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 30)

                VStack(spacing: 4) {
                    Text(image.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(image.width > 0 ? "\(image.source) · \(image.width) × \(image.height)" : image.source)
                        .font(.system(size: 12))
                        .foregroundStyle(Nightglass.mutedText)
                }
                .foregroundStyle(Nightglass.text)

                HStack(spacing: 10) {
                    if let page = image.page {
                        Button("Visit Page") { tab.load(page) }
                            .buttonStyle(.borderedProminent)
                            .tint(Nightglass.accent)
                    }
                    Button("Open Image") { tab.load(image.image) }
                    Button("Copy Image Address") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(image.image.absoluteString, forType: .string)
                    }
                    Button("Close") { search.preview = nil }
                        .keyboardShortcut(.cancelAction)
                }
                .controlSize(.regular)
            }
            .padding(30)
        }
    }
}

/// The "Images · Videos" pill floating over DuckDuckGo search results.
struct MediaSearchPill: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab
    let query: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MediaSearch.Kind.allCases) { kind in
                Button { store.showMediaSearch(query, kind: kind, in: tab) } label: {
                    Label(kind.rawValue, systemImage: kind == .images ? "photo.on.rectangle" : "play.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Nightglass.text)
                .help("Show \(kind.rawValue.lowercased()) for “\(query)” in Vela's grid")
            }
        }
        .padding(3)
        .glassPanel(cornerRadius: 18)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}
