import Foundation

/// Antigravity's CLI, `agy`, whose print mode mirrors Claude's flags:
/// `agy -p … --output-format json` answers with `response`, `status`,
/// `duration_seconds`, `num_turns` and `usage` (checked 2026-11-24). It
/// reports no price and no model. Refresh has not yet been run through it.
struct AntigravityBackend: AgentBackend {
    let id = "antigravity"
    let displayName = "Antigravity"
    let binaryOverrideVariable = "CLAUDE_ASSISTANT_AGY_BIN"
    let executableCandidates = [
        "/opt/homebrew/bin/agy",
        "/usr/local/bin/agy",
        NSHomeDirectory() + "/.local/bin/agy",
    ]

    func refreshArguments() -> [String] {
        ["-p", Paths.briefingInstructions, "--output-format", "json", "--mode", "accept-edits"]
    }

    func askArguments(question: String, continuing: Bool) -> [String] {
        var args = ["-p", question, "--output-format", "json"]
        if continuing { args.append("--continue") }
        return args
    }

    func parse(_ output: ProcessOutput) -> RunReport {
        var report = RunReport()
        guard let json = JSONReading.object(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            report.text = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            report.isError = output.status != 0
            report.errorText = output.combined
            return report
        }
        report.text = (json["response"] as? String ?? json["result"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let status = json["status"] as? String ?? "success"
        report.isError = output.status != 0 || (json["is_error"] as? Bool ?? false) || status.lowercased() != "success"
        report.errorText = report.isError ? (report.text.isEmpty ? output.combined : report.text) : ""
        report.costUSD = json["total_cost_usd"] as? Double
        if let ms = JSONReading.int(json["duration_ms"]) {
            report.durationMs = ms
        } else if let seconds = json["duration_seconds"] as? Double {
            report.durationMs = Int(seconds * 1000)
        }
        report.turns = JSONReading.int(json["num_turns"])
        if let usage = json["usage"] as? [String: Any] {
            let input = JSONReading.int(usage["input_tokens"]) ?? 0
            let cached = JSONReading.int(usage["cache_read_tokens"]) ?? 0
            report.inputTokens = input + cached
            report.outputTokens = JSONReading.int(usage["output_tokens"])
        }
        report.model = json["model"] as? String
        return report
    }
}
