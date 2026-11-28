import Foundation

/// Claude Code: `claude -p … --output-format json`. The one backend checked
/// end to end; the `briefing` skill lives in Claude's own skills folder.
struct ClaudeBackend: AgentBackend {
    let id = "claude"
    let displayName = "Claude Code"
    let binaryOverrideVariable = "CONCIERGE_CLAUDE_BIN"
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

    /// The app names the conversation, so a question never lands in a page
    /// build or a check that happens to be the newest in the folder.
    func askArguments(question: String, conversation: AskConversation, model: String) -> [String] {
        var args = ["-p"]
        switch conversation {
        case .fresh(let id): args += ["--session-id", id]
        case .resume(let id): args += ["--resume", id]
        }
        return args + ["--output-format", "json"] + modelArguments(model) + [question]
    }

    /// `stream-json` with partial messages sends the answer word by word,
    /// then the same report as `json` on the last line.
    func streamingAskArguments(question: String, conversation: AskConversation, model: String) -> [String]? {
        var args = askArguments(question: question, conversation: conversation, model: model)
        guard let format = args.firstIndex(of: "json") else { return nil }
        args.replaceSubrange(format...format, with: ["stream-json", "--verbose", "--include-partial-messages"])
        return args
    }

    func textDelta(inLine line: String) -> String? {
        guard line.contains("\"stream_event\""), let json = JSONReading.object(line),
              json["type"] as? String == "stream_event", let event = json["event"] as? [String: Any],
              // A helper agent's words are not the answer.
              json["parent_tool_use_id"] == nil || json["parent_tool_use_id"] is NSNull else { return nil }
        switch event["type"] as? String {
        case "message_start":
            // Words before and after a tool call are separate sentences.
            return "\n"
        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta" else { return nil }
            return delta["text"] as? String
        default:
            return nil
        }
    }

    /// A tool call opening, the agent's own or a helper's: both are work
    /// the owner is waiting on.
    func toolStarted(inLine line: String) -> String? {
        guard line.contains("\"tool_use\""), line.contains("content_block_start"), let json = JSONReading.object(line),
              json["type"] as? String == "stream_event", let event = json["event"] as? [String: Any],
              event["type"] as? String == "content_block_start",
              let block = event["content_block"] as? [String: Any], block["type"] as? String == "tool_use" else { return nil }
        return block["name"] as? String
    }

    private func modelArguments(_ model: String) -> [String] {
        model.isEmpty ? [] : ["--model", model]
    }

    func parse(_ output: ProcessOutput) -> RunReport {
        var report = RunReport()
        // One object, or with streaming one object per line with the report last.
        guard let json = JSONReading.object(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? JSONReading.lines(output.stdout).last(where: { $0["type"] as? String == "result" }) else {
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
