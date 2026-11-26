import Foundation

/// Where to find the app an app step waits for, so the card can offer "Open <App>".
public struct AppLaunchTarget: Equatable, Sendable {
    /// Short name for the button: "Teams", "Apple Music", "Agent Factory".
    public var displayName: String
    /// Tried first, in order (Launch Services lookup).
    public var bundleIDs: [String]
    /// App bundle names (without `.app`), looked up in `searchDirectories` when no bundle id resolves.
    public var names: [String]

    public init(displayName: String, bundleIDs: [String], names: [String]) {
        self.displayName = displayName
        self.bundleIDs = bundleIDs
        self.names = names
    }

    public var buttonTitle: String { "Open \(displayName)" }

    /// Candidate bundle paths for `names`, most specific first (`~/Applications` holds Safari web
    /// apps such as Agent Factory, which have no bundle id).
    public func candidatePaths(home: String) -> [String] {
        let dirs = ["\(home)/Applications", "/Applications", "/System/Applications"]
        return names.flatMap { name in dirs.map { "\($0)/\(name).app" } }
    }
}

/// The app an app step (app running / app in front / Apple Music playing) waits for; nil for
/// device, manual and final steps. Opening Apple Music is enough for the music step (no auto-play).
public func appLaunchTarget(for step: StepDefinition) -> AppLaunchTarget? {
    switch step.rule {
    case .appRunning(let m), .appActivated(let m):
        return AppLaunchTarget(displayName: waitingNames[step.id] ?? m.names.first ?? step.title,
                               bundleIDs: m.bundleIDs, names: m.names)
    case .musicPlaying:
        return AppLaunchTarget(displayName: "Apple Music", bundleIDs: ["com.apple.Music"], names: ["Music"])
    case .manual, .devices, .final:
        return nil
    }
}
