import Testing
@testable import Concierge

struct MicrophoneTests {
    @Test func theMacsChoiceNamesNoDevice() {
        #expect(Microphone.device(for: Microphone.system) == nil)
        #expect(Microphone.device(for: "something else") == nil)
        #expect(ConciergeSettings().microphone == Microphone.system)
    }

    /// On a Mac with a microphone of its own (a laptop), it is found and has a name.
    @Test func theMacsOwnMicrophoneIsFoundWhenThereIsOne() {
        guard let own = Microphone.builtInInput() else { return }
        #expect(Microphone.devices().contains(own))
        #expect(Microphone.device(for: Microphone.builtIn) == own)
        #expect(Microphone.name(of: own)?.isEmpty == false)
    }
}
