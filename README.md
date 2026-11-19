# Vela

A personal web browser for Mac with a dark, glass-like look called **Nightglass**. It's built with SwiftUI and Apple's WebKit engine, the same engine Safari uses.

## Run it

1. Open **Vela.xcodeproj** in Xcode by double-clicking it.
2. At the top of the Xcode window, make sure the run destination says **My Mac**.
3. Press **⌘R**, or click the ▶ Play button.

The first build takes a minute. If Xcode asks about signing, choose **Sign to Run Locally**.

## What works today

| Feature | How to use it |
|---|---|
| Tabs | ⌘T opens a new tab. Hover over a tab and click × to close it, or press ⇧⌘W. |
| Combining similar tabs | Click the stack icon at the right of the tab strip, or press ⇧⌘G. Tabs from the same website are grouped together. |
| Tab groups | Click a group's pill to collapse or expand it. Right-click it to rename it, change its color, ungroup it or close it. Right-click a tab to add it to a group or move it to another one. |
| Address bar | Type a web address or a search. Searches go to DuckDuckGo. ⌘L jumps to the address bar. |
| Navigation | Back and forward (⌘[ and ⌘]), reload (⌘R), and two-finger swipe on a trackpad. |
| Bookmarks | Click the ☆ star or press ⌘D. Bookmarks appear in the bar and on the New Tab page. Right-click one to delete it. |
| Links that open new windows | They open as a new tab next to the current one, in the same group. |

## Roadmap

1. ✅ Mockups. See the design canvas.
2. ✅ Core browser: tabs, tab groups, address bar, bookmarks. **← you are here**
3. ⏳ Privacy: pop-up blocker, ad and tracker blocking, cookie manager.
4. ⏳ Extras: Claude in the address bar and side panel, image and video search, the Spotify player.

## How the code is organized

```
Vela/
  App/VelaApp.swift          The starting point. Creates the window and the menu shortcuts.
  Models/                    The "brain": data and logic, no drawing.
    BrowserStore.swift       All tabs, groups and bookmarks, plus the actions on them.
    BrowserTab.swift         One tab and its WebKit web view.
    TabGroup.swift           Groups and their colors.
    Bookmark.swift           A saved page.
  Views/                     What you see on screen.
    ContentView.swift        The whole window, top to bottom.
    TabStripView.swift       Tabs and group pills.
    ToolbarView.swift        Back, forward, reload, address bar and star.
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
