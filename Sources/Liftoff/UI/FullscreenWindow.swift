import AppKit
import SwiftUI

/// Borderless window covering the whole main screen, menu bar and notch included (spec §5.4).
/// Fullscreen mode is an explicit choice, so it takes key focus at once: Space = Done (manual
/// steps), Return = Open <App> (app steps), S = Skip, Esc = continue in the notch panel. It is a non-activating panel because
/// macOS 14+ may refuse to activate a background app (e.g. when the run starts at unlock), and a
/// plain window of an inactive app never becomes key.
final class FullscreenWindow: NSPanel {
    private let model: SequenceViewModel
    private let hostingView: NSHostingView<FullscreenView>
    private var keyMonitor: Any?
    /// Fading out (run over or switched to the notch): takes no clicks and acts on no keys.
    private(set) var isHiding = false
    /// Stepped back to normal window level so an app the user opens comes in front (app steps).
    private(set) var isBackdrop = false

    init(model: SequenceViewModel) {
        self.model = model
        hostingView = NSHostingView(rootView: FullscreenView(model: model))
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = Self.stageLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        hostingView.sizingOptions = []
        contentView = hostingView
        fitToScreen()
        NotificationCenter.default.addObserver(self, selector: #selector(fitToScreen),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// Above the menu bar, Dock and the notch panel.
    private static let stageLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)

    private var restingLevel: NSWindow.Level { isBackdrop ? .normal : Self.stageLevel }

    /// Drops to normal window level (stays on screen as a backdrop behind the app being opened;
    /// menu bar and Dock become reachable).
    func stepBack() {
        guard !isBackdrop else { return }
        isBackdrop = true
        level = .normal
    }

    func restoreStageLevel() {
        isBackdrop = false
        level = Self.stageLevel
    }

    /// Back above everything, in front and key (non-activating, as at show).
    func comeForward() {
        restoreStageLevel()
        guard !isHiding else { return }
        orderFrontRegardless()
        makeKey()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// AppKit would otherwise push a borderless window below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    @objc private func fitToScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        setFrame(screen.frame, display: true)
        var view = FullscreenView(model: model, topInset: screen.safeAreaInsets.top)
        view.onMore = { [weak self] in self?.showMenu() }
        hostingView.rootView = view
    }

    /// The menu draws at pop-up-menu level, below this window; drop under it while it's open.
    private func showMenu() {
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        NotchMenu.show(for: model)  // blocks until the menu closes
        level = restingLevel
    }

    // MARK: Keys

    override func becomeKey() {
        super.becomeKey()
        // NSHostingView turns Esc into `cancelOperation:` and swallows Space/S, so read keys
        // before dispatch (local monitor: no Accessibility permission, only while key).
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self, self.handleKey(event) else { return event }
            return nil
        }
    }

    override func resignKey() {
        super.resignKey()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Space = Done (Done-only steps), Return = Open <App> (app steps), S = Skip, Esc = switch to the notch panel. Returns whether
    /// the key was used. Shortcuts with ⌘ / ⌃ / ⌥ pass through; a held key's repeats and keys
    /// during the fade-out are swallowed without acting.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return false }
        let action: (() -> Void)? = switch event.keyCode {
        case 49 where model.isDoneOnlyStep: model.onDone          // Space
        case 36 where model.openAppTitle != nil,                  // Return
             76 where model.openAppTitle != nil: model.onOpenApp  // keypad Enter
        case 1 where model.phase == .step: model.onSkip           // S
        case 53: model.onEscapeToNotch                            // Esc
        default: nil
        }
        guard let action else { return false }
        guard !event.isARepeat, !isHiding else { return true }
        action()
        return true
    }

    func setHiding(_ hiding: Bool) {
        isHiding = hiding
        ignoresMouseEvents = hiding
    }
}

/// Shows / hides the fullscreen stage with the 0.4 s fade from spec §5.4.
@MainActor
final class FullscreenPresenter: SequencePresenter {
    let window: FullscreenWindow

    init(model: SequenceViewModel) {
        window = FullscreenWindow(model: model)
    }

    func show() {
        window.setHiding(false)
        window.restoreStageLevel()
        window.fadeIn(duration: 0.4)
        window.makeKey()
    }

    func stepBack() { window.stepBack() }
    func comeForward() { if window.isBackdrop { window.comeForward() } }

    func hide(animated: Bool) {
        window.setHiding(true)
        window.fadeOut(duration: 0.4, animated: animated)
    }
}
