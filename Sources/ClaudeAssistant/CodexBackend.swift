import Foundation

/// OpenAI Codex: `codex exec --json …` prints one JSON event per line; the
/// reply is the last `agent_message` item and the tokens come from the
/// `turn.completed` event. Codex reports no price. Not yet run from the app.
struct CodexBackend: AgentBackend {
    let id = "codex"
    let displayName = "Codex"
    let binaryOverrideVariable = "CLAUDE_ASSISTANT_CODEX_BIN"
    let executableCandidates = [
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
        NSHomeDirectory() + "/.local/bin/codex",
    ]

    func refreshArguments() -> [String] {
        ["exec", "--json", "--sandbox", "workspace-write", Paths.briefingInstructions]
    }

    func askArguments(question: String, continuing: Bool) -> [String] {
        if continuing { return ["exec", "resume", "--last", "--json", question] }
        return ["exec", "--json", question]
    }

    func parse(_ output: ProcessOutput) -> RunReport {
        var report = RunReport()
        let events = JSONReading.lines(output.stdout)
        guard !events.isEmpty else {
            report.text = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            report.isError = output.status != 0
            report.errorText = output.combined
            return report
        }
        for event in events {
            let type = event["type"] as? String ?? ""
            if type == "item.completed", let item = event["item"] as? [String: Any],
               item["type"] as? String == "agent_message", let text = item["text"] as? String {
                report.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if type == "turn.completed", let usage = event["usage"] as? [String: Any] {
                let input = JSONReading.int(usage["input_tokens"]) ?? 0
                let cached = JSONReading.int(usage["cached_input_tokens"]) ?? 0
                report.inputTokens = input + cached
                report.outputTokens = JSONReading.int(usage["output_tokens"])
            }
            if type == "error" || type == "turn.failed" {
                report.isError = true
                report.errorText = event["message"] as? String
                    ?? (event["error"] as? [String: Any])?["message"] as? String
                    ?? output.combined
            }
        }
        if output.status != 0 {
            report.isError = true
            if report.errorText.isEmpty { report.errorText = output.combined }
        }
        return report
    }

    func isNoConversation(_ report: RunReport) -> Bool {
        report.isError && (report.errorText.localizedCaseInsensitiveContains("no session")
            || report.errorText.localizedCaseInsensitiveContains("no conversation")
            || report.errorText.localizedCaseInsensitiveContains("not found"))
    }
}
