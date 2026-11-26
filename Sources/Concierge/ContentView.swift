import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let notice = model.notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.04))
                    .accessibilityIdentifier("notice")
            }
            if let error = model.refreshError {
                // Capped: a generator that explains itself at length must not
                // push the page off the window.
                ScrollView {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                .frame(maxHeight: 140)
                .accessibilityIdentifier("refreshError")
            }

            BriefingWebView(page: model.page, reloadToken: model.reloadToken,
                            dismissedKeys: model.dismissedKeys,
                            updatesJSON: model.updatesJSON,
                            onDismiss: { model.dismiss($0) },
                            onRestore: { model.restore(key: $0) })
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            CostLine()
            VoiceStrip()
            FollowUpPanel()
        }
        .background(Color(red: 0.06, green: 0.07, blue: 0.08))
        .overlay { StagedFace() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { SilenceButton() }
            ToolbarItem(placement: .navigation) {
                if let page = model.page {
                    Text(page.longDay)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .navigation) { FaceButton() }
            ToolbarItem(placement: .primaryAction) {
                if model.isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        if let since = model.refreshStartedAt {
                            Text(since, style: .timer)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            model.cancelRefresh()
                        } label: {
                            Label("Stop", systemImage: "xmark.circle")
                        }
                        .help("Stop the generator")
                        .accessibilityIdentifier("toolbar.stop")
                    }
                } else {
                    Button {
                        model.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Build today's briefing again (⌘R)")
                    .accessibilityIdentifier("toolbar.refresh")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The scheduled task may have written a new page while the app sat
            // in the background, or overnight.
            model.checkForNewPage()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            model.checkForNewPage()
        }
        .task {
            if CommandLine.arguments.contains("--refresh") {
                model.refresh()
            }
        }
    }
}

/// What the last Refresh and the last follow-up cost, and today's total.
/// Prices are API prices: on a subscription nothing is billed, but this is
/// what the run would have cost.
struct CostLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let refresh = model.lastRefresh?.summary ?? ""
        let ask = model.lastAsk?.summary ?? ""
        if !refresh.isEmpty || !ask.isEmpty || model.today.runs > 0 {
            VStack(alignment: .leading, spacing: 2) {
                if !refresh.isEmpty {
                    Text("Refresh: \(refresh)")
                        .accessibilityIdentifier("cost.refresh")
                }
                if !ask.isEmpty {
                    Text("Reply: \(ask)")
                        .accessibilityIdentifier("cost.ask")
                }
                if model.today.runs > 0 {
                    Text("Today: \(String(format: "$%.2f", model.today.costUSD)) over \(model.today.runs) \(model.today.runs == 1 ? "run" : "runs") · \(model.backend.displayName)")
                        .accessibilityIdentifier("cost.today")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .help("API prices for the runs. On a subscription nothing is billed; this is what the same calls would cost.")
        }
    }
}

/// The question field and the reply under the page.
struct FollowUpPanel: View {
    @Environment(AppModel.self) private var model
    @FocusState private var fieldFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            if let answer = model.answer {
                ScrollView {
                    Text(answer)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                }
                .frame(minHeight: 60, maxHeight: 220)
                .accessibilityIdentifier("followup.answer")
            }
            if let error = model.askError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("followup.error")
            }
            HStack(spacing: 8) {
                TextField("Ask a follow-up about the briefing…", text: $model.question)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .disabled(model.isAsking)
                    .onSubmit { model.ask() }
                    .accessibilityIdentifier("followup.input")
                if model.isAsking {
                    ProgressView().controlSize(.small)
                    Button("Stop") { model.cancelAsk() }
                        .accessibilityIdentifier("followup.stop")
                } else {
                    Button("Ask") { model.ask() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.question.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("followup.ask")
                }
            }
        }
        .padding(12)
    }
}

/// The speaker in the toolbar: silence Concierge's voice for a while.
struct SilenceButton: View {
    @State private var s = ConciergeSettings.load()

    var body: some View {
        Menu {
            if s.isSilenced() {
                Button("Speak again") { change { $0.silence(until: nil) } }
            } else {
                Button("Silence for 1 hour") { change { $0.silence(until: Silence.forAnHour()) } }
                Button("Silence until tomorrow") { change { $0.silence(until: Silence.untilTomorrow()) } }
            }
            Divider()
            Toggle("Speak notifications", isOn: Binding(
                get: { s.speak }, set: { on in change { $0.speak = on } }))
        } label: {
            Label("Voice", systemImage: quiet ? "speaker.slash" : "speaker.wave.2")
        }
        .help(quiet ? "\(Brand.name) is silent" : "\(Brand.name) speaks its notifications")
        .accessibilityIdentifier("toolbar.silence")
        .onAppear { s = ConciergeSettings.load() }
        // Settings or the clock may have ended a silence.
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            s = ConciergeSettings.load()
        }
    }

    private var quiet: Bool { !s.speak || s.isSilenced() }

    private func change(_ edit: (inout ConciergeSettings) -> Void) {
        ConciergeSettings.update(edit)
        s = ConciergeSettings.load()
    }
}

/// One line above the question box while a spoken conversation runs.
struct VoiceStrip: View {
    @Environment(Conversation.self) private var talk

