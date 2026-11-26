import Testing
@testable import Concierge

struct WakeWordTests {
    @Test func noWakeWordGivesNothing() {
        #expect(WakeListener.afterWakeWord("I booked the B12 appointment") == nil)
        #expect(WakeListener.afterWakeWord("") == nil)
    }

    @Test func wakeWordAloneGivesAnEmptyQuestion() {
        #expect(WakeListener.afterWakeWord("Concierge") == "")
        #expect(WakeListener.afterWakeWord("Hey Concierge.") == "")
    }

    @Test func wordsAfterTheWakeWordAreTheQuestion() {
        #expect(WakeListener.afterWakeWord("Concierge, what's on tomorrow?") == "what's on tomorrow")
        #expect(WakeListener.afterWakeWord("so anyway hey concierge did Declan reply") == "did Declan reply")
    }

    @Test func theLastWakeWordCounts() {
        #expect(WakeListener.afterWakeWord("the Concierge app is good. Concierge, read my mail") == "read my mail")
    }
}
