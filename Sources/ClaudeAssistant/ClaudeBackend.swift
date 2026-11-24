import Foundation

/// Claude Code: `claude -p … --output-format json`. The one backend checked
/// end to end; the `briefing` skill lives in Claude's own skills folder.
struct ClaudeBackend: AgentBackend {
    let id = "claude"
    let displayName = "Claude Code"
    let binaryOverrideVariable = "CLAUDE_ASSISTANT_CLAUDE_BIN"
    let executableCandidates = [
        NSHomeDirectory() + "/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        NSHomeDirectory() + "/.npm-global/bin/claude",
        "/usr/bin/claude",
    ]

    /// `claude --model` takes an alias for the latest model of each size.
    let models = [
        ModelOption.cliDefault,
        ModelOption(id: "opus", name: "Opus"),
        ModelOption(id: "sonnet", name: "Sonnet"),
        ModelOption(id: "haiku", name: "Haiku"),
    ]

    /// The page needs the strongest model; a question about it does not.
    func defaultModel(for operation: Operation) -> String {
        operation == .refresh ? "opus" : "sonnet"
    }

    func refreshArguments(model: String) -> [String] {
        ["-p", "/briefing", "--output-format", "json"] + modelArguments(model)
    }

    func askArguments(question: String, continuing: Bool, model: String) -> [String] {
        var args = ["-p"]
        if continuing { args.append("--continue") }
        args += ["--output-format", "json"] + modelArguments(model) + [question]
        return args
    }

    private func modelArguments(_ model: String) -> [String] {
        model.isEmpty ? [] : ["--model", model]
    }

    func parse(_ output: ProcessOutput) -> RunReport {
        var report = RunReport()
        guard let json = JSONReading.object(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            report.text = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            report.isError = output.status != 0
            report.errorText = output.combined
            return report
        }
        report.text = (json["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        report.isError = (json["is_error"] as? Bool ?? false) || output.status != 0
        report.errorText = report.isError ? (report.text.isEmpty ? output.combined : report.text) : ""
        report.costUSD = json["total_cost_usd"] as? Double
        report.sessionID = json["session_id"] as? String
        report.durationMs = JSONReading.int(json["duration_ms"])
        report.turns = JSONReading.int(json["num_turns"])
        if let usage = json["usage"] as? [String: Any] {
            let input = JSONReading.int(usage["input_tokens"]) ?? 0
            let cacheWrite = JSONReading.int(usage["cache_creation_input_tokens"]) ?? 0
            let cacheRead = JSONReading.int(usage["cache_read_input_tokens"]) ?? 0
            report.inputTokens = input + cacheWrite + cacheRead
            report.outputTokens = JSONReading.int(usage["output_tokens"])
        }
        if let models = json["modelUsage"] as? [String: Any], let first = models.keys.sorted().first {
            report.model = first.replacingOccurrences(of: "[1m]", with: "")
        }
        if let denials = json["permission_denials"] as? [[String: Any]] {
            report.deniedTools = denials.compactMap { $0["tool_name"] as? String }
        }
        return report
    }
}
