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

To update later: Vela updates itself (see below). You can still pull the new code and run the same command.

## Updates: how new features reach Vela

```
feature branch ─▶ pull request ─▶ merge to main ─▶ beta build ─▶ Vela (beta on)
   (Claude)      (Build check)                   Run "Release" ─▶ stable build ─▶ Vela (everyone)
```

1. **Every change starts on its own branch** with a pull request. GitHub's **Build** check compiles Vela on a Mac for every pull request, so build errors show up there. The built app is attached to the run for 7 days if you want to try it early.
2. **Merging to `main` makes a beta.** The **Release** pipeline builds Vela, signs the update, puts it on the [Releases page](../../releases) as a pre-release, and adds it to the update feed (the `appcast` branch).
3. **A stable release is one click.** Go to **Actions ▸ Release ▸ Run workflow**, keep channel **stable**, type a version like `1.1`, and run it. Release notes are made from the change list since the last stable version.
4. **Vela checks once a day** (or Vela ▸ **Check for Updates…**). By default it downloads updates by itself and installs them when you quit Vela, so security fixes reach you without a click. Turn that off in Settings ▸ General if you'd rather choose. Turn on **Get beta updates** there to get betas too.
5. **Urgent security fixes:** when running **Release**, tick **Urgent security fix**. Vela then asks everyone to install it right away, even people who skipped an earlier version.
6. **macOS updates matter too.** Vela draws web pages with WebKit, the same engine as Safari, and Apple fixes WebKit through macOS updates. When one is waiting, Vela tells you at launch, and Settings ▸ General has an **Open Software Update** button.

### One-time setup

