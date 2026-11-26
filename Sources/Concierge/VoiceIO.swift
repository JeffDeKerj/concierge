import AVFoundation
import OSLog
import Speech

private let log = Logger(subsystem: "local.jeffdekerj.concierge", category: "voice")

/// The microphone and the voice of Concierge, on one audio engine with the
/// Mac's voice processing on. Speech is played through the same engine, so
/// its echo cancellation removes Concierge's own voice from the microphone,
/// and Concierge can listen while it talks. Speech recognition stays on the
/// Mac when the recogniser supports it.
///
/// The wake-word listener and the conversation share this one engine. It
/// runs for as long as either holds it, so a conversation that starts while
/// the wake word is on switches nothing on or off. Each switch made macOS
/// rewrite the output volume, and a headset beeps at that.
@MainActor
final class VoiceIO {
    enum Failure: LocalizedError {
        case notAllowed(String), unavailable, notOnThisMac(Language)
        var errorDescription: String? {
            switch self {
            case .notAllowed(let what): "\(Brand.name) may not use \(what). Allow it in System Settings › Privacy & Security."
            case .unavailable: "Speech recognition is not available right now."
            case .notOnThisMac(let language): "\(language.name) speech recognition is not on this Mac."
            }
        }
    }

    enum Said { case finished, interrupted }

    /// The pause that ends a spoken turn.
    var endOfTurnPause: TimeInterval = 1.6
    /// Sees the words of the current turn as they come.
    var onWords: ((String) -> Void)?
    /// The words of the turn so far.
    private(set) var heard = ""

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let synth = AVSpeechSynthesizer()
    private let feed = Feed()
    private var recogniser: SFSpeechRecognizer?
    /// The language of the turns and of what is said.
    private(set) var language = Language.english
    /// Whether the recogniser in use works on this Mac alone.
    private var onDevice = true
    private var task: SFSpeechRecognitionTask?
    private var lastChange = Date()
    private var turnStarted = Date()
    private var turnOver = false
    private var running = false
    /// Who needs the engine to run.
    enum Hold: Hashable { case wake, talk }
    private var holds: Set<Hold> = []
    private var deviceChanges: NSObjectProtocol?
    /// What the wake-word listener hears, beside the conversation's own feed.
    private let wakeFeed = Feed()
    /// Microphone buffers and the loudest sample since last asked, for the wake listener's log.
    private let meter = Locked<(buffers: Int, peak: Float)>((0, 0))
    /// Counts turns, so a late answer from a cancelled turn is ignored.
    private var turnNumber = 0
    /// How loud the sentence being said is, step by step, and when it began.
    private var loudness: [Float] = []
    private var speakingSince: Date?

