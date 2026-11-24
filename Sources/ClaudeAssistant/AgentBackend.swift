import Foundation

/// What one headless run came back with. Every backend fills what it can;
/// cost and tokens stay nil when the tool does not report them.
struct RunReport: Equatable {
    /// The reply text, or the final message.
    var text: String = ""
    var isError = false
    /// What to show when the run failed.
    var errorText: String = ""
    /// The API price of the run in US dollars. On a subscription nothing is
    /// billed; this is what the same calls would have cost at API prices.
    var costUSD: Double?
    var durationMs: Int?
    var turns: Int?
    /// Input tokens of every kind: fresh, cache writes and cache reads.
    var inputTokens: Int?
    var outputTokens: Int?
    var model: String?
    /// Tools the run wanted and was refused.
    var deniedTools: [String] = []

    /// "$0.41 · 3 min 12 s · 52k in, 4k out · claude-opus-5-5"
    var summary: String {
        var parts: [String] = []
        if let costUSD { parts.append(String(format: "$%.2f", costUSD)) }
        if let durationMs { parts.append(Self.duration(ms: durationMs)) }
        if inputTokens != nil || outputTokens != nil {
            parts.append("\(Self.count(inputTokens)) in, \(Self.count(outputTokens)) out")
        }
        if let turns { parts.append(turns == 1 ? "1 turn" : "\(turns) turns") }
        if let model { parts.append(model) }
        return parts.joined(separator: " · ")
    }

    static func duration(ms: Int) -> String {
        let s = ms / 1000
        if s < 60 { return "\(s) s" }
        return "\(s / 60) min \(s % 60) s"
    }

    static func count(_ n: Int?) -> String {
        guard let n else { return "?" }
        if n < 1000 { return "\(n)" }
        if n < 100_000 { return String(format: "%.1fk", Double(n) / 1000).replacingOccurrences(of: ".0k", with: "k") }
        return "\(n / 1000)k"
    }
}

/// A headless agent CLI the app can drive: how to call it and how to read
/// what it prints. One type per tool; `AgentBackends.all` lists them.
protocol AgentBackend {
    /// Stable key, used in settings and the run log.
    var id: String { get }
    var displayName: String { get }
    /// Environment variable that names the binary to use instead of the installed one.
    var binaryOverrideVariable: String { get }
    /// Where the binary is usually installed, in order of preference.
    var executableCandidates: [String] { get }
    /// Arguments that build today's briefing page.
    func refreshArguments() -> [String]
    /// Arguments for a follow-up; `continuing` resumes the latest conversation in the folder.
    func askArguments(question: String, continuing: Bool) -> [String]
    /// Read the process output into a report.
    func parse(_ output: ProcessOutput) -> RunReport
    /// True when the failure means there is no conversation to continue.
    func isNoConversation(_ report: RunReport) -> Bool
}

extension AgentBackend {
    var executable: URL? {
        if let path = ProcessInfo.processInfo.environment[binaryOverrideVariable], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        for p in executableCandidates where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    func isNoConversation(_ report: RunReport) -> Bool {
        report.isError && report.errorText.localizedCaseInsensitiveContains("no conversation")
    }
}

enum AgentBackends {
    static let all: [AgentBackend] = [ClaudeBackend(), CodexBackend(), AntigravityBackend()]
    static let defaultID = "claude"
    static let settingsKey = "agentBackend"

    static func named(_ id: String) -> AgentBackend {
        all.first { $0.id == id } ?? all[0]
    }

    /// The backend to use: the environment wins, then the saved choice, then Claude.
    static func current() -> AgentBackend {
        if let id = ProcessInfo.processInfo.environment["CLAUDE_ASSISTANT_AGENT"], !id.isEmpty {
            return named(id)
        }
        return named(UserDefaults.standard.string(forKey: settingsKey) ?? defaultID)
    }
}

/// Shared helpers for reading the tools' JSON.
enum JSONReading {
    static func object(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// One object per non-empty line; lines that are not JSON are skipped.
    static func lines(_ text: String) -> [[String: Any]] {
        text.split(separator: "\n").compactMap { object(String($0)) }
    }

    static func int(_ any: Any?) -> Int? {
        if let n = any as? Int { return n }
        if let d = any as? Double { return Int(d) }
        return nil
    }
}
