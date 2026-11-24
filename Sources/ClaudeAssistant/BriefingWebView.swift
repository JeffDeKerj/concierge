import SwiftUI
import WebKit

/// Shows one briefing page. The HTML is read from disk and injected as a string
/// so WebKit's file cache never shows a stale page; links open in the browser.
/// The app's page script adds a "done" button to each item and reports
/// dismissals back through `onDismiss` / `onRestore`.
struct BriefingWebView: NSViewRepresentable {
    let page: BriefingPage?
    let reloadToken: Int
    let dismissedKeys: [String]
    var onDismiss: (DismissedItem) -> Void = { _ in }
    var onRestore: (String) -> Void = { _ in }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loadedToken: Int?
        var loadedURL: URL?
        var dismissedKeys: [String] = []
        var onDismiss: (DismissedItem) -> Void = { _ in }
        var onRestore: (String) -> Void = { _ in }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(PageScript.applyCall(keys: dismissedKeys))
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let key = body["key"] as? String else { return }
            switch message.name {
            case PageScript.dismissHandler:
                onDismiss(DismissedItem(key: key,
                                        title: body["title"] as? String ?? "",
                                        source: nonEmpty(body["source"]),
                                        section: nonEmpty(body["section"]),
                                        dismissedAt: Date()))
            case PageScript.restoreHandler:
                onRestore(key)
            default:
                break
            }
        }

        private func nonEmpty(_ value: Any?) -> String? {
            guard let s = value as? String, !s.isEmpty else { return nil }
            return s
        }
    }

    /// WKUserContentController keeps its handlers strongly; this forwards to
    /// the coordinator without owning it.
    private final class HandlerProxy: NSObject, WKScriptMessageHandler {
        weak var target: Coordinator?
        init(_ target: Coordinator) { self.target = target }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.userContentController(controller, didReceive: message)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let proxy = HandlerProxy(context.coordinator)
        configuration.userContentController.add(proxy, name: PageScript.dismissHandler)
        configuration.userContentController.add(proxy, name: PageScript.restoreHandler)
        configuration.userContentController.addUserScript(
            WKUserScript(source: PageScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = NSColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1)
        sync(context.coordinator)
        load(into: webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        sync(context.coordinator)
        if context.coordinator.loadedToken != reloadToken || context.coordinator.loadedURL != page?.url {
            load(into: webView, context: context)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: PageScript.dismissHandler)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: PageScript.restoreHandler)
    }

    private func sync(_ coordinator: Coordinator) {
        coordinator.dismissedKeys = dismissedKeys
        coordinator.onDismiss = onDismiss
        coordinator.onRestore = onRestore
    }

    private func load(into webView: WKWebView, context: Context) {
        context.coordinator.loadedToken = reloadToken
        context.coordinator.loadedURL = page?.url
        if let page, let html = try? String(contentsOf: page.url, encoding: .utf8) {
            webView.loadHTMLString(html, baseURL: Paths.briefings)
        } else {
            webView.loadHTMLString(Self.emptyPage, baseURL: nil)
        }
    }

    static let emptyPage = """
    <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="color-scheme" content="dark"></head>
    <body style="background:#0f1115;color:#9aa1ad;font:15px/1.5 -apple-system,sans-serif;padding:32px;">
      <h2 style="color:#e6e8ee;font-size:20px;margin:0 0 8px">No briefing yet</h2>
      <p>Press <strong style="color:#e6e8ee">Refresh</strong> to build today's page.
      It takes a few minutes.</p>
    </body></html>
    """
}
