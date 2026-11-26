import Foundation

/// Bridges C callbacks (IOKit, CoreGraphics) that may arrive on any thread to a main-actor handler.
/// Passed to C APIs as an opaque `refcon`; `fire()` is safe to call from any thread.
final class MainRelay: Sendable {
    private let handler: @MainActor @Sendable () -> Void

    init(_ handler: @escaping @MainActor @Sendable () -> Void) {
        self.handler = handler
    }

    func fire() {
        let handler = self.handler
        DispatchQueue.main.async { MainActor.assumeIsolated { handler() } }
    }
}
