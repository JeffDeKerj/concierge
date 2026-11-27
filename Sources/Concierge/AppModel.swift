import AppKit
import Foundation
import Observation

/// App state: which page is on screen, the running Refresh, the follow-up
/// question and its answer, and what each run cost.
@MainActor
@Observable
final class AppModel {
    // The page
    private(set) var page: BriefingPage?
    /// One line shown above the page when it is not today's, or there is none.
    private(set) var notice: String?
    /// What looks odd about the page on screen, one line each: links to
    /// unknown places, items that cannot be dismissed for good.
    private(set) var pageProblems: [String] = []
    /// Bumped whenever the web view must read the file again.
    private(set) var reloadToken = 0
    /// When Nestor last updated itself: the newest of the page being written
    /// and a check, prep note, wrap-up or Refresh that finished well.
    private(set) var lastUpdated: Date?

    // The agent
    var backendID: String = AgentBackends.current().id {
        didSet {
            UserDefaults.standard.set(backendID, forKey: AgentBackends.settingsKey)
            loadModels()
        }
    }
    var backend: AgentBackend { AgentBackends.named(backendID) }
    private let log: RunLog

    /// The model each operation runs on with the current backend. Saved per
    /// backend, so switching agents brings back each one's own choice.
    var refreshModel: String = "" {
        didSet { if !loadingModels { ModelSettings.set(refreshModel, for: .refresh, backend: backend) } }
    }
    var askModel: String = "" {
        didSet { if !loadingModels { ModelSettings.set(askModel, for: .ask, backend: backend) } }
    }
    private var loadingModels = false

    private func loadModels() {
        loadingModels = true
        refreshModel = ModelSettings.model(for: .refresh, backend: backend)
        askModel = ModelSettings.model(for: .ask, backend: backend)
        loadingModels = false
    }

    // Refresh
    private(set) var isRefreshing = false
    private(set) var refreshStartedAt: Date?
    private(set) var refreshError: String?
    private(set) var lastRefresh: RunReport?
    private let refreshRunner = AgentRunner()

    // Follow-up
    var question = ""
    private(set) var answer: String?
    private(set) var isAsking = false
    private(set) var askError: String?
    private(set) var lastAsk: RunReport?
    private let askRunner = AgentRunner()
    /// Set when the owner stopped the answer being written.
    private var askStopped = false
    /// The question box's own conversation, kept apart from page builds and checks.
    private let askSessions = AskSessionStore()

    /// Cost and count of today's runs, from the log.
    private(set) var today: (costUSD: Double, runs: Int) = (0, 0)

    // Dismissed items
    private let dismissStore: DismissStore
    /// Items the owner is done with. Hidden on the page; the generator leaves
    /// them out of the next one.
    private(set) var dismissed: [DismissedItem] = []
    /// What the daytime jobs found today, as JSON for the page.
    private(set) var updatesJSON = "[]"
    private var updatesStamp: Date?

    var dismissedKeys: [String] { dismissed.filter { $0.isHidden() }.map(\.key) }

    init(log: RunLog = RunLog(), dismissStore: DismissStore = DismissStore()) {
        self.log = log
        self.dismissStore = dismissStore
        loadModels()
        loadPage()
        today = log.total()
        dismissed = dismissStore.removeExpired()
        loadUpdates()
    }

    /// Re-reads today's updates file when it changed; the page shows it
    /// without a reload.
    func loadUpdates() {
        let day = BriefingLocator.today()
        let stamp = Updates.stamp(for: day)
        guard stamp != updatesStamp || updatesStamp == nil else { return }
        updatesStamp = stamp
        updatesJSON = Updates.json(for: day)
    }

    // MARK: Page

