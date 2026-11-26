import AppKit
import CoreGraphics

/// Why the app asks whether to start a run: the Mac came (back) to the user, or the Learn wizard
/// that held a wake back has closed.
public enum WakeReason: String, Sendable {
    case launch, systemWake, screensWake, unlock, learnWizardClosed
}

/// Reports system wake, screen wake and screen unlock.
@MainActor
final class WakeMonitor {
    private let onWake: @MainActor (WakeReason) -> Void
    private var tokens: [NSObjectProtocol] = []

    init(onWake: @escaping @MainActor (WakeReason) -> Void) {
        self.onWake = onWake
    }

    func start() {
        guard tokens.isEmpty else { return }
        func handler(_ reason: WakeReason) -> @Sendable (Notification) -> Void {
            { [weak self] _ in MainActor.assumeIsolated { self?.onWake(reason) } }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        tokens.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main,
                                            using: handler(.systemWake)))
        tokens.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main,
                                            using: handler(.screensWake)))
        tokens.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: handler(.unlock)))
    }
}

/// True when the login session is not on the console or its screen is locked (e.g. the Mac woke to
/// the lock screen). No session dictionary at all counts as locked.
public func sessionIsLocked() -> Bool {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
    let onConsole = session["kCGSSessionOnConsoleKey"] as? Bool ?? false
    let screenLocked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
    return !onConsole || screenLocked
}
