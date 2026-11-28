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

    /// Replaced by a fresh one when a way of starting failed or the owner
    /// chose another microphone: a used engine keeps its device and fails.
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
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
    /// The energy of the microphone's sound during a turn, for its log.
    private let energy = Locked<(sum: Double, frames: Int)>((0, 0))
    private var lastTurnLine = Date()
    /// The whole turn so far: microphone buffers and its loudest sample, in dBFS.
    private var turnBuffers = 0
    private var turnLoudest = -120
    /// Counts turns, so a late answer from a cancelled turn is ignored.
    private var turnNumber = 0
    /// The sentences being said: when each starts to sound, how long it
    /// lasts and how loud it is step by step.
    private var segments: [(start: Date, duration: TimeInterval, levels: [Float])] = []
    /// Every sentence handed to the player in the current `say`, and
    /// whether more may come and whether the owner is listened to.
    private var sayingText = ""
    private var moreToSay = false
    private var listeningOver = false

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
        guard running, processing else { return }
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

    /// Starts the engine on the microphone chosen in Settings. The Mac's
    /// voice processing (echo cancelling) cannot run with the microphone on
    /// one device and the sound on another (avfaudio error -10875), which is
    /// what the Mac's own microphone with a headset is. So the ways to start
    /// are tried best first: the chosen microphone with voice processing,
    /// the chosen microphone without it (on a headset there is little echo
    /// to cancel), and last the Mac's own choice as before, so listening is
    /// never worse than with no choice made.
    private func startEngine() throws {
        guard !running else { return }
        let choice = ConciergeSettings.load().microphone
        let chosen = Microphone.device(for: choice)
        var plans: [(device: AudioDeviceID?, processing: Bool)] = []
        if let chosen { plans += [(chosen, true), (chosen, false)] }
        plans.append((nil, true))
        var failure: Error = Failure.unavailable
        for plan in plans {
            do {
                try start(on: plan.device, processing: plan.processing)
                microphone = choice
                let inUse = plan.device ?? Microphone.systemInput()
                microphoneName = inUse.flatMap(Microphone.name(of:)) ?? "the Mac's choice"
                log.notice("listening on \(self.microphoneName, privacy: .public), voice processing \(plan.processing, privacy: .public)")
                return
            } catch {
                failure = error
                log.notice("the engine did not start on \(plan.device.flatMap(Microphone.name(of:)) ?? "the Mac's choice", privacy: .public), voice processing \(plan.processing, privacy: .public): \(error.localizedDescription, privacy: .public)")
                freshEngine()
            }
        }
        // Remembered even so, or the listener would ask for a restart for ever.
        microphone = choice
        throw failure
    }

    /// A new engine with nothing set on it, so the next start is on the
    /// Mac's own choice of devices unless told otherwise.
    private func freshEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let deviceChanges { NotificationCenter.default.removeObserver(deviceChanges) }
        deviceChanges = nil
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        running = false
    }

    /// Whether the engine runs. It does not after a start that failed, and
    /// whoever holds it then asks again with `hold`.
    var isRunning: Bool { running }

    /// One way of starting: the input on `device` (nil leaves it alone),
    /// with or without the Mac's voice processing.
    private func start(on device: AudioDeviceID?, processing: Bool) throws {
        // The output side must exist before voice processing is switched on,
        // or the engine fails to start (avfaudio error -10875).
        _ = engine.outputNode
        _ = engine.mainMixerNode
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(processing)
        self.processing = processing
        if let device { try input.auAudioUnit.setDeviceID(device) }
        if processing {
            // Voice processing would otherwise turn other sound on the Mac down.
            input.voiceProcessingOtherAudioDuckingConfiguration =
                AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
        }
        if player.engine == nil { engine.attach(player) }
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        let feed = self.feed, wakeFeed = self.wakeFeed, meter = self.meter, energy = self.energy
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            let mono = Self.firstChannel(of: buffer)
            feed.append(mono)
            wakeFeed.append(mono)
            let peak = Self.peak(of: mono)
            meter.withLock { $0 = ($0.buffers + 1, max($0.peak, peak)) }
            let sum = Self.sumOfSquares(of: mono)
            energy.withLock { $0 = ($0.sum + sum, $0.frames + Int(mono.frameLength)) }
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

    /// The microphone choice the engine was last started for.
    private var microphone = Microphone.system
    /// Whether the engine runs with the Mac's voice processing.
    private var processing = true
    /// The name of the input in use, for the log.
    private(set) var microphoneName = "the Mac's choice"

    /// Starts a fresh engine when the owner chose another microphone.
    func followMicrophoneChoice() {
        guard running, ConciergeSettings.load().microphone != microphone else { return }
        log.notice("another microphone was chosen: starting the engine again")
        freshEngine()
        do {
            try startEngine()
            setProcessing()
        } catch {
            log.error("engine did not start again: \(error.localizedDescription, privacy: .public)")
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
        log.notice("the sound devices changed: starting the engine again")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        do {
            try startEngine()
            setProcessing()
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

    nonisolated static func sumOfSquares(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        var sum = 0.0
        for i in 0..<Int(buffer.frameLength) { sum += Double(data[i] * data[i]) }
        return sum
    }

    /// The microphone since the last call: buffers, loudest sample and
    /// average level, in dBFS. Also adds them to the turn's totals.
    private func turnLine() -> String {
        let got = takeMeter()
        let e = energy.withLock { e in defer { e = (0, 0) }; return e }
        let peak = got.peak > 0 ? Int(20 * log10(got.peak)) : -120
        let mean = e.frames > 0 && e.sum > 0 ? Int(10 * log10(e.sum / Double(e.frames))) : -120
        turnBuffers += got.buffers
        turnLoudest = max(turnLoudest, peak)
        return "\(got.buffers) buffers, loudest \(peak) dBFS, average \(mean) dBFS"
    }

    /// The turn in numbers, for the log: how long, and what the microphone gave.
    private func turnSummary() -> String {
        _ = turnLine()
        let seconds = String(format: "%.1f", Date().timeIntervalSince(turnStarted))
        return "\(seconds) s, \(turnBuffers) microphone buffers, loudest \(turnLoudest) dBFS"
    }

    // MARK: Speaking

    /// Says `text`. When `interruptible`, it listens at the same time and
    /// stops as soon as the owner talks over it; their words so far stay
    /// in the open turn, which `listen` then finishes.
    func say(_ text: String, voiceID: String, interruptible: Bool, in spoken: Language? = nil) async -> Said {
        let one = AsyncStream<String> { $0.yield(text); $0.finish() }
        return await say(parts: one, voiceID: voiceID, interruptible: interruptible, in: spoken)
    }

    /// Says sentences as they come, one after the other: an answer is
    /// spoken while the rest of it is still being written. `onFirst` is
    /// called when the first one starts to sound. One listening turn covers
    /// them all, so the owner can talk over any of them.
    /// `voiceFor`, when given, picks the voice and language for each sentence.
    func say(parts: AsyncStream<String>, voiceID: String, interruptible: Bool, in spoken: Language? = nil,
             voiceFor: ((String) -> (id: String, language: Language))? = nil,
             onFirst: (() -> Void)? = nil) async -> Said {
        let waiting = Locked(0)
        sayingText = ""
        moreToSay = true
        listeningOver = false
        segments = []
        defer { segments = [] }
        let producer = Task { @MainActor in
            defer { self.moreToSay = false }
            var audioEnd = Date()
            var connected: AVAudioFormat?
            for await part in parts {
                let voice = voiceFor?(part) ?? (id: voiceID, language: spoken ?? self.language)
                let buffers = await self.synthesise(Speaker.utterance(part, voiceID: voice.id, language: voice.language))
                guard !Task.isCancelled else { return }
                guard let format = buffers.first?.format else { continue }
                if connected != format {
                    self.engine.disconnectNodeOutput(self.player)
                    self.engine.connect(self.player, to: self.engine.mainMixerNode, format: format)
                    connected = format
                }
                waiting.withLock { $0 += buffers.count }
                for buffer in buffers {
                    self.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                        waiting.withLock { $0 -= 1 }
                    }
                }
                // A sentence sounds when the one before it has ended.
                let start = max(Date(), audioEnd)
                let duration = buffers.reduce(0.0) { $0 + Double($1.frameLength) } / format.sampleRate
                audioEnd = start.addingTimeInterval(duration)
                self.segments.append((start, duration, Self.loudness(of: buffers)))
                if self.sayingText.isEmpty {
                    onFirst?()
                    if interruptible {
                        self.beginTurn()
                        self.listeningOver = true
                    }
                }
                self.sayingText += (self.sayingText.isEmpty ? "" : " ") + part
                self.player.play()
                log.notice("say: \(buffers.count, privacy: .public) buffers, interruptible \(interruptible, privacy: .public)")
            }
        }
        while moreToSay || waiting.withLock({ $0 }) > 0 {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled {
                producer.cancel()
                player.stop()
                if listeningOver { endTurn() }
                return .finished
            }
            if listeningOver, Self.isBargeIn(heard: heard, speaking: sayingText) {
                log.notice("say: interrupted after \(Self.words(self.heard).count, privacy: .public) words")
                producer.cancel()
                player.stop()
                return .interrupted
            }
        }
        log.notice("say: finished, heard meanwhile \(Self.words(self.heard).count, privacy: .public) words")
        if listeningOver { endTurn() }
        return .finished
    }

    /// How loud Concierge's voice is at `date`, 0 to 1, or nil when it is
    /// not speaking. The face moves its mouth with this.
    func level(at date: Date) -> Double? {
        guard !segments.isEmpty else { return nil }
        for segment in segments where date >= segment.start && date < segment.start.addingTimeInterval(segment.duration) {
            let step = Int(date.timeIntervalSince(segment.start) * Self.loudnessRate)
            return segment.levels.indices.contains(step) ? Double(segment.levels[step]) : 0
        }
        // Between two sentences, or after the last.
        return 0
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
            if Date().timeIntervalSince(lastTurnLine) >= 1 {
                lastTurnLine = Date()
                log.debug("listen: \(self.turnLine(), privacy: .public), \(Self.words(self.heard).count, privacy: .public) words so far")
            }
            if heard.isEmpty {
                if Date().timeIntervalSince(waitingSince) > waitForSpeech {
                    log.notice("listen: nothing heard in \(self.turnSummary(), privacy: .public)")
                    endTurn()
                    return nil
                }
                // The recogniser can give up by itself with "No speech
                // detected": at once when the wake-word listener lets go
                // of the microphone as the conversation starts, or after a
                // silence of its own choosing. How long to wait for speech
                // is decided here, so listen on with a fresh turn.
                if turnOver {
                    log.notice("listen: the recogniser gave up early, listening again")
                    beginTurn()
                }
                continue
            }
            if !heard.isEmpty, quiet > endOfTurnPause || turnOver {
                let words = heard
                log.notice("listen: heard \(Self.words(words).count, privacy: .public) words in \(self.turnSummary(), privacy: .public)")
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
        _ = turnLine()
        turnBuffers = 0
        turnLoudest = -120
        lastTurnLine = Date()
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
                if let error { log.notice("recognition error: \(error.localizedDescription, privacy: .public)") }
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
