import Foundation
import NaturalLanguage
import Speech

/// The language the assistant listens and speaks in during a conversation.
/// The window and the morning page stay in English.
enum Language: String, CaseIterable, Identifiable {
    case english = "en"
    case french = "fr"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .english: "English"
        case .french: "Français"
        }
    }

    /// The locale speech recognition listens in.
    var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en-GB")
        case .french: Locale(identifier: "fr-FR")
        }
    }

    /// Whether this Mac can recognise the language by itself, without
    /// sending the sound to Apple. English can; French needs its files
    /// downloaded first, which Settings does.
    var isOnThisMac: Bool {
        SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false
    }

    // What it says by itself, outside the model's answers.

    /// After the wake word alone.
    var yes: String { self == .french ? "Oui ?" : "Yes?" }
    var hereIAm: String { self == .french ? "Me voilà." : "Here I am." }
    var okay: String { self == .french ? "D'accord." : "Okay." }
    var noAnswer: String {
        self == .french ? "Désolé, je n'ai pas eu de réponse." : "Sorry, I could not get an answer."
    }
    /// Said when an answer has not started after a few seconds.
    var letMeThink: String { self == .french ? "Laissez-moi réfléchir." : "Let me think." }
    /// Said, one after the other, while an answer goes on taking a while.
    var stillComing: [String] {
        self == .french
            ? ["J'y suis encore.", "Ça arrive.", "Encore un petit moment."]
            : ["Still on it.", "It's coming.", "Just a little longer."]
    }

    /// What it is doing, from the tool the agent started; nil for a tool
    /// not worth a word.
    func doing(_ tool: String) -> String? {
        let french = self == .french
        switch tool {
        case "WebSearch": return french ? "Je cherche." : "Searching for it."
        case "WebFetch": return french ? "Je le lis." : "Reading it now."
        case "Read", "Grep", "Glob": return french ? "Je regarde dans vos notes." : "Looking through your notes."
        case "Agent", "Task": return french ? "Je m'en occupe." : "Working on it."
        default:
            if tool.contains("Gmail") { return french ? "Je regarde vos mails." : "Checking your mail." }
            if tool.contains("Calendar") { return french ? "Je regarde l'agenda." : "Checking your calendar." }
            if tool.contains("whatsapp") { return french ? "Je regarde WhatsApp." : "Checking WhatsApp." }
            if tool.contains("Slack") { return french ? "Je regarde Slack." : "Checking Slack." }
            return nil
        }
    }
    /// Said when the owner has not gone on after an answer.
    var standingBy: String { self == .french ? "Je reste là si besoin." : "I'm here when you need me." }
    /// Said in the new language once it has switched.
    var switched: String { self == .french ? "D'accord, en français." : "Okay, in English." }
    /// Added to the question so the model answers in this language.
    /// Said for both languages: a conversation that began in French goes on
    /// in French unless it is told otherwise, even after a switch.
    var answerRule: String {
        self == .french
            ? " Answer in French, unless the owner asks for another language."
            : " Answer in English, unless the owner asks for another language."
    }
    /// For the Test button in Settings.
    var sample: String {
        self == .french
            ? "Bonjour. Stéphane pose une question sur les essais de mutation du groupe MIT."
            : "Good morning. Stephane asks about the mutation assays in the MIT group."
    }

    /// Said, in English, when French is asked for and cannot be used.
    static let frenchMissing = "French is not on this Mac yet. Open my settings and press Download French. Or allow Apple's servers for French there."

    /// "Speak French", "parle anglais" and the like: the language asked
    /// for, or nil. A switch to French has to be said in English, and a
    /// switch back in French, because that is the language being listened
    /// for at that moment.
    static func asked(in heard: String) -> Language? {
        // The listener puts commas where it pauses: "Speak, English".
        let words = Phrases.plain(heard).components(separatedBy: CharacterSet.letters.union(.init(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
        let count = words.split(separator: " ").count
        guard count <= 6 else { return nil }
        // One or two words alone is a request too: "Anglais !", "English please".
        if count <= 2, ["english", "anglais", "inglish"].contains(where: { words.hasPrefix($0) }) { return .english }
        if count <= 2, ["french", "francais"].contains(where: { words.hasPrefix($0) }) { return .french }
        let french = ["speak french", "in french", "talk french", "switch to french", "french please",
                      "speak in french", "parle francais", "en francais", "parlons francais", "parle en francais",
                      "passe en francais", "parler francais"]
        let english = ["speak english", "in english", "talk english", "switch to english", "english please",
                       "speak in english", "parle anglais", "en anglais", "parlons anglais", "parle en anglais",
                       "passe en anglais", "parler anglais", "anglais s'il te plait", "speak inglish", "in inglish"]
        if french.contains(where: { words.contains($0) }) { return .french }
        if english.contains(where: { words.contains($0) }) { return .english }
        return nil
    }

    /// The language a piece of text is written in, when it is clearly one
    /// of the two: a voice must never read English with a French accent.
    /// Nil for a few words or a mix, where the conversation's own language
    /// is the better guess.
    static func of(_ text: String) -> Language? {
        guard text.split(separator: " ").count >= 3 else { return nil }
        let recogniser = NLLanguageRecognizer()
        recogniser.languageConstraints = [.english, .french]
        recogniser.processString(text)
        guard let (best, chance) = recogniser.languageHypotheses(withMaximum: 1).first, chance >= 0.8 else { return nil }
        return best == .french ? .french : .english
    }
}

/// Getting heard words into a plain shape for matching against known phrases.
enum Phrases {
    /// Lower case, no accents, straight apostrophes, hyphens as spaces, and
    /// no punctuation or space at the ends: "Montre-toi !" is "montre toi".
    static func plain(_ heard: String) -> String {
        heard.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }
}
