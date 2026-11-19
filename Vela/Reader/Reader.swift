import Foundation
import Observation
import WebKit

/// A page's article, cleaned up for reading.
struct ReaderArticle: Equatable {
    let title: String
    let byline: String
    let siteName: String
    let html: String
    let minutes: Int
    let url: URL
}

enum ReaderFont: String, CaseIterable, Identifiable, Codable {
    case serif, sans, rounded

    var id: String { rawValue }
    var name: String {
        switch self {
        case .serif: "New York"
        case .sans: "San Francisco"
        case .rounded: "SF Rounded"
        }
    }
    var css: String {
        switch self {
        case .serif: "ui-serif, 'New York', Georgia, serif"
        case .sans: "-apple-system, 'SF Pro Text', sans-serif"
        case .rounded: "ui-rounded, 'SF Pro Rounded', -apple-system, sans-serif"
        }
    }
}

enum ReaderPage: String, CaseIterable, Identifiable, Codable {
    case night, sepia, paper

    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

/// Your reader choices, remembered between launches.
@MainActor
@Observable
final class ReaderSettings {
    static let shared = ReaderSettings()

    var fontSize: Double { didSet { save() } }
    var font: ReaderFont { didSet { save() } }
    var page: ReaderPage { didSet { save() } }

    private init() {
        let defaults = UserDefaults.standard
        fontSize = defaults.object(forKey: "vela.readerFontSize") as? Double ?? 19
        font = defaults.string(forKey: "vela.readerFont").flatMap(ReaderFont.init(rawValue:)) ?? .serif
        page = defaults.string(forKey: "vela.readerPage").flatMap(ReaderPage.init(rawValue:)) ?? .night
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(fontSize, forKey: "vela.readerFontSize")
        defaults.set(font.rawValue, forKey: "vela.readerFont")
        defaults.set(page.rawValue, forKey: "vela.readerPage")
    }
}

/// Reader mode: pulls the article out of a cluttered page and shows it as
/// clean text.
///
/// **How it works:** Vela runs Mozilla's Readability (the same code as
/// Firefox's Reader View) inside the page, in Vela's private script world. It
/// scores parts of the page to find the main article and returns just that.
/// Vela then shows it in its own little page with scripts turned off.
@MainActor
enum Reader {
    enum Failure: Error { case notAnArticle, failed }

    static func extract(from tab: BrowserTab) async throws -> ReaderArticle {
        guard let url = tab.url else { throw Failure.notAnArticle }
        let body = ReadabilityScript.source + """

        const article = new Readability(document.cloneNode(true), { charThreshold: 400 }).parse();
        if (!article || !article.content) { return null; }
        return {
          title: article.title || document.title || '',
          byline: article.byline || '',
          siteName: article.siteName || '',
          content: article.content,
          length: article.length || 0
        };
        """
        let result: Any? = try await withCheckedThrowingContinuation { continuation in
            tab.webView.callAsyncJavaScript(body, arguments: [:], in: nil, in: .defaultClient) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        guard let json = result as? [String: Any], let content = json["content"] as? String else {
            throw Failure.notAnArticle
        }
        let length = (json["length"] as? NSNumber)?.intValue ?? 0
        return ReaderArticle(
            title: json["title"] as? String ?? tab.title,
            byline: json["byline"] as? String ?? "",
            siteName: (json["siteName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? BrowserStore.siteName(url),
            html: content,
            minutes: max(1, length / 1150),
            url: url
        )
    }

    /// The finished reader page, styled with your settings.
    static func page(for article: ReaderArticle, settings: ReaderSettings, accent: String) -> String {
        let colors: (background: String, text: String, muted: String, rule: String) = switch settings.page {
        case .night: ("#0E0F16", "#E6E7EE", "#9BA0AE", "rgba(255,255,255,.1)")
        case .sepia: ("#F4ECD8", "#3B2F23", "#7A6A57", "rgba(59,47,35,.15)")
        case .paper: ("#FBFBFA", "#1D1D1F", "#6E6E73", "rgba(0,0,0,.1)")
        }
        let meta = [article.byline, "\(article.minutes) min read"].filter { !$0.isEmpty }.joined(separator: " · ")
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>
          :root { color-scheme: \(settings.page == .night ? "dark" : "light"); }
          html { background: \(colors.background); }
          body {
            margin: 0; color: \(colors.text); background: \(colors.background);
            font: \(Int(settings.fontSize))px/1.65 \(settings.font.css);
            -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility;
          }
          article { max-width: 700px; margin: 0 auto; padding: 64px 36px 140px; }
          .site { color: \(accent); font: 600 13px -apple-system, sans-serif; letter-spacing: .06em; text-transform: uppercase; }
          h1 { font-size: 2.05em; line-height: 1.18; margin: .35em 0 .4em; letter-spacing: -.01em; }
          .meta { color: \(colors.muted); font: 14px -apple-system, sans-serif; padding-bottom: 28px; margin-bottom: 32px; border-bottom: 1px solid \(colors.rule); }
          h2, h3, h4 { line-height: 1.3; margin-top: 1.8em; }
          p, li { hyphens: auto; }
          a { color: \(accent); text-decoration: none; border-bottom: 1px solid \(accent)55; }
          img, video, svg, figure, iframe { max-width: 100%; height: auto; border-radius: 12px; }
          figure { margin: 1.6em 0; }
          figcaption { color: \(colors.muted); font: 13px/1.5 -apple-system, sans-serif; margin-top: 8px; }
          blockquote { margin: 1.4em 0; padding-left: 18px; border-left: 3px solid \(accent); color: \(colors.muted); }
          pre, code { font: .85em ui-monospace, Menlo, monospace; }
          pre { overflow-x: auto; padding: 14px 16px; border-radius: 10px; background: \(colors.rule); }
          table { border-collapse: collapse; width: 100%; font-size: .9em; }
          td, th { border-bottom: 1px solid \(colors.rule); padding: 6px 8px; text-align: left; }
          hr { border: 0; border-top: 1px solid \(colors.rule); margin: 2em 0; }
        </style></head>
        <body><article>
          <div class="site">\(escape(article.siteName))</div>
          <h1>\(escape(article.title))</h1>
          <div class="meta">\(escape(meta))</div>
          \(article.html)
        </article></body></html>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
