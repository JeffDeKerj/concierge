import Foundation
import Testing
@testable import Concierge

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
        let report = try #require(model.lastRefresh)
        #expect(report.text == "Wrote the page.")
        #expect(report.summary == "$0.01 · 1 s · 5.1k in, 50 out · 3 turns · claude-opus-5-5")
        #expect(model.today.runs == 1)
        #expect(abs(model.today.costUSD - 0.0125) < 0.0001)
    }

    @Test @MainActor func refreshReportsRefusedTools() async throws {
        try Fixture.reset()
        try Fixture.stubMode("denied")
        let model = AppModel()
        model.refresh()
        let done = await Fixture.wait { !model.isRefreshing }
        #expect(done)
        let error = try #require(model.refreshError)
        #expect(error.contains("mcp__claude_ai_Gmail__search_threads"))
    }

    @Test @MainActor func refreshReportsAFailedGenerator() async throws {
        try Fixture.reset()
        try Fixture.stubMode("fail")
        let model = AppModel()
        model.refresh()
        let done = await Fixture.wait { !model.isRefreshing }
        #expect(done)
        let error = try #require(model.refreshError)
        #expect(error.hasPrefix("Claude Code failed:"))
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
        #expect(model.refreshError == "The generator finished but did not write today's page. It said: args: -p /briefing --output-format json --model opus")
    }

    @Test @MainActor func askStartsItsOwnConversationAndResumesIt() async throws {
        try Fixture.reset()
        try Fixture.writePage(BriefingLocator.today(), body: "<style>b{}</style><h2>Urgent</h2><ul><li>Reply to <b>Declan</b> &amp; Ana</li></ul>")
        try Fixture.stubMode("echo")
        let model = AppModel()
        model.question = "What is the deadline?"
        model.ask()
        #expect(model.isAsking)
        #expect(await Fixture.wait { !model.isAsking })
        #expect(model.askError == nil)
        let first = try #require(model.answer)
        // A conversation of its own, named by the app, told the page as words.
        #expect(first.hasPrefix("args: -p --session-id "))
        #expect(!first.contains("--continue"))
        #expect(first.contains("Urgent\nReply to Declan & Ana"))
        #expect(!first.contains("<li>"))
        #expect(first.hasSuffix("The question: What is the deadline?"))
        #expect(model.question.isEmpty)
        let report = try #require(model.lastAsk)
        #expect(report.costUSD == 0.0125)
        #expect(report.inputTokens == 5100)
        #expect(model.today.runs == 1)
        #expect(AskSessionStore().load()?.id == "stub-session")

        // The next question goes to the same conversation, with only its own words.
        model.question = "And who asked?"
        model.ask()
        #expect(await Fixture.wait { !model.isAsking })
        #expect(model.answer == "args: -p --resume stub-session --output-format json --model sonnet And who asked?")
    }

    @Test @MainActor func aRebuiltPageStartsANewConversation() async throws {
        try Fixture.reset()
        try Fixture.writePage(BriefingLocator.today())
        try Fixture.stubMode("echo")
        let model = AppModel()
        AskSessionStore().save(AskSession(id: "old", day: BriefingLocator.today(), backend: "claude", pageStamp: 1))
        model.question = "Anything new?"
        model.ask()
        #expect(await Fixture.wait { !model.isAsking })
        #expect(try #require(model.answer).hasPrefix("args: -p --session-id "))
    }

    @Test @MainActor func newUpdatesAreToldToARunningConversation() async throws {
        try Fixture.reset()
        try Fixture.writePage(BriefingLocator.today())
        try Fixture.stubMode("echo")
        let model = AppModel()
        model.question = "First"
        model.ask()
        #expect(await Fixture.wait { !model.isAsking })
        let updates = Updates.url(for: BriefingLocator.today())
        try FileManager.default.createDirectory(at: updates.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"[{"kind":"check","title":"Ana wrote"}]"#.write(to: updates, atomically: true, encoding: .utf8)
        model.question = "Second"
        model.ask()
        #expect(await Fixture.wait { !model.isAsking })
        let answer = try #require(model.answer)
        #expect(answer.hasPrefix("args: -p --resume stub-session --output-format json --model sonnet (Found since the page was written"))
        #expect(answer.contains("Ana wrote"))
        #expect(answer.hasSuffix("Second"))
        // Told once: the third question carries only its own words.
        model.question = "Third"
        model.ask()
        #expect(await Fixture.wait { !model.isAsking })
        #expect(model.answer == "args: -p --resume stub-session --output-format json --model sonnet Third")
    }

    @Test @MainActor func askFallsBackToAFreshConversation() async throws {
        try Fixture.reset()
        try Fixture.writePage("2026-11-22")
        try Fixture.stubMode("noconv")
        let model = AppModel()
        let stamp = try #require(model.page?.modificationDate?.timeIntervalSince1970)
        // A conversation the tool no longer has.
        AskSessionStore().save(AskSession(id: "gone", day: BriefingLocator.today(), backend: "claude", pageStamp: stamp))
        model.question = "Who sent it?"
        model.ask()
        #expect(await Fixture.wait { !model.isAsking })
        #expect(model.askError == nil)
        let answer = try #require(model.answer)
        #expect(answer.hasPrefix("fallback: -p --session-id "))
        #expect(answer.contains("/briefings/2026-11-22.html"))
        #expect(answer.hasSuffix("The question: Who sent it?"))
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
