import Foundation
import Testing
@testable import Concierge

struct DismissStoreTests {
    private func temporaryStore() -> DismissStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dismiss-\(UUID().uuidString)")
        return DismissStore(url: dir.appendingPathComponent("dismissed.json"))
    }

    @Test func addsReplacesRemovesAndClears() throws {
        let store = temporaryStore()
        #expect(store.load().isEmpty)

        let first = DismissedItem(key: "mail:1", title: "Tax return", source: "Email · 16:51",
                                  section: "Urgent actions", dismissedAt: Date())
        store.add(first)
        store.add(DismissedItem(key: "title:thierry", title: "Thierry's question", source: nil,
                                section: nil, dismissedAt: Date()))
        #expect(store.load().map(\.key) == ["mail:1", "title:thierry"])

        // Dismissing the same key again keeps one entry, the newer one.
        var again = first
        again.title = "Tax return (resent)"
        store.add(again)
        let items = store.load()
        #expect(items.count == 2)
        #expect(items.last?.title == "Tax return (resent)")

        store.remove(key: "mail:1")
        #expect(store.load().map(\.key) == ["title:thierry"])

        store.removeAll()
        #expect(store.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent())
    }

    @Test func fileIsReadableJSON() throws {
        let store = temporaryStore()
        store.add(DismissedItem(key: "whatsapp:67:123", title: "A question", source: "WhatsApp · 09:00",
                                section: "Urgent actions", dismissedAt: Date(timeIntervalSince1970: 0)))
        let text = try String(contentsOf: store.url, encoding: .utf8)
        #expect(text.contains("\"key\" : \"whatsapp:67:123\""))
        #expect(text.contains("1970-01-01T00:00:00Z"))
        try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent())
    }

    @Test func scriptEmbedsSectionsAndKeys() {
        #expect(PageScript.source.contains("\"urgent actions\""))
        #expect(PageScript.source.contains("\"keymodule on slack\""))
        #expect(PageScript.applyCall(keys: ["mail:1", "it's"]) == "window.briefing && window.briefing.applyDismissed([\"mail:1\",\"it's\"]);")
        #expect(PageScript.jsArray(["a\"b"]) == "[\"a\\\"b\"]")
    }
}

struct SnoozeTests {
    private let london: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func snoozeEndsBeforeTheMorningRun() {
        // Tuesday 24 November 2026, 21:30 in London.
        let now = date("2026-11-24T21:30:00Z")
        #expect(SnoozeLength.tomorrow.until(from: now, calendar: london) == date("2026-11-25T06:00:00Z"))
        #expect(SnoozeLength.nextWeek.until(from: now, calendar: london) == date("2026-11-30T06:00:00Z"))
    }

    @Test func expiredSnoozesAreDropped() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("snooze-\(UUID().uuidString)")
        let store = DismissStore(url: dir.appendingPathComponent("dismissed.json"))
        let now = Date()
        store.add(DismissedItem(key: "done", title: "Done", dismissedAt: now))
        store.add(DismissedItem(key: "later", title: "Later", dismissedAt: now, until: now.addingTimeInterval(3600)))
        store.add(DismissedItem(key: "back", title: "Back", dismissedAt: now, until: now.addingTimeInterval(-60)))
        #expect(store.removeExpired(now: now).map(\.key) == ["done", "later"])
        #expect(store.load().map(\.key) == ["done", "later"])
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func fileWithoutUntilStillReads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("snooze-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("dismissed.json")
        try Data(#"[{"key":"mail:1","title":"T","dismissedAt":"2026-11-24T10:00:00Z"}]"#.utf8).write(to: url)
        let items = DismissStore(url: url).load()
        #expect(items.count == 1 && items[0].until == nil && items[0].isHidden())
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func scriptOffersSnooze() {
        #expect(PageScript.source.contains("'\(PageScript.snoozeHandler)'"))
        #expect(PageScript.source.contains("next Monday"))
    }
}