1. **Make the repo public.** GitHub ▸ the repo ▸ Settings ▸ General ▸ Danger Zone ▸ Change visibility. Vela downloads updates without a password, so the feed and releases must be public. Public repos also get free Mac build minutes.
2. **Make the update signing key.** In Terminal, in the VelaBrowser folder, run `bash scripts/setup-updates.sh`. It saves the private key as the GitHub secret `SPARKLE_PRIVATE_KEY` and prints the public key. That goes into `Vela-Info.plist` (`SUPublicEDKey`); until it does, Vela doesn't look for updates.
3. **Recommended: save your signing certificate** so macOS keeps Full Disk Access and Keychain permission across updates. Run `bash scripts/setup-certificate.sh`. It finds your Apple Development certificate (or tells you how to make one in Xcode, for free), exports it with a random password, and saves both as the secrets `MAC_CERT_P12` and `MAC_CERT_PASSWORD`.
4. **Install the first updatable Vela** once by hand: download the newest `.dmg` from the Releases page, drag Vela to Applications, then right-click ▸ **Open** (it isn't notarized by Apple, so macOS asks once). From then on it updates itself.

### Repository security settings

The repo is public, so its settings protect the releases. Run `bash scripts/secure-repo.sh` once (it needs the GitHub tool: `brew install gh && gh auth login`). It turns on:

| Setting | What it protects |
|---|---|
| Secret scanning and push protection | Stops a key or password from being committed by accident. |
| Dependabot alerts and security fixes | Warns about, and proposes fixes for, vulnerable build tools. |
| Private vulnerability reporting | Lets people report a security problem privately instead of in public. |
| Immutable releases | A published release's files can't be swapped out afterwards. |
| Read-only workflows by default, only GitHub-made and verified actions | A workflow can't change the repo unless it says so, and unknown third-party actions can't run. |
| Approval for strangers' pull requests | Code from someone else's fork doesn't run on GitHub's Macs until you approve it. |
| Rulesets | `main` changes only through pull requests that pass the Build check. The `appcast` update feed and `v…` release tags can't be force-pushed, moved or deleted. |

If a step fails, make the same change by hand in the repo's **Settings**: Code security (the first four), Actions ▸ General (workflows and approvals), and Rules ▸ Rulesets (protection).

**How the update is kept safe.** Each update is signed with the private key, which only GitHub's secret store has. Vela checks the signature against the public key built into it, so a tampered download is rejected.

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
| Site info | Click the 🔒 at the left of the address bar to see whether the connection is secure, who issued the site's certificate and when it expires (**Show Certificate…** opens Apple's full viewer), what the site is allowed to do, and a button to clear its cookies and data. |
| Containers | Separate cookie jars for tabs, like Firefox: **Personal**, **Work**, **Shopping** and **Banking** (rename, recolor or add more in Settings ▸ General). Sites in one container can't see your logins or cookies from another, and you can be signed in to two accounts on the same site at once. Right-click the **+** button or use Tabs ▸ New Tab in Container; right-click a tab ▸ Reopen in Container to move it. A colored line on the tab and a badge in the address bar show which container you're in. |
| Vertical tabs | Tabs ▸ Vertical Tabs (⌃⌘V) moves the tabs into a list down the left side, with pinned tabs as icons at the top and groups still shown. |
| Split view | ⌥-click a tab (or right-click ▸ Open in Split View) to show it next to the current one. Tabs ▸ Split View with New Tab (⌥⌘D) opens a blank one. Click either page to type in it; the active one has a colored line on top. Picking any other tab, or the ✕, closes split view. |
| Command bar | ⌘K opens one box for everything: switch to an open tab, open a bookmark, a page from your history or an archived tab, run any menu command, search the web, or ask Claude. ↑/↓ to pick, Return to open, Esc to close. |
| Link preview | Hold ⌥ (Option) over a link to peek at the page without leaving yours. **Summarize** asks Claude for the main points; **Open in New Tab** opens it. Esc or a click outside closes it. Dangerous links aren't previewed, and pages with password boxes aren't sent to Claude. |
| Tab tidy-up | Tabs you haven't opened for 7 days (Settings ▸ General ▸ Tabs) close and wait in Tabs ▸ Archived Tabs and the command bar. Pinned and private tabs, split view, and tabs playing sound never are. Right-click a tab ▸ Archive Tab to do it by hand. |
| Video controls | A speaker on the tab shows it's playing sound; click it to mute (⌃⌘M). View ▸ Video: Faster ⌃⌘., Slower ⌃⌘,, Normal ⌃⌘0, skip ±10 seconds ⌃⌘→ / ⌃⌘←. Works on any site, including embedded players. |
| Dark mode for every site | Bright websites turn dark to match Vela; photos and videos keep their colors. Sites with their own dark look use it. View ▸ Dark Mode for This Site turns it off for one site; Settings ▸ Appearance ▸ Websites turns it off everywhere. |
| Web panels | The panel button in the toolbar (⌃⌘P) opens Calendar and Gmail in a slim panel on the right, signed in like your tabs. Click + to add any site; right-click a panel to remove it. Links to other sites open in normal tabs. |
| Focus mode | View ▸ Focus (or the command bar) blocks distracting sites (YouTube to start) for 25 minutes, an hour, or until you stop. Blocked pages show a calm “Stay focused” screen with a 5-minute break button. Settings ▸ Focus edits the list and sets automatic focus hours. |
| Weekly report | History ▸ Weekly Report (⌥⌘R): time online per day, the sites you spent it on, your top searches, pages visited and what the shield blocked, with an optional short summary from Claude. Counted only on your Mac; private tabs never count. Settings ▸ Privacy ▸ Activity report turns it off or clears it. |
| Find a page I've seen | History ▸ Find a Page I've Seen (⌥⌘Y), or type in the command bar: describe a page in your own words and Vela finds it. The words on pages you visit are remembered only on your Mac (never private tabs, the Banking container or pages with password boxes); Claude sees only your question and short excerpts of the best few matches. |
| Ask Claude about selected text | Select text on a page and right-click ▸ Ask Claude: Explain, Summarize, Define, Translate to English, or Ask Claude About This… (puts the text in the Claude panel for you to finish). |
| Writing help | Right-click in any text box ▸ Rewrite with Claude: fix spelling and grammar, make it shorter, friendlier or more professional. Works on what you selected, or the whole box. ⌘Z undoes it. Pages with a password box are never sent to Claude. |
| Talk to Claude | ⌥⌘A, or the mic in the Claude panel: say your question and pause, and it's sent. Speech is turned into text on your Mac only; Claude gets just the text. |
| Compare tabs | Claude ▸ Compare Tabs…: pick 2 to 6 tabs (products, recipes, plans) and Claude makes a side-by-side table with a short summary. Private tabs and pages with password boxes are left out. |
| YouTube summaries | On a YouTube video, Claude ▸ Summarize This Video: a short summary from the captions, with key moments you click to jump to. |
| Is this site legit? | Claude ▸ Is This Site Legit?: Vela checks the address, the secure connection and Google Safe Browsing on your Mac, then Claude weighs those and the page and gives a verdict with reasons. On pages with a password box Claude sees only the address. |
| Smart bookmarks | Organize with Claude (top of the Bookmarks sidebar, or the Claude menu) sorts your bookmarks into folders and adds tags that search finds. After that, new bookmarks are filed as you save them. Claude sees only titles and addresses. Right-click a bookmark to move it. |
| Scrolling tab bar | Tabs shrink to a readable width, then the row scrolls sideways (swipe, or use a mouse wheel). The tab you switch to scrolls into view, the edges fade when more tabs are hidden, and ⌄ lists every tab. Pinned tabs always stay in view. |
| Tab previews | Rest the pointer on a tab to see a picture of its page. Pictures stay in memory only. Turn off in Settings ▸ Appearance. |
| Translate | On a page in another language, a 文A button appears in the address bar. Click it (or ⌥⌘T) to translate the page into your language with Apple's on-device translation: nothing you read is sent anywhere. Click again to show the original. The first time, macOS may ask to download the language. |
| Reading List | ⇧⌘D (or ••• ▸ Add to Reading List) saves the page to read later. Find it in the sidebar under **Read Later**, with unread pages marked by a dot. |
| Screenshots | ⇧⌘S saves a screenshot of the **whole page**, including everything you'd scroll to, to Downloads. ••• ▸ Screenshot also offers the full page as a PDF, or just the visible area (copied to the clipboard too). |
| Suggestions as you type | The address bar lists matching open tabs (**Switch to Tab**), bookmarks (Vela's and Safari's), history and DuckDuckGo search ideas. When a site's name starts with what you typed ("git" → github.com), it becomes the **Top Hit** and Return opens it. ↑/↓ pick a row, Esc closes the list. DuckDuckGo ideas are never fetched in private tabs, and you can turn them off in the shield panel (**DuckDuckGo suggestions as I type**). |
| Back, forward and reload | ⌘[, ⌘] and ⌘R, or swipe with two fingers on a trackpad |
| Find on page | ⌘F. Return goes to the next match, ⇧Return to the previous one, and Esc closes the bar. |
| Zoom | ⌘= zooms in, ⌘- zooms out and ⌘0 resets. The zoom level shows in the address bar, and you can click it to reset. |
| Share | The share button in the toolbar sends a page to Messages, Mail, AirDrop, Notes and so on. |

