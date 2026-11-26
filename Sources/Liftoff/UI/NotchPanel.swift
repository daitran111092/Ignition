import AppKit
import Observation
import SwiftUI
import LiftoffCore

/// Borderless, non-activating panel pinned over the notch (or top-centre under the menu bar).
/// It never steals focus: it only becomes key after a click on the card, then Space = Done,
/// S = Skip, Esc = Skip all. The window is exactly the card's size and draws nothing outside
/// the card shape, so clicks beside it fall through to the app underneath.
final class NotchPanel: NSPanel {
    private let model: SequenceViewModel
    private var geometry: NotchGeometry
    private let hostingView: NSHostingView<NotchView>
    private var allowsKey = false
    /// Fading out (run over or replaced): takes no clicks and acts on no keys.
    private var isHiding = false
    private var shrinkTask: Task<Void, Never>?
    private var shadowTask: Task<Void, Never>?
    private var keyMonitor: Any?

    init(model: SequenceViewModel) {
        self.model = model
        geometry = Self.currentGeometry()
        hostingView = NSHostingView(rootView: NotchView(model: model, geometry: geometry))
        // Window-server shadow (follows the card's alpha) instead of a SwiftUI shadow, which would
        // need a transparent margin around the card that intercepts clicks.
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        hostingView.sizingOptions = []
        contentView = hostingView
        hostingView.rootView = makeRootView()
        applyLayout(animatedShrink: false)
        observeLayout()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // MARK: Focus

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !allowsKey, cardContains(event.locationInWindow) {
            allowsKey = true
            makeKey()
        }
        super.sendEvent(event)
    }

    override func becomeKey() {
        super.becomeKey()
        // NSHostingView turns Esc into `cancelOperation:` and swallows Space/S, so read keys
        // before dispatch. A local monitor needs no Accessibility permission and only runs
        // while this panel is key.
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self, self.handleKey(event) else { return event }
            return nil
        }
    }

    override func resignKey() {
        super.resignKey()
        allowsKey = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Space = Done (Done-only steps), S = Skip, Esc = Skip all. Returns whether the key was used.
    /// Shortcuts with ⌘ / ⌃ / ⌥ pass through; a held key's repeats and keys during the fade-out
    /// are swallowed without acting.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return false }
        let action: (() -> Void)? = switch event.keyCode {
        case 49 where model.isDoneOnlyStep: model.onDone          // Space
        case 1 where model.phase == .step: model.onSkip           // S
        case 53 where model.phase != .liftoff: model.onSkipAll    // Esc
        default: nil
        }
        guard let action else { return false }
        guard !event.isARepeat, !isHiding else { return true }
        action()
        relinquishKey()
        return true
    }

    /// Hands keyboard focus back to the frontmost app (after Done / Skip / a ⋯ menu action) so later
    /// typing doesn't land in the panel. Re-ordering without `makeKey` drops key status; a fading
    /// panel is left to order itself out.
    private func relinquishKey() {
        allowsKey = false
        guard isKeyWindow, !isHiding else { return }
        orderOut(nil)
        orderFrontRegardless()
    }

    /// The visible card (window minus the transparent top "ears"/corners), in window coordinates.
    private func cardContains(_ point: NSPoint) -> Bool {
        let layout = NotchLayout(geometry: geometry, phase: model.phase, isExpanded: model.isExpanded)
        let card = NSRect(x: (frame.width - layout.size.width) / 2 + layout.ear,
                          y: frame.height - layout.size.height,
                          width: layout.size.width - 2 * layout.ear, height: layout.size.height)
        return card.contains(point)
    }

    private func makeRootView() -> NotchView {
        var view = NotchView(model: model, geometry: geometry)
        view.onAction = { [weak self] in self?.relinquishKey() }
        return view
    }

    // MARK: Presenter

    func show() {
        isHiding = false
        ignoresMouseEvents = false
        fadeIn(duration: 0.25)
    }

    func hide(animated: Bool) {
        isHiding = true
        allowsKey = false
        ignoresMouseEvents = true  // clicks during the fade reach the app underneath
        fadeOut(duration: 0.25, animated: animated)
    }

    /// Keep the panel over the menu bar / notch; AppKit would otherwise push it below.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    // MARK: Layout

    /// Re-applies the window frame whenever expansion or phase changes. Growing happens at once
    /// (the SwiftUI spring then fills the space); shrinking waits for the collapse animation.
    private func observeLayout() {
        withObservationTracking {
            _ = model.isExpanded
            _ = model.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyLayout(animatedShrink: true)
                self?.observeLayout()
            }
        }
    }

    private func applyLayout(animatedShrink: Bool) {
        let layout = NotchLayout(geometry: geometry, phase: model.phase, isExpanded: model.isExpanded)
        let target = geometry.panelFrame(size: layout.size)
        shrinkTask?.cancel()
        let grows = target.width >= frame.width && target.height >= frame.height
        if grows || !animatedShrink {
            setFrame(target, display: true)
        } else {
            // Keep the larger frame while the collapse animates (the uncovered area is fully
            // transparent, so it passes clicks through), then settle on the target.
            setFrame(geometry.panelFrame(size: CGSize(width: max(target.width, frame.width),
                                                      height: max(target.height, frame.height))), display: true)
            shrinkTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled, let self else { return }
                self.setFrame(target, display: true)
            }
        }
        // The window-server shadow is computed from the content's alpha: refresh it once the
        // spring has settled on the new shape.
        shadowTask?.cancel()
        shadowTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.invalidateShadow()
        }
    }

    @objc private func screensChanged() {
        geometry = Self.currentGeometry()
        hostingView.rootView = makeRootView()
        applyLayout(animatedShrink: false)
    }

    static func currentGeometry() -> NotchGeometry {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            let fallback = CGRect(x: 0, y: 0, width: 1440, height: 900)
            return NotchGeometry(screenFrame: fallback, visibleFrame: fallback, safeAreaTop: 0,
                                 auxiliaryTopLeft: nil, auxiliaryTopRight: nil)
        }
        return NotchGeometry(screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
                             safeAreaTop: screen.safeAreaInsets.top,
                             auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
                             auxiliaryTopRight: screen.auxiliaryTopRightArea)
    }
}
