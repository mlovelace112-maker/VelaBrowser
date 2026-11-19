import AppKit
import NaturalLanguage
import PDFKit
import SwiftUI
import Translation
import UniformTypeIdentifiers
import WebKit

// MARK: - Translate

/// Where a tab's translation is at.
enum TranslationStatus: Equatable {
    case none
    case translating
    case translated
    case failed(String)
}

extension BrowserTab {
    /// Finds out what language the page is in. Sets `pageLanguage` only when
    /// it's different from yours and your Mac can translate it, which is what
    /// makes the Translate button appear.
    func detectLanguage() async {
        pageLanguage = nil
        translation = .none
        let body = """
        const text = (document.body ? document.body.innerText : '').slice(0, 1500);
        return [document.documentElement.lang || '', (document.title || '') + ' ' + text];
        """
        guard let result = try? await runScript(body, arguments: [:]) as? [String], result.count == 2 else { return }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(result[1])
        var code = recognizer.dominantLanguage?.rawValue
        if let code0 = code, (recognizer.languageHypotheses(withMaximum: 1)[NLLanguage(code0)] ?? 0) < 0.6 {
            code = nil
        }
        if code == nil, !result[0].isEmpty { code = result[0] }
        guard let code else { return }
        let page = Locale.Language(identifier: code)
        let mine = Locale.current.language
        guard page.languageCode != nil, page.languageCode != mine.languageCode else { return }
        let status = await LanguageAvailability().status(from: page, to: mine)
        if status != .unsupported { pageLanguage = code }
    }

    /// The page's words, one entry per piece of text, remembered so the
    /// translations can go back in the same places.
    func collectTextForTranslation() async -> [String] {
        let body = """
        const skip = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'CODE', 'PRE', 'TEXTAREA', 'SVG', 'MATH', 'KBD', 'SAMP']);
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
          acceptNode(node) {
            const text = node.nodeValue.trim();
            if (text.length < 2 || !/[^\\d\\s\\p{P}]/u.test(text)) return NodeFilter.FILTER_REJECT;
            for (let el = node.parentElement; el; el = el.parentElement) {
              if (skip.has(el.tagName) || el.isContentEditable || el.getAttribute('translate') === 'no') return NodeFilter.FILTER_REJECT;
            }
            return NodeFilter.FILTER_ACCEPT;
          }
        });
        const nodes = [];
        while (walker.nextNode() && nodes.length < 4000) nodes.push(walker.currentNode);
        window.__velaNodes = nodes;
        window.__velaOriginal = window.__velaOriginal || new Map();
        for (const node of nodes) if (!window.__velaOriginal.has(node)) window.__velaOriginal.set(node, node.nodeValue);
        return nodes.map((node) => node.nodeValue.trim());
        """
        return (try? await runScript(body, arguments: [:]) as? [String]) ?? []
    }

    /// Puts translated text into the page: pairs of [index, text].
    func applyTranslations(_ items: [[Any]]) async {
        let body = """
        for (const [index, text] of items) {
          const node = window.__velaNodes && window.__velaNodes[index];
          if (!node) continue;
          const value = node.nodeValue;
          node.nodeValue = value.match(/^\\s*/)[0] + text + value.match(/\\s*$/)[0];
        }
        """
        _ = try? await runScript(body, arguments: ["items": items])
    }

    /// "Show Original": puts every piece of text back.
    func showOriginalText() async {
        let body = """
        if (window.__velaOriginal) for (const [node, value] of window.__velaOriginal) node.nodeValue = value;
        """
        _ = try? await runScript(body, arguments: [:])
        translation = .none
    }

    /// The page's language as a name: "French".
    var pageLanguageName: String {
        guard let pageLanguage else { return "" }
        return Locale.current.localizedString(forLanguageCode: pageLanguage) ?? pageLanguage
    }
}

