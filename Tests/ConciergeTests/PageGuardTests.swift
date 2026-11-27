import Foundation
import Testing
@testable import Concierge

struct PageGuardTests {
    @Test func theRuleGoesFirstInTheHead() {
        let page = PageGuard.guarded("<!DOCTYPE html><html><HEAD lang=\"en\"><style>b{}</style></head><body>x</body></html>")
        #expect(page.contains("<HEAD lang=\"en\"><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none';"))
        #expect(page.hasSuffix("<style>b{}</style></head><body>x</body></html>"))
        // A page with no head still gets it.
        #expect(PageGuard.guarded("<p>x</p>").hasPrefix("<head><meta http-equiv=\"Content-Security-Policy\""))
        #expect(PageGuard.policy.contains("img-src data:"))
        #expect(!PageGuard.policy.contains("http"))
    }

    @Test func onlyThePageItselfIsShownAndOnlyClickedWebLinksOpen() {
        let folder = URL(fileURLWithPath: "/tmp/b/briefings")
        func go(_ address: String, clicked: Bool) -> PageGuard.Navigation {
            PageGuard.navigation(to: URL(string: address), clicked: clicked, briefings: folder)
        }
        #expect(go("file:///tmp/b/briefings/", clicked: false) == .show)
        #expect(go("about:blank", clicked: false) == .show)
        // A page that sends itself elsewhere, or a frame: refused.
        #expect(go("https://example.com/?q=secret", clicked: false) == .refuse)
        #expect(go("file:///etc/passwd", clicked: false) == .refuse)
        #expect(go("https://mail.google.com/mail/u/0/#drafts", clicked: true) == .openInBrowser)
        #expect(go("mailto:someone@example.com", clicked: true) == .openInBrowser)
        #expect(go("file:///Applications/Calculator.app", clicked: true) == .refuse)
        #expect(go("javascript:alert(1)", clicked: true) == .refuse)
        #expect(PageGuard.navigation(to: nil, clicked: true) == .refuse)
    }

    static let good = """
    <html><head><style>a{}</style></head><body>
    <section><h1>Briefing</h1><p>Hello</p></section>
    <section><h2>Urgent actions</h2><ul>
      <li data-key="mail:1"><span class="t">Reply</span> <a href="https://mail.google.com/mail/#all/thread-f:1">Open</a></li>
      <li data-key="ci:a/b:nightly"><a href="https://github.com/a/b/actions">Runs</a></li></ul></section>
    <section><h2>Agenda</h2><ul><li class="row">09:00 Dentist</li></ul></section>
    <section><h2>Keymodule on Slack</h2><ul><li data-key="slack:C1:2026-11-27T09:00"><a href="https://keymodule.slack.com/archives/C1/p1">Open in Slack</a></li></ul></section>
    <section><h2>Papers to read</h2><ul><li data-key="paper:1"><a href="https://some-journal.example.org/paper">Paper</a></li></ul></section>
    </body></html>
    """

    @Test func aNormalPageHasNothingOdd() {
        #expect(PageGuard.problems(in: Self.good) == [])
        #expect(PageGuard.problems(in: "") == [])
    }

    @Test func unknownSitesStrangeLinksAndMissingKeysAreNamed() {
        let page = Self.good
            .replacingOccurrences(of: "https://mail.google.com/mail/#all/thread-f:1", with: "https://mail.google.com.evil.example/x?d=1")
            .replacingOccurrences(of: "https://github.com/a/b/actions", with: "http://203.0.113.9/collect")
            .replacingOccurrences(of: "<li data-key=\"slack:C1:2026-11-27T09:00\">", with: "<li>")
        #expect(PageGuard.problems(in: page) == [
            "1 link on this page is not an ordinary web link: http://203.0.113.9/collect. Do not open it.",
            "1 link outside the papers goes to a site Nestor does not know: mail.google.com.evil.example. Look before you click.",
            "1 item on this page has no key, so dismissing it may not last.",
        ])
    }

    /// Every real page in the folder the tests are pointed at, when
    /// `PAGE_GUARD_REAL` names one: prints what would be flagged.
    @Test func realPages() throws {
        guard let folder = ProcessInfo.processInfo.environment["PAGE_GUARD_REAL"] else { return }
        for name in try FileManager.default.contentsOfDirectory(atPath: folder).sorted() where name.hasSuffix(".html") {
            let html = try String(contentsOfFile: folder + "/" + name, encoding: .utf8)
            print("PAGE \(name): \(PageGuard.problems(in: html))")
        }
    }
}
