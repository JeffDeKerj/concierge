import SwiftUI
import WebKit

/// Shows one briefing page. The HTML is read from disk and injected as a string
/// so WebKit's file cache never shows a stale page; links open in the browser.
struct BriefingWebView: NSViewRepresentable {
    let page: BriefingPage?
    let reloadToken: Int

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedToken: Int?
        var loadedURL: URL?

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = NSColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1)
        load(into: webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedToken != reloadToken || context.coordinator.loadedURL != page?.url {
            load(into: webView, context: context)
        }
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