/// An invisible helper on the page that runs Apple's on-device translation.
/// (Apple only hands out a translator through a SwiftUI modifier, so it
/// lives in a view.) Nothing you read is sent anywhere.
struct TranslationHost: View {
    let tab: BrowserTab
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(configuration) { session in
                await MainActor.run { tab.translation = .translating }
                let texts = await tab.collectTextForTranslation()
                do {
                    // In batches, so the top of the page changes first.
                    for start in stride(from: 0, to: texts.count, by: 150) {
                        let end = min(start + 150, texts.count)
                        let requests = (start..<end).map {
                            TranslationSession.Request(sourceText: texts[$0], clientIdentifier: String($0))
                        }
                        let responses = try await session.translations(from: requests)
                        let items: [[Any]] = responses.compactMap { response in
                            guard let id = response.clientIdentifier, let index = Int(id) else { return nil }
                            return [index, response.targetText]
                        }
                        await tab.applyTranslations(items)
                    }
                    await MainActor.run { tab.translation = .translated }
                } catch {
                    let message = "Translation didn't work: \(error.localizedDescription)"
                    await MainActor.run { tab.translation = .failed(message) }
                }
            }
            .onChange(of: tab.translateRequests) {
                guard let code = tab.pageLanguage else { return }
                let source = Locale.Language(identifier: code)
                if configuration?.source == source {
                    configuration?.invalidate()
                } else {
                    configuration = TranslationSession.Configuration(source: source, target: Locale.current.language)
                }
            }
    }
}

/// The Translate button in the address bar (only on pages in another language).
struct TranslateButton: View {
    let tab: BrowserTab

    var body: some View {
        Button {
            if tab.translation == .translated {
                Task { await tab.showOriginalText() }
            } else {
                tab.translateRequests += 1
            }
        } label: {
            Group {
                if tab.translation == .translating {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "translate")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tab.translation == .translated ? Nightglass.accent : Nightglass.mutedText)
                }
            }
            .frame(width: 16)
        }
        .buttonStyle(.plain)
        .disabled(tab.translation == .translating)
        .help(tab.translation == .translated
              ? "Show Original (\(tab.pageLanguageName))"
              : "Translate from \(tab.pageLanguageName) (on your Mac, nothing is sent)")
    }
}

// MARK: - Screenshots

extension BrowserStore {
    enum ScreenshotKind { case fullPageImage, fullPagePDF, visibleArea }

    /// Saves a picture of the page to Downloads.
    /// The full page includes everything you'd have to scroll to see.
    func takeScreenshot(_ kind: ScreenshotKind, of tab: BrowserTab? = nil) async {
        guard let tab = tab ?? selectedTab, tab.url != nil else { return }
        let webView = tab.webView
        let name = Self.screenshotName(for: tab)
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]

        do {
            switch kind {
            case .visibleArea:
                let image = try await webView.takeSnapshot(configuration: nil)
                guard let png = image.pngData else { throw ScreenshotError() }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                let url = Self.unique(folder.appendingPathComponent(name + ".png"))
                try png.write(to: url)
                showNotice("Screenshot copied and saved to Downloads.")
            case .fullPagePDF:
                // With no rect, WebKit draws the whole page as one tall PDF page.
                let data = try await webView.pdf(configuration: WKPDFConfiguration())
                let url = Self.unique(folder.appendingPathComponent(name + ".pdf"))
                try data.write(to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
                showNotice("Full-page PDF saved to Downloads.")
            case .fullPageImage:
                let data = try await webView.pdf(configuration: WKPDFConfiguration())
                guard let png = Self.pngFromPDF(data) else { throw ScreenshotError() }
                let url = Self.unique(folder.appendingPathComponent(name + ".png"))
                try png.write(to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
                showNotice("Full-page screenshot saved to Downloads.")
            }
        } catch {
            showNotice("Couldn't take a screenshot of this page.")
        }
    }

    /// "Screenshot – Apple – 2026-11-19 at 15.04.22"
    private static func screenshotName(for tab: BrowserTab) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let title = tab.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "Screenshot – \(title.prefix(60)) – \(formatter.string(from: Date()))"
    }

    private static func unique(_ url: URL) -> URL {
        let base = url.deletingPathExtension().path
        var candidate = url
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = URL(fileURLWithPath: "\(base) \(number).\(url.pathExtension)")
            number += 1
        }
        return candidate
    }

    /// Turns the one-page PDF into a sharp PNG (2× for Retina, capped so a
    /// very long page doesn't make a gigantic file).
    private static func pngFromPDF(_ data: Data) -> Data? {
        guard let document = PDFDocument(data: data), let page = document.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale = min(2, 32_000 / max(bounds.height, 1))
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.setFillColor(NSColor.white.cgColor)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.cgContext.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    private struct ScreenshotError: Error {}
}

private extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

// MARK: - Reading List

/// A page saved to read later (⇧⌘D, like Safari).
struct ReadingItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var url: URL
    var title: String
    var added = Date()
    var isRead = false
}

extension BrowserStore {
    static let readingListKey = "vela.readingList"

    static func loadReadingList() -> [ReadingItem] {
        guard let data = UserDefaults.standard.data(forKey: readingListKey),
              let items = try? JSONDecoder().decode([ReadingItem].self, from: data) else { return [] }
        return items
    }

    private func saveReadingList() {
        if let data = try? JSONEncoder().encode(readingList) {
            UserDefaults.standard.set(data, forKey: Self.readingListKey)
        }
    }

    func isInReadingList(_ url: URL?) -> Bool {
        guard let url else { return false }
        return readingList.contains { $0.url == url }
    }

    func addToReadingList(_ tab: BrowserTab? = nil) {
        guard let tab = tab ?? selectedTab, let url = tab.url, !tab.isPrivate else { return }
        guard !isInReadingList(url) else {
            showNotice("Already in your Reading List.")
            return
        }
        readingList.insert(ReadingItem(url: url, title: tab.title), at: 0)
        saveReadingList()
        showNotice("Added to Reading List.")
    }

    func openReadingItem(_ item: ReadingItem) {
        setRead(item, true)
        open(item.url)
    }

    func setRead(_ item: ReadingItem, _ isRead: Bool) {
        guard let index = readingList.firstIndex(where: { $0.id == item.id }) else { return }
        readingList[index].isRead = isRead
        saveReadingList()
    }

    func removeFromReadingList(_ item: ReadingItem) {
        readingList.removeAll { $0.id == item.id }
        saveReadingList()
    }

    func clearReadItems() {
        readingList.removeAll(where: \.isRead)
        saveReadingList()
    }
}

/// Sidebar ▸ Read Later.
struct ReadingListSection: View {
    @Environment(BrowserStore.self) private var store
    let search: String
    @State private var showRead = false

    var body: some View {
        let matching = store.readingList.filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                || $0.url.absoluteString.localizedCaseInsensitiveContains(search)
        }
        let items = matching.filter { showRead || !$0.isRead }
        let readCount = store.readingList.filter(\.isRead).count

        Picker("Show", selection: $showRead) {
            Text("Unread").tag(false)
            Text("All").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.bottom, 4)

        if items.isEmpty {
            Text(store.readingList.isEmpty
                 ? "Nothing saved yet. Press ⇧⌘D (or ••• ▸ Add to Reading List) on a page to read it later."
                 : search.isEmpty ? "All caught up." : "No matches.")
                .font(.system(size: 12))
                .foregroundStyle(Nightglass.mutedText)
                .padding(8)
        }
        ForEach(items) { item in
            ReadingRow(item: item)
        }
        if readCount > 0 && showRead {
            Button("Remove \(readCount) Read") { store.clearReadItems() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Nightglass.claude)
                .padding(8)
        }
    }
}

private struct ReadingRow: View {
    @Environment(BrowserStore.self) private var store
    let item: ReadingItem
    @State private var isHovering = false

    var body: some View {
        Button { store.openReadingItem(item) } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(item.isRead ? Color.clear : Nightglass.accent)
                    .frame(width: 7, height: 7)
                FaviconView(url: item.url, size: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: item.isRead ? .regular : .medium))
                        .foregroundStyle(item.isRead ? Nightglass.mutedText : Nightglass.text)
                        .lineLimit(2)
                    Text("\(BrowserStore.siteName(item.url)) · \(item.added.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 11))
                        .foregroundStyle(Nightglass.mutedText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(isHovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.url.absoluteString)
        .contextMenu {
            Button(item.isRead ? "Mark as Unread" : "Mark as Read") { store.setRead(item, !item.isRead) }
            Button("Open in New Tab") {
                store.setRead(item, true)
                store.open(item.url, inNewTab: true)
            }
            Button("Remove", role: .destructive) { store.removeFromReadingList(item) }
        }
    }
}
