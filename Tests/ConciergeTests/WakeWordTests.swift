import Testing
@testable import Concierge

struct WakeWordTests {
    @Test func noNameGivesNothing() {
        #expect(CalledName.after("I booked the B12 appointment", name: "Nestor") == nil)
        #expect(CalledName.after("", name: "Nestor") == nil)
        // The old name no longer wakes it.
        #expect(CalledName.after("Concierge, what's on tomorrow?", name: "Nestor") == nil)
    }

    @Test func theNameAloneGivesAnEmptyQuestion() {
        #expect(CalledName.after("Nestor", name: "Nestor") == "")
        #expect(CalledName.after("Hey Nestor.", name: "Nestor") == "")
    }

    @Test func wordsAfterTheNameAreTheQuestion() {
        #expect(CalledName.after("Nestor, what's on tomorrow?", name: "Nestor") == "what's on tomorrow")
        #expect(CalledName.after("so anyway hey nestor did Declan reply", name: "Nestor") == "did Declan reply")
    }

    @Test func theLastMentionCounts() {
        #expect(CalledName.after("Nestor is good. Nestor, read my mail", name: "Nestor") == "read my mail")
    }

    @Test func theNameIsFoundHoweverTheRecogniserSpellsIt() {
        #expect(CalledName.after("Nester, show your face", name: "Nestor") == "show your face")
        #expect(CalledName.after("nest or what's on tomorrow", name: "Nestor") == "what's on tomorrow")
        // What the recogniser wrote on 2026-11-28 for "Nestor, Nestor, Nestor".
        #expect(CalledName.after("Leicester Leicester", name: "Nestor") == "")
        #expect(CalledName.after("Lester, what's on tomorrow", name: "Nestor") == "what's on tomorrow")
        // Only for this name: another name is not woken by Leicester.
        #expect(CalledName.after("Leicester", name: "Max") == nil)
    }

    @Test func wordsThatOnlyLookLikeTheNameDoNotWakeIt() {
        for sentence in ["the pastor called", "it is nested twice", "a jar of nectar", "the nest is empty", "Nestle rang"] {
            #expect(CalledName.after(sentence, name: "Nestor") == nil)
        }
        // A short name must be said exactly.
        #expect(CalledName.after("hello Mac", name: "Max") == nil)
        #expect(CalledName.after("hello Max", name: "Max") == "")
    }

    @Test func theAppListensForItsOwnName() {
        #expect(CalledName.after("\(Brand.name), what's on tomorrow?", name: Brand.name) == "what's on tomorrow")
    }

    @Test func anotherNameWorksTheSameWay() {
        #expect(CalledName.after("Concierge, what's on tomorrow?", name: "Concierge") == "what's on tomorrow")
    }
}

struct NameInConversationTests {
    @Test func theNameIsTakenOffTheEnds() {
        #expect(CalledName.removed(from: "Thanks, Nestor", name: "Nestor") == "Thanks")
        #expect(CalledName.removed(from: "Nestor, hide", name: "Nestor") == "hide")
        #expect(CalledName.removed(from: "what did Nestor say about Declan", name: "Nestor") == "what did Nestor say about Declan")
        // The name alone stays: there is nothing else to keep.
        #expect(CalledName.removed(from: "Nestor", name: "Nestor") == "Nestor")
    }

    @Test func aGoodbyeWithTheNameEndsTheConversation() {
        #expect(Conversation.isGoodbye(CalledName.removed(from: "Thanks, Nestor.", name: "Nestor")))
        #expect(Conversation.windowCommand(CalledName.removed(from: "Nestor, show your face", name: "Nestor")) == .show)
    }
}

struct WakeSettleTests {
    @Test func aShortTailWaitsLonger() {
        #expect(WakeListener.settleTime(after: "Watson") > WakeListener.settleTime(after: "what's on tomorrow then"))
        #expect(WakeListener.settleTime(after: "") == 2.0)
    }
}
