import Foundation

/// Reading a session's question aloud and understanding the owner's reply.
/// Pure, for tests: the conversation does the talking.
enum DeskTalk {
    enum Reply: Equatable {
        /// One or more of the offered options, by their labels.
        case choice([String])
        /// The owner's own words.
        case text(String)
        /// Leave this one for later.
        case skip
        /// Say the question again.
        case again
    }

    enum Confirm: Equatable { case yes, no, again }

    /// "Again", "repeat", "pardon": say it once more.
    static func wantsAgain(_ heard: String) -> Bool {
        let words = plain(heard)
        guard words.split(separator: " ").count <= 5 else { return false }
        return ["again", "repeat", "pardon", "say that", "what was", "come again", "sorry", "repete", "encore", "quoi", "comment"]
            .contains { words.contains($0) } || words == "what"
    }

    enum AwayCommand: Equatable { case away, back }

    // MARK: Away switch and asking for the questions

    static func awayCommand(_ heard: String) -> AwayCommand? {
        let words = plain(heard)
        guard words.split(separator: " ").count <= 7 else { return nil }
        let away = ["stepping away", "i'm going out", "i am going out", "heading out", "i'm away", "i am away",
                    "away mode", "leaving the desk", "leaving my desk", "je m'absente", "je sors", "je pars"]
        let back = ["i'm back", "i am back", "back at my desk", "back at the desk", "away mode off",
                    "je suis de retour", "je suis revenu", "me revoila"]
        if back.contains(where: { words.contains($0) }) { return .back }
        if away.contains(where: { words.contains($0) }) { return .away }
        return nil
    }

    /// "Any questions waiting?", "read the questions" and the like.
    static func asksForQuestions(_ heard: String) -> Bool {
        let words = plain(heard)
        guard words.split(separator: " ").count <= 10 else { return false }
        return ["questions waiting", "waiting questions", "read the questions", "session questions",
                "sessions asking", "sessions waiting", "questions from my sessions", "questions en attente"]
            .contains { words.contains($0) }
    }

    // MARK: Reading a question out

    /// What Nestor says for one part of a question.
    static func readOut(_ question: DeskQuestion, part: Int) -> String {
        let p = question.parts[part]
        var said = "\(question.spokenName.prefix(1).uppercased() + question.spokenName.dropFirst()) asks: \(shortened(p.question))"
        if !said.hasSuffix("?") && !said.hasSuffix(".") { said += "." }
        if !p.options.isEmpty {
            let numbered = p.options.prefix(6).enumerated().map { "\(numberWords[$0.offset]), \($0.element)" }
            said += " Your choices: " + numbered.joined(separator: "; ") + "."
        }
        return said
    }

    /// The end of a long question: its last sentences, about 280 characters.
    static func shortened(_ text: String, limit: Int = 280) -> String {
        let flat = text.replacingOccurrences(of: "[*_`#>]", with: "", options: .regularExpression)
            .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard flat.count > limit else { return flat }
        let tail = String(flat.suffix(limit))
        // Start at a sentence boundary when there is one.
        if let cut = tail.range(of: #"[.!?]\s+"#, options: .regularExpression) {
            return String(tail[cut.upperBound...])
        }
        return tail
    }

    // MARK: Understanding the reply

    static let numberWords = ["one", "two", "three", "four", "five", "six"]
    private static let ordinals: [[String]] = [
        ["first", "one", "1", "premier", "premiere", "un", "une"],
        ["second", "two", "2", "deuxieme", "deux", "seconde"],
        ["third", "three", "3", "troisieme", "trois"],
        ["fourth", "four", "4", "quatrieme", "quatre"],
        ["fifth", "five", "5", "cinquieme", "cinq"],
        ["sixth", "six", "6", "sixieme"],
    ]

    static func interpret(_ heard: String, options: [String], multiSelect: Bool = false) -> Reply {
        let words = plain(heard)
        let tokens = words.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if wantsAgain(heard) { return .again }
        if ["skip", "next", "later", "not now", "pass", "passe", "plus tard", "suivant"].contains(where: { words == $0 || words.hasPrefix($0 + " ") }) {
            return .skip
        }
        if !options.isEmpty, tokens.count <= 6 {
            var picked: [String] = []
            for token in tokens {
                if let index = ordinals.firstIndex(where: { $0.contains(token) }), index < options.count,
                   !picked.contains(options[index]) {
                    picked.append(options[index])
                }
                if token == "last" || token == "dernier" || token == "derniere", let last = options.last { picked.append(last) }
            }
            if !picked.isEmpty { return .choice(multiSelect ? picked : [picked[0]]) }
        }
        let byLabel = options.filter { plain($0).count >= 3 && words.contains(plain($0)) }
        if !byLabel.isEmpty { return .choice(multiSelect ? byLabel : [byLabel[0]]) }
        return .text(heard.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func confirm(_ heard: String) -> Confirm? {
        let words = plain(heard)
        if wantsAgain(heard) { return .again }
        let no = ["no", "nope", "don't", "do not", "cancel", "wait", "stop", "non", "annule", "attends", "pas"]
        let yes = ["yes", "yeah", "yep", "yup", "yah", "ya", "yes please", "please", "send", "go", "go ahead", "do it",
                   "correct", "right", "that's right", "sure", "okay", "ok", "absolutely", "confirm", "confirmed",
                   "indeed", "affirmative", "fine", "perfect", "good", "oui", "vas y", "envoie", "d'accord", "ouais",
                   "c'est ca", "exactement", "parfait"]
        if no.contains(where: { words == $0 || words.hasPrefix($0 + " ") || words.hasPrefix($0 + ",") }) { return .no }
        if yes.contains(where: { words == $0 || words.hasPrefix($0 + " ") || words.hasPrefix($0 + ",") || words.contains(" " + $0) }) {
            return .yes
        }
        return nil
    }

    /// "I'll tell the brain session: Push them. Shall I send it?"
    static func confirmation(_ question: DeskQuestion, answer: String) -> String {
        "I'll tell \(question.spokenName): \(answer). Shall I send it?"
    }

    private static func plain(_ text: String) -> String {
        Phrases.plain(text).replacingOccurrences(of: ",", with: "")
    }
}
