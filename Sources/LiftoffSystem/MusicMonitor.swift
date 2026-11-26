import Foundation

/// Tracks Apple Music's play state from its `com.apple.Music.playerInfo` distributed notification.
@MainActor
final class MusicMonitor {
    /// Last state seen from the notification; nil until one arrives.
    private(set) var lastPlaying: Bool?
    private let onStateChange: @MainActor (Bool) -> Void
    private var token: NSObjectProtocol?

    init(onStateChange: @escaping @MainActor (Bool) -> Void) {
        self.onStateChange = onStateChange
    }

    func start() {
        guard token == nil else { return }
        token = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
        ) { [weak self] note in
            let playing = (note.userInfo?["Player State"] as? String) == "Playing"
            MainActor.assumeIsolated {
                self?.lastPlaying = playing
                self?.onStateChange(playing)
            }
        }
    }

    /// Asks Music directly via AppleScript. Never launches Music; nil when it isn't running,
    /// on error, or when Automation permission is denied.
    func queryPlaying() -> Bool? {
        let source = "tell application \"Music\" to if it is running then return player state as text"
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil,
              let state = result.stringValue else { return nil }
        return state == "playing"
    }
}
