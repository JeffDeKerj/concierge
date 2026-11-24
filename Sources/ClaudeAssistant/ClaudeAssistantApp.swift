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
            CommandGroup(after: .toolbar) {
                Button("Refresh Briefing") { model.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isRefreshing)
                Button("Reveal Briefings in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Paths.briefings])
                }
            }
        }
    }
}
