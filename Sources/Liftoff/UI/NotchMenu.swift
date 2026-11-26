import AppKit

/// The panel's "⋯" menu. A plain `NSMenu` (not a SwiftUI `Menu`) so it works from a
/// non-activating panel and so the button itself renders in `ImageRenderer` snapshots.
@MainActor
enum NotchMenu {
    /// `afterAction` runs after whichever item is chosen (the notch panel gives up key focus).
    static func show(for model: SequenceViewModel, afterAction: @escaping () -> Void = {}) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionItem("Skip pre-flight today") { model.onSkipAll(); afterAction() })
        menu.addItem(.separator())
        menu.addItem(ActionItem(model.voiceMuted ? "Unmute voice" : "Mute voice") { model.onToggleVoice(); afterAction() })
        menu.addItem(ActionItem(model.musicMuted ? "Unmute music" : "Mute music") { model.onToggleMusic(); afterAction() })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private final class ActionItem: NSMenuItem {
        private let handler: () -> Void

        init(_ title: String, _ handler: @escaping () -> Void) {
            self.handler = handler
            super.init(title: title, action: #selector(fire), keyEquivalent: "")
            target = self
        }

        @available(*, unavailable)
        required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        @objc private func fire() { handler() }
    }
}
