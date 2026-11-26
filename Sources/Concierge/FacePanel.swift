import AppKit
import SwiftUI

/// The face in a corner of the screen, for when Concierge talks while its
/// window is out of sight. A call by name gets a face that listens and
/// answers, not a window that jumps in front of the work. It never takes
/// the keyboard; a click on it brings the window forward.
@MainActor
final class FacePanel {
    private let conversation: Conversation
    private var panel: NSPanel?
    private var closing: Task<Void, Never>?
    private var wasActive = false

    init(conversation: Conversation) { self.conversation = conversation }

    func run() {
        watch()
        // The window is coming, or has come, forward: its own face takes over.
        for name in [NSApplication.didBecomeActiveNotification, Conversation.willShowWindow] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hideNow() }
            }
        }
    }

    private func watch() {
        withObservationTracking {
            _ = conversation.isActive
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.watch()
            }
        }
    }

    /// Shows the face when a conversation starts out of sight, and lets it
    /// go shortly after the conversation ends.
    private func update() {
        let active = conversation.isActive
        guard active != wasActive else { return }
        wasActive = active
        if active {
            closing?.cancel()
            if ConciergeSettings.load().floatingFace, !Self.windowInSight { show() }
        } else {
            closing = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                self?.fadeOut()
            }
        }
    }

    /// Whether the owner can see Concierge's own window, and so its face.
    static var windowInSight: Bool {
        NSApp.windows.contains { window in
            !(window is NSPanel) && window.canBecomeMain && window.isVisible && !window.isMiniaturized
                && window.occlusionState.contains(.visible)
                && window.identifier?.rawValue.contains("Settings") != true
        }
    }

    private func show() {
        let panel = self.panel ?? make()
        self.panel = panel
        if let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.maxX - panel.frame.width - 16, y: area.minY + 16))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
    }

    private func fadeOut() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; panel.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated {
                // Shown again meanwhile: leave it.
                if panel.alphaValue < 0.05 { panel.orderOut(nil) }
            }
        }
    }

    private func hideNow() {
        closing?.cancel()
        panel?.orderOut(nil)
    }

    private func make() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 200),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        // Stays on screen while the app itself is hidden.
        panel.canHide = false
        panel.isReleasedWhenClosed = false
        panel.contentView = FirstClickHost(rootView: FloatingFace(talk: conversation) {
            Conversation.showWindow()
        })
        return panel
    }
}

/// Takes the click that reaches it while another app is in front.
private final class FirstClickHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The face with what it is hearing under it.
private struct FloatingFace: View {
    let talk: Conversation
    let open: () -> Void
    @State private var style = ConciergeSettings.load().faceStyle

    var body: some View {
        VStack(spacing: 4) {
            Button(action: open) {
                FaceView(style: style, expression: Face.expression(state: talk.state, hasError: talk.error != nil,
                                                     silenced: false, hovered: false),
                         level: { talk.voiceLevel(at: $0) })
                    .frame(width: 132, height: 132)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(Brand.name)")
            Text(caption)
                .font(.callout)
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.head)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(red: 0.06, green: 0.07, blue: 0.08).opacity(0.92),
                            in: RoundedRectangle(cornerRadius: 9))
                .opacity(caption.isEmpty ? 0 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: ConciergeSettings.changed)) { _ in
            style = ConciergeSettings.load().faceStyle
        }
    }

    private var caption: String {
        switch talk.state {
        case .listening(let words): words.isEmpty ? "Listening…" : words
        case .thinking: "Thinking…"
        case .speaking: ""
        case .idle: talk.error ?? ""
        }
    }
}
