import AppKit
import SwiftUI

@main
struct ClaudeAssistantApp: App {
    @State private var model = AppModel()

    init() {
        // Dark everywhere, including AppKit chrome the SwiftUI scheme does not reach.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        WindowGroup("Briefing") {
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
