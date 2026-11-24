import Foundation

/// Where things live. The project folder holds `briefings/` and is the working
/// directory for every `claude` run, so `--continue` picks up the briefing run.
enum Paths {
    static let project: URL = {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_ASSISTANT_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir)
        }
        return URL(fileURLWithPath: "/Users/jeffdekerj/code/swift/claude-assistant")
    }()

    static var briefings: URL { project.appendingPathComponent("briefings") }

    /// Briefing dates follow the owner's clock, Europe/London, as the skill does.
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = TimeZone(identifier: "Europe/London")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func briefing(named day: String) -> URL {
        briefings.appendingPathComponent("\(day).html")
    }

    /// The briefing skill, for backends that have no `/briefing` command of their own.
    static let briefingSkill = NSHomeDirectory() + "/.claude/skills/briefing/SKILL.md"
    static var briefingInstructions: String {
        "Read \(briefingSkill) and follow it to build today's briefing page."
    }
}
