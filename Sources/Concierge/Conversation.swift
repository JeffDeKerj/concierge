import AppKit
import AVFoundation
import Observation
import OSLog

/// Kept in the system log so a conversation that went wrong can be read
/// afterwards. Numbers and kinds only: never the words.
private let log = Logger(subsystem: "local.jeffdekerj.concierge", category: "talk")

/// A spoken back-and-forth with Concierge: it listens, asks the question box,
/// says the answer, and listens again, until the owner stops or goes quiet.
///
/// The owner can talk over it: it stops speaking and their words become the
/// next question. Echo cancellation keeps it from hearing itself. The
/// microphone button stops it at any moment.
@MainActor
@Observable
final class Conversation {
    enum State: Equatable { case idle, speaking, listening(String), thinking }

    private(set) var state: State = .idle
    private(set) var error: String?
    var isActive: Bool { state != .idle }

    /// How loud Concierge's voice is at `date`, 0 to 1, when it is known.
    func voiceLevel(at date: Date) -> Double? { io.level(at: date) }

    /// Sent just before the window is asked to come forward.
    static let willShowWindow = Notification.Name("local.jeffdekerj.concierge.willShowWindow")

    private let model: AppModel
    private let io: VoiceIO
    /// For alerts said without listening afterwards.
    private let voice = SpokenTurn()
    private var loop: Task<Void, Never>?
    /// When the first words of the answer being given started to sound.
    private var firstWords: Date?
    /// The most turns in one conversation, as a guard against a runaway loop.
    /// Questions in one conversation (owner, 2026-11-28). At 8 it ended
    /// mid-conversation without a word; now it says so and how to go on.
    static let maxTurns = 25

    /// The sessions' questions and the away switch; set by the app.
    var desk: Desk?

    /// `io` is shared with the wake-word listener, so both use one microphone session.
    init(model: AppModel, io: VoiceIO? = nil) {
        self.model = model
        self.io = io ?? VoiceIO()
    }

    /// Starts a conversation. `opening` is said first: an alert Concierge
    /// starts the conversation with. `context` goes with the first question
    /// so the answer knows what "that" means.
    /// `firstQuestion` is a question already heard (after the wake word);
    /// `greet` says "Yes?" before listening.
    func start(opening: String? = nil, context: String? = nil, quickReply: Bool = false,
               firstQuestion: String? = nil, greet: Bool = false) {
        guard !isActive else { return }
        error = nil
        // Active at once, so the wake listener lets go of the microphone.
        state = .thinking
        loop = Task {
            await run(opening: opening, greet: greet, context: context, quickReply: quickReply, firstQuestion: firstQuestion)
        }
    }

    /// A session's question came in while the owner is away: read it out
    /// now, or at the next turn of a conversation already going on.
    func sessionAsked() {
        guard !isActive else { return }
        start(quickReply: true)
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
        model.cancelAsk()
        io.endConversation()
        voice.stop()
        state = .idle
    }

