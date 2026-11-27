import Foundation

/// Cuts an answer into sentences while it is still being written, so each
/// can be said as soon as it is whole.
final class SentenceCutter {
    private var pending = ""
    /// How many sentences it has handed out.
    private(set) var emitted = 0

    /// Takes the next piece of the answer; returns the sentences it completes.
    func add(_ piece: String) -> [String] {
        pending += piece
        var whole: [String] = []
        while let end = Self.boundary(in: pending) {
            let sentence = pending[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            pending = String(pending[end...])
            if !sentence.isEmpty {
                whole.append(sentence)
                emitted += 1
            }
        }
        return whole
    }

    /// What is left when the answer has ended.
    func finish() -> String? {
        let rest = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        pending = ""
        guard !rest.isEmpty else { return nil }
        emitted += 1
        return rest
    }

    /// A sentence shorter than this waits for the next one: "OK." alone
    /// would be said with a gap after it.
    static let shortest = 12

    private static let closers: Set<Character> = ["\"", "'", ")", "»", "”", "’"]
    /// Words that end in a full stop without ending a sentence.
    private static let abbreviations: Set<String> = ["mr", "mrs", "ms", "dr", "prof", "st", "vs", "etc", "eg", "ie",
                                                     "mme", "mlle", "no", "approx"]

    /// Where the first whole sentence of `text` ends, or nil when there is
    /// none yet. A line end always ends one. A full stop, question mark or
    /// exclamation mark ends one when white space follows it, so "3.5" and
    /// a sentence still being written are left alone.
    static func boundary(in text: String) -> String.Index? {
        var index = text.startIndex
        var length = 0
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "\n" { return next }
            if !character.isWhitespace { length += 1 }
            if ".!?…".contains(character), length >= shortest {
                var after = next
                while after < text.endIndex, closers.contains(text[after]) { after = text.index(after: after) }
                // The piece that says what follows has not come yet.
                guard after < text.endIndex else { return nil }
                if text[after].isWhitespace, !(character == "." && isInsideSentence(text[..<index])) {
                    return after
                }
            }
            index = next
        }
        return nil
    }

    /// Whether a full stop after `before` is part of a number, an initial
    /// or an abbreviation.
    private static func isInsideSentence(_ before: Substring) -> Bool {
        guard let last = before.last else { return true }
        if last.isNumber { return true }
        let word = String(before.reversed().prefix { $0.isLetter || $0 == "." }.reversed())
            .replacingOccurrences(of: ".", with: "").lowercased()
        return word.count == 1 || abbreviations.contains(word)
    }
}
