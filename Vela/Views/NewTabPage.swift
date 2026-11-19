import SwiftUI

/// What you see in a fresh tab: a greeting, a big glass search box and
/// shortcuts to your first six bookmarks. Claude search plugs in here in step 4.
struct NewTabPage: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab
    @State private var query = ""
    @State private var isGlowing = false

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text(tab.isPrivate ? "Private Browsing" : greeting)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                if tab.isPrivate {
                    Text("Vela won't remember the pages you visit, your searches or your cookies after you quit Vela.")
                        .font(.system(size: 13))
                        .foregroundStyle(Nightglass.mutedText)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "sparkle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Nightglass.accent)
                    .accessibilityHidden(true)
                TextField("Search the web or enter an address", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .onSubmit { store.navigate(query, in: tab) }
                Button { store.navigate(query, in: tab) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0B0B12))
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Nightglass.accent))
                }
                .buttonStyle(.plain)
                .disabled(query.isEmpty)
                .help("Search")
            }
            .padding(14)
            .frame(maxWidth: 680)
            .glassPanel(cornerRadius: 20)
            // A slow "breathing" glow around the search box.
            .shadow(color: Nightglass.accent.opacity(isGlowing ? 0.28 : 0.06), radius: isGlowing ? 26 : 10)
            .onAppear {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    isGlowing = true
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 6),
                spacing: 14
            ) {
                ForEach(store.bookmarks.prefix(6)) { bookmark in
                    SpeedDialTile(bookmark: bookmark) { tab.load(bookmark.url) }
                }
            }
            .frame(maxWidth: 680)

            if store.trackersBlockedTotal + store.popupsBlockedTotal > 0 {
                Label {
                    Text("\(store.trackersBlockedTotal) trackers and ads blocked · \(store.popupsBlockedTotal) pop-ups stopped")
                } icon: {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(Nightglass.accent)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Nightglass.mutedText)
                .contentTransition(.numericText())
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}

/// A shortcut tile that lifts up when you hover over it.
struct SpeedDialTile: View {
    let bookmark: Bookmark
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        Button(action: action) {
            VStack(spacing: 8) {
                FaviconView(url: bookmark.url, size: 28)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                Text(bookmark.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Nightglass.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(shape.fill(Color.white.opacity(isHovering ? 0.09 : 0.05)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.08)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.04 : 1)
        .offset(y: isHovering ? -3 : 0)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
    }
}
