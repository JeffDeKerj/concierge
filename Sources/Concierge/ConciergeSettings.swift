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
}

struct SettingsView: View {
    @State private var s = ConciergeSettings.load()
    private let models = ["haiku", "sonnet", "opus"]

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
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
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
