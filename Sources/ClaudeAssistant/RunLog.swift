import Foundation

/// One line per run, appended to `briefings/runs.jsonl` (gitignored with the
/// pages), so the cost of updating the briefing can be added up later.
struct RunLog {
    let url: URL

    init(url: URL = Paths.briefings.appendingPathComponent("runs.jsonl")) {
        self.url = url
    }

    struct Entry: Codable, Equatable {
        var when: Date
        /// "refresh" or "ask".
        var kind: String
        var backend: String
        var costUSD: Double?
        var durationMs: Int?
        var inputTokens: Int?
        var outputTokens: Int?
        var turns: Int?
        var model: String?
        var failed: Bool
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func append(kind: String, backend: String, report: RunReport) {
        let entry = Entry(when: Date(), kind: kind, backend: backend, costUSD: report.costUSD,
                          durationMs: report.durationMs, inputTokens: report.inputTokens,
                          outputTokens: report.outputTokens, turns: report.turns,
                          model: report.model, failed: report.isError)
        guard var data = try? Self.encoder.encode(entry) else { return }
        data.append(0x0A)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    func entries() -> [Entry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            try? Self.decoder.decode(Entry.self, from: Data(line.utf8))
        }
    }

    /// Cost and count of the runs on `day` (Europe/London), failed ones included.
    func total(on day: Date = Date()) -> (costUSD: Double, runs: Int) {
        let key = Paths.dayFormatter.string(from: day)
        let today = entries().filter { Paths.dayFormatter.string(from: $0.when) == key }
        return (today.compactMap(\.costUSD).reduce(0, +), today.count)
    }
}
