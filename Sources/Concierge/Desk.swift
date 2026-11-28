import CryptoKit
import Foundation
import Observation
import OSLog

private let log = Logger(subsystem: "local.jeffdekerj.concierge", category: "desk")

/// One question a Claude Code session put to the owner while they were away,
/// held by the session's hook (`~/.claude/hooks/nestor_desk.py`) until answered.
struct DeskQuestion: Equatable, Identifiable {
    struct Part: Equatable {
        var question: String
        var multiSelect: Bool
        var options: [String]
    }

    enum Kind: String { case card, reply }

    var id: String
    var host: String
    var project: String
    var title: String
    var kind: Kind
    var parts: [Part]

    /// "the brain session on spark": how Nestor names it aloud.
    var spokenName: String {
        let last = project.split(separator: "/").last.map(String.init) ?? project
        return host == "spark" ? "the \(last) session on spark" : "the \(last) session"
    }

    init?(_ body: [String: Any]) {
        guard body["kind"] as? String == "question", let id = body["id"] as? String,
              let kind = Kind(rawValue: body["type"] as? String ?? ""),
              let raw = body["questions"] as? [[String: Any]], !raw.isEmpty else { return nil }
        self.id = id
        host = body["host"] as? String ?? "mac"
        project = body["project"] as? String ?? ""
        title = body["title"] as? String ?? ""
        self.kind = kind
        parts = raw.map {
            Part(question: $0["question"] as? String ?? "", multiSelect: $0["multiSelect"] as? Bool ?? false,
                 options: $0["options"] as? [String] ?? [])
        }
    }
}

/// The signed messages the hooks and Nestor exchange through ntfy. Every
/// message is `{"body": <text>, "sig": <HMAC of the text>}` with the key in
/// `~/.config/ixelis/nestor-desk.key`; one without a valid HMAC is ignored.
enum DeskSeal {
    static let keyFile = NSHomeDirectory() + "/.config/ixelis/nestor-desk.key"

    static func key() -> Data? {
        guard let text = try? String(contentsOfFile: keyFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return Data(text.utf8)
    }

    /// The topic, the same as the hook's. Pure, for tests.
    static func topic(_ key: Data) -> String {
        let digest = SHA256.hash(data: key + Data("/topic".utf8))
        return "nestor-desk-" + digest.map { String(format: "%02x", $0) }.joined().prefix(24)
    }

    static func sign(_ text: String, _ key: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: key))
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// The message to post. Pure, for tests.
    static func seal(_ body: [String: Any], _ key: Data) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let text = String(data: data, encoding: .utf8),
              let outer = try? JSONSerialization.data(withJSONObject: ["body": text, "sig": sign(text, key)]) else { return nil }
        return String(data: outer, encoding: .utf8)
    }

    /// The body of a message whose HMAC is right, else nil. Pure, for tests.
    static func unseal(_ message: String, _ key: Data) -> [String: Any]? {
        guard let outer = (try? JSONSerialization.jsonObject(with: Data(message.utf8))) as? [String: Any],
              let text = outer["body"] as? String, let sig = outer["sig"] as? String,
              sig.count == 64, Data(sig.utf8) == Data(sign(text, key).utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }
}

/// The questions waiting for the owner, and their away switch.
@MainActor
@Observable
final class Desk {
    static let ntfy = "https://apps.tailf7bf45.ts.net:31443"
    /// The hooks treat an away message older than 2 hours as off, so it is said again every 30 minutes.
    static let repeatAway: TimeInterval = 1800

    private(set) var waiting: [DeskQuestion] = []
    /// Questions already read out, so each is announced once.
    @ObservationIgnored private var announced: Set<String> = []
    var unannounced: [DeskQuestion] { waiting.filter { !announced.contains($0.id) && isFresh($0) } }
    @ObservationIgnored private var arrived: [String: Date] = [:]
    private func isFresh(_ q: DeskQuestion) -> Bool {
        Date().timeIntervalSince(arrived[q.id] ?? Date()) < Self.questionLife
    }
    func markAnnounced(_ id: String) { announced.insert(id) }
    private(set) var away = UserDefaults.standard.bool(forKey: "deskAway")
    /// Called with each new question, for Nestor to read it out while the owner is away.
    @ObservationIgnored var onQuestion: ((DeskQuestion) -> Void)?
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var lastAwayPost = Date.distantPast

    func run() {
        guard listening == nil, let key = DeskSeal.key() else { return }
        listening = Task { [weak self] in
            while !Task.isCancelled {
                await self?.listen(key)
                try? await Task.sleep(for: .seconds(10))
            }
        }
        Task { [weak self] in
            while !Task.isCancelled {
                if let self, self.away, Date().timeIntervalSince(self.lastAwayPost) > Self.repeatAway {
                    await self.postAway()
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Turns the away switch on or off, for both machines' hooks.
    func setAway(_ on: Bool) async {
        away = on
        UserDefaults.standard.set(on, forKey: "deskAway")
        await postAway()
        if !on { waiting.removeAll() }
    }

    /// Sends the owner's answer to the session that asked.
    func answer(_ question: DeskQuestion, choices: [String: String]? = nil, text: String? = nil) async -> Bool {
        var body: [String: Any] = ["kind": "answer", "id": question.id]
        if let choices { body["answers"] = choices }
        if let text { body["text"] = text }
        let sent = await post(body)
        if sent { waiting.removeAll { $0.id == question.id } }
        log.notice("answer \(sent ? "sent" : "not sent", privacy: .public) to a \(question.kind.rawValue, privacy: .public) on \(question.host, privacy: .public)")
        return sent
    }

    private func postAway() async {
        if await post(["kind": "away", "on": away]) { lastAwayPost = Date() }
    }

    private func post(_ body: [String: Any]) async -> Bool {
        guard let key = DeskSeal.key(), let message = DeskSeal.seal(body, key),
              let url = URL(string: "\(Self.ntfy)/\(DeskSeal.topic(key))") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(message.utf8)
        request.timeoutInterval = 10
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Follows the topic as a stream, from a little before now.
    private func listen(_ key: Data) async {
        guard let url = URL(string: "\(Self.ntfy)/\(DeskSeal.topic(key))/json?since=15m") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3600
        guard let (bytes, _) = try? await URLSession.shared.bytes(for: request) else { return }
        do {
            for try await line in bytes.lines {
                guard let event = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                      event["event"] as? String == "message", let message = event["message"] as? String,
                      let body = DeskSeal.unseal(message, key) else { continue }
                let posted = Date(timeIntervalSince1970: (event["time"] as? Double) ?? Date().timeIntervalSince1970)
                take(body, posted: posted)
            }
        } catch {
            log.notice("desk stream ended: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A hook gives a question back to its window after 9 minutes; a hook
    /// that was stopped never says so. Older questions are not read out.
    static let questionLife: TimeInterval = 540

    /// One signed message from a hook or from Nestor itself.
    func take(_ body: [String: Any], posted: Date = Date(), now: Date = Date()) {
        switch body["kind"] as? String {
        case "question":
            guard now.timeIntervalSince(posted) < Self.questionLife,
                  let q = DeskQuestion(body), !waiting.contains(where: { $0.id == q.id }) else { return }
            waiting.append(q)
            arrived[q.id] = posted
            log.notice("a \(q.kind.rawValue, privacy: .public) question from \(q.host, privacy: .public)")
            if away { onQuestion?(q) }
        case "closed", "answer":
            if let id = body["id"] as? String { waiting.removeAll { $0.id == id } }
        default:
            break
        }
    }
}
