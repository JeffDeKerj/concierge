import Foundation

/// One briefing page on disk: today's, or the newest one when today's is missing.
struct BriefingPage: Equatable {
    let url: URL
    /// The date in the file name, `YYYY-MM-DD`.
    let day: String
    let isToday: Bool

    /// "Monday 23 November" for the notice line.
    var longDay: String {
        guard let date = Paths.dayFormatter.date(from: day) else { return day }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = Paths.dayFormatter.timeZone
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: date)
    }

    var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

/// The small line under the name in the top bar: the page's day, and when
/// Nestor last updated itself.
enum TopLine {
    static func text(day: String?, updated: Date?, now: Date = Date()) -> String {
        [day, updated.map { "updated \(time($0, now: now))" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// "13:07" today, "Thu 18:31" on another day, on the owner's clock.
    static func time(_ date: Date, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = Paths.dayFormatter.timeZone
        let sameDay = Paths.dayFormatter.string(from: date) == Paths.dayFormatter.string(from: now)
        f.dateFormat = sameDay ? "HH:mm" : "EEE HH:mm"
        return f.string(from: date)
    }
}

enum BriefingLocator {
    static let dayPattern = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}$"#)

    static func today(now: Date = Date()) -> String {
        Paths.dayFormatter.string(from: now)
    }

    /// Today's page when it exists, else the newest dated page in the folder, else nil.
    static func pick(now: Date = Date()) -> BriefingPage? {
        let day = today(now: now)
        let todayURL = Paths.briefing(named: day)
        if FileManager.default.fileExists(atPath: todayURL.path) {
            return BriefingPage(url: todayURL, day: day, isToday: true)
        }
        guard let newest = datedPages().last else { return nil }
        return BriefingPage(url: Paths.briefing(named: newest), day: newest, isToday: false)
    }

    /// Every `YYYY-MM-DD.html` in the folder, oldest first.
    static func datedPages() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Paths.briefings.path)) ?? []
        return names.compactMap { name -> String? in
            guard name.hasSuffix(".html") else { return nil }
            let stem = String(name.dropLast(5))
            let range = NSRange(stem.startIndex..., in: stem)
            return dayPattern.firstMatch(in: stem, range: range) == nil ? nil : stem
        }.sorted()
    }
}
