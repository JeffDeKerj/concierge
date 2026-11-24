import Foundation

/// An item the owner marked as done with: it stays off the page, and the
/// generator reads this list before writing the next one.
struct DismissedItem: Codable, Equatable, Identifiable {
    /// Stable id the page gives the item (`mail:<thread>`, `whatsapp:…`, or a
    /// title-derived fallback). Matches `data-key` on the page's list items.
    var key: String
    var title: String
    /// The "when" line of the item, e.g. "Email · yesterday 16:51".
    var source: String?
    /// The section the item sat in, e.g. "Urgent actions".
    var section: String?
    var dismissedAt: Date
    /// Set when the item was snoozed rather than dismissed: it comes back
    /// once this time has passed.
    var until: Date? = nil

    var id: String { key }

    /// True while the item should stay off the page.
    func isHidden(at now: Date = Date()) -> Bool {
        guard let until else { return true }
        return until > now
    }
}

/// How long a snooze lasts. The page offers both.
enum SnoozeLength: String {
    case tomorrow
    case nextWeek = "week"

    /// Tomorrow at 06:00, or next Monday at 06:00: before the morning run, so
    /// the item is back on the next page.
    func until(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        let morning = DateComponents(hour: 6, minute: 0)
        switch self {
        case .tomorrow:
            let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            return calendar.date(bySettingHour: 6, minute: 0, second: 0, of: next)!
        case .nextWeek:
            var monday = morning
            monday.weekday = 2
            return calendar.nextDate(after: now, matching: monday, matchingPolicy: .nextTime)!
        }
    }
}

/// `briefings/dismissed.json`: a pretty-printed array, so the headless
/// generator can read it with one Read call.
struct DismissStore {
    let url: URL

    init(url: URL = Paths.briefings.appendingPathComponent("dismissed.json")) {
        self.url = url
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func load() -> [DismissedItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? Self.decoder.decode([DismissedItem].self, from: data)) ?? []
    }

    /// Adds the item, replacing an earlier entry with the same key.
    @discardableResult
    func add(_ item: DismissedItem) -> [DismissedItem] {
        var items = load().filter { $0.key != item.key }
        items.append(item)
        save(items)
        return items
    }

    /// Every dismissal and snooze, kept for the skill to learn from. Never
    /// pruned by the app; one JSON object per line.
    func recordHistory(_ item: DismissedItem) {
        let history = url.deletingLastPathComponent().appendingPathComponent("dismiss-history.jsonl")
        guard var data = try? Self.encoder.encode(item) else { return }
        data = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\n", with: "").utf8)
        data.append(0x0A)
        if let h = try? FileHandle(forWritingTo: history) {
            defer { try? h.close() }
            _ = try? h.seekToEnd(); try? h.write(contentsOf: data)
        } else { try? data.write(to: history) }
    }

    /// Drops snoozes whose time has passed, so those items show again.
    @discardableResult
    func removeExpired(now: Date = Date()) -> [DismissedItem] {
        let all = load()
        let kept = all.filter { $0.isHidden(at: now) }
        if kept.count != all.count { save(kept) }
        return kept
    }

    @discardableResult
    func remove(key: String) -> [DismissedItem] {
        let items = load().filter { $0.key != key }
        save(items)
        return items
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: url)
    }

    private func save(_ items: [DismissedItem]) {
        if items.isEmpty {
            removeAll()
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Self.encoder.encode(items) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
