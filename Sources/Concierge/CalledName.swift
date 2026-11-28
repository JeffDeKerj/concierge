import Foundation

/// What the owner calls the assistant, in everything they see or say. The
/// code, the app file, the repository and the skills keep the working name
/// Concierge; `Scripts/make_app.sh` and `Scripts/tick.py` carry the same
/// name for the menu bar and the notifications.
enum Brand {
    static let name = "Nestor"
}

/// Finding the name in what was heard. Said aloud, it is the wake word.
enum CalledName {
    /// Whether a heard word is the name. The recogniser does not always
    /// spell a name the same way ("Nestor", "Nester"), so a name of five
    /// letters or more also matches with one letter different.
    static func matches(_ word: String, name: String) -> Bool {
        let heard = letters(word), wanted = letters(name)
        guard !wanted.isEmpty else { return false }
        if heard == wanted { return true }
        if soundsLike[String(wanted)]?.contains(String(heard)) == true { return true }
        return wanted.count >= 5 && distance(heard, wanted) <= 1
    }

    /// What may come before the name in a call: "hey", and how the
    /// recogniser writes it without the h, as a French speaker says it ("ey").
    /// Not "a": "a pastor" would wake it.
    static let callWords: Set<String> = ["hey", "hay", "ey", "eh", "ay", "hi", "hej"]

    /// Two letters off at most, for a name of five letters or more.
    private static func close(_ word: String, name: String) -> Bool {
        let wanted = letters(name)
        return wanted.count >= 5 && distance(letters(word), wanted, limit: 2) <= 2
    }

    /// What the English recogniser writes for a name it does not know, too
    /// far from the spelling to match by one letter. Seen on 2026-11-28:
    /// "Nestor, Nestor, Nestor" came out as "Nestor Leicester Leicester".
    static let soundsLike: [String: Set<String>] = [
        "nestor": ["leicester", "lester", "nesta"],
    ]

    /// The words after the name, or nil when the name was not said. The
    /// last mention counts: earlier ones were part of other talk.
    static func after(_ text: String, name: String) -> String? {
        let words = words(in: text)
        var last: String.Index?
        for (i, word) in words.enumerated() {
            if matches(word.text, name: name) {
                last = word.range.upperBound
            } else if i > 0, callWords.contains(String(letters(words[i - 1].text))), close(word.text, name: name) {
                // "Hey Nestor": after "hey", a name two letters off still counts.
                last = word.range.upperBound
            } else if i + 1 < words.count, matches(word.text + words[i + 1].text, name: name) {
                // Heard in two pieces: "nest or".
                last = words[i + 1].range.upperBound
            }
        }
        guard let last else { return nil }
        return text[last...].trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }

    /// What was said without the name at its start or end: "thanks, Nestor"
    /// is "thanks", so the name does not hide a goodbye or a command.
    static func removed(from text: String, name: String) -> String {
        var words = words(in: text)
        guard words.count > 1 else { return text }
        if let first = words.first, matches(first.text, name: name) { words.removeFirst() }
        if words.count > 1, let last = words.last, matches(last.text, name: name) { words.removeLast() }
        guard let first = words.first, let last = words.last else { return text }
        return text[first.range.lowerBound..<last.range.upperBound]
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }

    private static func words(in text: String) -> [(text: String, range: Range<String.Index>)] {
        var found: [(String, Range<String.Index>)] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { word, range, _, _ in
            if let word { found.append((word, range)) }
        }
        return found
    }

    private static func letters(_ text: String) -> [Character] {
        Array(text.lowercased().filter(\.isLetter))
    }

    /// How many letters must be changed, added or dropped to turn one word into the other.
    private static func distance(_ a: [Character], _ b: [Character], limit: Int = 1) -> Int {
        if abs(a.count - b.count) > limit { return limit + 1 }
        var row = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var previous = row[0]
            row[0] = i + 1
            for (j, y) in b.enumerated() {
                let above = row[j + 1]
                row[j + 1] = min(previous + (x == y ? 0 : 1), above + 1, row[j] + 1)
                previous = above
            }
        }
        return row[b.count]
    }
}
