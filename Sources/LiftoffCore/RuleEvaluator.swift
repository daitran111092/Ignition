import Foundation

/// Everything observed since the run started; lets steps tick on transient events.
public struct EventLog: Sendable {
    private var activatedApps: [RunningApp] = []
    public private(set) var musicStartedPlaying = false

    public init() {}

    public mutating func record(_ e: SystemEvent) {
        switch e {
        case .appActivated(let app): activatedApps.append(app)
        case .musicStateChanged(let playing): if playing { musicStartedPlaying = true }
        case .snapshot: break
        }
    }

    public func activated(_ m: AppMatch) -> Bool {
        activatedApps.contains { m.matches($0) }
    }
}

public func isSatisfied(_ step: StepDefinition, learned: [DeviceSignature], snapshot: SystemSnapshot, log: EventLog) -> Bool {
    switch step.rule {
    case .manual, .final:
        return false
    case .devices(let kind, let hint):
        if !learned.isEmpty {
            return learned.allSatisfy { sig in snapshot.devices.contains { sig.matches($0) } }
        }
        let ofKind = snapshot.devices.filter { $0.kind == kind }
        if let hint, !hint.isEmpty {
            return ofKind.contains { $0.name.range(of: hint, options: .caseInsensitive) != nil }
        }
        return kind == .display && !ofKind.isEmpty
    case .appRunning(let m):
        return snapshot.runningApps.contains { m.matches($0) }
    case .appActivated(let m):
        return log.activated(m)
    case .musicPlaying:
        return snapshot.musicPlaying == true || log.musicStartedPlaying
    }
}

/// True when only the user's Done can tick the step: manual steps, and device steps whose rule can
/// never match (a USB / audio rule with no name hint and nothing learned). Mirrors `isSatisfied`.
public func needsManualConfirm(_ step: StepDefinition, learned: [DeviceSignature]) -> Bool {
    switch step.rule {
    case .manual:
        return true
    case .devices(let kind, let hint):
        return learned.isEmpty && (hint ?? "").isEmpty && kind != .display
    case .appRunning, .appActivated, .musicPlaying, .final:
        return false
    }
}
