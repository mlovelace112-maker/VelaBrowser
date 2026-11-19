import Foundation
import WebKit

/// Builds Vela's blocking rules and the two small scripts the shield adds to pages.
///
/// **How blocking works:** WebKit has a built-in, very fast content blocker
/// (the same one Safari's ad-blocker extensions use). We hand it a list of
/// rules written in JSON, such as "block any request to doubleclick.net". WebKit
/// compiles them once and then applies them to every page, before anything
/// downloads. Our Swift code never has to look at each request itself.
@MainActor
enum ContentBlocker {
    /// Messages from scripts that share the page's own JavaScript world.
    static let messageName = "velaShield"
    /// Messages from Vela's private script world, which the page can't see or fake
    /// (used for the link checker and passwords).
    static let clientMessageName = "velaClient"
    private static let ruleListID = "vela.shield"

    // MARK: - Rules

    /// Compiles the rules for these settings. Returns nil when there's nothing to block.
    static func compile(for settings: PrivacySettings) async -> WKContentRuleList? {
        if let full = await compile(makeRules(for: settings)) { return full }
        // If a hiding rule ever fails to compile, keep the network blocking working without it.
        return await compile(makeRules(for: settings, includeHidingRules: false))
    }

    private static func compile(_ rules: [[String: Any]]) async -> WKContentRuleList? {
        guard !rules.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else { return nil }

        return await withCheckedContinuation { (continuation: CheckedContinuation<WKContentRuleList?, Never>) in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: ruleListID,
                encodedContentRuleList: json
            ) { ruleList, error in
                if let error {
                    NSLog("Vela: blocking rules failed to compile: %@", error.localizedDescription)
                }
                continuation.resume(returning: ruleList)
            }
        }
    }

    static func makeRules(for settings: PrivacySettings, includeHidingRules: Bool = true) -> [[String: Any]] {
        var rules: [[String: Any]] = []
        let blocking = settings.blockingLevel != .off

        // 1. Trackers, ad networks and pop-up networks.
        if blocking {
            for domain in trackerDomains {
                var trigger: [String: Any] = ["url-filter": urlPattern(for: domain)]
                if settings.blockingLevel == .standard {
                    trigger["load-type"] = ["third-party"]
                }
                rules.append(["trigger": trigger, "action": ["type": "block"]])
            }
        }

        // 2. Aggressive: block ad-shaped requests from any company, and hide leftover ad boxes.
        if settings.blockingLevel == .aggressive {
            for path in adPathPatterns {
                rules.append([
                    "trigger": ["url-filter": path, "load-type": ["third-party"]] as [String: Any],
                    "action": ["type": "block"],
                ])
            }
            if includeHidingRules {
                rules.append(hide(cosmeticSelectors))
            }
        }

        // 3. Embedded ads: video-ad players and ad frames inside articles.
        if blocking && settings.blockEmbeddedAds {
            for domain in videoAdDomains {
                rules.append([
                    "trigger": ["url-filter": urlPattern(for: domain), "load-type": ["third-party"]] as [String: Any],
                    "action": ["type": "block"],
                ])
            }
            if includeHidingRules {
                rules.append(hide(embeddedAdSelectors))
            }
        }

        // 4. Interstitials: full-screen ads that cover the page.
        if blocking && settings.blockInterstitialAds && includeHidingRules {
            rules.append(hide(interstitialSelectors))
        }

        // 5. Third-party cookies: sites can't follow you around using cookies set inside other sites.
        if settings.blockThirdPartyCookies {
            rules.append([
                "trigger": ["url-filter": ".*", "load-type": ["third-party"]] as [String: Any],
                "action": ["type": "block-cookies"],
            ])
        }

        // 5b. Sign-in services ("Sign in with Google" and friends) need their own
        //     cookies inside other sites' sign-in buttons, or logging in breaks.
        //     "ignore-previous-rules" undoes everything above for just these addresses.
        if !rules.isEmpty {
            for domain in signInDomains {
                rules.append([
                    "trigger": ["url-filter": urlPattern(for: domain)],
                    "action": ["type": "ignore-previous-rules"],
                ])
            }
        }

        // 6. Upgrade insecure http:// requests to https://.
        if settings.upgradeToHTTPS {
            rules.append([
                "trigger": ["url-filter": "^http://"],
                "action": ["type": "make-https"],
            ])
        }

        // 7. Sites where you turned the shield off: "ignore all the rules above".
        if !rules.isEmpty {
            for site in settings.shieldsDownSites.sorted() {
                rules.append([
                    "trigger": ["url-filter": ".*", "if-top-url": [urlPattern(for: site)]] as [String: Any],
                    "action": ["type": "ignore-previous-rules"],
                ])
            }
        }

        // 8. Script slider: block scripts from other companies. This comes after
        //    step 7 because it's a separate choice from the shield.
        //    (The "Block all JavaScript" position is handled per page in BrowserTab.)
        var scriptTrigger: [String: Any] = [
            "url-filter": ".*",
            "resource-type": ["script"],
            "load-type": ["third-party"],
        ]
        if settings.scriptLevel == .blockThirdParty {
            // On everywhere, except sites you set to something else.
            let exceptions = settings.siteScriptLevels
                .filter { $0.value != .blockThirdParty }
                .keys.sorted().map { urlPattern(for: $0) }
            if !exceptions.isEmpty { scriptTrigger["unless-top-url"] = exceptions }
            rules.append(["trigger": scriptTrigger, "action": ["type": "block"]])
        } else {
            // Off everywhere, except sites you set to "Block 3rd-party".
            let sites = settings.siteScriptLevels
                .filter { $0.value == .blockThirdParty }
                .keys.sorted().map { urlPattern(for: $0) }
            if !sites.isEmpty {
                scriptTrigger["if-top-url"] = sites
                rules.append(["trigger": scriptTrigger, "action": ["type": "block"]])
            }
        }
        return rules
    }

    /// A rule that hides page elements matching these CSS selectors.
    private static func hide(_ selectors: [String]) -> [String: Any] {
        [
            "trigger": ["url-filter": ".*"],
            "action": ["type": "css-display-none", "selector": selectors.joined(separator: ", ")],
        ]
    }

    /// A WebKit pattern matching a domain and all its subdomains, over http or https.
    /// "doubleclick.net" also matches "ad.doubleclick.net" but not "notdoubleclick.net".
    private static func urlPattern(for domain: String) -> String {
        let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
        return "^[^:]+://+([^:/]+\\.)?\(escaped)[:/]"
    }

    static func isTracker(_ host: String) -> Bool {
        let host = host.lowercased()
        return trackerDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: - Page scripts

    /// Runs at the start of every page and frame. Pages open pop-ups with
    /// `window.open`. WebKit already blocks the ones you didn't click for; this
    /// notices when that happens so Vela can show "Pop-up blocked · Allow once".
    ///
    /// **Pop-unders** are sneakier: the page waits for you to click *anywhere*
    /// (so it counts as "you clicked"), then opens an ad tab. With pop-under
    /// protection on, a click that wasn't on a link or button can't open a tab
    /// to a different website.
    static func popupGuardScript(popUnderProtection: Bool, shieldsDownSites: Set<String>) -> WKUserScript {
        let source = """
        (() => {
          if (window.__velaPopupGuard) return;
          window.__velaPopupGuard = true;
          const shieldsDown = \(jsonArray(shieldsDownSites.sorted()));
          const host = location.hostname;
          const shieldOff = shieldsDown.some((s) => host === s || host.endsWith('.' + s));
          const POPUNDER = \(popUnderProtection) && !shieldOff;
          const post = (message) => {
            try { window.webkit.messageHandlers.\(messageName).postMessage(message); } catch (e) {}
          };
          let lastClick = null;
          document.addEventListener('click', (e) => { lastClick = { target: e.target, time: Date.now() }; }, true);
          const siteOf = (h) => h.replace(/^www\\./, '');
          const original = window.open;
          window.open = function (url, ...rest) {
            const clicked = navigator.userActivation ? navigator.userActivation.isActive : true;
            let href = '';
            try { href = url ? new URL(url, location.href).href : ''; } catch (e) {}
            if (POPUNDER && clicked && href) {
              const recent = lastClick && Date.now() - lastClick.time < 1500 ? lastClick.target : null;
              const control = recent && recent.closest
                ? recent.closest('a[href], button, input, select, textarea, label, summary, [role="button"], [role="link"], [role="menuitem"], [role="tab"]')
                : null;
              let otherSite = true;
              try { otherSite = siteOf(new URL(href).hostname) !== siteOf(host); } catch (e) {}
              if (!control && otherSite) {
                post({ type: 'popup', url: href, popunder: true });
                return null;
              }
            }
            const opened = original.call(window, url, ...rest);
            if (!opened && !clicked) {
              post({ type: 'popup', url: href, popunder: false });
            }
            return opened;
          };
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    /// Cleans up ads the network rules can't stop, after the page loads:
    /// full-screen ad overlays (interstitials), invisible full-page links that
    /// open pop-unders, and empty frames left behind by blocked ads.
    /// Returns nil when none of those settings are on.
    static func adCleanerScript(for settings: PrivacySettings) -> WKUserScript? {
        guard settings.blockingLevel != .off,
              settings.blockInterstitialAds || settings.popUnderProtection || settings.blockEmbeddedAds else { return nil }
        let source = """
        (() => {
          if (window.__velaCleaner) return;
          window.__velaCleaner = true;
          const shieldsDown = \(jsonArray(settings.shieldsDownSites.sorted()));
          const host = location.hostname;
          if (shieldsDown.some((s) => host === s || host.endsWith('.' + s))) return;
          const INTERSTITIALS = \(settings.blockInterstitialAds);
          const POPUNDER = \(settings.popUnderProtection);
          const EMBEDDED = \(settings.blockEmbeddedAds);
          const adDomains = \(jsonArray(trackerDomains));
          const adWords = /(^|[^a-z])(ad|ads|advert|advertisement|interstitial|preroll|sponsor|sponsored|takeover|popunder|adblock)([^a-z]|$)/i;
          const isAdHost = (h) => adDomains.some((d) => h === d || h.endsWith('.' + d));
          const coversScreen = (el) => {
            const r = el.getBoundingClientRect();
            return r.width >= innerWidth * 0.85 && r.height >= innerHeight * 0.85;
          };
          const label = (el) => (el.id || '') + ' ' + (typeof el.className === 'string' ? el.className : '');
          const restoreScroll = () => {
            for (const el of [document.documentElement, document.body]) {
              if (!el) continue;
              const s = getComputedStyle(el);
              if (s.overflow === 'hidden' || s.overflowY === 'hidden') el.style.setProperty('overflow', 'auto', 'important');
            }
          };
          const clean = () => {
            if (!document.body) return;
            let removed = false;
            document.querySelectorAll('body > *, body > * > *').forEach((el) => {
              if (!el.isConnected) return;
              const style = getComputedStyle(el);
              if (style.position !== 'fixed' || !coversScreen(el)) return;
              const z = parseInt(style.zIndex, 10) || 0;
              if (z < 100) return;
              // A full-screen ad covering the page.
              if (INTERSTITIALS && adWords.test(label(el))) {
                el.remove(); removed = true; return;
              }
              // An invisible full-page link: clicking "the page" opens an ad tab.
              const invisible = Number(style.opacity) < 0.1;
              const isLink = el.tagName === 'A' && el.target === '_blank';
              if (POPUNDER && (isLink || invisible) && !(el.innerText || '').trim()) {
                el.remove(); removed = true;
              }
            });
            if (removed) restoreScroll();
          };
          const hideAdFrames = () => {
            document.querySelectorAll('iframe').forEach((frame) => {
              let frameHost = '';
              try { frameHost = new URL(frame.src, location.href).hostname; } catch (e) { return; }
              if (frameHost && frameHost !== host && isAdHost(frameHost)) {
                frame.style.setProperty('display', 'none', 'important');
              }
            });
          };
          const run = () => {
            try { clean(); if (EMBEDDED) hideAdFrames(); } catch (e) {}
          };
          run();
          let timer = null;
          new MutationObserver(() => {
            if (!timer) timer = setTimeout(() => { timer = null; run(); }, 800);
          }).observe(document.documentElement, { childList: true, subtree: true });
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    /// Turns a list of strings into a JavaScript array, safely quoted.
    static func jsonArray(_ values: [String]) -> String {
        (try? JSONSerialization.data(withJSONObject: values))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    /// Runs when a page has loaded. It looks for scripts, images and frames that
    /// point at known trackers. Those requests were already blocked, so this
    /// only reports *which* trackers the page tried to load, for the shield's count.
    static func trackerScanScript() -> WKUserScript {
        let list = jsonArray(trackerDomains)
        let source = """
        (() => {
          if (window.__velaShieldScan) return;
          window.__velaShieldScan = true;
          const domains = \(list);
          const seen = new Set();
          const check = (value) => {
            if (!value) return;
            let host;
            try { host = new URL(value, location.href).hostname; } catch (e) { return; }
            if (!host || host === location.hostname) return;
            for (const d of domains) {
              if (host === d || host.endsWith('.' + d)) {
                if (!seen.has(d)) {
                  seen.add(d);
                  try { window.webkit.messageHandlers.\(messageName).postMessage({ type: 'tracker', domain: d }); } catch (e) {}
                }
                return;
              }
            }
          };
          const scan = () => {
            document.querySelectorAll('script[src], img[src], iframe[src], link[rel~="preload"][href], link[rel~="prefetch"][href]')
              .forEach((el) => check(el.getAttribute('src') || el.getAttribute('href')));
          };
          let timer = null;
          scan();
          new MutationObserver(() => {
            if (!timer) timer = setTimeout(() => { timer = null; scan(); }, 500);
          }).observe(document.documentElement, { childList: true, subtree: true });
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    // MARK: - Lists

    /// Well-known ad networks, trackers and analytics services.
    /// Add a domain here to block it everywhere.
    static let trackerDomains: [String] = [
        // Google ads and analytics
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com",
        "googletagmanager.com", "googletagservices.com", "adservice.google.com", "2mdn.net",
        // Meta, X, LinkedIn, TikTok, Pinterest, Snap, Reddit pixels
        "connect.facebook.net", "pixel.facebook.com", "ads-twitter.com", "analytics.twitter.com",
        "ads.linkedin.com", "px.ads.linkedin.com", "analytics.tiktok.com", "ads.tiktok.com",
        "ct.pinterest.com", "tr.snapchat.com", "alb.reddit.com", "events.redditmedia.com",
        // Microsoft, Yandex, Amazon ads
        "bat.bing.com", "clarity.ms", "mc.yandex.ru", "amazon-adsystem.com",
        // Ad exchanges and networks
        "adnxs.com", "criteo.com", "criteo.net", "taboola.com", "outbrain.com", "adsrvr.org",
        "rubiconproject.com", "pubmatic.com", "openx.net", "casalemedia.com", "indexww.com",
        "moatads.com", "media.net", "sharethrough.com", "teads.tv", "yieldmo.com", "3lift.com",
        "smartadserver.com", "adform.net", "bidswitch.net", "mathtag.com", "adroll.com",
        "zemanta.com", "revcontent.com", "mgid.com", "lijit.com", "sovrn.com", "gumgum.com",
        "kargo.com", "unrulymedia.com", "serving-sys.com", "flashtalking.com", "innovid.com",
        "spotxchange.com", "springserve.com", "contextweb.com", "advertising.com", "yieldlab.net",
        "adition.com", "districtm.io", "sonobi.com", "triplelift.com", "33across.com",
        "undertone.com", "verizonmedia.com", "adtech.com", "zedo.com",
        // Pop-up and pop-under networks
        "propellerads.com", "popads.net", "popcash.net", "adsterra.com", "exoclick.com",
        "trafficjunky.net", "juicyads.com", "hilltopads.net", "adcash.com", "clickadu.com",
        "popmyads.com", "popunder.net", "onclickads.net", "onclkds.com", "admaven.com", "ad-maven.com",
        "monetag.com", "galaksion.com", "trafficstars.com", "tsyndicate.com", "realsrv.com",
        "evadav.com", "rollerads.com", "zeropark.com", "clickaine.com", "richpush.co",
        "pushground.com", "a-ads.com", "adsco.re", "adskeeper.com", "adspyglass.com",
        "bidvertiser.com", "revenuehits.com", "yllix.net", "popadscdn.net", "highperformanceformat.com",
        "profitablecpmrate.com", "displayvertising.com", "acint.net", "ad-delivery.net",
        // Native "around the web" ad widgets and more exchanges
        "nativo.com", "ntv.io", "plista.com", "ligatus.com", "content.ad", "zergnet.com",
        "adblade.com", "dianomi.com", "connatix.com", "primis.tech", "vidoomy.com", "aniview.com",
        "seedtag.com", "insticator.com", "adthrive.com", "mediavine.com", "ezoic.net", "ezojs.com",
        "freestar.com", "pubnation.com", "adpushup.com", "venatus.com", "playwire.com",
        // Data brokers and audience tracking
        "scorecardresearch.com", "quantserve.com", "quantcount.com", "demdex.net",
        "everesttech.net", "omtrdc.net", "krxd.net", "bluekai.com", "exelator.com",
        "rlcdn.com", "tapad.com", "agkn.com", "crwdcntrl.net", "addthis.com", "sharethis.com",
        "liadm.com", "id5-sync.com", "adsymptotic.com", "intentiq.com", "eyeota.net",
        // Session recording and analytics
        "hotjar.com", "hotjar.io", "mouseflow.com", "crazyegg.com", "inspectlet.com",
        "luckyorange.com", "luckyorange.net", "fullstory.com", "mixpanel.com", "segment.io",
        "cdn.segment.com", "api.segment.io", "heapanalytics.com", "kissmetrics.com",
        "chartbeat.com", "chartbeat.net", "statcounter.com", "nr-data.net", "amplitude.com",
        "branch.io", "app-measurement.com", "newrelic.com", "pendo.io", "quantummetric.com",
    ]

    /// "Sign in with Google / Apple / Microsoft" services that keep their cookies.
    static let signInDomains: [String] = [
        "accounts.google.com", "appleid.apple.com", "login.microsoftonline.com", "login.live.com",
    ]

    /// Parts of web addresses that only ads use. Aggressive mode blocks these
    /// from any company (but never from the site you're visiting).
    /// WebKit's patterns don't support "this|that", so each gets its own rule.
    static let adPathPatterns: [String] = [
        "/pagead/", "/adserver", "/adframe", "/ad_banner", "/ads/banner", "/adsbygoogle",
        "prebid[.-]", "/prebid", "/advert", "/ad[.]js", "/ads[.]js", "[/_.-]popunder",
        "/pop[.]js", "/vast/", "/vast[.]xml", "/vpaid", "/adunit", "/adtag", "/adimg",
    ]

    /// Video-ad players embedded in articles.
    static let videoAdDomains: [String] = [
        "imasdk.googleapis.com", "ads.youtube.com", "vid.springserve.com", "ads.stickyadstv.com",
        "ad.360yield.com", "vast.adsafeprotected.com", "pixel.adsafeprotected.com", "adsafeprotected.com",
        "doubleverify.com", "cdn.doubleverify.com", "imrworldwide.com", "jwpltx.com",
    ]

    /// CSS selectors for ads embedded inside articles (hidden when "Embedded ads" is on).
    static let embeddedAdSelectors: [String] = [
        "iframe[id^=\"google_ads_iframe\"]", "[id^=\"div-gpt-ad\"]", "ins.adsbygoogle",
        ".native-ad", ".ad-wrapper", ".ad-unit", ".in-article-ad", ".inline-ad", ".article-ad",
        "[data-ad-slot]", "[data-google-query-id]", "[aria-label=\"Advertisement\"]",
        ".ima-ad-container", ".video-ad", ".video-ads", ".preroll-ad", ".sponsored-post",
        ".trc_related_container", ".ob-widget", "[id^=\"taboola-\"]",
    ]

    /// CSS selectors for full-screen ads that cover the page (hidden when "Interstitial ads" is on).
    static let interstitialSelectors: [String] = [
        ".interstitial-ad", "#interstitial-ad", ".ad-interstitial", "#ad-interstitial",
        ".interstitial-ad-container", ".ad-takeover", ".takeover-ad", ".welcome-ad",
        ".fullscreen-ad", ".full-screen-ad", ".ad-overlay", "#ad-overlay", ".ad-modal",
    ]

    /// CSS selectors for ad boxes hidden in Aggressive mode.
    static let cosmeticSelectors: [String] = [
        ".adsbygoogle", "ins.adsbygoogle", "[id^=\"google_ads_\"]", "[id^=\"div-gpt-ad\"]",
        "[data-ad-slot]", "[data-ad-unit]", ".ad-slot", ".ad-container", ".ad-banner",
        ".advertisement", ".sponsored-content", ".taboola", "[id^=\"taboola-\"]",
        ".OUTBRAIN", ".outbrain", "[id^=\"rc_widget\"]", "iframe[src*=\"doubleclick.net\"]",
        "iframe[src*=\"googlesyndication.com\"]",
    ]
}
