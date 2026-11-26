import Testing
import Foundation
@testable import LiftoffCore

@Suite struct RunSessionTests {
    let display = DeviceSignature(kind: .display, name: "LG UltraFine")
    let k7 = DeviceSignature(kind: .audioOutput, name: "FiiO K7")
    let teams = RunningApp(bundleID: "com.microsoft.teams2", name: "Microsoft Teams")

    func session(resumeAt: Int? = nil) -> RunSession {
        RunSession(config: .default, resumeAt: resumeAt)
    }

    @Test func startPerformsEngineActionsInOrderWithoutAdvancing() {
        var s = session()
        let r1 = s.start(SystemSnapshot())
        #expect(r1 == [
            .perform(.startMusic), .perform(.play(.chime)), .perform(.say(LineKey(step: nil, kind: .greeting))),
            .perform(.show(stepIndex: 0)), .perform(.persist(.inProgress(stepIndex: 0))),
            .perform(.play(.chime)), .perform(.say(LineKey(step: .water, kind: .prompt))),
        ])
    }

    @Test func tickIsFollowedByItsLineThenPauseThenAdvance() {
        var s = session(resumeAt: ix(.cables))
        _ = s.start(SystemSnapshot())
        let r2 = s.handle(.snapshot(SystemSnapshot(devices: [display])))
        #expect(r2 == [
            .perform(.ticked(stepIndex: ix(.cables))), .perform(.play(.tick)),
            .perform(.say(LineKey(step: .cables, kind: .confirm))), .pauseThenAdvance,
        ])
    }

    @Test func alreadySatisfiedStepAdvancesAfterTheAlreadyLine() {
        var s = session(resumeAt: ix(.dac))
        let commands = s.start(SystemSnapshot(devices: [k7]))
        #expect(commands.suffix(4) == [
            .perform(.ticked(stepIndex: ix(.dac))), .perform(.play(.tick)),
            .perform(.say(LineKey(step: .dac, kind: .already))), .pauseThenAdvance,
        ])
    }

    @Test func skipStepTicksAndAdvances() {
        var s = session()
        _ = s.start(SystemSnapshot())
        let r3 = s.skipStep()
        #expect(r3 == [.perform(.ticked(stepIndex: 0)), .pauseThenAdvance])
        let r4 = s.skipStep()
        #expect(r4 == [])  // already ticked; waits for the advance
    }

    @Test func musicHandOffComesBeforeTheAdvance() {
        var s = session(resumeAt: ix(.music))
        _ = s.start(SystemSnapshot())
        let commands = s.handle(.musicStateChanged(playing: true))
        #expect(commands.contains(.perform(.handOffMusic)))
        #expect(commands.last == .pauseThenAdvance)
    }

    @Test func finishedRunDoesNotAdvanceAndIsOver() {
        var s = session(resumeAt: ix(.liftoff))
        let commands = s.start(SystemSnapshot())
        #expect(commands.contains(.perform(.finished)))
        #expect(!commands.contains(.pauseThenAdvance))
        #expect(s.isOver)
    }

    @Test func skipAllAfterFinishIsIgnored() {
        var s = session(resumeAt: ix(.liftoff))
        _ = s.start(SystemSnapshot())
        let r5 = s.skipAll()
        #expect(r5 == [])  // never overwrite .completed with .skipped
    }

    @Test func skipAllPersistsSkippedOnce() {
        var s = session()
        _ = s.start(SystemSnapshot())
        let r6 = s.skipAll()
        #expect(r6 == [.perform(.persist(.skipped)), .perform(.dismissed)])
        #expect(s.isOver)
        let r7 = s.skipAll()
        #expect(r7 == [])
        let r8 = s.advance()
        #expect(r8 == [])
        let r9 = s.confirmManual()
        #expect(r9 == [])
    }

    @Test func resumeShowsEarlierStepsAsDone() {
        var s = session(resumeAt: 3)
        _ = s.start(SystemSnapshot())
        #expect(s.displayedTicked == [0, 1, 2])
        _ = s.skipStep()
        #expect(s.displayedTicked == [0, 1, 2, 3])
        #expect(session().displayedTicked.isEmpty)
    }

    @Test func teamsActivatedEarlierTicksItsStepOnEntry() {
        var s = session(resumeAt: ix(.headphones))
        _ = s.start(SystemSnapshot())
        let r10 = s.handle(.appActivated(teams))
        #expect(r10 == [])  // not the Teams step yet, but logged
        _ = s.skipStep()
        _ = s.advance()
        _ = s.skipStep()
        let commands = s.advance()
        #expect(commands.contains(.perform(.say(LineKey(step: .teams, kind: .already)))))
        #expect(commands.last == .pauseThenAdvance)
    }

    @Test func musicIsQueriedOnceOnlyOnTheMusicStep() {
        var s = session(resumeAt: ix(.headphones))
        _ = s.start(SystemSnapshot())
        let onHeadphones = s.takeMusicQuery()
        #expect(!onHeadphones)
        _ = s.skipStep()
        _ = s.advance()  // music step
        let first = s.takeMusicQuery()
        let second = s.takeMusicQuery()
        #expect(first)
        #expect(!second)
    }

    @Test func musicIsNotQueriedWhenAlreadyPlaying() {
        var s = session(resumeAt: ix(.music))
        _ = s.start(SystemSnapshot(musicPlaying: true))
        let queried = s.takeMusicQuery()
        #expect(!queried)
    }
}

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    return c
}()

