import AppKit
import Foundation
import Observation

/// App state: which page is on screen, the running Refresh, and the follow-up
/// question and its answer.
@MainActor
@Observable
final class AppModel {
    // The page
    private(set) var page: BriefingPage?
    /// One line shown above the page when it is not today's, or there is none.
    private(set) var notice: String?
    /// Bumped whenever the web view must read the file again.
    private(set) var reloadToken = 0

    // Refresh
    private(set) var isRefreshing = false
    private(set) var refreshStartedAt: Date?
    private(set) var refreshError: String?
    private let refreshRunner = ClaudeRunner()

    // Follow-up
    var question = ""
    private(set) var answer: String?
    private(set) var isAsking = false
    private(set) var askError: String?
    private let askRunner = ClaudeRunner()

    init() {
        loadPage()
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
    }

    /// Re-read the folder. Reloads the page when a newer file appeared or the
    /// current one changed since it was shown.
    func checkForNewPage() {
        let before = page
        let beforeStamp = before?.modificationDate
        loadPage()
        if page != before || page?.modificationDate != beforeStamp {
            reloadToken += 1
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

        Task {
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
                let out = try await refreshRunner.run(arguments: ["-p", "/briefing"])
                if out.status != 0 {
                    refreshError = ClaudeError.failed(status: out.status, output: out.combined).localizedDescription
                }
            } catch {
                refreshError = error.localizedDescription
            }

            // One last look, in case the file landed in the final two seconds.
            if modificationDate(of: target) != stampBefore {
                loadPage()
                reloadToken += 1
            } else if refreshError == nil {
                refreshError = "The generator finished but did not write today's page."
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

    /// Send the question to the most recent conversation in the project folder.
    /// When there is none yet, start one that points at the page on screen.
    func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isAsking else { return }
        isAsking = true
        askError = nil
        answer = nil

        Task {
            do {
                var out = try await askRunner.run(arguments: ["-p", "--continue", "--output-format", "text", q])
                if out.status != 0, out.combined.localizedCaseInsensitiveContains("no conversation") {
                    let intro = page.map { "Regarding the briefing page at \($0.url.path): " } ?? ""
                    out = try await askRunner.run(arguments: ["-p", "--output-format", "text", intro + q])
                }
                if out.status == 0 {
                    answer = out.text.isEmpty ? "(no reply)" : out.text
                    question = ""
                } else {
                    askError = ClaudeError.failed(status: out.status, output: out.combined).localizedDescription
                }
            } catch {
                askError = error.localizedDescription
            }
            isAsking = false
        }
    }

    func cancelAsk() {
        askRunner.stop()
    }
}
