import AppKit
import SwiftUI

@main
struct ConciergeApp: App {
    @State private var model = AppModel()

    init() {
        // Dark everywhere, including AppKit chrome the SwiftUI scheme does not reach.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        WindowGroup("Concierge") {
            ContentView()
                .environment(model)
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