    var body: some View {
        if talk.isActive || talk.error != nil {
            HStack(spacing: 8) {
                switch talk.state {
                // The face shows which of these it is, with the words it hears
                // under it; this says it plainly and holds the Stop button.
                case .listening:
                    Text("Listening…")
                case .thinking:
                    Text("Thinking…")
                case .speaking:
                    Text("Speaking…")
                case .idle:
                    Text(talk.error ?? "").foregroundStyle(.red).textSelection(.enabled)
                }
                Spacer()
                if talk.isActive {
                    Button("Stop") { talk.stop() }.accessibilityIdentifier("voice.stop")
                }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .accessibilityIdentifier("voice.strip")
        }
    }
}

/// Where the face is: the spot it rests at in the top bar, and whether it
/// has left that spot for the middle of the window.
@MainActor
@Observable
final class FacePlace {
    /// The middle of the resting face, from the window's left edge.
    var restX: CGFloat?
    /// The face is on stage, or on its way back.
    var away = false
}

/// Concierge's face in the top bar, where it rests. It shows what Concierge
/// is doing, sleeps while silenced, and a click starts a conversation.
struct FaceButton: View {
    @Environment(Conversation.self) private var talk
    @Environment(FacePlace.self) private var place
    @State private var hovered = false
    @State private var s = ConciergeSettings.load()
    private var silenced: Bool { s.isSilenced() }

    var body: some View {
        Button {
            talk.isActive ? talk.stop() : talk.start()
        } label: {
            FaceView(style: s.faceStyle,
                     expression: Face.expression(state: .idle, hasError: talk.error != nil,
                                                 silenced: silenced, hovered: hovered))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                // While it is on stage, its place in the bar is empty.
                .opacity(place.away ? 0 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .background(PlaceProbe { x in
            if abs((place.restX ?? -1) - x) > 0.5 { place.restX = x }
        })
        .help(talk.isActive ? "Stop the conversation" : silenced ? "\(Brand.name) is silenced. Click to talk anyway (⌘T)" : "Talk to \(Brand.name) (⌘T)")
        .keyboardShortcut("t", modifiers: .command)
        .accessibilityLabel(talk.isActive ? "Stop talking" : "Talk to \(Brand.name)")
        .accessibilityIdentifier("toolbar.talk")
        .onReceive(NotificationCenter.default.publisher(for: ConciergeSettings.changed)) { _ in
            s = ConciergeSettings.load()
        }
        // A silence ends by the clock.
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            s = ConciergeSettings.load()
        }
    }
}

/// The face on stage. When a conversation starts it leaves the top bar,
/// glides to the middle of the window and grows; what it hears shows under
/// it. When the conversation ends it glides back. A click on it stops the
/// conversation; the page around it stays usable.
struct StagedFace: View {
    @Environment(Conversation.self) private var talk
    @Environment(FacePlace.self) private var place
    @State private var staged = false
    @State private var style = ConciergeSettings.load().faceStyle

    static let stageSide: CGFloat = 150
    static let restSide: CGFloat = 30

    /// Where the middle of the face is, in a window area of `size`: on
    /// stage a little above the middle, at rest just under its spot in
    /// the top bar, out of sight.
    static func centre(staged: Bool, restX: CGFloat?, in size: CGSize) -> CGPoint {
        staged ? CGPoint(x: size.width / 2, y: size.height * 0.4)
               : CGPoint(x: restX ?? size.width / 2, y: -restSide)
    }

    var body: some View {
        GeometryReader { area in
            if place.away {
                let side = staged ? Self.stageSide : Self.restSide
                Button {
                    talk.stop()
                } label: {
                    FaceView(style: style,
                             expression: Face.expression(state: talk.state, hasError: talk.error != nil,
                                                         silenced: false, hovered: false),
                             level: { talk.voiceLevel(at: $0) }, staysPut: false)
                        .frame(width: side, height: side)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Stop the conversation")
                .accessibilityIdentifier("face.stage")
                // A soft shadow keeps it readable over the page's text.
                .background {
                    Circle()
                        .fill(RadialGradient(colors: [.black.opacity(0.85), .black.opacity(0)],
                                             center: .center, startRadius: side * 0.45, endRadius: side * 0.95))
                        .frame(width: side * 1.9, height: side * 1.9)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    if staged, case .listening(let words) = talk.state, !words.isEmpty {
                        Text(words)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .truncationMode(.head)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.06, green: 0.07, blue: 0.08).opacity(0.94),
                                        in: RoundedRectangle(cornerRadius: 10))
                            .frame(width: min(area.size.width - 40, 420))
                            .fixedSize(horizontal: false, vertical: true)
                            .offset(y: 56)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("face.heard")
                    }
                }
                .position(Self.centre(staged: staged, restX: place.restX, in: area.size))
            }
        }
        .onChange(of: talk.isActive, initial: true) { _, active in
            if active {
                place.away = true
                // On the next turn of the run loop, so the glide starts from its resting place.
                DispatchQueue.main.async {
                    withAnimation(.spring(duration: 0.6, bounce: 0.3)) { staged = true }
                }
            } else if place.away {
                withAnimation(.spring(duration: 0.5, bounce: 0.1)) { staged = false }
                Task {
                    try? await Task.sleep(for: .seconds(0.55))
                    if !talk.isActive { place.away = false }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ConciergeSettings.changed)) { _ in
            style = ConciergeSettings.load().faceStyle
        }
    }
}

/// Reports where the middle of the view it sits behind is, from the
/// window's left edge.
private struct PlaceProbe: NSViewRepresentable {
    var report: (CGFloat) -> Void

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.report = report
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) { probe.report = report }

    final class Probe: NSView {
        var report: (CGFloat) -> Void = { _ in }
        private var watching: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let watching { NotificationCenter.default.removeObserver(watching) }
            watching = window.map { window in
                NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
                                                       object: window, queue: .main) { [weak self] _ in self?.tell() }
            }
            tell()
        }

        override func layout() {
            super.layout()
            tell()
        }

        private func tell() {
            guard window != nil else { return }
            let x = convert(bounds, to: nil).midX
            // Not during a view update.
            DispatchQueue.main.async { [report] in report(x) }
        }

        deinit {
            if let watching { NotificationCenter.default.removeObserver(watching) }
        }
    }
}
