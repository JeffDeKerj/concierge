import Foundation
import Testing
@testable import ClaudeAssistant

struct RunLogTests {
    @Test func appendsAndTotalsToday() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("runlog-\(UUID().uuidString)")
        let log = RunLog(url: dir.appendingPathComponent("runs.jsonl"))
        #expect(log.entries().isEmpty)
        #expect(log.total().runs == 0)

        var a = RunReport(); a.costUSD = 0.5; a.durationMs = 100
        var b = RunReport(); b.costUSD = 0.25; b.isError = true
        let c = RunReport()   // no price reported
        log.append(kind: "refresh", backend: "claude", report: a)
        log.append(kind: "ask", backend: "claude", report: b)
        log.append(kind: "ask", backend: "antigravity", report: c)

        let entries = log.entries()
        #expect(entries.count == 3)
        #expect(entries[0].kind == "refresh")
        #expect(entries[1].failed)
        #expect(entries[2].backend == "antigravity")
        let total = log.total()
        #expect(total.runs == 3)
        #expect(abs(total.costUSD - 0.75) < 0.0001)
        #expect(log.total(on: Date(timeIntervalSince1970: 0)).runs == 0)
        try? FileManager.default.removeItem(at: dir)
    }
}