    /// Pick today's page, or the newest one, and say so.
    func loadPage() {
        let picked = BriefingLocator.pick()
        page = picked
        if let picked, picked.isToday {
            notice = nil
        } else if let picked {
            notice = "Today's briefing is not there yet. Showing \(picked.longDay)."
        } else {
            notice = "No briefing yet. Press Refresh to build today's."
        }
        loadLastUpdated()
        let html = picked.flatMap { try? String(contentsOf: $0.url, encoding: .utf8) }
        pageProblems = html.map(PageGuard.problems(in:)) ?? []
        // An item the page brought back with news is shown again.
        if let html, let written = picked?.modificationDate {
            let returned = PageGuard.returnedKeys(in: html)
            if !returned.isEmpty { dismissed = dismissStore.clearReturned(keys: returned, pageWritten: written) }
        }
    }

    private func loadLastUpdated() {
        lastUpdated = [log.lastUpdate(), page?.modificationDate].compactMap { $0 }.max()
    }

    /// Re-read the folder. Reloads the page when a newer file appeared or the
    /// current one changed since it was shown.
    func checkForNewPage() {
        let before = page
        let beforeStamp = before?.modificationDate
        let hiddenBefore = dismissed.count
        dismissed = dismissStore.removeExpired()
        loadPage()
        if dismissed.count != hiddenBefore { reloadToken += 1 }
        loadUpdates()
        if page != before || page?.modificationDate != beforeStamp {
            reloadToken += 1
            // A new page (the morning run, say) makes an old refresh warning stale.
            if !isRefreshing { refreshError = nil }
        }
    }

    // MARK: Refresh

    /// Run the briefing generator headless and reload the page as soon as the
    /// file on disk changes.
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshStartedAt = Date()
        refreshError = nil

        let today = BriefingLocator.today()
        let target = Paths.briefing(named: today)
        let stampBefore = modificationDate(of: target)
        let backend = self.backend

        Task {
            var refused: [String] = []
            // Watch the file while the generator runs; it is written before
            // the generator's own check step ends.
            let watcher = Task {
                var lastSeen = stampBefore
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    let now = self.modificationDate(of: target)
                    if now != lastSeen {
                        lastSeen = now
                        self.loadPage()
                        self.reloadToken += 1
                    }
                }
            }
            defer { watcher.cancel() }

            do {
                let output = try await refreshRunner.run(backend, arguments: backend.refreshArguments(model: refreshModel))
                let report = backend.parse(output)
                record(kind: "refresh", report)
                if report.isError {
                    refreshError = "\(backend.displayName) failed: \(report.errorText)"
                }
                refused = report.deniedTools
            } catch {
                refreshError = error.localizedDescription
            }

