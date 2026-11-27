import Testing
@testable import Concierge

struct SentenceCutterTests {
    @Test func cutsWhenASentenceIsWholeAndWhatFollowsIsKnown() {
        let cutter = SentenceCutter()
        #expect(cutter.add("You have two meetings") == [])
        #expect(cutter.add(" tomorrow.") == [])
        #expect(cutter.add(" The first is at nine") == ["You have two meetings tomorrow."])
        #expect(cutter.add(". Shall I say more? Or") == ["The first is at nine.", "Shall I say more?"])
        #expect(cutter.finish() == "Or")
        #expect(cutter.finish() == nil)
        #expect(cutter.emitted == 4)
    }

    @Test func leavesNumbersInitialsAndAbbreviationsWhole() {
        let cutter = SentenceCutter()
        #expect(cutter.add("The bill is 3.5 pounds more than at no. 12 last year. ") == ["The bill is 3.5 pounds more than at no. 12 last year."])
        #expect(cutter.add("Then Dr. Smith and J. Marsh wrote to you today. ") == ["Then Dr. Smith and J. Marsh wrote to you today."])
        #expect(cutter.add("Le rendez-vous avec Mme. Durand est à 15 heures. ") == ["Le rendez-vous avec Mme. Durand est à 15 heures."])
    }

    @Test func aShortSentenceWaitsForTheNext() {
        let cutter = SentenceCutter()
        #expect(cutter.add("Yes. Declan asked for the report by Friday. ") == ["Yes. Declan asked for the report by Friday."])
        #expect(cutter.add("OK.") == [])
        #expect(cutter.finish() == "OK.")
    }

    @Test func aLineEndAlwaysCuts() {
        let cutter = SentenceCutter()
        #expect(cutter.add("\nLet me check\nIt is at nine \u{201C}sharp.\u{201D} Then") == ["Let me check", "It is at nine \u{201C}sharp.\u{201D}"])
        #expect(cutter.emitted == 2)
    }
}
