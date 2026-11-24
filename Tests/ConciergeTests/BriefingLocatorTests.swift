import Foundation
import Testing
@testable import Concierge

extension SerialTests {
@Suite struct BriefingLocatorTests {
    @Test func emptyFolderGivesNoPage() throws {
        try Fixture.reset()
        #expect(BriefingLocator.pick() == nil)
    }

    @Test func todayWinsWhenPresent() throws {
        try Fixture.reset()
        let today = BriefingLocator.today()
        try Fixture.writePage("2020-01-01")
        try Fixture.writePage(today)
        let page = try #require(BriefingLocator.pick())
        #expect(page.isToday)
        #expect(page.day == today)
    }

    @Test func newestDatedPageWhenTodayIsMissing() throws {
        try Fixture.reset()
        try Fixture.writePage("2026-11-20")
        try Fixture.writePage("2026-11-22")
        try Fixture.writePage("2026-11-21")
        try "x".write(to: Fixture.briefings.appendingPathComponent("backup-2026-11-23.html"),
                      atomically: true, encoding: .utf8)
        try "x".write(to: Fixture.briefings.appendingPathComponent("2026-11-25.png"),
                      atomically: true, encoding: .utf8)
        let page = try #require(BriefingLocator.pick())
        #expect(!page.isToday)
        #expect(page.day == "2026-11-22")
        #expect(page.longDay == "Sunday 22 November")
    }

    @Test @MainActor func modelNoticeNamesTheFallbackDay() throws {
        try Fixture.reset()
        try Fixture.writePage("2026-11-22")
        let model = AppModel()
        #expect(model.notice == "Today's briefing is not there yet. Showing Sunday 22 November.")
        try Fixture.reset()
        model.loadPage()
        #expect(model.page == nil)
        #expect(model.notice == "No briefing yet. Press Refresh to build today's.")
    }
}
}
