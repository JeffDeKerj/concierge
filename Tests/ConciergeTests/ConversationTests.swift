import Testing
@testable import Concierge

struct ConversationTests {
    @Test(arguments: ["Thanks.", "thank you", "No thanks, that's fine", "Stop", "That's all.", "Not now"])
    func endsTheConversation(_ said: String) {
        #expect(Conversation.isGoodbye(said))
    }

    @Test(arguments: ["Thanks, and what did Declan say about the return?", "No, the other one",
                      "What is on my calendar today?", "Stop the reminder for B12 and tell me more"])
    func keepsTalking(_ said: String) {
        #expect(!Conversation.isGoodbye(said))
    }

    @Test func spokenPromptAsksForAShortAnswerAndCarriesTheAlert() {
        let p = Conversation.spokenPrompt("Draft a reply", context: "Stephane asks about assays")
        #expect(p.contains("short spoken sentences"))
        #expect(p.contains("never send"))
        #expect(p.contains("About this alert: Stephane asks about assays."))
        #expect(p.hasSuffix("Draft a reply"))
        #expect(!Conversation.spokenPrompt("Hi", context: nil).contains("About this alert"))
    }
}