private func at(_ h: Int, _ m: Int, _ s: Int = 0, day: Int = 18) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m, second: s))!
}

@Suite struct WakeGateTests {
    let window = TriggerWindow()

    @Test func wakeInWindowStartsAFreshRun() {
        var gate = WakeGate()
        let r12 = gate.decide(now: at(8, 47), calendar: cal, window: window, ledger: nil, activeRunDay: nil)
        #expect(r12 == WakeDecision(endActiveRun: false, trigger: .start(resumeAt: nil)))
    }

    @Test func burstOfWakeNotificationsStartsOnce() {
        var gate = WakeGate()
        let r13 = gate.decide(now: at(8, 47, 0), calendar: cal, window: window, ledger: nil, activeRunDay: nil)
        #expect(r13 == WakeDecision(endActiveRun: false, trigger: .start(resumeAt: nil)))
        let r14 = gate.decide(now: at(8, 47, 1), calendar: cal, window: window, ledger: nil, activeRunDay: nil)
        #expect(r14 == WakeDecision(endActiveRun: false, trigger: .stayQuiet))
        // still within 2 s of the previous (ignored) wake
        let r15 = gate.decide(now: at(8, 47, 2), calendar: cal, window: window, ledger: nil, activeRunDay: nil)
        #expect(r15 == WakeDecision(endActiveRun: false, trigger: .stayQuiet))
    }

    @Test func wakeWhileRunningIsIgnored() {
        var gate = WakeGate()
        let r16 = gate.decide(now: at(8, 47), calendar: cal, window: window, ledger: nil, activeRunDay: "2026-11-18")
        #expect(r16 == WakeDecision(endActiveRun: false, trigger: .stayQuiet))
        let r17 = gate.decide(now: at(8, 50), calendar: cal, window: window, ledger: nil, activeRunDay: "2026-11-18")
        #expect(r17 == WakeDecision(endActiveRun: false, trigger: .stayQuiet))
    }

    @Test func laterWakeResumesTheSavedStep() {
        var gate = WakeGate()
        let ledger = DayLedger(day: "2026-11-18", status: .inProgress(stepIndex: 4))
        let r18 = gate.decide(now: at(9, 0), calendar: cal, window: window, ledger: ledger, activeRunDay: nil)
        #expect(r18 == WakeDecision(endActiveRun: false, trigger: .start(resumeAt: 4)))
    }

    @Test func doneTodayOrOutsideWindowStaysQuiet() {
        var gate = WakeGate()
        let done = DayLedger(day: "2026-11-18", status: .completed)
        let r19 = gate.decide(now: at(9, 0), calendar: cal, window: window, ledger: done, activeRunDay: nil)
        #expect(r19 == WakeDecision(endActiveRun: false, trigger: .stayQuiet))
        let r20 = gate.decide(now: at(10, 31), calendar: cal, window: window, ledger: nil, activeRunDay: nil)
        #expect(r20 == WakeDecision(endActiveRun: false, trigger: .stayQuiet))
        let r21 = gate.decide(now: at(9, 0, day: 21), calendar: cal, window: window, ledger: nil, activeRunDay: nil)
        #expect(r21 == WakeDecision(endActiveRun: false, trigger: .stayQuiet))  // Saturday
    }
}

extension WakeGateTests {
    @Test func wakeWhileLockedStaysQuietAndTheUnlockDecides() {
        var gate = WakeGate()
        let locked = gate.decide(now: at(8, 47, 0), calendar: cal, window: window, ledger: nil, activeRunDay: nil,
                                 isLocked: true)
        #expect(locked == WakeDecision(endActiveRun: false, trigger: .stayQuiet))
        // Touch ID unlock one second later: not swallowed as part of the same burst.
        let unlocked = gate.decide(now: at(8, 47, 1), calendar: cal, window: window, ledger: nil, activeRunDay: nil,
                                   isLocked: false)
        #expect(unlocked == WakeDecision(endActiveRun: false, trigger: .start(resumeAt: nil)))
    }

