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
            HStack(alignment: .bottom, spacing: 0) {
                FaceButton()
                    .padding(.leading, 12)
                    .padding(.bottom, 6)
                VStack(spacing: 0) {
                    VoiceStrip()
                    FollowUpPanel()
                }
            }
        }
        .background(Color(red: 0.06, green: 0.07, blue: 0.08))
        .toolbar {
            ToolbarItem(placement: .primaryAction) { TalkButton() }
            ToolbarItem(placement: .primaryAction) { SilenceButton() }
            ToolbarItem(placement: .navigation) {
                if let page = model.page {
                    Text(page.longDay)
                        .foregroundStyle(.secondary)
                }
            }
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
        .help(quiet ? "Concierge is silent" : "Concierge speaks its notifications")
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

/// The microphone in the toolbar: talk to Concierge, or stop talking.
struct TalkButton: View {
    @Environment(Conversation.self) private var talk

    var body: some View {
        Button {
            talk.isActive ? talk.stop() : talk.start()
        } label: {
            Label(talk.isActive ? "Stop talking" : "Talk",
                  systemImage: talk.isActive ? "mic.fill" : "mic")
        }
        .foregroundStyle(talk.isActive ? Color.accentColor : Color.primary)
        .help(talk.isActive ? "Stop the conversation" : "Talk to Concierge (⌘T)")
        .keyboardShortcut("t", modifiers: .command)
        .accessibilityIdentifier("toolbar.talk")
    }
}

/// One line above the question box while a spoken conversation runs.
struct VoiceStrip: View {
    @Environment(Conversation.self) private var talk

    var body: some View {
        if talk.isActive || talk.error != nil {
            HStack(spacing: 8) {
                switch talk.state {
                // The face beside it shows which of these it is; this says it in words.
                case .listening(let words):
                    Text(words.isEmpty ? "Listening…" : words).lineLimit(2)
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

/// Concierge's face beside the question box. It shows what Concierge is
/// doing, sleeps while silenced, and a click starts or stops a conversation.
struct FaceButton: View {
    @Environment(Conversation.self) private var talk
    @State private var hovered = false
    @State private var s = ConciergeSettings.load()
    private var silenced: Bool { s.isSilenced() }

    var body: some View {
        Button {
            talk.isActive ? talk.stop() : talk.start()
        } label: {
            FaceView(style: s.faceStyle,
                     expression: Face.expression(state: talk.state, hasError: talk.error != nil,
                                                 silenced: silenced, hovered: hovered),
                     level: { talk.voiceLevel(at: $0) })
                .frame(width: 60, height: 60)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(talk.isActive ? "Stop the conversation" : silenced ? "Concierge is silenced. Click to talk anyway" : "Talk to Concierge (⌘T)")
        .accessibilityLabel(talk.isActive ? "Stop talking" : "Talk to Concierge")
        .accessibilityIdentifier("face")
        .onReceive(NotificationCenter.default.publisher(for: ConciergeSettings.changed)) { _ in
            s = ConciergeSettings.load()
        }
        // A silence ends by the clock.
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            s = ConciergeSettings.load()
        }
    }
}
