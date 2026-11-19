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

### Privacy and security (the shield)
| Feature | How to use it |
|---|---|
| Ad and tracker blocking | This is on by default. The shield button to the right of the address bar shows how many trackers were blocked on the page. Choose **Standard** (block trackers that other sites load, like Brave), **Aggressive** (also block them on their own sites and hide leftover ad boxes) or **Off**. |
| Turn the shield off for one site | Click the shield and flip its switch, for when a site doesn't work right. You can turn it back on later in Settings (⌘,). |
| Pop-up blocker | Pop-ups you didn't click for are blocked. A "Pop-up blocked · Allow once" notice appears at the bottom of the window. |
| Third-party cookies | Blocked by default, so ad companies can't follow you from site to site. |
| HTTPS upgrade | Insecure `http://` requests are switched to secure `https://`. |
| Cookie manager | Open it from the shield panel or press ⌥⌘K. It shows every site's cookies, with trackers listed first. Delete one site, all trackers or everything. Mark a site **Keep** to stay signed in. |
| Clear cookies on quit | Turn this on in the cookie manager or Settings. When Vela quits, it deletes every site's data except the sites marked Keep. |
| Settings | Vela ▸ Settings… (⌘,) has every privacy switch, blocked totals, and the sites where the shield is off. |
| **Pop-under protection** | Stops ad tabs that open when you click *anywhere* on a page. A click on a real link or button still works. Invisible full-page "click traps" are removed. |
| **Interstitial ads** | Full-screen ads that cover a page are hidden or removed, and the page can scroll again. |
| **Embedded ads** | Video-ad players and ad boxes inside articles are blocked and hidden. |
| **Aggressive mode** | Now also blocks ad-shaped requests (like `/pagead/` or `prebid.js`) from any company, plus ~60 more pop-up and native-ad networks. |

