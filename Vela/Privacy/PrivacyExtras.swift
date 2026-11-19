import Foundation
import WebKit

// MARK: - Tracking parameters

/// Removes tracking tags from links before a page loads.
///
/// **What they are:** when you click a link in an email, an ad or a social
/// post, the address often ends with something like
/// `?utm_source=newsletter&fbclid=IwAR3…`. Those tags don't change the page
/// at all. They only tell the site (and Facebook, Google and so on) exactly
/// which email or post you came from, and often who you are.
///
/// **What Vela does:** before loading the page, it removes the known tags and
/// loads the clean address instead. Firefox and Brave do the same.
enum TrackingParameters {
    /// Tags removed on every website.
    private static let everywhere: Set<String> = [
        // Google Analytics campaign tags (utm_* is also matched by prefix below)
        "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "srsltid", "_ga", "_gl",
        // Facebook, Instagram, Microsoft, TikTok, X, LinkedIn, Yandex
        "fbclid", "igshid", "igsh", "msclkid", "ttclid", "twclid", "li_fat_id", "yclid", "_openstat",
        // Mailchimp, HubSpot, Marketo, Vero, Olytics and other email tools
        "mc_cid", "mc_eid", "_hsenc", "_hsmi", "__hssc", "__hstc", "__hsfp", "hsctatracking",
        "mkt_tok", "vero_id", "vero_conv", "oly_anon_id", "oly_enc_id", "rb_clickid", "wickedid", "epik",
        "s_cid", "trk_contact", "trk_msg", "trk_module", "trk_sid",
    ]

    /// Tags that only mean "tracking" on certain sites (elsewhere a site
    /// might use the same name for something real).
    private static let perSite: [String: Set<String>] = [
        "youtube.com": ["si", "feature", "pp"],
        "youtu.be": ["si", "feature"],
        "open.spotify.com": ["si", "context"],
        "x.com": ["s", "t", "ref_src", "ref_url"],
        "twitter.com": ["s", "t", "ref_src", "ref_url"],
        "amazon.com": ["ref_", "pd_rd_r", "pd_rd_w", "pd_rd_wg", "pf_rd_p", "pf_rd_r", "pd_rd_i"],
        "linkedin.com": ["trk", "trackingid", "lipi", "refid"],
        "instagram.com": ["igshid", "igsh", "utm_source"],
    ]

    /// The address without tracking tags, or nil if there was nothing to remove.
    static func clean(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.percentEncodedQueryItems, !items.isEmpty else { return nil }
        let host = (url.host() ?? "").lowercased()
        let siteTags = perSite.first { host == $0.key || host.hasSuffix("." + $0.key) }?.value ?? []
        let kept = items.filter { item in
            let name = item.name.lowercased()
            return !(name.hasPrefix("utm_") || everywhere.contains(name) || siteTags.contains(name))
        }
        guard kept.count != items.count else { return nil }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.url
    }
}

// MARK: - Global Privacy Control

/// Global Privacy Control (GPC): a "do not sell or share my data" signal.
///
/// In California, Colorado, Connecticut and a growing number of other places,
/// sites are legally required to honor it. Vela sends it two ways: the
/// `Sec-GPC: 1` header when you open a site, and `navigator.globalPrivacyControl`
/// for the site's scripts (that's where most sites check).
enum GlobalPrivacyControl {
    static let header = "Sec-GPC"

