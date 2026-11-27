import Foundation
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
    /// Said in the new language once it has switched.
    var switched: String { self == .french ? "D'accord, en français." : "Okay, in English." }
    /// Added to the question so the model answers in this language.
    var answerRule: String { self == .french ? " Answer in French." : "" }
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
        let words = Phrases.plain(heard)
        guard words.split(separator: " ").count <= 6 else { return nil }
        let french = ["speak french", "in french", "talk french", "switch to french", "french please",
                      "parle francais", "en francais", "parlons francais"]
        let english = ["speak english", "in english", "talk english", "switch to english", "english please",
                       "parle anglais", "en anglais", "parlons anglais", "anglais s'il te plait"]
        if french.contains(where: { words.contains($0) }) { return .french }
        if english.contains(where: { words.contains($0) }) { return .english }
        return nil
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
