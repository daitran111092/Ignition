import Foundation

/// One thing the coordinator does, in order, while a run is on screen.
public enum RunCommand: Equatable, Sendable {
    case perform(EngineAction)
    /// The current step has ticked and its line has been spoken: pause `advancePause`, then `advance()`.
    case pauseThenAdvance
}

/// A single pre-flight run: wraps `SequenceEngine` with the sequencing and guards the app needs
/// (advance after a tick, nothing after the run is over, resume display, one Music query).
public struct RunSession: Sendable {
    /// The beat between a step's confirm line and the next step.
    public static let advancePause: Duration = .milliseconds(500)

    public let resumeAt: Int?
    private var engine: SequenceEngine
    private let steps: [StepDefinition]
    private var musicQueried = false
    /// The voice line being spoken (reported by the coordinator), nil between lines.
    public private(set) var speaking: LineKey?

    /// Finished (liftoff) or dismissed (skip all): later calls return no commands.
    public private(set) var isOver = false

    public init(config: LiftoffConfig, resumeAt: Int?) {
        self.resumeAt = resumeAt
        engine = SequenceEngine(config: config, resumeAt: resumeAt)
        steps = config.steps
    }

    public mutating func start(_ snapshot: SystemSnapshot) -> [RunCommand] { run(engine.start(snapshot)) }
    public mutating func handle(_ event: SystemEvent) -> [RunCommand] { run(engine.handle(event)) }
    public mutating func confirmManual() -> [RunCommand] { run(engine.confirmManual()) }
    public mutating func skipStep() -> [RunCommand] { run(engine.skipStep()) }
    public mutating func advance() -> [RunCommand] { run(engine.advance()) }

    /// "Skip pre-flight today". Ignored once the run is over, so `.skipped` never replaces `.completed`.
    public mutating func skipAll() -> [RunCommand] { run(engine.skipAll()) }

    /// Steps to draw as done: everything before the resume point plus what ticked this run
    /// (the engine only ticks steps ≥ resumeAt).
    public var displayedTicked: Set<Int> {
        guard let resumeAt, !steps.isEmpty else { return engine.ticked }
        return engine.ticked.union(0..<min(max(resumeAt, 0), steps.count - 1))
    }

    /// The coordinator starts / finishes speaking a line.
    public mutating func lineStarted(_ key: LineKey) { speaking = key }
    public mutating func lineEnded() { speaking = nil }

    /// Whether `commands` (from `handle(_:)`) tick the step whose prompt line is being spoken: the
    /// prompt is cut so the tick and its confirm line follow at once. Greeting, confirm, already and
    /// liftoff lines are never cut.
    public func interruptsSpokenPrompt(_ commands: [RunCommand]) -> Bool {
        guard let speaking, speaking.kind == .prompt, let id = speaking.step else { return false }
        return commands.contains {
            if case .perform(.ticked(let i)) = $0 { steps.indices.contains(i) && steps[i].id == id } else { false }
        }
    }

    /// The step `commands` tick, if any.
    public static func tickedStep(in commands: [RunCommand]) -> Int? {
        for command in commands { if case .perform(.ticked(let i)) = command { return i } }
        return nil
    }

    /// True exactly once: when the current step waits for Apple Music and hasn't ticked yet.
    /// The coordinator then asks Music directly (AppleScript) and feeds a `true` answer back in.
    public mutating func takeMusicQuery() -> Bool {
        guard !musicQueried, !isOver, let i = engine.currentIndex, steps[i].rule == .musicPlaying,
              !engine.ticked.contains(i) else { return false }
        musicQueried = true
        return true
    }

    private mutating func run(_ actions: [EngineAction]) -> [RunCommand] {
        guard !isOver else { return [] }
        var commands = actions.map(RunCommand.perform)
        if actions.contains(.finished) || actions.contains(.dismissed) {
            isOver = true
        } else if actions.contains(where: { if case .ticked = $0 { true } else { false } }) {
            commands.append(.pauseThenAdvance)
        }
        return commands
    }
}