    @Test func unlockOutsideTheWindowStillStaysQuiet() {
        var gate = WakeGate()
        _ = gate.decide(now: at(10, 40), calendar: cal, window: window, ledger: nil, activeRunDay: nil, isLocked: true)
        let r = gate.decide(now: at(10, 41), calendar: cal, window: window, ledger: nil, activeRunDay: nil, isLocked: false)
        #expect(r == WakeDecision(endActiveRun: false, trigger: .stayQuiet))
    }

    @Test func lockedWakeStillEndsYesterdaysRunSilently() {
        var gate = WakeGate()
        let r = gate.decide(now: at(8, 30), calendar: cal, window: window, ledger: nil, activeRunDay: "2026-11-17",
                            isLocked: true)
        #expect(r == WakeDecision(endActiveRun: true, trigger: .stayQuiet))
    }

    @Test func noRunWhileLearningDevicesThenTheRecheckStarts() {
        var gate = WakeGate()
        let during = gate.decide(now: at(8, 30, 0), calendar: cal, window: window, ledger: nil, activeRunDay: nil,
                                 learningDevices: true)
        #expect(during == WakeDecision(endActiveRun: false, trigger: .stayQuiet))
        let after = gate.decide(now: at(8, 30, 1), calendar: cal, window: window, ledger: nil, activeRunDay: nil,
                                learningDevices: false)
        #expect(after == WakeDecision(endActiveRun: false, trigger: .start(resumeAt: nil)))
    }

    @Test func runFromAnEarlierDayIsDetected() {
        #expect(isFromEarlierDay("2026-11-17", now: at(8, 0), calendar: cal))
        #expect(!isFromEarlierDay("2026-11-18", now: at(23, 59), calendar: cal))
    }

    @Test func previousDayRunIsEndedAndTodayStartsFresh() {
        var gate = WakeGate()
        // Yesterday's run was left waiting at step 2; its ledger says so.
        let ledger = DayLedger(day: "2026-11-17", status: .inProgress(stepIndex: 2))
        let r = gate.decide(now: at(8, 30), calendar: cal, window: window, ledger: ledger, activeRunDay: "2026-11-17")
        #expect(r == WakeDecision(endActiveRun: true, trigger: .start(resumeAt: nil)))
    }

    @Test func previousDayRunIsEndedEvenOutsideTheWindow() {
        var gate = WakeGate()
        let r = gate.decide(now: at(11, 0), calendar: cal, window: window, ledger: nil, activeRunDay: "2026-11-17")
        #expect(r == WakeDecision(endActiveRun: true, trigger: .stayQuiet))
    }

    @Test func sameDayActiveRunStaysQuietAndIsKept() {
        var gate = WakeGate()
        let r = gate.decide(now: at(8, 30), calendar: cal, window: window, ledger: nil, activeRunDay: "2026-11-18")
        #expect(r == WakeDecision(endActiveRun: false, trigger: .stayQuiet))
    }
}

@Suite struct WaitingTextTests {
    let steps = Dictionary(uniqueKeysWithValues: LiftoffConfig.default.steps.map { ($0.id, $0) })

    @Test func autoStepsWaitManualAndFinalDoNot() {
        #expect(waitingText(for: steps[.dac]!, learned: []) == "Waiting for FiiO K7…")
        #expect(waitingText(for: steps[.teams]!, learned: []) == "Waiting for Teams…")
        #expect(waitingText(for: steps[.water]!, learned: []) == nil)
        #expect(waitingText(for: steps[.liftoff]!, learned: []) == nil)
    }

    @Test func aDeviceStepThatCanNeverTickDoesNotWait() {
        #expect(waitingText(for: steps[.dock]!, learned: []) == nil)
        let hub = DeviceSignature(kind: .usb, name: "CalDigit TS4")
        #expect(waitingText(for: steps[.dock]!, learned: [hub]) == "Waiting for the dock…")
    }
}

@Suite struct TimeoutTests {
    @Test func returnsTheResultWhenFastEnough() async {
        #expect(await withTimeout(seconds: 1) { 42 } == 42)
    }

    @Test func givesUpWithoutWaitingForASlowOperation() async {
        let start = Date()
        let result: Int? = await withTimeout(seconds: 0.1) {
            try? await Task.sleep(for: .seconds(2))
            return 1
        }
        #expect(result == nil)
        #expect(Date().timeIntervalSince(start) < 1)
    }
}
