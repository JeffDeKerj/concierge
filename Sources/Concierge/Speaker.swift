import AppKit
import AVFoundation

/// Concierge's voice: the Mac's own speech voices, so nothing said leaves the Mac.
///
/// The job runner speaks through the app's binary (`Concierge --say "…"`), so
/// the voice chosen in Settings is the one heard, with no second voice list.
enum Speaker {
    static let flag = "--say"
    /// Posted by `--say` to a running Concierge, which then speaks and listens.
    static let alertNotification = Notification.Name("local.jeffdekerj.concierge.alert")

    /// The voices of a language, best quality first. Premium and Enhanced voices appear
    /// here once downloaded in System Settings › Accessibility › Spoken Content.
    static func voices(for language: Language = .english) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language.rawValue) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
    }

    static func label(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality = switch voice.quality {
        case .premium: " · Premium"
        case .enhanced: " · Enhanced"
        default: ""
        }
        let region = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
        return "\(voice.name) (\(region))\(quality)"
    }

    /// The saved voice, else the best voice installed for the language.
    static func voice(id: String, language: Language = .english) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(identifier: id) ?? voices(for: language).first
    }

    static func utterance(_ text: String, voiceID: String, language: Language = .english) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.voice = voice(id: voiceID, language: language)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        return u
    }

    /// For the Test button in Settings.
    @MainActor static let shared = AVSpeechSynthesizer()

    @MainActor static func preview(_ text: String, voiceID: String, language: Language = .english) {
        shared.stopSpeaking(at: .immediate)
        shared.speak(utterance(text, voiceID: voiceID, language: language))
    }

    /// `Concierge --say <voice id> <text>`: speaks and returns when done.
    static func runFromCommandLine(_ args: [String]) -> Int32 {
        guard let i = args.firstIndex(of: flag), args.count > i + 2 else { return 2 }
        // A running window speaks instead, so it can listen for a reply.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.activationPolicy == .regular
           }) {
            DistributedNotificationCenter.default().postNotificationName(
                alertNotification, object: nil, userInfo: ["text": args[i + 2]], deliverImmediately: true)
            return 0
        }
        let done = Finished()
        let synth = AVSpeechSynthesizer()
        synth.delegate = done
        synth.speak(utterance(args[i + 2], voiceID: args[i + 1]))
        let deadline = Date().addingTimeInterval(90)
        while !done.flag && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return done.flag ? 0 : 1
    }

    private final class Finished: NSObject, AVSpeechSynthesizerDelegate {
        var flag = false
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { flag = true }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { flag = true }
    }
}
