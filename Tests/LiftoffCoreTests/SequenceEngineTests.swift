import Testing
@testable import LiftoffCore

/// Index of `id` in the default step order, so tests survive reordering.
func ix(_ id: StepID) -> Int {
    LiftoffConfig.default.steps.firstIndex { $0.id == id }!
}

@Suite struct SequenceEngineTests {
    let k7 = DeviceSignature(kind: .audioOutput, name: "FiiO K7")
    let display = DeviceSignature(kind: .display, name: "LG UltraFine")

    func engine(resumeAt: Int? = nil) -> SequenceEngine {
        SequenceEngine(config: .default, resumeAt: resumeAt)
    }

    @Test func freshStartGreetsThenShowsWater() {
        var e = engine()
        #expect(e.start(SystemSnapshot()) == [
            .startMusic, .play(.chime), .say(LineKey(step: nil, kind: .greeting)),
            .show(stepIndex: 0), .persist(.inProgress(stepIndex: 0)),
            .play(.chime), .say(LineKey(step: .water, kind: .prompt)),
        ])
    }

    @Test func alreadySatisfiedTicksImmediately() {
        var e = engine(resumeAt: ix(.dac) - 1)
        _ = e.start(SystemSnapshot(devices: [k7]))
        let actions = e.advance()
        #expect(actions.contains(.show(stepIndex: ix(.dac))))
        #expect(actions.contains(.ticked(stepIndex: ix(.dac))))
        #expect(actions.contains(.say(LineKey(step: .dac, kind: .already))))
    }

    @Test func eventTicksWaitingStep() {
        var e = engine(resumeAt: ix(.cables))
        _ = e.start(SystemSnapshot())
        let actions = e.handle(.snapshot(SystemSnapshot(devices: [display])))
        #expect(actions == [.ticked(stepIndex: ix(.cables)), .play(.tick), .say(LineKey(step: .cables, kind: .confirm))])
        #expect(e.ticked == [ix(.cables)])
    }

    @Test func manualStepNeedsConfirm() {
        var e = engine(resumeAt: ix(.water))
        _ = e.start(SystemSnapshot())
        #expect(e.handle(.snapshot(SystemSnapshot(devices: [display, k7]))).isEmpty)
        #expect(e.ticked.isEmpty)
        #expect(e.confirmManual() == [.ticked(stepIndex: ix(.water)), .play(.tick), .say(LineKey(step: .water, kind: .confirm))])
        #expect(e.confirmManual().isEmpty)
    }

    @Test func tickedStepNeverUnticks() {
        var e = engine(resumeAt: ix(.cables))
        _ = e.start(SystemSnapshot())
        _ = e.handle(.snapshot(SystemSnapshot(devices: [display])))
        #expect(e.handle(.snapshot(SystemSnapshot())).isEmpty)
        #expect(e.ticked.contains(ix(.cables)))
    }

    @Test func musicHandOffOnce() {
        var e = engine(resumeAt: ix(.music))
        _ = e.start(SystemSnapshot())
        var all = e.handle(.musicStateChanged(playing: true))
        all += e.handle(.musicStateChanged(playing: true))
        all += e.handle(.snapshot(SystemSnapshot(musicPlaying: true)))
        #expect(all.filter { $0 == .handOffMusic }.count == 1)
    }

    @Test func musicAlreadyPlayingAtStartNeverStartsOurs() {
        var e = engine(resumeAt: ix(.music))
        let actions = e.start(SystemSnapshot(musicPlaying: true))
        #expect(!actions.contains(.startMusic))
        #expect(!actions.contains(.handOffMusic))  // nothing of ours to hand off
        #expect(actions.contains(.say(LineKey(step: .music, kind: .already))))
    }

    @Test func resumeStartsAtSavedStep() {
        var e = engine(resumeAt: 4)
        let actions = e.start(SystemSnapshot())
        #expect(actions.prefix(2) == [.startMusic, .say(LineKey(step: nil, kind: .greetingResume))])
        #expect(actions.first { if case .show = $0 { return true } else { return false } } == .show(stepIndex: 4))
        #expect(e.currentIndex == 4)
    }

    @Test func finalStepCompletesDay() {
        var e = engine(resumeAt: ix(.teams))
        _ = e.start(SystemSnapshot())
        _ = e.confirmManual()
        let actions = e.advance()
        #expect(actions == [.show(stepIndex: ix(.liftoff)), .play(.liftoff), .say(LineKey(step: .liftoff, kind: .liftoff)),
                            .persist(.completed), .finished])
        #expect(e.isFinished)
        #expect(e.advance().isEmpty)
    }

    @Test func skipStepTicksWithoutConfirmThenAdvance() {
        var e = engine()
        _ = e.start(SystemSnapshot())
        #expect(e.skipStep() == [.ticked(stepIndex: 0)])
        #expect(e.advance().contains(.show(stepIndex: 1)))
    }

    @Test func skipAllMarksSkipped() {
        var e = engine()
        _ = e.start(SystemSnapshot())
        #expect(e.skipAll() == [.persist(.skipped), .dismissed])
    }

    // MARK: Music hand-off (final review item 5)

    @Test func musicStartingBeforeTheMusicStepHandsOffAtOnce() {
        var e = engine()
        _ = e.start(SystemSnapshot())
        #expect(e.handle(.musicStateChanged(playing: true)) == [.handOffMusic])
        #expect(e.ticked.isEmpty)  // the water step still waits for its own Done
    }

    @Test func handOffHappensAtMostOncePerRun() {
        var e = engine(resumeAt: ix(.headphones))
        var all = e.start(SystemSnapshot())
        all += e.handle(.musicStateChanged(playing: true))
        all += e.handle(.musicStateChanged(playing: true))
        all += e.confirmManual()
        all += e.advance()  // music step: ticks "already" from the log
        all += e.skipStep()
        #expect(all.contains(.say(LineKey(step: .music, kind: .already))))
        #expect(all.filter { $0 == .handOffMusic }.count == 1)
    }

    @Test func skippingTheMusicStepHandsOff() {
        var e = engine(resumeAt: ix(.music))
        _ = e.start(SystemSnapshot())
        #expect(e.skipStep() == [.ticked(stepIndex: ix(.music)), .handOffMusic])
    }

    @Test func doneOnTheMusicStepHandsOff() {
        var e = engine(resumeAt: ix(.music))
        _ = e.start(SystemSnapshot())
        #expect(e.confirmManual().filter { $0 == .handOffMusic }.count == 1)
    }

    @Test func skippingAnotherStepDoesNotHandOff() {
        var e = engine()
        _ = e.start(SystemSnapshot())
        #expect(e.skipStep() == [.ticked(stepIndex: 0)])
    }

    @Test func doneTicksANonManualWaitingStep() {
        var e = engine(resumeAt: ix(.cables))
        _ = e.start(SystemSnapshot())
        #expect(e.confirmManual() == [.ticked(stepIndex: ix(.cables)), .play(.tick), .say(LineKey(step: .cables, kind: .confirm))])
    }

    @Test func resumingAtOrBeforeTheMusicStepStartsMusic() {
        var at = engine(resumeAt: ix(.music))
        #expect(at.start(SystemSnapshot()).first == .startMusic)
        var before = engine(resumeAt: 2)
        #expect(before.start(SystemSnapshot()).first == .startMusic)
    }

    @Test func resumingPastTheMusicStepDoesNotStartMusic() {
        var e = engine(resumeAt: ix(.teams))
        var all = e.start(SystemSnapshot())
        all += e.handle(.musicStateChanged(playing: true))
        all += e.confirmManual()
        all += e.advance()
        #expect(!all.contains(.startMusic))
        #expect(!all.contains(.handOffMusic))
    }
}
