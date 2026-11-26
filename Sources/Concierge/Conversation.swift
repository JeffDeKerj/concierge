import AVFoundation
import Observation

/// A spoken back-and-forth with Concierge: it listens, asks the question box,
/// says the answer, and listens again, until the owner stops or goes quiet.
///
/// Turn-taking, not true duplex: it never listens while it speaks, so it
/// cannot hear itself. The microphone button stops it at any moment.
@MainActor
@Observable
final class Conversation {
    enum State: Equatable { case idle, speaking, listening(String), thinking }

    private(set) var state: State = .idle
    private(set) var error: String?
    var isActive: Bool { state != .idle }

    private let model: AppModel
    private let listener = Listener()
    private let voice = SpokenTurn()
    private var loop: Task<Void, Never>?
    /// The most turns in one conversation, as a guard against a runaway loop.
    private let maxTurns = 8

    init(model: AppModel) { self.model = model }

    /// Starts a conversation. `opening` is said first: an alert Concierge
    /// starts the conversation with. `context` goes with the first question
    /// so the answer knows what "that" means.
    func start(opening: String? = nil, context: String? = nil, quickReply: Bool = false) {
        guard !isActive else { return }
        error = nil
        loop = Task { await run(opening: opening, context: context, quickReply: quickReply) }
    }

    /// An alert from the job runner: say it, then listen for a reply when
    /// the owner wants that. Waits for a conversation already going on.
    func alert(_ text: String, listen: Bool) {
        if !listen || isActive {
            Task {
                while isActive { try? await Task.sleep(for: .seconds(1)) }
                state = .speaking
                await voice.say(text, voiceID: ConciergeSettings.load().voice)
                state = .idle
            }
            return
        }
        start(opening: text + " Anything I can do?", context: text, quickReply: true)
    }

    func stop() {
        loop?.cancel()
        listener.stop()
        voice.stop()
        state = .idle
    }

    private func run(opening: String?, context: String?, quickReply: Bool) async {
        defer { state = .idle }
        do {
            try await Listener.authorise()
        } catch {
            self.error = error.localizedDescription
            return
        }
        let settings = ConciergeSettings.load()
        if let opening {
            state = .speaking
            await voice.say(opening, voiceID: settings.voice)
        }
        var context = context
        for turn in 0..<maxTurns {
            guard !Task.isCancelled else { return }
            state = .listening("")
            // After an alert, only a short wait: the owner may be busy.
            listener.waitForSpeech = (quickReply && turn == 0) ? 6 : 8
            let heard: String?
            do {
                heard = try await listener.listen { [weak self] words in self?.state = .listening(words) }
            } catch {
                self.error = error.localizedDescription
                return
            }
            guard !Task.isCancelled, let heard, !Self.isGoodbye(heard) else {
                if let heard, Self.isGoodbye(heard) {
                    state = .speaking
                    await voice.say("Okay.", voiceID: settings.voice)
                }
                return
            }
            state = .thinking
            let reply = await model.ask(heard, prompt: Self.spokenPrompt(heard, context: context))
            context = nil
            guard !Task.isCancelled else { return }
            state = .speaking
            await voice.say(reply ?? "Sorry, I could not get an answer.", voiceID: settings.voice)
            if reply == nil { return }
        }
    }

    /// What the model reads for a spoken question.
    nonisolated static func spokenPrompt(_ heard: String, context: String?) -> String {
        var p = "(The owner said this aloud and will hear your answer read out. Answer in one to three short spoken sentences: no lists, no markdown, no links. You still never send, reply, accept, pay or delete; offer to draft instead.)"
        if let context { p += " About this alert: \(context)." }
        return p + " \(heard)"
    }

    /// "Thanks", "that's all", "stop" and the like end the conversation.
    nonisolated static func isGoodbye(_ heard: String) -> Bool {
        let words = heard.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        let endings = ["stop", "no", "no thanks", "no thank you", "nothing", "that's all", "that's it",
                       "thanks", "thank you", "goodbye", "bye", "never mind", "not now", "later"]
        if endings.contains(words) { return true }
        // "No thanks, that's fine" ends it; "Thanks, and what about Declan?" does not.
        let short = words.split(separator: " ").count <= 4 && !words.contains("?")
        // A bare "no" leads into a correction ("No, the other one"), so only longer endings count here.
        return short && endings.filter { $0 != "no" }.contains { words.hasPrefix($0 + ",") || words.hasPrefix($0 + ".") }
    }
}

/// Says one thing and returns when it has been said.
@MainActor
final class SpokenTurn: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var done: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ text: String, voiceID: String) async {
        await withCheckedContinuation { c in
            done = c
            synth.speak(Speaker.utterance(text, voiceID: voiceID))
        }
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }

    private func resume() {
        done?.resume()
        done = nil
    }
}