    /// Asks for the microphone and speech recognition, once.
    static func authorise() async throws {
        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else { throw Failure.notAllowed("speech recognition") }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw Failure.notAllowed("the microphone") }
    }

    /// Keeps the engine running for `who`, starting it when nobody held it.
    func hold(_ who: Hold) throws {
        if !running { try startEngine() }
        holds.insert(who)
        setProcessing()
    }

    /// Lets go for `who`; the engine stops when nobody holds it any more.
    func release(_ who: Hold) {
        holds.remove(who)
        if holds.isEmpty { stopEngine() } else { setProcessing() }
    }

    /// Echo cancellation and noise removal work only during a conversation.
    /// While the engine just waits for the wake word they are bypassed: left
    /// on, they took a quarter of a processor core all day. Bypassing keeps
    /// the engine as it is, so nothing is switched and the volume stays put.
    private func setProcessing() {
        guard running else { return }
        engine.inputNode.isVoiceProcessingBypassed = !holds.contains(.talk)
    }

    /// The recognition request that gets the microphone for the wake word, or nil for none.
    func setWakeRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        wakeFeed.set(request)
    }

    /// Microphone buffers and the loudest sample (0 to 1) since the last call.
    func takeMeter() -> (buffers: Int, peak: Float) {
        meter.withLock { m in defer { m = (0, 0) }; return m }
    }

    var inputFormat: String { engine.inputNode.outputFormat(forBus: 0).description }

    /// Listens and speaks in `language` from now on. Recognition stays on
    /// this Mac. When the Mac cannot recognise the language by itself,
    /// `allowOnline` lets Apple's servers do it; without that this throws
    /// and nothing changes.
    func use(_ language: Language, allowOnline: Bool) throws {
        guard let r = SFSpeechRecognizer(locale: language.locale), r.isAvailable else { throw Failure.unavailable }
        guard r.supportsOnDeviceRecognition || allowOnline else { throw Failure.notOnThisMac(language) }
        endTurn()
        recogniser = r
        onDevice = r.supportsOnDeviceRecognition
        self.language = language
    }

    private func startEngine() throws {
        guard !running else { return }
        // The output side must exist before voice processing is switched on,
        // or the engine fails to start (avfaudio error -10875).
        _ = engine.outputNode
        _ = engine.mainMixerNode
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        // Voice processing would otherwise turn other sound on the Mac down.
        input.voiceProcessingOtherAudioDuckingConfiguration =
            AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
        if player.engine == nil { engine.attach(player) }
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        let feed = self.feed, wakeFeed = self.wakeFeed, meter = self.meter
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            let mono = Self.firstChannel(of: buffer)
            feed.append(mono)
            wakeFeed.append(mono)
            let peak = Self.peak(of: mono)
            meter.withLock { $0 = ($0.buffers + 1, max($0.peak, peak)) }
        }
        engine.prepare()
        try engine.start()
        running = true
        if deviceChanges == nil {
            // A headset that connects or drops stops the engine: start it again on the new device.
            deviceChanges = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restartAfterDeviceChange() }
            }
        }
    }

    private func stopEngine() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        running = false
    }

    private func restartAfterDeviceChange() {
        guard running else { return }
        log.info("the sound devices changed: starting the engine again")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        do {
            try startEngine()
        } catch {
            log.error("engine did not start again: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Ends the conversation's part: its turn and its voice. The engine
    /// goes on when the wake word still holds it.
    func endConversation() {
        endTurn()
        synth.stopSpeaking(at: .immediate)
        player.stop()
        release(.talk)
    }

    /// With voice processing on, the input has several channels and only the
    /// first carries the cleaned-up voice.
    nonisolated private static func firstChannel(of buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard buffer.format.channelCount > 1, let source = buffer.floatChannelData,
              let format = AVAudioFormat(standardFormatWithSampleRate: buffer.format.sampleRate, channels: 1),
              let mono = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
              let target = mono.floatChannelData else { return buffer }
        mono.frameLength = buffer.frameLength
        target[0].update(from: source[0], count: Int(buffer.frameLength))
        return mono
    }

    /// The loudest sample of a buffer, 0 to 1.
    nonisolated static func peak(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        var m: Float = 0
        for i in 0..<Int(buffer.frameLength) { m = max(m, abs(data[i])) }
        return m
    }

    // MARK: Speaking

    /// Says `text`. When `interruptible`, it listens at the same time and
    /// stops as soon as the owner talks over it; their words so far stay
    /// in the open turn, which `listen` then finishes.
    func say(_ text: String, voiceID: String, interruptible: Bool, in spoken: Language? = nil) async -> Said {
        let buffers = await synthesise(Speaker.utterance(text, voiceID: voiceID, language: spoken ?? language))
        guard let format = buffers.first?.format, !Task.isCancelled else { return .finished }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        let played = Flag()
        for (i, buffer) in buffers.enumerated() {
            let last = i == buffers.count - 1
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                if last { played.set() }
            }
        }
        loudness = Self.loudness(of: buffers)
        speakingSince = Date()
        defer { speakingSince = nil }
        player.play()
        log.info("say: \(buffers.count) buffers, interruptible \(interruptible)")
        if interruptible { beginTurn() }
        while !played.isSet {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { player.stop(); endTurn(); return .finished }
            if interruptible, Self.isBargeIn(heard: heard, speaking: text) {
                log.info("say: interrupted by \(self.heard, privacy: .private)")
                player.stop()
                return .interrupted
            }
        }
        log.info("say: finished, heard meanwhile \(self.heard, privacy: .private)")
        if interruptible { endTurn() }
        return .finished
    }

    /// How loud Concierge's voice is at `date`, 0 to 1, or nil when it is
    /// not speaking. The face moves its mouth with this.
    func level(at date: Date) -> Double? {
        guard let since = speakingSince else { return nil }
        let step = Int(date.timeIntervalSince(since) * Self.loudnessRate)
        return loudness.indices.contains(step) ? Double(loudness[step]) : 0
    }

    /// Steps a second in the loudness of a sentence.
    nonisolated static let loudnessRate = 30.0

    /// The loudness of speech step by step, each 0 to 1 against the
    /// loudest step of the sentence.
    nonisolated static func loudness(of buffers: [AVAudioPCMBuffer]) -> [Float] {
        var steps: [Float] = []
        var sum: Float = 0
        var count = 0
        for buffer in buffers {
            let perStep = max(1, Int(buffer.format.sampleRate / loudnessRate))
            for i in 0..<Int(buffer.frameLength) {
                let sample: Float
                if let floats = buffer.floatChannelData {
                    sample = floats[0][i]
                } else if let ints = buffer.int16ChannelData {
                    sample = Float(ints[0][i]) / 32768
                } else if let ints = buffer.int32ChannelData {
                    sample = Float(ints[0][i]) / 2_147_483_648
                } else {
                    return []
                }
                sum += sample * sample
                count += 1
                if count == perStep {
                    steps.append((sum / Float(count)).squareRoot())
                    sum = 0
                    count = 0
                }
            }
        }
        guard let loudest = steps.max(), loudest > 0 else { return steps }
        // The square root lifts the quiet parts, so the mouth moves on soft syllables too.
        return steps.map { ($0 / loudest).squareRoot() }
    }

    /// The utterance as audio buffers, made faster than it plays.
    private func synthesise(_ utterance: AVSpeechUtterance) async -> [AVAudioPCMBuffer] {
        let box = Buffers()
        return await withCheckedContinuation { c in
            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                // The end can be signalled more than once (when speech is
                // stopped, say); resuming twice would crash.
                if pcm.frameLength == 0 {
                    if let all = box.finish() { c.resume(returning: all) }
                } else {
                    box.add(pcm)
                }
            }
        }
    }

    /// Whether what the microphone heard while Concierge spoke is the owner
    /// talking, not what is left of Concierge's own voice after echo
    /// cancellation. Two or more words that are mostly not in the sentence
    /// being said, or one word such as "stop" or "wait".
    nonisolated static func isBargeIn(heard: String, speaking: String) -> Bool {
        let words = Self.words(heard)
        guard !words.isEmpty else { return false }
        let said = Set(Self.words(speaking))
        if words.count == 1 {
            return ["stop", "wait", "sorry", "hang", "hold", "actually", "excuse",
                    "attends", "arrete", "arrête", "pardon"].contains(words[0])
                && !said.contains(words[0])
        }
        let foreign = words.filter { !said.contains($0) }.count
        return Double(foreign) / Double(words.count) >= 0.5
    }

    nonisolated private static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.union(.init(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: Listening

    /// Finishes the turn the owner started by interrupting, or starts one.
    /// Returns their words, or nil when nothing was said for `waitForSpeech`.
    func listen(waitForSpeech: TimeInterval) async -> String? {
        if task == nil { beginTurn() }
        let waitingSince = turnStarted
        while true {
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { endTurn(); return nil }
            let quiet = Date().timeIntervalSince(lastChange)
            if heard.isEmpty {
                if Date().timeIntervalSince(waitingSince) > waitForSpeech {
                    log.info("listen: nothing heard")
                    endTurn()
                    return nil
                }
                // The recogniser can give up by itself with "No speech
                // detected": at once when the wake-word listener lets go
                // of the microphone as the conversation starts, or after a
                // silence of its own choosing. How long to wait for speech
                // is decided here, so listen on with a fresh turn.
                if turnOver {
                    log.info("listen: the recogniser gave up early, listening again")
                    beginTurn()
                }
                continue
            }
            if !heard.isEmpty, quiet > endOfTurnPause || turnOver {
                let words = heard
                endTurn()
                return words
            }
        }
    }

    private func beginTurn() {
        endTurn()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = onDevice
        request.addsPunctuation = true
        heard = ""
        turnStarted = Date()
        lastChange = Date()
        turnOver = false
        feed.set(request)
        turnNumber += 1
        let turn = turnNumber
        task = recogniser?.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? (error != nil)
            Task { @MainActor in
                // Ending a turn cancels its task, whose error arrives after the next turn began.
                guard let self, turn == self.turnNumber else { return }
                if let error { log.info("recognition error: \(error.localizedDescription, privacy: .public)") }
                self.receive(text, final: final)
            }
        }
    }

    private func receive(_ text: String?, final: Bool) {
        guard task != nil else { return }
        if let text, text != heard {
            heard = text
            lastChange = Date()
            onWords?(text)
        }
        if final { turnOver = true }
    }

    private func endTurn() {
        feed.set(nil)?.endAudio()
        task?.cancel()
        task = nil
    }
}

/// The recognition request the microphone feeds, swapped between turns from
/// the main actor while the audio thread appends to it.
private final class Feed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }

    /// Sets the new request and returns the old one.
    @discardableResult
    func set(_ new: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock(); defer { lock.unlock() }
        let old = request
        request = new
        return old
    }
}

private final class Buffers: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [AVAudioPCMBuffer] = []
    private var finished = false
    func add(_ b: AVAudioPCMBuffer) { lock.lock(); if !finished { list.append(b) }; lock.unlock() }
    /// The buffers the first time, nil after that.
    func finish() -> [AVAudioPCMBuffer]? {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return nil }
        finished = true
        return list
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
