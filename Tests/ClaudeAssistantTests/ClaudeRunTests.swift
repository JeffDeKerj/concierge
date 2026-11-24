import Foundation
import Testing
@testable import ClaudeAssistant

extension SerialTests {
@Suite struct ClaudeRunTests {
    @Test @MainActor func refreshReloadsWhenTheFileChanges() async throws {
        try Fixture.reset()
        try Fixture.stubMode("write")
        let model = AppModel()
        #expect(model.page == nil)
        let tokenBefore = model.reloadToken

        model.refresh()
        #expect(model.isRefreshing)
        let done = await Fixture.wait { !model.isRefreshing }
        #expect(done)
        #expect(model.refreshError == nil)
        #expect(model.page?.isToday == true)
        #expect(model.notice == nil)
        #expect(model.reloadToken > tokenBefore)
    }

    @Test @MainActor func refreshReportsAFailedGenerator() async throws {
        try Fixture.reset()
        try Fixture.stubMode("fail")
        let model = AppModel()
        model.refresh()
        let done = await Fixture.wait { !model.isRefreshing }
        #expect(done)
        let error = try #require(model.refreshError)
        #expect(error.contains("status 1"))
        #expect(error.contains("Failed to authenticate: stub"))
        #expect(model.page == nil)
    }

    @Test @MainActor func refreshNoticesWhenNothingWasWritten() async throws {
        try Fixture.reset()
        try Fixture.stubMode("echo")
        let model = AppModel()
        model.refresh()
        let done = await Fixture.wait { !model.isRefreshing }
        #expect(done)
        #expect(model.refreshError == "The generator finished but did not write today's page.")
    }

    @Test @MainActor func askContinuesTheConversation() async throws {
        try Fixture.reset()
        try Fixture.stubMode("echo")
        let model = AppModel()
        model.question = "What is the deadline?"
        model.ask()
        #expect(model.isAsking)
        let done = await Fixture.wait { !model.isAsking }
        #expect(done)
        #expect(model.askError == nil)
        #expect(model.answer == "args: -p --continue --output-format text What is the deadline?")
        #expect(model.question.isEmpty)
    }

    @Test @MainActor func askFallsBackToAFreshConversation() async throws {
        try Fixture.reset()
        try Fixture.writePage("2026-11-22")
        try Fixture.stubMode("noconv")
        let model = AppModel()
        model.question = "Who sent it?"
        model.ask()
        let done = await Fixture.wait { !model.isAsking }
        #expect(done)
        #expect(model.askError == nil)
        let answer = try #require(model.answer)
        #expect(answer.hasPrefix("fallback: -p --output-format text Regarding the briefing page at "))
        #expect(answer.hasSuffix("/briefings/2026-11-22.html: Who sent it?"))
    }

    @Test @MainActor func emptyQuestionIsIgnored() throws {
        try Fixture.reset()
        let model = AppModel()
        model.question = "   "
        model.ask()
        #expect(!model.isAsking)
    }
}
}