/// What to do on a wake: whether the run on screen must be ended first, and the trigger decision.
public struct WakeDecision: Equatable, Sendable {
    /// The active run belongs to an earlier day: end it silently (no ledger write) before `trigger`.
    public var endActiveRun: Bool
    public var trigger: TriggerDecision

    public init(endActiveRun: Bool, trigger: TriggerDecision) {
        self.endActiveRun = endActiveRun
        self.trigger = trigger
    }
}

/// Turns the 2–3 notifications macOS posts per unlock (wake, screens wake, unlock) into one decision.
public struct WakeGate: Sendable {
    public let minimumInterval: TimeInterval
    private var lastWake: Date?

    public init(minimumInterval: TimeInterval = 2) {
        self.minimumInterval = minimumInterval
    }

    /// `activeRunDay` is the `dayKey` of the run on screen (nil when none). A run left over from an
    /// earlier day is ended ("the next day always starts fresh") and today is judged as if none were
    /// active. A same-day active run, or a wake within `minimumInterval` of the previous one, stays
    /// quiet; otherwise `decideTrigger`.
    ///
    /// `isLocked`: the screen is locked (or the session is not on the console), e.g. the Mac woke to
    /// the lock screen. `learningDevices`: the Learn wizard is open. Either keeps the wake quiet
    /// without counting it towards `minimumInterval`, so the unlock (or the re-check after the
    /// wizard closes) that follows a moment later decides normally.
    public mutating func decide(now: Date, calendar: Calendar, window: TriggerWindow, ledger: DayLedger?,
                                activeRunDay: String?, isLocked: Bool = false, learningDevices: Bool = false) -> WakeDecision {
        let stale = activeRunDay.map { isFromEarlierDay($0, now: now, calendar: calendar) } ?? false
        if isLocked || learningDevices { return WakeDecision(endActiveRun: stale, trigger: .stayQuiet) }
        defer { lastWake = now }
        let runActive = activeRunDay != nil && !stale
        if runActive { return WakeDecision(endActiveRun: false, trigger: .stayQuiet) }
        if let lastWake, now.timeIntervalSince(lastWake) < minimumInterval {
            return WakeDecision(endActiveRun: stale, trigger: .stayQuiet)
        }
        return WakeDecision(endActiveRun: stale,
                            trigger: decideTrigger(now: now, calendar: calendar, window: window, ledger: ledger))
    }
}

let waitingNames: [StepID: String] = [
    .cables: "the monitor", .dock: "the dock", .keyboard: "the Reclusa keyboard", .mouse: "MX Master 4", .dac: "FiiO K7", .agentFactory: "Agent Factory",
    .music: "Apple Music", .teams: "Teams",
]

/// "Waiting for FiiO K7…" under auto-detected steps; nil for the final step and for steps only
/// Done can tick (manual ones, and device steps that can never match — see `needsManualConfirm`).
public func waitingText(for step: StepDefinition, learned: [DeviceSignature]) -> String? {
    guard step.rule != .final, !needsManualConfirm(step, learned: learned) else { return nil }
    return "Waiting for \(waitingNames[step.id] ?? step.title)…"
}

/// Whether a run started on `day` (a `dayKey`) belongs to a day before `now`'s.
public func isFromEarlierDay(_ day: String, now: Date, calendar: Calendar) -> Bool {
    day != dayKey(now, calendar: calendar)
}

/// Runs `operation` and returns its result, or nil if it takes longer than `seconds`. The caller is
/// released at the deadline even when the operation can't be cancelled (e.g. a blocking Keychain read).
public func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async -> T?) async -> T? {
    await withCheckedContinuation { continuation in
        let once = ResumeOnce(continuation)
        let work = Task.detached { once.resume(await operation()) }
        Task.detached {
            try? await Task.sleep(for: .seconds(seconds))
            work.cancel()
            once.resume(nil)
        }
    }
}

/// Resumes a continuation from whichever caller comes first; later calls are ignored.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T?) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}
