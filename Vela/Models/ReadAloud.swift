import AVFoundation
import Foundation

/// Read Aloud: your Mac's own voices read the page to you. Nothing is sent
/// anywhere; the speech is made on your Mac.
@MainActor
@Observable
final class ReadAloud: NSObject {
    enum State { case idle, speaking, paused }

    private(set) var state: State = .idle
    private(set) var title = ""
    /// How far through the page, from 0 to 1.
    private(set) var progress: Double = 0
    var rate: Float = UserDefaults.standard.object(forKey: "vela.readAloudRate") as? Float ?? 1.0 {
        didSet { UserDefaults.standard.set(rate, forKey: "vela.readAloudRate") }
    }

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var text = ""
    /// Where the current spoken piece starts in `text`, for restarting at a new speed.
    @ObservationIgnored private var spokenOffset = 0
    @ObservationIgnored private var position = 0

    static let rates: [Float] = [0.75, 1, 1.25, 1.5, 2]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func read(_ text: String, title: String) {
        stop()
        self.text = text
        self.title = title
        start(at: 0)
    }

    private func start(at offset: Int) {
        guard offset < text.count else { return stop() }
        spokenOffset = offset
        let piece = String(text.dropFirst(offset))
        let utterance = AVSpeechUtterance(string: piece)
        // 1× is a comfortable reading speed; the slider scales it.
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                             AVSpeechUtteranceDefaultSpeechRate * (0.85 + (rate - 1) * 0.5))
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
        synthesizer.speak(utterance)
        state = .speaking
    }

    func togglePause() {
        switch state {
        case .speaking:
            synthesizer.pauseSpeaking(at: .word)
            state = .paused
        case .paused:
            synthesizer.continueSpeaking()
            state = .speaking
        case .idle:
            break
        }
    }

    /// A new speed takes effect from the current word.
    func setRate(_ newRate: Float) {
        rate = newRate
        guard state != .idle else { return }
        let resumeAt = position
        synthesizer.stopSpeaking(at: .immediate)
        start(at: resumeAt)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        state = .idle
        progress = 0
        position = 0
    }

    fileprivate func spoke(upTo location: Int) {
        position = spokenOffset + location
        progress = text.isEmpty ? 0 : Double(position) / Double(text.count)
    }

    fileprivate func finished(_ utterance: AVSpeechUtterance) {
        // Ignore pieces stopped on purpose (a speed change starts a new one).
        guard utterance.speechString.count + spokenOffset >= text.count - 1 else { return }
        state = .idle
        progress = 1
    }
}

extension ReadAloud: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let location = characterRange.location
        Task { @MainActor in self.spoke(upTo: location) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished(utterance) }
    }
}

extension BrowserStore {
    /// View ▸ Read Aloud: reads the main text of the page.
    func readAloud() {
        guard let tab = selectedTab, tab.url != nil else {
            showNotice("Open a page to read aloud")
            return
        }
        if readAloudPlayer.state != .idle {
            readAloudPlayer.stop()
            return
        }
        Task {
            // The article itself if the page marks one, else the whole page.
            let script = """
            const main = document.querySelector('article') || document.querySelector('main') || document.body;
            return main ? main.innerText.replace(/\\n{2,}/g, '\\n').slice(0, 100000) : '';
            """
            let text = (try? await tab.runScript(script, arguments: [:]) as? String) ?? ""
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 else {
                showNotice("This page has no text to read")
                return
            }
            readAloudPlayer.read(text, title: tab.title)
        }
    }
}
