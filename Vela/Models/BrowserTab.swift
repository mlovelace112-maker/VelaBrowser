import AppKit
import Foundation
import Observation
import WebKit

/// One browser tab.
///
/// Each tab owns its own `WKWebView` (Apple's WebKit engine, the same one
/// Safari uses), so switching tabs keeps each page exactly where you left it.
///
/// `@Observable` means SwiftUI watches these properties: when `title` or
/// `isLoading` changes, any view that reads them redraws automatically.
@MainActor
@Observable
final class BrowserTab: Identifiable {
    let id = UUID()
    let webView: WKWebView
    /// Private tabs keep no history, cookies or cache after they close.
    let isPrivate: Bool

    var title = "New Tab"
    var url: URL?
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var progress: Double = 0
    /// Which tab group this tab belongs to, if any.
    var groupID: UUID?
    /// Pinned tabs stay small at the left of the tab strip.
    var isPinned = false
    /// The container (separate cookie jar) this tab lives in, if any.
    var containerID: UUID?
    /// Tracker companies the shield caught on the current page.
    var trackersFound: [String] = []
    /// Pop-ups the shield stopped on the current page.
    var popupsBlocked: [URL] = []
    /// The link under the mouse pointer, shown with its safety check at the bottom of the page.
    var hoveredLink: URL?
    /// Set when the link checker stopped a dangerous page from opening.
    var linkWarning: LinkWarning?
    /// Saved logins for this page's website (they make the key button appear).
    var savedLogins: [PasswordEntry] = []
    /// Set when a site has no secure (https) version: the "Not Secure" warning.
    var httpsWarning: URL?
    /// Set when focus mode stopped this page from opening (the "Stay focused" screen).
    var focusBlocked: URL?
    /// Asks the store whether focus mode blocks an address right now.
    @ObservationIgnored var isFocusBlocked: ((URL) -> Bool)?
    /// Shows the list of saved logins under the key button.
    var isLoginPickerShown = false
    /// Set once Vela has filled (or tried to fill) a login on this page, so
    /// clicking around the form doesn't keep asking for Touch ID.
    var didAutoFill = false
    /// True once a password (not just a username) was filled on this page.
    @ObservationIgnored var didFillPassword = false
    /// Set while the tab shows Vela's image or video search grid instead of a page.
    var mediaSearch: MediaSearch?
    /// Set while Reader mode shows this page's article.
    var reader: ReaderArticle?
    /// The page's language code ("fr") when it isn't yours and can be translated.
    var pageLanguage: String?
    var translation: TranslationStatus = .none
    /// Bumped by the Translate button; the page's TranslationHost watches it.
    var translateRequests = 0

    /// A website asking to use your camera or microphone, waiting for your answer.
    var permissionRequest: PermissionRequest?
    /// True while the page is using your camera or microphone.
    var isUsingCamera = false
    var isUsingMicrophone = false
    /// True while a video or song on the page is playing with sound (the
    /// speaker on the tab). See MediaControls.swift.
    var isPlayingAudio = false
    /// Muted with the speaker button on the tab. Stays muted on new pages.
    var isMuted = false
    /// Video and audio speed for this tab (1 = normal).
    var playbackRate: Double = 1
    /// Frames on the current page that have video or audio, so speed and
    /// mute reach players inside embeds too.
    @ObservationIgnored var mediaFrames: [String: WKFrameInfo] = [:]
    /// A sleeping tab's page was unloaded to free memory. It loads again,
    /// right where the address was, as soon as you open the tab.
    private(set) var isAsleep = false
    /// When you last looked at this tab (tab sleeping uses it).
    @ObservationIgnored var lastActive = Date()

    /// Page zoom: 1.0 is 100%. Change it with zoomIn(), zoomOut() or resetZoom().
    private(set) var zoom: Double = 1

