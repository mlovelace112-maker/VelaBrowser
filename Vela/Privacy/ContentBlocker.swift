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
    static let messageName = "velaShield"
    private static let ruleListID = "vela.shield"

    // MARK: - Rules

    /// Compiles the rules for these settings. Returns nil when there's nothing to block.
    static func compile(for settings: PrivacySettings) async -> WKContentRuleList? {
        let rules = makeRules(for: settings)
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

    static func makeRules(for settings: PrivacySettings) -> [[String: Any]] {
        var rules: [[String: Any]] = []

        // 1. Trackers and ad networks.
        if settings.blockingLevel != .off {
            for domain in trackerDomains {
                var trigger: [String: Any] = ["url-filter": urlPattern(for: domain)]
                if settings.blockingLevel == .standard {
                    trigger["load-type"] = ["third-party"]
                }
                rules.append(["trigger": trigger, "action": ["type": "block"]])
            }
        }

        // 2. Aggressive: hide the empty boxes ads leave behind.
        if settings.blockingLevel == .aggressive {
            rules.append([
                "trigger": ["url-filter": ".*"],
                "action": ["type": "css-display-none", "selector": cosmeticSelectors.joined(separator: ", ")],
            ])
        }

        // 3. Third-party cookies: sites can't follow you around using cookies set inside other sites.
        if settings.blockThirdPartyCookies {
            rules.append([
                "trigger": ["url-filter": ".*", "load-type": ["third-party"]] as [String: Any],
                "action": ["type": "block-cookies"],
            ])
        }

        // 4. Upgrade insecure http:// requests to https://.
        if settings.upgradeToHTTPS {
            rules.append([
                "trigger": ["url-filter": "^http://"],
                "action": ["type": "make-https"],
            ])
        }

        // 5. Sites where you turned the shield off: "ignore all the rules above".
        //    These must come last.
        if !rules.isEmpty {
            for site in settings.shieldsDownSites.sorted() {
                rules.append([
                    "trigger": ["url-filter": ".*", "if-top-url": [urlPattern(for: site)]] as [String: Any],
                    "action": ["type": "ignore-previous-rules"],
                ])
            }
        }
        return rules
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
    static func popupGuardScript() -> WKUserScript {
        let source = """
        (() => {
          const original = window.open;
          window.open = function (url, ...rest) {
            const clicked = navigator.userActivation ? navigator.userActivation.isActive : true;
            const opened = original.call(window, url, ...rest);
            if (!opened && !clicked) {
              let href = '';
              try { href = url ? new URL(url, location.href).href : ''; } catch (e) {}
              try { window.webkit.messageHandlers.\(messageName).postMessage({ type: 'popup', url: href }); } catch (e) {}
            }
            return opened;
          };
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    /// Runs when a page has loaded. It looks for scripts, images and frames that
    /// point at known trackers. Those requests were already blocked, so this
    /// only reports *which* trackers the page tried to load, for the shield's count.
    static func trackerScanScript() -> WKUserScript {
        let list = (try? JSONSerialization.data(withJSONObject: trackerDomains))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
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

    /// CSS selectors for ad boxes hidden in Aggressive mode.
    static let cosmeticSelectors: [String] = [
        ".adsbygoogle", "ins.adsbygoogle", "[id^=\"google_ads_\"]", "[id^=\"div-gpt-ad\"]",
        "[data-ad-slot]", "[data-ad-unit]", ".ad-slot", ".ad-container", ".ad-banner",
        ".advertisement", ".sponsored-content", ".taboola", "[id^=\"taboola-\"]",
        ".OUTBRAIN", ".outbrain", "[id^=\"rc_widget\"]", "iframe[src*=\"doubleclick.net\"]",
        "iframe[src*=\"googlesyndication.com\"]",
    ]
}
