import Foundation
import Network
import Testing
import WebKit
@testable import Concierge

/// A hostile page in a real web view, with a listener on this Mac that
/// counts what the page manages to fetch.
extension SerialTests {
@Suite struct PageGuardLiveTests {
    /// Counts connections to a port on this Mac.
    final class Listener: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private let listener: NWListener
        var port: UInt16 { listener.port?.rawValue ?? 0 }
        var connections: Int { lock.lock(); defer { lock.unlock() }; return count }

        init() throws {
            listener = try NWListener(using: .tcp, on: .any)
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.lock.lock(); self.count += 1; self.lock.unlock()
                connection.cancel()
            }
            listener.start(queue: .global())
        }

        func stop() { listener.cancel() }
    }

    static func hostile(port: UInt16) -> String {
        let there = "http://127.0.0.1:\(port)"
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <link rel="stylesheet" href="\(there)/style.css"><style>body{color:#eee}</style></head><body><main>
        <section><h2>Urgent actions</h2><ul>
        <li data-key="mail:1"><span class="t">One</span><img src="\(there)/picture.png?said=secret"></li>
        <li data-key="mail:2"><span class="t">Two</span></li></ul></section>
        <script>fetch('\(there)/script'); new Image().src = '\(there)/script-image';</script>
        <iframe src="\(there)/frame"></iframe>
        </main></body></html>
        """
    }

    /// Loads `html` as the app's page view does and returns how many
    /// items the app's page script took charge of.
    @MainActor static func show(_ html: String) async throws -> Int {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(source: PageScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 800), configuration: configuration)
        let coordinator = BriefingWebView.Coordinator()
        view.navigationDelegate = coordinator
        view.loadHTMLString(html, baseURL: Paths.briefings)
        // Time for the page to try everything it wants to fetch.
        try await Task.sleep(for: .seconds(3))
        let items = try await view.evaluateJavaScript("window.briefing ? window.briefing.keys().length : -1")
        return items as? Int ?? -1
    }

    @Test @MainActor func aGuardedPageFetchesNothingAndKeepsItsButtons() async throws {
        let listener = try Listener()
        defer { listener.stop() }
        try await Task.sleep(for: .milliseconds(200))
        let page = Self.hostile(port: listener.port)

        // First without the rule, to show the listener does see such a page.
        _ = try await Self.show(page)
        #expect(listener.connections > 0)

        let before = listener.connections
        let items = try await Self.show(PageGuard.guarded(page))
        #expect(listener.connections == before)
        // The app's own script still ran and found both items.
        #expect(items == 2)
    }
}
}
