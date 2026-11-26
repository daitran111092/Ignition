import AppKit

/// A window that presents the pre-flight sequence (notch panel or fullscreen stage).
/// The coordinator holds one and swaps it when the display mode changes mid-run.
@MainActor
protocol SequencePresenter: AnyObject {
    func show()
    func hide(animated: Bool)
    /// Gets out of the way of an app the user opens (fullscreen: drops to a backdrop behind it).
    func stepBack()
    /// Back to the presenter's normal place in front, if it stepped back.
    func comeForward()
}

extension SequencePresenter {
    func stepBack() {}
    func comeForward() {}
}

extension NSWindow {
    /// Fades the window in (if needed) and orders it front without stealing focus.
    func fadeIn(duration: TimeInterval) {
        if !isVisible { alphaValue = 0 }
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = 1
        }
    }

    /// Fades the window out and orders it out — unless it was shown again in the meantime.
    func fadeOut(duration: TimeInterval, animated: Bool) {
        guard animated, isVisible else {
            orderOut(nil)
            alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
            }
        })
    }
}

extension NotchPanel: SequencePresenter {}