    /// Called when a page asks to open a link in a new window/tab.
    @ObservationIgnored var onOpenInNewTab: (@MainActor (URL) -> Void)?
    /// Called when a page opens a new window (a link with target="_blank" or
    /// a sign-in pop-up). Must return a web view made with this exact configuration.
    @ObservationIgnored var onOpenWindow: (@MainActor (WKWebViewConfiguration, URL?) -> WKWebView?)?
    /// Called when the page closes its own window (window.close()).
    @ObservationIgnored var onCloseRequested: (@MainActor () -> Void)?
    /// Called when a page finishes loading (used to record History).
    @ObservationIgnored var onFinishLoading: (@MainActor () -> Void)?
    /// Called when the shield's page script spots a tracker.
    @ObservationIgnored var onTrackerFound: (@MainActor (String) -> Void)?
    /// Called when the shield stops a pop-up. The flag is true for a pop-under.
    @ObservationIgnored var onPopupBlocked: (@MainActor (URL?, Bool) -> Void)?
    /// Called when a link or page turns into a file download.
    @ObservationIgnored var onDownload: (@MainActor (WKDownload) -> Void)?
    /// Called when the page shows a password box. Passes the website's host.
    @ObservationIgnored var onLoginFormFound: (@MainActor (String) -> Void)?
    /// Called when you click into a login box. Passes the website's host.
    @ObservationIgnored var onLoginFieldFocused: (@MainActor (String) -> Void)?
    /// Called when you submit a login: host, username, password.
    @ObservationIgnored var onLoginSubmitted: (@MainActor (String, String, String) -> Void)?
    /// A page asked for the camera and/or microphone. Call the answer with true to allow.
    @ObservationIgnored var onMediaPermission: (@MainActor (String, [PermissionKind], @escaping @MainActor (Bool) -> Void) -> Void)?
    /// Asks Google Safe Browsing about an address (set by BrowserStore).
    @ObservationIgnored var checkThreat: (@MainActor (URL) async -> SafeBrowsingThreat?)?
    /// Reads your current privacy settings (set by BrowserStore).
    @ObservationIgnored var settings: @MainActor () -> PrivacySettings = { PrivacySettings() }

    /// The frame (page or embedded frame) that holds the login form.
    @ObservationIgnored fileprivate var loginFrame: WKFrameInfo?
    /// The http:// address Vela switched to https://, until that loads or fails.
    @ObservationIgnored fileprivate var upgradedFrom: URL?
    /// The address Vela just reloaded without tracking tags (or with the
    /// privacy signal), so it isn't reloaded twice.
    @ObservationIgnored fileprivate var reissuedURL: URL?
    /// A 2FA code to type in once the site asks for it (after autofill).
    @ObservationIgnored var pendingCode: PendingCode?
    /// Dangerous links you chose to open anyway.
    @ObservationIgnored fileprivate var allowedDangerousURLs: Set<URL> = []

