import Foundation
import Testing
@testable import Concierge

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

    @Test func lastUpdateSkipsQuestionsAndFailedRuns() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("runlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("runs.jsonl")
        let log = RunLog(url: url)
        #expect(log.lastUpdate() == nil)
        // As the job runner writes them.
        let lines = [
            #"{"when": "2026-11-27T09:06:29Z", "kind": "check", "backend": "claude", "failed": false}"#,
            #"{"when": "2026-11-27T13:07:13Z", "kind": "check", "backend": "claude", "failed": false}"#,
            #"{"when": "2026-11-27T13:56:36Z", "kind": "ask", "backend": "claude", "failed": false}"#,
            #"{"when": "2026-11-27T15:07:00Z", "kind": "check", "backend": "claude", "failed": true}"#,
        ]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        #expect(log.lastUpdate() == ISO8601DateFormatter().date(from: "2026-11-27T13:07:13Z"))
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func topLineShowsTheDayAndTheTime() throws {
        let iso = ISO8601DateFormatter()
        let now = try #require(iso.date(from: "2026-11-27T14:00:00Z"))
        let today = try #require(iso.date(from: "2026-11-27T13:07:13Z"))
        let yesterday = try #require(iso.date(from: "2026-11-26T18:31:49Z"))
        #expect(TopLine.text(day: "Friday 27 November", updated: today, now: now) == "Friday 27 November · updated 13:07")
        #expect(TopLine.text(day: "Thursday 26 November", updated: yesterday, now: now) == "Thursday 26 November · updated Thu 18:31")
        #expect(TopLine.text(day: "Friday 27 November", updated: nil, now: now) == "Friday 27 November")
        #expect(TopLine.text(day: nil, updated: nil, now: now) == "")
        // Summer time: the owner's clock is an hour ahead of UTC.
        let summer = try #require(iso.date(from: "2026-07-01T12:00:00Z"))
        #expect(TopLine.time(summer, now: summer) == "13:00")
    }

    @Test func continuedConversationIsChargedTheDifference() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("runlog-\(UUID().uuidString)")
        let log = RunLog(url: dir.appendingPathComponent("runs.jsonl"))
        var refresh = RunReport(); refresh.costUSD = 3.24; refresh.sessionID = "s1"
        var ask = RunReport(); ask.costUSD = 3.46; ask.sessionID = "s1"
        var other = RunReport(); other.costUSD = 0.20; other.sessionID = "s2"
        #expect(log.append(kind: "refresh", backend: "claude", report: refresh).costUSD == 3.24)
        let charged = log.append(kind: "ask", backend: "claude", report: ask)
        #expect(abs((charged.costUSD ?? 0) - 0.22) < 0.0001)
        #expect(log.append(kind: "ask", backend: "claude", report: other).costUSD == 0.20)
        let entries = log.entries()
        #expect(entries[1].sessionCostUSD == 3.46)
        #expect(abs(log.total().costUSD - 3.66) < 0.0001)
        try? FileManager.default.removeItem(at: dir)
    }
}

struct CostHistoryTests {
    private func entry(_ when: String, _ kind: String, _ cost: Double?, failed: Bool = false) -> RunLog.Entry {
        RunLog.Entry(when: ISO8601DateFormatter().date(from: when)!, kind: kind, backend: "claude",
                     costUSD: cost, failed: failed)
    }

    @Test func runsAreAddedUpByDayAndByPart() {
        let days = CostHistory.days([
            entry("2026-11-27T09:00:00Z", "check", 0.05),
            entry("2026-11-27T11:48:00Z", "refresh", 1.0),
            entry("2026-11-27T12:16:00Z", "ask", 0.2),
            entry("2026-11-27T16:24:00Z", "morning-test", 1.0),
            entry("2026-11-27T18:38:00Z", "wrapup", 0.4, failed: true),
            entry("2026-11-28T08:44:00Z", "morning", 1.4),
            entry("2026-11-28T09:30:00Z", "ask", nil),
            entry("2026-11-28T10:00:00Z", "something-new", 0.1),
        ])
        #expect(days.map(\.id) == ["2026-11-28", "2026-11-27"])
        let fri = days[1]
        #expect(abs(fri.page - 2.0) < 1e-9 && abs(fri.questions - 0.2) < 1e-9 && abs(fri.daytime - 0.45) < 1e-9)
        #expect(fri.runs == 5 && fri.failed == 1)
        #expect(abs(fri.total - 2.65) < 1e-9)
        let sat = days[0]
        #expect(sat.runs == 3 && abs(sat.other - 0.1) < 1e-9 && abs(sat.total - 1.5) < 1e-9)
        #expect(sat.label == "Sat 28 Nov")
    }

    @Test func aRunJustAfterMidnightInSummerBelongsToTheLondonDay() {
        // 23:30 UTC on 30 June is 00:30 on 1 July in London.
        let days = CostHistory.days([entry("2026-06-30T23:30:00Z", "check", 0.01)])
        #expect(days.map(\.id) == ["2026-07-01"])
    }
}
