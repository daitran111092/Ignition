import Foundation

/// Devices of `kind` present in `after` that no device in `before` matches — i.e. what the user just
/// plugged in or powered on. Removed devices are ignored. Sorted by name for a stable order.
public func newDevices(before: SystemSnapshot, after: SystemSnapshot, kind: DeviceKind) -> [DeviceSignature] {
    after.devices
        .filter { device in device.kind == kind && !before.devices.contains { $0.matches(device) } }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

/// The "Learn my devices" wizard (spec §6.3): everything off → snapshot; then for cables, dock,
/// keyboard, mouse and K7 in turn, whatever appears of that step's device kind becomes the step's signature.
public struct LearnSession: Sendable {
    public enum Page: Equatable, Sendable {
        case unplug
        case device(StepID)
        case finished

        /// The device kind each learnable step is recognised by.
        public var kind: DeviceKind? {
            guard case .device(let step) = self else { return nil }
            switch step {
            case .cables: return .display
            case .dock: return .usb
            case .keyboard, .mouse: return .hid
            default: return .audioOutput
            }
        }
    }

    public static let learnableSteps: [StepID] = [.cables, .dock, .keyboard, .mouse, .dac]

    /// Steps with no usable built-in guess: until one of them is learned the wizard opens by itself.
    /// (Keyboard and mouse have name hints, so they never force it open.)
    public static let essentialSteps: [StepID] = [.cables, .dock, .dac]

    public private(set) var page: Page = .unplug
    public private(set) var learned: [StepID: [DeviceSignature]]
    private var baseline = SystemSnapshot()

    /// `learned` is the current config's; steps where nothing new shows up keep their old signature.
    public init(learned: [StepID: [DeviceSignature]]) {
        self.learned = learned
    }

    /// Everything is unplugged / off: remember what is still there.
    public mutating func begin(_ snapshot: SystemSnapshot) {
        baseline = snapshot
        page = .device(Self.learnableSteps[0])
    }

    /// What appeared since the page's baseline.
    public func detect(_ snapshot: SystemSnapshot) -> [DeviceSignature] {
        guard let kind = page.kind else { return [] }
        return newDevices(before: baseline, after: snapshot, kind: kind)
    }

    /// Something unrelated showed up: forget it and watch only for changes from now on.
    public mutating func retry(_ snapshot: SystemSnapshot) {
        baseline = snapshot
    }

    /// Stores what was detected (if anything) and moves on, with `snapshot` as the next baseline.
    public mutating func next(_ snapshot: SystemSnapshot) {
        guard case .device(let step) = page else { return }
        let found = detect(snapshot)
        if !found.isEmpty { learned[step] = found }
        baseline = snapshot
        if let i = Self.learnableSteps.firstIndex(of: step), i + 1 < Self.learnableSteps.count {
            page = .device(Self.learnableSteps[i + 1])
        } else {
            page = .finished
        }
    }
}

/// The Learn wizard opens by itself until at least one of cables / dock / K7 has a learned device.
public func needsDeviceLearning(_ config: LiftoffConfig) -> Bool {
    LearnSession.essentialSteps.allSatisfy { (config.learned[$0] ?? []).isEmpty }
}