    static func script() -> WKUserScript {
        let source = """
        (() => {
          try {
            const get = function () { return true; };
            Object.defineProperty(Navigator.prototype, 'globalPrivacyControl', { get, configurable: true, enumerable: true });
          } catch (e) {}
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}

// MARK: - Cookie banners

/// Answers "We use cookies" pop-ups for you, choosing **Reject all**.
///
/// **How it works:** most sites use one of about twenty companies' consent
/// banners (OneTrust, Cookiebot, Didomi, Quantcast…). Vela knows where each
/// one puts its "Reject all" button and clicks it. For other banners it looks
/// for a button that says "Reject all", "Decline" or "Only necessary" inside
/// something labelled cookie or consent. If a banner has no way to say no,
/// Vela hides it, which counts as no consent.
///
/// The script runs in Vela's own private space, so pages can't see or
/// interfere with it.
enum CookieBanners {
    static func script(shieldsDownSites: Set<String>) -> WKUserScript {
        let sites = (try? JSONEncoder().encode(shieldsDownSites.sorted()))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let source = """
        (() => {
          if (window.__velaBanners) return;
          window.__velaBanners = true;
          const host = location.hostname;
          const shieldsDown = \(sites);
          if (shieldsDown.some((s) => host === s || host.endsWith('.' + s))) return;

          // The "Reject all" button of each well-known consent banner.
          const rejectButtons = [
            '#onetrust-reject-all-handler', '.ot-pc-refuse-all-handler',
            '#CybotCookiebotDialogBodyButtonDecline', '#CybotCookiebotDialogBodyLevelButtonLevelOptinDeclineAll',
            '#didomi-notice-disagree-button', '.didomi-continue-without-agreeing',
            '#truste-consent-required',
            'button[data-testid="uc-deny-all-button"]',
            '.qc-cmp2-summary-buttons button[mode="secondary"]',
            '.fc-cta-do-not-consent',
            '.cky-btn-reject', '.cmplz-btn.cmplz-deny', '.osano-cm-denyAll',
            '.iubenda-cs-reject-btn', '[data-tid="banner-decline"]', '.cm-btn-decline',
            '#axeptio_btn_dismiss', '.cc-btn.cc-deny', 'button.sp_choice_type_REJECT_ALL',
            '#cookiescript_reject', '.moove-gdpr-infobar-reject-btn', '#wt-cli-reject-btn',
            '[data-cookiebanner="accept_only_essential_button"]',
          ];
          // Banners to hide if there's no way to say no.
          const banners = [
            '#onetrust-banner-sdk', '#onetrust-consent-sdk', '#CybotCookiebotDialog', '#didomi-host',
            '#truste-consent-track', '.qc-cmp2-container', '#usercentrics-root', '.fc-consent-root',
            '.cky-consent-container', '#cmplz-cookiebanner-container', '.osano-cm-window',
            '#iubenda-cs-banner', '#cookiescript_injected', '.cc-window', '#axeptio_overlay',
            '[id^="sp_message_container"]', '#cookie-law-info-bar', '#cookie-notice',
            '#moove_gdpr_cookie_info_bar',
          ];
          const rejectText = /^(reject|decline|deny|refuse|disagree)( all)?( cookies| optional cookies| non-essential cookies| additional cookies)?$|^(only|use only|accept only|allow only) (the )?(necessary|essential|required|strictly necessary)( cookies)?$|^(necessary|essential) (cookies )?only$|^continue without (accepting|agreeing)$/i;
          const consentWords = /cookie|consent|gdpr|cmp|privacy|onetrust|didomi|usercentrics|truste|sp_message/i;
          // Some banners live in their own frame (consent.example.com).
          const isConsentFrame = /consent|privacy-mgmt|cmp|cookie/i.test(host);

          const isVisible = (el) => !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);
          const inConsentArea = (el) => {
            if (isConsentFrame) return true;
            for (let n = el, depth = 0; n && n !== document.body && depth < 15; depth++) {
              const label = (n.id || '') + ' ' + (typeof n.className === 'string' ? n.className : '') + ' ' +
                ((n.getAttribute && n.getAttribute('aria-label')) || '');
              if (consentWords.test(label)) return true;
              n = n.parentElement || (n.getRootNode && n.getRootNode().host);
            }
            return false;
          };
          // Usercentrics and a few others put their banner in a shadow root.
          const roots = () => [document].concat(
            ['#usercentrics-root', '#usercentrics-cmp-ui', '#cmpwrapper']
              .map((s) => { const el = document.querySelector(s); return el && el.shadowRoot; })
              .filter(Boolean)
          );

          let done = false;
          const tryReject = () => {
            for (const root of roots()) {
              for (const selector of rejectButtons) {
                const el = root.querySelector(selector);
                if (el && isVisible(el)) { el.click(); return true; }
              }
              const candidates = root.querySelectorAll('button, [role="button"], a, input[type="button"], input[type="submit"]');
              for (let i = 0; i < candidates.length && i < 600; i++) {
                const el = candidates[i];
                const text = (el.innerText || el.value || el.getAttribute('aria-label') || '').trim().replace(/\\s+/g, ' ');
                if (text.length < 45 && rejectText.test(text) && isVisible(el) && inConsentArea(el)) {
                  el.click();
                  return true;
                }
              }
            }
            return false;
          };
          const hideLeftovers = () => {
            const found = banners.filter((s) => { const el = document.querySelector(s); return el && isVisible(el); });
            if (!found.length) return;
            const style = document.createElement('style');
            style.textContent = found.join(',') + '{display:none!important}' +
              'html,body{overflow:auto!important}';
            (document.head || document.documentElement).appendChild(style);
          };

          const attempt = () => {
            if (done) return;
            if (tryReject()) { done = true; observer.disconnect(); }
          };
          let pending = null;
          const observer = new MutationObserver(() => {
            if (pending || done) return;
            pending = setTimeout(() => { pending = null; attempt(); }, 250);
          });
          observer.observe(document.documentElement, { childList: true, subtree: true });
          attempt();
          // Give up watching after 15 seconds; hide any banner with no "no" button.
          setTimeout(() => { if (!done) hideLeftovers(); }, 4000);
          setTimeout(() => { observer.disconnect(); }, 15000);
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: .defaultClient)
    }
}

extension URL {
    /// The same address without its "#section" part.
    var withoutFragment: URL {
        guard fragment != nil, var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.fragment = nil
        return components.url ?? self
    }
}
