import Foundation

/// The page is written by a model that has just read mail and chats, so the
/// app does not trust it: nothing on it may fetch anything, and it is looked
/// over before it is shown.
///
/// A summary of a mail can carry an address the sender chose. A picture at
/// that address would be fetched the moment the page opens, and the address
/// can hold whatever the page says. So the page gets a rule that lets it
/// load nothing from anywhere; links still open in the browser, on a click.
enum PageGuard {
    /// Nothing is loaded from any address: no pictures, scripts, styles,
    /// fonts or frames. The page's own `<style>` block still applies. The
    /// app's page script is added by the app, not by the page, and is not
    /// held by this rule.
    static let policy = "default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'"

    /// The page with that rule as the first thing in its head.
    static func guarded(_ html: String) -> String {
        let meta = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">"
        if let head = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            return html.replacingCharacters(in: head.upperBound..<head.upperBound, with: meta)
        }
        return "<head>\(meta)</head>" + html
    }

    enum Navigation: Equatable { case show, openInBrowser, refuse }

    /// What to do when the page view is asked to go somewhere. Only the
    /// page itself is shown in the view. A link the owner clicked opens in
    /// the browser when it is a web or mail address. Anything else, such as
    /// a page that sends itself elsewhere, is refused.
    static func navigation(to url: URL?, clicked: Bool, briefings: URL = Paths.briefings) -> Navigation {
        guard let url else { return .refuse }
        if clicked {
            return ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") ? .openInBrowser : .refuse
        }
        if url.scheme == "about" { return .show }
        if url.isFileURL, url.standardizedFileURL.path.hasPrefix(briefings.standardizedFileURL.path) { return .show }
        return .refuse
    }

    /// Sites the mail, chat and CI items link to. The papers section may
    /// link anywhere on the web.
    static let familiar = ["google.com", "slack.com", "github.com", "arxiv.org", "doi.org", "whatsapp.com"]
    static let anyHostSections = ["papers to read"]
    /// Sections whose items the owner can dismiss, so each needs a key.
    static let keyedSections = ["urgent actions", "keymodule on slack", "other conversations", "papers to read",
                                "already handled or low priority"]

    /// What is odd about a page, in the owner's words: one line each, none
    /// when all is well.
    static func problems(in html: String) -> [String] {
        var strange: [String] = []
        var unfamiliar: [String] = []
        var unkeyed = 0
        for section in sections(of: html) {
            let anyHost = anyHostSections.contains(section.title)
            for link in matches("<a\\b[^>]*\\bhref\\s*=\\s*[\"']([^\"']*)[\"']", in: section.body) {
                guard let url = URL(string: link.trimmingCharacters(in: .whitespaces)), let scheme = url.scheme?.lowercased() else { continue }
                if scheme == "mailto" { continue }
                guard scheme == "https", let host = url.host?.lowercased(), !isNumeric(host) else {
                    strange.append(String(link.prefix(40)))
                    continue
                }
                if !anyHost, !familiar.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { unfamiliar.append(host) }
            }
            if keyedSections.contains(section.title) {
                unkeyed += matches("<li\\b([^>]*)>", in: section.body).filter {
                    !$0.contains("data-key") && !$0.contains("class=\"row\"")
                }.count
            }
        }
        var lines: [String] = []
        if !strange.isEmpty {
            lines.append("\(count(strange.count, "link")) on this page \(strange.count == 1 ? "is not an ordinary web link" : "are not ordinary web links"): \(list(strange)). Do not open \(strange.count == 1 ? "it" : "them").")
        }
        if !unfamiliar.isEmpty {
            lines.append("\(count(unfamiliar.count, "link")) outside the papers \(unfamiliar.count == 1 ? "goes" : "go") to \(unfamiliar.count == 1 ? "a site" : "sites") Nestor does not know: \(list(unfamiliar)). Look before you click.")
        }
        if unkeyed > 0 {
            lines.append("\(count(unkeyed, "item")) on this page \(unkeyed == 1 ? "has" : "have") no key, so dismissing \(unkeyed == 1 ? "it" : "them") may not last.")
        }
        return lines
    }

    /// The keys of items the skill listed again although they were dismissed,
    /// because something new happened: `<li data-key="…" data-returned="new">`.
    static func returnedKeys(in html: String) -> Set<String> {
        var keys: Set<String> = []
        for attributes in matches("<li\\b([^>]*\\bdata-returned\\b[^>]*)>", in: html) {
            if let key = matches("\\bdata-key\\s*=\\s*[\"']([^\"']+)[\"']", in: attributes).first { keys.insert(key) }
        }
        return keys
    }

    /// The page cut at its headings: each title in lower case with what follows it.
    private static func sections(of html: String) -> [(title: String, body: String)] {
        guard let heading = try? NSRegularExpression(pattern: "<h[12][^>]*>([\\s\\S]*?)</h[12]>", options: .caseInsensitive) else { return [] }
        let whole = html as NSString
        let found = heading.matches(in: html, range: NSRange(location: 0, length: whole.length))
        var parts: [(String, String)] = []
        if let first = found.first, first.range.location > 0 {
            parts.append(("", whole.substring(to: first.range.location)))
        } else if found.isEmpty {
            parts.append(("", html))
        }
        for (i, match) in found.enumerated() {
            let title = whole.substring(with: match.range(at: 1))
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let end = i + 1 < found.count ? found[i + 1].range.location : whole.length
            let start = match.range.location + match.range.length
            parts.append((title, whole.substring(with: NSRange(location: start, length: end - start))))
        }
        return parts
    }

    /// The first group of every match.
    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let whole = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: whole.length)).map { whole.substring(with: $0.range(at: 1)) }
    }

    private static func isNumeric(_ host: String) -> Bool {
        host.contains(":") || host.allSatisfy { $0.isNumber || $0 == "." }
    }

    private static func count(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }

    private static func list(_ names: [String]) -> String {
        var seen: [String] = []
        for name in names where !seen.contains(name) { seen.append(name) }
        return seen.prefix(4).joined(separator: ", ") + (seen.count > 4 ? " and \(seen.count - 4) more" : "")
    }
}