### Scripts, links and downloads
| Feature | How to use it |
|---|---|
| **JavaScript slider** | Three positions: **Allow all**, **Block 3rd-party** (only the site's own scripts run) and **Block all**. Set the default in Settings ▸ Security, or one site from the shield panel. The page reloads with the new setting. |
| **Link checker** | Point at a link and a bubble at the bottom-left shows where it really goes, with a green, yellow or red shield and the reason. |
| **Dangerous link warning** | Links that look like phishing (a fake "@" address, a brand name on the wrong site with "login" or "verify" in it…) are stopped with a warning page. **Go Back** or **Open Anyway**. |
| **Downloads** | A downloads button appears in the toolbar with a progress ring. Click it to see your files, cancel, or show them in Finder. |
| **Malicious download blocking** | Windows programs (.exe, .scr, .bat…), disguised files ("invoice.pdf.exe"), names with hidden flip characters, and anything from an ad network are blocked. Apps, installers, scripts and macro documents ask first. Hidden frames can't start downloads. |
| **macOS quarantine** | Every download is tagged "downloaded from the internet", so Gatekeeper and XProtect check apps before they open. |

### Passwords
| Feature | How to use it |
|---|---|
| **Password store** | Passwords are saved in the macOS Keychain, never in a normal file. Open them with ⌥⌘P or the ••• menu. Touch ID (or your Mac password) unlocks them for 10 minutes. |
| **Save on sign-in** | After you sign in, Vela asks "Save password?" (or "Update?"). Choose **Never for This Site** to stop asking. Private tabs never save. |
| **Autofill** | On a page with a login form, a 🔑 key appears in the address bar. Pick an account, confirm with Touch ID, and Vela fills it in. It only ever fills into the exact website the login was saved for. |
| **Generator** | The Passwords window makes strong random passwords. Copied passwords are hidden from clipboard-history apps and cleared after 90 seconds. |
| **Passkeys** | Not yet. macOS only lets browsers that Apple has approved use passkeys (an entitlement Apple grants to browser makers). |

### Look and feel
| Feature | How to use it |
|---|---|
| **Themes** | Settings ▸ Appearance: Nightglass, Aurora, Ember, Ocean, Rose and Graphite. Pick any accent color and how strong the background glow is. |
| **Customize the window** | Show or hide the bookmarks bar, compact tabs, the bookmarks and share buttons, animations, and each part of the New Tab page. |

The app also has a custom icon: a "V" drawn as the Vela constellation. Its source is `docs/icon-source.svg`.

## Roadmap

1. ✅ Mockups. See the design canvas.
2. ✅ Core browser: tabs, tab groups, address bar, bookmarks, plus Safari-style extras: a sidebar, history, find, zoom, private tabs, pinned tabs and a custom icon. 
3. ✅ Privacy: pop-up blocker, ad and tracker blocking, cookie manager.
3½. ✅ Security and looks: passwords, link checker, safe downloads, script slider, pop-under and stronger ad blocking, themes. **← you are here**
4. ⏳ Extras: Claude in the address bar and side panel, image and video search, the Spotify player.

## How the code is organized

```
Vela/
  App/VelaApp.swift          The starting point. Creates the window, Settings and the menu shortcuts.
  App/AppDelegate.swift      Launch and quit handling (Dock icon, clearing cookies on quit).
  Privacy/                   The shield.
    ContentBlocker.swift     Blocking rules, ad lists, and the pop-up and ad-cleaner page scripts.
    CookieManager.swift      Lists and deletes cookies and site data.
    PrivacySettings.swift    Your privacy and security choices, saved between launches.
    LinkChecker.swift        Spots phishing tricks in web addresses; the link-hover script.
    DownloadManager.swift    Downloads, the download guard, and macOS quarantine.
  Passwords/
    PasswordVault.swift      The Keychain password store, Touch ID, the generator, fill scripts.
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
    ShieldViews.swift        Shield button and panel, privacy switches, script slider, "Pop-up blocked" notice.
    SecurityViews.swift      Link bubble, dangerous-link warning, downloads, "Save password?", Security settings.
    PasswordsView.swift      The Passwords window (⌥⌘P).
    SettingsView.swift       The Settings window and its Appearance tab.
    CookieManagerView.swift  The cookie manager and the Privacy settings tab.
    BookmarksBarView.swift   The bookmarks row.
    NewTabPage.swift         The greeting, the search box and the shortcut tiles.
    WebViewContainer.swift   Puts a WebKit page inside SwiftUI.
  Theme/Nightglass.swift     Colors, glass effects and the hover-button style.
  Theme/Appearance.swift     The themes and your look-and-feel choices.
```

## Five ideas worth learning from this code

1. **Views describe; they don't command.** A SwiftUI view says what the screen *should* look like for the current data, for example `Text(tab.title)`. When `title` changes, SwiftUI redraws that text by itself. You never write "update the label".
2. **`@Observable` is the glue.** `BrowserStore` and `BrowserTab` are marked `@Observable`, so any view that reads one of their properties is redrawn automatically when that property changes.
3. **Each view has one job, and the logic lives in the store.** Views call store methods like `store.close(tab)` or `store.groupSimilarTabs()` instead of changing data themselves. Later, Claude's "control the browser" feature will call those same methods.
4. **Bridging to AppKit.** WebKit's `WKWebView` and the macOS blur view are older AppKit views. `NSViewRepresentable` (see `WebViewContainer` and `VisualEffectBackground`) is how SwiftUI borrows them.
5. **Watching WebKit with KVO.** `BrowserTab.watch(...)` asks WebKit to report whenever the page's title, address or loading progress changes, and copies the new values into the tab. That's what makes the loading bar and tab titles update live.

## The big idea in step 3: content rule lists

Vela doesn't inspect each web request itself. Instead, `ContentBlocker.makeRules` writes a list of rules in JSON, such as:

```json
{ "trigger": { "url-filter": "^[^:]+://+([^:/]+\\.)?doubleclick\\.net[:/]", "load-type": ["third-party"] },
  "action":  { "type": "block" } }
```

WebKit compiles the list once (`WKContentRuleListStore`) and applies it to every page before anything downloads. That's the same fast engine Safari's ad blockers use. Changing a setting rebuilds the list and swaps it into every open tab.

## The big ideas in step 3½

**Two script worlds.** Vela's page scripts run in two places. The pop-up guard has to run *in the page's own world*, because it replaces the page's `window.open`. The link checker and password scripts run in Vela's **private world** (`WKContentWorld.defaultClient`): they see the same page, but the page's code can't see them, read them or send fake messages to them. Vela also asks WebKit (not the page) which website a message came from, so a page can't pretend to be your bank.

**Async delegate methods.** WebKit asks "should this page load?" through `decidePolicyFor`. Vela uses the `async` versions, so code like "ask the user whether to keep this download, *then* answer WebKit" reads top to bottom instead of being split across callbacks. See `DownloadManager.destination(for:…)`.

**What the link and download checks can't do.** They run entirely on your Mac and look at the *shape* of addresses and file names. They can't recognize a brand-new scam site with an ordinary name. That needs an online threat list such as Google Safe Browsing (free, needs an API key), which could be added later.

**Keychain prompts after rebuilding.** Vela is signed "to run locally", so each rebuild looks like a slightly different app to the Keychain, and macOS may ask for your Mac password to let Vela read its saved passwords. Click **Always Allow**. Signing with your free Apple ID team in Xcode (Signing & Capabilities ▸ Team) makes this go away.

## Good first experiments

- Change `Nightglass.accent` in `Theme/Nightglass.swift` to another color, such as `Color(hex: 0x4FD1A5)`, and run again.
- Change the search engine in `BrowserStore.url(from:)`.
- Add a domain to `ContentBlocker.trackerDomains` to block it everywhere.
- Add your own theme to `Theme.all` in `Theme/Appearance.swift`.
- Add a brand to `LinkChecker.brands` so look-alike sites get flagged.
- Edit the starter bookmarks in `BrowserStore.loadBookmarks()`. Starter bookmarks only appear the first time, so delete your saved ones from the bookmarks bar to see the change.