    private func run(opening: String?, greet: Bool, context: String?, quickReply: Bool, firstQuestion: String?) async {
        defer {
            io.endConversation()
            state = .idle
            log.notice("ended")
        }
        var settings = ConciergeSettings.load()
        var language = settings.spokenLanguage(frenchOnThisMac: Language.french.isOnThisMac)
        log.notice("started in \(language.rawValue, privacy: .public): opening \(opening != nil, privacy: .public), greeting \(greet, privacy: .public), question with the name \(firstQuestion != nil, privacy: .public)")
        do {
            try await VoiceIO.authorise()
            try io.hold(.talk)
            try io.use(language, allowOnline: settings.frenchOnline)
        } catch {
            self.error = error.localizedDescription
            return
        }
        io.onWords = { [weak self] words in
            guard let self, case .listening = self.state else { return }
            self.state = .listening(words)
        }
        if let opening {
            // An alert: the daytime jobs write those in English.
            await speak(opening, settings, in: .english)
        } else if greet {
            await speak(language.yes, settings, in: language)
        }
        var context = context
        for turn in 0..<Self.maxTurns {
            guard !Task.isCancelled else { return }
            // Sessions' questions that came in while away are read out first.
            if let desk, desk.away, !desk.unannounced.isEmpty {
                guard await readQuestions(desk.unannounced, settings, in: language) else { return }
            }
            state = .listening(io.heard)
            // After an alert, only a short wait: the owner may be busy.
            let heard = (turn == 0 && firstQuestion != nil)
                ? firstQuestion
                : await io.listen(waitForSpeech: (quickReply && turn == 0) ? 6 : (turn == 0 ? 8 : 15))
            guard !Task.isCancelled else { return }
            guard let heard else {
                // After an answer the owner may just be thinking: say so rather than go quiet.
                if turn > 0 { await sayAndEnd(language.standingBy, settings, in: language) }
                return
            }
            // "Thanks, Nestor" is a goodbye, and "Nestor, hide" a command.
            let said = CalledName.removed(from: heard, name: Brand.name)
            if let wanted = Language.asked(in: said) {
                do {
                    try io.use(wanted, allowOnline: settings.frenchOnline)
                    language = wanted
                    ConciergeSettings.update { $0.language = wanted.rawValue }
                    settings = ConciergeSettings.load()
                    log.notice("turn \(turn, privacy: .public): switched to \(wanted.rawValue, privacy: .public)")
                    await speak(wanted.switched, settings, in: wanted)
                } catch {
                    await speak(Language.frenchMissing, settings, in: .english)
                }
                continue
            }
            if let desk, let command = DeskTalk.awayCommand(said) {
                log.notice("turn \(turn, privacy: .public): away switch \(command == .away ? "on" : "off", privacy: .public)")
                await desk.setAway(command == .away)
                await speak(command == .away
                    ? "Okay. While you're away, I'll read your sessions' questions to you."
                    : "Welcome back. Your sessions will ask you in their windows again.", settings, in: .english)
                continue
            }
            if let desk, DeskTalk.asksForQuestions(said) {
                if desk.waiting.isEmpty {
                    await speak(desk.away ? "No session is waiting for you." : "No session is waiting. They only wait for me while you're away.",
                                settings, in: .english)
                } else {
                    guard await readQuestions(desk.waiting, settings, in: language) else { return }
                }
                continue
            }
            switch Self.windowCommand(said) {
            case .show:
                log.notice("turn \(turn, privacy: .public): asked to show the window")
                Self.showWindow()
                await speak(language.hereIAm, settings, in: language)
                continue
            case .hide:
                log.notice("turn \(turn, privacy: .public): asked to hide the window")
                NSApp.hide(nil)
                await sayAndEnd(language.okay, settings, in: language)
                return
            case nil:
                break
            }
            if Self.isGoodbye(said) {
                log.notice("turn \(turn, privacy: .public): a goodbye")
                await sayAndEnd(language.okay, settings, in: language)
                return
            }
            state = .thinking
            let asked = Date()
            // Each sentence is said as soon as it is written, while the rest still comes.
            let (sentences, feed) = AsyncStream<String>.makeStream()
            let cutter = SentenceCutter()
            let question = Self.spokenPrompt(heard, context: context, language: language)
            let noAnswer = language.noAnswer
            let progress = Progress(language: language)
            // Words while it works, so a long read is not a dead silence.
            let bridging = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    if let line = progress.tick() { feed.yield(line) }
                }
            }
            let asking = Task { @MainActor () -> String? in
                let reply = await self.model.ask(heard, prompt: question, onTool: { tool in
                    if let line = progress.using(tool) { feed.yield(line) }
                }, onText: { piece in
                    for sentence in cutter.add(piece) { feed.yield(sentence); progress.said() }
                })
                bridging.cancel()
                if let rest = cutter.finish() { feed.yield(rest) }
                // An agent that sends nothing on the way gives its answer whole.
                if cutter.emitted == 0 { feed.yield(reply ?? noAnswer) }
                feed.finish()
                return reply
            }
            firstWords = nil
            let spoken = language
            let voices = settings
            let outcome = await io.say(parts: sentences, voiceID: settings.voiceID(for: language),
                                    interruptible: settings.interruptible, in: language,
                                    voiceFor: { sentence in
                                        let written = Language.of(sentence) ?? spoken
                                        return (voices.voiceID(for: written), written)
                                    }) { [weak self] in
                self?.firstWords = Date()
                self?.state = .speaking
            }
            if outcome == .interrupted {
                state = .listening(io.heard)
                model.cancelAsk()
            }
            let reply = await asking.value
            log.notice("turn \(turn, privacy: .public): \(reply == nil ? "no answer" : "an answer", privacy: .public), first words after \(Int((self.firstWords ?? Date()).timeIntervalSince(asked)), privacy: .public) s, all of it after \(Int(Date().timeIntervalSince(asked)), privacy: .public) s")
            context = nil
            guard !Task.isCancelled else { return }
            guard let reply else { return }
            // Asked for the other language in words the listener mangled
            // ("store Wat"), the model still answers in it: listen in it too.
            if let written = Self.switchTo(answer: reply, from: language) {
                do {
                    try io.use(written, allowOnline: settings.frenchOnline)
                    language = written
                    ConciergeSettings.update { $0.language = written.rawValue }
                    settings = ConciergeSettings.load()
                    log.notice("turn \(turn, privacy: .public): the answer was in \(written.rawValue, privacy: .public), so listening in it")
                } catch {
                    log.notice("turn \(turn, privacy: .public): the answer was in \(written.rawValue, privacy: .public), which cannot be heard here")
                }
            }
        }
        // The limit: say so, and how to go on, rather than vanish.
        await sayAndEnd(language.limitReached, settings, in: language)
    }

    /// Reads each question out, takes the owner's pick, says it back, and
    /// sends it only on a yes. False when the conversation was stopped.
    private func readQuestions(_ questions: [DeskQuestion], _ settings: ConciergeSettings, in language: Language) async -> Bool {
        guard let desk else { return true }
        for question in questions {
            desk.markAnnounced(question.id)
            guard desk.waiting.contains(where: { $0.id == question.id }) else { continue }
            var choices: [String: String] = [:]
            var reply = ""
            for (index, part) in question.parts.enumerated() {
                await speak(DeskTalk.readOut(question, part: index), settings, in: .english)
                guard let heard = await io.listen(waitForSpeech: 15) else {
                    guard !Task.isCancelled else { return false }
                    await speak("I'll leave it in its window.", settings, in: .english)
                    return true
                }
                switch DeskTalk.interpret(CalledName.removed(from: heard, name: Brand.name),
                                          options: part.options, multiSelect: part.multiSelect) {
                case .skip:
                    reply = ""; choices = [:]
                case .choice(let labels):
                    choices[part.question] = labels.joined(separator: ", ")
                    reply = labels.joined(separator: ", ")
                case .text(let words):
                    choices[part.question] = words
                    reply = words
                }
                if reply.isEmpty { break }
            }
            guard !reply.isEmpty else { await speak("Skipped.", settings, in: .english); continue }
            let shown = question.kind == .card ? choices.values.joined(separator: "; ") : reply
            guard await confirmed(DeskTalk.confirmation(question, answer: shown), settings) else {
                guard !Task.isCancelled else { return false }
                await speak("Okay, not sent.", settings, in: .english)
                continue
            }
            let sent = question.kind == .card
                ? await desk.answer(question, choices: choices)
                : await desk.answer(question, text: reply)
            await speak(sent ? "Sent." : "I couldn't send it. It's still in its window.", settings, in: .english)
        }
        return true
    }

    /// Asks for a yes, once more if the reply was unclear.
    private func confirmed(_ question: String, _ settings: ConciergeSettings) async -> Bool {
        await speak(question, settings, in: .english)
        for _ in 0..<2 {
            guard let heard = await io.listen(waitForSpeech: 12) else { return false }
            if let answer = DeskTalk.confirm(CalledName.removed(from: heard, name: Brand.name)) { return answer == .yes }
            await speak("Yes or no?", settings, in: .english)
        }
        return false
    }

    /// Says something the owner may talk over, when Settings allows that.
    private func speak(_ text: String, _ settings: ConciergeSettings, in language: Language) async {
        state = .speaking
        if await io.say(text, voiceID: settings.voiceID(for: language), interruptible: settings.interruptible,
                        in: language) == .interrupted {
            state = .listening(io.heard)
        }
    }

    /// The last word of a conversation: said without listening.
    private func sayAndEnd(_ text: String, _ settings: ConciergeSettings, in language: Language) async {
        state = .speaking
        _ = await io.say(text, voiceID: settings.voiceID(for: language), interruptible: false, in: language)
    }

    enum WindowCommand: Equatable { case show, hide }

    /// "Show your face", "come up", "hide" and the like: handled here, at
    /// once, without asking the model.
    nonisolated static func windowCommand(_ heard: String) -> WindowCommand? {
        let words = Phrases.plain(heard)
        // A command is short; a longer sentence is a question that happens to use the words.
        guard words.split(separator: " ").count <= 6 else { return nil }
        let show = ["show your face", "show yourself", "show the window", "show me the window", "show up",
                    "come up", "come forward", "come to the front", "bring up the window", "open the window",
                    "open up", "where are you",
                    "montre toi", "montre ton visage", "montre la fenetre", "ou es tu", "viens ici"]
        let hide = ["hide", "hide yourself", "hide the window", "go to the back", "go away", "go back",
                    "cache toi", "cache la fenetre", "va t'en", "disparais"]
        if show.contains(where: { words.contains($0) }) { return .show }
        if hide.contains(where: { words == $0 || words.hasPrefix($0 + " ") || words.hasSuffix(" " + $0) }) { return .hide }
        return nil
    }

    /// Brings the window to the front, opening one if it was closed.
    static func showWindow() {
        NotificationCenter.default.post(name: willShowWindow, object: nil)
        // Opening the running app's own bundle is a reopen: macOS makes a
        // window when there is none, and brings the app forward.
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: .init())
        NSApp.unhide(nil)
        NSApp.activate()
    }

    /// The language to go on in when a whole answer came in the other one. Pure, for tests.
    nonisolated static func switchTo(answer: String, from current: Language) -> Language? {
        guard answer.split(separator: " ").count >= 6, let written = Language.of(answer), written != current else { return nil }
        return written
    }

    /// What the model reads for a spoken question.
    nonisolated static func spokenPrompt(_ heard: String, context: String?, language: Language = .english) -> String {
        var p = "(The owner said this aloud and will hear your answer read out. Answer in one to three short spoken sentences: no lists, no markdown, no links. You still never send, reply, accept, pay or delete; offer to draft instead. If you need to look something up or read something first, begin with one short sentence saying so, such as \"Let me look that up.\", before using any tool; for an answer you already have, just answer.)"
        p += language.answerRule
        if let context { p += " About this alert: \(context)." }
        return p + " \(heard)"
    }

    /// "Thanks", "that's all", "stop" and the like end the conversation.
    nonisolated static func isGoodbye(_ heard: String) -> Bool {
        let words = Phrases.plain(heard)
        let endings = ["stop", "no", "no thanks", "no thank you", "nothing", "that's all", "that's it",
                       "thanks", "thank you", "goodbye", "bye", "never mind", "not now", "later",
                       "non", "non merci", "merci", "merci beaucoup", "rien", "c'est tout", "c'est bon",
                       "au revoir", "laisse tomber", "pas maintenant", "plus tard", "ca ira"]
        if endings.contains(words) { return true }
        // "No thanks, that's fine" ends it; "Thanks, and what about Declan?" does not.
        let short = words.split(separator: " ").count <= 4 && !words.contains("?")
        // A bare "no" leads into a correction ("No, the other one"), so only longer endings count here.
        return short && endings.filter { $0 != "no" && $0 != "non" }.contains { words.hasPrefix($0 + ",") || words.hasPrefix($0 + ".") }
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

/// What to say while an answer is being worked on: what the agent is
/// doing when it starts a tool and has not said so itself, then that it is
/// still coming. No timed "Let me think": an answer without a lookup comes
/// in 4 to 6 s, and a timer at 3.5 s spoke just before it (2026-11-28). The
/// model says its own short line before a lookup. The clock is passed in,
/// for tests.
@MainActor
final class Progress {
    /// Seconds with nothing new before "Still on it" and the like.
    static let still: TimeInterval = 12
    /// Seconds at least between two lines about the work.
    static let apart: TimeInterval = 6

    private let language: Language
    private let now: () -> Date
    private let started: Date
    private var lastSaid: Date?
    private var stills = 0
    private var lastLine = ""

    init(language: Language, now: @escaping () -> Date = Date.init) {
        self.language = language
        self.now = now
        started = now()
    }

    /// A sentence of the answer was said.
    func said() { lastSaid = now() }

    /// Checked twice a second: a line to say, or nil.
    func tick() -> String? {
        let quiet = now().timeIntervalSince(lastSaid ?? started)
        guard quiet > Self.still, stills < language.stillComing.count else { return nil }
        stills += 1
        return say(language.stillComing[stills - 1])
    }

    /// The agent started a tool: a line about it, unless one was just said.
    func using(_ tool: String) -> String? {
        guard let line = language.doing(tool), line != lastLine else { return nil }
        if let lastSaid, now().timeIntervalSince(lastSaid) < Self.apart { return nil }
        return say(line)
    }

    private func say(_ line: String) -> String {
        lastSaid = now()
        lastLine = line
        return line
    }
}
