import Foundation
@testable import ClaudeAssistant

/// The throwaway project folder Scripts/test.sh points the app at.
enum Fixture {
    static var project: URL { Paths.project }
    static var briefings: URL { Paths.briefings }

    static func reset() throws {
        try? FileManager.default.removeItem(at: briefings)
        try FileManager.default.createDirectory(at: briefings, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: project.appendingPathComponent("stub-mode"))
    }

    static func stubMode(_ mode: String) throws {
        try mode.write(to: project.appendingPathComponent("stub-mode"), atomically: true, encoding: .utf8)
    }

    static func writePage(_ day: String, body: String = "page") throws {
        try "<html><body>\(body)</body></html>".write(to: Paths.briefing(named: day), atomically: true, encoding: .utf8)
    }

    /// Poll until `condition` holds, or give up after `seconds`.
    static func wait(seconds: Double = 10, until condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return await condition()
    }
}
