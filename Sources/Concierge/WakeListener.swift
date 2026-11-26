import AVFoundation
import OSLog
import Speech

private let log = Logger(subsystem: "local.jeffdekerj.concierge", category: "wake")

/// Listens for "Concierge" while the app runs (in front or not) and no conversation is
/// going on, then starts one. Runs only with on-device recognition, so the
/// always-open microphone never streams audio off the Mac. Paused while
/// switched off in Settings or while Concierge is silenced.
///
/// It hears through the conversation's own audio engine and holds it open
/// for as long as the wake word is on, also during a conversation: the
/// microphone is opened once, not handed back and forth.
@MainActor
final class WakeListener {
    private let conversation: Conversation
    private let io: VoiceIO
    /// Whether this listener keeps the audio engine running.
    private var holding = false
    private var nextTry = Date.distantPast
    private var recogniser: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var requestStarted = Date()
    private var listening = false
    private var generation = 0
    /// Set when the wake word was heard: what followed it so far, and when it last changed.
    private var pending: (words: String, changed: Date)?

    init(conversation: Conversation, io: VoiceIO) {
        self.conversation = conversation
        self.io = io
    }

    /// Watches the settings and the conversation, and keeps the listener
    /// on exactly when it should be.
    func run() {
        Task {
            guard await authorised() else { return }
            while true {
                let s = ConciergeSettings.load()
                let on = s.wakeWord && !s.isSilenced()
                keepEngine(on)
                let wanted = on && holding && !conversation.isActive
                if wanted && !listening { begin() }
                if !wanted && listening { end() }
                if listening { tick() }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    private func authorised() async -> Bool {
        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        return speech == .authorized && mic
    }

    /// Holds the audio engine while the wake word is on, and lets go when it is off.
    private func keepEngine(_ on: Bool) {
        if on, !holding, Date() >= nextTry {
            do {
                try io.hold(.wake)
                holding = true
            } catch {
                log.error("wake: engine did not start: \(error.localizedDescription, privacy: .public)")
                nextTry = Date().addingTimeInterval(15)
            }
        }
        if !on, holding {
            io.release(.wake)
            holding = false
        }
    }

    private func begin() {
        guard let r = SFSpeechRecognizer(locale: Locale(identifier: "en-GB")) ?? SFSpeechRecognizer(),
              r.isAvailable else { return }
        // Never listen all the time through Apple's servers.
        guard r.supportsOnDeviceRecognition else {
            log.error("wake: no on-device recognition, so the wake word stays off")
            return
        }
        recogniser = r
        listening = true
        newRequest()
        log.info("wake: listening")
    }

    private func end() {
        cancelRequest()
        listening = false
        pending = nil
        log.info("wake: stopped")
    }

    private var lastLevelLine = Date()

    private func newRequest() {
        log.debug("wake: new request, format \(self.io.inputFormat, privacy: .public)")
        cancelRequest()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request
        io.setWakeRequest(request)
        requestStarted = Date()
        pending = nil
        generation += 1
        let mine = generation
        task = recogniser?.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let over = result?.isFinal == true || error != nil
            if let error { log.debug("wake: recognition ended: \(error.localizedDescription, privacy: .public)") }
            Task { @MainActor in
                guard let self, mine == self.generation, self.listening else { return }
                if let text { self.heard(text) }
                if over { self.newRequest() }
            }
        }
    }

    private func cancelRequest() {
        io.setWakeRequest(nil)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func heard(_ text: String) {
        guard let after = Self.afterWakeWord(text) else { return }
        if pending?.words != after { pending = (after, Date()) }
    }

    /// Once the wake word was heard, waits for a short pause, then hands
    /// over. Also starts a fresh request now and then, as long requests
    /// slow down and grow.
    private func tick() {
        if let pending, Date().timeIntervalSince(pending.changed) > Self.settleTime(after: pending.words) {
            let question = pending.words
            log.info("wake: heard the wake word")
            end()
            conversation.start(firstQuestion: question.isEmpty ? nil : question, greet: question.isEmpty)
            return
        }
        if pending == nil, Date().timeIntervalSince(requestStarted) > 50 { newRequest() }
        // The microphone level every 5 seconds, for diagnosis with `log stream --level debug`.
        if Date().timeIntervalSince(lastLevelLine) > 5 {
            lastLevelLine = Date()
            let heard = io.takeMeter()
            let db = heard.peak > 0 ? 20 * log10(heard.peak) : -120
            log.debug("wake: loudest \(Int(db), privacy: .public) dBFS in \(heard.buffers, privacy: .public) buffers, the last 5 s")
        }
    }

    /// How long to wait for the words after the wake word to settle. The
    /// recogniser corrects itself for a moment ("Watson" becomes "what's on
    /// tomorrow"), so a short tail gets more time than a full question.
    nonisolated static func settleTime(after words: String) -> TimeInterval {
        words.split(separator: " ").count <= 2 ? 2.0 : 1.5
    }

    /// The words after "Concierge" (or "Hey Concierge"), or nil when it was not said.
    nonisolated static func afterWakeWord(_ text: String) -> String? {
        // The last mention counts: earlier ones were part of other talk.
        var last: Range<String.Index>?
        var from = text.startIndex
        while let r = text.range(of: #"\bconcierge\b"#, options: [.regularExpression, .caseInsensitive],
                                 range: from..<text.endIndex) {
            last = r
            from = r.upperBound
        }
        guard let last else { return nil }
        let rest = text[last.upperBound...]
        return rest.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }
}

/// A value the audio thread and the main actor both touch.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}
