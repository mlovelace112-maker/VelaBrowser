# Vela

A personal web browser for Mac with a dark, glass-like look called **Nightglass**. It's built with SwiftUI and Apple's WebKit engine, the same engine Safari uses.

## Run it

1. Open **Vela.xcodeproj** in Xcode by double-clicking it.
2. At the top of the Xcode window, make sure the run destination says **My Mac**.
3. Press **⌘R**, or click the ▶ Play button.

The first build takes a minute. If Xcode asks about signing, choose **Sign to Run Locally**.

## What works today

### Tabs
| Feature | How to use it |
|---|---|
| New tab and close tab | Press ⌘T to open a tab. Close one with the × that appears on hover, or with ⇧⌘W. |
| Private tab | ⇧⌘N, or the ••• menu. Private tabs keep no history, and their cookies disappear when you quit Vela. |
| Reopen a closed tab | ⇧⌘T |
| Switch tabs | ⇧⌘] for the next tab, ⇧⌘[ for the previous one |
| **Right-click a tab** | Pin, duplicate, reload, **Group All [site] Tabs**, Group Similar Tabs, add to or move between groups, bookmark, copy the link, share, close other tabs, or close tabs to the right |
| Pinned tabs | Pinned tabs shrink to just an icon and stay at the left of the tab strip. |
| Tab groups | The stack icon or ⇧⌘G groups similar tabs. Click a group's pill to collapse it. Right-click the pill to rename, recolor, ungroup or close the group. |

### Browsing
| Feature | How to use it |
|---|---|
| Address bar | Type an address or a search (searches go to DuckDuckGo). ⌘L jumps to the address bar. |
| Back, forward and reload | ⌘[, ⌘] and ⌘R, or swipe with two fingers on a trackpad |
| Find on page | ⌘F. Return goes to the next match, ⇧Return to the previous one, and Esc closes the bar. |
| Zoom | ⌘= zooms in, ⌘- zooms out and ⌘0 resets. The zoom level shows in the address bar, and you can click it to reset. |
| Share | The share button in the toolbar sends a page to Messages, Mail, AirDrop, Notes and so on. |

### Bookmarks and History
| Feature | How to use it |
|---|---|
| Add a bookmark | Click ☆ or press ⌘D. Use "Bookmark All Tabs" in the ••• menu to save every open tab. |
| **Bookmarks button** | Click 📖, or press ⌥⌘B, to open the sidebar with all your bookmarks. You can search them, and right-click one to open it in a new tab or delete it. |
| History | ⌘Y opens the sidebar on History, grouped by day and searchable. Right-click an entry to remove it, or use "Clear History…". |
| Sidebar | ⇧⌘L, or the sidebar button at the far left of the toolbar |

The app also has a custom icon: a "V" drawn as the Vela constellation. Its source is `docs/icon-source.svg`.

## Roadmap

1. ✅ Mockups. See the design canvas.
2. ✅ Core browser: tabs, tab groups, address bar, bookmarks, plus Safari-style extras: a sidebar, history, find, zoom, private tabs, pinned tabs and a custom icon. **← you are here**
3. ⏳ Privacy: pop-up blocker, ad and tracker blocking, cookie manager.
4. ⏳ Extras: Claude in the address bar and side panel, image and video search, the Spotify player.

## How the code is organized

```
Vela/
  App/VelaApp.swift          The starting point. Creates the window and the menu shortcuts.
  Assets.xcassets            The app icon and accent color.
  Models/                    The "brain": data and logic, no drawing.
    BrowserStore.swift       All tabs, groups, bookmarks and history, plus the actions on them.
    HistoryEntry.swift       A visited page, a closed tab, and the sidebar sections.
    BrowserTab.swift         One tab and its WebKit web view.
    TabGroup.swift           Groups and their colors.
    Bookmark.swift           A saved page.
  Views/                     What you see on screen.
    ContentView.swift        The whole window, top to bottom.
    TabStripView.swift       Tabs and group pills.
    ToolbarView.swift        Back, forward, reload, address bar, star, bookmarks, share and ••• menu.
    SidebarView.swift        Bookmarks and History, with search.
    FindBar.swift            Find on page (⌘F).
    BookmarksBarView.swift   The bookmarks row.
    NewTabPage.swift         The greeting, the search box and the shortcut tiles.
    WebViewContainer.swift   Puts a WebKit page inside SwiftUI.
  Theme/Nightglass.swift     Colors, glass effects and the hover-button style.
```

## Five ideas worth learning from this code

1. **Views describe; they don't command.** A SwiftUI view says what the screen *should* look like for the current data, for example `Text(tab.title)`. When `title` changes, SwiftUI redraws that text by itself. You never write "update the label".
2. **`@Observable` is the glue.** `BrowserStore` and `BrowserTab` are marked `@Observable`, so any view that reads one of their properties is redrawn automatically when that property changes.
3. **Each view has one job, and the logic lives in the store.** Views call store methods like `store.close(tab)` or `store.groupSimilarTabs()` instead of changing data themselves. Later, Claude's "control the browser" feature will call those same methods.
4. **Bridging to AppKit.** WebKit's `WKWebView` and the macOS blur view are older AppKit views. `NSViewRepresentable` (see `WebViewContainer` and `VisualEffectBackground`) is how SwiftUI borrows them.
5. **Watching WebKit with KVO.** `BrowserTab.watch(...)` asks WebKit to report whenever the page's title, address or loading progress changes, and copies the new values into the tab. That's what makes the loading bar and tab titles update live.

## Good first experiments

- Change `Nightglass.accent` in `Theme/Nightglass.swift` to another color, such as `Color(hex: 0x4FD1A5)`, and run again.
- Change the search engine in `BrowserStore.url(from:)`.
- Edit the starter bookmarks in `BrowserStore.loadBookmarks()`. Starter bookmarks only appear the first time, so delete your saved ones from the bookmarks bar to see the change.
