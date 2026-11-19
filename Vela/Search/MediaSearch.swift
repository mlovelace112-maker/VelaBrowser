import Foundation
import Observation

struct ImageResult: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let thumbnail: URL
    let image: URL
    let page: URL?
    let width: Int
    let height: Int
    let source: String
}

struct VideoResult: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let thumbnail: URL?
    let page: URL
    let duration: String
    let publisher: String
    let published: Date?
    let views: Int?
}

/// One image or video search, shown as a grid in a tab.
///
/// **Where results come from:** DuckDuckGo's image and video search (its
/// results come from Bing). It's the same data duckduckgo.com's own pages load,
/// fetched without cookies or tracking. First Vela asks duckduckgo.com for a
/// short-lived search token ("vqd"), then asks for results with it.
@MainActor
@Observable
final class MediaSearch {
    enum Kind: String, CaseIterable, Identifiable {
        case images = "Images"
        case videos = "Videos"
        var id: String { rawValue }
    }

    private(set) var query: String
    private(set) var kind: Kind
    private(set) var images: [ImageResult] = []
    private(set) var videos: [VideoResult] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var canLoadMore = false
    /// The image shown large in the preview.
    var preview: ImageResult?

    @ObservationIgnored private var token: String?
    @ObservationIgnored private var nextPage: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(query: String, kind: Kind) {
        self.query = query
        self.kind = kind
    }

    var title: String { "\(kind.rawValue): \(query)" }

    var isEmpty: Bool { kind == .images ? images.isEmpty : videos.isEmpty }

    /// Starts a new search (a new query, or the same one as images/videos).
    func search(_ newQuery: String? = nil, kind newKind: Kind? = nil) {
        let trimmed = (newQuery ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed != query { token = nil }
        query = trimmed
        kind = newKind ?? kind
        images = []
        videos = []
        nextPage = nil
        preview = nil
        load(more: false)
    }

    func loadMore() {
        guard canLoadMore, !isLoading else { return }
        load(more: true)
    }

    private func load(more: Bool) {
        task?.cancel()
        isLoading = true
        error = nil
        let query = query, kind = kind, page = more ? nextPage : nil
        task = Task {
            do {
                if token == nil { token = try await DuckDuckGoMedia.token(for: query) }
                guard let token else { return }
                switch kind {
                case .images:
                    let (results, next) = try await DuckDuckGoMedia.images(query, token: token, next: page)
                    guard !Task.isCancelled else { return }
                    images += results
                    nextPage = next
                case .videos:
                    let (results, next) = try await DuckDuckGoMedia.videos(query, token: token, next: page)
                    guard !Task.isCancelled else { return }
                    videos += results
                    nextPage = next
                }
                canLoadMore = nextPage != nil
            } catch {
                guard !Task.isCancelled else { return }
                // Tokens expire; try a fresh one next time.
                token = nil
                self.error = "Couldn't load \(kind.rawValue.lowercased()) from DuckDuckGo. Check your connection and try again."
                canLoadMore = false
            }
            isLoading = false
        }
    }
}

/// The DuckDuckGo image and video endpoints.
@MainActor
enum DuckDuckGoMedia {
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// A cookie-free session, so searches aren't linked together.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    static func token(for query: String) async throws -> String {
        var components = URLComponents(string: "https://duckduckgo.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "ia", value: "images")]
        let data = try await get(components.url!)
        let html = String(decoding: data, as: UTF8.self)
        // The page contains something like vqd="4-1234567890…".
        guard let range = html.range(of: #"vqd=["']?([0-9-]+)"#, options: .regularExpression) else {
            throw URLError(.cannotParseResponse)
        }
        let digits = html[range].drop(while: { !$0.isNumber }).filter { $0.isNumber || $0 == "-" }
        guard !digits.isEmpty else { throw URLError(.cannotParseResponse) }
        return String(digits)
    }

    static func images(_ query: String, token: String, next: String?) async throws -> ([ImageResult], String?) {
        let json = try await results("i.js", query: query, token: token, next: next)
        let items = (json["results"] as? [[String: Any]] ?? []).compactMap { item -> ImageResult? in
            guard let thumbnail = (item["thumbnail"] as? String).flatMap(URL.init(string:)),
                  let image = (item["image"] as? String).flatMap(URL.init(string:)) else { return nil }
            return ImageResult(
                title: item["title"] as? String ?? "",
                thumbnail: thumbnail,
                image: image,
                page: (item["url"] as? String).flatMap(URL.init(string:)),
                width: (item["width"] as? NSNumber)?.intValue ?? 0,
                height: (item["height"] as? NSNumber)?.intValue ?? 0,
                source: (item["url"] as? String).flatMap(URL.init(string:)).map(BrowserStore.siteName) ?? ""
            )
        }
        return (items, json["next"] as? String)
    }

    static func videos(_ query: String, token: String, next: String?) async throws -> ([VideoResult], String?) {
        let json = try await results("v.js", query: query, token: token, next: next)
        let dates = ISO8601DateFormatter()
        let items = (json["results"] as? [[String: Any]] ?? []).compactMap { item -> VideoResult? in
            guard let page = (item["content"] as? String).flatMap(URL.init(string:)) else { return nil }
            let images = item["images"] as? [String: Any]
            let thumbnail = (images?["large"] as? String ?? images?["medium"] as? String).flatMap(URL.init(string:))
            let statistics = item["statistics"] as? [String: Any]
            return VideoResult(
                title: item["title"] as? String ?? "",
                thumbnail: thumbnail,
                page: page,
                duration: item["duration"] as? String ?? "",
                publisher: item["publisher"] as? String ?? item["uploader"] as? String ?? "",
                published: (item["published"] as? String).flatMap { dates.date(from: $0) },
                views: (statistics?["viewCount"] as? NSNumber)?.intValue
            )
        }
        return (items, json["next"] as? String)
    }

    private static func results(_ endpoint: String, query: String, token: String, next: String?) async throws -> [String: Any] {
        var components = URLComponents(string: "https://duckduckgo.com/\(endpoint)")!
        var items = [
            URLQueryItem(name: "l", value: "us-en"),
            URLQueryItem(name: "o", value: "json"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "vqd", value: token),
            URLQueryItem(name: "f", value: ",,,,,"),
            URLQueryItem(name: "p", value: "1"), // SafeSearch: moderate
        ]
        // "next" looks like "i.js?q=…&s=100…"; carry its "s" (where to start) over.
        if let next, let start = URLComponents(string: "https://duckduckgo.com/" + next)?.queryItems?.first(where: { $0.name == "s" }) {
            items.append(start)
        }
        components.queryItems = items
        let data = try await get(components.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return json
    }

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://duckduckgo.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
