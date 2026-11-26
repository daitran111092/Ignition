import Foundation

public struct LineKey: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case greeting, greetingResume, prompt, confirm, already, liftoff }
    public var step: StepID?
    public var kind: Kind

    public init(step: StepID?, kind: Kind) {
        self.step = step
        self.kind = kind
    }
}

public enum SFX: String, Sendable { case chime, tick, liftoff }

public enum EngineAction: Equatable, Sendable {
    /// Start our background music (once, at run start; never when it would only be handed off).
    case startMusic
    case show(stepIndex: Int)
    case say(LineKey)
    case play(SFX)
    case ticked(stepIndex: Int)
    /// Apple Music is playing (or the music step is done/skipped): fade ours out. At most once per run.
    case handOffMusic
    case persist(DayLedger.Status)
    case finished
    case dismissed
}

/// Pure state machine; the coordinator performs the returned actions and calls `advance()`
/// once the confirm/already line has finished playing.
public struct SequenceEngine: Sendable {
    private let config: LiftoffConfig
    private let resumeAt: Int?
    private var log = EventLog()
    private var snapshot = SystemSnapshot()
    private var musicHandedOff = false

    public private(set) var currentIndex: Int?
    public private(set) var ticked: Set<Int> = []
    public private(set) var isFinished = false

    public init(config: LiftoffConfig, resumeAt: Int?) {
        self.config = config
        self.resumeAt = resumeAt
    }

    public mutating func start(_ s: SystemSnapshot) -> [EngineAction] {
        snapshot = s
        log.record(.snapshot(s))
        guard !config.steps.isEmpty else { return [] }
        let first = resumeAt.map { min(max($0, 0), config.steps.count - 1) } ?? 0
        // Already past the music step, or Apple Music already playing: ours would only be handed off.
        let pastMusicStep = config.steps[..<first].contains { $0.rule == .musicPlaying }
        var actions: [EngineAction] = []
        if pastMusicStep || s.musicPlaying == true {
            musicHandedOff = true
        } else {
            actions.append(.startMusic)
        }
        if resumeAt != nil {
            actions.append(.say(LineKey(step: nil, kind: .greetingResume)))
        } else {
            actions += [.play(.chime), .say(LineKey(step: nil, kind: .greeting))]
        }
        return actions + enter(first)
    }

    public mutating func handle(_ e: SystemEvent) -> [EngineAction] {
        log.record(e)
        if case .snapshot(let s) = e { snapshot = s }
        guard currentIndex != nil, !isFinished else { return [] }
        // Apple Music started playing at any point in the run: ours gives way at once.
        var actions: [EngineAction] = []
        if case .musicStateChanged(playing: true) = e { actions += handOffMusic() }
        guard let i = waitingIndex else { return actions }
        let step = config.steps[i]
        guard isSatisfied(step, learned: config.learned[step.id] ?? [], snapshot: snapshot, log: log) else { return actions }
        return actions + tick(i, line: .confirm)
    }

    /// The user's "Done": ticks the current step whatever its rule.
    public mutating func confirmManual() -> [EngineAction] {
        guard let i = waitingIndex else { return [] }
        return tick(i, line: .confirm)
    }

    public mutating func skipStep() -> [EngineAction] {
        guard let i = waitingIndex else { return [] }
        ticked.insert(i)
        return [.ticked(stepIndex: i)] + (config.steps[i].rule == .musicPlaying ? handOffMusic() : [])
    }

    public mutating func skipAll() -> [EngineAction] {
        currentIndex = nil
        return [.persist(.skipped), .dismissed]
    }

    public mutating func advance() -> [EngineAction] {
        guard let i = currentIndex, !isFinished, i + 1 < config.steps.count else { return [] }
        return enter(i + 1)
    }

    // MARK: - Private

    /// Current step if it is a non-final step that has not yet ticked.
    private var waitingIndex: Int? {
        guard let i = currentIndex, !isFinished, !ticked.contains(i), config.steps[i].rule != .final else { return nil }
        return i
    }

    private mutating func enter(_ i: Int) -> [EngineAction] {
        currentIndex = i
        let step = config.steps[i]
        if step.rule == .final {
            isFinished = true
            ticked.insert(i)
            return [.show(stepIndex: i), .play(.liftoff), .say(LineKey(step: step.id, kind: .liftoff)),
                    .persist(.completed), .finished]
        }
        var actions: [EngineAction] = [.show(stepIndex: i), .persist(.inProgress(stepIndex: i)),
                                       .play(.chime), .say(LineKey(step: step.id, kind: .prompt))]
        if isSatisfied(step, learned: config.learned[step.id] ?? [], snapshot: snapshot, log: log) {
            actions += tick(i, line: .already)
        }
        return actions
    }

    private mutating func tick(_ i: Int, line: LineKey.Kind) -> [EngineAction] {
        ticked.insert(i)
        let step = config.steps[i]
        let actions: [EngineAction] = [.ticked(stepIndex: i), .play(.tick), .say(LineKey(step: step.id, kind: line))]
        return actions + (step.rule == .musicPlaying ? handOffMusic() : [])
    }

    private mutating func handOffMusic() -> [EngineAction] {
        guard !musicHandedOff else { return [] }
        musicHandedOff = true
        return [.handOffMusic]
    }
}
