import AppKit
import Foundation
import LocalAuthentication
import Observation
import Security
import WebKit

/// One saved login. Only the website and username live here; the password
/// itself stays in the Keychain until you unlock and ask for it.
struct PasswordEntry: Identifiable, Hashable {
    let server: String
    let account: String

    var id: String { server + "\n" + account }
}

/// A login you just typed, waiting for "Save password?".
struct PasswordPrompt: Identifiable, Equatable {
    let id = UUID()
    let tabID: UUID
    let server: String
    let account: String
    let password: String
    let isUpdate: Bool
}

/// Vela's password store, kept in the macOS Keychain.
///
/// **Why the Keychain?** It's the encrypted vault macOS itself uses for Wi-Fi
/// and Safari passwords. Items are encrypted with a key tied to your Mac login,
/// and macOS only hands them back to the app that saved them. Vela never writes
/// a password to a normal file.
///
/// Showing, copying or filling a password first asks for Touch ID (or your Mac
/// password). After that it stays unlocked for 10 minutes.
@MainActor
@Observable
final class PasswordVault {
    private(set) var entries: [PasswordEntry] = []
    private(set) var isUnlocked = false

    @ObservationIgnored private var unlockedAt: Date?
    private static let itemKind = "Vela Password"
    private static let unlockDuration: TimeInterval = 10 * 60

    init() {
        reload()
    }

    /// "WWW.Example.com" → "example.com"
    static func normalize(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }

    func entries(for host: String) -> [PasswordEntry] {
        let site = Self.normalize(host)
        return entries.filter { $0.server == site }
    }

    // MARK: - Unlocking

    /// Asks for Touch ID or your Mac password. `reason` finishes the sentence
    /// "Vela is trying to …".
    func unlock(reason: String) async -> Bool {
        if isUnlocked, let unlockedAt, Date().timeIntervalSince(unlockedAt) < Self.unlockDuration {
            return true
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            isUnlocked = success
            unlockedAt = success ? Date() : nil
            return success
        } catch {
            return false
        }
    }

    /// True if you unlocked with Touch ID in the last 10 minutes.
    var isRecentlyUnlocked: Bool {
        guard isUnlocked, let unlockedAt else { return false }
        return Date().timeIntervalSince(unlockedAt) < Self.unlockDuration
    }

    func lock() {
        isUnlocked = false
        unlockedAt = nil
    }

    // MARK: - Keychain

    /// Reloads the list of saved logins (website and username only).
    func reload() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrDescription as String: Self.itemKind,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            entries = []
            return
        }
        entries = items.compactMap { item -> PasswordEntry? in
            guard let server = item[kSecAttrServer as String] as? String else { return nil }
            let account = item[kSecAttrAccount as String] as? String ?? ""
            return PasswordEntry(server: server, account: account)
        }
        .sorted { ($0.server, $0.account) < ($1.server, $1.account) }
    }

    /// Saves a new login, or updates the password if this username is already saved.
    @discardableResult
    func save(server: String, account: String, password: String) -> Bool {
        let site = Self.normalize(server)
        let match: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: site,
            kSecAttrAccount as String: account,
            kSecAttrDescription as String: Self.itemKind,
        ]
        let data = Data(password.utf8)
        var status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = match
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "\(site) (Vela)"
            item[kSecAttrProtocol as String] = kSecAttrProtocolHTTPS
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess {
            NSLog("Vela: couldn't save password (Keychain error %d)", status)
        }
        reload()
        return status == errSecSuccess
    }

    /// Reads one password from the Keychain.
    func password(for entry: PasswordEntry) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: entry.server,
            kSecAttrAccount as String: entry.account,
            kSecAttrDescription as String: Self.itemKind,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ entry: PasswordEntry) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: entry.server,
            kSecAttrAccount as String: entry.account,
            kSecAttrDescription as String: Self.itemKind,
        ]
        SecItemDelete(query as CFDictionary)
        reload()
    }

    // MARK: - Clipboard

    /// Copies a password, hides it from clipboard-history apps, and clears it
    /// after 90 seconds if you haven't copied anything else since.
    static func copyToClipboard(_ secret: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(secret, forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let changeCount = pasteboard.changeCount
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(90))
            if NSPasteboard.general.changeCount == changeCount {
                NSPasteboard.general.clearContents()
            }
        }
    }
}

/// Makes strong random passwords like "q7Rk-vW2m!xT9p_Hc4Zs".
enum PasswordGenerator {
    // Leaves out look-alikes such as l, 1, I, O and 0.
    private static let lower = Array("abcdefghijkmnopqrstuvwxyz")
    private static let upper = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    private static let digits = Array("23456789")
    private static let symbols = Array("-_!@#$%*+=?")

