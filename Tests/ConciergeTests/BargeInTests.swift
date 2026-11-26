import Testing
@testable import Concierge

struct BargeInTests {
    let sentence = "Stephane asks whether the mutation data is the Ames test or gene mutation in mammalian cells."

    @Test func itsOwnVoiceLeakingBackIsNotAnInterruption() {
        #expect(!VoiceIO.isBargeIn(heard: "", speaking: sentence))
        #expect(!VoiceIO.isBargeIn(heard: "the mutation data", speaking: sentence))
        #expect(!VoiceIO.isBargeIn(heard: "Ames test or gene", speaking: sentence))
        #expect(!VoiceIO.isBargeIn(heard: "Stephane", speaking: sentence))
    }

    @Test func theOwnerTalkingIsAnInterruption() {
        #expect(VoiceIO.isBargeIn(heard: "Wait, what about Declan", speaking: sentence))
        #expect(VoiceIO.isBargeIn(heard: "Draft a reply", speaking: sentence))
        #expect(VoiceIO.isBargeIn(heard: "Stop", speaking: sentence))
        #expect(VoiceIO.isBargeIn(heard: "hold on", speaking: sentence))
    }

    @Test func aWordThatIsAlsoBeingSaidDoesNotInterruptAlone() {
        #expect(!VoiceIO.isBargeIn(heard: "stop", speaking: "Shall I stop the reminder?"))
    }
}
