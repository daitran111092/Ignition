import Testing
@testable import LiftoffCore

@Suite struct RuleEvaluatorTests {
    let steps = Dictionary(uniqueKeysWithValues: LiftoffConfig.default.steps.map { ($0.id, $0) })
    let k7 = DeviceSignature(kind: .audioOutput, name: "FiiO K7")
    let display = DeviceSignature(kind: .display, name: "LG UltraFine")

    func ok(_ id: StepID, learned: [DeviceSignature] = [], _ snap: SystemSnapshot, log: EventLog = EventLog()) -> Bool {
        isSatisfied(steps[id]!, learned: learned, snapshot: snap, log: log)
    }

    @Test func k7ByHint() {
        #expect(ok(.dac, SystemSnapshot(devices: [k7])))
        #expect(!ok(.dac, SystemSnapshot(devices: [display])))
    }

    @Test func learnedDockNeedsAllSignatures() {
        let a = DeviceSignature(kind: .usb, name: "Hub A", vendorID: 1, productID: 2)
        let b = DeviceSignature(kind: .usb, name: "Hub B", vendorID: 3, productID: 4)
        #expect(!ok(.dock, learned: [a, b], SystemSnapshot(devices: [a])))
        #expect(ok(.dock, learned: [a, b], SystemSnapshot(devices: [a, b])))
    }

    @Test func unlearnedDisplayAndUsb() {
        #expect(ok(.cables, SystemSnapshot(devices: [display])))
        #expect(!ok(.cables, SystemSnapshot()))
        #expect(!ok(.dock, SystemSnapshot(devices: [DeviceSignature(kind: .usb, name: "Mouse")])))
    }

    @Test func teamsActivatedInLogCounts() {
        var log = EventLog()
        log.record(.appActivated(RunningApp(bundleID: "com.microsoft.teams2", name: "Microsoft Teams")))
        #expect(ok(.teams, SystemSnapshot(), log: log))
        #expect(!ok(.teams, SystemSnapshot()))
    }

    @Test func agentFactoryByNameWithoutBundleID() {
        let snap = SystemSnapshot(runningApps: [RunningApp(bundleID: nil, name: "Agent Factory")])
        #expect(ok(.agentFactory, snap))
    }

    @Test func musicUnknownIsNotSatisfied() {
        #expect(!ok(.music, SystemSnapshot(musicPlaying: nil)))
        #expect(ok(.music, SystemSnapshot(musicPlaying: true)))
        var log = EventLog()
        log.record(.musicStateChanged(playing: true))
        #expect(ok(.music, SystemSnapshot(musicPlaying: false), log: log))
    }

    @Test func manualAndFinalNeverSatisfied() {
        #expect(!ok(.water, SystemSnapshot()))
        #expect(!ok(.liftoff, SystemSnapshot()))
    }

    @Test func onlyDoneCanTickManualStepsAndDeviceStepsThatCanNeverMatch() {
        let hub = DeviceSignature(kind: .usb, name: "CalDigit TS4")
        #expect(needsManualConfirm(steps[.water]!, learned: []))
        #expect(needsManualConfirm(steps[.dock]!, learned: []))       // USB, no hint, nothing learned
        #expect(!needsManualConfirm(steps[.dock]!, learned: [hub]))
        #expect(!needsManualConfirm(steps[.cables]!, learned: []))    // any display counts
        #expect(!needsManualConfirm(steps[.dac]!, learned: []))       // "FiiO" hint
        #expect(!needsManualConfirm(steps[.music]!, learned: []))
        #expect(!needsManualConfirm(steps[.teams]!, learned: []))
        #expect(!needsManualConfirm(steps[.liftoff]!, learned: []))   // the final card has no Done
        let blankHint = StepDefinition(id: .dac, title: "DAC", instruction: "", rule: .devices(.audioOutput, hint: ""),
                                       gradient: [], symbol: "")
        #expect(needsManualConfirm(blankHint, learned: []))
    }
}
