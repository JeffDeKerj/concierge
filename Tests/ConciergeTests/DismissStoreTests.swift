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
        #expect(PageScript.applyCall(keys: ["mail:1", "it's"]) == "window.briefing && window.briefing.applyDismissed([\"mail:1\",\"it's\"]);")
        #expect(PageScript.jsArray(["a\"b"]) == "[\"a\\\"b\"]")
    }
}
