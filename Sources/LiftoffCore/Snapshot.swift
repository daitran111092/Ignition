import Foundation

public struct RunningApp: Hashable, Sendable {
    public var bundleID: String?
    public var name: String

    public init(bundleID: String?, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public struct SystemSnapshot: Equatable, Sendable {
    public var devices: Set<DeviceSignature>
    public var runningApps: Set<RunningApp>
    /// nil when Music's state is unknown (not running / not queried).
    public var musicPlaying: Bool?

    public init(devices: Set<DeviceSignature> = [], runningApps: Set<RunningApp> = [], musicPlaying: Bool? = nil) {
        self.devices = devices
        self.runningApps = runningApps
        self.musicPlaying = musicPlaying
    }
}

public enum SystemEvent: Equatable, Sendable {
    case snapshot(SystemSnapshot)
    case appActivated(RunningApp)
    case musicStateChanged(playing: Bool)
}

extension AppMatch {
    /// Bundle id in `bundleIDs`, or name in `names` (case-insensitive).
    public func matches(_ app: RunningApp) -> Bool {
        if let id = app.bundleID, bundleIDs.contains(id) { return true }
        return names.contains { $0.caseInsensitiveCompare(app.name) == .orderedSame }
    }
}
