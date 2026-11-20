import Foundation

// Claude tools that look at whole pages: compare tabs, summarize a YouTube
// video, and "Is this site legit?". Each one shows its answer in a sheet
// (PageToolsViews.swift).
//
// **Privacy:** like everywhere else in Vela, pages with a password box are
// never sent to Claude, and private tabs are left out of comparisons.

/// What the Claude tools sheet is showing.
struct PageToolState: Identifiable {
    enum Kind { case compare, video, siteCheck }

    let id = UUID()
    let kind: Kind
    var isWorking = false
    var error: String?
    var comparison: TabComparison?
    var video: VideoSummary?
    var siteCheck: SiteCheck?
    /// The tab a video summary or site check is about.
    var tabID: UUID?

    var title: String {
        switch kind {
        case .compare: "Compare Tabs"
        case .video: "Video Summary"
        case .siteCheck: "Is This Site Legit?"
        }
    }
}

/// Claude's side-by-side table of several tabs.
struct TabComparison: Decodable {
    struct Row: Decodable, Identifiable {
        var id: String { name }
        var name: String
        var values: [String]
    }
    var summary: String
    var rows: [Row]
    /// Filled in by Vela: the page titles, in the same order as each row's values.
    var columns: [String] = []

    private enum CodingKeys: String, CodingKey { case summary, rows }
}

/// A YouTube video's summary, with moments you can jump to.
struct VideoSummary: Decodable {
    struct Moment: Decodable, Identifiable {
        var id: Int { seconds }
        var seconds: Int
        var text: String

        var time: String {
            let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
            return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        }
    }
    var summary: String
    var moments: [Moment]
    /// Filled in by Vela: false when the video had no captions, so only the description was used.
    var fromTranscript = true

    private enum CodingKeys: String, CodingKey { case summary, moments }
}

/// Claude's verdict on whether a site can be trusted.
struct SiteCheck: Decodable {
    enum Verdict: String, Decodable { case safe, caution, danger }
    var verdict: Verdict
    var headline: String
    var reasons: [String]
    /// Filled in by Vela: what it checked on your Mac before asking Claude.
    var signals: [String] = []

    private enum CodingKeys: String, CodingKey { case verdict, headline, reasons }
}

enum PageToolError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}

extension BrowserStore {
    // MARK: Shared

    /// Asks Claude for a JSON reply and decodes it.
    static func askClaudeForJSON<T: Decodable>(_ type: T.Type, model: ClaudeModel = .haiku, system: String,
                                               prompt: String, maxTokens: Int = 4_000) async throws -> T {
        let request = ClaudeRequest(
            model: model,
            system: system + " Reply with JSON only, no other text.",
            messages: [["role": "user", "content": prompt]],
            maxTokens: maxTokens,
            effort: "low"
        )
        let response = try await ClaudeClient.stream(request) { _ in }
        if response.stopReason == "refusal" { throw PageToolError.message("Claude declined to answer this one.") }
        let text = response.text
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let value = try? JSONDecoder().decode(T.self, from: Data(text[start...end].utf8)) else {
            throw PageToolError.message("Claude's answer didn't come back in the expected shape. Try again.")
        }
        return value
    }