            // One last look, in case the file landed in the final two seconds.
            // Refused tools are worth a warning only when the page did not get written:
            // a run that tried a shell command, was refused and read the file instead is fine.
            if modificationDate(of: target) != stampBefore {
                loadPage()
                reloadToken += 1
            } else if refreshError == nil {
                let said = lastRefresh?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                refreshError = "The generator finished but did not write today's page."
                    + (said.isEmpty ? "" : " It said: \(said)")
                    + (refused.isEmpty ? "" : " Refused tools: \(Set(refused).sorted().joined(separator: ", ")).")
            }
            isRefreshing = false
            refreshStartedAt = nil
        }
    }

    func cancelRefresh() {
        refreshRunner.stop()
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: Follow-up

    /// Send the question to the app's own conversation. The first question of
    /// the day, or after the page was rebuilt, starts one that is told the page.
    func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isAsking else { return }
        isAsking = true
        Task { @MainActor in _ = await perform(q, prompt: nil) }
    }

    /// Asks and returns the answer, or nil on failure or when a question is
    /// already running. `prompt` is what the model reads when it differs from
    /// what the owner said (spoken questions ask for a short answer).
    @MainActor @discardableResult
    /// `onText` gets the answer piece by piece while it is written, when
    /// the agent can send it that way.
    func ask(_ q: String, prompt: String? = nil, onText: ((String) -> Void)? = nil) async -> String? {
        guard !isAsking else { return nil }
        isAsking = true
        return await perform(q, prompt: prompt, onText: onText)
    }

    /// One run of the agent for a question. The answer shows as it is
    /// written when the agent streams.
    @MainActor
    private func runAsk(_ backend: AgentBackend, _ text: String, _ conversation: AskConversation, model: String,
                        onText: ((String) -> Void)?) async throws -> RunReport {
        guard let streaming = backend.streamingAskArguments(question: text, conversation: conversation, model: model) else {
            return backend.parse(try await askRunner.run(backend, arguments: backend.askArguments(question: text, conversation: conversation, model: model)))
        }
        // One reader, so the pieces stay in order.
        let (lines, feed) = AsyncStream<String>.makeStream()
        let reader = Task { @MainActor in
            for await line in lines {
                guard let piece = backend.textDelta(inLine: line) else { continue }
                let soFar = (self.answer ?? "") + piece
                if !soFar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.answer = soFar }
                onText?(piece)
            }
        }
        defer { feed.finish() }
        let output = try await askRunner.run(backend, arguments: streaming) { feed.yield($0) }
        feed.finish()
        await reader.value
        return backend.parse(output)
    }

    @MainActor
    private func perform(_ q: String, prompt: String?, onText: ((String) -> Void)? = nil) async -> String? {
        askError = nil
        answer = nil
        askStopped = false
        question = q
        let backend = self.backend
        let model = askModel
        let sent = prompt ?? q
        defer { isAsking = false }
        do {
            let day = BriefingLocator.today()
            let pageStamp = page?.modificationDate?.timeIntervalSince1970
            let updatesStamp = Updates.stamp(for: day)?.timeIntervalSince1970
            let updates = Updates.json(for: day)
            var session = askSessions.load().flatMap { $0.fits(day: day, backend: backend.id, pageStamp: pageStamp) ? $0 : nil }
            var report = RunReport()
            if let known = session {
                // Tell a running conversation what the daytime jobs found since it last heard.
                let news = known.updatesStamp == updatesStamp ? nil : AskContext.news(updates)
                let text = (news.map { "(\($0))\n\n" } ?? "") + sent
                report = try await runAsk(backend, text, .resume(id: known.id), model: model, onText: onText)
                if backend.isNoConversation(report), !askStopped { session = nil }
            }
            if session == nil {
                let id = UUID().uuidString.lowercased()
                let opening = AskContext.opening(pageHTML: page.flatMap { try? String(contentsOf: $0.url, encoding: .utf8) },
                                                 pagePath: page?.url.path, updatesJSON: updates,
                                                 briefingsPath: Paths.briefings.path)
                report = try await runAsk(backend, opening + sent, .fresh(id: id), model: model, onText: onText)
                session = AskSession(id: report.sessionID ?? id, day: day, backend: backend.id, pageStamp: pageStamp)
            }
            if !report.isError || askStopped, var kept = session {
                kept.updatesStamp = updatesStamp
                askSessions.save(kept)
            }
            if askStopped {
                // Stopped by the owner (the Stop button, or talking over it):
                // what was written so far stands, and nothing is an error.
                question = ""
                return answer
            }
            record(kind: "ask", report)
            if report.isError {
                askError = "\(backend.displayName) failed: \(report.errorText)"
                return nil
            }
            answer = report.text.isEmpty ? "(no reply)" : report.text
            question = ""
            return report.text
        } catch {
            askError = error.localizedDescription
            return nil
        }
    }

    func cancelAsk() {
        guard isAsking else { return }
        askStopped = true
        askRunner.stop()
    }

    // MARK: Dismissed items

    /// Called from the page when the owner presses an item's "done" button.
    func dismiss(_ item: DismissedItem) {
        dismissed = dismissStore.add(item)
        dismissStore.recordHistory(item)
    }

    /// Called from the page when a dismissed item is put back.
    func restore(key: String) {
        dismissed = dismissStore.remove(key: key)
    }

    /// Empties the list and shows every item again.
    func forgetDismissed() {
        dismissStore.removeAll()
        dismissed = []
        reloadToken += 1
    }

    // MARK: Cost

    private func record(kind: String, _ report: RunReport) {
        let charged = log.append(kind: kind, backend: backendID, report: report)
        if kind == "refresh" { lastRefresh = charged } else { lastAsk = charged }
        today = log.total()
        loadLastUpdated()
    }
}