    static func make(length: Int = 20) -> String {
        // SystemRandomNumberGenerator uses the Mac's secure random source.
        var random = SystemRandomNumberGenerator()
        let all = lower + upper + digits + symbols
        var characters = [lower, upper, digits, symbols].compactMap { $0.randomElement(using: &random) }
        while characters.count < max(length, 8) {
            if let next = all.randomElement(using: &random) { characters.append(next) }
        }
        characters.shuffle(using: &random)
        return String(characters)
    }
}

/// The page scripts behind saving and filling passwords. They run in Vela's
/// private script world, so the page's own code can't read or fake them.
@MainActor
enum PasswordScripts {
    /// Shared helpers: find the visible password box and its username box.
    private static let helpers = """
      const visible = (el) => !!(el && (el.offsetWidth || el.offsetHeight || el.getClientRects().length));
      const passwordField = (root) => Array.from((root || document).querySelectorAll('input[type="password"]')).find(visible) || null;
      const usernameField = (pw) => {
        const scope = (pw && pw.form) || document;
        const preferred = Array.from(scope.querySelectorAll('input[autocomplete="username"], input[autocomplete="email"], input[type="email"]')).find(visible);
        if (preferred) return preferred;
        if (!pw) return null;
        const inputs = Array.from(scope.querySelectorAll('input[type="text"], input[type="tel"], input:not([type])')).filter(visible);
        let candidate = null;
        for (const input of inputs) {
          if (input.compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING) candidate = input;
        }
        return candidate;
      };
    """

    /// Notices login forms (so the key button can appear) and the login you submit.
    static func loginScript() -> WKUserScript {
        let source = """
        (() => {
          if (window.__velaLogin) return;
          window.__velaLogin = true;
          const post = (message) => {
            try { window.webkit.messageHandlers.\(ContentBlocker.clientMessageName).postMessage(message); } catch (e) {}
          };
        \(helpers)
          // A login form: a password box, or (on "email first, password
          // next" pages like Google's) a box marked as a username or email.
          const loginField = () => passwordField() || usernameField(null);
          let announced = false;
          const announce = () => {
            if (!announced && loginField()) { announced = true; post({ type: 'loginForm', hasPassword: !!passwordField() }); }
          };
          // Clicking into a login box is the cue to fill a saved login.
          const isLoginInput = (el) => !!(el && el.tagName === 'INPUT' && (
            el.type === 'password' ||
            /username|email/.test(el.autocomplete || '') || el.type === 'email' ||
            (el === usernameField(passwordField()))
          ));
          document.addEventListener('focusin', (e) => {
            if (isLoginInput(e.target)) {
              announced = true;
              post({ type: 'loginFieldFocused' });
            }
          }, true);
          let lastSent = '';
          const capture = (root) => {
            const pw = passwordField(root) || passwordField();
            if (!pw || !pw.value) return;
            const user = usernameField(pw);
            const username = user ? user.value.trim() : '';
            const key = username + '\\n' + pw.value;
            if (key === lastSent) return;
            lastSent = key;
            post({ type: 'credentials', username, password: pw.value });
          };
          document.addEventListener('submit', (e) => capture(e.target), true);
          document.addEventListener('click', (e) => {
            const button = e.target && e.target.closest ? e.target.closest('button, input[type="submit"], [role="button"]') : null;
            if (button) capture(button.form || null);
          }, true);
          document.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && e.target && e.target.type === 'password') capture(e.target.form || null);
          }, true);
          announce();
          let timer = null;
          new MutationObserver(() => {
            if (timer) return;
            timer = setTimeout(() => {
              timer = null;
              // Single-page sites swap the email box for a password box
              // without loading a new page: announce that as a new form.
              const pw = passwordField();
              if (pw && !pw.__velaSeen) { pw.__velaSeen = true; announced = false; }
              announce();
            }, 500);
          }).observe(document.documentElement, { childList: true, subtree: true });
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: .defaultClient)
    }

    /// Fills `username` and `password` into the page. Typed the way a person
    /// would, so sites built with React and similar frameworks notice.
    static let fillFunction = """
    \(helpers)
    const setValue = (el, value) => {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
      el.focus();
      setter.call(el, value);
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    };
    const pw = passwordField();
    const user = usernameField(pw);
    // Don't overwrite a username you already typed differently.
    if (user && username && (!user.value || user.value === username)) setValue(user, username);
    if (pw) setValue(pw, password);
    if (pw) pw.focus(); else if (user) user.focus();
    return pw ? 'password' : (user ? 'username' : 'none');
    """
}
