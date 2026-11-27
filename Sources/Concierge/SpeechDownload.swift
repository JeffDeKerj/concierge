import Foundation
import Speech

/// Whether a language's speech recognition files are on this Mac.
enum SpeechFilesStatus: Equatable {
    case installed
    /// Not here, and this Mac can fetch them.
    case missing
    /// This Mac cannot fetch them from an app.
    case unsupported
}

/// The Mac's store of speech recognition files, one set per language.
protocol SpeechFiles: Sendable {
    func status(of language: Language) async -> SpeechFilesStatus
    /// Downloads and installs the language. `progress` gets 0 to 1 as it goes.
    func fetch(_ language: Language, progress: @escaping @Sendable (Double) -> Void) async throws
}

/// The real store. It asks for the dictation files, because those are the
/// ones `SFSpeechRecognizer` uses when it recognises on the Mac.
struct MacSpeechFiles: SpeechFiles {
    func status(of language: Language) async -> SpeechFilesStatus {
        guard #available(macOS 26, *) else { return .unsupported }
        switch await AssetInventory.status(forModules: [Self.module(language)]) {
        case .installed: return .installed
        case .supported, .downloading: return .missing
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    func fetch(_ language: Language, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard #available(macOS 26, *) else { return }
        // No request means there is nothing left to install.
        guard let request = try await AssetInventory.assetInstallationRequest(
            supporting: [Self.module(language)]) else { return }
        let watcher = Task {
            while !Task.isCancelled {
                progress(request.progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { watcher.cancel() }
        try await request.downloadAndInstall()
    }

    @available(macOS 26, *)
    private static func module(_ language: Language) -> DictationTranscriber {
        DictationTranscriber(locale: language.locale, preset: .shortDictation)
    }
}

/// One language's download, as Settings shows it.
@MainActor @Observable
final class SpeechDownload {
    enum State: Equatable {
        case checking
        case missing
        case downloading(Double)
        case installed
        case failed(String)
        /// This Mac cannot fetch the language from an app.
        case unavailable
    }

    private(set) var state = State.checking
    private let language: Language
    private let files: any SpeechFiles
    private var fetching = false

    init(_ language: Language, files: any SpeechFiles = MacSpeechFiles()) {
        self.language = language
        self.files = files
    }

    /// Asks the Mac where the language stands. A failed download stays
    /// shown, with its reason, until it is tried again.
    func refresh() async {
        guard !fetching else { return }
        let status = await files.status(of: language)
        guard !fetching else { return }
        if case .failed = state, status == .missing { return }
        state = Self.state(for: status)
    }

    /// Downloads the language. Does nothing while a download runs.
    func start() async {
        guard !fetching else { return }
        fetching = true
        defer { fetching = false }
        state = .downloading(0)
        do {
            try await files.fetch(language) { [weak self] fraction in
                Task { @MainActor in self?.report(fraction) }
            }
            state = await files.status(of: language) == .installed
                ? .installed
                : .failed("The download ended, but \(language.name) is still not on this Mac.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func report(_ fraction: Double) {
        guard fetching, case .downloading = state else { return }
        state = .downloading(min(max(fraction, 0), 1))
    }

    static func state(for status: SpeechFilesStatus) -> State {
        switch status {
        case .installed: .installed
        case .missing: .missing
        case .unsupported: .unavailable
        }
    }
}
