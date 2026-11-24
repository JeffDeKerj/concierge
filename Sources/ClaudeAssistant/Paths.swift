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
}

/// Locate the `claude` CLI. A GUI process has no shell PATH, so look in the
/// known install locations.
enum ToolLookup {
    static let claudeCandidates = [
        NSHomeDirectory() + "/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        NSHomeDirectory() + "/.npm-global/bin/claude",
        "/usr/bin/claude",
    ]

    static var claude: URL? {
        if let path = ProcessInfo.processInfo.environment["CLAUDE_ASSISTANT_CLAUDE_BIN"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        for p in claudeCandidates where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }
}
