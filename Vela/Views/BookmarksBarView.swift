import SwiftUI

/// Your saved sites, in a row under the address bar.
/// Right-click a bookmark to open it in a new tab or delete it.
struct BookmarksBarView: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        HStack(spacing: 2) {
            ForEach(store.bookmarks) { bookmark in
                Button { store.open(bookmark) } label: {
                    HStack(spacing: 6) {
                        FaviconView(url: bookmark.url, size: 12)
                        Text(bookmark.title).lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Nightglass.secondaryText)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: 160)
                    .frame(height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(bookmark.url.absoluteString)
                .contextMenu {
                    Button("Open in New Tab") { store.newTab(url: bookmark.url) }
                    Button("Delete Bookmark", role: .destructive) { store.removeBookmark(bookmark) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
    }
}
