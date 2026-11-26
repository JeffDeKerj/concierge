import AppKit
import SwiftUI

@main
struct ConciergeApp: App {
    @State private var model: AppModel
    @State private var conversation: Conversation
    @State private var wake: WakeListener
    @State private var face: FacePanel
    @State private var place = FacePlace()

    init() {
        // launchd starts the app with --tick to run the scheduled jobs: no window.
        if CommandLine.arguments.contains(TickLauncher.flag) { exit(TickLauncher.run()) }
        // The job runner speaks notifications through the app: no window.
        if CommandLine.arguments.contains(Speaker.flag) { exit(Speaker.runFromCommandLine(CommandLine.arguments)) }
        // Dark everywhere, including AppKit chrome the SwiftUI scheme does not reach.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let model = AppModel()
        // One microphone session for the wake word and the conversation.
        let io = VoiceIO()
        let conversation = Conversation(model: model, io: io)
        _model = State(initialValue: model)
        _conversation = State(initialValue: conversation)
        let wake = WakeListener(conversation: conversation, io: io)
        _wake = State(initialValue: wake)
        wake.run()
        let face = FacePanel(conversation: conversation)
        _face = State(initialValue: face)
        face.run()
        // Alerts from the job runner, said here so Concierge can hear the reply.
        DistributedNotificationCenter.default().addObserver(
            forName: Speaker.alertNotification, object: nil, queue: .main) { note in
            guard let text = note.userInfo?["text"] as? String else { return }
            MainActor.assumeIsolated {
                conversation.alert(text, listen: ConciergeSettings.load().listenAfter)
            }
        }
    }

    var body: some Scene {
        WindowGroup(Brand.name) {
            ContentView()
                .environment(model)
                .environment(conversation)
                .environment(place)
                .preferredColorScheme(.dark)
                .frame(minWidth: 560, minHeight: 600)
        }
        .defaultSize(width: 600, height: 900)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Agent") {
                Picker("Agent", selection: Binding(
                    get: { model.backendID },
                    set: { model.backendID = $0 })) {
                    ForEach(AgentBackends.all, id: \.id) { backend in
                        Text(backend.displayName).tag(backend.id)
                    }
                }
                .pickerStyle(.inline)
                .disabled(model.isRefreshing || model.isAsking)
                Divider()
                // Menus get no environment from the window, so the model is passed in.
                ModelMenu(model: model, operation: .refresh, selection: Binding(
                    get: { model.refreshModel }, set: { model.refreshModel = $0 }))
                ModelMenu(model: model, operation: .ask, selection: Binding(
                    get: { model.askModel }, set: { model.askModel = $0 }))
                Divider()
                Button("Reveal Run Log in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Paths.briefings.appendingPathComponent("runs.jsonl")])
                }
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh Briefing") { model.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isRefreshing)
                Button("Reveal Briefings in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Paths.briefings])
                }
                Divider()
                Button(model.dismissed.isEmpty
                       ? "Forget Dismissed Items"
                       : "Forget \(model.dismissed.count) Dismissed \(model.dismissed.count == 1 ? "Item" : "Items")") {
                    model.forgetDismissed()
                }
                .disabled(model.dismissed.isEmpty)
                .help("Show every dismissed item again and let the generator list them next time")
            }
        }
        Settings { SettingsView().preferredColorScheme(.dark) }
    }
}

/// A submenu of the current agent's models for one operation. Greyed out
/// when the agent offers no choice.
private struct ModelMenu: View {
    let model: AppModel
    let operation: Operation
    let selection: Binding<String>

    var body: some View {
        let options = model.backend.models
        Menu(operation.label) {
            Picker(operation.label, selection: selection) {
                ForEach(options) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .disabled(options.count <= 1)
    }
}
