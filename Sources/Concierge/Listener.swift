import AVFoundation
import Speech

/// Hears one spoken turn with the Mac's own speech recognition, kept on the
/// Mac when the recogniser supports it (English does on Apple Silicon).
@MainActor
final class Listener {
    enum Failure: LocalizedError {
        case notAllowed(String), unavailable
        var errorDescription: String? {
            switch self {
            case .notAllowed(let what): "Concierge may not use \(what). Allow it in System Settings › Privacy & Security."
            case .unavailable: "Speech recognition is not available right now."
            }
        }
    }

    /// How long to wait for the first word, and the pause that ends a turn.
    var waitForSpeech: TimeInterval = 8
    var endOfTurnPause: TimeInterval = 1.6

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finish: ((String?) -> Void)?

    /// Asks for the microphone and speech recognition, once.
    static func authorise() async throws {
        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else { throw Failure.notAllowed("speech recognition") }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw Failure.notAllowed("the microphone") }
    }

    /// The words of one turn, or nil when nothing was said. `partial` sees
    /// the words as they come.
    func listen(partial: @escaping (String) -> Void) async throws -> String? {
        guard let recogniser = SFSpeechRecognizer(locale: Locale(identifier: "en-GB")) ?? SFSpeechRecognizer(),
              recogniser.isAvailable else { throw Failure.unavailable }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recogniser.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.addsPunctuation = true
        self.request = request

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()

        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            var heard = ""
            var lastChange = Date()
            let started = Date()
            var done = false
            let end: (String?) -> Void = { [weak self] text in
                guard !done else { return }
                done = true
                self?.teardown()
                c.resume(returning: text)
            }
            finish = end
            task = recogniser.recognitionTask(with: request) { result, error in
                Task { @MainActor in
                    if let result {
                        let text = result.bestTranscription.formattedString
                        if text != heard { heard = text; lastChange = Date(); partial(text) }
                        if result.isFinal { end(heard.isEmpty ? nil : heard) }
                    } else if error != nil {
                        end(heard.isEmpty ? nil : heard)
                    }
                }
            }
            // End the turn after a pause, or when nothing is said at all.
            Task { @MainActor [weak self] in
                while !done {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard let self else { return }
                    if heard.isEmpty, Date().timeIntervalSince(started) > self.waitForSpeech { end(nil) }
                    if !heard.isEmpty, Date().timeIntervalSince(lastChange) > self.endOfTurnPause { end(heard) }
                }
            }
        }
    }

    /// Stops listening at once; the pending `listen` returns what it heard so far, or nil.
    func stop() { finish?(nil) }

    private func teardown() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        finish = nil
    }
}
