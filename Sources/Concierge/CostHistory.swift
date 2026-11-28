import SwiftUI

/// What Nestor cost, day by day, from `briefings/runs.jsonl`. Prices are API
/// prices: on a subscription nothing is billed.
enum CostHistory {
    /// The kinds of run, as the owner knows them.
    enum Part: CaseIterable {
        case page, questions, daytime, other

        static func of(kind: String) -> Part {
            switch kind {
            case "refresh", "morning", "morning-test": .page
            case "ask": .questions
            case "check", "prep", "wrapup": .daytime
            default: .other
            }
        }
    }

    struct Day: Identifiable, Equatable {
        /// `yyyy-MM-dd` in Europe/London, which also sorts by date.
        var id: String
        var page = 0.0
        var questions = 0.0
        var daytime = 0.0
        var other = 0.0
        var runs = 0
        var failed = 0
        var total: Double { page + questions + daytime + other }

        /// "Sat 28 Nov".
        var label: String {
            guard let date = Paths.dayFormatter.date(from: id) else { return id }
            return Self.labelFormat.string(from: date)
        }

        private static let labelFormat: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.timeZone = Paths.dayFormatter.timeZone
            f.dateFormat = "EEE d MMM"
            return f
        }()
    }

    /// One line per day that had runs, newest first. Pure, for tests.
    static func days(_ entries: [RunLog.Entry]) -> [Day] {
        var byDay: [String: Day] = [:]
        for e in entries {
            let key = Paths.dayFormatter.string(from: e.when)
            var day = byDay[key] ?? Day(id: key)
            let cost = e.costUSD ?? 0
            switch Part.of(kind: e.kind) {
            case .page: day.page += cost
            case .questions: day.questions += cost
            case .daytime: day.daytime += cost
            case .other: day.other += cost
            }
            day.runs += 1
            if e.failed { day.failed += 1 }
            byDay[key] = day
        }
        return byDay.values.sorted { $0.id > $1.id }
    }

    static func dollars(_ value: Double) -> String { String(format: "$%.2f", value) }
}

/// The window with the cost of every day, opened from the cost line or the Agent menu.
struct CostHistoryView: View {
    static let windowID = "cost-history"

    @State private var days: [CostHistory.Day] = []
    @State private var order = [KeyPathComparator(\CostHistory.Day.id, order: .reverse)]
    @State private var filter = ""
    @State private var rowHeight = 22.0

    private var shown: [CostHistory.Day] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let kept = query.isEmpty ? days : days.filter { "\($0.label) \($0.id)".lowercased().contains(query) }
        return kept.sorted(using: order)
    }

    var body: some View {
        let rows = shown
        let most = rows.map(\.total).max() ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TextField("Filter by day, as \u{201C}Sat\u{201D} or \u{201C}2026-11\u{201D}", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .accessibilityIdentifier("costs.filter")
                Spacer()
                Text("Row height")
                    .foregroundStyle(.secondary)
                Slider(value: $rowHeight, in: 18...44)
                    .frame(width: 110)
                    .accessibilityIdentifier("costs.rowHeight")
                Button {
                    reload()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }
            Table(rows, sortOrder: $order) {
                TableColumn("Day", value: \.id) { day in
                    Text(day.label).frame(height: rowHeight)
                }
                .width(min: 80, ideal: 90)
                TableColumn("Total", value: \.total) { day in
                    // A bar against the dearest day shown, to see the shape at a glance.
                    HStack(spacing: 6) {
                        Text(CostHistory.dollars(day.total)).monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                        GeometryReader { area in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor.opacity(0.7))
                                .frame(width: most > 0 ? area.size.width * day.total / most : 0, height: 6)
                                .frame(maxHeight: .infinity)
                        }
                    }
                }
                .width(min: 120, ideal: 170)
                TableColumn("Morning page", value: \.page) { money($0.page) }
                    .width(min: 70, ideal: 90)
                TableColumn("Questions", value: \.questions) { money($0.questions) }
                    .width(min: 60, ideal: 75)
                TableColumn("Daytime jobs", value: \.daytime) { money($0.daytime) }
                    .width(min: 70, ideal: 90)
                TableColumn("Runs", value: \.runs) { day in
                    Text(day.failed > 0 ? "\(day.runs) (\(day.failed) failed)" : "\(day.runs)")
                        .monospacedDigit()
                        .foregroundStyle(day.failed > 0 ? .orange : .primary)
                }
                .width(min: 50, ideal: 110)
            }
            .accessibilityIdentifier("costs.table")
            HStack {
                let sum = rows.map(\.total).reduce(0, +)
                Text("\(rows.count) \(rows.count == 1 ? "day" : "days") · \(CostHistory.dollars(sum)) in all"
                     + (rows.isEmpty ? "" : " · \(CostHistory.dollars(sum / Double(rows.count))) a day"))
                Spacer()
                Text("API prices. On a subscription nothing is billed.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(minWidth: 640, minHeight: 320)
        .preferredColorScheme(.dark)
        .onAppear(perform: reload)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in reload() }
    }

    private func money(_ value: Double) -> some View {
        Text(value > 0 ? CostHistory.dollars(value) : "–")
            .monospacedDigit()
            .foregroundStyle(value > 0 ? .primary : .secondary)
            .frame(height: rowHeight)
    }

    private func reload() {
        days = CostHistory.days(RunLog().entries())
    }
}

/// The Agent menu's item that opens the window. Menus get no app
/// environment, but the system's own `openWindow` is there.
struct CostHistoryMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Cost History") { openWindow(id: CostHistoryView.windowID) }
            .keyboardShortcut("y", modifiers: [.command, .shift])
    }
}