    /// The words on a tab's page, or nil when it has a password box (or no page).
    func readablePageText(of tab: BrowserTab, limit: Int) async -> String? {
        if tab.isAsleep {
            tab.wake()
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(250))
                if !tab.isLoading && !tab.isAsleep { break }
            }
        }
        let script = """
        if (document.querySelector('input[type=password]')) return null;
        return (document.body ? document.body.innerText : '').replace(/\\s+/g, ' ').slice(0, limit);
        """
        return try? await tab.runScript(script, arguments: ["limit": limit]) as? String
    }

    private func startTool(_ kind: PageToolState.Kind, tab: BrowserTab? = nil) -> UUID? {
        var state = PageToolState(kind: kind)
        state.tabID = tab?.id
        guard claude.hasKey else {
            state.error = ClaudeError.noKey.localizedDescription
            pageTool = state
            return nil
        }
        state.isWorking = kind != .compare
        pageTool = state
        return state.id
    }

    private func finishTool(_ id: UUID, _ update: (inout PageToolState) -> Void) {
        guard var state = pageTool, state.id == id else { return }
        update(&state)
        state.isWorking = false
        pageTool = state
    }

    // MARK: Compare tabs

    /// Tabs that can be compared: open web pages, not private.
    var comparableTabs: [BrowserTab] {
        tabs.filter { !$0.isPrivate && $0.url != nil && ["http", "https"].contains($0.url?.scheme ?? "") }
    }

    /// Opens the Compare Tabs sheet, where you pick the tabs.
    func showCompareTabs() {
        _ = startTool(.compare)
    }

    func compare(_ picked: [BrowserTab]) {
        guard let id = pageTool?.id, pageTool?.kind == .compare, picked.count >= 2 else { return }
        pageTool?.isWorking = true
        pageTool?.error = nil
        Task {
            var pages: [(title: String, url: URL, text: String)] = []
            var skipped: [String] = []
            for tab in picked {
                guard let url = tab.url else { continue }
                if let text = await readablePageText(of: tab, limit: 9_000), text.count > 40 {
                    pages.append((tab.title, url, text))
                } else {
                    skipped.append(tab.title)
                }
            }
            guard pages.count >= 2 else {
                finishTool(id) { $0.error = "Vela needs at least two tabs it can read. Pages with a password box are kept private from Claude." }
                return
            }
            let listing = pages.enumerated().map { index, page in
                "<page number=\"\(index + 1)\" title=\"\(page.title)\" address=\"\(page.url.absoluteString)\">\n\(page.text)\n</page>"
            }.joined(separator: "\n\n")
            let system = """
            You compare web pages someone has open in their browser (products, articles, recipes, plans, \
            places, anything). Pick the 4 to 9 attributes that matter most for deciding between them \
            (price, key specs, pros, cons, ratings, and so on). Keep each cell under 12 words, and write \
            "Not listed" when a page doesn't say. Return: {"summary": "two or three sentences on how they \
            differ and which suits whom", "rows": [{"name": "attribute", "values": ["page 1 value", \
            "page 2 value", ...]}]}. Every values list has exactly \(pages.count) entries, in page order.
            """
            do {
                var result = try await Self.askClaudeForJSON(TabComparison.self, model: .sonnet, system: system,
                                                             prompt: listing, maxTokens: 3_000)
                result.columns = pages.map { $0.title.isEmpty ? (BrowserStore.siteName($0.url)) : $0.title }
                result.rows = result.rows.map { row in
                    var row = row
                    row.values = Array((row.values + Array(repeating: "", count: pages.count)).prefix(pages.count))
                    return row
                }
                if !skipped.isEmpty {
                    result.summary += "\n\nLeft out (password box on the page): " + skipped.joined(separator: ", ")
                }
                finishTool(id) { $0.comparison = result }
            } catch {
                finishTool(id) { $0.error = error.localizedDescription }
            }
        }
    }

    // MARK: YouTube summaries

    static func isYouTubeVideo(_ url: URL?) -> Bool {
        guard let url, let host = url.host()?.lowercased() else { return false }
        return (host == "youtube.com" || host.hasSuffix(".youtube.com")) && url.path() == "/watch"
    }

    /// Reads the video's captions (or its description) and asks Claude for a summary.
    func summarizeVideo(in tab: BrowserTab) {
        guard Self.isYouTubeVideo(tab.url) else {
            showNotice("Open a YouTube video first")
            return
        }
        guard let id = startTool(.video, tab: tab) else { return }
        Task {
            guard let page = try? await tab.runScript(Self.youTubeScript, arguments: [:]) as? [String: Any] else {
                finishTool(id) { $0.error = "Vela couldn't read this video's details. Let the page finish loading and try again." }
                return
            }
            let title = page["title"] as? String ?? tab.title
            let transcript = page["transcript"] as? String ?? ""
            let description = page["description"] as? String ?? ""
            let hasTranscript = transcript.count > 200
            guard hasTranscript || description.count > 80 else {
                finishTool(id) { $0.error = "This video has no captions or description to summarize." }
                return
            }
            let source = hasTranscript
                ? "Transcript (each line starts with its time in seconds):\n\(transcript)"
                : "This video has no captions. Description:\n\(description)"
            let system = """
            You summarize YouTube videos from their transcript. Return: {"summary": "3 to 5 sentences on what \
            the video says, including its main conclusion", "moments": [{"seconds": 75, "text": "what happens \
            there, under 15 words"}]}. Give 4 to 10 key moments in time order, using times from the transcript. \
            If you only have a description, give moments only for timestamps the description lists, else none.
            """
            do {
                var result = try await Self.askClaudeForJSON(VideoSummary.self, system: system,
                                                             prompt: "Video: \(title)\n\n\(source)", maxTokens: 2_000)
                result.fromTranscript = hasTranscript
                finishTool(id) { $0.video = result }
            } catch {
                finishTool(id) { $0.error = error.localizedDescription }
            }
        }
    }

    /// Jumps the video to a moment from the summary.
    func seekVideo(to seconds: Int) {
        guard let tabID = pageTool?.tabID, let tab = tabs.first(where: { $0.id == tabID }) else { return }
        select(tab)
        Task {
            _ = try? await tab.runScript("""
            const v = document.querySelector('video');
            if (v) { v.currentTime = seconds; v.play(); }
            """, arguments: ["seconds": seconds])
        }
    }

    /// Gets the title, description and captions of the YouTube video on the page.
    private static let youTubeScript = """
    const id = new URL(location.href).searchParams.get('v');
    if (!id) return null;
    const html = await (await fetch('/watch?v=' + encodeURIComponent(id), { credentials: 'include' })).text();
    // Finds the JSON array that follows a key, minding brackets inside strings.
    function arrayAfter(s, key) {
      const i = s.indexOf(key); if (i < 0) return null;
      const start = s.indexOf('[', i); let depth = 0, inString = false, escaped = false;
      for (let j = start; j < s.length; j++) {
        const c = s[j];
        if (inString) { if (escaped) escaped = false; else if (c === '\\\\') escaped = true; else if (c === '"') inString = false; continue; }
        if (c === '"') inString = true;
        else if (c === '[') depth++;
        else if (c === ']') { depth--; if (depth === 0) return s.slice(start, j + 1); }
      }
      return null;
    }
    let description = '';
    const d = html.match(/"shortDescription":"((?:[^"\\\\]|\\\\.)*)"/);
    if (d) { try { description = JSON.parse('"' + d[1] + '"'); } catch (e) {} }
    const lines = [];
    try {
      const tracks = JSON.parse(arrayAfter(html, '"captionTracks":') || '[]');
      const english = (t) => (t.languageCode || '').startsWith('en');
      const track = tracks.find(t => english(t) && t.kind !== 'asr') || tracks.find(english) || tracks[0];
      if (track) {
        const data = await (await fetch(track.baseUrl + '&fmt=json3')).json();
        for (const ev of (data.events || [])) {
          if (!ev.segs) continue;
          const text = ev.segs.map(s => s.utf8 || '').join('').replace(/\\s+/g, ' ').trim();
          if (text) lines.push('[' + Math.floor((ev.tStartMs || 0) / 1000) + '] ' + text);
        }
      }
    } catch (e) {}
    return {
      title: document.title.replace(/ - YouTube$/, ''),
      description: description.slice(0, 4000),
      transcript: lines.join('\\n').slice(0, 60000),
    };
    """

    // MARK: Is this site legit?

    /// Checks the site in this tab: Vela's own checks first, then Claude weighs them.
    func checkSite(in tab: BrowserTab) {
        guard let url = tab.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            showNotice("Open a website first")
            return
        }
        guard let id = startTool(.siteCheck, tab: tab) else { return }
        Task {
            var signals: [String] = []
            let report = LinkChecker.check(url)
            signals += report.reasons.isEmpty ? ["The address looks ordinary (no look-alike letters or brand tricks)"] : report.reasons
            if safeBrowsing.hasKey {
                if let threat = await safeBrowsing.check(url) {
                    signals.append(threat.reason)
                } else {
                    signals.append("Not on Google Safe Browsing's list of dangerous sites")
                }
            }
            if url.scheme == "https" && tab.webView.hasOnlySecureContent {
                if let certificate = CertificateSummary(trust: tab.webView.serverTrust) {
                    signals.append("Secure connection; certificate for \(certificate.subject), issued by \(certificate.issuer)")
                } else {
                    signals.append("Secure connection")
                }
            } else {
                signals.append("Not a fully secure connection (no https, or some parts load insecurely)")
            }
            let facts = try? await tab.runScript("""
            return {
              password: !!document.querySelector('input[type=password]'),
              card: !!document.querySelector('input[autocomplete^="cc-"], input[name*="card" i], input[id*="card" i]'),
            };
            """, arguments: [:]) as? [String: Any]
            let hasPassword = facts?["password"] as? Bool ?? true
            if facts?["card"] as? Bool == true { signals.append("The page asks for card details") }

            var prompt = "Site: \(url.absoluteString)\nTitle: \(tab.title)\n\nVela's checks:\n"
                + signals.map { "- \($0)" }.joined(separator: "\n")
            if hasPassword {
                signals.append("The page has a password box, so Claude only saw the address, not the page")
                prompt += "\n\n(The page has a password box, so its text is private. Judge from the address and checks.)"
            } else if let text = await readablePageText(of: tab, limit: 3_000) {
                prompt += "\n\nStart of the page's text:\n\(text)"
            }
            let system = """
            You help someone decide whether a website is trustworthy, like a careful friend who knows \
            online scams. Weigh the browser's checks and the page: look for fake shops (prices too good to \
            be true, no contact details), phishing (copying a known brand on another address), fake \
            prizes, urgency and pressure, tech-support scams, and requests for payment by gift card or \
            crypto. Well-known, established sites are "safe". You can't see how old the domain is, so \
            don't claim to. Return: {"verdict": "safe" | "caution" | "danger", "headline": "one short \
            sentence", "reasons": ["2 to 5 short reasons, plain language"]}.
            """
            do {
                var result = try await Self.askClaudeForJSON(SiteCheck.self, system: system, prompt: prompt, maxTokens: 1_000)
                // Google's list outranks anything else.
                if signals.contains(where: { $0.hasPrefix("Google Safe Browsing lists") }) { result.verdict = .danger }
                result.signals = signals
                finishTool(id) { $0.siteCheck = result }
            } catch {
                finishTool(id) { $0.error = error.localizedDescription }
            }
        }
    }
}
