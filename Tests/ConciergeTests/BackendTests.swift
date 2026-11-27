import Foundation
import Testing
@testable import Concierge

/// `modelChoiceIsSavedPerBackend` writes the saved model choices, which the
/// app-model suites reset, so this suite runs one at a time with them.
extension SerialTests {
@Suite struct BackendTests {
    @Test func claudeReadsCostTokensModelAndDenials() {
        let json = """
        {"type":"result","is_error":false,"duration_ms":192000,"num_turns":41,"result":"Written.","session_id":"abc",
         "total_cost_usd":1.2345,"usage":{"input_tokens":12,"cache_creation_input_tokens":30000,
         "cache_read_input_tokens":500000,"output_tokens":4100},"modelUsage":{"claude-opus-5-5[1m]":{}},
         "permission_denials":[{"tool_name":"Bash","tool_use_id":"a","tool_input":{}}]}
        """
        let report = ClaudeBackend().parse(ProcessOutput(status: 0, stdout: json, stderr: ""))
        #expect(report.text == "Written.")
        #expect(!report.isError)
        #expect(report.costUSD == 1.2345)
        #expect(report.durationMs == 192000)
        #expect(report.turns == 41)
        #expect(report.inputTokens == 530012)
        #expect(report.outputTokens == 4100)
        #expect(report.model == "claude-opus-5-5")
        #expect(report.deniedTools == ["Bash"])
        #expect(report.sessionID == "abc")
        #expect(report.summary == "$1.23 · 3 min 12 s · 530k in, 4.1k out · 41 turns · claude-opus-5-5")
    }

    @Test func claudeFallsBackToPlainTextOnBadJSON() {
        let report = ClaudeBackend().parse(ProcessOutput(status: 1, stdout: "", stderr: "No conversation found to continue"))
        #expect(report.isError)
        #expect(ClaudeBackend().isNoConversation(report))
        #expect(report.costUSD == nil)
    }

    @Test func claudeArguments() {
        let b = ClaudeBackend()
        #expect(b.refreshArguments() == ["-p", "/briefing", "--output-format", "json"])
        #expect(b.refreshArguments(model: "opus") == ["-p", "/briefing", "--output-format", "json", "--model", "opus"])
        #expect(b.askArguments(question: "Why?", continuing: true) == ["-p", "--continue", "--output-format", "json", "Why?"])
        #expect(b.askArguments(question: "Why?", continuing: false, model: "sonnet") == ["-p", "--output-format", "json", "--model", "sonnet", "Why?"])
        #expect(b.defaultModel(for: .refresh) == "opus")
        #expect(b.defaultModel(for: .ask) == "sonnet")
        #expect(b.models.first == .cliDefault)
    }

    @Test func modelChoiceIsSavedPerBackend() {
        ModelSettings.reset()
        let claude = ClaudeBackend()
        let agy = AntigravityBackend()
        #expect(ModelSettings.model(for: .refresh, backend: claude) == "opus")
        #expect(ModelSettings.model(for: .ask, backend: agy) == "")
        ModelSettings.set("haiku", for: .ask, backend: claude)
        ModelSettings.set("gemini-4-neon-low", for: .ask, backend: agy)
        #expect(ModelSettings.model(for: .ask, backend: claude) == "haiku")
        #expect(ModelSettings.model(for: .ask, backend: agy) == "gemini-4-neon-low")
        // A saved id the backend no longer lists falls back to the default.
        ModelSettings.set("gone", for: .refresh, backend: claude)
        #expect(ModelSettings.model(for: .refresh, backend: claude) == "opus")
        #expect(CodexBackend().models == [.cliDefault])
        #expect(CodexBackend().refreshArguments(model: "x").prefix(6) == ["exec", "--json", "--sandbox", "workspace-write", "-m", "x"])
        #expect(AntigravityBackend().askArguments(question: "Q", continuing: false, model: "m") == ["-p", "Q", "--output-format", "json", "--model", "m"])
        ModelSettings.reset()
    }

    @Test func antigravityReadsTheResponseField() {
        let json = #"{"conversation_id":"c1","status":"SUCCESS","duration_seconds":3.4,"num_turns":1,"response":"Hello.\n","usage":{"input_tokens":26810,"output_tokens":25,"thinking_tokens":23,"cache_read_tokens":190,"total_tokens":26835}}"#
        let report = AntigravityBackend().parse(ProcessOutput(status: 0, stdout: json, stderr: ""))
        #expect(report.text == "Hello.")
        #expect(!report.isError)
        #expect(report.durationMs == 3400)
        #expect(report.turns == 1)
        #expect(report.inputTokens == 27000)
        #expect(report.outputTokens == 25)
        #expect(report.costUSD == nil)
        #expect(report.model == nil)
        let failed = AntigravityBackend().parse(ProcessOutput(status: 0, stdout: #"{"status":"error","response":"Quota."}"#, stderr: ""))
        #expect(failed.isError)
        #expect(failed.errorText == "Quota.")
        #expect(AntigravityBackend().askArguments(question: "Q", continuing: true) == ["-p", "Q", "--output-format", "json", "--continue"])
    }

    @Test func codexReadsTheLastMessageAndTokens() {
        let lines = """
        {"type":"thread.started","thread_id":"t1"}
        {"type":"item.completed","item":{"type":"agent_message","text":"First."}}
        {"type":"item.completed","item":{"type":"agent_message","text":"Last."}}
        {"type":"turn.completed","usage":{"input_tokens":900,"cached_input_tokens":100,"output_tokens":42}}
        """
        let report = CodexBackend().parse(ProcessOutput(status: 0, stdout: lines, stderr: ""))
        #expect(report.text == "Last.")
        #expect(report.inputTokens == 1000)
        #expect(report.outputTokens == 42)
        #expect(!report.isError)
        #expect(CodexBackend().askArguments(question: "Q", continuing: true) == ["exec", "resume", "--last", "--json", "Q"])
    }

    @Test func backendLookupFallsBackToClaude() {
        #expect(AgentBackends.named("codex").id == "codex")
        #expect(AgentBackends.named("nonsense").id == "claude")
        #expect(AgentBackends.all.map(\.id) == ["claude", "codex", "antigravity"])
    }

    @Test func summaryFormatting() {
        #expect(RunReport.duration(ms: 8400) == "8 s")
        #expect(RunReport.duration(ms: 61000) == "1 min 1 s")
        #expect(RunReport.count(999) == "999")
        #expect(RunReport.count(52000) == "52k")
        #expect(RunReport.count(4150) == "4.2k")
        #expect(RunReport.count(530012) == "530k")
        #expect(RunReport().summary == "")
    }
}
}