    private let coordinator: TabCoordinator
    private let contentController: WKUserContentController
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration, isPrivate: Bool = false, ruleList: WKContentRuleList?, privacy: PrivacySettings) {
        // Each tab gets its own "user content controller": the place where
        // blocking rules and our small page scripts are attached.
        let tabConfiguration = configuration.copy() as! WKWebViewConfiguration
        let contentController = WKUserContentController()
        if let ruleList { contentController.add(ruleList) }
        tabConfiguration.userContentController = contentController
        self.contentController = contentController

        webView = VelaWebView(frame: .zero, configuration: tabConfiguration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        self.isPrivate = isPrivate
        coordinator = TabCoordinator()

        coordinator.tab = self
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        // Two mailboxes for messages from page scripts: one in the page's own
        // script world, one in Vela's private world that pages can't reach.
        contentController.add(WeakScriptMessageHandler(coordinator), name: ContentBlocker.messageName)
        contentController.add(WeakScriptMessageHandler(coordinator), contentWorld: .defaultClient, name: ContentBlocker.clientMessageName)
        installScripts(for: privacy)

        // Key-Value Observing (KVO): WebKit tells us whenever these change.
        observations = [
            watch(\.title),
            watch(\.url),
            watch(\.isLoading),
            watch(\.canGoBack),
            watch(\.canGoForward),
            watch(\.estimatedProgress),
            watch(\.cameraCaptureState),
            watch(\.microphoneCaptureState),
        ]
    }

    /// A tab for a window that a page opened, such as "Sign in with Google".
    ///
    /// **Why it's special:** WebKit links this window to the page that opened
    /// it (`window.opener`), so the sign-in pop-up can hand your login back to
    /// the site and close itself. That link only works if the new web view uses
    /// the *exact* configuration WebKit gives us, so this tab shares the opener's
    /// blocking rules, scripts and message mailboxes instead of making its own.
    init(popupConfiguration: WKWebViewConfiguration, isPrivate: Bool, url: URL?) {
        contentController = popupConfiguration.userContentController
        webView = VelaWebView(frame: .zero, configuration: popupConfiguration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        self.isPrivate = isPrivate
        coordinator = TabCoordinator()
        self.url = url

        coordinator.tab = self
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator

        observations = [
            watch(\.title),
            watch(\.url),
            watch(\.isLoading),
            watch(\.canGoBack),
            watch(\.canGoForward),
            watch(\.estimatedProgress),
            watch(\.cameraCaptureState),
            watch(\.microphoneCaptureState),
        ]
    }

    func load(_ url: URL) {
        isAsleep = false
        if focusBlocked != url { focusBlocked = nil }
        mediaSearch = nil
        reader = nil
        self.url = url
        if url.isFileURL {
            // A saved web page from your Mac (opened from Finder).
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            var request = URLRequest(url: url)
            if settings().globalPrivacyControl { request.setValue("1", forHTTPHeaderField: GlobalPrivacyControl.header) }
            webView.load(request)
        }
    }

    /// Swaps in a newly compiled set of blocking rules (or none).
    func apply(ruleList: WKContentRuleList?) {
        contentController.removeAllContentRuleLists()
        if let ruleList { contentController.add(ruleList) }
    }

    /// (Re)adds Vela's page scripts. New scripts take effect on the next page load.
    func installScripts(for privacy: PrivacySettings) {
        contentController.removeAllUserScripts()
        contentController.addUserScript(ContentBlocker.popupGuardScript(
            popUnderProtection: privacy.blockingLevel != .off && privacy.popUnderProtection,
            shieldsDownSites: privacy.shieldsDownSites
        ))
        contentController.addUserScript(ContentBlocker.trackerScanScript())
        if let cleaner = ContentBlocker.adCleanerScript(for: privacy) {
            contentController.addUserScript(cleaner)
        }
        contentController.addUserScript(LinkChecker.hoverScript())
        contentController.addUserScript(MediaControls.script())
        contentController.addUserScript(DarkMode.script())
        contentController.addUserScript(PasswordScripts.loginScript())
        if privacy.fingerprintProtection {
            contentController.addUserScript(Fingerprinting.script(shieldsDownSites: privacy.shieldsDownSites))
        }
        if privacy.globalPrivacyControl {
            contentController.addUserScript(GlobalPrivacyControl.script())
        }
        if privacy.dismissCookieBanners {
            contentController.addUserScript(CookieBanners.script(shieldsDownSites: privacy.shieldsDownSites))
        }
    }

    /// "Open Anyway" on the dangerous-link warning.
    func openDangerousLinkAnyway() {
        guard let warning = linkWarning else { return }
        allowedDangerousURLs.insert(warning.url)
        linkWarning = nil
        load(warning.url)
    }

    /// "Go Back" on the dangerous-link warning.
    func dismissLinkWarning() {
        linkWarning = nil
        url = webView.url // A brand-new tab goes back to the New Tab page.
    }

    /// Types a saved login into the page's login form.
    func fillLogin(username: String, password: String, for server: String) {
        // Only ever fill into the website the login was saved for. Prefer the
        // frame that showed the login form; fall back to the page itself.
        let frame: WKFrameInfo?
        if let loginFrame, PasswordVault.normalize(loginFrame.securityOrigin.host) == server {
            frame = loginFrame
        } else if let url, PasswordVault.normalize(url.host() ?? "") == server {
            frame = nil
        } else {
            return
        }
        didAutoFill = true
        // The frame could have moved to another site while you used Touch ID,
        // so the fill script checks the address again right before typing.
        let arguments: [String: Any] = ["username": username, "password": password, "site": server]
        webView.callAsyncJavaScript(
            PasswordScripts.fillFunction, arguments: arguments, in: frame, in: .defaultClient
        ) { [weak self] result in
            if case .success(let filled) = result, filled as? String == "password" {
                self?.didFillPassword = true
            }
            // The form's frame may have gone away (the page swapped it out).
            // Try once more in the page itself.
            guard case .failure = result, frame != nil, let self,
                  let url = self.url, PasswordVault.normalize(url.host() ?? "") == server else { return }
            self.webView.callAsyncJavaScript(
                PasswordScripts.fillFunction, arguments: arguments, in: nil, in: .defaultClient
            ) { [weak self] retry in
                if case .success(let filled) = retry, filled as? String == "password" {
                    self?.didFillPassword = true
                }
            }
        }
    }

    func setPopupsAllowed(_ allowed: Bool) {
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = allowed
    }

    // MARK: Sleeping tabs

    /// Unloads the page to free memory, keeping its address and title.
    func sleep() {
        guard !isAsleep, url != nil, mediaSearch == nil, reader == nil else { return }
        isAsleep = true
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    /// A small picture of the page, shown when you hover over the tab.
    /// Kept in memory only.
    var preview: NSImage?

    /// Takes the hover picture while the page is on screen.
    func capturePreview() {
        guard url != nil, !isAsleep, webView.window != nil else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 360
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            if let image { self?.preview = image }
        }
    }

    /// Loads a sleeping tab's page again.
    func wake() {
        guard isAsleep, let url else { return }
        // If the page is still in this tab's history (it was put to sleep,
        // not restored from last session), step back to it. That keeps your
        // Back and Forward history the way it was.
        if let previous = webView.backForwardList.backItem, previous.url == url,
           webView.backForwardList.currentItem?.url.scheme == "about" {
            isAsleep = false
            webView.goBack()
        } else {
            load(url)
        }
    }

    /// A tab brought back from your last session. It stays asleep (nothing
    /// loads) until you open it, so restoring 30 tabs is instant.
    func restoreAsleep(url: URL, title: String) {
        self.url = url
        self.title = title.isEmpty ? BrowserStore.siteName(url) : title
        isAsleep = true
    }

    /// Stops the camera and microphone for this tab (the red icon on the tab).
    func stopCapture() {
        webView.setCameraCaptureState(.none, completionHandler: nil)
        webView.setMicrophoneCaptureState(.none, completionHandler: nil)
    }

    // MARK: Picture in picture and private email

    /// Moves the page's video into a small floating window, or back.
    /// Returns what happened: "on", "off", "none" (no video) or "unsupported".
    func togglePictureInPicture() async -> String {
        let body = """
        const videos = [...document.querySelectorAll('video')].filter((v) => v.readyState > 0 || v.currentSrc);
        if (!videos.length) return 'none';
        const playing = videos.find((v) => !v.paused);
        const video = playing || videos.sort((a, b) => b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight)[0];
        video.disablePictureInPicture = false;
        video.removeAttribute('disablepictureinpicture');
        if (video.webkitPresentationMode === 'picture-in-picture' || document.pictureInPictureElement === video) {
          if (video.webkitSetPresentationMode) video.webkitSetPresentationMode('inline');
          else await document.exitPictureInPicture();
          return 'off';
        }
        if (video.webkitSupportsPresentationMode && video.webkitSupportsPresentationMode('picture-in-picture')) {
          video.webkitSetPresentationMode('picture-in-picture');
          return 'on';
        }
        if (document.pictureInPictureEnabled) { await video.requestPictureInPicture(); return 'on'; }
        return 'unsupported';
        """
        return (try? await runScript(body, arguments: [:])) as? String ?? "unsupported"
    }

    /// Types an email address into the box you're in (or the page's email
    /// box). Returns true if it found somewhere to put it.
    func fillEmail(_ address: String) async -> Bool {
        let body = """
        const usable = (el) => el && el.tagName === 'INPUT' && !el.disabled && !el.readOnly
          && !['password', 'hidden', 'checkbox', 'radio', 'submit', 'button'].includes((el.type || '').toLowerCase());
        let field = document.activeElement;
        if (!usable(field)) {
          field = [...document.querySelectorAll('input[type="email"], input[name*="email" i], input[autocomplete="email"]')]
            .find((el) => usable(el) && el.offsetParent !== null);
        }
        if (!field) return false;
        const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
        setter.call(field, address);
        field.dispatchEvent(new Event('input', { bubbles: true }));
        field.dispatchEvent(new Event('change', { bubbles: true }));
        field.focus();
        return true;
        """
        return (try? await runScript(body, arguments: ["address": address])) as? Bool ?? false
    }

    /// Runs JavaScript in Vela's private script world (pages can't see it).
    func runScript(_ body: String, arguments: [String: Any]) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .defaultClient) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    /// A new page started: forget the previous page's shield stats.
    fileprivate func resetPageStats() {
        trackersFound = []
        popupsBlocked = []
        hoveredLink = nil
        savedLogins = []
        isLoginPickerShown = false
        didAutoFill = false
        didFillPassword = false
        loginFrame = nil
        // A question from the previous page no longer applies.
        permissionRequest?.answer(false)
        permissionRequest = nil
    }

    func zoomIn() { setZoom(zoom + 0.1) }
    func zoomOut() { setZoom(zoom - 0.1) }
    func resetZoom() { setZoom(1) }

    private func setZoom(_ value: Double) {
        // Round to whole percents so 0.1 steps don't drift (e.g. 1.2000000002).
        zoom = (min(max(value, 0.5), 3) * 100).rounded() / 100
        webView.pageZoom = zoom
    }

    private func watch<Value>(_ keyPath: KeyPath<WKWebView, Value>) -> NSKeyValueObservation {
        webView.observe(keyPath, options: [.new]) { [weak self] _, _ in
            // WebKit reports changes on the main thread, which is where UI state lives.
            MainActor.assumeIsolated { self?.syncFromWebView() }
        }
    }

    /// Copies the web view's current state into our observable properties.
    private func syncFromWebView() {
        isUsingCamera = webView.cameraCaptureState != .none
        isUsingMicrophone = webView.microphoneCaptureState != .none
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        // A sleeping tab keeps showing the page it had, not the empty page.
        guard !isAsleep else { return }
        if let current = webView.url { url = current }
        let pageTitle = webView.title ?? ""
        if let mediaSearch {
            title = mediaSearch.title
        } else if !pageTitle.isEmpty {
            title = pageTitle
        } else if let url {
            title = BrowserStore.siteName(url)
        }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

/// Receives callbacks from WebKit for one tab: new windows, navigation
/// decisions, downloads and messages from Vela's page scripts.
@MainActor
final class TabCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var tab: BrowserTab?

    // MARK: New windows and pop-ups

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let tab else { return nil }
        let url = navigationAction.request.url
        let settings = tab.settings()

        // Pop-under protection: never open a new tab straight to an ad network.
        if settings.blockingLevel != .off, settings.popUnderProtection, shieldsUp(for: tab, settings),
           let url, let host = url.host(), ContentBlocker.isTracker(host) {
            tab.onPopupBlocked?(url, true)
            return nil
        }
        // Open the new window as a tab that stays linked to this page.
        return tab.onOpenWindow?(configuration, url)
    }

    /// A page asked for the camera or microphone. Vela uses your remembered
    /// answer for the site, or asks you with a banner over the page.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        guard let tab, let ask = tab.onMediaPermission else {
            decisionHandler(.deny)
            return
        }
        let kinds: [PermissionKind] = switch type {
        case .camera: [.camera]
        case .microphone: [.microphone]
        default: [.camera, .microphone]
        }
        ask(PermissionKind.siteName(origin.host), kinds) { allowed in
            decisionHandler(allowed ? .grant : .deny)
        }
    }

    /// The page called window.close(), e.g. a sign-in pop-up that's finished.
    func webViewDidClose(_ webView: WKWebView) {
        tab?.onCloseRequested?()
    }

    // MARK: Navigation decisions

    /// Asked before every page (and frame) loads. This is where JavaScript gets
    /// switched off for "Block all JavaScript", the link checker stops dangerous
    /// pages, and "download this" links become downloads.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        guard let tab else { return (.allow, preferences) }
        let settings = tab.settings()

        if navigationAction.shouldPerformDownload {
            return (.download, preferences)
        }

        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let pageURL = isMainFrame ? navigationAction.request.url : webView.url

        // Focus mode: show "Stay focused" instead of a distracting site.
        if isMainFrame, let url = navigationAction.request.url, tab.isFocusBlocked?(url) == true {
            tab.focusBlocked = url
            return (.cancel, preferences)
        }

        // Hardening: a web page may never open files on your Mac (file://).
        // Files you open yourself from Finder still work, because those
        // don't come from a web page. (sourceFrame can be missing for pages
        // you typed, so it's read carefully.)
        if navigationAction.request.url?.isFileURL == true,
           let source = navigationAction.value(forKey: "sourceFrame") as? WKFrameInfo,
           ["http", "https"].contains(source.request.url?.scheme?.lowercased() ?? "") {
            return (.cancel, preferences)
        }

        // HTTPS-Only: try the secure version of an http:// address first.
        // If that fails, show "Not Secure" and let you decide.
        if isMainFrame, settings.httpsOnly, let url = navigationAction.request.url,
           url.scheme?.lowercased() == "http", let host = url.host(), !HTTPSOnly.isLocal(host),
           !settings.httpAllowedSites.contains(BrowserStore.siteName(url)) {
            if tab.upgradedFrom == url {
                // The secure version already failed: ask.
                tab.upgradedFrom = nil
                tab.httpsWarning = url
                return (.cancel, preferences)
            }
            if let secure = HTTPSOnly.secureVersion(of: url) {
                tab.upgradedFrom = url
                tab.httpsWarning = nil
                Task { @MainActor in webView.load(URLRequest(url: secure)) }
                return (.cancel, preferences)
            }
        }
        // Tracking tags and Global Privacy Control: load a clean address,
        // with the "don't sell my data" header, instead.
        if isMainFrame, let url = navigationAction.request.url,
           (navigationAction.request.httpMethod ?? "GET").uppercased() == "GET",
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           navigationAction.navigationType != .backForward, navigationAction.navigationType != .reload,
           !settings.shieldsDownSites.contains(BrowserStore.siteName(url)),
           tab.reissuedURL != url,
           // A "#section" link on the same page must not reload it.
           url.withoutFragment != webView.url?.withoutFragment {
            let cleaned = settings.stripTrackingParameters ? TrackingParameters.clean(url) : nil
            // Link clicks to another site don't carry the header on their own.
            let needsSignal = settings.globalPrivacyControl
                && navigationAction.navigationType == .linkActivated
                && navigationAction.request.value(forHTTPHeaderField: GlobalPrivacyControl.header) == nil
                && url.host() != webView.url?.host()
            let target = cleaned ?? url
            // If a site insists on its tags (it redirects straight back to
            // them), let it be rather than loop.
            if cleaned != nil || needsSignal, target != tab.reissuedURL {
                var request = URLRequest(url: target)
                if settings.globalPrivacyControl { request.setValue("1", forHTTPHeaderField: GlobalPrivacyControl.header) }
                tab.reissuedURL = target
                Task { @MainActor in webView.load(request) }
                return (.cancel, preferences)
            }
        }

        let site = pageURL.map(BrowserStore.siteName)
        preferences.allowsContentJavaScript = settings.scriptLevel(for: site) != .blockAll
        // Lockdown Mode for sites you've chosen (Site Settings or the shield).
        preferences.isLockdownModeEnabled = site.map { settings.lockdownSites.contains($0) } ?? false

        if isMainFrame, let url = navigationAction.request.url {
            let isRevisit = navigationAction.navigationType == .backForward || navigationAction.navigationType == .reload
            if settings.linkCheckerEnabled, settings.warnBeforeDangerousLinks, !isRevisit,
               !tab.allowedDangerousURLs.contains(url) {
                let report = LinkChecker.check(url)
                if report.verdict == .dangerous {
                    tab.linkWarning = LinkWarning(url: url, report: report)
                    return (.cancel, preferences)
                }
            }
            // Google Safe Browsing: known malware and phishing sites.
            if settings.safeBrowsingEnabled, !isRevisit, !tab.allowedDangerousURLs.contains(url),
               let threat = await tab.checkThreat?(url) {
                var report = LinkReport()
                report.flag(.dangerous, threat.reason)
                tab.linkWarning = LinkWarning(url: url, report: report)
                return (.cancel, preferences)
            }
            tab.linkWarning = nil
        }
        return (.allow, preferences)
    }

    /// Asked when the server answers. Files a page can't display become downloads.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        let isAttachment = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?
            .lowercased().hasPrefix("attachment") ?? false

        if navigationResponse.isForMainFrame {
            return (isAttachment || !navigationResponse.canShowMIMEType) ? .download : .allow
        }
        // Hidden frames can't start downloads (a common "drive-by download" trick).
        return navigationResponse.canShowMIMEType && !isAttachment ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        tab?.onDownload?(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        tab?.onDownload?(download)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        tab?.upgradedFrom = nil
        tab?.reissuedURL = nil
        tab?.resetPageStats()
        tab?.mediaFrames = [:]
        tab?.isPlayingAudio = false
        // Pop-ups: your per-site choice (Site Settings) or the global switch.
        if let tab {
            tab.setPopupsAllowed(tab.settings().allowsPopups(on: webView.url.map(BrowserStore.siteName)))
        }
    }

    /// A page failed before anything appeared. If it was the secure version
    /// Vela tried for an http:// address, show the "Not Secure" warning.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard let tab, let original = tab.upgradedFrom else { return }
        let error = error as NSError
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
        guard let failed = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL,
              failed.scheme?.lowercased() == "https", failed.host() == original.host() else { return }
        tab.upgradedFrom = nil
        tab.httpsWarning = original
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tab?.onFinishLoading?()
    }

    // MARK: Messages from page scripts

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let tab, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }

        if message.name == ContentBlocker.clientMessageName {
            handleClientMessage(type, body: body, frame: message.frameInfo, tab: tab)
            return
        }
        switch type {
        case "tracker":
            if let domain = body["domain"] as? String { tab.onTrackerFound?(domain) }
        case "popup":
            let address = body["url"] as? String ?? ""
            let isPopUnder = body["popunder"] as? Bool ?? false
            tab.onPopupBlocked?(URL(string: address), isPopUnder)
        default:
            break
        }
    }

    /// Messages from Vela's private script world (link hover and passwords).
    private func handleClientMessage(_ type: String, body: [String: Any], frame: WKFrameInfo, tab: BrowserTab) {
        // The website a message really came from, according to WebKit, not the page.
        let origin = frame.securityOrigin
        let isSecure = origin.protocol == "https" || origin.host == "localhost"

        switch type {
        case "hover":
            guard frame.isMainFrame, tab.settings().linkCheckerEnabled else { return }
            let address = String((body["url"] as? String ?? "").prefix(4096))
            tab.hoveredLink = address.isEmpty ? nil : URL(string: address)
        case "media":
            tab.mediaChanged(isAudible: body["audible"] as? Bool ?? false, in: frame)
        case "loginForm":
            guard isSecure else { return }
            tab.loginFrame = frame
            // "Email first, password next" pages: Vela filled the email, and
            // now the password box appeared. Allow one more fill for it.
            if body["hasPassword"] as? Bool == true, !tab.didFillPassword { tab.didAutoFill = false }
            tab.onLoginFormFound?(origin.host)
        case "loginFieldFocused":
            guard isSecure else { return }
            tab.loginFrame = frame
            tab.onLoginFieldFocused?(origin.host)
        case "credentials":
            guard isSecure,
                  let username = body["username"] as? String,
                  let password = body["password"] as? String,
                  username.count <= 512, password.count <= 1024 else { return }
            tab.onLoginSubmitted?(origin.host, username, password)
        default:
            break
        }
    }

    private func shieldsUp(for tab: BrowserTab, _ settings: PrivacySettings) -> Bool {
        guard let url = tab.url else { return true }
        return !settings.shieldsDownSites.contains(BrowserStore.siteName(url))
    }
}

/// WebKit keeps a strong hold on message handlers, which would keep a closed
/// tab alive forever. This small go-between holds the real handler weakly.
@MainActor
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// HTTPS-Only mode helpers.
enum HTTPSOnly {
    /// Addresses on your own Mac or home network often have no https
    /// version, so they're left alone.
    static func isLocal(_ host: String) -> Bool {
        let host = host.lowercased()
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") || !host.contains(".") {
            return true
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    static func secureVersion(of url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "https"
        if components.port == 80 { components.port = nil }
        return components.url
    }
}
