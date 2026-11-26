import SwiftUI

/// What Concierge may spend tokens on, kept in `briefings/settings.json` so
/// the skills and `Scripts/tick.py` read the same switches the window shows.
struct ConciergeSettings: Codable, Equatable {
    /// "YYYY-MM-DD": nothing runs on that day, the morning page included.
    var pausedOn: String? = nil
    var morning = true
    var drafts = true
    var openItems = true
    var learn = true
    var checks = true
    var checkEveryMinutes = 120
    var checkFrom = "09:00"
    var checkTo = "19:00"
    var prep = true
    var prepMinutes = 30
    var wrapup = true
    var wrapupAt = "18:30"
    var notifyMac = true
    var notifyPhone = true
    var checkModel = "haiku"
    var prepModel = "sonnet"
    var wrapupModel = "sonnet"
    /// Say notifications aloud, on the Mac only.
    var speak = true
    /// An `AVSpeechSynthesisVoice` identifier; empty means the best English voice.
    var voice = ""
    var speakFrom = "08:30"
    var speakTo = "21:00"
    /// Stay quiet while an event of today's agenda is on.
    var quietInEvents = true
    /// Local "YYYY-MM-DDTHH:MM": nothing is said before then.
    var silenceUntil: String? = nil
    /// After saying an alert, listen a few seconds for a spoken reply.
    var listenAfter = true
    /// Talking over Concierge stops it and starts your turn.
    var interruptible = true
    /// Listen for "Concierge" while the window is open.
    var wakeWord = true

    static let url = Paths.briefings.appendingPathComponent("settings.json")

    static func load(from url: URL = url) -> ConciergeSettings {
        guard let data = try? Data(contentsOf: url) else { return ConciergeSettings() }
        // Missing keys keep their defaults.
        var base = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(ConciergeSettings()))) as? [String: Any] ?? [:]
        let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        base.merge(saved) { _, new in new }
        guard let merged = try? JSONSerialization.data(withJSONObject: base) else { return ConciergeSettings() }
        return (try? JSONDecoder().decode(ConciergeSettings.self, from: merged)) ?? ConciergeSettings()
    }

    func save(to url: URL = url) {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? e.encode(self) { try? data.write(to: url, options: .atomic) }
    }

    var pausedToday: Bool { pausedOn == BriefingLocator.today() }

    static let minuteFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    func isSilenced(at now: Date = Date()) -> Bool {
        guard let until = silenceUntil.flatMap(Self.minuteFormat.date(from:)) else { return false }
        return now < until
    }

    mutating func silence(until date: Date?) {
        silenceUntil = date.map(Self.minuteFormat.string(from:))
    }

    /// Edits the saved settings in place, for controls outside the Settings window.
    static func update(_ change: (inout ConciergeSettings) -> Void) {
        var s = load()
        change(&s)
        s.save()
    }
}

/// The silence choices, shared by the window's speaker button and Settings.
enum Silence {
    static func forAnHour(from now: Date = Date()) -> Date { now.addingTimeInterval(3600) }
    static func untilTomorrow(from now: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: now).addingTimeInterval(86400)
    }
}

struct SettingsView: View {
    @State private var s = ConciergeSettings.load()
    private let models = ["haiku", "sonnet", "opus"]
    private let voices = Speaker.voices()

    var body: some View {
        Form {
            Section {
                Toggle("Pause everything today", isOn: Binding(
                    get: { s.pausedToday },
                    set: { s.pausedOn = $0 ? BriefingLocator.today() : nil }))
                Text("Nothing runs until tomorrow, the morning page included. Refresh and questions still work.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Morning page") {
                Toggle("Build the morning page", isOn: $s.morning)
                Toggle("Draft replies", isOn: $s.drafts)
                Toggle("Follow open items across days", isOn: $s.openItems)
                Toggle("Learn from what I dismiss", isOn: $s.learn)
            }
            Section("During the day") {
                Toggle("Check for new urgent things", isOn: $s.checks)
                Stepper("Every \(s.checkEveryMinutes) min", value: $s.checkEveryMinutes, in: 30...480, step: 30)
                HStack {
                    TextField("From", text: $s.checkFrom).frame(width: 70)
                    Text("to")
                    TextField("To", text: $s.checkTo).frame(width: 70)
                }
                Picker("Model", selection: $s.checkModel) { ForEach(models, id: \.self) { Text($0) } }
                Toggle("Prepare for meetings", isOn: $s.prep)
                Stepper("\(s.prepMinutes) min before", value: $s.prepMinutes, in: 10...120, step: 5)
                Picker("Model", selection: $s.prepModel) { ForEach(models, id: \.self) { Text($0) } }
                Toggle("Evening wrap-up", isOn: $s.wrapup)
                TextField("At", text: $s.wrapupAt).frame(width: 70)
                Picker("Model", selection: $s.wrapupModel) { ForEach(models, id: \.self) { Text($0) } }
            }
            Section("Tell me") {
                Toggle("Mac notification", isOn: $s.notifyMac)
                Toggle("Phone (ntfy on spark)", isOn: $s.notifyPhone)
                Toggle("Say it aloud on the Mac", isOn: $s.speak)
            }
            Section("Voice") {
                Picker("Voice", selection: $s.voice) {
                    Text("Best English voice").tag("")
                    ForEach(voices, id: \.identifier) { Text(Speaker.label($0)).tag($0.identifier) }
                }
                Button("Test the voice") {
                    Speaker.preview("Good morning. Stephane asks about the mutation assays in the MIT group.", voiceID: s.voice)
                }
                Text("Nicer voices: System Settings › Accessibility › Spoken Content › System voice › Manage Voices. Download a Premium English voice, then pick it here.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Speak between")
                    Spacer()
                    TextField("From", text: $s.speakFrom).labelsHidden().frame(width: 56)
                    Text("and")
                    TextField("To", text: $s.speakTo).labelsHidden().frame(width: 56)
                }
                Toggle("Stay quiet during calendar events", isOn: $s.quietInEvents)
                Toggle("Listen for a reply after an alert", isOn: $s.listenAfter)
                Toggle("Let me interrupt by talking over it", isOn: $s.interruptible)
                Toggle("Listen for \u{201C}Concierge\u{201D} while the window is open", isOn: $s.wakeWord)
                Text("Say \u{201C}Concierge\u{201D}, or \u{201C}Concierge, what\u{2019}s on tomorrow?\u{201D}. Recognition stays on this Mac. Paused while silenced.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if s.isSilenced() {
                        Text("Silenced until \(s.silenceUntil ?? "")".replacingOccurrences(of: "T", with: " "))
                        Spacer()
                        Button("Speak again") { s.silence(until: nil) }
                    } else {
                        Text("Silence")
                        Spacer()
                        Button("1 hour") { s.silence(until: Silence.forAnHour()) }
                        Button("Until tomorrow") { s.silence(until: Silence.untilTomorrow()) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        // The window's speaker button may have changed the file meanwhile.
        .onAppear { s = ConciergeSettings.load() }
        .onChange(of: s) { _, new in new.save() }
    }
}

/// `briefings/updates/<day>.json`: what the daytime jobs found, shown above
/// the page as "Since this morning".
enum Updates {
    static func url(for day: String) -> URL {
        Paths.briefings.appendingPathComponent("updates/\(day).json")
    }

    /// The file's text, or "[]".
    static func json(for day: String) -> String {
        guard let data = try? Data(contentsOf: url(for: day)),
              (try? JSONSerialization.jsonObject(with: data)) is [Any] else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func stamp(for day: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url(for: day).path))?[.modificationDate] as? Date
    }
}