### Tabs and video
| Feature | How to use it |
|---|---|
| **Session restore** | Vela reopens the tabs (and tab groups) you had when you quit. They load when you click them, so even 50 tabs open instantly. Private tabs are never saved. Turn it off in Settings ▸ General ▸ Tabs. |
| **Tab sleeping** | Tabs you haven't looked at for 30 minutes (change it in Settings ▸ General ▸ Tabs) unload to save memory and battery, and fade a little in the tab strip. Click one and it loads again. Pinned tabs, and tabs playing sound or using the camera, stay awake. Tabs ▸ **Put Other Tabs to Sleep** does it now. |
| **Picture in picture** | **⌥⌘V** (or ••• ▸ Picture in Picture) pops the page's video into a small floating window that stays on top while you use other tabs and apps. Press it again to put it back. |

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
| Allow sign-in | School and work logins (Auth0, Okta, Microsoft, Google and others) keep their cookies automatically. If a site still sends you back to its login page, click the shield and turn on **Allow sign-in** for that site. Ads and trackers stay blocked. |
| HTTPS upgrade | Insecure `http://` requests are switched to secure `https://`. |
| **Warn before insecure sites** | If a site has no secure version, Vela stops with a warning page. **Go Back**, or **Continue to Site (Not Secure)** to remember that site. Manage the list in Settings ▸ Privacy. Your own network (router pages, `localhost`) is never warned about. |
| **Fingerprinting protection** | On by default. Sites can recognize your Mac without cookies by drawing on a hidden canvas, measuring sound, or asking about your hardware. Vela adds invisible noise to those answers, different on every site and every launch (like Brave). Turn it off in the shield panel or for one site by turning that site's shield off. |
| **Clean links** | On by default. Tracking tags like `utm_source`, `fbclid` and `gclid` are removed from addresses before the page loads, so the site and ad companies can't tell which email or post you came from. |
| **Global Privacy Control** | On by default. Tells every site "don't sell or share my data" (the `Sec-GPC` signal). Many US states require sites to honor it. |
| **Cookie pop-ups** | On by default. Vela clicks **Reject all** on cookie banners for you (OneTrust, Cookiebot, Didomi, Quantcast and others), and hides banners that have no way to say no. |
| **Lockdown Mode for a site** | In the shield panel or Site Settings. Turns on Apple's strictest web protection for just that site: no fast JavaScript, WebGL or unusual fonts and files, which is what most browser attacks rely on. Good for your bank or a site you don't trust. |
| **Locks on sleep** | Saved passwords lock again as soon as your Mac sleeps, its screen locks or you switch users, so filling or viewing one needs Touch ID again. |
| **Camera and microphone** | When a site asks, a banner over the page says "Use your camera?" with **Allow** / **Don't Allow** and **Remember**. A red camera or mic icon on the tab shows it's in use; click it to turn them off. |
| **Site Settings** | Shield panel ▸ **Site Settings…**, Tabs ▸ Site Settings…, or Settings ▸ **Sites**. Every website you've made a choice for, with its camera, microphone, pop-ups, JavaScript, shield, sign-in, insecure access, kept cookies and password choices in one place. **Reset** forgets them all. |
| **Pop-ups for one site** | With pop-ups blocked, the shield panel has **Allow pop-ups on this site**. |
| **Email masking** | Settings ▸ Privacy ▸ Email masking: type your Duck Address (free at duckduckgo.com/email), paste the passphrase DuckDuckGo emails you, done. On a sign-up form press **⌥⌘E**: Vela makes a new private @duck.com address, fills it in and copies it. Mail is forwarded to your real inbox. (Apple's Hide My Email only works in Safari and Mail.) |
| **Home-network blocking** | Websites can't secretly reach devices on your home network (your router, printer, `localhost`). Pages you open yourself on those addresses still work. |
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
| **Download scanning** | Optional. Add a free VirusTotal API key in Settings ▸ Security and each finished download is checked against about 70 antivirus engines. Only the file's SHA-256 fingerprint is sent, never the file. Flagged files get a red warning and a **Move to Trash** button. Right-click a download to copy its fingerprint. |
| **macOS quarantine** | Every download is tagged "downloaded from the internet", so Gatekeeper and XProtect check apps before they open. |

### Passwords
| Feature | How to use it |
|---|---|
| **Password store** | Passwords are saved in the macOS Keychain, never in a normal file. Open them with ⌥⌘P or the ••• menu. Touch ID (or your Mac password) unlocks them for 10 minutes. |
| **Save on sign-in** | After you sign in, Vela asks "Save password?" (or "Update?"). Choose **Never for This Site** to stop asking. Private tabs never save. |
| **Autofill** | On a page with a login form, a 🔑 key appears in the address bar. Pick an account, confirm with Touch ID, and Vela fills it in. It only ever fills into the exact website the login was saved for. |
| **2FA codes** | Vela can make the 6-digit two-factor codes too. They come in automatically when you import from the Passwords app, or click **123** next to a login in Passwords (⌥⌘P) and paste the site's setup key. When Vela fills that login, it also copies the code and types it in when the site asks for it. Codes show live in Passwords with a countdown ring. |
| **Import from the Passwords app** | In the Passwords app choose **File ▸ Export All Passwords…**. Then in Vela's Passwords window click **Import…** and pick the file. Vela saves every login to the Keychain and then shreds the exported file (overwrites it, then deletes it). Exports from Chrome, Firefox, Brave, Edge and 1Password work too. Apple doesn't let browsers other than Safari read the Passwords app directly, so this is the safe way in. |
| **Password check** | Click **Check** in the Passwords window. Vela lists weak and reused passwords, and (if you leave it on) ones found in data breaches. The breach check uses Have I Been Pwned privately: only the first 5 characters of a scrambled code of each password are sent, never the password. |
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
| **Sign-in pages are off limits** | On any page with a password box, Claude can't read the page or click anything. Log in yourself, then ask again. |

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
5. ✅ Finishing touches: Reader, live Safari bookmarks, default browser, and a packaged app.
6. ✅ Update pipeline: compile checks on pull requests, beta and stable releases, and self-updates with Sparkle.
7. ✅ Security round: Passwords-app import, password check, warnings for insecure sites, home-network blocking, Claude safety on sign-in pages, automatic and urgent updates, and an OWASP Top 10 review (see SECURITY.md).
8. 🔨 Privacy and tabs: fingerprinting protection, Site Settings with camera and microphone permissions, email masking, session restore, tab sleeping, picture in picture, and download scanning. **← you are here**

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
