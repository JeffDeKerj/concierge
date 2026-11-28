import Foundation
import IOKit
import Observation

/// Counts the looks at the microphone that found nothing at all, and says
/// when Nestor went deaf and when it hears again.
///
/// A microphone that sends pure silence is not a quiet room: it is a headset
/// that is switched off or muted while still being the Mac's input. A quiet
/// room on a live microphone is about -58 dBFS, never nothing.
struct SilenceWatch {
    /// Looks in a row before it counts as deaf. The listener looks every 5 seconds: a minute.
    static let looksToDeaf = 12

    enum Change: Equatable { case deaf, hearsAgain }

    private var silentLooks = 0
    var isDeaf: Bool { silentLooks >= Self.looksToDeaf }

    /// One look at the last few seconds of the microphone.
    mutating func look(silent: Bool) -> Change? {
        if silent {
            silentLooks += 1
            return silentLooks == Self.looksToDeaf ? .deaf : nil
        }
        return forget()
    }

    /// Nobody is listening any more, or sound came back.
    mutating func forget() -> Change? {
        defer { silentLooks = 0 }
        return isDeaf ? .hearsAgain : nil
    }
}

/// Whether Nestor can hear, for the face in the top bar. The wake-word
/// listener sets it; the owner is told once each time hearing is lost.
@MainActor
@Observable
final class Hearing {
    enum Problem: Equatable {
        /// The microphone runs and sends nothing at all.
        case silent(microphone: String)
        /// No microphone could be started for a minute.
        case noMicrophone
    }

    private(set) var problem: Problem?
    @ObservationIgnored private let lidClosed: () -> Bool
    @ObservationIgnored private let tell: (String) -> Void

    init(lidClosed: @escaping () -> Bool = Lid.isClosed, tell: @escaping (String) -> Void = Hearing.notify) {
        self.lidClosed = lidClosed
        self.tell = tell
    }

    /// What is wrong and what to do about it, or nil while Nestor hears.
    var words: String? { problem.map { Self.words(for: $0, lidClosed: lidClosed()) } }

    /// Sets what is wrong, or nil for nothing. The owner is told when
    /// hearing is lost, not while it stays lost.
    func set(_ new: Problem?) {
        guard new != problem else { return }
        let heard = problem == nil
        problem = new
        if heard, let words { tell(words) }
    }

    /// With the lid closed the Mac's own microphone is cut, so the headset
    /// is the only microphone there is and no setting helps.
    nonisolated static func words(for problem: Problem, lidClosed: Bool) -> String {
        switch (problem, lidClosed) {
        case (.silent(let microphone), true):
            "\(Brand.name) cannot hear you: \(microphone) sends only silence. Switch the headset on."
        case (.silent(let microphone), false):
            "\(Brand.name) cannot hear you: \(microphone) sends only silence. Switch the headset on, or choose This Mac\u{2019}s own microphone in Settings \u{203A} Voice."
        case (.noMicrophone, true):
            "\(Brand.name) cannot hear you: no microphone works while the lid is closed. Switch the headset on."
        case (.noMicrophone, false):
            "\(Brand.name) cannot hear you: no microphone could be started."
        }
    }

    /// A notification on the Mac, the way the job runner sends its own.
    nonisolated static func notify(_ words: String) {
        func quoted(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let run = Process()
        run.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        run.arguments = ["-e", "display notification \(quoted(words)) with title \(quoted(Brand.name))"]
        run.standardOutput = FileHandle.nullDevice
        run.standardError = FileHandle.nullDevice
        try? run.run()
    }
}

/// The Mac's lid.
enum Lid {
    /// Whether the lid is shut, as at the desk on an outside screen. False on a Mac with no lid.
    static func isClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let state = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (state?.takeRetainedValue() as? Bool) ?? false
    }
}
