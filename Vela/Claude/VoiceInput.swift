import AVFoundation
import Speech

/// Talk to Claude: turns what you say into text, on your Mac.
///
/// Uses Apple's speech recognition with "on device" required, so your voice
/// never leaves the Mac. Only the finished text is sent to Claude, the same
/// as if you'd typed it. Listening stops on its own after a short pause.
@MainActor
@Observable
final class VoiceInput {
    /// What you've said so far.
    private(set) var transcript = ""
    private(set) var isListening = false
    private(set) var error: String?
    /// Goes up by one each time you finish speaking, so the panel knows to send.
    private(set) var finished = 0

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTimer: Task<Void, Never>?

    /// How long a pause ends what you're saying.
    private static let pause: Duration = .milliseconds(1_800)

    func toggle() {
        isListening ? stop(send: true) : start()
    }

    func start() {
        guard !isListening else { return }
        error = nil
        transcript = ""
        Task {
            guard await Self.askPermission() else {
                error = "Allow Vela to use speech recognition and the microphone in System Settings ▸ Privacy & Security."
                return
            }
            begin()
        }
    }

    /// Stops listening. With `send`, what you said goes to Claude.
    func stop(send: Bool) {
        guard isListening else { return }
        silenceTimer?.cancel()
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        engine = nil
        request = nil
        task = nil
        isListening = false
        if send, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finished += 1
        }
    }

    private func begin() {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            error = "Speech recognition isn't available for your Mac's language."
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            error = "Your Mac can't turn speech into text on its own for this language, so Vela won't send your voice anywhere."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            error = "Vela couldn't find a microphone."
            return
        }
        Self.installTap(on: input, format: format, feeding: request)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.error = "The microphone couldn't start: \(error.localizedDescription)"
            return
        }
        self.engine = engine
        self.request = request
        isListening = true
        task = Self.recognize(with: recognizer, request: request) { [weak self] text, isFinal, failed in
            Task { @MainActor in self?.heard(text, isFinal: isFinal, failed: failed) }
        }
        waitForPause()
    }

    private func heard(_ text: String?, isFinal: Bool, failed: Bool) {
        guard isListening else { return }
        if let text { transcript = text }
        if isFinal || failed {
            stop(send: !failed || !transcript.isEmpty)
        } else {
            waitForPause()
        }
    }

    /// Restarts the pause timer each time new words arrive.
    private func waitForPause() {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            // Give a little longer before the first word.
            let wait = (self?.transcript.isEmpty ?? true) ? Duration.seconds(6) : Self.pause
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.stop(send: true)
        }
    }

    // These run on audio and speech threads, so they're kept out of the main actor.

    private nonisolated static func installTap(on input: AVAudioInputNode, format: AVAudioFormat,
                                               feeding request: SFSpeechAudioBufferRecognitionRequest) {
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private nonisolated static func recognize(
        with recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        update: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            update(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    private nonisolated static func askPermission() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}

extension BrowserStore {
    /// ⌥⌘A: opens Claude and starts (or stops) listening.
    func talkToClaude() {
        guard claude.hasKey else {
            isClaudePanelVisible = true
            return
        }
        isClaudePanelVisible = true
        voice.toggle()
    }
}
