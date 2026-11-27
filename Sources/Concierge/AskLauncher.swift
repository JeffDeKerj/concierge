import Foundation

/// `Concierge --ask "<question>"`: asks through the same path as the
/// question box, with no window, and prints each sentence with the time it
/// arrived. `--spoken` asks as the voice does. For checking by hand how
/// fast an answer comes and what it costs.
enum AskLauncher {
    static let flag = "--ask"

    private final class Outcome {
        var done = false
        var failed = false
    }

    @MainActor static func run(_ args: [String]) -> Int32 {
        guard let i = args.firstIndex(of: flag), args.count > i + 1 else { return 2 }
        let question = args[i + 1]
        let prompt = args.contains("--spoken") ? Conversation.spokenPrompt(question, context: nil) : nil
        let model = AppModel()
        let cutter = SentenceCutter()
        let started = Date()
        let outcome = Outcome()
        func show(_ sentence: String) {
            print(String(format: "%5.1f s  %@", Date().timeIntervalSince(started), sentence))
        }
        Task { @MainActor in
            let reply = await model.ask(question, prompt: prompt) { piece in
                cutter.add(piece).forEach(show)
            }
            if let rest = cutter.finish() { show(rest) }
            if cutter.emitted == 0, let reply { show(reply) }
            if let error = model.askError { print("failed: \(error)") }
            if let report = model.lastAsk { print(String(format: "%5.1f s  done · ", Date().timeIntervalSince(started)) + report.summary) }
            outcome.failed = reply == nil
            outcome.done = true
        }
        while !outcome.done { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        return outcome.failed ? 1 : 0
    }
}
