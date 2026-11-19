# Vela

A personal web browser for Mac with a dark, glass-like look called **Nightglass**. It's built with SwiftUI and Apple's WebKit engine, the same engine Safari uses.

## Run it

1. Open **Vela.xcodeproj** in Xcode by double-clicking it.
2. At the top of the Xcode window, make sure the run destination says **My Mac**.
3. Press **⌘R**, or click the ▶ Play button.

The first build takes a minute. If Xcode asks about signing, choose **Sign to Run Locally**.

## Install it for everyday use

Running from Xcode is for development. To use Vela every day, build a finished copy:

1. Open **Terminal**, go to this folder (type `cd `, a space, then drag the VelaBrowser folder in and press Return).
2. Run:
   ```
   TEAM=YOURTEAMID ./scripts/package.sh --install
   ```
   Your team ID is in Xcode ▸ Settings ▸ Accounts (select your Apple ID; it's the 10-character code next to "Personal Team"). Leave out `TEAM=…` to sign "to run locally" instead.
3. Vela is copied to **Applications** and opens. A disk image (`build/Vela-1.0.dmg`) is made too, if you want a copy to keep.
4. Make it your browser: Vela ▸ **Make Vela the Default Browser**, then confirm in the macOS dialog.
5. For Safari bookmarks: System Settings ▸ Privacy & Security ▸ **Full Disk Access** ▸ turn on Vela (use **+** to add it from Applications).

**Why the team ID matters.** macOS remembers permissions (Full Disk Access, Keychain) by the app's signature. Signed with your Apple ID team, each new build keeps the same signature, so you grant them once. Signed "locally", every rebuild looks like a new app and macOS asks again.

To update later: pull the new code and run the same command.

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
| **Google Safe Browsing** | Optional. Add a free API key in Settings ▸ Security and Vela checks each new page and download against Google's list of malware and phishing sites (the one Safari and Chrome use). Only the site and path are sent, never the part after "?". |
| **macOS quarantine** | Every download is tagged "downloaded from the internet", so Gatekeeper and XProtect check apps before they open. |

### Passwords
| Feature | How to use it |
|---|---|
| **Password store** | Passwords are saved in the macOS Keychain, never in a normal file. Open them with ⌥⌘P or the ••• menu. Touch ID (or your Mac password) unlocks them for 10 minutes. |
| **Save on sign-in** | After you sign in, Vela asks "Save password?" (or "Update?"). Choose **Never for This Site** to stop asking. Private tabs never save. |
| **Autofill** | On a page with a login form, a 🔑 key appears in the address bar. Pick an account, confirm with Touch ID, and Vela fills it in. It only ever fills into the exact website the login was saved for. |
| **Generator** | The Passwords window makes strong random passwords. Copied passwords are hidden from clipboard-history apps and cleared after 90 seconds. |
| **Passkeys** | Not yet. macOS only lets browsers that Apple has approved use passkeys (an entitlement Apple grants to browser makers). |

### Claude
| Feature | How to use it |
|---|---|
| **Set up** | Get an API key at [console.anthropic.com](https://console.anthropic.com/settings/keys) and paste it in Settings ▸ Claude (or in the Claude panel). It's kept in your Keychain. Usage is billed to that Anthropic account. |
| **Ask from the address bar** | Type a question and press **Tab** (or click **Ask Claude ⇥**) instead of Return. Haiku 5.5 answers in a card over the page. **Continue in Side Panel** carries the conversation over. Works on the New Tab page too. |
| **Side panel** | ⇧⌘A or the ✦ button. Chat with Haiku 5.5, Sonnet 5.5 or Opus 5.5 (switching models starts a new chat). Links in answers open in new tabs. |
| **Browser control** | In the panel, Claude can list your tabs, read and summarize a page, open addresses and searches, switch tabs, go back, click links and buttons, group tabs (by site or by topic) and close tabs. Each action shows as a chip in the chat. |
| **Asks first** | Closing tabs and clicks that would send a form show an **Allow / Don't Allow** card. **Stop** cancels at any point. |
| **Privacy** | Claude sees a page's text only when it reads that page. Private tabs are never shared. Page text is marked as untrusted, and Claude is told never to follow instructions hidden in it. |

### Image and video search
| Feature | How to use it |
|---|---|
| **Search** | Type something on the New Tab page and click **Images** or **Videos**. On any DuckDuckGo results page, the floating **Images · Videos** pill switches to Vela's grid. The ••• menu has Image Search and Video Search too. |
| **Image grid** | Tiles fade in one after another and lift on hover. Click one for a large preview with **Visit Page**, **Open Image** and **Copy Image Address**. Scroll for more. |
| **Video grid** | 16:9 thumbnails with duration, channel, views and date. Click to open the video. |
| **Privacy** | Results come from DuckDuckGo (powered by Bing), fetched without cookies. SafeSearch is moderate. Back (⌘[) leaves the grid. |

### Reader, Safari bookmarks and default browser
| Feature | How to use it |
|---|---|
| **Reader** | ⇧⌘R or the 📄 button in the address bar. Shows just the article (using Mozilla's Readability, the same code as Firefox's Reader View) on a Night, Sepia or Paper page. Change the text size and font with the floating controls or in Settings ▸ General. Links open in the tab; Esc leaves Reader. |
| **Safari bookmarks, live** | Sidebar ▸ **Safari** shows Safari's Favorites, Bookmarks Menu, folders and Reading List, re-read every time you switch to Vela. **Copy All into Vela Bookmarks** brings them into Vela's own list. Vela only reads Safari's file, never changes it. Needs Full Disk Access. |
| **Default browser** | Vela ▸ Make Vela the Default Browser, or Settings ▸ General. Links from Mail, Messages and other apps then open in a new Vela tab, and `.html` files open from Finder. |
| **Packaged app** | `scripts/package.sh` builds `Vela.app` and a `.dmg`. See "Install it for everyday use" above. |

### Spotify
| Feature | How to use it |
|---|---|
| **Set up** | At [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard), create an app with the redirect URI `vela-spotify://callback` and tick Web API and Web Playback SDK. Paste its Client ID in Settings ▸ Spotify, then **Connect Spotify**. Needs Premium. |
| **Player bar** | Along the bottom: cover art, song and artist, previous / play / next, and a progress line you can click to jump. ⌥⌘S shows or hides it. |
| **Vela as a speaker** | Vela runs Spotify's own web player in a hidden page, so it appears in Spotify as a device called "Vela". No Spotify app needed. |
| **Library** | The ♫ button searches songs, albums and playlists and lists your playlists. Click to play. |
| **Devices** | The speaker button sets the volume and moves playback between Vela, your phone and speakers. |

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
3½. ✅ Security and looks: passwords, link checker, safe downloads, script slider, pop-under and stronger ad blocking, themes.
4. ✅ Extras: Claude in the address bar and side panel, the Spotify player, image and video search, and animation polish.
5. ✅ Finishing touches: Reader, live Safari bookmarks, default browser, and a packaged app. **← you are here**

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
  App/SandboxMigration.swift One-time move of your data out of the old sandbox container.
  App/DefaultBrowser.swift   Checks and sets Vela as the default browser.
  Models/SafariBookmarks.swift Reads Safari's Bookmarks.plist live.
  Reader/
    Reader.swift             Finds the article and builds the styled reader page.
    ReadabilityScript.swift  Mozilla Readability (Apache 2.0), embedded as text.
  Search/
    MediaSearch.swift        Image and video search through DuckDuckGo.
  Spotify/
    SpotifyAuth.swift        Signing in to Spotify (OAuth with PKCE).
    SpotifyPlayer.swift      Now playing, controls, library, devices and the hidden web player.
  Claude/
    ClaudeClient.swift       Talks to the Claude API: streaming replies, models, the Keychain key.
    ClaudeAssistant.swift    The chat, quick answers and the tool loop.
    BrowserTools.swift       The browser actions Claude can take, and how its requests are checked.
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
    ClaudeViews.swift        The Claude panel, the quick-answer card and Settings ▸ Claude.
    ReaderView.swift         The reader page and its floating controls.
    MediaSearchView.swift    The image and video grids, the preview, and the Images · Videos pill.
    SpotifyViews.swift       The Spotify bar, library and devices popovers, and Settings ▸ Spotify.
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

**What the link and download checks can't do.** They run entirely on your Mac and look at the *shape* of addresses and file names. They can't recognize a brand-new scam site with an ordinary name. That's what the optional Google Safe Browsing check is for (`Privacy/SafeBrowsing.swift`).

**Keychain prompts after rebuilding.** Vela is signed "to run locally", so each rebuild looks like a slightly different app to the Keychain, and macOS may ask for your Mac password to let Vela read its saved passwords. Click **Always Allow**. Signing with your free Apple ID team in Xcode (Signing & Capabilities ▸ Team) makes this go away.

## The big ideas in step 4: Claude

**Streaming.** Vela asks for `"stream": true`, so the API sends the reply as a series of small "server-sent events" (`content_block_delta` and friends) instead of one big answer. `ClaudeClient.stream` reads them line by line with `URLSession.bytes(for:)` and rebuilds Claude's reply as it goes, which is why words appear as Claude writes them.

**Tool use is a loop.** Vela sends Claude a list of tools (`BrowserTools.definitions`). When Claude wants one, it stops with `stop_reason: "tool_use"`. Vela runs the tool, sends back a `tool_result`, and asks again, until Claude stops for good (`ClaudeAssistant.runConversation`). Claude's earlier replies go back exactly as they came, including its private "thinking" blocks, which is why switching models starts a new chat.

**Never trust the input.** Claude's tool requests are checked before anything happens: wrong types, unknown tabs and cut-off input are sent back to Claude as errors. Web pages are treated the same way: their text is labeled untrusted, private tabs are off limits, and anything destructive waits for your click.

## The big ideas in step 5

**Leaving the sandbox.** Sandboxed Mac apps can only touch their own files, which keeps them safe but makes Safari's bookmarks unreachable. Vela now runs without the sandbox (see `Vela.entitlements`), still protected by the *hardened runtime*, and macOS still guards Safari's folder until you grant Full Disk Access. Because sandboxed apps store their data in a private container, `SandboxMigration` copies your settings, bookmarks, history and website data out of it once.

**Being a browser.** `Vela-Info.plist` tells macOS that Vela opens `http`/`https` links and HTML files. That's what puts Vela in the default-browser list. Links from other apps arrive in `AppDelegate.application(_:open:)`.

**Reader mode is a scoring game.** Readability looks at every block on the page and gives points for paragraphs, commas and article-like class names, and takes points away for "sidebar", "comment" and "ad". The winning block is the article. Vela runs it in its private script world and shows the result with scripts turned off.

## Good first experiments

- Change `Nightglass.accent` in `Theme/Nightglass.swift` to another color, such as `Color(hex: 0x4FD1A5)`, and run again.
- Change the search engine in `BrowserStore.url(from:)`.
- Add a domain to `ContentBlocker.trackerDomains` to block it everywhere.
- Add your own theme to `Theme.all` in `Theme/Appearance.swift`.
- Add a fourth reader page color to `ReaderPage` in `Reader/Reader.swift`.
- Give Claude a new tool: add it to `BrowserTools.definitions` and handle it in `BrowserTools.run`. A "scroll down" or "find on page" tool is a good start.
- Change the suggestions in the empty Claude panel (`EmptyChat` in `Views/ClaudeViews.swift`).
- Add a brand to `LinkChecker.brands` so look-alike sites get flagged.
- Edit the starter bookmarks in `BrowserStore.loadBookmarks()`. Starter bookmarks only appear the first time, so delete your saved ones from the bookmarks bar to see the change.
